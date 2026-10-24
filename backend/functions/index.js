const functions = require("firebase-functions");
const admin = require("firebase-admin");
const crypto = require("crypto");
const Razorpay = require("razorpay");
const {
  resolveDiscountPercent,
  computeAmounts,
  clampRating,
  cashFeeFor,
  splitRecovery,
  autoPayoutAmount,
  resolveMinWithdrawal,
  UPI_PATTERN,
} = require("./payments");
const { buildErrorDoc, makeLimiter } = require("./errorlog");
const payouts = require("./payouts");
const captcha = require("./captcha");
const phoneLogin = require("./phone_login");
const adminTeam = require("./admin_team");
admin.initializeApp();

// The modular import: `admin.firestore.FieldValue` is missing under the Functions
// emulator, which wraps the firebase-admin namespace.
const { FieldValue } = require("firebase-admin/firestore");

// The two values that must never leak live in Google Secret Manager, NOT in `.env`, the code or the
// deployed bundle. Naming them here makes Firebase hand each one, as an ordinary environment variable,
// ONLY to the functions that need it:
//   firebase functions:secrets:set RAZORPAY_KEY_SECRET        (you type it; nobody else sees it)
//   firebase functions:secrets:set RAZORPAYX_WEBHOOK_SECRET   (any long random text)
// `.env` keeps only the harmless ids (RAZORPAY_KEY_ID, RAZORPAYX_ACCOUNT_NUMBER).
const PAYMENT_SECRETS = ["RAZORPAY_KEY_SECRET"];
const WEBHOOK_SECRETS = ["RAZORPAYX_WEBHOOK_SECRET"];

function getRazorpayClient() {
  return new Razorpay({
    key_id: process.env.RAZORPAY_KEY_ID,
    key_secret: process.env.RAZORPAY_KEY_SECRET,
  });
}

// Records a server-side failure in `errorLogs`, where the admin panel's
// "Errors & Health" page shows it next to what the app reports. It never throws
// and never waits long: a logging problem must not change what the caller sees.
const errorLimiter = makeLimiter();
async function logServerError(fnName, err, data, context, category = "payment") {
  try {
    const doc = buildErrorDoc({
      fnName,
      err,
      data,
      category,
      isHttps: err instanceof functions.https.HttpsError,
      auth: context && context.auth,
    });
    if (!doc || !errorLimiter.allow(doc.fingerprint)) return;
    const write = admin.firestore().collection("errorLogs").add({
      ...doc,
      createdAt: FieldValue.serverTimestamp(),
    });
    await Promise.race([write, new Promise((resolve) => setTimeout(resolve, 3000))]);
  } catch (loggingError) {
    console.error("Could not write to errorLogs:", loggingError);
  }
}

// Wraps a callable: if it fails for a reason the owner should know about, the
// failure is recorded, then the original error is re-thrown unchanged.
function withErrorLog(fnName, handler) {
  return async (data, context) => {
    try {
      return await handler(data, context);
    } catch (err) {
      await logServerError(fnName, err, data, context);
      throw err;
    }
  };
}

// metadata/paymentConfig: useRazorpay, discountEnabled/Percent, autoPayout.
async function readPaymentConfig() {
  const snap = await admin.firestore().collection("metadata").doc("paymentConfig").get();
  return snap.exists ? snap.data() || {} : {};
}

// Reads the admin-controlled discount from metadata/paymentConfig.
async function getDiscountPercent() {
  return resolveDiscountPercent(await readPaymentConfig());
}

// What the poster and the hired helper agreed for the task (rupees).
function agreedAmountOf(task) {
  return task.bids && task.bids[task.acceptedByUid]
    ? Number(task.bids[task.acceptedByUid])
    : Number(task.proposedPrice || task.price);
}

function taskLog(taskId, action, actorUid, details) {
  return admin
    .firestore()
    .collection("tasks")
    .doc(taskId)
    .collection("taskLog")
    .add({ action, actorUid, details, timestamp: FieldValue.serverTimestamp() });
}

function notification(uid, fromUid, { title, message, type, taskId }) {
  return admin
    .firestore()
    .collection("users")
    .doc(uid)
    .collection("notifications")
    .add({
      fromUid,
      taskId: taskId || "",
      title,
      message,
      type,
      isRead: false,
      createdAt: FieldValue.serverTimestamp(),
    });
}

const rupees = (n) => `₹${Math.round(n * 100) % 100 === 0 ? Math.round(n) : n.toFixed(2)}`;

