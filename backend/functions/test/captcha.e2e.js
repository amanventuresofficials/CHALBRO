// End-to-end check (Firestore EMULATOR, Firebase's reCAPTCHA setting replaced by a stand-in) of the captcha switch:
// counters, saving a choice, "auto" turning on and off by itself, errors, clean-up.
//
// Run:  npm run test:captcha     (refuses to run unless FIRESTORE_EMULATOR_HOST is set)
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
const { createCaptchaService } = require("../captcha");

const db = admin.firestore();

// Stand-in for Firebase's setting.
const fb = { state: "AUDIT", calls: [], failGet: null, failSet: null };
const identity = {
  async getPhoneState() {
    if (fb.failGet) throw new Error(fb.failGet);
    return fb.state;
  },
  async setPhoneState(s) {
    fb.calls.push(s);
    if (fb.failSet) throw new Error(fb.failSet);
    fb.state = s;
  },
};

let clock = 1_800_000_000_000; // a fixed "now" we can move
const service = createCaptchaService({ db, FieldValue, Timestamp, identity, now: () => clock, random: () => 0.1 });

const getDoc = async (p) => {
  const s = await db.doc(p).get();
  return s.exists ? s.data() : null;
};
async function wipe() {
  for (const col of ["phoneAuthEvents", "adminLogs", "metadata"]) {
    const snap = await db.collection(col).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
  fb.state = "AUDIT";
  fb.calls = [];
  fb.failGet = null;
  fb.failSet = null;
}
const saveConfig = (cfg) => db.doc("metadata/captchaConfig").set(cfg);
const report = async (code, n = 1) => {
  for (let i = 0; i < n; i++) await service.reportIssue(code);
};

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
  console.log("Counters");
  await wipe();
  await check("only the two kinds of problem are counted; other codes are ignored", async () => {
    assert.deepEqual(await service.reportIssue("invalid-phone-number"), { counted: false });
    assert.deepEqual(await service.reportIssue(""), { counted: false });
    assert.deepEqual(await service.reportIssue("too-many-requests"), { counted: true, kind: "rate" });
    assert.deepEqual(await service.reportIssue("invalid-app-credential"), { counted: true, kind: "captcha" });
    const c = await service.countRecent(10);
    assert.deepEqual(c, { rate: 1, captcha: 1 });
  });

  await check("reports from different moments add up inside the window and fall out of it", async () => {
    await wipe();
    await report("too-many-requests", 4);
    clock += 6 * 60 * 1000;
    await report("quota-exceeded", 3);
    assert.deepEqual(await service.countRecent(10), { rate: 7, captcha: 0 });
    clock += 20 * 60 * 1000;
    assert.deepEqual(await service.countRecent(10), { rate: 0, captcha: 0 }, "old problems no longer count");
  });

  await check("a flood of reports is cut off instead of turning into a flood of writes", async () => {
    await wipe();
    let counted = 0;
    for (let i = 0; i < 150; i++) if ((await service.reportIssue("too-many-requests")).counted) counted++;
    assert.ok(counted <= 120, `counted ${counted}`);
    clock += 2 * 60 * 1000; // a new minute: counting is allowed again
  });

  console.log("Saved choice");
  await check("nothing saved yet: Firebase is left alone, but what it says is recorded", async () => {
    await wipe();
    fb.state = "ENFORCE";
    const r = await service.reconcile("scheduled");
    assert.equal(r.managed, false);
    assert.deepEqual(fb.calls, []);
    const st = await getDoc("metadata/captchaStatus");
    assert.equal(st.liveState, "ENFORCE");
    assert.equal(st.managed, false);
  });

  await check("Off: Firebase goes to watch-only and the change is written to the audit log", async () => {
    await wipe();
    fb.state = "ENFORCE";
    await saveConfig({ mode: "off" });
    const r = await service.reconcile("config saved");
    assert.equal(r.changed, true);
    assert.deepEqual(fb.calls, ["AUDIT"]);
    const st = await getDoc("metadata/captchaStatus");
    assert.equal(st.liveState, "AUDIT");
    assert.equal(st.mode, "off");
    const logs = (await db.collection("adminLogs").get()).docs.map((d) => d.data());
    assert.equal(logs.length, 1);
    assert.equal(logs[0].action, "captcha_state_changed");
    assert.match(logs[0].details, /ENFORCE to AUDIT/);
  });

  await check("On: Firebase goes to enforce; running again changes nothing more", async () => {
    await wipe();
    await saveConfig({ mode: "on" });
    await service.reconcile("config saved");
    assert.equal(fb.state, "ENFORCE");
    fb.calls = [];
    const again = await service.reconcile("scheduled");
    assert.equal(again.changed, false);
    assert.deepEqual(fb.calls, []);
    assert.equal((await db.collection("adminLogs").get()).size, 1, "only the real change was logged");
  });

  console.log("Auto");
  await check("auto stays on watch-only while things are calm (and captcha failures alone never turn it on)", async () => {
    await wipe();
    await saveConfig({ mode: "auto", threshold: 5, windowMinutes: 10, holdMinutes: 30 });
    await report("invalid-app-credential", 50);
    await report("too-many-requests", 4);
    const r = await service.reconcile("scheduled");
    assert.equal(r.changed, false);
    assert.equal(fb.state, "AUDIT");
    const st = await getDoc("metadata/captchaStatus");
    assert.equal(st.rateEvents, 4);
    assert.equal(st.captchaEvents, 50);
    assert.equal(st.autoEnforcedAt, null);
  });

  await check("auto turns the check on when too many 'too many requests' arrive", async () => {
    await report("too-many-requests", 1);
    const r = await service.reconcile("scheduled");
    assert.equal(r.changed, true);
    assert.equal(fb.state, "ENFORCE");
    const st = await getDoc("metadata/captchaStatus");
    assert.ok(st.autoEnforcedAt, "the timer is recorded");
    assert.match(st.reason, /Too many requests/);
  });

  await check("when calm returns it stays on for the hold time, then goes back by itself", async () => {
    clock += 15 * 60 * 1000; // problems fall out of the 10-minute window
    fb.calls = [];
    let r = await service.reconcile("scheduled");
    assert.equal(r.changed, false);
    assert.equal(fb.state, "ENFORCE", "still holding after 15 minutes (hold is 30)");
    clock += 20 * 60 * 1000; // 35 minutes after it was turned on
    r = await service.reconcile("scheduled");
    assert.equal(r.changed, true);
    assert.equal(fb.state, "AUDIT");
    assert.deepEqual(fb.calls, ["AUDIT"]);
    const st = await getDoc("metadata/captchaStatus");
    assert.equal(st.autoEnforcedAt, null);
    assert.equal((await db.collection("adminLogs").get()).size, 2, "on and off were both logged");
  });

  await check("switching from On to Auto while calm turns it back down (no leftover 'on')", async () => {
    await wipe();
    await saveConfig({ mode: "on" });
    await service.reconcile("config saved");
    assert.equal(fb.state, "ENFORCE");
    await saveConfig({ mode: "auto", threshold: 5, windowMinutes: 10, holdMinutes: 30 });
    await service.reconcile("config saved");
    assert.equal(fb.state, "AUDIT");
  });

  console.log("When Firebase says no");
  await check("cannot read Firebase's state: the error is recorded for the admin panel, nothing is thrown or changed", async () => {
    await wipe();
    await saveConfig({ mode: "on" });
    fb.failGet = "Firebase said no (403): Caller does not have permission";
    const r = await service.reconcile("scheduled");
    assert.equal(r.ok, false);
    assert.deepEqual(fb.calls, []);
    const st = await getDoc("metadata/captchaStatus");
    assert.match(st.lastError, /403/);
  });

  await check("cannot change Firebase: the old state is reported, the error is shown, and a later run recovers", async () => {
    await wipe();
    await saveConfig({ mode: "on" });
    fb.failSet = "Firebase said no (403): Caller does not have permission";
    const r = await service.reconcile("config saved");
    assert.equal(r.ok, false);
    const st = await getDoc("metadata/captchaStatus");
    assert.equal(st.liveState, "AUDIT");
    assert.equal(st.wantedState, "ENFORCE");
    assert.match(st.lastError, /403/);
    assert.equal((await db.collection("adminLogs").get()).size, 0, "a change that did not happen is not logged");
    fb.failSet = null;
    const ok = await service.reconcile("scheduled");
    assert.equal(ok.changed, true);
    assert.equal((await getDoc("metadata/captchaStatus")).lastError, null);
  });

  console.log("Clean-up");
  await check("counters older than two days are deleted, recent ones stay", async () => {
    await wipe();
    await report("too-many-requests", 2);
    clock -= 3 * 24 * 3600 * 1000;
    await report("too-many-requests", 2);
    clock += 3 * 24 * 3600 * 1000;
    assert.equal((await db.collection("phoneAuthEvents").get()).size, 2);
    assert.equal(await service.cleanup(), 1);
    assert.equal((await db.collection("phoneAuthEvents").get()).size, 1);
  });

  console.log("The deployed entry points");
  await check("index.js exports the three functions, and the public one counts a problem", async () => {
    for (const n of ["reportPhoneAuthIssue", "captchaOnConfigWrite", "captchaGuard"]) assert.equal(typeof fns[n], "function", n);
    await wipe();
    const ok = await fns.reportPhoneAuthIssue.run({ code: "too-many-requests" }, {});
    assert.deepEqual(ok, { counted: true });
    const ignored = await fns.reportPhoneAuthIssue.run({ code: 12345 }, {});
    assert.deepEqual(ignored, { counted: false });
    const none = await fns.reportPhoneAuthIssue.run(null, {});
    assert.deepEqual(none, { counted: false });
  });

  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
