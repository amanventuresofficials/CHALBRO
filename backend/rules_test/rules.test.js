// Replays the app's real queries and write payloads against firestore.rules
// in the Firestore emulator. Run via:  firebase emulators:exec --only firestore "node rules.test.js"
const assert = require("node:assert/strict");
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
        { uid, fullName: uid, city: "Surat", earnings: 500, ratingSum: 0, ratingCount: 0, tasksDone: 0, ...extra });
      await user("poster"); await user("worker"); await user("other"); await user("target"); await user("admin");
      await user("banned", { isBanned: true });
      await setDoc(doc(db, "admins", "admin"), { role: "admin" });

      const base = { postedByUid: "poster", city: "Surat", price: 100, category: "Repairs", title: "T", description: "D", isUrgent: false };
      await setDoc(doc(db, "tasks", "t_open"), { ...base, status: "open", applicants: ["other"], bids: { other: 100 }, endTime: future });
      await setDoc(doc(db, "tasks", "t_expired"), { ...base, status: "open", applicants: [], bids: {}, endTime: past });
      await setDoc(doc(db, "tasks", "t_pending"), { ...base, status: "pending_worker_acceptance", targetHelperUid: "target", applicants: ["target", "other"], bids: { other: 90, target: 100 }, proposedPrice: 100 });
      await setDoc(doc(db, "tasks", "t_assigned"), { ...base, status: "assigned", acceptedByUid: "worker", applicants: ["worker", "other"], bids: { worker: 100, other: 90 }, proposedPrice: 100 });
      await setDoc(doc(db, "tasks", "t_direct"), { ...base, status: "pending_worker_acceptance", directRequest: true, targetHelperUid: "target", applicants: ["target"], bids: { target: 100 }, proposedPrice: 100, endTime: future });
      await setDoc(doc(db, "tasks", "t_done"), { ...base, status: "completed", acceptedByUid: "worker", applicants: ["worker"], bids: { worker: 100 }, workerRating: 5 });
      await setDoc(doc(db, "tasks", "t_done2"), { ...base, status: "completed", acceptedByUid: "worker", applicants: ["worker"], bids: { worker: 100 }, workerRating: 4 });
      await setDoc(doc(db, "tasks", "t_assigned_b"), { ...base, status: "assigned", acceptedByUid: "target", applicants: ["target"], bids: { target: 100 }, proposedPrice: 100 });
      await setDoc(doc(db, "tasks", "t_assigned", "taskLog", "l1"), { action: "assigned", actorUid: "worker" });
      await setDoc(doc(db, "tasks", "t_open", "taskLog", "l1"), { action: "task_created", actorUid: "poster" });
      await setDoc(doc(db, "reviews", "t_done"), { taskId: "t_done", workerUid: "worker", posterUid: "poster", rating: 5, category: "Repairs" });
    });
  }

  const as = (uid) => env.authenticatedContext(uid).firestore();
  const tasks = (db) => collection(db, "tasks");
  // Creates a user doc as that user (goes through the rules, like the Terms screen does).
  const setDocAs = (uid, data) => setDoc(doc(as(uid), "users", uid), data, { merge: true });
  // The payment switch the owner controls from the admin panel (metadata/paymentConfig).
  const putConfig = (on) => env.withSecurityRulesDisabled(async (ctx) => setDoc(doc(ctx.firestore(), "metadata", "paymentConfig"), { useRazorpay: on }));

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
  await check("poster of an assigned task can create its review (in the batch that completes it)", () => ok(completeBatch(as("poster"))));
  await seed();
  await check("a review on its own, without completing the task, is refused", () => no(setDoc(doc(as("poster"), "reviews", "t_assigned"),
    { taskId: "t_assigned", workerUid: "worker", posterUid: "poster", rating: 4, category: "Repairs", createdAt: serverTimestamp() })));
  await check("a review whose rating differs from the task's rating is refused", () => no((async () => {
    const db = as("poster"); const b = writeBatch(db);
    b.set(doc(db, "tasks", "t_assigned"), { status: "completed", completedAt: serverTimestamp(), workerRating: 2 }, { merge: true });
    b.set(doc(db, "reviews", "t_assigned"), { taskId: "t_assigned", workerUid: "worker", posterUid: "poster", rating: 5, category: "Repairs", createdAt: serverTimestamp() });
    return b.commit();
  })()));
  await check("a review for a task that is already completed is refused", () => no(setDoc(doc(as("poster"), "reviews", "t_done2"),
    { taskId: "t_done2", workerUid: "worker", posterUid: "poster", rating: 5, category: "Repairs", createdAt: serverTimestamp() })));
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

  // ───────────────────────────── PRIVATE DIRECT REQUESTS ─────────────────────────────
  console.log("\n[Private direct requests: hire one helper without posting publicly]");
  await seed();
  const directDoc = (extra = {}) => ({ postedByUid: "poster", postedByName: "Poster", title: "Fix tap", description: "d", price: 300,
    category: "Repairs", city: "Surat", isUrgent: false, status: "pending_worker_acceptance", directRequest: true, targetHelperUid: "target",
    proposedPrice: 300, proposedAt: serverTimestamp(), applicants: ["target"], bids: { target: 300 }, createdAt: serverTimestamp(), endTime: future, ...extra });
  await check("the poster can send a private request to one helper", () => ok(addDoc(tasks(as("poster")), directDoc())));
  await check("a normal open task can still be posted", () => ok(addDoc(tasks(as("poster")), { postedByUid: "poster", postedByName: "Poster", title: "Fix tap",
    description: "d", price: 300, category: "Repairs", city: "Surat", isUrgent: false, status: "open", targetHelperUid: null, applicants: [], bids: {},
    createdAt: serverTimestamp(), endTime: future })));
  await check("a request cannot be sent to yourself", () => no(addDoc(tasks(as("poster")), directDoc({ targetHelperUid: "poster" }))));
  await check("a private request must name a helper", () => no(addDoc(tasks(as("poster")), directDoc({ targetHelperUid: null }))));
  await check("a task cannot be created already hired out", () => no(addDoc(tasks(as("poster")), directDoc({ status: "assigned", acceptedByUid: "worker" }))));
  await check("a task cannot be created already completed", () => no(addDoc(tasks(as("poster")), directDoc({ status: "completed" }))));
  await check("someone else cannot send a request in the poster's name", () => no(addDoc(tasks(as("other")), directDoc())));
  await check("the named helper can read the private request", () => ok(getDoc(doc(as("target"), "tasks", "t_direct"))));
  await check("the poster can read it", () => ok(getDoc(doc(as("poster"), "tasks", "t_direct"))));
  await check("a stranger cannot read it", () => no(getDoc(doc(as("other"), "tasks", "t_direct"))));
  await check("it is not in the public list (open tasks in the city)", async () => {
    const snap = await getDocs(query(tasks(as("other")), where("city", "==", "Surat"), where("status", "==", "open")));
    assert.ok(!snap.docs.some((d) => d.id === "t_direct"));
  });
  await check("the helper sees it in their offers", async () => {
    const snap = await getDocs(query(tasks(as("target")), where("targetHelperUid", "==", "target")));
    assert.ok(snap.docs.some((d) => d.id === "t_direct"));
  });
  await check("the helper accepts: it becomes assigned", () => ok(updateDoc(doc(as("target"), "tasks", "t_direct"),
    { status: "assigned", acceptedByUid: "target", assignedAt: serverTimestamp(), "bids.target": 100 })));
  await seed();
  await check("the helper asks for another price", () => ok(updateDoc(doc(as("target"), "tasks", "t_direct"),
    { status: "pending_poster_acceptance", proposedPrice: 150, proposedAt: serverTimestamp() })));
  await seed();
  await check("the helper declines: the request ends as declined", () => ok(updateDoc(doc(as("target"), "tasks", "t_direct"), { status: "declined" })));
  await seed();
  await check("a declined private request can NOT be turned into an open task", () => no(updateDoc(doc(as("target"), "tasks", "t_direct"),
    { status: "open", targetHelperUid: deleteField(), proposedPrice: deleteField(), proposedAt: deleteField() })));
  await check("the poster cannot publish it either by declining to 'open'", () => no(updateDoc(doc(as("poster"), "tasks", "t_direct"),
    { status: "open", targetHelperUid: deleteField(), proposedPrice: deleteField(), proposedAt: deleteField() })));
  await check("declining a PUBLIC offer still returns it to open", () => ok(updateDoc(doc(as("target"), "tasks", "t_pending"),
    { status: "open", targetHelperUid: deleteField(), proposedPrice: deleteField(), proposedAt: deleteField() })));
  await seed();
  await check("a hired-out task cannot be flipped back to open by a 'decline'", () => no(updateDoc(doc(as("poster"), "tasks", "t_assigned"),
    { status: "open", targetHelperUid: deleteField(), proposedPrice: deleteField(), proposedAt: deleteField() })));
  await check("a stranger cannot decline someone else's private request", () => no(updateDoc(doc(as("other"), "tasks", "t_direct"), { status: "declined" })));
  await seed();

  console.log("\n[Cash fees owed and the linked UPI id]");
  await seed();
  await check("an owner cannot clear or change their own fee owed", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => updateDoc(doc(ctx.firestore(), "users", "worker"), { feeDue: 90 }));
    await no(updateDoc(doc(as("worker"), "users", "worker"), { feeDue: 0 }));
    await no(updateDoc(doc(as("worker"), "users", "worker"), { feeDue: increment(-90) }));
  });
  await check("nobody can put a fee on someone else from the app", () => no(updateDoc(doc(as("poster"), "users", "worker"), { feeDue: increment(30) })));
  await check("a poster's rating update cannot carry a fee along", () => no(updateDoc(doc(as("poster"), "users", "worker"),
    { feeDue: increment(30), ratingSum: increment(5), ratingCount: increment(1), tasksDone: increment(1) })));
  await check("an admin can waive a fee", () => ok(updateDoc(doc(as("admin"), "users", "worker"), { feeDue: 0 })));
  await check("a new profile cannot start with a fee owed or any earnings", () => no(setDoc(doc(env.authenticatedContext("fresh9").firestore(), "users", "fresh9"), { feeDue: 50 })));
  await check("an owner can link a well-formed UPI id", () => ok(updateDoc(doc(as("worker"), "users", "worker"), { upiId: "meera@okhdfc" })));
  await check("...and change it", () => ok(updateDoc(doc(as("worker"), "users", "worker"), { upiId: "9876543210@ybl" })));
  await check("...and remove it", () => ok(updateDoc(doc(as("worker"), "users", "worker"), { upiId: deleteField() })));
  await check("a UPI id that is not one is refused", () => no(updateDoc(doc(as("worker"), "users", "worker"), { upiId: "just some text" })));
  await check("a UPI id that is not a string is refused", () => no(updateDoc(doc(as("worker"), "users", "worker"), { upiId: 12345 })));
  await check("nobody can change someone else's UPI id", () => no(updateDoc(doc(as("other"), "users", "worker"), { upiId: "thief@okhdfc" })));
  await check("a profile cannot be created with a bad UPI id", () => no(setDoc(doc(env.authenticatedContext("fresh10").firestore(), "users", "fresh10"), { upiId: "not valid" })));
  await check("payout accounts cannot be read or written by anyone, not even an admin", async () => {
    await no(getDoc(doc(as("worker"), "payoutAccounts", "worker")));
    await no(getDoc(doc(as("admin"), "payoutAccounts", "worker")));
    await no(setDoc(doc(as("worker"), "payoutAccounts", "worker"), { contactId: "cont_x" }));
    await no(setDoc(doc(as("admin"), "payoutAccounts", "worker"), { contactId: "cont_x" }));
  });
  await check("cash-job fields on a task cannot be written by the poster or the helper", async () => {
    await no(updateDoc(doc(as("poster"), "tasks", "t_assigned"), { cashClaimedAt: serverTimestamp(), cashClaimRating: 5 }));
    await no(updateDoc(doc(as("worker"), "tasks", "t_assigned"), { paidInCash: true, cashFee: 0 }));
    await no(updateDoc(doc(as("poster"), "tasks", "t_assigned"), { status: "completed", completedAt: serverTimestamp(), workerRating: 5, paidInCash: true }));
  });
  await seed();

  // ───────────────────────── COMPLETING A TASK ─────────────────────────
  // Payments OFF: nothing is charged, the poster closes the task and rates the helper.
  // Payments ON (Razorpay): only the payment Cloud Function (Admin SDK, not tested here) can.
  console.log("\n[Closing a task while payments are OFF: completeTaskWithoutPayment batch]");
  function completeBatch(db, { taskId = "t_assigned", extraTask = {} } = {}) {
    const b = writeBatch(db);
    b.set(doc(db, "tasks", taskId), { status: "completed", completedAt: serverTimestamp(), workerRating: 5, ...extraTask }, { merge: true });
    b.set(doc(db, "reviews", taskId), { taskId, workerUid: "worker", posterUid: "poster", rating: 5, category: "Repairs", createdAt: serverTimestamp() });
    b.set(doc(db, "users", "worker"), { ratingSum: increment(5), ratingCount: increment(1), tasksDone: increment(1), lastRatedTaskId: taskId }, { merge: true });
    return b.commit();
  }
  // Same batch, but with every part adjustable, to prove each link in the chain is enforced.
  function rateBatch(db, { taskId = "t_assigned", helper = "worker", linkTask = taskId, workerRating = 5, sum = 5, count = 1, done = 1,
    completeTask = true, extraUser = {} } = {}) {
    const b = writeBatch(db);
    if (completeTask) b.set(doc(db, "tasks", taskId), { status: "completed", completedAt: serverTimestamp(), workerRating }, { merge: true });
    b.set(doc(db, "users", helper), { ratingSum: increment(sum), ratingCount: increment(count), tasksDone: increment(done),
      ...(linkTask ? { lastRatedTaskId: linkTask } : {}), ...extraUser }, { merge: true });
    return b.commit();
  }
  await seed();
  await check("with no payment settings at all the poster completes the task and rates the helper", () => ok(completeBatch(as("poster"))));
  await seed(); await putConfig(false);
  await check("with payments switched off it is accepted too", () => ok(completeBatch(as("poster"))));
  await seed(); await putConfig(true);
  await check("while Razorpay is ON the app cannot complete a task for free", () => no(completeBatch(as("poster"))));
  await check("...not even the task update alone", () => no(updateDoc(doc(as("poster"), "tasks", "t_assigned"), { status: "completed", completedAt: serverTimestamp(), workerRating: 5 })));
  await check("...nor the review alone", () => no(setDoc(doc(as("poster"), "reviews", "t_assigned"), { taskId: "t_assigned", workerUid: "worker", posterUid: "poster", rating: 5, category: "Repairs", createdAt: serverTimestamp() })));
  await check("...nor a rating bump on the helper", () => no(updateDoc(doc(as("poster"), "users", "worker"), { ratingSum: increment(5), ratingCount: increment(1), tasksDone: increment(1) })));
  await seed();
  await check("a stranger cannot run the completion batch", () => no(completeBatch(as("other"))));
  await seed();
  await check("the poster cannot write payment records on the task (amountPaidByPoster)", () => no(completeBatch(as("poster"), { extraTask: { amountPaidByPoster: 1, finalPricePaid: 1 } })));
  await seed();
  await check("the poster cannot mark a Razorpay payment on the task", () => no(completeBatch(as("poster"), { extraTask: { paidViaRazorpay: true } })));
  await seed();
  await check("a task that is not hired out yet cannot be completed", () => no(completeBatch(as("poster"), { taskId: "t_open" })));
  await check("a completed task cannot be completed again", () => no(completeBatch(as("poster"), { taskId: "t_done" })));

  console.log("\n[Earnings & ratings: nobody can mint money or reputation]");
  await seed();
  await check("a user cannot raise their OWN earnings", () => no(updateDoc(doc(as("other"), "users", "other"), { earnings: increment(1000) })));
  await check("a user cannot SET their own earnings to a big number", () => no(setDoc(doc(as("other"), "users", "other"), { earnings: 99999 }, { merge: true })));
  await check("a user cannot drain someone ELSE's earnings", () => no(updateDoc(doc(as("other"), "users", "worker"), { earnings: increment(-100) })));
  await check("a poster cannot credit a helper's earnings from the app", () => no(updateDoc(doc(as("poster"), "users", "worker"), { earnings: increment(100) })));
  await check("a user cannot inflate their own rating", () => no(updateDoc(doc(as("other"), "users", "other"), { ratingSum: increment(500), ratingCount: increment(1) })));
  await check("a user cannot inflate their own tasksDone", () => no(updateDoc(doc(as("other"), "users", "other"), { tasksDone: increment(50) })));
  await check("a user CAN lower their own earnings (that is what a withdrawal does)", () => ok(updateDoc(doc(as("other"), "users", "other"), { earnings: 400 })));
  await check("a bare rating bump on someone, tied to no task, is refused (the old hole)", () => no(updateDoc(doc(as("poster"), "users", "worker"),
    { ratingSum: increment(5), ratingCount: increment(1), tasksDone: increment(1) })));
  await check("...even when it names a task but the task is not completed in the same batch", () => no(rateBatch(as("poster"), { completeTask: false })));
  await check("a rating given together with completing the hired task works", () => ok(rateBatch(as("poster"))));
  await seed();
  await check("a rating cannot name a task the poster did not post (rating a friend up)", () => no(rateBatch(as("other"), { taskId: "t_assigned" })));
  await check("a rating cannot be given to someone who was not hired for that task", () => no(rateBatch(as("poster"), { helper: "target" })));
  await check("a rating cannot name a task that is already completed (second rating)", () => no(rateBatch(as("poster"), { taskId: "t_done2", completeTask: false, linkTask: "t_done2" })));
  await check("a rating cannot name another task than the one being completed", () => no(rateBatch(as("poster"), { linkTask: "t_done2" })));
  await check("the rating added must equal the rating on the task", () => no(rateBatch(as("poster"), { workerRating: 1, sum: 5 })));
  await check("a huge rating bump is refused", () => no(rateBatch(as("poster"), { workerRating: 5, sum: 500, count: 100, done: 100 })));
  await check("two ratings or two tasks in one go are refused", () => no(rateBatch(as("poster"), { count: 2 })));
  await check("a rating of 0 or above 5 is refused", async () => {
    await no(rateBatch(as("poster"), { workerRating: 0, sum: 0 }));
    await no(rateBatch(as("poster"), { workerRating: 9, sum: 9 }));
  });
  await check("a rating bump cannot ride along with an earnings change", () => no(rateBatch(as("poster"), { extraUser: { earnings: increment(180) } })));
  await check("a poster cannot rate their own account up", () => no(rateBatch(as("poster"), { helper: "poster" })));
  await check("admin can set any earnings", () => ok(updateDoc(doc(as("admin"), "users", "worker"), { earnings: 777 })));

  console.log("\n[Earnings history: nobody writes into someone else's]");
  await seed();
  const txDoc = (extra = {}) => ({ amount: 100, type: "credit", title: "Earned from task", razorpay: true, timestamp: serverTimestamp(), ...extra });
  await check("a user cannot invent a credit / payment line in their own history", () => no(addDoc(collection(as("worker"), "users", "worker", "transactions"), txDoc())));
  await check("nor a debit line that names no real withdrawal", () => no(addDoc(collection(as("worker"), "users", "worker", "transactions"), txDoc({ type: "debit", withdrawalId: "nope" }))));
  const wdBatch = (db, { amount = 200, txAmount = amount, uid = "worker" } = {}) => {
    const b = writeBatch(db);
    b.set(doc(db, "withdrawals", "wtx"), { uid, amount, paymentDetails: "ravi.k@okhdfc", userName: "W", status: "pending", timestamp: serverTimestamp() });
    b.update(doc(db, "users", uid), { earnings: increment(-amount) });
    b.set(doc(db, "users", uid, "transactions", "tx1"), { amount: txAmount, type: "debit", razorpay: true, title: "Withdrawal requested", withdrawalId: "wtx", timestamp: serverTimestamp() });
    return b.commit();
  };
  await check("the 'withdrawal requested' line is allowed in the same batch as its withdrawal", () => ok(wdBatch(as("worker"))));
  await seed();
  await check("...but not with a different amount than the withdrawal", () => no(wdBatch(as("worker"), { amount: 200, txAmount: 5 })));
  await check("a poster cannot write an entry into the helper's history", () => no(addDoc(collection(as("poster"), "users", "worker", "transactions"), txDoc())));
  await check("a stranger cannot write into anyone's history", () => no(addDoc(collection(as("other"), "users", "target", "transactions"), txDoc())));
  await check("an admin can write a history entry (refund)", () => ok(addDoc(collection(as("admin"), "users", "worker", "transactions"), txDoc())));
  await check("an entry cannot be edited afterwards", async () => {
    const ref = await addDoc(collection(as("admin"), "users", "worker", "transactions"), txDoc());
    await no(updateDoc(doc(as("worker"), "users", "worker", "transactions", ref.id), { amount: 99999 }));
  });
  await check("only the owner reads their history", async () => {
    await ok(getDocs(collection(as("worker"), "users", "worker", "transactions")));
    await no(getDocs(collection(as("other"), "users", "worker", "transactions")));
  });

  console.log("\n[User profile: every way the app writes its own document]");
  await seed();
  const fresh = () => env.authenticatedContext("newbie").firestore();
  await check("terms screen creates the doc (termsAccepted only)", () => ok(setDoc(doc(fresh(), "users", "newbie"), { termsAccepted: true, termsAcceptedAt: serverTimestamp() }, { merge: true })));
  const firstSave = (extra) => ({ uid: "newbie", email: "n@x.com", fullName: "New Bie", phone: "+919000000000", gender: "Male", city: "Surat",
    qualifications: "Plumber", updatedAt: serverTimestamp(), createdAt: serverTimestamp(), ratingSum: 0, ratingCount: 0,
    tasksDone: 0, isOpenForWork: false, ...extra });
  await check("first profile save WITHOUT an ID photo ('Not Uploaded')", () => ok(setDoc(doc(fresh(), "users", "newbie"), firstSave({ idProofStatus: "Not Uploaded" }), { merge: true })));
  await seed();
  await setDocAs("newbie", { termsAccepted: true });
  await check("first profile save WITH an ID photo ('Pending Verification')", () => ok(setDoc(doc(fresh(), "users", "newbie"), firstSave({ idProofStatus: "Pending Verification" }), { merge: true })));
  await seed();
  await setDocAs("newbie", { termsAccepted: true });
  await check("first save cannot start with earnings", () => no(setDoc(doc(fresh(), "users", "newbie"), firstSave({ idProofStatus: "Not Uploaded", earnings: 99999 }), { merge: true })));
  await check("first save cannot start with a pre-made rating", () => no(setDoc(doc(fresh(), "users", "newbie"), firstSave({ idProofStatus: "Not Uploaded", ratingSum: 50, ratingCount: 10 }), { merge: true })));
  await check("first save cannot claim 'Verified'", () => no(setDoc(doc(fresh(), "users", "newbie"), firstSave({ idProofStatus: "Verified" }), { merge: true })));
  await seed();
  await check("a brand-new user cannot create a doc with earnings", () => no(setDoc(doc(env.authenticatedContext("fresh2").firestore(), "users", "fresh2"), { earnings: 99999 })));
  console.log("\n[Withdrawal requests]");
  const wd = (extra = {}) => ({ uid: "worker", amount: 200, paymentDetails: "ravi.k@okhdfc", userName: "Worker", status: "pending", timestamp: serverTimestamp(), ...extra });
  // Request + hold of the earnings in one batch, exactly as the app does it. The seeded earnings are Rs 500.
  const requestWd = async (data, left = 300, uid = "worker") => {
    const db = as(uid);
    const b = writeBatch(db);
    b.set(doc(db, "withdrawals", "req1"), data);
    b.update(doc(db, "users", uid), { earnings: left });
    return b.commit();
  };
  await seed();
  await check("a withdrawal (earnings held by the same amount) is accepted", () => ok(requestWd(wd())));
  await seed();
  await check("the app's own way (increment(-amount)) is accepted", async () => {
    const db = as("worker");
    const b = writeBatch(db);
    b.set(doc(db, "withdrawals", "req1"), wd());
    b.update(doc(db, "users", "worker"), { earnings: increment(-200) });
    return ok(b.commit());
  });
  await seed();
  await check("earnings reduced by LESS than the amount is refused", () => no(requestWd(wd(), 400)));
  await seed();
  await check("earnings reduced by MORE than the amount is refused", () => no(requestWd(wd(), 100)));
  await seed();
  await check("a request without touching the earnings is refused", () => no(setDoc(doc(as("worker"), "withdrawals", "req1"), wd())));
  await seed();
  await check("more than the earnings is refused", () => no(requestWd(wd({ amount: 600 }), -100)));
  await seed();
  await check("below the Rs 100 minimum is refused", () => no(requestWd(wd({ amount: 50 }), 450)));
  console.log("\n[Smallest withdrawal set by the owner]");
  const putMin = (min) => env.withSecurityRulesDisabled(async (ctx) => setDoc(doc(ctx.firestore(), "metadata", "paymentConfig"), { useRazorpay: true, minWithdrawal: min }));
  await seed();
  await check("no number saved: the default 100 applies, 99 is refused", () => no(requestWd(wd({ amount: 99 }), 401)));
  await seed();
  await check("no number saved: exactly 100 is accepted", () => ok(requestWd(wd({ amount: 100 }), 400)));
  await seed(); await putConfig(true);
  await check("a payment config WITHOUT a number behaves the same (99 refused)", () => no(requestWd(wd({ amount: 99 }), 401)));
  await seed(); await putMin(10);
  await check("owner set 10: 10 is accepted", () => ok(requestWd(wd({ amount: 10 }), 490)));
  await seed(); await putMin(10);
  await check("owner set 10: 9 is still refused", () => no(requestWd(wd({ amount: 9 }), 491)));
  await seed(); await putMin(1);
  await check("owner set 1: a single rupee is accepted", () => ok(requestWd(wd({ amount: 1 }), 499)));
  await seed(); await putMin(300);
  await check("owner set 300: 200 is refused", () => no(requestWd(wd({ amount: 200 }), 300)));
  await seed(); await putMin(300);
  await check("owner set 300: 300 is accepted", () => ok(requestWd(wd({ amount: 300 }), 200)));
  for (const bad of [0, -5, 1.5, "10", 100001, true]) {
    await seed(); await putMin(bad);
    await check(`an unusable number (${JSON.stringify(bad)}) never lowers the bar: 50 is refused`, () => no(requestWd(wd({ amount: 50 }), 450)));
  }
  await seed(); await putMin(10);
  await check("the largest withdrawal is unchanged: 100001 is refused whatever the minimum", () => no(requestWd(wd({ amount: 100001 }), -99501)));
  await seed(); await putMin(10);
  await check("a normal user still cannot change the minimum", () => no(setDoc(doc(as("worker"), "metadata", "paymentConfig"), { useRazorpay: true, minWithdrawal: 1 })));
  await seed(); await putMin(10);
  await check("an admin can", () => ok(setDoc(doc(as("admin"), "metadata", "paymentConfig"), { useRazorpay: true, minWithdrawal: 5 })));
  await seed();
  await check("a UPI id that is not a UPI id is refused", () => no(requestWd(wd({ paymentDetails: "just some text" }))));
  await seed();
  await check("an extra field is refused", () => no(requestWd(wd({ approvedByAdmin: true }))));
  await seed();
  await check("creating it as already 'approved' is refused", () => no(requestWd(wd({ status: "approved" }))));
  await seed();
  await check("asking in someone else's name is refused", () => no(requestWd(wd({ uid: "other" }))));
  await seed();
  await check("a banned user cannot request", () => no(requestWd(wd({ uid: "banned" }), 300, "banned")));
  await seed(); await putConfig(false);
  await check("earnings already made stay withdrawable when payments are switched off later", () => ok(requestWd(wd())));
  await seed(); await putConfig(true);
  await requestWd(wd());
  await check("the requester cannot approve their own request", () => no(updateDoc(doc(as("worker"), "withdrawals", "req1"), { status: "approved" })));
  await check("the requester can read their request", () => ok(getDoc(doc(as("worker"), "withdrawals", "req1"))));
  await check("someone else cannot read it", () => no(getDoc(doc(as("other"), "withdrawals", "req1"))));
  await check("an admin can mark it paid with a reference", () => ok(updateDoc(doc(as("admin"), "withdrawals", "req1"), { status: "approved", paidReference: "UTR123", processedAt: serverTimestamp() })));
  await seed();
  await check("a brand-new user cannot create themselves as an admin-flagged/unbanned user", () => no(setDoc(doc(env.authenticatedContext("fresh3").firestore(), "users", "fresh3"), { canPost: true })));
  const IDURL = "https://firebasestorage.googleapis.com/v0/b/chal-bro.appspot.com/o/id_proofs%2Fother.jpg?alt=media&token=abc";
  await check("upload ID photo: the link goes to the private document, the profile only gets a flag + status", async () => {
    await ok(setDoc(doc(as("other"), "users", "other", "private", "idProof"), { url: IDURL, path: "id_proofs/other.jpg", updatedAt: serverTimestamp() }));
    await ok(updateDoc(doc(as("other"), "users", "other"), { hasIdProof: true, idProofStatus: "Pending Verification", idProofUrl: deleteField(), updatedAt: serverTimestamp() }));
  });
  await check("the ID photo link is readable by its owner and by admins only", async () => {
    await ok(getDoc(doc(as("other"), "users", "other", "private", "idProof")));
    await ok(getDoc(doc(as("admin"), "users", "other", "private", "idProof")));
    await no(getDoc(doc(as("worker"), "users", "other", "private", "idProof")));
    await no(getDoc(doc(as("poster"), "users", "other", "private", "idProof")));
  });
  await check("nobody can write a private document for someone else, or any other document name", async () => {
    await no(setDoc(doc(as("worker"), "users", "other", "private", "idProof"), { url: IDURL, path: "id_proofs/other.jpg" }));
    await no(setDoc(doc(as("other"), "users", "other", "private", "bank"), { url: IDURL, path: "id_proofs/other.jpg" }));
  });
  await check("the private link must be a Firebase Storage link to the owner's own ID file", async () => {
    await no(setDoc(doc(as("other"), "users", "other", "private", "idProof"), { url: "https://evil.example/x.jpg", path: "id_proofs/other.jpg" }));
    await no(setDoc(doc(as("other"), "users", "other", "private", "idProof"), { url: IDURL, path: "id_proofs/worker.jpg" }));
    await no(setDoc(doc(as("other"), "users", "other", "private", "idProof"), { url: IDURL, path: "id_proofs/other.jpg", extra: 1 }));
  });
  await check("a profile can still be written with the old idProofUrl (older app builds)", () => ok(updateDoc(doc(as("other"), "users", "other"), { idProofUrl: "https://x/y", idProofStatus: "Pending Verification", updatedAt: serverTimestamp() })));
  await check("a new profile cannot be created already 'Verified'", () => no(setDoc(doc(env.authenticatedContext("fresh20").firestore(), "users", "fresh20"), { fullName: "F", idProofStatus: "Verified" })));
  await check("a new profile can be created 'Not Uploaded' or 'Pending Verification'", async () => {
    await ok(setDoc(doc(env.authenticatedContext("fresh21").firestore(), "users", "fresh21"), { fullName: "F", idProofStatus: "Not Uploaded" }));
    await ok(setDoc(doc(env.authenticatedContext("fresh22").firestore(), "users", "fresh22"), { fullName: "F", idProofStatus: "Pending Verification" }));
  });
  await check("a user cannot approve their own ID", () => no(updateDoc(doc(as("other"), "users", "other"), { idProofStatus: "Verified" })));
  await check("a user cannot un-ban or un-pause themselves", () => no(updateDoc(doc(as("banned"), "users", "banned"), { isBanned: false })));
  await check("profile photo", () => ok(updateDoc(doc(as("other"), "users", "other"), { profilePhotoUrl: "https://x/p.jpg" })));
  await check("settings: name/phone/skills/city", () => ok(updateDoc(doc(as("other"), "users", "other"), { fullName: "N", phone: "+91", qualifications: "q", city: "Surat" })));
  await check("settings: open-for-work, hide-from-search, leaderboard toggles", () => ok(setDoc(doc(as("other"), "users", "other"), { isOpenForWork: true, isHiddenFromSearch: true, leaderboardOptIn: true }, { merge: true })));
  await check("push token registration (arrayUnion)", () => ok(setDoc(doc(as("other"), "users", "other"), { fcmTokens: arrayUnion("tok") }, { merge: true })));
  await check("someone else cannot edit my profile", () => no(updateDoc(doc(as("other"), "users", "worker"), { fullName: "Hacked" })));
  await check("admin approves an ID", () => ok(updateDoc(doc(as("admin"), "users", "other"), { idProofStatus: "Verified", canPost: true })));
  await check("admin bans a user", () => ok(updateDoc(doc(as("admin"), "users", "other"), { isBanned: true })));
  await check("a banned user cannot delete their profile to wipe the ban and re-create it", () => no(env.authenticatedContext("other").firestore().doc("users/other").delete()));
  await seed();
  await check("Delete Account: a user in good standing deletes their own profile", () => ok(env.authenticatedContext("other").firestore().doc("users/other").delete()));
  await check("a user cannot delete someone else's profile", () => no(env.authenticatedContext("other").firestore().doc("users/worker").delete()));
  await check("a user who still owes a cash-job fee cannot delete the profile (fee would vanish)", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => updateDoc(doc(ctx.firestore(), "users", "worker"), { feeDue: 90 }));
    await no(env.authenticatedContext("worker").firestore().doc("users/worker").delete());
  });
  await check("an admin can delete any profile", () => ok(env.authenticatedContext("admin").firestore().doc("users/worker").delete()));
  await seed();

  console.log("\n[Notifications: sender cannot be spoofed]");
  await check("send a notification as yourself", () => ok(addDoc(collection(as("poster"), "users", "target", "notifications"), { fromUid: "poster", title: "Hi", message: "m", isRead: false, createdAt: serverTimestamp() })));
  await check("cannot send a notification pretending to be someone else", () => no(addDoc(collection(as("poster"), "users", "target", "notifications"), { fromUid: "admin", title: "Hi", message: "m", isRead: false, createdAt: serverTimestamp() })));

  console.log("\n[Admin panel: task management]");
  await seed();
  await check("admin force-closes a hired task (admin panel updateTaskStatus)", () => ok(updateDoc(doc(as("admin"), "tasks", "t_assigned"), { status: "cancelled" })));
  await check("admin deletes a task", () => ok(env.authenticatedContext("admin").firestore().doc("tasks/t_done").delete()));
  await check("a normal user still cannot force a status on someone's task", () => no(updateDoc(doc(as("other"), "tasks", "t_pending"), { status: "cancelled" })));
  await check("admin changes earnings and logs the action", async () => {
    await ok(updateDoc(doc(as("admin"), "users", "worker"), { earnings: increment(-50) }));
    await ok(addDoc(collection(as("admin"), "adminLogs"), { adminUid: "admin", action: "earnings_adjusted", targetId: "worker", timestamp: serverTimestamp() }));
  });
  await check("admin processes a withdrawal (status + refund)", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => setDoc(doc(ctx.firestore(), "withdrawals", "w1"), { uid: "worker", amount: 100, status: "pending" }));
    const adminDb = as("admin");
    const b = writeBatch(adminDb);
    b.update(doc(adminDb, "withdrawals", "w1"), { status: "rejected", processedAt: serverTimestamp() });
    b.update(doc(adminDb, "users", "worker"), { earnings: increment(100) });
    await ok(b.commit());
  });
  await check("admin reads every transaction (collection group)", () => ok(getDocs(env.authenticatedContext("admin").firestore().collectionGroup("transactions"))));

  console.log("\n[Admin: payment settings document]");
  await check("admin can write metadata/paymentConfig", () => ok(setDoc(doc(as("admin"), "metadata", "paymentConfig"), { useRazorpay: false, discountEnabled: true, discountPercent: 10 })));
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

  // ───────────────────────── SECURITY REVIEW 2026-10-14 ─────────────────────────
  console.log("\n[Notifications: fixed shape, no arbitrary content]");
  await seed();
  const nCol = (db, uid = "target") => collection(db, "users", uid, "notifications");
  const goodN = (extra = {}) => ({ fromUid: "poster", taskId: "t_open", title: "New Applicant!", message: "A helper applied", isRead: false, createdAt: serverTimestamp(), ...extra });
  await check("the app's notification (task id, type) is accepted", () => ok(addDoc(nCol(as("poster")), goodN({ type: "task_proposed" }))));
  await check("every real notification type is accepted", async () => {
    for (const t of ["offer_accepted", "offer_declined", "offer_revised", "worker_done", "task_completed"]) await ok(addDoc(nCol(as("poster")), goodN({ type: t })));
  });
  await check("a made-up type (e.g. to fake a payment notice) is refused", () => no(addDoc(nCol(as("poster")), goodN({ type: "payment_received" }))));
  await check("an extra field is refused", () => no(addDoc(nCol(as("poster")), goodN({ deepLink: "https://evil.example" }))));
  await check("a 5,000-character message is refused", () => no(addDoc(nCol(as("poster")), goodN({ message: "x".repeat(5000) }))));
  await check("a back-dated or already-read notification is refused", async () => {
    await no(addDoc(nCol(as("poster")), goodN({ createdAt: Timestamp.fromMillis(1000) })));
    await no(addDoc(nCol(as("poster")), goodN({ isRead: true })));
  });
  await check("a banned user cannot send notifications", () => no(addDoc(nCol(as("banned")), goodN({ fromUid: "banned" }))));

  console.log("\n[Task tampering: applicants, hiring, states, deletion, creation]");
  await seed();
  await check("applying cannot remove other applicants from the list", () => no(updateDoc(doc(as("target"), "tasks", "t_open"), { applicants: ["target"], "bids.target": 120 })));
  await check("applying cannot add other people to the list", () => no(updateDoc(doc(as("target"), "tasks", "t_open"), { applicants: arrayUnion("target", "sock1"), "bids.target": 120 })));
  await check("a bid must be a positive number", async () => {
    await no(updateDoc(doc(as("target"), "tasks", "t_open"), { applicants: arrayUnion("target"), "bids.target": 0 }));
    await no(updateDoc(doc(as("target"), "tasks", "t_open"), { applicants: arrayUnion("target"), "bids.target": -5 }));
    await no(updateDoc(doc(as("target"), "tasks", "t_open"), { applicants: arrayUnion("target"), "bids.target": "cheap" }));
  });
  await check("the poster cannot apply to their own task", () => no(updateDoc(doc(as("poster"), "tasks", "t_open"), { applicants: arrayUnion("poster"), "bids.poster": 10 })));
  await check("an existing applicant can change their own bid", () => ok(updateDoc(doc(as("other"), "tasks", "t_open"), { applicants: arrayUnion("other"), "bids.other": 80 })));
  await check("the poster cannot hire someone who was never offered the job (force-assign a sock puppet)", () => no(updateDoc(doc(as("poster"), "tasks", "t_open"),
    { status: "assigned", acceptedByUid: "sock", assignedAt: serverTimestamp(), "bids.sock": 1 })));
  await check("the poster cannot hire the helper on an offer the helper has not accepted", () => no(updateDoc(doc(as("poster"), "tasks", "t_pending"),
    { status: "assigned", acceptedByUid: "target", assignedAt: serverTimestamp(), "bids.target": 100 })));
  await check("a finished task cannot be re-opened as 'assigned' to be rated again", () => no(updateDoc(doc(as("poster"), "tasks", "t_done2"),
    { status: "assigned", acceptedByUid: "worker", assignedAt: serverTimestamp(), "bids.worker": 100 })));
  await check("a hired or finished task cannot be pushed back into a proposal", async () => {
    await no(updateDoc(doc(as("poster"), "tasks", "t_assigned"), { status: "pending_worker_acceptance", targetHelperUid: "other", applicants: arrayUnion("other"), proposedPrice: 10, proposedAt: serverTimestamp() }));
    await no(updateDoc(doc(as("poster"), "tasks", "t_done2"), { status: "pending_worker_acceptance", targetHelperUid: "worker", applicants: arrayUnion("worker"), proposedPrice: 10, proposedAt: serverTimestamp() }));
  });
  await check("a counter-offer cannot be used on a hired or finished task", async () => {
    await no(updateDoc(doc(as("poster"), "tasks", "t_assigned"), { status: "pending_worker_acceptance", proposedPrice: 10, proposedAt: serverTimestamp() }));
    await no(updateDoc(doc(as("worker"), "tasks", "t_done2"), { status: "pending_poster_acceptance", proposedPrice: 10, proposedAt: serverTimestamp() }));
  });
  await check("the poster can accept the helper's counter-offer", async () => {
    await ok(updateDoc(doc(as("target"), "tasks", "t_direct"), { status: "pending_poster_acceptance", proposedPrice: 150, proposedAt: serverTimestamp() }));
    await ok(updateDoc(doc(as("poster"), "tasks", "t_direct"), { status: "assigned", acceptedByUid: "target", assignedAt: serverTimestamp(), "bids.target": 150 }));
  });
  await seed();
  await check("the worker can only mark an ASSIGNED task done", () => no(updateDoc(doc(as("worker"), "tasks", "t_done2"), { workerCompleted: true, workerCompletedAt: serverTimestamp() })));
  await check("completing a task needs a rating between 1 and 5", async () => {
    await no(updateDoc(doc(as("poster"), "tasks", "t_assigned"), { status: "completed", completedAt: serverTimestamp(), workerRating: 0 }));
    await no(updateDoc(doc(as("poster"), "tasks", "t_assigned"), { status: "completed", completedAt: serverTimestamp(), workerRating: 50 }));
    await no(updateDoc(doc(as("poster"), "tasks", "t_assigned"), { status: "completed", completedAt: serverTimestamp(), workerRating: "great" }));
  });
  await check("the poster cannot delete a hired task", () => no(env.authenticatedContext("poster").firestore().doc("tasks/t_assigned").delete()));
  await check("the poster cannot delete a finished task (it is the record of the job)", () => no(env.authenticatedContext("poster").firestore().doc("tasks/t_done2").delete()));
  await check("the poster can still cancel (delete) an open task", () => ok(env.authenticatedContext("poster").firestore().doc("tasks/t_open").delete()));
  await check("the poster can delete a declined private request", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => updateDoc(doc(ctx.firestore(), "tasks", "t_direct"), { status: "declined" }));
    await ok(env.authenticatedContext("poster").firestore().doc("tasks/t_direct").delete());
  });
  await seed();
  const openTask = (extra = {}) => ({ postedByUid: "poster", postedByName: "Poster", title: "Fix tap", description: "d", price: 300, category: "Repairs",
    city: "Surat", isUrgent: false, status: "open", targetHelperUid: null, applicants: [], bids: {}, createdAt: serverTimestamp(), endTime: future, ...extra });
  await check("a task cannot be created carrying payment records", async () => {
    await no(addDoc(tasks(as("poster")), openTask({ paidViaRazorpay: true, finalPricePaid: 99999, amountPaidByPoster: 99999 })));
    await no(addDoc(tasks(as("poster")), openTask({ paidInCash: true, cashFee: 0 })));
  });
  await check("a task cannot be created with a helper already hired or fake applicants", async () => {
    await no(addDoc(tasks(as("poster")), openTask({ acceptedByUid: "worker" })));
    await no(addDoc(tasks(as("poster")), openTask({ applicants: ["sock1", "sock2"], bids: { sock1: 1, sock2: 1 } })));
    await no(addDoc(tasks(as("poster")), openTask({ targetHelperUid: "worker" })));
  });
  await check("a private request must list only the helper it is for", () => no(addDoc(tasks(as("poster")), directDoc({ applicants: ["target", "other"] }))));
  await check("a task needs a numeric, non-negative price and the real creation time", async () => {
    await no(addDoc(tasks(as("poster")), openTask({ price: -5 })));
    await no(addDoc(tasks(as("poster")), openTask({ price: "free" })));
    await no(addDoc(tasks(as("poster")), openTask({ createdAt: Timestamp.fromMillis(1000) })));
  });
  await check("a normal task is still accepted", () => ok(addDoc(tasks(as("poster")), openTask())));

  console.log("\n[Task log: attributable, fixed shape]");
  await seed();
  await check("a stranger cannot write into the log of a hired-out task", () => no(addDoc(collection(as("other"), "tasks", "t_assigned", "taskLog"), { action: "x", actorUid: "other", details: "", timestamp: serverTimestamp() })));
  await check("a log entry cannot name someone else as the actor", () => no(addDoc(collection(as("other"), "tasks", "t_open", "taskLog"), { action: "x", actorUid: "poster", details: "", timestamp: serverTimestamp() })));
  await check("an extra field is refused", () => no(addDoc(collection(as("poster"), "tasks", "t_open", "taskLog"), { action: "x", actorUid: "poster", details: "", timestamp: serverTimestamp(), note: 1 })));
  await check("the poster and the hired worker can log, in their own name", async () => {
    await ok(addDoc(collection(as("poster"), "tasks", "t_assigned", "taskLog"), { action: "task_completed", actorUid: "poster", details: "d", timestamp: serverTimestamp() }));
    await ok(addDoc(collection(as("worker"), "tasks", "t_assigned", "taskLog"), { action: "worker_marked_done", actorUid: "worker", details: "d", timestamp: serverTimestamp() }));
  });

  console.log("\n[Chats: two people, own name, fixed shape]");
  await seed();
  const chatData = (extra = {}) => ({ participants: ["poster", "worker"], lastMessage: "", lastMessageTime: serverTimestamp(), unreadCounts: { poster: 0, worker: 0 }, ...extra });
  await check("a chat is created with the app's sorted '<uidA>_<uidB>' id", () => ok(setDoc(doc(as("poster"), "chats", "poster_worker"), chatData())));
  await check("nobody can claim the chat id of two OTHER people", () => no(setDoc(doc(as("other"), "chats", "poster_worker"), chatData({ participants: ["other", "poster"] }))));
  await check("a chat with three people is refused", () => no(setDoc(doc(as("poster"), "chats", "poster_target"), chatData({ participants: ["poster", "target", "other"] }))));
  await check("a chat cannot be created without yourself in it", () => no(setDoc(doc(as("other"), "chats", "poster_worker"), chatData())));
  await check("a participant cannot add a third reader later", () => no(updateDoc(doc(as("poster"), "chats", "poster_worker"), { participants: ["poster", "worker", "other"] })));
  await check("sending a message updates only the preview fields", async () => {
    const db = as("poster"); const b = writeBatch(db);
    b.set(doc(db, "chats", "poster_worker", "messages", "m1"), { senderId: "poster", text: "hi", timestamp: serverTimestamp() });
    b.update(doc(db, "chats", "poster_worker"), { lastMessage: "hi", lastMessageTime: serverTimestamp(), "unreadCounts.worker": increment(1) });
    await ok(b.commit());
  });
  await check("a message cannot be sent in someone else's name", () => no(setDoc(doc(as("poster"), "chats", "poster_worker", "messages", "m2"), { senderId: "worker", text: "hi", timestamp: serverTimestamp() })));
  await check("a message cannot carry extra fields or a back-dated time", async () => {
    await no(setDoc(doc(as("poster"), "chats", "poster_worker", "messages", "m3"), { senderId: "poster", text: "hi", timestamp: serverTimestamp(), link: "x" }));
    await no(setDoc(doc(as("poster"), "chats", "poster_worker", "messages", "m4"), { senderId: "poster", text: "hi", timestamp: Timestamp.fromMillis(1000) }));
  });
  await check("an outsider cannot read or write the conversation", async () => {
    await no(getDocs(collection(as("other"), "chats", "poster_worker", "messages")));
    await no(setDoc(doc(as("other"), "chats", "poster_worker", "messages", "m5"), { senderId: "other", text: "hi", timestamp: serverTimestamp() }));
  });

  await env.cleanup();
  console.log(`\n${passed} passed, ${failed} failed`);
  if (failed) { console.log("FAILED:\n  - " + failures.join("\n  - ")); process.exit(1); }
})().catch((e) => { console.error(e); process.exit(1); });