// Creates a Razorpay order for a hired task. The amount is worked out here from
// the task document and the admin's discount setting -- the client can never
// dictate what is charged.
exports.createRazorpayOrder = functions.runWith({ secrets: PAYMENT_SECRETS }).https.onCall(withErrorLog("createRazorpayOrder", async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "You must be signed in.");
  }
  const taskId = data.taskId;
  if (!taskId) {
    throw new functions.https.HttpsError("invalid-argument", "taskId is required.");
  }

  const taskSnap = await admin.firestore().collection("tasks").doc(taskId).get();
  if (!taskSnap.exists) {
    throw new functions.https.HttpsError("not-found", "Task not found.");
  }
  const task = taskSnap.data();

  if (task.postedByUid !== context.auth.uid) {
    throw new functions.https.HttpsError("permission-denied", "Only the task poster can pay for this task.");
  }
  if (task.status === "completed") {
    throw new functions.https.HttpsError("failed-precondition", "This task has already been paid.");
  }
  if (task.status !== "assigned" || !task.acceptedByUid) {
    throw new functions.https.HttpsError("failed-precondition", "Hire a helper before paying for this task.");
  }

  const agreedAmount = agreedAmountOf(task);
  if (!Number.isFinite(agreedAmount) || agreedAmount <= 0) {
    throw new functions.https.HttpsError("failed-precondition", "Task has no valid price.");
  }

  const discountPercent = await getDiscountPercent();
  const { discountAmount, payable } = computeAmounts(agreedAmount, discountPercent);

  const razorpay = getRazorpayClient();
  const order = await razorpay.orders.create({
    amount: Math.round(payable * 100), // Razorpay expects paise
    currency: "INR",
    receipt: `t_${taskId}_${Date.now()}`.slice(0, 40),
    // Notes are written here, on the server, and read back when the payment is
    // verified -- this is what ties an order to exactly one task and amount.
    notes: {
      taskId,
      posterUid: context.auth.uid,
      workerUid: task.acceptedByUid,
      agreedAmount: String(agreedAmount),
      discountPercent: String(discountPercent),
      discountAmount: String(discountAmount),
      payable: String(payable),
    },
  });

  return {
    orderId: order.id,
    amount: order.amount,
    currency: order.currency,
    keyId: process.env.RAZORPAY_KEY_ID,
    agreedAmount,
    discountAmount,
  };
}));

