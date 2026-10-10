// Replays the app's real queries and write payloads against firestore.rules
// in the Firestore emulator. Run via:  firebase emulators:exec --only firestore "node rules.test.js"
const fs = require("fs");
const path = require("path");
const {
  initializeTestEnvironment, assertSucceeds, assertFails,
} = require("@firebase/rules-unit-testing");
const {
  doc, getDoc, getDocs, collection, query, where, setDoc, updateDoc,
  writeBatch, serverTimestamp, increment, arrayUnion, deleteField, Timestamp, addDoc,
} = require("firebase/firestore");

const RULES = fs.readFileSync(path.join(__dirname, "..", "firestore.rules"), "utf8");

let passed = 0, failed = 0;
const failures = [];
async function check(name, fn) {
  try { await fn(); passed++; console.log("  PASS  " + name); }
  catch (e) { failed++; failures.push(name); console.log("  FAIL  " + name + "\n        " + String(e.message).split("\n")[0]); }
}
const ok = (p) => assertSucceeds(p);
const no = (p) => assertFails(p);

(async () => {
  const env = await initializeTestEnvironment({ projectId: "demo-chalbro", firestore: { rules: RULES } });

  const past = Timestamp.fromMillis(Date.now() - 3600 * 1000);
  const future = Timestamp.fromMillis(Date.now() + 3600 * 1000);

  async function seed() {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      const user = (uid, extra = {}) => setDoc(doc(db, "users", uid),
        { uid, fullName: uid, city: "Surat", walletBalance: 500, realBalance: 500, ratingSum: 0, ratingCount: 0, tasksDone: 0, ...extra });
      await user("poster"); await user("worker"); await user("other"); await user("target"); await user("admin");
      await user("banned", { isBanned: true });
      await setDoc(doc(db, "admins", "admin"), { role: "admin" });

      const base = { postedByUid: "poster", city: "Surat", price: 100, category: "Repairs", title: "T", description: "D", isUrgent: false };
      await setDoc(doc(db, "tasks", "t_open"), { ...base, status: "open", applicants: ["other"], bids: { other: 100 }, endTime: future });
      await setDoc(doc(db, "tasks", "t_expired"), { ...base, status: "open", applicants: [], bids: {}, endTime: past });
      await setDoc(doc(db, "tasks", "t_pending"), { ...base, status: "pending_worker_acceptance", targetHelperUid: "target", applicants: ["target", "other"], bids: { other: 90, target: 100 }, proposedPrice: 100 });
      await setDoc(doc(db, "tasks", "t_assigned"), { ...base, status: "assigned", acceptedByUid: "worker", applicants: ["worker", "other"], bids: { worker: 100, other: 90 }, proposedPrice: 100 });
      await setDoc(doc(db, "tasks", "t_done"), { ...base, status: "completed", acceptedByUid: "worker", applicants: ["worker"], bids: { worker: 100 }, workerRating: 5 });
      await setDoc(doc(db, "tasks", "t_assigned", "taskLog", "l1"), { action: "assigned", actorUid: "worker" });
      await setDoc(doc(db, "tasks", "t_open", "taskLog", "l1"), { action: "task_created", actorUid: "poster" });
      await setDoc(doc(db, "reviews", "t_done"), { taskId: "t_done", workerUid: "worker", posterUid: "poster", rating: 5, category: "Repairs" });
    });
  }

  const as = (uid) => env.authenticatedContext(uid).firestore();
  const tasks = (db) => collection(db, "tasks");
  // Creates a user doc as that user (goes through the rules, like the Terms screen does).
  const setDocAs = (uid, data) => setDoc(doc(as(uid), "users", uid), data, { merge: true });

  // ───────────────────────────── READ VISIBILITY ─────────────────────────────
  console.log("\n[Task visibility: single documents]");
  await seed();
  await check("anyone can read an OPEN task", () => ok(getDoc(doc(as("other"), "tasks", "t_open"))));
  await check("stranger CANNOT read an ASSIGNED task", () => no(getDoc(doc(as("other"), "tasks", "t_assigned"))));
  await check("stranger CANNOT read a COMPLETED task", () => no(getDoc(doc(as("other"), "tasks", "t_done"))));
  await check("stranger CANNOT read a task offered to someone else", () => no(getDoc(doc(as("other"), "tasks", "t_pending"))));
  await check("poster can read assigned task", () => ok(getDoc(doc(as("poster"), "tasks", "t_assigned"))));
  await check("hired worker can read assigned task", () => ok(getDoc(doc(as("worker"), "tasks", "t_assigned"))));
  await check("hired worker can read completed task", () => ok(getDoc(doc(as("worker"), "tasks", "t_done"))));
  await check("targeted helper can read the pending offer", () => ok(getDoc(doc(as("target"), "tasks", "t_pending"))));
  await check("admin can read an assigned task", () => ok(getDoc(doc(as("admin"), "tasks", "t_assigned"))));
  await check("signed-out user cannot read an open task", () => no(getDoc(doc(env.unauthenticatedContext().firestore(), "tasks", "t_open"))));

  console.log("\n[Task visibility: the app's list queries]");
  await check("Find Work / main layout: city + status=='open'", () => ok(getDocs(query(tasks(as("other")), where("city", "==", "Surat"), where("status", "==", "open")))));
  await check("Home: city + status=='open' + isUrgent (urgentOnly)", () => ok(getDocs(query(tasks(as("other")), where("city", "==", "Surat"), where("status", "==", "open"), where("isUrgent", "==", true)))));
  await check("cleanupExpiredTasks: status=='open' + endTime<now", () => ok(getDocs(query(tasks(as("other")), where("status", "==", "open"), where("endTime", "<", Timestamp.now())))));
  await check("My Tasks (posted): postedByUid==me", () => ok(getDocs(query(tasks(as("poster")), where("postedByUid", "==", "poster")))));
  await check("My Tasks (hired): acceptedByUid==me", () => ok(getDocs(query(tasks(as("worker")), where("acceptedByUid", "==", "worker")))));
  await check("My Tasks (hired, assigned only): acceptedByUid==me + status", () => ok(getDocs(query(tasks(as("worker")), where("acceptedByUid", "==", "worker"), where("status", "==", "assigned")))));
  await check("My Tasks (offers): targetHelperUid==me", () => ok(getDocs(query(tasks(as("target")), where("targetHelperUid", "==", "target")))));
  await check("My Tasks (applied, still open): applicants has me + status=='open'", () => ok(getDocs(query(tasks(as("other")), where("applicants", "array-contains", "other"), where("status", "==", "open")))));
  await check("HiredContacts poster stream", () => ok(getDocs(query(tasks(as("poster")), where("postedByUid", "==", "poster")))));
  await check("HiredContacts worker stream", () => ok(getDocs(query(tasks(as("worker")), where("acceptedByUid", "==", "worker")))));
  await check("admin lists every task", () => ok(getDocs(tasks(as("admin")))));
  await check("OLD applied query (array-contains, no status) is now refused", () => no(getDocs(query(tasks(as("other")), where("applicants", "array-contains", "other")))));
  await check("OLD streamTasksByCity (city only) is now refused", () => no(getDocs(query(tasks(as("other")), where("city", "==", "Surat")))));
  await check("listing ALL tasks as a normal user is refused", () => no(getDocs(tasks(as("other")))));
  await check("a stranger cannot list another user's tasks via postedByUid", () => no(getDocs(query(tasks(as("other")), where("postedByUid", "==", "poster")))));
  await check("a stranger cannot list another user's hired tasks via acceptedByUid", () => no(getDocs(query(tasks(as("other")), where("acceptedByUid", "==", "worker")))));

  console.log("\n[Task activity log]");
  await check("stranger can read the log of an OPEN task", () => ok(getDocs(collection(as("other"), "tasks", "t_open", "taskLog"))));
  await check("stranger CANNOT read the log of an ASSIGNED task", () => no(getDocs(collection(as("other"), "tasks", "t_assigned", "taskLog"))));
  await check("hired worker can read the log of their task", () => ok(getDocs(collection(as("worker"), "tasks", "t_assigned", "taskLog"))));
  await check("anyone signed in can still append a log entry", () => ok(addDoc(collection(as("target"), "tasks", "t_pending", "taskLog"), { action: "x", actorUid: "target" })));

  // ───────────────────────────── REVIEWS ─────────────────────────────
  console.log("\n[Reviews]");
  await seed();
  await check("anyone signed in can read reviews", () => ok(getDocs(query(collection(as("other"), "reviews"), where("workerUid", "==", "worker")))));
  await check("poster of an assigned task can create its review", () => ok(setDoc(doc(as("poster"), "reviews", "t_assigned"),
    { taskId: "t_assigned", workerUid: "worker", posterUid: "poster", rating: 4, category: "Repairs", createdAt: serverTimestamp() })));
  await check("review with rating 9 is refused", () => no(setDoc(doc(as("poster"), "reviews", "t_assigned"),
    { taskId: "t_assigned", workerUid: "worker", posterUid: "poster", rating: 9, category: "Repairs" })));
  await check("review for the wrong worker is refused", () => no(setDoc(doc(as("poster"), "reviews", "t_assigned"),
    { taskId: "t_assigned", workerUid: "other", posterUid: "poster", rating: 5, category: "Repairs" })));
  await check("stranger cannot review someone else's task", () => no(setDoc(doc(as("other"), "reviews", "t_assigned"),
    { taskId: "t_assigned", workerUid: "worker", posterUid: "other", rating: 5, category: "Repairs" })));
  await check("a review cannot be edited afterwards", () => no(updateDoc(doc(as("poster"), "reviews", "t_done"), { rating: 1 })));
  await check("a review cannot be deleted", () => no(env.authenticatedContext("poster").firestore().doc("reviews/t_done").delete()));

  // ─────────────────── TASK LIFECYCLE WRITES (the app's real payloads) ───────────────────
  console.log("\n[Task lifecycle: writes exactly as database_service.dart sends them]");
  await seed();
  await check("apply to an open task (arrayUnion + own bid)", () => ok(updateDoc(doc(as("target"), "tasks", "t_open"), { applicants: arrayUnion("target"), "bids.target": 120 })));
  await check("apply to an ASSIGNED task is refused", () => no(updateDoc(doc(as("target"), "tasks", "t_assigned"), { applicants: arrayUnion("target"), "bids.target": 120 })));
  await check("applying cannot overwrite someone else's bid", () => no(updateDoc(doc(as("target"), "tasks", "t_open"), { applicants: arrayUnion("target"), "bids.other": 1 })));
  await check("poster proposes to a helper", () => ok(updateDoc(doc(as("poster"), "tasks", "t_open"),
    { status: "pending_worker_acceptance", targetHelperUid: "target", applicants: arrayUnion("target"), proposedPrice: 100, proposedAt: serverTimestamp() })));
  await check("stranger cannot propose on someone else's task", () => no(updateDoc(doc(as("other"), "tasks", "t_open"),
    { status: "pending_worker_acceptance", targetHelperUid: "other", applicants: arrayUnion("other"), proposedPrice: 1, proposedAt: serverTimestamp() })));
  await check("targeted helper accepts the offer", () => ok(updateDoc(doc(as("target"), "tasks", "t_pending"),
    { status: "assigned", acceptedByUid: "target", assignedAt: serverTimestamp(), "bids.target": 100 })));
  await check("a different user cannot accept someone else's offer", () => no(updateDoc(doc(as("other"), "tasks", "t_pending"),
    { status: "assigned", acceptedByUid: "other", assignedAt: serverTimestamp(), "bids.other": 100 })));
  await seed();
  await check("targeted helper declines the offer", () => ok(updateDoc(doc(as("target"), "tasks", "t_pending"),
    { status: "open", targetHelperUid: deleteField(), proposedPrice: deleteField(), proposedAt: deleteField() })));
  await check("hired worker marks the work done", () => ok(updateDoc(doc(as("worker"), "tasks", "t_assigned"), { workerCompleted: true, workerCompletedAt: serverTimestamp() })));
  await check("stranger cannot mark someone else's task done", () => no(updateDoc(doc(as("other"), "tasks", "t_assigned"), { workerCompleted: true, workerCompletedAt: serverTimestamp() })));
  await check("stranger cannot force an assigned task to 'completed'", () => no(updateDoc(doc(as("other"), "tasks", "t_assigned"), { status: "completed" })));
  await check("nobody can reassign postedByUid", () => no(updateDoc(doc(as("poster"), "tasks", "t_assigned"), { postedByUid: "other" })));
  await check("anyone can expire a task past its endTime", () => ok(updateDoc(doc(as("other"), "tasks", "t_expired"), { status: "expired" })));
  await check("but not a task that has not yet ended", () => no(updateDoc(doc(as("other"), "tasks", "t_open"), { status: "expired" })));
  await check("a banned user cannot apply", () => no(updateDoc(doc(as("banned"), "tasks", "t_open"), { applicants: arrayUnion("banned"), "bids.banned": 50 })));

  // ───────────────────────── PAYMENT (dummy wallet) ─────────────────────────
  console.log("\n[Dummy-wallet payment: payAndCompleteTask batch]");
  function payBatch(db, { payable, discountPercent, discountAmount, withDiscountFields }) {
    const b = writeBatch(db);
    const taskPayload = { status: "completed", completedAt: serverTimestamp(), finalPricePaid: 200, workerRating: 5 };
    if (withDiscountFields) Object.assign(taskPayload, { amountPaidByPoster: payable, discountPercent, discountAmount });
    b.set(doc(db, "tasks", "t_assigned"), taskPayload, { merge: true });
    b.set(doc(db, "users", "poster"), { walletBalance: increment(-payable) }, { merge: true });
    b.set(doc(collection(db, "users", "poster", "transactions")), { amount: payable, type: "debit", title: "Paid for task", taskId: "t_assigned", timestamp: serverTimestamp() });
    b.set(doc(db, "users", "worker"), { walletBalance: increment(180), ratingSum: increment(5), ratingCount: increment(1), tasksDone: increment(1) }, { merge: true });
    b.set(doc(collection(db, "users", "worker", "transactions")), { amount: 180, type: "credit", title: "Earned from task", taskId: "t_assigned", timestamp: serverTimestamp() });
    b.set(doc(db, "reviews", "t_assigned"), { taskId: "t_assigned", workerUid: "worker", posterUid: "poster", rating: 5, category: "Repairs", createdAt: serverTimestamp() });
    return b.commit();
  }
  await seed();
  await check("pay with NO discount (full payload incl. review)", () => ok(payBatch(as("poster"), { payable: 200, discountPercent: 0, discountAmount: 0, withDiscountFields: true })));
  await seed();
  await check("pay with 10% discount (poster pays 180, helper earns 180)", () => ok(payBatch(as("poster"), { payable: 180, discountPercent: 10, discountAmount: 20, withDiscountFields: true })));
  await seed();
  await check("pay without the new discount fields (older payload) still works", () => ok(payBatch(as("poster"), { payable: 200, withDiscountFields: false })));
  await seed();
  await check("a stranger cannot run the payment batch", () => no(payBatch(as("other"), { payable: 200, discountPercent: 0, discountAmount: 0, withDiscountFields: true })));

  console.log("\n[Wallet & ratings: nobody can mint money or reputation]");
  await seed();
  await check("a user cannot top up their OWN wallet", () => no(updateDoc(doc(as("other"), "users", "other"), { walletBalance: increment(1000) })));
  await check("a user cannot SET their own wallet to a big number", () => no(setDoc(doc(as("other"), "users", "other"), { walletBalance: 99999 }, { merge: true })));
  await check("a user cannot drain someone ELSE's wallet", () => no(updateDoc(doc(as("other"), "users", "worker"), { walletBalance: increment(-100) })));
  await check("a user cannot inflate their own rating", () => no(updateDoc(doc(as("other"), "users", "other"), { ratingSum: increment(500), ratingCount: increment(1) })));
  await check("a user cannot inflate their own tasksDone", () => no(updateDoc(doc(as("other"), "users", "other"), { tasksDone: increment(50) })));
  await check("a user CAN lower their own wallet (paying)", () => ok(updateDoc(doc(as("other"), "users", "other"), { walletBalance: increment(-100) })));
  await check("poster credits a helper: wallet up, one rating, one more task", () => ok(updateDoc(doc(as("poster"), "users", "worker"),
    { walletBalance: increment(180), ratingSum: increment(5), ratingCount: increment(1), tasksDone: increment(1) })));
  await check("but not a huge rating bump on someone else", () => no(updateDoc(doc(as("poster"), "users", "worker"), { ratingSum: increment(500), ratingCount: increment(100) })));
  await check("admin can adjust any wallet", () => ok(updateDoc(doc(as("admin"), "users", "worker"), { walletBalance: increment(250) })));

  console.log("\n[User profile: every way the app writes its own document]");
  await seed();
  const fresh = () => env.authenticatedContext("newbie").firestore();
  await check("terms screen creates the doc (termsAccepted only)", () => ok(setDoc(doc(fresh(), "users", "newbie"), { termsAccepted: true, termsAcceptedAt: serverTimestamp() }, { merge: true })));
  const firstSave = (extra) => ({ uid: "newbie", email: "n@x.com", fullName: "New Bie", phone: "+919000000000", gender: "Male", city: "Surat",
    qualifications: "Plumber", updatedAt: serverTimestamp(), createdAt: serverTimestamp(), walletBalance: 500, ratingSum: 0, ratingCount: 0,
    tasksDone: 0, isOpenForWork: false, ...extra });
  await check("first profile save WITHOUT an ID photo ('Not Uploaded')", () => ok(setDoc(doc(fresh(), "users", "newbie"), firstSave({ idProofStatus: "Not Uploaded" }), { merge: true })));
  await seed();
  await setDocAs("newbie", { termsAccepted: true });
  await check("first profile save WITH an ID photo ('Pending Verification')", () => ok(setDoc(doc(fresh(), "users", "newbie"), firstSave({ idProofStatus: "Pending Verification" }), { merge: true })));
  await seed();
  await setDocAs("newbie", { termsAccepted: true });
  await check("first save cannot start with a bigger wallet", () => no(setDoc(doc(fresh(), "users", "newbie"), firstSave({ idProofStatus: "Not Uploaded", walletBalance: 99999 }), { merge: true })));
  await check("first save cannot start with a pre-made rating", () => no(setDoc(doc(fresh(), "users", "newbie"), firstSave({ idProofStatus: "Not Uploaded", ratingSum: 50, ratingCount: 10 }), { merge: true })));
  await check("first save cannot claim 'Verified'", () => no(setDoc(doc(fresh(), "users", "newbie"), firstSave({ idProofStatus: "Verified" }), { merge: true })));
  await seed();
  await check("a brand-new user cannot create a doc with a huge wallet", () => no(setDoc(doc(env.authenticatedContext("fresh2").firestore(), "users", "fresh2"), { walletBalance: 99999 })));
  console.log("\n[Withdrawal requests]");
  const putConfig = (on) => env.withSecurityRulesDisabled(async (ctx) => setDoc(doc(ctx.firestore(), "metadata", "paymentConfig"), { useRazorpay: on }));
  const wd = (extra = {}) => ({ uid: "worker", amount: 200, paymentDetails: "ravi.k@okhdfc", userName: "Worker", status: "pending", timestamp: serverTimestamp(), ...extra });
  // Request + hold of the REAL balance in one batch, exactly as the app does it. The seeded real balance is Rs 500.
  const requestWd = async (data, wallet = 300, uid = "worker") => {
    const db = as(uid);
    const b = writeBatch(db);
    b.set(doc(db, "withdrawals", "req1"), data);
    b.update(doc(db, "users", uid), { realBalance: wallet });
    return b.commit();
  };
  await seed(); await putConfig(true);
  await check("a withdrawal (wallet held by the same amount) is accepted", () => ok(requestWd(wd())));
  await seed(); await putConfig(true);
  await check("the app's own way (increment(-amount)) is accepted", async () => {
    const db = as("worker");
    const b = writeBatch(db);
    b.set(doc(db, "withdrawals", "req1"), wd());
    b.update(doc(db, "users", "worker"), { realBalance: increment(-200) });
    return ok(b.commit());
  });
  await seed(); await putConfig(true);
  await check("wallet reduced by LESS than the amount is refused", () => no(requestWd(wd(), 400)));
  await seed(); await putConfig(true);
  await check("wallet reduced by MORE than the amount is refused", () => no(requestWd(wd(), 100)));
  await seed(); await putConfig(true);
  await check("a request without touching the wallet is refused", () => no(setDoc(doc(as("worker"), "withdrawals", "req1"), wd())));
  await seed(); await putConfig(true);
  await check("more than the balance is refused", () => no(requestWd(wd({ amount: 600 }), -100)));
  await seed(); await putConfig(true);
  await check("below the Rs 100 minimum is refused", () => no(requestWd(wd({ amount: 50 }), 450)));
  await seed(); await putConfig(true);
  await check("a UPI id that is not a UPI id is refused", () => no(requestWd(wd({ paymentDetails: "just some text" }))));
  await seed(); await putConfig(true);
  await check("an extra field is refused", () => no(requestWd(wd({ approvedByAdmin: true }))));
  await seed(); await putConfig(true);
  await check("creating it as already 'approved' is refused", () => no(requestWd(wd({ status: "approved" }))));
  await seed(); await putConfig(true);
  await check("asking in someone else's name is refused", () => no(requestWd(wd({ uid: "other" }))));
  await seed(); await putConfig(true);
  await check("a banned user cannot request", () => no(requestWd(wd({ uid: "banned" }), 300, "banned")));
  await seed(); await putConfig(false);
  await check("while Razorpay is OFF (virtual wallet) withdrawals are closed", () => no(requestWd(wd())));
  await seed();
  await check("with no payment config at all withdrawals are closed", () => no(requestWd(wd())));
  await seed(); await putConfig(true);
  await requestWd(wd());
  await check("the requester cannot approve their own request", () => no(updateDoc(doc(as("worker"), "withdrawals", "req1"), { status: "approved" })));
  await check("the requester can read their request", () => ok(getDoc(doc(as("worker"), "withdrawals", "req1"))));
  await check("someone else cannot read it", () => no(getDoc(doc(as("other"), "withdrawals", "req1"))));
  await check("an admin can mark it paid with a reference", () => ok(updateDoc(doc(as("admin"), "withdrawals", "req1"), { status: "approved", paidReference: "UTR123", processedAt: serverTimestamp() })));
  await seed();
  console.log("\n[Two balances: practice wallet and real balance]");
  await seed(); await putConfig(true);
  await check("a new user starts with Rs 500 practice credit, even when Razorpay is on", () => ok(setDoc(doc(env.authenticatedContext("w1").firestore(), "users", "w1"), { walletBalance: 500 })));
  await check("a new user cannot start with a real balance", () => no(setDoc(doc(env.authenticatedContext("w2").firestore(), "users", "w2"), { walletBalance: 500, realBalance: 100 })));
  await setDocAs("w5", { termsAccepted: true });
  await check("first profile save with Rs 500 practice and Rs 0 real is accepted", () => ok(setDoc(doc(as("w5"), "users", "w5"), { ...firstSave({ idProofStatus: "Not Uploaded" }), uid: "w5", walletBalance: 500, realBalance: 0 }, { merge: true })));
  await setDocAs("w6", { termsAccepted: true });
  await check("first profile save claiming a real balance is refused", () => no(setDoc(doc(as("w6"), "users", "w6"), { ...firstSave({ idProofStatus: "Not Uploaded" }), uid: "w6", walletBalance: 500, realBalance: 50 }, { merge: true })));
  await seed();
  await check("an owner cannot raise their own real balance", () => no(updateDoc(doc(as("worker"), "users", "worker"), { realBalance: 9999 })));
  await check("a poster cannot credit a helper's real balance from the app", () => no(updateDoc(doc(as("poster"), "users", "worker"), { realBalance: increment(100) })));
  await check("an owner can lower their own real balance (that is what a withdrawal does)", () => ok(updateDoc(doc(as("worker"), "users", "worker"), { realBalance: 400 })));
  await check("an admin can set a real balance", () => ok(updateDoc(doc(as("admin"), "users", "worker"), { realBalance: 777 })));
  await seed();

  await check("a brand-new user cannot create themselves as an admin-flagged/unbanned user", () => no(setDoc(doc(env.authenticatedContext("fresh3").firestore(), "users", "fresh3"), { canPost: true })));
  await check("upload ID photo (idProofUrl + 'Pending Verification')", () => ok(updateDoc(doc(as("other"), "users", "other"), { idProofUrl: "https://x/y", idProofStatus: "Pending Verification", updatedAt: serverTimestamp() })));
  await check("a user cannot approve their own ID", () => no(updateDoc(doc(as("other"), "users", "other"), { idProofStatus: "Verified" })));
  await check("a user cannot un-ban or un-pause themselves", () => no(updateDoc(doc(as("banned"), "users", "banned"), { isBanned: false })));
  await check("profile photo", () => ok(updateDoc(doc(as("other"), "users", "other"), { profilePhotoUrl: "https://x/p.jpg" })));
  await check("settings: name/phone/skills/city", () => ok(updateDoc(doc(as("other"), "users", "other"), { fullName: "N", phone: "+91", qualifications: "q", city: "Surat" })));
  await check("settings: open-for-work, hide-from-search, leaderboard toggles", () => ok(setDoc(doc(as("other"), "users", "other"), { isOpenForWork: true, isHiddenFromSearch: true, leaderboardOptIn: true }, { merge: true })));
  await check("push token registration (arrayUnion)", () => ok(setDoc(doc(as("other"), "users", "other"), { fcmTokens: arrayUnion("tok") }, { merge: true })));
  await check("someone else cannot edit my profile", () => no(updateDoc(doc(as("other"), "users", "worker"), { fullName: "Hacked" })));
  await check("admin approves an ID", () => ok(updateDoc(doc(as("admin"), "users", "other"), { idProofStatus: "Verified", canPost: true })));
  await check("admin bans a user", () => ok(updateDoc(doc(as("admin"), "users", "other"), { isBanned: true })));
  await check("Delete Account: a user deletes their own profile", () => ok(env.authenticatedContext("other").firestore().doc("users/other").delete()));
  await check("a user cannot delete someone else's profile", () => no(env.authenticatedContext("other").firestore().doc("users/worker").delete()));

  console.log("\n[Notifications: sender cannot be spoofed]");
  await check("send a notification as yourself", () => ok(addDoc(collection(as("poster"), "users", "target", "notifications"), { fromUid: "poster", title: "Hi", message: "m", isRead: false, createdAt: serverTimestamp() })));
  await check("cannot send a notification pretending to be someone else", () => no(addDoc(collection(as("poster"), "users", "target", "notifications"), { fromUid: "admin", title: "Hi", message: "m", isRead: false, createdAt: serverTimestamp() })));

  console.log("\n[Admin panel: task management]");
  await seed();
  await check("admin force-closes a hired task (admin panel updateTaskStatus)", () => ok(updateDoc(doc(as("admin"), "tasks", "t_assigned"), { status: "cancelled" })));
  await check("admin deletes a task", () => ok(env.authenticatedContext("admin").firestore().doc("tasks/t_done").delete()));
  await check("a normal user still cannot force a status on someone's task", () => no(updateDoc(doc(as("other"), "tasks", "t_pending"), { status: "cancelled" })));
  await check("admin adjusts a wallet and logs the action", async () => {
    await ok(updateDoc(doc(as("admin"), "users", "worker"), { walletBalance: increment(-50) }));
    await ok(addDoc(collection(as("admin"), "adminLogs"), { adminUid: "admin", action: "wallet_adjusted", targetId: "worker", timestamp: serverTimestamp() }));
  });
  await check("admin processes a withdrawal (status + refund)", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => setDoc(doc(ctx.firestore(), "withdrawals", "w1"), { uid: "worker", amount: 100, status: "pending" }));
    const adminDb = as("admin");
    const b = writeBatch(adminDb);
    b.update(doc(adminDb, "withdrawals", "w1"), { status: "rejected", processedAt: serverTimestamp() });
    b.update(doc(adminDb, "users", "worker"), { walletBalance: increment(100) });
    await ok(b.commit());
  });
  await check("admin reads every transaction (collection group)", () => ok(getDocs(env.authenticatedContext("admin").firestore().collectionGroup("transactions"))));

  console.log("\n[Admin: payment settings document]");
  await check("admin can write metadata/paymentConfig", () => ok(setDoc(doc(as("admin"), "metadata", "paymentConfig"), { paymentsEnabled: true, useRazorpay: false, discountEnabled: true, discountPercent: 10 })));
  await check("normal user cannot write metadata/paymentConfig", () => no(setDoc(doc(as("other"), "metadata", "paymentConfig"), { discountEnabled: true, discountPercent: 90 })));
  await check("normal user can read metadata/paymentConfig", () => ok(getDoc(doc(as("other"), "metadata", "paymentConfig"))));

  // ───────────────────────── ERROR LOGS (app -> admin panel) ─────────────────────────
  console.log("\n[Error logs: the app writes, only admins read]");
  await seed();
  const goodLog = (over = {}) => ({
    category: "database", severity: "error", message: "Missing or insufficient permissions",
    errorType: "cloud_firestore/permission-denied", fingerprint: "ab12cd34", context: "Live: open tasks",
    uid: "worker", appVersion: "1.0.0+6", platform: "android", status: "open", source: "client",
    createdAt: serverTimestamp(), stack: "#0 HomeState.build (package:chalbroo/screens/home_screen.dart:1:1)", ...over,
  });
  await check("a signed-in user's app can log an error about its own session", () => ok(addDoc(collection(as("worker"), "errorLogs"), goodLog())));
  await check("payment errors can carry a task id and a few extra facts", () => ok(addDoc(collection(as("poster"), "errorLogs"), goodLog({ category: "payment", severity: "fatal", uid: "poster", taskId: "t_assigned", extra: { razorpayPaymentId: "pay_1", agreedAmount: "450" } }))));
  await check("cannot log in someone else's name", () => no(addDoc(collection(as("worker"), "errorLogs"), goodLog({ uid: "other" }))));
  await check("unknown category is refused", () => no(addDoc(collection(as("worker"), "errorLogs"), goodLog({ category: "hacking" }))));
  await check("unknown severity is refused", () => no(addDoc(collection(as("worker"), "errorLogs"), goodLog({ severity: "meh" }))));
  await check("extra fields are refused", () => no(addDoc(collection(as("worker"), "errorLogs"), goodLog({ secret: "x" }))));
  await check("a 5,000-character message is refused", () => no(addDoc(collection(as("worker"), "errorLogs"), goodLog({ message: "x".repeat(5000) }))));
  await check("a client cannot create an already-resolved log", () => no(addDoc(collection(as("worker"), "errorLogs"), goodLog({ status: "resolved" }))));
  await check("a client cannot back-date a log", () => no(addDoc(collection(as("worker"), "errorLogs"), goodLog({ createdAt: Timestamp.fromMillis(1000) }))));
  await check("signed-out users cannot log", () => no(addDoc(collection(env.unauthenticatedContext().firestore(), "errorLogs"), goodLog())));
  await check("normal users cannot read error logs", () => no(getDocs(collection(as("worker"), "errorLogs"))));
  await check("admin reads the error list", () => ok(getDocs(collection(as("admin"), "errorLogs"))));
  await check("admin marks a log resolved, a normal user cannot touch it", async () => {
    const ref = await addDoc(collection(as("worker"), "errorLogs"), goodLog());
    await no(updateDoc(doc(as("worker"), "errorLogs", ref.id), { status: "resolved" }));
    await ok(updateDoc(doc(as("admin"), "errorLogs", ref.id), { status: "resolved", resolvedBy: "admin" }));
  });
  await check("admin can delete logs, a normal user cannot", async () => {
    const ref = await addDoc(collection(as("worker"), "errorLogs"), goodLog());
    await no(env.authenticatedContext("worker").firestore().doc(`errorLogs/${ref.id}`).delete());
    await ok(env.authenticatedContext("admin").firestore().doc(`errorLogs/${ref.id}`).delete());
  });

  // ───────────────────────── REPORTS ─────────────────────────
  console.log("\n[Reports: users flag tasks/people, admins review]");
  const goodReport = (over = {}) => ({
    reporterUid: "worker", targetType: "task", targetId: "t_open", targetOwnerUid: "poster", targetTitle: "T",
    reason: "spam", details: "looks fake", status: "open", createdAt: serverTimestamp(), ...over,
  });
  const rid = "worker_task_t_open";
  await check("a user reports a task", () => ok(setDoc(doc(as("worker"), "reports", rid), goodReport())));
  await check("reporting the same target again is refused (one report per person per target)", () => no(setDoc(doc(as("worker"), "reports", rid), goodReport({ details: "again" }))));
  await check("a user can report another user", () => ok(setDoc(doc(as("worker"), "reports", "worker_user_poster"), goodReport({ targetType: "user", targetId: "poster", targetOwnerUid: "poster" }))));
  await check("cannot report yourself or your own task", () => no(setDoc(doc(as("poster"), "reports", "poster_task_t_open"), goodReport({ reporterUid: "poster", targetOwnerUid: "poster" }))));
  await check("the document id must match reporter + target", () => no(setDoc(doc(as("other"), "reports", "anything"), goodReport({ reporterUid: "other" }))));
  await check("cannot file a report in someone else's name", () => no(setDoc(doc(as("other"), "reports", "worker_task_t_x"), goodReport({ targetId: "t_x" }))));
  await check("an unknown reason is refused", () => no(setDoc(doc(as("other"), "reports", "other_task_t_open"), goodReport({ reporterUid: "other", reason: "because" }))));
  await check("an over-long details text is refused", () => no(setDoc(doc(as("other"), "reports", "other_task_t_open"), goodReport({ reporterUid: "other", details: "x".repeat(900) }))));
  await check("a banned user cannot file reports", () => no(setDoc(doc(as("banned"), "reports", "banned_task_t_open"), goodReport({ reporterUid: "banned" }))));
  await check("normal users cannot list reports", () => no(getDocs(collection(as("other"), "reports"))));
  await check("not even the reporter can read the report back", () => no(getDoc(doc(as("worker"), "reports", rid))));
  await check("admin lists and resolves reports", async () => {
    await ok(getDocs(collection(as("admin"), "reports")));
    await ok(updateDoc(doc(as("admin"), "reports", rid), { status: "resolved", resolution: "dismissed", resolvedBy: "admin" }));
  });

  // ───────────────────────── ADMIN TEAM ─────────────────────────
  console.log("\n[Admin team: only admins manage admins]");
  await check("an admin can list the admin team", () => ok(getDocs(collection(as("admin"), "admins"))));
  await check("a normal user cannot list the admin team", () => no(getDocs(collection(as("other"), "admins"))));
  await check("a normal user can read only their OWN admin document (the role check)", async () => {
    await ok(getDoc(doc(as("other"), "admins", "other")));
    await no(getDoc(doc(as("other"), "admins", "admin")));
  });
  await check("a normal user cannot make themselves an admin", () => no(setDoc(doc(as("other"), "admins", "other"), { role: "admin", email: "x@y.z" })));
  await check("an admin can add another admin", () => ok(setDoc(doc(as("admin"), "admins", "newadmin"), { email: "n@x.in", displayName: "N", role: "admin", createdAt: serverTimestamp(), addedByUid: "admin", addedByEmail: "a@x.in" })));
  await check("admin documents only accept the known fields", () => no(setDoc(doc(as("admin"), "admins", "weird"), { role: "admin", isSuper: true })));
  await check("a normal user cannot remove an admin", () => no(env.authenticatedContext("other").firestore().doc("admins/admin").delete()));
  await check("an admin cannot remove themselves", () => no(env.authenticatedContext("admin").firestore().doc("admins/admin").delete()));
  await check("an admin can remove another admin", () => ok(env.authenticatedContext("admin").firestore().doc("admins/newadmin").delete()));

  // ───────────────────────── BROADCASTS + APP CONFIG ─────────────────────────
  console.log("\n[Broadcast notifications and app settings]");
  await check("an admin can broadcast into a user's mailbox", () => ok(addDoc(collection(as("admin"), "users", "target", "notifications"), { fromUid: "admin", title: "Notice", message: "m", type: "admin_broadcast", isRead: false, createdAt: serverTimestamp() })));
  await check("even an admin cannot spoof the sender", () => no(addDoc(collection(as("admin"), "users", "target", "notifications"), { fromUid: "poster", title: "Notice", message: "m", isRead: false, createdAt: serverTimestamp() })));
  await check("the user can read what an admin sent them", async () => {
    await ok(getDocs(collection(as("target"), "users", "target", "notifications")));
  });
  await check("admin can write metadata/appConfig", () => ok(setDoc(doc(as("admin"), "metadata", "appConfig"), { maintenanceMode: false, minBuildNumber: 5, allowNewRegistrations: true, minTaskPrice: 50, maxTaskPrice: 50000 })));
  await check("a normal user can read the app config but not change it", async () => {
    await ok(getDoc(doc(as("other"), "metadata", "appConfig")));
    await no(setDoc(doc(as("other"), "metadata", "appConfig"), { maintenanceMode: true }, { merge: true }));
  });
  await check("admin can edit the supported-cities list", () => ok(setDoc(doc(as("admin"), "metadata", "locations"), { cities: ["Surat", "Mumbai"] })));

  await env.cleanup();
  console.log(`\n${passed} passed, ${failed} failed`);
  if (failed) { console.log("FAILED:\n  - " + failures.join("\n  - ")); process.exit(1); }
})().catch((e) => { console.error(e); process.exit(1); });
