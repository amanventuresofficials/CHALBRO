"use strict";
// The admin panel's switch for Firebase's phone sign-in captcha (reCAPTCHA Enterprise).
//
// What Firebase allows: the check always runs for real phone numbers; the only choice is whether a
// request that fails it is BLOCKED.
//     AUDIT   = watch only. Sign-in is never blocked by the check ("off" in the admin panel).
//     ENFORCE = a request that fails the check is refused ("on").
// (OFF would make the website fall back to the old captcha that failed with invalid-app-credential,
//  and SMS fraud protection needs AUDIT or ENFORCE, so this switch never uses OFF.)
//
// Modes saved by the admin panel in metadata/captchaConfig:
//     "off"  -> AUDIT          "on" -> ENFORCE
//     "auto" -> AUDIT while things are calm; ENFORCE while the app keeps hitting "too many requests"
//               (threshold problems within windowMinutes), kept on for holdMinutes after that.
//
// The app tells us about problems through the reportPhoneAuthIssue function, which only adds to small
// counters (phoneAuthEvents). Pure decisions live here so they can be tested without Firebase.

const MODES = ["on", "off", "auto"];
const AUDIT = "AUDIT";
const ENFORCE = "ENFORCE";
const BUCKET_MS = 5 * 60 * 1000;
const SHARDS = 5;
const EVENT_KEEP_MS = 2 * 24 * 3600 * 1000;

const DEFAULTS = { mode: "off", threshold: 15, windowMinutes: 10, holdMinutes: 60 };
const LIMITS = { threshold: [3, 1000], windowMinutes: [5, 120], holdMinutes: [5, 1440] };

// Firebase says "too many tries": the signal that turns "auto" on.
const RATE_CODES = new Set(["too-many-requests", "quota-exceeded"]);
// The check itself failed. Counted for the admin to see, but never turns "auto" on (that would feed itself:
// enforcing a check that is failing only creates more failures).
const CAPTCHA_CODES = new Set([
  "invalid-app-credential",
  "captcha-check-failed",
  "missing-app-credential",
  "missing-recaptcha-token",
  "invalid-recaptcha-token",
  "recaptcha-not-enabled",
]);

function clampInt(value, [lo, hi], fallback) {
  const n = Math.round(Number(value));
  if (!Number.isFinite(n)) return fallback;
  return Math.min(hi, Math.max(lo, n));
}

/** Turns the saved document (or null) into safe settings. `exists` = the admin has saved a choice at least once. */
function normalizeConfig(raw) {
  const exists = !!raw && typeof raw === "object";
  const r = exists ? raw : {};
  return {
    exists,
    mode: MODES.includes(r.mode) ? r.mode : DEFAULTS.mode,
    threshold: clampInt(r.threshold, LIMITS.threshold, DEFAULTS.threshold),
    windowMinutes: clampInt(r.windowMinutes, LIMITS.windowMinutes, DEFAULTS.windowMinutes),
    holdMinutes: clampInt(r.holdMinutes, LIMITS.holdMinutes, DEFAULTS.holdMinutes),
  };
}

function bucketOf(ms) {
  return Math.floor(ms / BUCKET_MS);
}

/** "rate" | "captcha" | null for an auth error code reported by the app. */
function classifyCode(code) {
  const c = String(code == null ? "" : code).trim();
  if (RATE_CODES.has(c)) return "rate";
  if (CAPTCHA_CODES.has(c)) return "captcha";
  return null;
}

/** Firebase's own words for the state, reduced to the three we care about. */
function parseLive(state) {
  const s = String(state || "").toUpperCase();
  if (s === "ENFORCE") return ENFORCE;
  if (s === "AUDIT") return AUDIT;
  if (s === "OFF") return "OFF";
  return "UNKNOWN";
}

/**
 * What Firebase should be set to right now.
 *  live            : what Firebase says it is now
 *  rateEvents      : "too many requests" problems the app reported inside the window
 *  autoEnforcedAt  : ms when "auto" last turned it on (or null)
 * Returns { target, autoEnforcedAt, reason }.
 */
