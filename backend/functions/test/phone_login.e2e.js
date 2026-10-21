// End-to-end check (Firestore EMULATOR, Firebase's Phone provider replaced by a stand-in) of the "Phone login" switch:
// what the signed-out login screen is told, what a change in the admin panel does to Firebase, failures and retries.
//
// Run from chalbroo:  firebase emulators:exec --only firestore --project demo-chalbro "node functions/test/phone_login.e2e.js"
const assert = require("node:assert/strict");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("Refusing to run: FIRESTORE_EMULATOR_HOST is not set (this would touch a real project).");
  process.exit(2);
}
process.env.GCLOUD_PROJECT = "demo-chalbro";
process.env.RAZORPAY_KEY_ID = "rzp_test_standin";
const fns = require("../index.js"); // starts firebase-admin (against the emulator)
const admin = require("firebase-admin");
const { Timestamp } = require("firebase-admin/firestore");
const { createPhoneLoginService, phoneLoginEnabledOf } = require("../phone_login");

const db = admin.firestore();

// Stand-in for Firebase's Phone provider setting.
const fb = { enabled: true, calls: [], failGet: null, failSet: null };
const identity = {
  async getPhoneProviderEnabled() {
    if (fb.failGet) throw new Error(fb.failGet);
    return fb.enabled;
  },
  async setPhoneProviderEnabled(v) {
    fb.calls.push(v);
    if (fb.failSet) throw new Error(fb.failSet);
    fb.enabled = v;
  },
};
let clock = 1_800_000_000_000;
const service = createPhoneLoginService({ db, Timestamp, identity, now: () => clock });

