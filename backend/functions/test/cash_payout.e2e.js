// End-to-end check (Firestore EMULATOR, Razorpay and RazorpayX replaced by stand-ins) of:
//  * cash jobs: the poster claims, the helper confirms, a fee is owed;
//  * the owed fee being taken from the helper's next online payments until it is settled;
//  * paying a helper straight to their linked UPI id, and what the webhook does afterwards.
//
// Run:  npm run test:e2e     (it refuses to run unless FIRESTORE_EMULATOR_HOST is set)
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
process.env.RAZORPAYX_ACCOUNT_NUMBER = "2323230000000001";
process.env.RAZORPAYX_WEBHOOK_SECRET = "whsec_standin";

// ─── Stand-in for Razorpay checkout ─────────────────────────────────────────
const rz = { seq: 0, orders: {}, payments: {} };
class FakeRazorpay {
  constructor() {
    this.orders = {
      create: async (body) => {
        const id = `order_CP${String(++rz.seq).padStart(6, "0")}`;
        rz.orders[id] = { id, amount: body.amount, currency: body.currency, notes: body.notes };
        return rz.orders[id];
      },
      fetch: async (id) => rz.orders[id],
    };
    this.payments = {
      fetch: async (id) => rz.payments[id],
      capture: async (id) => rz.payments[id],
    };
  }
}
const functionsDir = path.resolve(__dirname, "..");
const razorpayPath = require.resolve("razorpay", { paths: [functionsDir] });
require.cache[razorpayPath] = { id: razorpayPath, filename: razorpayPath, loaded: true, exports: FakeRazorpay, children: [], paths: [] };

// ─── Stand-in for RazorpayX ─────────────────────────────────────────────────
const rzx = { calls: [], payoutStatus: "processing", failWith: null, networkDown: false, n: 0 };
globalThis.fetch = async (url, init) => {
  const p = url.replace("https://api.razorpay.com/v1", "");
  const body = JSON.parse(init.body);
  rzx.calls.push({ path: p, body, headers: init.headers });
  if (rzx.networkDown) throw new Error("getaddrinfo ENOTFOUND api.razorpay.com");
  const reply = (status, json) => ({ ok: status < 300, status, text: async () => JSON.stringify(json) });
  if (rzx.failWith && p === "/payouts") return reply(rzx.failWith.status, { error: rzx.failWith.error });
  if (p === "/contacts") return reply(200, { id: `cont_${++rzx.n}` });
  if (p === "/fund_accounts") return reply(200, { id: `fa_${++rzx.n}` });
  if (p === "/payouts") return reply(200, { id: `pout_${++rzx.n}`, status: rzx.payoutStatus, utr: rzx.payoutStatus === "processed" ? "UTR123" : "" });
  return reply(404, { error: { code: "NOT_FOUND", description: p } });
};

const fns = require(path.join(functionsDir, "index.js"));
const admin = require(require.resolve("firebase-admin", { paths: [functionsDir] }));
const db = admin.firestore();

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
async function rejects(fn) {
  try {
    await fn();
  } catch (e) {
    return e;
  }
  throw new Error("expected the call to fail, but it succeeded");
}

const POSTER = "cp_poster";
const WORKER = "cp_worker";
const asPoster = { auth: { uid: POSTER } };
const asWorker = { auth: { uid: WORKER } };
const sign = (orderId, paymentId) =>
  crypto.createHmac("sha256", process.env.RAZORPAY_KEY_SECRET).update(`${orderId}|${paymentId}`).digest("hex");