function decideTarget({ mode, live, rateEvents, threshold, now, autoEnforcedAt, holdMinutes }) {
  if (mode === "on") return { target: ENFORCE, autoEnforcedAt: null, reason: "Set to On by an admin" };
  if (mode === "off") return { target: AUDIT, autoEnforcedAt: null, reason: "Set to Off by an admin (watch only)" };

  // auto
  if (rateEvents >= threshold) {
    return { target: ENFORCE, autoEnforcedAt: now, reason: `Too many requests: ${rateEvents} in the last few minutes` };
  }
  const holdMs = holdMinutes * 60 * 1000;
  if (live === ENFORCE && autoEnforcedAt && now - autoEnforcedAt < holdMs) {
    return { target: ENFORCE, autoEnforcedAt, reason: "Staying on for a while after too many requests" };
  }
  return { target: AUDIT, autoEnforcedAt: null, reason: "Calm: watching only" };
}

// ─── Talking to Firebase (Identity Toolkit admin API) ─────────────────────────

const API_HOST = "https://identitytoolkit.googleapis.com";

/**
 * getToken(): Promise<string>  an access token of this project's own service account.
 * Only the one field recaptchaConfig.phoneEnforcementState is ever read or written, so the other
 * settings (SMS fraud protection, site keys) are left exactly as they are.
 */
function makeIdentityClient({ projectId, getToken, fetchFn = (...a) => fetch(...a) }) {
  const url = `${API_HOST}/v2/projects/${projectId}/config`;

  async function call(method, fullUrl, body) {
    const res = await fetchFn(fullUrl, {
      method,
      headers: { Authorization: `Bearer ${await getToken()}`, "Content-Type": "application/json" },
      body: body ? JSON.stringify(body) : undefined,
    });
    let json = null;
    try {
      json = await res.json();
    } catch (_) {
      /* an empty body is fine */
    }
    if (!res.ok) {
      const msg = (json && json.error && (json.error.message || json.error.status)) || `HTTP ${res.status}`;
      const err = new Error(`Firebase said no (${res.status}): ${String(msg).slice(0, 300)}`);
      err.status = res.status;
      throw err;
    }
    return json;
  }

  return {
    async getPhoneState() {
      const json = await call("GET", url);
      return parseLive(json && json.recaptchaConfig && json.recaptchaConfig.phoneEnforcementState);
    },
    async setPhoneState(state) {
      if (state !== AUDIT && state !== ENFORCE) throw new Error(`Refusing to set the phone check to "${state}"`);
      await call("PATCH", `${url}?updateMask=recaptchaConfig.phoneEnforcementState`, {
        recaptchaConfig: { phoneEnforcementState: state },
      });
    },
  };
}

// ─── The service: counters + reconcile ───────────────────────────────────────

function toMs(v) {
  if (!v) return null;
  if (typeof v.toMillis === "function") return v.toMillis();
  if (typeof v === "number") return v;
  return null;
}

