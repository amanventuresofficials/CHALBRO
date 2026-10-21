// End-to-end check (Firestore EMULATOR, the sign-in system replaced by a stand-in) of the Admin Team calls:
// only admins may use them, adding by e-mail or user id, listing, removing, audit entries.
//
// Run from chalbroo:  firebase emulators:exec --only firestore --project demo-chalbro "node functions/test/admin_team.e2e.js"
const assert = require("node:assert/strict");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("Refusing to run: FIRESTORE_EMULATOR_HOST is not set (this would touch a real project).");
  process.exit(2);
}
process.env.GCLOUD_PROJECT = "demo-chalbro";
process.env.RAZORPAY_KEY_ID = "rzp_test_standin";
const fns = require("../index.js"); // starts firebase-admin (against the emulator)
const admin = require("firebase-admin");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");
const { createAdminTeamService } = require("../admin_team");

const db = admin.firestore();

// Stand-in for the sign-in system.
const accounts = [
  { uid: "ME", email: "me@example.com", displayName: "Me Admin" },
  { uid: "AMAN", email: "aman@gmail.com", displayName: "Aman Google" },
  { uid: "PHONEONLY", email: undefined, displayName: "" },
  { uid: "PROFILEPERSON", email: "profile@gmail.com", displayName: "" },
];
const notFound = () => Object.assign(new Error("no user"), { code: "auth/user-not-found" });
const fakeAuth = {
  async getUserByEmail(e) {
    const a = accounts.find((x) => x.email && x.email.toLowerCase() === e.toLowerCase());
    if (!a) throw notFound();
    return a;
  },
  async getUser(uid) {
    const a = accounts.find((x) => x.uid === uid);
    if (!a) throw notFound();
    return a;
  },
};
let clock = 1_800_000_000_000;
const team = createAdminTeamService({ db, auth: fakeAuth, FieldValue, Timestamp, now: () => clock });

