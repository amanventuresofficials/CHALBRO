// Unit checks of the RazorpayX client (payouts.js) with a stand-in for the network.
const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("crypto");
const { payToUpi, ensureFundAccount, webhookSignatureOk, readPayoutEvent, payoutsConfigured, PayoutApiError } = require("../payouts");

const ENV = { RAZORPAY_KEY_ID: "rzp_test_x", RAZORPAY_KEY_SECRET: "s3cret", RAZORPAYX_ACCOUNT_NUMBER: "2323230000000001" };

function memoryStore() {
  const data = {};
  return { data, get: async (uid) => data[uid] || null, set: async (uid, d) => { data[uid] = { ...(data[uid] || {}), ...d }; } };
}

// A fake RazorpayX: records every request, answers like the real API.
function installFakeNetwork(handlers = {}) {
  const calls = [];
  const original = globalThis.fetch;
  globalThis.fetch = async (url, init) => {
    const path = url.replace("https://api.razorpay.com/v1", "");
    const body = JSON.parse(init.body);
    calls.push({ path, body, headers: init.headers });
    const h = handlers[path];
    const out = h ? h(body, calls) : { status: 200, json: {} };
    return { ok: out.status >= 200 && out.status < 300, status: out.status, text: async () => JSON.stringify(out.json) };
  };
  return { calls, restore: () => { globalThis.fetch = original; } };
}

const happy = {
  "/contacts": () => ({ status: 200, json: { id: "cont_1" } }),
  "/fund_accounts": () => ({ status: 200, json: { id: "fa_1" } }),
  "/payouts": () => ({ status: 200, json: { id: "pout_1", status: "processing", utr: "" } }),
};

test("configured only when keys AND the RazorpayX account number are present", () => {
  assert.equal(payoutsConfigured(ENV), true);
  assert.equal(payoutsConfigured({ ...ENV, RAZORPAYX_ACCOUNT_NUMBER: "" }), false);
  assert.equal(payoutsConfigured({}), false);
});

test("pays a UPI id: contact, fund account, then a UPI payout in paise with an idempotency key", async () => {
  const net = installFakeNetwork(happy);
  try {
    const store = memoryStore();
    const r = await payToUpi({ env: ENV, store, uid: "u1", name: "Meera", vpa: "meera@okhdfc", amountRupees: 240, reference: "wd_abc", narration: "ChalBro payout" });
    assert.deepEqual(r, { id: "pout_1", status: "processing", utr: "" });
    assert.deepEqual(net.calls.map((c) => c.path), ["/contacts", "/fund_accounts", "/payouts"]);
    const payout = net.calls[2];
    assert.equal(payout.body.amount, 24000);
    assert.equal(payout.body.mode, "UPI");
    assert.equal(payout.body.account_number, ENV.RAZORPAYX_ACCOUNT_NUMBER);
    assert.equal(payout.body.fund_account_id, "fa_1");
    assert.equal(payout.body.reference_id, "wd_abc");
    assert.equal(payout.headers["X-Payout-Idempotency"], "wd_abc");
    assert.match(payout.headers.Authorization, /^Basic /);
    assert.equal(net.calls[1].body.vpa.address, "meera@okhdfc");
  } finally {
    net.restore();
  }
});

test("the contact and fund account are created once and reused for the same UPI id", async () => {
  const net = installFakeNetwork(happy);
  try {
    const store = memoryStore();
    await payToUpi({ env: ENV, store, uid: "u1", name: "Meera", vpa: "meera@okhdfc", amountRupees: 100, reference: "w1" });
    await payToUpi({ env: ENV, store, uid: "u1", name: "Meera", vpa: "MEERA@okhdfc", amountRupees: 100, reference: "w2" });
    assert.deepEqual(net.calls.map((c) => c.path), ["/contacts", "/fund_accounts", "/payouts", "/payouts"]);
  } finally {
    net.restore();
  }
});

test("a different UPI id gets its own fund account on the same contact", async () => {
  const net = installFakeNetwork({ ...happy, "/fund_accounts": (_b, calls) => ({ status: 200, json: { id: `fa_${calls.filter((c) => c.path === "/fund_accounts").length}` } }) });
  try {
    const store = memoryStore();
    await ensureFundAccount({ store, uid: "u1", name: "M", vpa: "a@okhdfc", auth: {} });
    const second = await ensureFundAccount({ store, uid: "u1", name: "M", vpa: "b@okhdfc", auth: {} });
    assert.equal(second, "fa_2");
    assert.equal(net.calls.filter((c) => c.path === "/contacts").length, 1);
  } finally {
    net.restore();
  }
});

test("an API error comes out shaped like a Razorpay SDK error", async () => {
  const net = installFakeNetwork({
    ...happy,
    "/payouts": () => ({ status: 400, json: { error: { code: "BAD_REQUEST_ERROR", description: "The account number is invalid." } } }),
  });
  try {
    await assert.rejects(
      () => payToUpi({ env: ENV, store: memoryStore(), uid: "u1", name: "M", vpa: "m@okhdfc", amountRupees: 100, reference: "w" }),
      (e) => e instanceof PayoutApiError && e.statusCode === 400 && e.error.code === "BAD_REQUEST_ERROR" && /invalid/.test(e.error.description),
    );
  } finally {
    net.restore();
  }
});

test("webhook signatures: right secret passes, wrong secret, wrong body or none fail", () => {
  const body = Buffer.from(JSON.stringify({ event: "payout.processed" }));
  const sig = crypto.createHmac("sha256", "whsec").update(body).digest("hex");
  assert.equal(webhookSignatureOk(body, sig, "whsec"), true);
  assert.equal(webhookSignatureOk(body, sig, "other"), false);
  assert.equal(webhookSignatureOk(Buffer.from("{}"), sig, "whsec"), false);
  assert.equal(webhookSignatureOk(body, "", "whsec"), false);
  assert.equal(webhookSignatureOk(body, sig, ""), false);
});

test("webhook events: processed is paid, reversed/failed are failures, the rest is ignored", () => {
  const ev = (event, status, extra = {}) => ({ event, payload: { payout: { entity: { id: "pout_9", reference_id: "wd_9", status, utr: "UTR9", ...extra } } } });
  assert.deepEqual(readPayoutEvent(ev("payout.processed", "processed")), { outcome: "paid", reference: "wd_9", payoutId: "pout_9", utr: "UTR9", reason: "" });
  const rev = readPayoutEvent(ev("payout.reversed", "reversed", { status_details: { description: "Beneficiary bank returned it" } }));
  assert.equal(rev.outcome, "failed");
  assert.equal(rev.reason, "Beneficiary bank returned it");
  assert.equal(readPayoutEvent(ev("payout.failed", "failed")).outcome, "failed");
  assert.equal(readPayoutEvent(ev("payout.processing", "processing")).outcome, "ignore");
  assert.equal(readPayoutEvent({}).outcome, "ignore");
});