const getDoc = async (p) => (await db.doc(p).get()).data();
const user = () => getDoc(`users/${WORKER}`);
async function seedTask(id, extra = {}) {
  await db.collection("tasks").doc(id).set({
    postedByUid: POSTER, acceptedByUid: WORKER, status: "assigned", category: "Cleaning", title: `Job ${id}`,
    price: 300, bids: { [WORKER]: 300 }, ...extra,
  });
}
async function resetWorker(extra = {}) {
  await db.doc(`users/${WORKER}`).set({ fullName: "Meera Patel", ratingSum: 0, ratingCount: 0, tasksDone: 0, ...extra });
  for (const c of ["transactions", "notifications"]) {
    const s = await db.collection(`users/${WORKER}/${c}`).get();
    await Promise.all(s.docs.map((d) => d.ref.delete()));
  }
}
async function setConfig(cfg) {
  await db.doc("metadata/paymentConfig").set(cfg);
}
async function payOnline(taskId, paymentId) {
  const order = await fns.createRazorpayOrder.run({ taskId }, asPoster);
  const o = rz.orders[order.orderId];
  rz.payments[paymentId] = { id: paymentId, order_id: order.orderId, status: "captured", amount: o.amount, currency: "INR" };
  return fns.verifyRazorpayPayment.run({
    taskId, givenRating: 5, razorpayOrderId: order.orderId, razorpayPaymentId: paymentId, razorpaySignature: sign(order.orderId, paymentId),
  }, asPoster);
}
async function col(p) {
  return (await db.collection(p).get()).docs.map((d) => ({ id: d.id, ...d.data() }));
}
async function runTrigger(withdrawalId) {
  const snap = await db.doc(`withdrawals/${withdrawalId}`).get();
  await fns.autoPayWithdrawal.run(snap, { params: { withdrawalId } });
}
function webhook(body, { secret = process.env.RAZORPAYX_WEBHOOK_SECRET, method = "POST" } = {}) {
  const raw = Buffer.from(JSON.stringify(body));
  const req = { method, rawBody: raw, body, get: (h) => (h.toLowerCase() === "x-razorpay-signature" ? crypto.createHmac("sha256", secret).update(raw).digest("hex") : "") };
  const res = { code: 0, sent: "", status(c) { this.code = c; return this; }, send(t) { this.sent = t; return this; } };
  return fns.razorpayXWebhook(req, res).then(() => res);
}
const payoutEvent = (event, reference, status, extra = {}) => ({ event, payload: { payout: { entity: { id: "pout_wh", reference_id: reference, status, utr: status === "processed" ? "UTRWH" : "", ...extra } } } });

