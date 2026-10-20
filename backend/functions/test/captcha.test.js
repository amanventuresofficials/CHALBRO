// Unit checks of the captcha switch (captcha.js): the decisions, and the one request it makes to Firebase.
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  normalizeConfig,
  classifyCode,
  bucketOf,
  BUCKET_MS,
  parseLive,
  decideTarget,
  makeIdentityClient,
} = require("../captcha");

test("normalizeConfig: nothing saved yet means 'off' with safe numbers and exists=false", () => {
  assert.deepEqual(normalizeConfig(null), { exists: false, mode: "off", threshold: 15, windowMinutes: 10, holdMinutes: 60 });
  assert.equal(normalizeConfig(undefined).exists, false);
});

test("normalizeConfig: a saved choice is kept, nonsense is replaced by safe values and numbers are clamped", () => {
  assert.equal(normalizeConfig({ mode: "on" }).mode, "on");
  assert.equal(normalizeConfig({ mode: "auto" }).exists, true);
  assert.equal(normalizeConfig({ mode: "ENFORCE" }).mode, "off");
  assert.equal(normalizeConfig({ mode: "auto", threshold: 1 }).threshold, 3);
  assert.equal(normalizeConfig({ mode: "auto", threshold: 99999 }).threshold, 1000);
  assert.equal(normalizeConfig({ mode: "auto", threshold: "abc" }).threshold, 15);
  assert.equal(normalizeConfig({ mode: "auto", windowMinutes: 1 }).windowMinutes, 5);
  assert.equal(normalizeConfig({ mode: "auto", holdMinutes: 100000 }).holdMinutes, 1440);
  assert.equal(normalizeConfig({ mode: "auto", threshold: 7.6 }).threshold, 8);
});

test("classifyCode: rate-limit codes and captcha codes are told apart, everything else is ignored", () => {
  assert.equal(classifyCode("too-many-requests"), "rate");
  assert.equal(classifyCode("quota-exceeded"), "rate");
  assert.equal(classifyCode("invalid-app-credential"), "captcha");
  assert.equal(classifyCode("captcha-check-failed"), "captcha");
  assert.equal(classifyCode("invalid-phone-number"), null);
  assert.equal(classifyCode("network-request-failed"), null);
  assert.equal(classifyCode(""), null);
  assert.equal(classifyCode(null), null);
  assert.equal(classifyCode({ evil: true }), null);
});

test("bucketOf: five-minute buckets", () => {
  assert.equal(bucketOf(0), 0);
  assert.equal(bucketOf(BUCKET_MS - 1), 0);
  assert.equal(bucketOf(BUCKET_MS), 1);
});

test("parseLive reads Firebase's words", () => {
  assert.equal(parseLive("ENFORCE"), "ENFORCE");
  assert.equal(parseLive("AUDIT"), "AUDIT");
  assert.equal(parseLive("OFF"), "OFF");
  assert.equal(parseLive(undefined), "UNKNOWN");
  assert.equal(parseLive("RECAPTCHA_PROVIDER_ENFORCEMENT_STATE_UNSPECIFIED"), "UNKNOWN");
});

const NOW = 1_800_000_000_000;
const base = { threshold: 15, now: NOW, autoEnforcedAt: null, holdMinutes: 60, rateEvents: 0, live: "AUDIT" };

test("decideTarget: On always enforces, Off always only watches, whatever the counters say", () => {
  assert.equal(decideTarget({ ...base, mode: "on" }).target, "ENFORCE");
  assert.equal(decideTarget({ ...base, mode: "on", rateEvents: 0, live: "ENFORCE" }).target, "ENFORCE");
  assert.equal(decideTarget({ ...base, mode: "off", rateEvents: 500, live: "ENFORCE" }).target, "AUDIT");
  assert.equal(decideTarget({ ...base, mode: "off" }).autoEnforcedAt, null);
});

test("decideTarget auto: calm stays on watch-only", () => {
  const d = decideTarget({ ...base, mode: "auto", rateEvents: 14 });
  assert.equal(d.target, "AUDIT");
  assert.equal(d.autoEnforcedAt, null);
});

test("decideTarget auto: reaching the threshold turns it on and starts the timer", () => {
  const d = decideTarget({ ...base, mode: "auto", rateEvents: 15 });
  assert.equal(d.target, "ENFORCE");
  assert.equal(d.autoEnforcedAt, NOW);
  assert.match(d.reason, /Too many requests/);
});