// Confirms a Razorpay payment really happened -- for THIS task, for the amount
// the server asked for -- then completes the task, credits the helper's earnings
// and tells them. Only this function can complete a task while Razorpay is on
// (the Firestore rules refuse the app's own attempt).
//
// Two more things happen here:
//  * Fees the helper still owes from earlier CASH jobs (`feeDue`) are taken out of
//    this payment, payment after payment, until nothing is owed.
//  * If the owner has switched on direct UPI payouts and the helper has linked a UPI
//    id, the balance is moved into a withdrawal that autoPayWithdrawal then sends.
exports.verifyRazorpayPayment = functions.runWith({ secrets: PAYMENT_SECRETS }).https.onCall(withErrorLog("verifyRazorpayPayment", async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "You must be signed in.");
  }
  const { taskId, givenRating, razorpayOrderId, razorpayPaymentId, razorpaySignature } = data;
  if (!taskId || !razorpayOrderId || !razorpayPaymentId || !razorpaySignature) {
    throw new functions.https.HttpsError("invalid-argument", "Missing required payment fields.");
  }

  // 1) The signature proves this order/payment pair came from Razorpay.
  const expectedSignature = crypto
    .createHmac("sha256", process.env.RAZORPAY_KEY_SECRET)
    .update(`${razorpayOrderId}|${razorpayPaymentId}`)
    .digest("hex");
  if (expectedSignature !== razorpaySignature) {
    throw new functions.https.HttpsError("permission-denied", "Payment signature verification failed.");
  }

  const taskRef = admin.firestore().collection("tasks").doc(taskId);
  const taskSnap = await taskRef.get();
  if (!taskSnap.exists) {
    throw new functions.https.HttpsError("not-found", "Task not found.");
  }
  const task = taskSnap.data();
  if (task.postedByUid !== context.auth.uid) {
    throw new functions.https.HttpsError("permission-denied", "Only the task poster can complete this payment.");
  }
  if (task.status === "completed") {
    // Already processed (e.g. a retried call) -- don't double-credit the helper.
    return { success: true, alreadyCompleted: true };
  }
  if (task.status !== "assigned" || !task.acceptedByUid) {
    throw new functions.https.HttpsError("failed-precondition", "This task is not awaiting payment.");
  }

  // 2) Ask Razorpay what actually happened, and check it belongs to this task.
  const razorpay = getRazorpayClient();
  const payment = await razorpay.payments.fetch(razorpayPaymentId);
  if (payment.order_id !== razorpayOrderId) {
    throw new functions.https.HttpsError("permission-denied", "Payment does not belong to this order.");
  }
  let paymentStatus = payment.status;
  if (paymentStatus === "authorized") {
    // Accounts set to manual capture need the money captured explicitly.
    await razorpay.payments.capture(razorpayPaymentId, payment.amount, payment.currency);
    paymentStatus = "captured";
  }
  if (paymentStatus !== "captured") {
    throw new functions.https.HttpsError("failed-precondition", "Payment has not been completed.");
  }

  const order = await razorpay.orders.fetch(razorpayOrderId);
  const notes = order.notes || {};
  if (notes.taskId !== taskId || notes.posterUid !== context.auth.uid) {
    throw new functions.https.HttpsError("permission-denied", "This payment was made for a different task.");
  }
  if (payment.amount !== order.amount) {
    throw new functions.https.HttpsError("failed-precondition", "Paid amount does not match the order.");
  }

  // 3) Money maths comes from the server-written order notes, never the client.
  const agreedAmount = Number(notes.agreedAmount);
  const discountPercent = Number(notes.discountPercent) || 0;
  const { discountAmount, payable, helperEarnings } = computeAmounts(agreedAmount, discountPercent);
  if (Math.round(payable * 100) !== order.amount) {
    throw new functions.https.HttpsError("failed-precondition", "Order amount is inconsistent.");
  }
  const workerUid = task.acceptedByUid;
  const rating = clampRating(givenRating);

  const cfg = await readPaymentConfig();
  const directPayouts = cfg.autoPayout === true && payouts.payoutsConfigured();

  const db = admin.firestore();
  const workerRef = db.collection("users").doc(workerUid);
  const now = FieldValue.serverTimestamp();

  // One transaction: the helper's owed fees and balance are read and changed together, so
  // two payments at the same moment cannot both take the same fee or pay out the same money.
  const outcome = await db.runTransaction(async (tx) => {
    const [freshTask, workerSnap] = await Promise.all([tx.get(taskRef), tx.get(workerRef)]);
    if (freshTask.data().status === "completed") return { alreadyCompleted: true };

    const w = workerSnap.exists ? workerSnap.data() || {} : {};
    const { recovered, credit } = splitRecovery(helperEarnings, w.feeDue);
    const before = Number(w.earnings) > 0 ? Number(w.earnings) : 0;
    const upi = typeof w.upiId === "string" && UPI_PATTERN.test(w.upiId) ? w.upiId : "";
    const payout = directPayouts && upi ? autoPayoutAmount(before + credit, resolveMinWithdrawal(cfg)) : 0;

    tx.set(taskRef, {
      status: "completed",
      completedAt: now,
      finalPricePaid: agreedAmount,
      amountPaidByPoster: payable,
      discountPercent,
      discountAmount,
      workerRating: rating,
      paidViaRazorpay: true,
      razorpayPaymentId,
      ...(recovered > 0 ? { feeRecovered: recovered } : {}),
    }, { merge: true });

    tx.set(db.collection("users").doc(context.auth.uid).collection("transactions").doc(), {
      amount: payable,
      type: "debit",
      title: discountAmount > 0
        ? `Paid for task via Razorpay (₹${discountAmount} discount applied)`
        : "Paid for task (Razorpay)",
      taskId,
      razorpayPaymentId,
      razorpay: true, // part of the earnings history the app lists
      timestamp: now,
    });

    // What the helper earned is added to their withdrawable earnings.
    const workerUpdate = {
      earnings: FieldValue.increment(credit - payout),
      ratingSum: FieldValue.increment(rating),
      ratingCount: FieldValue.increment(1),
      tasksDone: FieldValue.increment(1),
    };
    if (recovered > 0) workerUpdate.feeDue = FieldValue.increment(-recovered);
    tx.set(workerRef, workerUpdate, { merge: true });

    tx.set(workerRef.collection("transactions").doc(), {
      amount: helperEarnings,
      type: "credit",
      title: "Earned from task (Razorpay payment)",
      taskId,
      razorpay: true,
      timestamp: now,
    });
    if (recovered > 0) {
      tx.set(workerRef.collection("transactions").doc(), {
        amount: recovered,
        type: "debit",
        title: "Platform fee for earlier cash job(s)",
        taskId,
        razorpay: true,
        timestamp: now,
      });
    }
    if (payout > 0) {
      const withdrawalRef = db.collection("withdrawals").doc();
      tx.set(withdrawalRef, {
        uid: workerUid,
        userName: String(w.fullName || ""),
        amount: payout,
        paymentDetails: upi,
        status: "pending",
        auto: true,
        taskId,
        timestamp: now,
      });
      tx.set(workerRef.collection("transactions").doc(), {
        amount: payout,
        type: "debit",
        title: `Sent to your UPI (${upi})`,
        withdrawalId: withdrawalRef.id,
        razorpay: true,
        timestamp: now,
      });
    }

    // Tell the helper (also becomes a push through sendPushNotification).
    const taken = recovered > 0 ? ` (${rupees(recovered)} was kept for the platform fee on earlier cash jobs)` : "";
    tx.set(workerRef.collection("notifications").doc(), {
      fromUid: context.auth.uid,
      taskId,
      title: "💰 Payment received!",
      message: `You earned ${rupees(helperEarnings)} for your work${taken}. Great job!`,
      createdAt: now,
      isRead: false,
      type: "payment_received",
    });

    // Public review (rating + category only) -- the task itself stays private.
    tx.set(db.collection("reviews").doc(taskId), {
      taskId,
      workerUid,
      posterUid: context.auth.uid,
      rating,
      category: task.category || "Task",
      createdAt: now,
    });
    return { alreadyCompleted: false };
  });

  if (outcome.alreadyCompleted) return { success: true, alreadyCompleted: true };
  return { success: true };
}));

