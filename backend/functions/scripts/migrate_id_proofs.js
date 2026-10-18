#!/usr/bin/env node
"use strict";
/**
 * One-off clean-up for ID photos uploaded by app builds <= 10.
 *
 * Those builds stored the photo's download link in `users/{uid}.idProofUrl`, which every
 * signed-in user can read, and a Storage download link works for anyone who holds it.
 * The new app keeps it in `users/{uid}/private/idProof` (owner + admins only).
 *
 * For every user that still has `idProofUrl` this script
 *   1. gives the Storage file a NEW download token, so links that were already readable
 *      stop working (skip with --no-rotate),
 *   2. writes the new link to `users/{uid}/private/idProof`,
 *   3. sets `hasIdProof: true` and removes `idProofUrl` from the profile.
 *
 * It is safe to run twice (users already moved have no `idProofUrl`) and does nothing
 * unless you pass --apply.
 *
 *   cd chalbroo/functions
 *   node scripts/migrate_id_proofs.js --project chal-bro            # dry run: only counts
 *   node scripts/migrate_id_proofs.js --project chal-bro --apply    # really do it
 *
 * It needs Admin credentials for the project: `gcloud auth application-default login`, or
 * GOOGLE_APPLICATION_CREDENTIALS pointing at a service-account key (never commit that file).
 * Against the emulators (FIRESTORE_EMULATOR_HOST set) it needs none.
 */
const crypto = require("crypto");

/** "id_proofs/abc.jpg" out of a firebasestorage download link, or null. */
function storagePathFromUrl(url) {
  try {
    const m = new URL(url).pathname.match(/\/o\/(.+)$/);
    return m ? decodeURIComponent(m[1]) : null;
  } catch (e) {
    return null;
  }
}

/** The bucket name out of a firebasestorage download link, or null. */
function bucketFromUrl(url) {
  try {
    const m = new URL(url).pathname.match(/\/v0\/b\/([^/]+)\/o\//);
    return m ? m[1] : null;
  } catch (e) {
    return null;
  }
}

function downloadUrl(bucketName, path, token) {
  return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encodeURIComponent(path)}?alt=media&token=${token}`;
}

/**
 * @param {object} o
 * @param {FirebaseFirestore.Firestore} o.db
 * @param {(bucketName: string) => {file: (p: string) => {setMetadata: (m: object) => Promise<any>}}} o.bucketFor
 * @param {boolean} o.apply   write changes (false = report only)
 * @param {boolean} o.rotate  give the file a new download token
 */
async function migrate({ db, bucketFor, apply, rotate, log = console.log }) {
  const { FieldValue } = require("firebase-admin/firestore");
  const snap = await db.collection("users").where("idProofUrl", ">", "").get();
  const result = { found: snap.size, moved: 0, skipped: [], failed: [] };
  log(`${snap.size} profile(s) still carry idProofUrl.`);

  for (const doc of snap.docs) {
    const url = doc.get("idProofUrl");
    const path = storagePathFromUrl(url);
    const bucketName = bucketFromUrl(url);
    if (typeof url !== "string" || !path || !bucketName || !path.startsWith("id_proofs/")) {
      result.skipped.push(doc.id);
      log(`  skip ${doc.id}: link is not a Storage id_proofs link`);
      continue;
    }
    if (!apply) {
      log(`  would move ${doc.id} (${path})${rotate ? " and rotate its token" : ""}`);
      continue;
    }
    try {
      let newUrl = url;
      if (rotate) {
        const token = crypto.randomUUID();
        await bucketFor(bucketName).file(path).setMetadata({ metadata: { firebaseStorageDownloadTokens: token } });
        newUrl = downloadUrl(bucketName, path, token);
      }
      const batch = db.batch();
      batch.set(db.doc(`users/${doc.id}/private/idProof`), { url: newUrl, path, updatedAt: FieldValue.serverTimestamp() });
      batch.update(doc.ref, { hasIdProof: true, idProofUrl: FieldValue.delete() });
      await batch.commit();
      result.moved++;
      log(`  moved ${doc.id}`);
    } catch (e) {
      result.failed.push(doc.id);
      log(`  FAILED ${doc.id}: ${e.message}`);
    }
  }
  log(apply
    ? `Done: ${result.moved} moved, ${result.skipped.length} skipped, ${result.failed.length} failed.`
    : "Dry run only: nothing was changed. Add --apply to do it.");
  return result;
}

async function main() {
  const args = process.argv.slice(2);
  const flag = (n) => args.includes(n);
  const value = (n) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : undefined; };
  const project = value("--project") || process.env.GCLOUD_PROJECT;
  if (!project) {
    console.error("Pass --project <firebase-project-id>");
    process.exit(2);
  }
  const admin = require("firebase-admin");
  admin.initializeApp({ projectId: project });
  const { getFirestore } = require("firebase-admin/firestore");
  const { getStorage } = require("firebase-admin/storage");
  const result = await migrate({
    db: getFirestore(),
    bucketFor: (name) => getStorage().bucket(name),
    apply: flag("--apply"),
    rotate: !flag("--no-rotate"),
  });
  process.exit(result.failed.length ? 1 : 0);
}

module.exports = { migrate, storagePathFromUrl, bucketFromUrl, downloadUrl };

if (require.main === module) {
  main().catch((e) => { console.error(e); process.exit(1); });
}
