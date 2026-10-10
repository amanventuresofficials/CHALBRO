// End-to-end check of the real payment functions (functions/index.js) against the
// Firestore EMULATOR, with Razorpay replaced by a stand-in. It proves that:
//  * normal payments still work and write the same data as before, and
//  * every kind of failure the owner should hear about lands in `errorLogs`
//    (and ordinary caller mistakes do not).
//
// Run:  npm run test:e2e      (starts a throw-away emulator with a fake project)
// It refuses to run unless FIRESTORE_EMULATOR_HOST is set, so it can never touch
// the live project.
const assert = require("node:assert/strict");
const crypto = require("crypto");
const path = require("path");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("Refusing to run: FIRESTORE_EMULATOR_HOST is not set (this would touch a real project).");
  process.exit(2);
}
process.env.GCLOUD_PROJECT = "demo-chalbro";
process.env.RAZORPAY_KEY_ID = "rzp_test_standin";
process.env.RAZORPAY_KEY_SECRET = "standin_secret_for_tests";

// ─── A stand-in for Razorpay ────────────────────────────────────────────────
const rz = { seq: 0, orders: {}, payments: {}, failCreate: null, failFetch: null };
class FakeRazorpay {
  constructor() {
    this.orders = {
      create: async (body) => {
        if (rz.failCreate) throw rz.failCreate;
        const id = `order_E2E${String(++rz.seq).padStart(6, "0")}`;
        rz.orders[id] = { id, amount: body.amount, currency: body.currency, notes: body.notes };
        return rz.orders[id];
      },
      fetch: async (id) => rz.orders[id],
    };
    this.payments = {
      fetch: async (id) => {
        if (rz.failFetch) throw rz.failFetch;
        return rz.payments[id];
      },
      capture: async (id) => {
        rz.payments[id].status = "captured";
        return rz.payments[id];
      },
    };
  }
}

const functionsDir = path.resolve(__dirname, "..");
const razorpayPath = require.resolve("razorpay", { paths: [functionsDir] });
require.cache[razorpayPath] = { id: razorpayPath, filename: razorpayPath, loaded: true, exports: FakeRazorpay, children: [], paths: [] };

const fns = require(path.join(functionsDir, "index.js"));
const admin = require(require.resolve("firebase-admin", { paths: [functionsDir] }));
const db = admin.firestore();

// ─── Helpers ────────────────────────────────────────────────────────────────
let passed = 0;
let failed = 0;
async function check(name, fn) {
  try {
    await fn();
    passed++;
    console.log(`  ok   ${name}`);
  } catch (e) {
    failed++;
    console.log(`  FAIL ${name}\n       ${e && e.message ? e.message : JSON.stringify(e)}`);
  }
}

const POSTER = "e2e_poster";
const WORKER = "e2e_worker";
const sign = (orderId, paymentId) =>
  crypto.createHmac("sha256", process.env.RAZORPAY_KEY_SECRET).update(`${orderId}|${paymentId}`).digest("hex");

async function rejects(fn) {
  try {
    await fn();
  } catch (e) {
    return e;
  }
  throw new Error("expected the call to fail, but it succeeded");
}

async function seedTask(id, extra = {}) {
  await db.collection("tasks").doc(id).set({
    postedByUid: POSTER,
    acceptedByUid: WORKER,
    status: "assigned",
    category: "Cleaning",
    price: 300,
    bids: { [WORKER]: 300 },
    ...extra,
  });
}

async function logs() {
  const snap = await db.collection("errorLogs").get();
  return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
}
async function clearLogs() {
  const snap = await db.collection("errorLogs").get();
  await Promise.all(snap.docs.map((d) => d.ref.delete()));
}

const asPoster = { auth: { uid: POSTER } };
const create = (taskId, ctx = asPoster) => fns.createRazorpayOrder.run({ taskId }, ctx);
const verify = (data, ctx = asPoster) => fns.verifyRazorpayPayment.run(data, ctx);

function paidPayment(orderId, paymentId, status = "captured") {
  const order = rz.orders[orderId];
  rz.payments[paymentId] = { id: paymentId, order_id: orderId, status, amount: order.amount, currency: "INR" };
  return { razorpayOrderId: orderId, razorpayPaymentId: paymentId, razorpaySignature: sign(orderId, paymentId) };
}

