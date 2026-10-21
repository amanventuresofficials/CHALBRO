"use strict";
// The admin panel's "Phone login" switch (App Settings).
//
// The switch itself is metadata/appConfig.phoneLoginEnabled (missing = on). It works in two places:
//   1. In the app: the login screen hides "Continue with Phone" and profile setup stops asking for a verified
//      number. The login screen cannot read Firestore yet (nobody is signed in), so it asks the public function
//      getLoginOptions, which only ever returns this one yes/no.
//   2. In Firebase: when an admin CHANGES the switch, the matching Phone provider setting
//      (signIn.phoneNumber.enabled) is changed too, so nobody can still request SMS codes by calling Firebase
//      directly. Only a change made in the panel is applied (a later manual change in the Firebase console is
//      not fought), and a change that failed is retried by the scheduled guard.
//
// Nothing here needs Firebase to be reachable to answer the app: the app-side part works on its own.

/** Missing field or anything but an explicit false means "on". */
function phoneLoginEnabledOf(data) {
  return !(data && data.phoneLoginEnabled === false);
}

function createPhoneLoginService({ db, Timestamp, identity, now = () => Date.now() }) {
  const configRef = db.collection("metadata").doc("appConfig");
  const statusRef = db.collection("metadata").doc("phoneLoginStatus");

  /** What the signed-out login screen may know. */
  async function getOptions() {
    const snap = await configRef.get();
    return { phoneLoginEnabled: phoneLoginEnabledOf(snap.exists ? snap.data() : null) };
  }

  async function writeAudit(details) {
    try {
      await db.collection("adminLogs").add({
        adminUid: "system",
        action: "phone_login_changed",
        targetId: "phoneLogin",
        details,
        timestamp: Timestamp.fromMillis(now()),
      });
    } catch (err) {
      console.error("Could not write the audit entry:", err);
    }
  }

  /** Makes Firebase's Phone provider match [wanted]; records what happened for the admin panel. */
  async function applyToFirebase(wanted, trigger) {
    const t = now();
    let current = null;
    let changed = false;
    let lastError = null;
    try {
      current = await identity.getPhoneProviderEnabled();
      if (current !== wanted) {
        await identity.setPhoneProviderEnabled(wanted);
        current = wanted;
        changed = true;
      }
    } catch (err) {
      lastError = String((err && err.message) || err).slice(0, 400);
    }
    await statusRef.set(
      {
        wantedEnabled: wanted,
        providerEnabled: current,
        checkedAt: Timestamp.fromMillis(t),
        lastError,
        trigger,
        ...(changed ? { changedAt: Timestamp.fromMillis(t) } : {}),
      },
      { merge: true },
    );
    if (changed) await writeAudit(`Firebase phone sign-in ${wanted ? "switched on" : "switched off"} (the Phone login switch was changed)`);
    return { ok: !lastError, changed, providerEnabled: current, error: lastError };
  }

  /** The appConfig document was written: act only when the phone switch really changed. */
  async function onConfigWrite(beforeData, afterData) {
    const before = phoneLoginEnabledOf(beforeData);
    const after = phoneLoginEnabledOf(afterData);
    if (before === after) return { skipped: true };
    return applyToFirebase(after, "switch changed");
  }

  /** Scheduled: a change that failed earlier (for example a missing permission) is tried again. */
  async function retryPending() {
    const status = (await statusRef.get()).data();
    if (!status || !status.lastError) return { skipped: true };
    const wanted = phoneLoginEnabledOf((await configRef.get()).data());
    return applyToFirebase(wanted, "retry");
  }

  return { getOptions, onConfigWrite, retryPending, applyToFirebase };
}

module.exports = { phoneLoginEnabledOf, createPhoneLoginService };
