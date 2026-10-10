// Unit tests for the server-side error recording helpers. Run: npm test
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  clean, describeError, classify, fingerprint, buildErrorDoc, makeLimiter, REPEAT_WINDOW_MS, INSTANCE_CAP,
} = require("../errorlog");

const httpsErr = (code, message) => Object.assign(new Error(message), { code });

test("clean masks e-mails and phone-like numbers and truncates", () => {
  assert.equal(clean("mail me at jo.doe+x@example.co.in now", 100), "mail me at <email> now");
  assert.equal(clean("call +91 98765 43210 please", 100), "call <number> please");
  const long = clean("x".repeat(600), 500);
  assert.equal(long.length, 500);
  assert.ok(long.endsWith("…"));
  assert.equal(clean(null, 10), "");
});

test("describeError tells deliberate answers from real failures", () => {
  const a = describeError(httpsErr("permission-denied", "nope"), true);
  assert.deepEqual([a.code, a.type, a.unexpected], ["permission-denied", "functions/permission-denied", false]);

  // Razorpay's SDK rejects with a plain object, not an Error.
  const rz = describeError({ statusCode: 401, error: { code: "BAD_REQUEST_ERROR", description: "Authentication failed" } }, false);
  assert.deepEqual([rz.type, rz.message, rz.unexpected], ["razorpay/BAD_REQUEST_ERROR", "Authentication failed", true]);

  const plain = describeError(new TypeError("boom"), false);
  assert.deepEqual([plain.type, plain.message, plain.unexpected], ["TypeError", "boom", true]);
  assert.ok(plain.stack.includes("TypeError"));

  const str = describeError("just a string", false);
  assert.equal(str.message, "just a string");
});

test("classify ignores ordinary caller mistakes", () => {
  for (const code of ["unauthenticated", "invalid-argument", "not-found"]) {
    assert.equal(classify("verifyRazorpayPayment", describeError(httpsErr(code, "x"), true)).log, false, code);
  }
  for (const m of ["This task has already been paid.", "Hire a helper before paying for this task.", "This task is not awaiting payment."]) {
    assert.equal(classify("createRazorpayOrder", describeError(httpsErr("failed-precondition", m), true)).log, false, m);
  }
});

test("classify records real payment problems with sensible severity", () => {
  const sig = classify("verifyRazorpayPayment", describeError(httpsErr("permission-denied", "Payment signature verification failed."), true));
  assert.deepEqual(sig, { log: true, severity: "error" });

  const notPaid = classify("verifyRazorpayPayment", describeError(httpsErr("failed-precondition", "Payment has not been completed."), true));
  assert.deepEqual(notPaid, { log: true, severity: "warning" });

  const mismatch = classify("verifyRazorpayPayment", describeError(httpsErr("failed-precondition", "Paid amount does not match the order."), true));
  assert.deepEqual(mismatch, { log: true, severity: "error" });

  const noPrice = classify("createRazorpayOrder", describeError(httpsErr("failed-precondition", "Task has no valid price."), true));
  assert.deepEqual(noPrice, { log: true, severity: "error" });
});

test("an unexpected failure while verifying a payment is fatal (money may have moved)", () => {
  const info = describeError(new Error("commit failed"), false);
  assert.deepEqual(classify("verifyRazorpayPayment", info), { log: true, severity: "fatal" });
  assert.deepEqual(classify("createRazorpayOrder", info), { log: true, severity: "error" });
});

test("fingerprint groups the same problem and separates different ones", () => {
  const f = (cat, type, msg, ctx = "Function: a") => fingerprint(cat, type, msg, ctx);
  assert.equal(
    f("payment", "t", "Order order_AbCdEfGhIjKlMn12 failed after 3 tries"),
    f("payment", "t", "Order order_ZyXwVuTsRqPoNm99 failed after 9 tries"),
  );
  const base = f("payment", "t", "boom");
  assert.notEqual(f("app", "t", "boom"), base);
  assert.notEqual(f("payment", "u", "boom"), base);
  assert.notEqual(f("payment", "t", "bang"), base);
  assert.notEqual(f("payment", "t", "boom", "Function: b"), base);
  assert.match(base, /^[0-9a-f]{8}$/);
});