function createCaptchaService({ db, FieldValue, Timestamp, identity, now = () => Date.now(), random = Math.random }) {
  const configRef = db.collection("metadata").doc("captchaConfig");
  const statusRef = db.collection("metadata").doc("captchaStatus");
  const events = db.collection("phoneAuthEvents");

  // A flood of reports must not become a flood of writes.
  let windowStart = 0;
  let windowCount = 0;
  const MAX_REPORTS_PER_MINUTE = 120;

  /** Counts one problem the app ran into. Never throws. */
  async function reportIssue(code) {
    const kind = classifyCode(code);
    if (!kind) return { counted: false };
    const t = now();
    if (t - windowStart > 60 * 1000) {
      windowStart = t;
      windowCount = 0;
    }
    if (++windowCount > MAX_REPORTS_PER_MINUTE) return { counted: false, limited: true };
    const bucket = bucketOf(t);
    const shard = Math.floor(random() * SHARDS);
    try {
      await events.doc(`${bucket}_${shard}`).set(
        { bucket, [kind]: FieldValue.increment(1), updatedAt: Timestamp.fromMillis(t) },
        { merge: true },
      );
      return { counted: true, kind };
    } catch (err) {
      console.error("Could not count a phone sign-in problem:", err);
      return { counted: false };
    }
  }

  async function countRecent(windowMinutes) {
    const start = bucketOf(now()) - Math.ceil((windowMinutes * 60 * 1000) / BUCKET_MS) + 1;
    const snap = await events.where("bucket", ">=", start).get();
    let rate = 0;
    let captcha = 0;
    snap.forEach((d) => {
      const v = d.data();
      rate += Number(v.rate) || 0;
      captcha += Number(v.captcha) || 0;
    });
    return { rate, captcha };
  }

  async function writeAudit(details) {
    try {
      await db.collection("adminLogs").add({
        adminUid: "system",
        action: "captcha_state_changed",
        targetId: "captcha",
        details,
        timestamp: Timestamp.fromMillis(now()),
      });
    } catch (err) {
      console.error("Could not write the audit entry:", err);
    }
  }

  /**
   * Looks at the saved choice, the counters and what Firebase says, and changes Firebase if it differs.
   * Nothing is changed until an admin has saved a choice once (so deploying this never flips a live setting).
   */
  async function reconcile(trigger = "scheduled") {
    const t = now();
    const cfg = normalizeConfig((await configRef.get()).data() || null);
    const prev = (await statusRef.get()).data() || {};

    let live;
    try {
      live = await identity.getPhoneState();
    } catch (err) {
      await statusRef.set(
        { checkedAt: Timestamp.fromMillis(t), lastError: String(err.message || err).slice(0, 400), managed: cfg.exists, trigger },
        { merge: true },
      );
      return { ok: false, error: err.message };
    }

    const counts = await countRecent(cfg.windowMinutes);
    const base = {
      mode: cfg.mode,
      threshold: cfg.threshold,
      windowMinutes: cfg.windowMinutes,
      holdMinutes: cfg.holdMinutes,
      rateEvents: counts.rate,
      captchaEvents: counts.captcha,
      checkedAt: Timestamp.fromMillis(t),
      managed: cfg.exists,
      trigger,
    };

    if (!cfg.exists) {
      await statusRef.set({ ...base, liveState: live, wantedState: live, reason: "No choice saved yet: nothing is managed", lastError: null }, { merge: true });
      return { ok: true, changed: false, live, managed: false };
    }

    const decision = decideTarget({
      mode: cfg.mode,
      live,
      rateEvents: counts.rate,
      threshold: cfg.threshold,
      now: t,
      autoEnforcedAt: toMs(prev.autoEnforcedAt),
      holdMinutes: cfg.holdMinutes,
    });

    let applied = live;
    let changed = false;
    let lastError = null;
    if (decision.target !== live) {
      try {
        await identity.setPhoneState(decision.target);
        applied = decision.target;
        changed = true;
      } catch (err) {
        lastError = String(err.message || err).slice(0, 400);
      }
    }

    const keepAuto = cfg.mode === "auto" && applied === ENFORCE ? decision.autoEnforcedAt : null;
    await statusRef.set(
      {
        ...base,
        liveState: applied,
        wantedState: decision.target,
        reason: decision.reason,
        autoEnforcedAt: keepAuto ? Timestamp.fromMillis(keepAuto) : null,
        lastError,
        ...(changed ? { changedAt: Timestamp.fromMillis(t), changeReason: decision.reason } : {}),
      },
      { merge: true },
    );
    if (changed) {
      await writeAudit(`Phone sign-in captcha changed from ${live} to ${applied}: ${decision.reason}`);
    }
    return { ok: !lastError, changed, live: applied, wanted: decision.target, error: lastError };
  }

  /** Deletes counters older than two days. */
  async function cleanup() {
    const cutoff = bucketOf(now() - EVENT_KEEP_MS);
    const snap = await events.where("bucket", "<", cutoff).limit(300).get();
    if (snap.empty) return 0;
    const batch = db.batch();
    snap.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    return snap.size;
  }

  return { reportIssue, reconcile, cleanup, countRecent };
}

module.exports = {
  MODES,
  AUDIT,
  ENFORCE,
  BUCKET_MS,
  DEFAULTS,
  LIMITS,
  normalizeConfig,
  bucketOf,
  classifyCode,
  parseLive,
  decideTarget,
  makeIdentityClient,
  createCaptchaService,
};
