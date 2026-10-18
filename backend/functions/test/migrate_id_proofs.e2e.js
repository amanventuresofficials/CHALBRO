"use strict";
// Runs the ID-photo migration against the Firestore EMULATOR with a stand-in for Storage.
// Refuses to run against anything else.
//   firebase emulators:exec --only firestore --project demo-chalbro "node functions/test/migrate_id_proofs.e2e.js"
const assert = require("node:assert/strict");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("Refusing to run: FIRESTORE_EMULATOR_HOST is not set (this must never touch the live project).");
  process.exit(2);
}

const admin = require("firebase-admin");
admin.initializeApp({ projectId: "demo-chalbro" });
const { getFirestore } = require("firebase-admin/firestore");
const { migrate, storagePathFromUrl, bucketFromUrl } = require("../scripts/migrate_id_proofs");

const db = getFirestore();
let passed = 0;
const t = async (name, fn) => { await fn(); passed++; console.log("  PASS  " + name); };
const link = (uid, token = "oldtoken") =>
  `https://firebasestorage.googleapis.com/v0/b/chal-bro.appspot.com/o/id_proofs%2F${uid}.jpg?alt=media&token=${token}`;

(async () => {
  await t("parses the storage path and bucket out of a download link", async () => {
    assert.equal(storagePathFromUrl(link("u1")), "id_proofs/u1.jpg");
    assert.equal(bucketFromUrl(link("u1")), "chal-bro.appspot.com");
    assert.equal(storagePathFromUrl("https://evil.example/x"), null);
    assert.equal(storagePathFromUrl("not a url"), null);
  });

  await db.doc("users/u1").set({ fullName: "One", idProofUrl: link("u1"), idProofStatus: "Pending Verification" });
  await db.doc("users/u2").set({ fullName: "Two", idProofUrl: link("u2"), idProofStatus: "Verified" });
  await db.doc("users/u3").set({ fullName: "Three", idProofUrl: "https://evil.example/photo.jpg" });
  await db.doc("users/u4").set({ fullName: "Four", hasIdProof: true });
  await db.doc("users/u5").set({ fullName: "Five" });

  const rotated = [];
  const bucketFor = (name) => ({
    file: (p) => ({
      setMetadata: async (m) => { rotated.push({ name, p, token: m.metadata.firebaseStorageDownloadTokens }); },
    }),
  });
  const quiet = () => {};

  await t("a dry run reports and changes nothing", async () => {
    const r = await migrate({ db, bucketFor, apply: false, rotate: true, log: quiet });
    assert.equal(r.found, 3);
    assert.equal(r.moved, 0);
    assert.equal(rotated.length, 0);
    assert.equal((await db.doc("users/u1").get()).get("idProofUrl"), link("u1"));
  });

  await t("--apply moves the link into the private document and rotates the token", async () => {
    const r = await migrate({ db, bucketFor, apply: true, rotate: true, log: quiet });
    assert.equal(r.moved, 2);
    assert.deepEqual(r.skipped, ["u3"]);
    assert.equal(rotated.length, 2);
    const u1 = (await db.doc("users/u1").get()).data();
    assert.equal(u1.hasIdProof, true);
    assert.equal("idProofUrl" in u1, false);
    assert.equal(u1.idProofStatus, "Pending Verification");
    const priv = (await db.doc("users/u1/private/idProof").get()).data();
    assert.equal(priv.path, "id_proofs/u1.jpg");
    assert.ok(priv.url.includes("token=" + rotated.find((x) => x.p === "id_proofs/u1.jpg").token));
    assert.ok(!priv.url.includes("oldtoken"), "the old token must not survive");
  });

  await t("a profile that is not an id_proofs link is left alone", async () => {
    const u3 = (await db.doc("users/u3").get()).data();
    assert.equal(u3.idProofUrl, "https://evil.example/photo.jpg");
    assert.equal((await db.doc("users/u3/private/idProof").get()).exists, false);
  });

  await t("running it again changes nothing more", async () => {
    const before = rotated.length;
    const r = await migrate({ db, bucketFor, apply: true, rotate: true, log: quiet });
    assert.equal(r.found, 1); // only the skipped u3
    assert.equal(r.moved, 0);
    assert.equal(rotated.length, before);
  });

  await t("--no-rotate keeps the link as it is", async () => {
    await db.doc("users/u6").set({ idProofUrl: link("u6", "keepme") });
    const before = rotated.length;
    const r = await migrate({ db, bucketFor, apply: true, rotate: false, log: quiet });
    assert.equal(r.moved, 1);
    assert.equal(rotated.length, before);
    assert.ok((await db.doc("users/u6/private/idProof").get()).get("url").includes("keepme"));
  });

  console.log(`\n${passed} passed`);
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