test("fingerprint matches the app's Dart implementation for the same input", () => {
  // Dart: ErrorLogger.fingerprint('app','T','m',null) -> same FNV-1a over "app|T|m||" (value computed by hand below)
  let h = 0x811c9dc5;
  for (const ch of "app|T|m||") { h ^= ch.charCodeAt(0); h = Math.imul(h, 0x01000193) >>> 0; }
  assert.equal(fingerprint("app", "T", "m", ""), h.toString(16).padStart(8, "0"));
});

test("buildErrorDoc: shape, ids and what it must never contain", () => {
  const doc = buildErrorDoc({
    fnName: "verifyRazorpayPayment",
    err: httpsErr("permission-denied", "Payment signature verification failed."),
    isHttps: true,
    auth: { uid: "uid_123" },
    data: {
      taskId: "task_abc",
      razorpayOrderId: "order_X1",
      razorpayPaymentId: "pay_Y2",
      razorpaySignature: "SUPERSECRETSIGNATURE",
      givenRating: 5,
    },
  });
  assert.equal(doc.category, "payment");
  assert.equal(doc.severity, "error");
  assert.equal(doc.source, "function");
  assert.equal(doc.platform, "server");
  assert.equal(doc.status, "open");
  assert.equal(doc.uid, "uid_123");
  assert.equal(doc.taskId, "task_abc");
  assert.equal(doc.context, "Function: verifyRazorpayPayment");
  assert.deepEqual(doc.extra, { razorpayOrderId: "order_X1", razorpayPaymentId: "pay_Y2" });
  assert.equal(doc.errorType, "functions/permission-denied");
  assert.ok(!JSON.stringify(doc).includes("SUPERSECRETSIGNATURE"), "the signature must never be copied");
  assert.ok(!("createdAt" in doc), "the caller adds the server timestamp");
});

test("buildErrorDoc: nothing for ordinary mistakes; client-supplied junk is not copied", () => {
  assert.equal(buildErrorDoc({ fnName: "createRazorpayOrder", err: httpsErr("unauthenticated", "x"), isHttps: true, auth: null, data: {} }), null);

  const doc = buildErrorDoc({
    fnName: "createRazorpayOrder",
    err: new Error("Reach me at someone@example.com or +91 98765 43210"),
    isHttps: false,
    auth: null,
    data: { taskId: "<script>alert(1)</script>", razorpayOrderId: { a: 1 } },
  });
  assert.ok(doc);
  assert.ok(!("uid" in doc));
  assert.ok(!("taskId" in doc));
  assert.ok(!("extra" in doc));
  assert.ok(!/someone@example\.com/.test(doc.message));
  assert.ok(!/98765/.test(doc.message));
  assert.ok(doc.stack.length > 0 && doc.stack.length <= 3500);
});

test("buildErrorDoc: the sendPushNotification failure is filed under 'app'", () => {
  const doc = buildErrorDoc({ fnName: "sendPushNotification", err: new Error("FCM down"), isHttps: false, auth: null, data: null, category: "app" });
  assert.equal(doc.category, "app");
  assert.equal(doc.context, "Function: sendPushNotification");
});

test("limiter: one record per problem per window, and a hard cap", () => {
  let t = 1_000_000;
  const lim = makeLimiter(() => t);
  assert.equal(lim.allow("aaaa"), true);
  assert.equal(lim.allow("aaaa"), false);
  assert.equal(lim.allow("bbbb"), true);
  t += REPEAT_WINDOW_MS - 1;
  assert.equal(lim.allow("aaaa"), false);
  t += 2;
  assert.equal(lim.allow("aaaa"), true);

  const capped = makeLimiter(() => t);
  let allowed = 0;
  for (let i = 0; i < INSTANCE_CAP + 50; i++) if (capped.allow(`fp${i}`)) allowed++;
  assert.equal(allowed, INSTANCE_CAP);
});
