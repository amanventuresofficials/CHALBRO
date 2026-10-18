// Tests storage.rules against the Storage emulator (with the Firestore emulator for the admin check).
// Run via:  firebase emulators:exec --only firestore,storage --project demo-chalbro "node storage.test.js"
const fs = require("fs");
const path = require("path");
const { initializeTestEnvironment, assertSucceeds, assertFails } = require("@firebase/rules-unit-testing");
const { ref, uploadBytes, getBytes, deleteObject } = require("firebase/storage");
const { doc, setDoc } = require("firebase/firestore");

const RULES = fs.readFileSync(path.join(__dirname, "..", "storage.rules"), "utf8");
const FS_RULES = fs.readFileSync(path.join(__dirname, "..", "firestore.rules"), "utf8");

let passed = 0, failed = 0;
const failures = [];
async function check(name, fn) {
  try { await fn(); passed++; console.log("  PASS  " + name); }
  catch (e) { failed++; failures.push(name); console.log("  FAIL  " + name + "\n        " + String(e.message).split("\n")[0]); }
}
const ok = (p) => assertSucceeds(p);
const no = (p) => assertFails(p);
const bytes = () => new Uint8Array([1, 2, 3, 4]);
const jpg = { contentType: "image/jpeg" };

(async () => {
  const env = await initializeTestEnvironment({ projectId: "demo-chalbro", storage: { rules: RULES }, firestore: { rules: FS_RULES } });
  await env.withSecurityRulesDisabled(async (ctx) => setDoc(doc(ctx.firestore(), "admins", "admin"), { role: "admin" }));
  const st = (uid) => env.authenticatedContext(uid).storage();
  const put = (uid, p, meta = jpg, data = bytes()) => uploadBytes(ref(st(uid), p), data, meta);

  console.log("\n[Profile photos]");
  await check("a user uploads their own photo", () => ok(put("alice", "profile_photos/alice.jpg")));
  await check("a user cannot overwrite someone else's photo", () => no(put("bob", "profile_photos/alice.jpg")));
  await check("any signed-in user can read a profile photo", () => ok(getBytes(ref(st("bob"), "profile_photos/alice.jpg"))));
  await check("signed-out users cannot read it", () => no(getBytes(ref(env.unauthenticatedContext().storage(), "profile_photos/alice.jpg"))));
  await check("an SVG 'photo' is refused", () => no(put("alice", "profile_photos/alice.jpg", { contentType: "image/svg+xml" })));
  await check("a non-image is refused", () => no(put("alice", "profile_photos/alice.jpg", { contentType: "text/html" })));

  console.log("\n[ID proofs]");
  await check("a user uploads their own ID photo", () => ok(put("alice", "id_proofs/alice.jpg")));
  await check("the owner can read it back", () => ok(getBytes(ref(st("alice"), "id_proofs/alice.jpg"))));
  await check("an admin can read it", () => ok(getBytes(ref(st("admin"), "id_proofs/alice.jpg"))));
  await check("another user CANNOT read it", () => no(getBytes(ref(st("bob"), "id_proofs/alice.jpg"))));
  await check("another user cannot overwrite it", () => no(put("bob", "id_proofs/alice.jpg")));
  await check("an SVG ID is refused", () => no(put("alice", "id_proofs/alice.svg", { contentType: "image/svg+xml" })));

  console.log("\n[Task images]");
  await check("a user uploads a task picture named <millis>_<their uid>.jpg", () => ok(put("alice", "task_images/1760000000000_alice.jpg")));
  await check("a picture under someone else's uid is refused", () => no(put("bob", "task_images/1760000000001_alice.jpg")));
  await check("an arbitrary file name is refused", () => no(put("alice", "task_images/whatever.jpg")));
  await check("nobody can replace an existing picture", () => no(put("alice", "task_images/1760000000000_alice.jpg")));
  await check("nobody can delete a picture", () => no(deleteObject(ref(st("alice"), "task_images/1760000000000_alice.jpg"))));
  await check("any signed-in user can read task pictures", () => ok(getBytes(ref(st("bob"), "task_images/1760000000000_alice.jpg"))));
  await check("a file bigger than 10 MB is refused", () => no(put("alice", "task_images/1760000000002_alice.jpg", jpg, new Uint8Array(10 * 1024 * 1024 + 1))));

  console.log("\n[Everything else]");
  await check("an unknown path is refused", () => no(put("alice", "secrets/alice.jpg")));

  await env.cleanup();
  console.log(`\n${passed} passed, ${failed} failed`);
  if (failed) { console.log("FAILED:\n  - " + failures.join("\n  - ")); process.exit(1); }
})().catch((e) => { console.error(e); process.exit(1); });