// ─── Cash payments ──────────────────────────────────────────────────────────────
// Poster and helper may settle a job in cash, outside the app. ChalBro's 10% fee is then
// owed by the helper (`feeDue` on their user document) and is taken out of their next
// online payments (see verifyRazorpayPayment) until it is settled.
//
//   claimCashPayment   the poster says they paid cash (and gives the rating): the task is
//                      COMPLETED at once, the helper is told and now owes the fee.
//   answerCashPayment  the helper can say "I did not receive it" within DISPUTE_DAYS: the fee is
//                      taken off again and the task is flagged for the admin to look at.
//
// (Older app builds asked the helper to confirm BEFORE completing; a claim made that way, still
// waiting on the task as `cashClaimedAt`, is still answered the old way below.)

const DISPUTE_DAYS = 7;

async function completeCashTask({ taskRef, task, posterUid, helperUid, agreed, fee, rating, requireClaim }) {
  const db = admin.firestore();
  const workerRef = db.collection("users").doc(helperUid);
  const now = FieldValue.serverTimestamp();
  return db.runTransaction(async (tx) => {
    const fresh = await tx.get(taskRef);
    const f = fresh.data();
    if (f.status === "completed") return false;
    if (f.status !== "assigned" || f.acceptedByUid !== helperUid) return false;
    if (requireClaim && !f.cashClaimedAt) return false;
    tx.update(taskRef, {
      status: "completed",
      completedAt: now,
      workerRating: rating,
      paidInCash: true,
      cashAmount: agreed,
      cashFee: fee,
      cashClaimedAt: FieldValue.delete(),
      cashClaimRating: FieldValue.delete(),
    });
    tx.set(db.collection("reviews").doc(taskRef.id), {
      taskId: taskRef.id,
      workerUid: helperUid,
      posterUid,
      rating,
      category: task.category || "Task",
      createdAt: now,
    });
    tx.set(workerRef, {
      feeDue: FieldValue.increment(fee),
      ratingSum: FieldValue.increment(rating),
      ratingCount: FieldValue.increment(1),
      tasksDone: FieldValue.increment(1),
    }, { merge: true });
    return true;
  });
}

exports.claimCashPayment = functions.https.onCall(withErrorLog("claimCashPayment", async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "You must be signed in.");
  }
  const taskId = data.taskId;
  if (!taskId) {
    throw new functions.https.HttpsError("invalid-argument", "taskId is required.");
  }
  const taskRef = admin.firestore().collection("tasks").doc(taskId);
  const snap = await taskRef.get();
  if (!snap.exists) {
    throw new functions.https.HttpsError("not-found", "Task not found.");
  }
  const task = snap.data();
  if (task.postedByUid !== context.auth.uid) {
    throw new functions.https.HttpsError("permission-denied", "Only the person who posted this task can say it was paid in cash.");
  }
  if (task.status === "completed") {
    throw new functions.https.HttpsError("failed-precondition", "This task is already completed.");
  }
  if (task.status !== "assigned" || !task.acceptedByUid) {
    throw new functions.https.HttpsError("failed-precondition", "Hire a helper before closing this task.");
  }
  if ((await readPaymentConfig()).useRazorpay !== true) {
    throw new functions.https.HttpsError("failed-precondition", "Payments are switched off, so there is nothing to pay for this task.");
  }
  const agreed = agreedAmountOf(task);
  if (!Number.isFinite(agreed) || agreed <= 0) {
    throw new functions.https.HttpsError("failed-precondition", "Task has no valid price.");
  }

  const fee = cashFeeFor(agreed);
  const rating = clampRating(data.givenRating);
  const done = await completeCashTask({
    taskRef, task, posterUid: context.auth.uid, helperUid: task.acceptedByUid, agreed, fee, rating, requireClaim: false,
  });
  if (!done) return { success: true, alreadyCompleted: true };

  const title = task.title || "your task";
  await taskLog(taskId, "cash_paid", context.auth.uid,
    `Poster completed the task and says ${rupees(agreed)} was paid in cash. Platform fee ${rupees(fee)} will be taken from the helper's next online payments.`);
  await notification(task.acceptedByUid, context.auth.uid, {
    title: "✅ Task completed - paid in cash",
    message: `"${title}" is complete. The poster says they paid you ${rupees(agreed)} in cash. `
      + `ChalBro's fee (${rupees(fee)}) will be taken from your next online payments. `
      + `If you did NOT get the cash, open the task within ${DISPUTE_DAYS} days and tap "Not received".`,
    type: "task_completed",
    taskId,
  });
  return { success: true, completed: true, fee };
}));