const getDoc = async (p) => {
  const s = await db.doc(p).get();
  return s.exists ? s.data() : null;
};
async function wipe() {
  for (const col of ["metadata", "adminLogs"]) {
    const snap = await db.collection(col).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
  fb.enabled = true;
  fb.calls = [];
  fb.failGet = null;
  fb.failSet = null;
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
  console.log("What the login screen is told");
  await check("missing field, missing document or anything but an explicit false means ON", async () => {
    assert.equal(phoneLoginEnabledOf(null), true);
    assert.equal(phoneLoginEnabledOf({}), true);
    assert.equal(phoneLoginEnabledOf({ phoneLoginEnabled: true }), true);
    assert.equal(phoneLoginEnabledOf({ phoneLoginEnabled: "no" }), true);
    assert.equal(phoneLoginEnabledOf({ phoneLoginEnabled: false }), false);
  });

  await check("the public function answers yes without any settings, no when the admin turned it off, and nothing else", async () => {
    await wipe();
    assert.deepEqual(await fns.getLoginOptions.run({}, {}), { phoneLoginEnabled: true });
    await db.doc("metadata/appConfig").set({ phoneLoginEnabled: false, maintenanceMode: true, maintenanceMessage: "secret plans" });
    const r = await fns.getLoginOptions.run({}, {});
    assert.deepEqual(r, { phoneLoginEnabled: false }, "only the one yes/no is ever returned");
  });

  console.log("A change in the admin panel");
  await check("turning it OFF switches Firebase's Phone provider off, records it and logs it", async () => {
    await wipe();
    const r = await service.onConfigWrite({ phoneLoginEnabled: true }, { phoneLoginEnabled: false });
    assert.equal(r.changed, true);
    assert.deepEqual(fb.calls, [false]);
    const st = await getDoc("metadata/phoneLoginStatus");
    assert.equal(st.wantedEnabled, false);
    assert.equal(st.providerEnabled, false);
    assert.equal(st.lastError, null);
    const logs = (await db.collection("adminLogs").get()).docs.map((d) => d.data());
    assert.equal(logs.length, 1);
    assert.equal(logs[0].action, "phone_login_changed");
    assert.match(logs[0].details, /switched off/);
  });

  await check("turning it back ON switches it on again", async () => {
    const r = await service.onConfigWrite({ phoneLoginEnabled: false }, { phoneLoginEnabled: true });
    assert.equal(r.changed, true);
    assert.equal(fb.enabled, true);
    assert.equal((await getDoc("metadata/phoneLoginStatus")).providerEnabled, true);
  });

  await check("saving other settings (switch unchanged, or first appearing as on) never touches Firebase", async () => {
    await wipe();
    assert.equal((await service.onConfigWrite({ maintenanceMode: false }, { maintenanceMode: true })).skipped, true);
    assert.equal((await service.onConfigWrite(null, { phoneLoginEnabled: true })).skipped, true);
    assert.equal((await service.onConfigWrite({ phoneLoginEnabled: false }, { phoneLoginEnabled: false })).skipped, true);
    assert.deepEqual(fb.calls, []);
    assert.equal(await getDoc("metadata/phoneLoginStatus"), null);
  });

  await check("if Firebase already matches, nothing is changed and nothing is logged", async () => {
    await wipe();
    fb.enabled = false; // somebody already switched it off in the console
    const r = await service.onConfigWrite({ phoneLoginEnabled: true }, { phoneLoginEnabled: false });
    assert.equal(r.changed, false);
    assert.deepEqual(fb.calls, []);
    assert.equal((await db.collection("adminLogs").get()).size, 0);
    assert.equal((await getDoc("metadata/phoneLoginStatus")).providerEnabled, false);
  });

  console.log("When Firebase says no");
  await check("a refused change is shown to the admin, not thrown, and the app-side switch still works", async () => {
    await wipe();
    fb.failSet = "Firebase said no (403): Caller does not have permission";
    const r = await service.onConfigWrite({}, { phoneLoginEnabled: false });
    assert.equal(r.ok, false);
    const st = await getDoc("metadata/phoneLoginStatus");
    assert.equal(st.wantedEnabled, false);
    assert.equal(st.providerEnabled, true, "what Firebase really is");
    assert.match(st.lastError, /403/);
    assert.equal((await db.collection("adminLogs").get()).size, 0, "a change that did not happen is not logged");
    await db.doc("metadata/appConfig").set({ phoneLoginEnabled: false });
    assert.deepEqual(await fns.getLoginOptions.run({}, {}), { phoneLoginEnabled: false });
  });

  await check("the scheduled guard retries a failed change and stops once it worked", async () => {
    fb.failSet = null;
    const r = await service.retryPending();
    assert.equal(r.changed, true);
    assert.equal(fb.enabled, false);
    const st = await getDoc("metadata/phoneLoginStatus");
    assert.equal(st.lastError, null);
    const again = await service.retryPending();
    assert.equal(again.skipped, true, "nothing pending any more");
    assert.deepEqual(fb.calls, [false, false], "only the failed call and the retry reached Firebase");
  });

  await check("retry follows the CURRENT switch, not the old failed one", async () => {
    await wipe();
    fb.failSet = "boom";
    await service.onConfigWrite({}, { phoneLoginEnabled: false });
    await db.doc("metadata/appConfig").set({ phoneLoginEnabled: true }); // the admin changed their mind
    fb.failSet = null;
    fb.calls = [];
    const r = await service.retryPending();
    assert.equal(r.ok, true);
    assert.equal(fb.enabled, true);
    assert.equal((await getDoc("metadata/phoneLoginStatus")).wantedEnabled, true);
  });

  await check("cannot read Firebase's state: the error is recorded and nothing is changed", async () => {
    await wipe();
    fb.failGet = "Firebase said no (403): nope";
    const r = await service.onConfigWrite({}, { phoneLoginEnabled: false });
    assert.equal(r.ok, false);
    assert.deepEqual(fb.calls, []);
    const st = await getDoc("metadata/phoneLoginStatus");
    assert.equal(st.providerEnabled, null);
    assert.match(st.lastError, /403/);
  });

  console.log("The deployed entry points");
  await check("index.js exports the new functions", async () => {
    for (const n of ["getLoginOptions", "phoneLoginOnConfigWrite", "captchaGuard"]) assert.equal(typeof fns[n], "function", n);
  });

  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
