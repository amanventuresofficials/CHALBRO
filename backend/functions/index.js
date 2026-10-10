const functions = require("firebase-functions");
const admin = require("firebase-admin");
const crypto = require("crypto");
const Razorpay = require("razorpay");
const { resolveDiscountPercent, computeAmounts, clampRating } = require("./payments");
const { buildErrorDoc, makeLimiter } = require("./errorlog");
admin.initializeApp();

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
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
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

// Reads the admin-controlled discount from metadata/paymentConfig.
async function getDiscountPercent() {
  const snap = await admin.firestore().collection("metadata").doc("paymentConfig").get();
  return resolveDiscountPercent(snap.exists ? snap.data() : null);
}

// Creates a Razorpay order for a hired task. The amount is worked out here from
// the task document and the admin's discount setting -- the client can never
// dictate what is charged.
exports.createRazorpayOrder = functions.https.onCall(withErrorLog("createRazorpayOrder", async (data, context) => {
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

  const agreedAmount = task.bids && task.bids[task.acceptedByUid]
    ? Number(task.bids[task.acceptedByUid])
    : Number(task.proposedPrice || task.price);
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
// the server asked for -- then completes the task and credits the helper.
// The poster's in-app wallet is NOT debited: they paid real money instead.
exports.verifyRazorpayPayment = functions.https.onCall(withErrorLog("verifyRazorpayPayment", async (data, context) => {
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

  const db = admin.firestore();
  const batch = db.batch();

  batch.set(taskRef, {
    status: "completed",
    completedAt: admin.firestore.FieldValue.serverTimestamp(),
    finalPricePaid: agreedAmount,
    amountPaidByPoster: payable,
    discountPercent,
    discountAmount,
    workerRating: rating,
    paidViaRazorpay: true,
    razorpayPaymentId,
  }, { merge: true });

  batch.set(db.collection("users").doc(context.auth.uid).collection("transactions").doc(), {
    amount: payable,
    type: "debit",
    title: discountAmount > 0
      ? `Paid for task via Razorpay (₹${discountAmount} discount applied)`
      : "Paid for task (Razorpay)",
    taskId,
    razorpayPaymentId,
    real: true, // shown in the app's real-money wallet history, not the practice one
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
  });

  const workerRef = db.collection("users").doc(workerUid);
  // Real money earned goes to the helper's REAL balance. The practice wallet
  // (walletBalance, test credit) is never touched by a Razorpay payment.
  batch.set(workerRef, {
    realBalance: admin.firestore.FieldValue.increment(helperEarnings),
    ratingSum: admin.firestore.FieldValue.increment(rating),
    ratingCount: admin.firestore.FieldValue.increment(1),
    tasksDone: admin.firestore.FieldValue.increment(1),
  }, { merge: true });

  batch.set(workerRef.collection("transactions").doc(), {
    amount: helperEarnings,
    type: "credit",
    title: "Earned from task (Razorpay payment)",
    taskId,
    real: true,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
  });

  // Public review (rating + category only) -- the task itself stays private.
  batch.set(db.collection("reviews").doc(taskId), {
    taskId,
    workerUid,
    posterUid: context.auth.uid,
    rating,
    category: task.category || "Task",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await batch.commit();
  return { success: true };
}));

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