exports.answerCashPayment = functions.https.onCall(withErrorLog("answerCashPayment", async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "You must be signed in.");
  }
  const taskId = data.taskId;
  if (!taskId || typeof data.received !== "boolean") {
    throw new functions.https.HttpsError("invalid-argument", "taskId and received are required.");
  }
  const db = admin.firestore();
  const taskRef = db.collection("tasks").doc(taskId);
  const snap = await taskRef.get();
  if (!snap.exists) {
    throw new functions.https.HttpsError("not-found", "Task not found.");
  }
  const task = snap.data();
  if (task.acceptedByUid !== context.auth.uid) {
    throw new functions.https.HttpsError("permission-denied", "Only the hired helper can answer this.");
  }
  const posterUid = task.postedByUid;
  const title = task.title || "the task";

  // ── A cash job that is already completed: the helper can say they did not get the cash ──
  if (task.status === "completed" && task.paidInCash === true) {
    if (data.received) return { success: true, confirmed: true, alreadyCompleted: true };
    if (task.cashDisputed === true) return { success: true, alreadyDisputed: true };
    const completedMs = task.completedAt && task.completedAt.toMillis ? task.completedAt.toMillis() : 0;
    if (completedMs && Date.now() - completedMs > DISPUTE_DAYS * 24 * 3600 * 1000) {
      throw new functions.https.HttpsError("failed-precondition",
        `It is more than ${DISPUTE_DAYS} days since this task was completed. Please contact support@chalbro.in.`);
    }
    const fee = Number(task.cashFee) || 0;
    const workerRef = db.collection("users").doc(context.auth.uid);
    const reversed = await db.runTransaction(async (tx) => {
      const [t, u] = await Promise.all([tx.get(taskRef), tx.get(workerRef)]);
      if (t.data().cashDisputed === true) return null;
      const owed = Number(u.data() && u.data().feeDue) || 0;
      const take = Math.min(owed, fee);
      tx.update(taskRef, { cashDisputed: true, cashDisputedAt: FieldValue.serverTimestamp() });
      if (take > 0) tx.set(workerRef, { feeDue: FieldValue.increment(-take) }, { merge: true });
      return take;
    });
    if (reversed === null) return { success: true, alreadyDisputed: true };
    await taskLog(taskId, "cash_disputed", context.auth.uid,
      `Helper says the cash payment was NOT received. The fee (${rupees(reversed)}) is no longer owed. The admin team has been flagged.`);
    await notification(posterUid, context.auth.uid, {
      title: "Cash payment disputed",
      message: `The helper says they did not receive the cash for "${title}". ChalBro will look into it.`,
      type: "cash_denied",
      taskId,
    });
    return { success: true, disputed: true, feeReversed: reversed };
  }

  // ── An older-style claim that is still waiting for the helper to confirm ──
  if (task.status === "completed") {
    return { success: true, alreadyCompleted: true };
  }
  if (task.status !== "assigned" || !task.cashClaimedAt) {
    throw new functions.https.HttpsError("failed-precondition", "No cash payment has been reported for this task.");
  }

  if (!data.received) {
    await taskRef.update({ cashClaimedAt: FieldValue.delete(), cashClaimRating: FieldValue.delete() });
    await taskLog(taskId, "cash_denied", context.auth.uid, "Helper says the cash payment was not received.");
    await notification(posterUid, context.auth.uid, {
      title: "Cash payment not confirmed",
      message: `The helper says they have not received cash for "${title}". You can pay online instead.`,
      type: "cash_denied",
      taskId,
    });
    return { success: true, confirmed: false };
  }

  const agreed = agreedAmountOf(task);
  if (!Number.isFinite(agreed) || agreed <= 0) {
    throw new functions.https.HttpsError("failed-precondition", "Task has no valid price.");
  }
  const fee = cashFeeFor(agreed);
  const done = await completeCashTask({
    taskRef, task, posterUid, helperUid: context.auth.uid, agreed, fee, rating: clampRating(task.cashClaimRating), requireClaim: true,
  });
  if (!done) return { success: true, alreadyCompleted: true };

  await taskLog(taskId, "cash_confirmed", context.auth.uid,
    `Helper confirmed ${rupees(agreed)} paid in cash. Platform fee ${rupees(fee)} will be taken from their next online payments.`);
  await notification(posterUid, context.auth.uid, {
    title: "✅ Task completed",
    message: `The helper confirmed the cash payment for "${title}".`,
    type: "task_completed",
    taskId,
  });
  return { success: true, confirmed: true, fee };
}));

