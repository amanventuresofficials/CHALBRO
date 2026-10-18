// Pure helpers for recording server-side problems in the `errorLogs` collection --
// the same collection the mobile app writes to and the admin panel's "Errors &
// Health" page reads. Kept free of Firebase imports so it can be tested on its own.
//
// Rules of the road (same as the app's ErrorLogger):
//  * Never log personal data: only the user's uid. E-mail-like text and long digit
//    runs inside messages are masked.
//  * Never log secrets: the payment signature and API keys are never copied in.
//  * Never flood: the same problem is written at most once per REPEAT_WINDOW_MS per
//    server instance, and one instance writes at most INSTANCE_CAP records.
//  * Normal user mistakes (not signed in, task already paid ...) are not errors.

const MAX_MESSAGE = 500;
const MAX_STACK = 3500;
const MAX_CONTEXT = 160;
const REPEAT_WINDOW_MS = 10 * 60 * 1000;
const INSTANCE_CAP = 200;

// A caller doing something ordinary -- nothing for the owner to look at.
const QUIET_CODES = new Set(["unauthenticated", "invalid-argument", "not-found", "already-exists", "cancelled"]);
const QUIET_MESSAGES = [
  /already been paid/i,
  /hire a helper/i,
  /not awaiting payment/i,
  /already completed/i,
  /switched off/i,
  /no cash payment/i,
];

// Environment variables whose VALUE must never appear in a log, whatever the error text happens to contain.
const SECRET_ENV_NAMES = ["RAZORPAY_KEY_SECRET", "RAZORPAYX_WEBHOOK_SECRET"];

/** Replaces any secret value found in `text` (defence in depth: nothing should put one there). */
function redactSecrets(text, env = process.env) {
  let s = String(text == null ? "" : text);
  for (const name of SECRET_ENV_NAMES) {
    const value = env[name];
    if (value && value.length >= 6) s = s.split(value).join("<secret>");
  }
  return s;
}

/** Truncates, hides secret values and masks e-mail addresses and long digit runs (phone numbers). */
function clean(text, max) {
  let s = redactSecrets(text)
    .replace(/[\w.+-]+@[\w-]+(\.[\w-]+)+/g, "<email>")
    .replace(/\+?\d[\d\s-]{8,}\d/g, "<number>");
  if (s.length > max) s = `${s.slice(0, max - 1)}…`;
  return s;
}

/**
 * Turns whatever was thrown into { code, type, message, unexpected, stack }.
 *  - HttpsError: a deliberate answer to the caller (not "unexpected").
 *  - Razorpay SDK failures are plain objects { statusCode, error: { code, description } }.
 *  - Anything else is a genuine bug / outage (unexpected).
 */
function describeError(err, isHttps) {
  if (isHttps) {
    return {
      code: String(err.code),
      type: `functions/${err.code}`,
      message: String(err.message || err.code),
      unexpected: false,
      stack: "",
    };
  }
  const rz = err && typeof err === "object" && err.error && typeof err.error === "object" ? err.error : null;
  if (rz) {
    return {
      code: "razorpay",
      type: `razorpay/${rz.code || "ERROR"}`,
      message: String(rz.description || rz.reason || rz.code || "Razorpay error"),
      unexpected: true,
      stack: "",
    };
  }
  const e = err instanceof Error ? err : new Error(String(err));
  return {
    code: "internal",
    type: e.name || "Error",
    message: String(e.message || e),
    unexpected: true,
    stack: e.stack || "",
  };
}

/** Decides whether a failure is worth recording and how serious it is. */
function classify(fnName, info) {
  if (!info.unexpected) {
    if (QUIET_CODES.has(info.code)) return { log: false };
    if (info.code === "failed-precondition" && QUIET_MESSAGES.some((r) => r.test(info.message))) {
      return { log: false };
    }
  }
  let severity = "error";
  // Money may have left the poster's account but the task was not completed.
  if (info.unexpected && fnName === "verifyRazorpayPayment") severity = "fatal";
  else if (/has not been completed/i.test(info.message)) severity = "warning";
  return { log: true, severity };
}

/**
 * Same problem -> same fingerprint whatever ids or numbers the message holds.
 * Mirrors the app's ErrorLogger.fingerprint (FNV-1a, 8 hex characters).
 */
function fingerprint(category, type, message, context) {
  const normalized = String(message)
    .toLowerCase()
    .replace(/https?:\/\/\S+/g, "<url>")
    .replace(/[0-9a-z_-]{14,}/g, "<id>")
    .replace(/\d+/g, "0");
  const input = `${category}|${type}|${normalized}||${String(context).toLowerCase()}`;
  let hash = 0x811c9dc5;
  for (let i = 0; i < input.length; i++) {
    hash ^= input.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash.toString(16).padStart(8, "0");
}

// Firestore document ids / Razorpay ids only -- the client controls `data`.
function safeId(value) {
  const s = String(value == null ? "" : value);
  return /^[\w-]{1,64}$/.test(s) ? s : "";
}

/**
 * Builds the errorLogs document (without createdAt -- the caller adds the server
 * timestamp). Returns null when the failure should not be recorded.
 *
 * [data] is the callable's request data (client-controlled, so only ids that look
 * like ids are copied); [auth] is context.auth.
 */
function buildErrorDoc({ fnName, err, isHttps, data, auth, category = "payment" }) {
  const info = describeError(err, isHttps);
  const verdict = classify(fnName, info);
  if (!verdict.log) return null;

  const context = clean(`Function: ${fnName}`, MAX_CONTEXT);
  const message = clean(info.message, MAX_MESSAGE);
  const doc = {
    category,
    severity: verdict.severity,
    message,
    errorType: clean(info.type, 80),
    fingerprint: fingerprint(category, info.type, message, context),
    context,
    platform: "server",
    status: "open",
    source: "function",
  };
  if (auth && safeId(auth.uid)) doc.uid = auth.uid;
  if (info.stack) doc.stack = clean(info.stack, MAX_STACK);

  const d = data && typeof data === "object" ? data : {};
  const taskId = safeId(d.taskId);
  if (taskId) doc.taskId = taskId;
  // Razorpay ids are what the owner needs to find the payment in the Razorpay
  // dashboard. Never the signature.
  const extra = {};
  const orderId = safeId(d.razorpayOrderId);
  const paymentId = safeId(d.razorpayPaymentId);
  if (orderId) extra.razorpayOrderId = orderId;
  if (paymentId) extra.razorpayPaymentId = paymentId;
  if (Object.keys(extra).length) doc.extra = extra;
  return doc;
}

/**
 * Limits how often the same problem is written. One limiter lives for the life of
 * a server instance, so a burst of identical failures becomes a single record.
 */
function makeLimiter(now = () => Date.now()) {
  const last = new Map();
  let written = 0;
  return {
    allow(fp) {
      if (written >= INSTANCE_CAP) return false;
      const t = now();
      const prev = last.get(fp);
      if (prev !== undefined && t - prev < REPEAT_WINDOW_MS) return false;
      if (last.size >= 500) last.clear();
      last.set(fp, t);
      written++;
      return true;
    },
  };
}

module.exports = {
  REPEAT_WINDOW_MS,
  INSTANCE_CAP,
  clean,
  redactSecrets,
  describeError,
  classify,
  fingerprint,
  buildErrorDoc,
  makeLimiter,
};