const getDoc = async (p) => {
  const s = await db.doc(p).get();
  return s.exists ? s.data() : null;
};
async function wipe() {
  for (const col of ["admins", "adminLogs", "users"]) {
    const snap = await db.collection(col).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
  await db.doc("admins/ME").set({ email: "me@example.com", displayName: "Me Admin", role: "admin", createdAt: Timestamp.fromMillis(1_000_000_000_000) });
}
async function rejects(fn) {
  try {
    await fn();
  } catch (e) {
    return e;
  }
  throw new Error("expected a refusal");
}

let passed = 0;
let failed = 0;
async function check(name, fn) {
  try {
    await fn();
    passed++;
    console.log("  ok   " + name);
  } catch (e) {
    failed++;
    console.log("  FAIL " + name + "\n       " + (e && e.message ? e.message.split("\n")[0] : e));
  }
}

async function main() {
  console.log("Only admins");
  await wipe();
  await check("not signed in, or signed in but not an admin: every call is refused and nothing changes", async () => {
    assert.equal((await rejects(() => team.addAdmin(null, "", "AMAN"))).code, "unauthenticated");
    assert.equal((await rejects(() => team.addAdmin("STRANGER", "s@x.com", "AMAN"))).code, "permission-denied");
    assert.equal((await rejects(() => team.listAdmins("STRANGER"))).code, "permission-denied");
    assert.equal((await rejects(() => team.removeAdmin("STRANGER", "ME"))).code, "permission-denied");
    assert.equal((await db.collection("admins").get()).size, 1);
    assert.equal((await db.collection("adminLogs").get()).size, 0);
  });

  console.log("Adding");
  await check("by user id: the account must exist, the admin document is written with who added them, and it is logged", async () => {
    const r = await team.addAdmin("ME", "me@example.com", "AMAN");
    assert.deepEqual(r, { uid: "AMAN", email: "aman@gmail.com", displayName: "Aman Google" });
    const d = await getDoc("admins/AMAN");
    assert.equal(d.role, "admin");
    assert.equal(d.email, "aman@gmail.com");
    assert.equal(d.addedByUid, "ME");
    assert.equal(d.addedByEmail, "me@example.com");
    assert.ok(d.createdAt);
    assert.deepEqual(Object.keys(d).sort(), ["addedByEmail", "addedByUid", "createdAt", "displayName", "email", "role"], "same fields the security rules expect");
    const logs = (await db.collection("adminLogs").get()).docs.map((x) => x.data());
    assert.equal(logs.length, 1);
    assert.equal(logs[0].adminUid, "ME");
    assert.equal(logs[0].action, "admin_added");
    assert.equal(logs[0].targetId, "AMAN");
  });

  await check("by e-mail: finds the sign-in account even though there is no ChalBro profile, any capitals", async () => {
    const r = await team.addAdmin("ME", "me@example.com", "  Profile@GMAIL.com ");
    assert.equal(r.uid, "PROFILEPERSON");
    assert.ok(await getDoc("admins/PROFILEPERSON"));
  });

  await check("the name comes from the ChalBro profile when there is one", async () => {
    await db.doc("admins/PROFILEPERSON").delete();
    await db.doc("users/PROFILEPERSON").set({ fullName: "Priya Profile", email: "profile@gmail.com" });
    const r = await team.addAdmin("ME", "", "PROFILEPERSON");
    assert.equal(r.displayName, "Priya Profile");
  });

  await check("a phone-only account can be added by id (no e-mail)", async () => {
    const r = await team.addAdmin("ME", "", "PHONEONLY");
    assert.equal(r.email, "");
    assert.ok(await getDoc("admins/PHONEONLY"));
  });

  await check("unknown e-mail or id, empty or silly input: refused with a clear message", async () => {
    const a = await rejects(() => team.addAdmin("ME", "", "nobody@nowhere.com"));
    assert.equal(a.code, "not-found");
    assert.match(a.message, /Access Denied/);
    assert.equal((await rejects(() => team.addAdmin("ME", "", "NOSUCHUID"))).code, "not-found");
    assert.equal((await rejects(() => team.addAdmin("ME", "", "   "))).code, "invalid-argument");
    assert.equal((await rejects(() => team.addAdmin("ME", "", "x".repeat(300)))).code, "invalid-argument");
    assert.equal((await rejects(() => team.addAdmin("ME", "", null))).code, "invalid-argument");
  });

  await check("adding someone who is already an admin changes nothing", async () => {
    const before = (await db.collection("admins").get()).size;
    const e = await rejects(() => team.addAdmin("ME", "", "aman@gmail.com"));
    assert.equal(e.code, "already-exists");
    assert.equal((await db.collection("admins").get()).size, before);
  });

  console.log("Listing and removing");
  await check("the list has everybody, oldest first, with the facts the panel shows", async () => {
    const rows = await team.listAdmins("ME");
    assert.equal(rows[0].uid, "ME", "the original admin is first");
    assert.deepEqual(rows.map((r) => r.uid).sort(), ["AMAN", "ME", "PHONEONLY", "PROFILEPERSON"]);
    const aman = rows.find((r) => r.uid === "AMAN");
    assert.equal(aman.addedByEmail, "me@example.com");
    assert.equal(typeof aman.createdAtMs, "number");
  });

  await check("remove: works, is logged, and the person can no longer use the team calls", async () => {
    const r = await team.removeAdmin("ME", "AMAN", "Aman Google");
    assert.deepEqual(r, { uid: "AMAN" });
    assert.equal(await getDoc("admins/AMAN"), null);
    const log = (await db.collection("adminLogs").where("action", "==", "admin_revoked").get()).docs.map((d) => d.data());
    assert.equal(log.length, 1);
    assert.match(log[0].details, /Aman Google/);
    assert.equal((await rejects(() => team.listAdmins("AMAN"))).code, "permission-denied");
  });

  await check("nobody can remove themselves; unknown or silly ids are refused", async () => {
    assert.equal((await rejects(() => team.removeAdmin("ME", "ME"))).code, "failed-precondition");
    assert.equal((await rejects(() => team.removeAdmin("ME", "GHOST"))).code, "not-found");
    assert.equal((await rejects(() => team.removeAdmin("ME", "a/b"))).code, "invalid-argument");
    assert.equal((await rejects(() => team.removeAdmin("ME", ""))).code, "invalid-argument");
    assert.ok(await getDoc("admins/ME"));
  });

  console.log("The deployed entry points");
  await check("the three functions exist and refuse a caller who is not an admin or not signed in", async () => {
    await wipe();
    for (const n of ["addAdminUser", "listAdminUsers", "removeAdminUser"]) assert.equal(typeof fns[n], "function", n);
    const anon = await rejects(() => fns.addAdminUser.run({ input: "AMAN" }, {}));
    assert.equal(anon.code, "unauthenticated");
    const stranger = await rejects(() => fns.listAdminUsers.run({}, { auth: { uid: "STRANGER", token: {} } }));
    assert.equal(stranger.code, "permission-denied");
    assert.equal(stranger.message, "Only an admin can do this.");
  });

  await check("through the real entry points an admin can list and remove, and a refusal arrives as a proper error", async () => {
    await db.doc("admins/OTHER").set({ email: "o@x.com", displayName: "Other", role: "admin", createdAt: Timestamp.fromMillis(clock) });
    const ctx = { auth: { uid: "ME", token: { email: "me@example.com" } } };
    const rows = await fns.listAdminUsers.run({}, ctx);
    assert.deepEqual(rows.map((r) => r.uid).sort(), ["ME", "OTHER"]);
    await fns.removeAdminUser.run({ uid: "OTHER", label: "Other" }, ctx);
    assert.equal(await getDoc("admins/OTHER"), null);
    const self = await rejects(() => fns.removeAdminUser.run({ uid: "ME" }, ctx));
    assert.equal(self.code, "failed-precondition");
    assert.equal(self.message, "You cannot remove your own admin access.");
  });

  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