// ─── Paying helpers straight to their UPI id (RazorpayX) ───────────────────────

// The server-only record of RazorpayX contacts / fund accounts (no app can read or write it).
const payoutStore = {
  get: async (uid) => {
    const s = await admin.firestore().collection("payoutAccounts").doc(uid).get();
    return s.exists ? s.data() : null;
  },
  set: (uid, data) => admin.firestore().collection("payoutAccounts").doc(uid).set(data, { merge: true }),
};

// The final answer for a withdrawal that was sent for automatic payout.
//   'paid'   -> approved (+ reference), the helper is told
//   'failed' -> rejected, the money goes back into their earnings, the helper is told
// Safe to call twice: a withdrawal that is already final is left alone (a payout that was
// 'processed' and later REVERSED by the bank is the one exception, and only for auto payouts).
async function settlePayout(withdrawalId, outcome, info = {}) {
  const db = admin.firestore();
  const ref = db.collection("withdrawals").doc(withdrawalId);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return "missing";
    const w = snap.data();
    const final = w.status === "approved" || w.status === "rejected";
    if (final && !(outcome === "failed" && w.status === "approved" && w.auto === true)) return "already";

    const userRef = db.collection("users").doc(w.uid);
    const now = FieldValue.serverTimestamp();
    if (outcome === "paid") {
      tx.update(ref, {
        status: "approved",
        processedAt: now,
        paidReference: info.utr || info.payoutId || "",
        ...(info.payoutId ? { payoutId: info.payoutId } : {}),
      });
      tx.set(userRef.collection("notifications").doc(), {
        fromUid: "chalbro",
        title: "Withdrawal paid",
        message: `We have sent ₹${w.amount} to ${w.paymentDetails}.`,
        type: "withdrawal",
        isRead: false,
        createdAt: now,
      });
      return "paid";
    }
    tx.update(ref, {
      status: "rejected",
      processedAt: now,
      failureReason: String(info.reason || "The payment could not be completed.").slice(0, 200),
    });
    tx.set(userRef, { earnings: FieldValue.increment(w.amount) }, { merge: true });
    tx.set(userRef.collection("transactions").doc(), {
      amount: w.amount,
      type: "credit",
      title: "Withdrawal not paid - returned",
      withdrawalId,
      razorpay: true,
      timestamp: now,
    });
    tx.set(userRef.collection("notifications").doc(), {
      fromUid: "chalbro",
      title: "Withdrawal not paid",
      message: `We could not pay your ₹${w.amount} withdrawal. The money is back in your earnings.`,
      type: "withdrawal",
      isRead: false,
      createdAt: now,
    });
    return "failed";
  });
}