test("decideTarget auto: once calm again it stays on until the hold time has passed, then goes back", () => {
  const since = NOW - 30 * 60 * 1000;
  const holding = decideTarget({ ...base, mode: "auto", live: "ENFORCE", autoEnforcedAt: since, rateEvents: 0 });
  assert.equal(holding.target, "ENFORCE");
  assert.equal(holding.autoEnforcedAt, since, "the timer is not restarted while merely holding");
  const expired = decideTarget({ ...base, mode: "auto", live: "ENFORCE", autoEnforcedAt: NOW - 61 * 60 * 1000, rateEvents: 0 });
  assert.equal(expired.target, "AUDIT");
  assert.equal(expired.autoEnforcedAt, null);
});

test("decideTarget auto: more trouble while it is on restarts the timer", () => {
  const d = decideTarget({ ...base, mode: "auto", live: "ENFORCE", autoEnforcedAt: NOW - 50 * 60 * 1000, rateEvents: 20 });
  assert.equal(d.target, "ENFORCE");
  assert.equal(d.autoEnforcedAt, NOW);
});

test("decideTarget auto: an 'on' left over from the On mode is NOT kept (nobody set the timer)", () => {
  const d = decideTarget({ ...base, mode: "auto", live: "ENFORCE", autoEnforcedAt: null, rateEvents: 0 });
  assert.equal(d.target, "AUDIT");
});

// ── the request to Firebase ──
function fakeFetch(handler) {
  const calls = [];
  const fn = async (url, init) => {
    calls.push({ url, init });
    const r = handler({ url, init });
    return { ok: r.status < 300, status: r.status, json: async () => r.json };
  };
  return { fn, calls };
}

test("makeIdentityClient reads the phone state from the project config", async () => {
  const f = fakeFetch(() => ({ status: 200, json: { recaptchaConfig: { phoneEnforcementState: "AUDIT", useSmsTollFraudProtection: true } } }));
  const c = makeIdentityClient({ projectId: "chal-bro", getToken: async () => "tok123", fetchFn: f.fn });
  assert.equal(await c.getPhoneState(), "AUDIT");
  assert.equal(f.calls[0].url, "https://identitytoolkit.googleapis.com/v2/projects/chal-bro/config");
  assert.equal(f.calls[0].init.method, "GET");
  assert.equal(f.calls[0].init.headers.Authorization, "Bearer tok123");
});

test("makeIdentityClient changes ONLY the one field, and nothing else in the config is sent", async () => {
  const f = fakeFetch(() => ({ status: 200, json: {} }));
  const c = makeIdentityClient({ projectId: "chal-bro", getToken: async () => "t", fetchFn: f.fn });
  await c.setPhoneState("ENFORCE");
  const call = f.calls[0];
  assert.equal(call.init.method, "PATCH");
  assert.equal(call.url, "https://identitytoolkit.googleapis.com/v2/projects/chal-bro/config?updateMask=recaptchaConfig.phoneEnforcementState");
  assert.deepEqual(JSON.parse(call.init.body), { recaptchaConfig: { phoneEnforcementState: "ENFORCE" } });
});

test("makeIdentityClient never sets OFF (or anything but AUDIT / ENFORCE)", async () => {
  const f = fakeFetch(() => ({ status: 200, json: {} }));
  const c = makeIdentityClient({ projectId: "p", getToken: async () => "t", fetchFn: f.fn });
  await assert.rejects(() => c.setPhoneState("OFF"), /Refusing/);
  await assert.rejects(() => c.setPhoneState("whatever"), /Refusing/);
  assert.equal(f.calls.length, 0);
});

test("makeIdentityClient turns a refusal into a readable error with the status", async () => {
  const f = fakeFetch(() => ({ status: 403, json: { error: { message: "Caller does not have permission", status: "PERMISSION_DENIED" } } }));
  const c = makeIdentityClient({ projectId: "p", getToken: async () => "t", fetchFn: f.fn });
  await assert.rejects(
    () => c.setPhoneState("AUDIT"),
    (e) => e.status === 403 && /Firebase said no \(403\).*permission/.test(e.message),
  );
});