// ─── Scenarios ──────────────────────────────────────────────────────────────
async function main() {
  await db.collection("users").doc(WORKER).set({ walletBalance: 500, realBalance: 0, ratingSum: 0, ratingCount: 0, tasksDone: 0 });
  await db.collection("users").doc(POSTER).set({ walletBalance: 500 });

  console.log("Normal payments (must keep working, must not log anything)");

  await check("createRazorpayOrder charges the agreed price and logs nothing", async () => {
    await clearLogs();
    await seedTask("t_happy");
    const r = await create("t_happy");
    assert.equal(r.amount, 30000);
    assert.equal(r.discountAmount, 0);
    assert.match(r.orderId, /^order_E2E/);
    assert.equal((await logs()).length, 0);
  });

  await check("verifyRazorpayPayment completes the task and pays the helper 90%", async () => {
    const orderId = Object.keys(rz.orders)[0];
    const body = { taskId: "t_happy", givenRating: 4, ...paidPayment(orderId, "pay_E2E000001") };
    const r = await verify(body);
    assert.deepEqual(r, { success: true });
    const task = (await db.collection("tasks").doc("t_happy").get()).data();
    assert.equal(task.status, "completed");
    assert.equal(task.finalPricePaid, 300);
    assert.equal(task.amountPaidByPoster, 300);
    assert.equal(task.paidViaRazorpay, true);
    assert.equal(task.workerRating, 4);
    const worker = (await db.collection("users").doc(WORKER).get()).data();
    assert.equal(worker.realBalance, 270, "real money goes to the REAL balance");
    assert.equal(worker.walletBalance, 500, "the practice wallet is untouched by a Razorpay payment");
    assert.equal(worker.tasksDone, 1);
    const txs = (await db.collection("users").doc(WORKER).collection("transactions").get()).docs.map((d) => d.data());
    assert.ok(txs.length === 1 && txs[0].real === true && txs[0].type === "credit", "the credit is tagged as real money");
    // The owner's revenue = paid - helper earnings = 30
    assert.equal(task.amountPaidByPoster - 270, 30);
    assert.equal((await logs()).length, 0);
  });

  await check("calling verify again does not pay the helper twice and logs nothing", async () => {
    const orderId = Object.keys(rz.orders)[0];
    const r = await verify({ taskId: "t_happy", givenRating: 4, razorpayOrderId: orderId, razorpayPaymentId: "pay_E2E000001", razorpaySignature: sign(orderId, "pay_E2E000001") });
    assert.deepEqual(r, { success: true, alreadyCompleted: true });
    assert.equal((await db.collection("users").doc(WORKER).get()).data().realBalance, 270);
    assert.equal((await logs()).length, 0);
  });

  await check("with a 10% discount the poster pays 270, the helper still earns 270", async () => {
    await db.collection("metadata").doc("paymentConfig").set({ discountEnabled: true, discountPercent: 10 });
    await seedTask("t_discount");
    const r = await create("t_discount");
    assert.equal(r.amount, 27000);
    assert.equal(r.discountAmount, 30);
    await verify({ taskId: "t_discount", givenRating: 5, ...paidPayment(r.orderId, "pay_E2E000002") });
    const task = (await db.collection("tasks").doc("t_discount").get()).data();
    assert.equal(task.finalPricePaid, 300);
    assert.equal(task.amountPaidByPoster, 270);
    assert.equal(task.discountAmount, 30);
    assert.equal(task.amountPaidByPoster - 270, 0); // fee 30 - discount 30
    await db.collection("metadata").doc("paymentConfig").delete();
    assert.equal((await logs()).length, 0);
  });

  console.log("Ordinary mistakes are not errors");

  await check("paying for an already-paid task is refused quietly", async () => {
    const e = await rejects(() => create("t_happy"));
    assert.equal(e.code, "failed-precondition");
    assert.equal((await logs()).length, 0);
  });

  await check("not signed in / missing fields / unknown task are refused quietly", async () => {
    assert.equal((await rejects(() => create("t_happy", {}))).code, "unauthenticated");
    assert.equal((await rejects(() => verify({ taskId: "t_happy" }))).code, "invalid-argument");
    assert.equal((await rejects(() => create("no_such_task"))).code, "not-found");
    assert.equal((await logs()).length, 0);
  });

  console.log("Real problems are recorded for the admin panel");

  await check("someone else trying to pay for a task is recorded (payment / error)", async () => {
    await seedTask("t_intruder");
    const e = await rejects(() => create("t_intruder", { auth: { uid: "e2e_intruder" } }));
    assert.equal(e.code, "permission-denied");
    const l = await logs();
    assert.equal(l.length, 1);
    assert.equal(l[0].category, "payment");
    assert.equal(l[0].severity, "error");
    assert.equal(l[0].source, "function");
    assert.equal(l[0].status, "open");
    assert.equal(l[0].uid, "e2e_intruder");
    assert.equal(l[0].taskId, "t_intruder");
    assert.equal(l[0].context, "Function: createRazorpayOrder");
    assert.ok(l[0].createdAt && typeof l[0].createdAt.toDate === "function", "server timestamp");
    await clearLogs();
  });

  await check("Razorpay being down while creating an order is recorded and the original error is re-thrown", async () => {
    await seedTask("t_rzdown");
    rz.failCreate = { statusCode: 500, error: { code: "SERVER_ERROR", description: "Razorpay is down" } };
    const e = await rejects(() => create("t_rzdown"));
    rz.failCreate = null;
    assert.equal(e.error.description, "Razorpay is down"); // unchanged
    const l = await logs();
    assert.equal(l.length, 1);
    assert.equal(l[0].errorType, "razorpay/SERVER_ERROR");
    assert.equal(l[0].message, "Razorpay is down");
    assert.equal(l[0].severity, "error");
    await clearLogs();
  });

  await check("a wrong payment signature is recorded, without the signature itself", async () => {
    await seedTask("t_badsig");
    const { orderId } = await create("t_badsig");
    const body = { taskId: "t_badsig", ...paidPayment(orderId, "pay_E2E000003"), razorpaySignature: "deadbeef_forged_signature" };
    const e = await rejects(() => verify(body));
    assert.equal(e.code, "permission-denied");
    const l = await logs();
    assert.equal(l.length, 1);
    assert.equal(l[0].severity, "error");
    assert.equal(l[0].message, "Payment signature verification failed.");
    assert.deepEqual(l[0].extra, { razorpayOrderId: orderId, razorpayPaymentId: "pay_E2E000003" });
    assert.ok(!JSON.stringify(l[0]).includes("deadbeef_forged_signature"));
    // the task must be untouched
    assert.equal((await db.collection("tasks").doc("t_badsig").get()).data().status, "assigned");
  });

  await check("the same failure repeated straight away is not written again (no flooding)", async () => {
    const before = (await logs()).length;
    const body = { taskId: "t_badsig", razorpayOrderId: "order_E2E000003", razorpayPaymentId: "pay_E2E000003", razorpaySignature: "another_forged_one" };
    for (let i = 0; i < 5; i++) await rejects(() => verify(body));
    assert.equal((await logs()).length, before);
    await clearLogs();
  });

  await check("Razorpay failing while verifying (money may have moved) is recorded as FATAL", async () => {
    await seedTask("t_fatal");
    const { orderId } = await create("t_fatal");
    const body = { taskId: "t_fatal", ...paidPayment(orderId, "pay_E2E000004") };
    rz.failFetch = { statusCode: 500, error: { code: "SERVER_ERROR", description: "Razorpay lookup failed" } };
    await rejects(() => verify(body));
    rz.failFetch = null;
    const l = await logs();
    assert.equal(l.length, 1);
    assert.equal(l[0].severity, "fatal");
    assert.equal(l[0].category, "payment");
    assert.equal(l[0].context, "Function: verifyRazorpayPayment");
    assert.equal(l[0].taskId, "t_fatal");
    assert.deepEqual(l[0].extra, { razorpayOrderId: orderId, razorpayPaymentId: "pay_E2E000004" });
    await clearLogs();
  });

  await check("a payment that was not captured is recorded as a warning", async () => {
    await seedTask("t_notpaid");
    const { orderId } = await create("t_notpaid");
    const body = { taskId: "t_notpaid", ...paidPayment(orderId, "pay_E2E000005", "created") };
    const e = await rejects(() => verify(body));
    assert.equal(e.code, "failed-precondition");
    const l = await logs();
    assert.equal(l.length, 1);
    assert.equal(l[0].severity, "warning");
    assert.equal((await db.collection("tasks").doc("t_notpaid").get()).data().status, "assigned");
    await clearLogs();
  });

  await check("a payment made for a different task is recorded and refused", async () => {
    await seedTask("t_mix_a");
    await seedTask("t_mix_b");
    const { orderId } = await create("t_mix_a");
    const body = { taskId: "t_mix_b", ...paidPayment(orderId, "pay_E2E000006") };
    const e = await rejects(() => verify(body));
    assert.equal(e.code, "permission-denied");
    const l = await logs();
    assert.equal(l.length, 1);
    assert.match(l[0].message, /different task/);
    assert.equal((await db.collection("tasks").doc("t_mix_b").get()).data().status, "assigned");
    await clearLogs();
  });

  await check("a logging failure never changes what the caller gets", async () => {
    // Make the errorLogs write blow up and confirm the ORIGINAL error still comes out.
    await seedTask("t_logfail", { price: 0, bids: {} }); // -> "Task has no valid price." (a recorded problem)
    const realCollection = db.collection.bind(db);
    let tried = false;
    db.collection = (name) => {
      if (name === "errorLogs") {
        tried = true;
        throw new Error("errorLogs unavailable");
      }
      return realCollection(name);
    };
    try {
      const e = await rejects(() => create("t_logfail"));
      assert.equal(e.code, "failed-precondition");
      assert.equal(e.message, "Task has no valid price.");
      assert.ok(tried, "the failure should have been sent to errorLogs");
    } finally {
      db.collection = realCollection;
    }
    assert.equal((await logs()).length, 0);
  });

  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