// A new withdrawal (typed by the helper, or made by verifyRazorpayPayment for a linked UPI id)
// is paid out automatically when the owner has switched that on. Otherwise nothing happens and
// the owner pays it by hand from the admin panel, as before.
exports.autoPayWithdrawal = functions
  .runWith({ secrets: PAYMENT_SECRETS })
  .firestore
  .document("withdrawals/{withdrawalId}")
  .onCreate(async (snap, context) => {
    const id = context.params.withdrawalId;
    const w = snap.data() || {};
    try {
      if (w.status !== "pending") return null;
      if ((await readPaymentConfig()).autoPayout !== true || !payouts.payoutsConfigured()) return null;
      if (!UPI_PATTERN.test(String(w.paymentDetails || "")) || !(Number(w.amount) > 0)) return null;

      // Claim it first, so a person cannot also pay it by hand while it is being sent.
      const db = admin.firestore();
      const claimed = await db.runTransaction(async (tx) => {
        const cur = await tx.get(snap.ref);
        if (!cur.exists || cur.data().status !== "pending") return false;
        tx.update(snap.ref, { status: "processing", processingAt: FieldValue.serverTimestamp(), auto: true });
        return true;
      });
      if (!claimed) return null;

      try {
        const res = await payouts.payToUpi({
          store: payoutStore,
          uid: w.uid,
          name: w.userName,
          vpa: w.paymentDetails,
          amountRupees: Number(w.amount),
          reference: id,
          narration: "ChalBro payout",
        });
        await snap.ref.update({ payoutId: res.id, payoutStatus: res.status });
        if (res.status === "processed") {
          await settlePayout(id, "paid", { payoutId: res.id, utr: res.utr });
        } else if (["rejected", "cancelled", "reversed", "failed"].includes(res.status)) {
          await settlePayout(id, "failed", { payoutId: res.id, reason: `The payout was ${res.status}.` });
        }
        // anything else (queued / pending / processing): the webhook gives the final answer
      } catch (err) {
        const answered = typeof err.statusCode === "number";
        await snap.ref.update(answered
          // RazorpayX answered with an error: nothing was sent. Back to a person.
          ? { status: "pending", processingAt: FieldValue.delete(), autoError: String(err.message).slice(0, 200) }
          // No answer at all (network): we cannot know. Keep it locked and say so.
          : { autoError: `Could not confirm the payout: ${String(err.message).slice(0, 160)}. Check RazorpayX before paying by hand.` });
        await logServerError("autoPayWithdrawal", err, { taskId: w.taskId }, null);
      }
    } catch (outer) {
      await logServerError("autoPayWithdrawal", outer, { taskId: w.taskId }, null);
    }
    return null;
  });

// RazorpayX tells us how a payout ended. Register this function's URL in the RazorpayX
// dashboard (Settings > Webhooks) with the events payout.processed, payout.reversed,
// payout.rejected, payout.failed and payout.cancelled, and put the secret you choose there
// into RAZORPAYX_WEBHOOK_SECRET.
exports.razorpayXWebhook = functions.runWith({ secrets: WEBHOOK_SECRETS }).https.onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).send("POST only");
    return;
  }
  const ok = payouts.webhookSignatureOk(req.rawBody, req.get("X-Razorpay-Signature"), process.env.RAZORPAYX_WEBHOOK_SECRET);
  if (!ok) {
    res.status(400).send("bad signature");
    return;
  }
  try {
    const event = payouts.readPayoutEvent(req.body);
    if (event.outcome !== "ignore" && event.reference) {
      await settlePayout(event.reference, event.outcome === "paid" ? "paid" : "failed", event);
    }
    res.status(200).send("ok");
  } catch (err) {
    await logServerError("razorpayXWebhook", err, null, null);
    res.status(500).send("error"); // Razorpay retries
  }
});

// ─── Phone sign-in captcha switch (admin panel: App Settings) ─────────────────────────────────────────
// See captcha.js. The admin panel writes metadata/captchaConfig; these functions apply it to Firebase's
// reCAPTCHA setting for phone sign-in and, in "auto" mode, turn it on while the app keeps reporting
// "too many requests".
let identityClientInstance = null;
function identityClient() {
  if (!identityClientInstance) {
    const projectId = process.env.GCLOUD_PROJECT || (process.env.FIREBASE_CONFIG && JSON.parse(process.env.FIREBASE_CONFIG).projectId);
    identityClientInstance = captcha.makeIdentityClient({
      projectId,
      getToken: async () => (await admin.credential.applicationDefault().getAccessToken()).access_token,
    });
  }
  return identityClientInstance;
}

let captchaServiceInstance = null;
function captchaService() {
  if (!captchaServiceInstance) {
    const { Timestamp } = require("firebase-admin/firestore");
    captchaServiceInstance = captcha.createCaptchaService({ db: admin.firestore(), FieldValue, Timestamp, identity: identityClient() });
  }
  return captchaServiceInstance;
}

// The "Phone login" switch (admin panel > App Settings): see phone_login.js.
let phoneLoginServiceInstance = null;
function phoneLoginService() {
  if (!phoneLoginServiceInstance) {
    const { Timestamp } = require("firebase-admin/firestore");
    phoneLoginServiceInstance = phoneLogin.createPhoneLoginService({ db: admin.firestore(), Timestamp, identity: identityClient() });
  }
  return phoneLoginServiceInstance;
}

// The login screen (nobody signed in yet, so it cannot read Firestore) asks this: only a yes/no comes back.
// If anything goes wrong the answer is "on", so a problem here can never lock people out of signing in.
exports.getLoginOptions = functions.https.onCall(async () => {
  try {
    return await phoneLoginService().getOptions();
  } catch (err) {
    console.error("getLoginOptions failed:", err);
    return { phoneLoginEnabled: true };
  }
});

