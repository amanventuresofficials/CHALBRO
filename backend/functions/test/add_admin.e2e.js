"use strict";
// Runs scripts/add_admin.js for real against the Auth + Firestore EMULATORS with the real firestore.rules.
// Refuses to run against anything else.
//   firebase emulators:exec --only auth,firestore --project demo-chalbro "node functions/test/add_admin.e2e.js"
const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const path = require("node:path");

if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  console.error("Refusing to run: the Auth and Firestore emulators are not both running (this must never touch the live project).");
  process.exit(2);
}

const admin = require("firebase-admin");
admin.initializeApp({ projectId: "demo-chalbro" });
const db = admin.firestore();
const SCRIPT = path.resolve(__dirname, "..", "scripts", "add_admin.js");
const AUTH = `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts`;

let passed = 0;
const t = async (name, fn) => { await fn(); passed++; console.log("  PASS  " + name); };

async function signUp(email, password) {
  const r = await fetch(`${AUTH}:signUp?key=fake`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ email, password, returnSecureToken: true }) });
  const j = await r.json();
  assert.ok(j.localId, JSON.stringify(j));
  return j.localId;
}
async function canSignIn(email, password) {
  const r = await fetch(`${AUTH}:signInWithPassword?key=fake`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ email, password, returnSecureToken: true }) });
  return r.ok ? (await r.json()).localId : null;
}
function run(args, { by, byPassword, newPassword }) {
  const res = spawnSync(process.execPath, [SCRIPT, ...args, "--project", "demo-chalbro"], {
    env: { ...process.env, ADD_ADMIN_BY_EMAIL: by, ADD_ADMIN_BY_PASSWORD: byPassword, ADD_ADMIN_NEW_PASSWORD: newPassword },
    encoding: "utf8",
  });
  return { code: res.status, out: `${res.stdout}${res.stderr}` };
}

(async () => {
  const adminUid = await signUp("boss@test.dev", "bosspass123");
  await db.doc(`admins/${adminUid}`).set({ email: "boss@test.dev", displayName: "Boss", role: "admin" });
  const normalUid = await signUp("normal@test.dev", "normalpass123");

  await t("an existing admin adds a brand-new person", async () => {
    const r = run(["--email", "New.Person@Test.dev", "--name", "New Person"], { by: "boss@test.dev", byPassword: "bosspass123", newPassword: "FreshPass#2026" });
    assert.equal(r.code, 0, r.out);
    assert.match(r.out, /is now an admin/);
    const uid = await canSignIn("new.person@test.dev", "FreshPass#2026");
    assert.ok(uid, "the new person can sign in with the password that was typed");
    const doc = (await db.doc(`admins/${uid}`).get()).data();
    assert.equal(doc.email, "new.person@test.dev");
    assert.equal(doc.displayName, "New Person");
    assert.equal(doc.role, "admin");
    assert.equal(doc.addedByUid, adminUid);
    assert.equal(doc.addedByEmail, "boss@test.dev");
    assert.ok(doc.createdAt);
    const logs = await db.collection("adminLogs").where("targetId", "==", uid).get();
    assert.equal(logs.size, 1);
    assert.equal(logs.docs[0].get("adminUid"), adminUid);
    assert.equal(logs.docs[0].get("action"), "admin_added");
  });

  await t("running it again says they are already an admin and changes nothing", async () => {
    const r = run(["--email", "new.person@test.dev"], { by: "boss@test.dev", byPassword: "bosspass123", newPassword: "FreshPass#2026" });
    assert.equal(r.code, 0, r.out);
    assert.match(r.out, /already an admin/);
    assert.equal((await db.collection("admins").get()).size, 2);
  });

  await t("someone who already has a sign-in (and types its password) can be made admin", async () => {
    const r = run(["--email", "normal@test.dev"], { by: "boss@test.dev", byPassword: "bosspass123", newPassword: "normalpass123" });
    assert.equal(r.code, 0, r.out);
    assert.match(r.out, /sign-in already existed/);
    assert.equal((await db.doc(`admins/${normalUid}`).get()).exists, true);
  });

  await t("an existing sign-in with the WRONG password typed is refused", async () => {
    await signUp("third@test.dev", "thirdpass123");
    const r = run(["--email", "third@test.dev"], { by: "boss@test.dev", byPassword: "bosspass123", newPassword: "not-their-password" });
    assert.notEqual(r.code, 0);
    assert.match(r.out, /not its password/);
    assert.equal((await db.collection("admins").get()).size, 3);
  });

  await t("someone who is NOT an admin cannot add admins (the rules refuse it)", async () => {
    const r = run(["--email", "sneaky@test.dev"], { by: "third@test.dev", byPassword: "thirdpass123", newPassword: "SneakyPass#1" });
    assert.notEqual(r.code, 0);
    assert.match(r.out, /Not done/);
    const uid = await canSignIn("sneaky@test.dev", "SneakyPass#1");
    assert.equal((await db.doc(`admins/${uid}`).get()).exists, false, "no admin record may exist");
  });

  await t("a wrong password for the existing admin is refused", async () => {
    const r = run(["--email", "other@test.dev"], { by: "boss@test.dev", byPassword: "wrong-wrong", newPassword: "OtherPass#1" });
    assert.notEqual(r.code, 0);
    assert.match(r.out, /Could not sign in as the existing admin/);
  });

  await t("a too-short password and a bad e-mail are refused before anything is created", async () => {
    const short = run(["--email", "short@test.dev"], { by: "boss@test.dev", byPassword: "bosspass123", newPassword: "abc" });
    assert.notEqual(short.code, 0);
    assert.equal(await canSignIn("short@test.dev", "abc"), null);
    const bad = spawnSync(process.execPath, [SCRIPT, "--email", "not-an-email"], { encoding: "utf8", env: process.env });
    assert.equal(bad.status, 2);
  });

  console.log(`\n${passed} passed`);
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
