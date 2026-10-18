// Sending money straight to a helper's UPI id through RazorpayX Payouts.
//
// RazorpayX is a SEPARATE Razorpay product from the checkout the poster pays with: it has
// to be activated on the Razorpay account, it has its own account number and it pays out of
// a balance the owner keeps topped up. Everything here is therefore OFF until the owner
// switches "Pay helpers straight to their UPI ID" on in the admin panel AND fills in
// RAZORPAYX_ACCOUNT_NUMBER / RAZORPAYX_WEBHOOK_SECRET in functions/.env.
//
// This file only talks to the RazorpayX HTTP API and checks webhook signatures. Which
// withdrawal to pay, and what to do with the answer, is decided in index.js.
const crypto = require("crypto");

const BASE_URL = "https://api.razorpay.com/v1";

/** A failed RazorpayX call, shaped like the Razorpay SDK's errors so errorlog.js understands it. */
class PayoutApiError extends Error {
  constructor(statusCode, apiError) {
    const e = apiError && typeof apiError === "object" ? apiError : {};
    super(String(e.description || e.code || `RazorpayX request failed (${statusCode})`));
    this.statusCode = statusCode;
    this.error = { code: String(e.code || `HTTP_${statusCode}`), description: this.message };
  }
}

/** True when everything needed to pay out is present in the environment. */
function payoutsConfigured(env = process.env) {
  return Boolean(env.RAZORPAY_KEY_ID && env.RAZORPAY_KEY_SECRET && env.RAZORPAYX_ACCOUNT_NUMBER);
}

async function call(path, body, { keyId, keySecret, idempotencyKey } = {}) {
  const headers = {
    "Content-Type": "application/json",
    Authorization: `Basic ${Buffer.from(`${keyId}:${keySecret}`).toString("base64")}`,
  };
  if (idempotencyKey) headers["X-Payout-Idempotency"] = idempotencyKey;
  // globalThis.fetch is looked up at call time so tests can replace it.
  const res = await globalThis.fetch(`${BASE_URL}${path}`, { method: "POST", headers, body: JSON.stringify(body) });
  const text = await res.text();
  let json = {};
  try {
    json = text ? JSON.parse(text) : {};
  } catch (_) {
    json = {};
  }
  if (!res.ok) throw new PayoutApiError(res.status, json.error || { description: text.slice(0, 200) });
  return json;
}

const vpaKey = (vpa) => crypto.createHash("sha1").update(String(vpa).toLowerCase()).digest("hex").slice(0, 20);

/**
 * The RazorpayX "fund account" for [vpa], created on first use and remembered in [store]
 * ({ get(uid), set(uid, data) }, backed by the server-only payoutAccounts collection).
 */
async function ensureFundAccount({ store, uid, name, vpa, auth }) {
  const rec = (await store.get(uid)) || {};
  const key = vpaKey(vpa);
  if (rec.accounts && rec.accounts[key]) return rec.accounts[key];

  let contactId = rec.contactId;
  if (!contactId) {
    const contact = await call(
      "/contacts",
      { name: String(name || "ChalBro helper").slice(0, 60) || "ChalBro helper", type: "vendor", reference_id: uid },
      auth,
    );
    contactId = contact.id;
  }
  const fundAccount = await call(
    "/fund_accounts",
    { contact_id: contactId, account_type: "vpa", vpa: { address: vpa } },
    auth,
  );
  await store.set(uid, { contactId, accounts: { ...(rec.accounts || {}), [key]: fundAccount.id } });
  return fundAccount.id;
}

/**
 * Sends [amountRupees] to [vpa]. [reference] (the withdrawal id) doubles as the idempotency
 * key, so repeating the call can never pay twice.
 * Resolves { id, status, utr }. `status` is RazorpayX's own: queued | pending | processing |
 * processed | rejected | cancelled | reversed | failed.
 */
async function payToUpi({ env = process.env, store, uid, name, vpa, amountRupees, reference, narration }) {
  const auth = { keyId: env.RAZORPAY_KEY_ID, keySecret: env.RAZORPAY_KEY_SECRET };
  const fundAccountId = await ensureFundAccount({ store, uid, name, vpa, auth });
  const payout = await call(
    "/payouts",
    {
      account_number: env.RAZORPAYX_ACCOUNT_NUMBER,
      fund_account_id: fundAccountId,
      amount: Math.round(amountRupees * 100), // paise
      currency: "INR",
      mode: "UPI",
      purpose: "payout",
      queue_if_low_balance: true,
      reference_id: String(reference).slice(0, 40),
      narration: String(narration || "ChalBro payout").slice(0, 30),
    },
    { ...auth, idempotencyKey: String(reference) },
  );
  return { id: payout.id, status: payout.status, utr: payout.utr || "" };
}

/** True when [signature] is the HMAC-SHA256 of [rawBody] under [secret]. */
function webhookSignatureOk(rawBody, signature, secret) {
  if (!secret || !signature || !rawBody) return false;
  const expected = crypto.createHmac("sha256", secret).update(rawBody).digest("hex");
  const a = Buffer.from(expected);
  const b = Buffer.from(String(signature));
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

const SUCCESS_EVENTS = new Set(["payout.processed"]);
const FAILURE_EVENTS = new Set(["payout.reversed", "payout.rejected", "payout.failed", "payout.cancelled"]);

/**
 * Reads a RazorpayX webhook body. Returns { outcome: 'paid'|'failed'|'ignore', reference,
 * payoutId, utr, reason }. Events that say nothing final (queued, processing ...) are 'ignore'.
 */
function readPayoutEvent(body) {
  const event = body && body.event;
  const entity = body && body.payload && body.payload.payout && body.payload.payout.entity;
  if (!event || !entity) return { outcome: "ignore" };
  const base = {
    reference: String(entity.reference_id || ""),
    payoutId: String(entity.id || ""),
    utr: String(entity.utr || ""),
    reason: String(entity.status_details && entity.status_details.description ? entity.status_details.description : entity.failure_reason || ""),
  };
  if (SUCCESS_EVENTS.has(event)) return { outcome: "paid", ...base };
  if (FAILURE_EVENTS.has(event)) return { outcome: "failed", ...base };
  return { outcome: "ignore", ...base };
}

module.exports = {
  PayoutApiError,
  payoutsConfigured,
  ensureFundAccount,
  payToUpi,
  webhookSignatureOk,
  readPayoutEvent,
};