async function main() {
  await db.doc(`users/${POSTER}`).set({ fullName: "Poster" });

  console.log("Cash jobs: claim and confirm");
  await check("the poster claims a cash payment: the task keeps waiting and the helper is told", async () => {
    await resetWorker();
    await setConfig({ useRazorpay: true });
    await seedTask("c1");
    const r = await fns.claimCashPayment.run({ taskId: "c1", givenRating: 4 }, asPoster);
    assert.equal(r.success, true);
    assert.equal(r.fee, 30);
    const t = await getDoc("tasks/c1");
    assert.equal(t.status, "assigned");
    assert.ok(t.cashClaimedAt);
    assert.equal(t.cashClaimRating, 4);
    const notes = await col(`users/${WORKER}/notifications`);
    assert.equal(notes.length, 1);
    assert.equal(notes[0].type, "cash_claim");
    assert.match(notes[0].message, /₹300/);
    assert.match(notes[0].message, /₹30/);
    assert.equal((await user()).feeDue, undefined, "no fee is owed until the helper confirms");
  });

  await check("only the poster can claim; only while payments are on; not twice for a finished task", async () => {
    await seedTask("c2");
    assert.equal((await rejects(() => fns.claimCashPayment.run({ taskId: "c2" }, { auth: { uid: "cp_intruder" } }))).code, "permission-denied");
    assert.equal((await rejects(() => fns.claimCashPayment.run({ taskId: "c2" }, {}))).code, "unauthenticated");
    await setConfig({ useRazorpay: false });
    assert.equal((await rejects(() => fns.claimCashPayment.run({ taskId: "c2" }, asPoster))).code, "failed-precondition");
    await setConfig({ useRazorpay: true });
    await seedTask("c2done", { status: "completed" });
    assert.equal((await rejects(() => fns.claimCashPayment.run({ taskId: "c2done" }, asPoster))).code, "failed-precondition");
    assert.equal((await db.collection("errorLogs").where("context", "==", "Function: claimCashPayment").get()).docs.filter((d) => d.data().severity !== "error").length, 0);
  });

  await check("the helper cannot be given a fee without answering: only the hired helper can answer, and only after a claim", async () => {
    await seedTask("c3");
    assert.equal((await rejects(() => fns.answerCashPayment.run({ taskId: "c3", received: true }, asWorker))).code, "failed-precondition");
    await fns.claimCashPayment.run({ taskId: "c3", givenRating: 5 }, asPoster);
    assert.equal((await rejects(() => fns.answerCashPayment.run({ taskId: "c3", received: true }, asPoster))).code, "permission-denied");
    assert.equal((await rejects(() => fns.answerCashPayment.run({ taskId: "c3" }, asWorker))).code, "invalid-argument");
  });

  await check("the helper says 'not received': the claim is cleared, nothing is owed, the poster is told", async () => {
    await resetWorker();
    await seedTask("c4");
    await fns.claimCashPayment.run({ taskId: "c4", givenRating: 5 }, asPoster);
    const r = await fns.answerCashPayment.run({ taskId: "c4", received: false }, asWorker);
    assert.equal(r.confirmed, false);
    const t = await getDoc("tasks/c4");
    assert.equal(t.status, "assigned");
    assert.equal(t.cashClaimedAt, undefined);
    assert.equal((await user()).feeDue, undefined);
    const notes = await col(`users/${POSTER}/notifications`);
    assert.ok(notes.some((n) => n.type === "cash_denied"));
  });

  await check("the helper confirms: task completed as a cash job, fee owed, rating and review recorded", async () => {
    await resetWorker();
    await seedTask("c5", { title: "Paint wall", price: 450, bids: { [WORKER]: 450 } });
    await fns.claimCashPayment.run({ taskId: "c5", givenRating: 4 }, asPoster);
    const r = await fns.answerCashPayment.run({ taskId: "c5", received: true }, asWorker);
    assert.deepEqual(r, { success: true, confirmed: true, fee: 45 });
    const t = await getDoc("tasks/c5");
    assert.equal(t.status, "completed");
    assert.equal(t.paidInCash, true);
    assert.equal(t.cashAmount, 450);
    assert.equal(t.cashFee, 45);
    assert.equal(t.workerRating, 4);
    assert.equal(t.finalPricePaid, undefined, "a cash job is not an online payment");
    assert.equal(t.cashClaimedAt, undefined);
    const u = await user();
    assert.equal(u.feeDue, 45);
    assert.equal(u.tasksDone, 1);
    assert.equal(u.ratingCount, 1);
    assert.equal(u.ratingSum, 4);
    assert.equal(u.earnings, undefined, "cash never touches earnings");
    assert.equal((await getDoc("reviews/c5")).rating, 4);
    assert.equal((await col(`users/${WORKER}/transactions`)).length, 0);
    const again = await fns.answerCashPayment.run({ taskId: "c5", received: true }, asWorker);
    assert.equal(again.alreadyCompleted, true);
    assert.equal((await user()).feeDue, 45, "answering twice does not charge twice");
  });

  console.log("Owed fees are taken from the next online payments");
  await check("an online payment settles a small fee at once: helper gets 90% minus the fee", async () => {
    await resetWorker({ feeDue: 30 });
    await setConfig({ useRazorpay: true });
    await seedTask("f1");
    await payOnline("f1", "pay_CP_f1");
    const u = await user();
    assert.equal(u.earnings, 240);
    assert.equal(u.feeDue, 0);
    const t = await getDoc("tasks/f1");
    assert.equal(t.feeRecovered, 30);
    assert.equal(t.amountPaidByPoster, 300);
    const tx = await col(`users/${WORKER}/transactions`);
    assert.equal(tx.length, 2);
    assert.ok(tx.some((x) => x.type === "credit" && x.amount === 270 && x.razorpay === true));
    assert.ok(tx.some((x) => x.type === "debit" && x.amount === 30 && /fee/i.test(x.title) && x.razorpay === true));
    const notes = await col(`users/${WORKER}/notifications`);
    assert.match(notes[0].message, /₹270/);
    assert.match(notes[0].message, /₹30/);
  });

  await check("a big fee carries over several payments until it is settled", async () => {
    await resetWorker({ feeDue: 500 });
    await seedTask("f2");
    await seedTask("f3");
    await seedTask("f4");
    await payOnline("f2", "pay_CP_f2");
    let u = await user();
    assert.equal(u.feeDue, 230);
    assert.equal(u.earnings, 0);
    await payOnline("f3", "pay_CP_f3");
    u = await user();
    assert.equal(u.feeDue, 0);
    assert.equal(u.earnings, 40);
    await payOnline("f4", "pay_CP_f4");
    u = await user();
    assert.equal(u.feeDue, 0);
    assert.equal(u.earnings, 310, "after the fee is cleared the helper gets the full 90% again");
    assert.equal((await getDoc("tasks/f4")).feeRecovered, undefined);
  });

  console.log("Paying straight to a linked UPI id");
  await check("switched off: a linked UPI id changes nothing, earnings just accumulate", async () => {
    await resetWorker({ upiId: "meera@okhdfc" });
    await setConfig({ useRazorpay: true });
    await seedTask("p0");
    await payOnline("p0", "pay_CP_p0");
    assert.equal((await user()).earnings, 270);
    assert.equal((await col("withdrawals")).filter((w) => w.taskId === "p0").length, 0);
  });

  await check("switched on with a linked UPI id: the balance is moved into a held payout", async () => {
    await resetWorker({ upiId: "meera@okhdfc" });
    await setConfig({ useRazorpay: true, autoPayout: true });
    await seedTask("p1");
    await payOnline("p1", "pay_CP_p1");
    const u = await user();
    assert.equal(u.earnings, 0);
    const w = (await col("withdrawals")).filter((x) => x.taskId === "p1");
    assert.equal(w.length, 1);
    assert.equal(w[0].amount, 270);
    assert.equal(w[0].paymentDetails, "meera@okhdfc");
    assert.equal(w[0].status, "pending");
    assert.equal(w[0].auto, true);
    assert.equal(w[0].uid, WORKER);
    const tx = await col(`users/${WORKER}/transactions`);
    assert.ok(tx.some((x) => x.type === "debit" && x.amount === 270 && x.withdrawalId === w[0].id));
  });

  await check("no linked UPI id, or less than the minimum: nothing is sent, earnings stay", async () => {
    await resetWorker();
    await seedTask("p2");
    await payOnline("p2", "pay_CP_p2");
    assert.equal((await user()).earnings, 270);
    await resetWorker({ upiId: "meera@okhdfc", feeDue: 200 });
    await seedTask("p3");
    await payOnline("p3", "pay_CP_p3");
    const u = await user();
    assert.equal(u.earnings, 70);
    assert.equal((await col("withdrawals")).filter((x) => x.taskId === "p3").length, 0);
  });

  await check("a bad UPI id on file is never used", async () => {
    await resetWorker({ upiId: "not a upi id" });
    await seedTask("p4");
    await payOnline("p4", "pay_CP_p4");
    assert.equal((await user()).earnings, 270);
    assert.equal((await col("withdrawals")).filter((x) => x.taskId === "p4").length, 0);
  });

  console.log("The payout trigger and the webhook");
  const makeWithdrawal = async (id, extra = {}) => {
    await resetWorker({ earnings: 0 });
    await db.doc(`withdrawals/${id}`).set({
      uid: WORKER, userName: "Meera Patel", amount: 270, paymentDetails: "meera@okhdfc", status: "pending", auto: true,
      timestamp: admin.firestore.FieldValue.serverTimestamp(), ...extra,
    });
  };

  await check("switched off: the trigger leaves a withdrawal for a person", async () => {
    await setConfig({ useRazorpay: true, autoPayout: false });
    await makeWithdrawal("w_off");
    rzx.calls.length = 0;
    await runTrigger("w_off");
    assert.equal((await getDoc("withdrawals/w_off")).status, "pending");
    assert.equal(rzx.calls.length, 0);
  });

  await check("switched on: it is sent (UPI, paise, idempotency key) and waits for the webhook", async () => {
    await setConfig({ useRazorpay: true, autoPayout: true });
    await makeWithdrawal("w_on");
    rzx.calls.length = 0;
    rzx.payoutStatus = "processing";
    await runTrigger("w_on");
    const w = await getDoc("withdrawals/w_on");
    assert.equal(w.status, "processing");
    assert.match(w.payoutId, /^pout_/);
    const payout = rzx.calls.find((c) => c.path === "/payouts");
    assert.equal(payout.body.amount, 27000);
    assert.equal(payout.body.mode, "UPI");
    assert.equal(payout.body.reference_id, "w_on");
    assert.equal(payout.headers["X-Payout-Idempotency"], "w_on");
    const stored = await getDoc(`payoutAccounts/${WORKER}`);
    assert.ok(stored.contactId && stored.accounts);
  });

  await check("the webhook says processed: approved with the bank reference, helper told; repeated is harmless", async () => {
    const res = await webhook(payoutEvent("payout.processed", "w_on", "processed"));
    assert.equal(res.code, 200);
    const w = await getDoc("withdrawals/w_on");
    assert.equal(w.status, "approved");
    assert.equal(w.paidReference, "UTRWH");
    assert.equal((await user()).earnings, 0);
    const notes = (await col(`users/${WORKER}/notifications`)).filter((n) => n.type === "withdrawal");
    assert.equal(notes.length, 1);
    await webhook(payoutEvent("payout.processed", "w_on", "processed"));
    assert.equal((await col(`users/${WORKER}/notifications`)).filter((n) => n.type === "withdrawal").length, 1);
  });

  await check("the bank later REVERSES an auto payout: it is rejected and the money returns exactly once", async () => {
    const before = (await user()).earnings || 0;
    await webhook(payoutEvent("payout.reversed", "w_on", "reversed", { status_details: { description: "Beneficiary bank returned it" } }));
    assert.equal((await getDoc("withdrawals/w_on")).status, "rejected");
    assert.equal((await user()).earnings, before + 270);
    await webhook(payoutEvent("payout.reversed", "w_on", "reversed"));
    assert.equal((await user()).earnings, before + 270, "a repeated event must not refund twice");
    const tx = await col(`users/${WORKER}/transactions`);
    assert.equal(tx.filter((t) => t.type === "credit" && /returned/i.test(t.title)).length, 1);
  });

  await check("RazorpayX says the payout failed: rejected and refunded", async () => {
    await makeWithdrawal("w_fail");
    await db.doc("withdrawals/w_fail").update({ status: "processing" });
    await webhook(payoutEvent("payout.failed", "w_fail", "failed"));
    assert.equal((await getDoc("withdrawals/w_fail")).status, "rejected");
    assert.equal((await user()).earnings, 270);
  });

  await check("a webhook with a wrong signature, the wrong method, or an unknown payout does nothing", async () => {
    await makeWithdrawal("w_sig");
    await db.doc("withdrawals/w_sig").update({ status: "processing" });
    const bad = await webhook(payoutEvent("payout.failed", "w_sig", "failed"), { secret: "not_the_secret" });
    assert.equal(bad.code, 400);
    assert.equal((await getDoc("withdrawals/w_sig")).status, "processing");
    assert.equal((await webhook({}, { method: "GET" })).code, 405);
    const unknown = await webhook(payoutEvent("payout.processed", "no_such_withdrawal", "processed"));
    assert.equal(unknown.code, 200);
    const ignored = await webhook(payoutEvent("payout.processing", "w_sig", "processing"));
    assert.equal(ignored.code, 200);
    assert.equal((await getDoc("withdrawals/w_sig")).status, "processing");
  });

  await check("RazorpayX answers 'processed' straight away: approved at once", async () => {
    await makeWithdrawal("w_now");
    rzx.payoutStatus = "processed";
    await runTrigger("w_now");
    rzx.payoutStatus = "processing";
    const w = await getDoc("withdrawals/w_now");
    assert.equal(w.status, "approved");
    assert.equal(w.paidReference, "UTR123");
  });

  await check("RazorpayX refuses the request: nothing was sent, it goes back to a person with the reason", async () => {
    await makeWithdrawal("w_err");
    rzx.failWith = { status: 400, error: { code: "BAD_REQUEST_ERROR", description: "Insufficient balance in the account." } };
    await runTrigger("w_err");
    rzx.failWith = null;
    const w = await getDoc("withdrawals/w_err");
    assert.equal(w.status, "pending");
    assert.match(w.autoError, /Insufficient balance/);
    assert.equal((await user()).earnings, 0, "the money stays held, it is not refunded or lost");
    const logs = await col("errorLogs");
    assert.ok(logs.some((l) => l.context === "Function: autoPayWithdrawal"));
  });

  await check("the network dies mid-request: we cannot know, so it stays locked as 'processing' with a warning", async () => {
    await makeWithdrawal("w_net");
    rzx.networkDown = true;
    await runTrigger("w_net");
    rzx.networkDown = false;
    const w = await getDoc("withdrawals/w_net");
    assert.equal(w.status, "processing");
    assert.match(w.autoError, /Check RazorpayX before paying/);
  });

  await check("a withdrawal that is no longer pending is never sent twice", async () => {
    await makeWithdrawal("w_twice");
    rzx.calls.length = 0;
    await runTrigger("w_twice");
    await runTrigger("w_twice");
    assert.equal(rzx.calls.filter((c) => c.path === "/payouts").length, 1);
  });

  await check("a bad UPI id on a withdrawal is left for a person", async () => {
    await makeWithdrawal("w_bad", { paymentDetails: "just text" });
    rzx.calls.length = 0;
    await runTrigger("w_bad");
    assert.equal((await getDoc("withdrawals/w_bad")).status, "pending");
    assert.equal(rzx.calls.length, 0);
  });

  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
