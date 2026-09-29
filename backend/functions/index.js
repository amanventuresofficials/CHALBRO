const functions = require("firebase-functions");
const admin = require("firebase-admin");
const crypto = require("crypto");
const Razorpay = require("razorpay");
admin.initializeApp();

function getRazorpayClient() {
  return new Razorpay({
    key_id: process.env.RAZORPAY_KEY_ID,
    key_secret: process.env.RAZORPAY_KEY_SECRET,
  });
}

// Creates a Razorpay order for a task, using the price already stored on
// the task document -- the client can never dictate the amount charged.
exports.createRazorpayOrder = functions.https.onCall(async (data, context) => {
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

  const amountRupees = task.proposedPrice || task.price;
  if (!amountRupees || amountRupees <= 0) {
    throw new functions.https.HttpsError("failed-precondition", "Task has no valid price.");
  }

  const razorpay = getRazorpayClient();
  const order = await razorpay.orders.create({
    amount: Math.round(amountRupees * 100), // Razorpay expects paise
    currency: "INR",
    receipt: `task_${taskId}_${Date.now()}`,
    notes: { taskId, posterUid: context.auth.uid },
  });

  return {
    orderId: order.id,
    amount: order.amount,
    currency: order.currency,
    keyId: process.env.RAZORPAY_KEY_ID,
  };
});

// Verifies a completed Razorpay payment's signature, then applies the same
// task-completion + worker-payout bookkeeping as the dummy-wallet flow --
// except the poster's in-app wallet is NOT debited, since they already
// paid real money through Razorpay.
exports.verifyRazorpayPayment = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "You must be signed in.");
  }
  const {
    taskId, workerUid, givenRating,
    razorpayOrderId, razorpayPaymentId, razorpaySignature,
  } = data;
  if (!taskId || !workerUid || !razorpayOrderId || !razorpayPaymentId || !razorpaySignature) {
    throw new functions.https.HttpsError("invalid-argument", "Missing required payment fields.");
  }

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
    // Already processed (e.g. a retried call) -- don't double-credit the worker.
    return { success: true, alreadyCompleted: true };
  }

  const priceAmount = task.proposedPrice || task.price;
  const commission = priceAmount * 0.10;
  const helperEarnings = priceAmount - commission;
  const rating = givenRating || 5;

  const batch = admin.firestore().batch();

  batch.set(taskRef, {
    status: "completed",
    completedAt: admin.firestore.FieldValue.serverTimestamp(),
    finalPricePaid: priceAmount,
    workerRating: rating,
    paidViaRazorpay: true,
    razorpayPaymentId,
  }, { merge: true });

  const posterTxRef = admin.firestore()
    .collection("users").doc(context.auth.uid).collection("transactions").doc();
  batch.set(posterTxRef, {
    amount: priceAmount,
    type: "debit",
    title: "Paid for task (Razorpay)",
    taskId,
    razorpayPaymentId,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
  });

  const workerRef = admin.firestore().collection("users").doc(workerUid);
  batch.set(workerRef, {
    walletBalance: admin.firestore.FieldValue.increment(helperEarnings),
    ratingSum: admin.firestore.FieldValue.increment(rating),
    ratingCount: admin.firestore.FieldValue.increment(1),
    tasksDone: admin.firestore.FieldValue.increment(1),
  }, { merge: true });

  const workerTxRef = workerRef.collection("transactions").doc();
  batch.set(workerTxRef, {
    amount: helperEarnings,
    type: "credit",
    title: "Earned from task (Razorpay payment)",
    taskId,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
  });

  await batch.commit();
  return { success: true };
});

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
    }

    return null;
  });