// An admin changed the Phone login switch: make Firebase's Phone provider match.
exports.phoneLoginOnConfigWrite = functions.firestore.document("metadata/appConfig").onWrite(async (change) => {
  try {
    await phoneLoginService().onConfigWrite(change.before.exists ? change.before.data() : null, change.after.exists ? change.after.data() : null);
  } catch (err) {
    console.error("phoneLoginOnConfigWrite failed:", err);
    await logServerError("phoneLoginOnConfigWrite", err, null, null, "app");
  }
  return null;
});

// Called by the login screens (signed out) when Firebase refuses a phone sign-in. Only adds to a counter.
exports.reportPhoneAuthIssue = functions.https.onCall(async (data) => {
  const code = data && typeof data.code === "string" ? data.code.slice(0, 60) : "";
  const result = await captchaService().reportIssue(code);
  return { counted: !!result.counted };
});

// An admin saved a new choice: apply it straight away.
exports.captchaOnConfigWrite = functions.firestore.document("metadata/captchaConfig").onWrite(async () => {
  try {
    await captchaService().reconcile("config saved");
  } catch (err) {
    console.error("captchaOnConfigWrite failed:", err);
    await logServerError("captchaOnConfigWrite", err, null, null, "app");
  }
  return null;
});

// Every 2 minutes: turn "auto" on/off as the counters change, and refresh what the admin panel shows.
exports.captchaGuard = functions.pubsub.schedule("every 2 minutes").onRun(async () => {
  try {
    const service = captchaService();
    const result = await service.reconcile("scheduled");
    // Shown in `firebase functions:log`, so a missing permission is easy to spot (the admin panel shows it too).
    if (!result.ok) console.warn("captchaGuard: could not read or change Firebase's captcha setting:", result.error);
    await service.cleanup();
    await phoneLoginService().retryPending();
  } catch (err) {
    console.error("captchaGuard failed:", err);
    await logServerError("captchaGuard", err, null, null, "app");
  }
  return null;
});

// ─── Admin Team (admin panel > Admin Team): see admin_team.js ──────────────────────────────────────────
// Every call checks on the server that the CALLER is an admin, so these work whatever state the security rules are in.
let adminTeamServiceInstance = null;
function adminTeamService() {
  if (!adminTeamServiceInstance) {
    const { Timestamp } = require("firebase-admin/firestore");
    adminTeamServiceInstance = adminTeam.createAdminTeamService({ db: admin.firestore(), auth: admin.auth(), FieldValue, Timestamp });
  }
  return adminTeamServiceInstance;
}

// Turns a deliberate refusal into the answer the admin panel shows; anything unexpected is logged as an error.
async function teamCall(name, context, fn) {
  try {
    return await fn(context.auth ? context.auth.uid : null, (context.auth && context.auth.token && context.auth.token.email) || "");
  } catch (err) {
    if (err instanceof adminTeam.TeamError) throw new functions.https.HttpsError(err.code, err.message);
    await logServerError(name, err, null, context);
    throw new functions.https.HttpsError("internal", "Something went wrong. Please try again.");
  }
}

exports.addAdminUser = functions.https.onCall((data, context) =>
  teamCall("addAdminUser", context, (uid, email) => adminTeamService().addAdmin(uid, email, data && data.input)),
);
exports.listAdminUsers = functions.https.onCall((data, context) =>
  teamCall("listAdminUsers", context, (uid) => adminTeamService().listAdmins(uid)),
);
exports.removeAdminUser = functions.https.onCall((data, context) =>
  teamCall("removeAdminUser", context, (uid) => adminTeamService().removeAdmin(uid, data && data.uid, data && data.label)),
);

exports.sendPushNotification = functions.firestore
  .document("users/{userId}/notifications/{notificationId}")
  .onCreate(async (snap, context) => {
    const notification = snap.data();
    const userId = context.params.userId;

    // Get the user's FCM tokens
    const userDoc = await admin.firestore().collection("users").doc(userId).get();
    const fcmTokens = userDoc.exists ? userDoc.data().fcmTokens : null;

    if (!fcmTokens || fcmTokens.length === 0) {
      console.log("No FCM tokens for user", userId);
      return null;
    }

    const message = {
      tokens: fcmTokens,
      notification: {
        title: notification.title || "New Notification",
        body: notification.message || "You have a new update in Chalbro.",
      },
      data: {
        click_action: "FLUTTER_NOTIFICATION_CLICK",
        taskId: notification.taskId || "",
        type: notification.type || "",
      },
    };

    try {
      const response = await admin.messaging().sendEachForMulticast(message);
      console.log("Sent:", response.successCount, "failed:", response.failureCount);
    } catch (error) {
      console.log("Error sending message:", error);
      await logServerError("sendPushNotification", error, null, null, "app");
    }

    return null;
  });
