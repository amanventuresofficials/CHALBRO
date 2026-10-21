"use strict";
// Admin Team (admin panel > Admin Team): adding, listing and removing admins on the SERVER.
//
// Why on the server: the browser cannot look an e-mail up in the sign-in system (only ChalBro profiles, which have
// no e-mail until the person finishes setting up), and it depends on the Firestore security rules being the newest
// ones. Here every call first checks that the CALLER is an admin, then uses the admin credentials. The rules still
// protect the `admins` collection from everyone else.
//
// Pure logic with the database and the sign-in system passed in, so it can be tested on its own.

class TeamError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code; // an HttpsError code: "permission-denied", "not-found", ...
  }
}

function createAdminTeamService({ db, auth, FieldValue, Timestamp, now = () => Date.now() }) {
  const admins = db.collection("admins");

  async function requireAdmin(callerUid) {
    if (!callerUid) throw new TeamError("unauthenticated", "Sign in first.");
    const snap = await admins.doc(callerUid).get();
    if (!snap.exists) throw new TeamError("permission-denied", "Only an admin can do this.");
  }

  async function audit(callerUid, action, targetId, details) {
    try {
      await db.collection("adminLogs").add({
        adminUid: callerUid,
        action,
        targetId,
        details,
        timestamp: Timestamp.fromMillis(now()),
      });
    } catch (err) {
      console.error("Could not write the audit entry:", err);
    }
  }

  /** Finds the sign-in account for an e-mail or a user id. */
  async function findAccount(value) {
    try {
      return value.includes("@") ? await auth.getUserByEmail(value) : await auth.getUser(value);
    } catch (err) {
      const code = String((err && err.code) || "");
      if (code === "auth/user-not-found" || code === "auth/invalid-uid" || code === "auth/invalid-email" || code === "auth/argument-error") {
        throw new TeamError(
          "not-found",
          "No sign-in account matches that. Ask the person to open the admin panel once and sign in with Google, then use the user id shown on their \"Access Denied\" screen.",
        );
      }
      throw err;
    }
  }

  async function addAdmin(callerUid, callerEmail, input) {
    await requireAdmin(callerUid);
    const value = String(input == null ? "" : input).trim();
    if (!value) throw new TeamError("invalid-argument", "Enter a user id or an e-mail address.");
    if (value.length > 200) throw new TeamError("invalid-argument", "That is too long to be a user id or an e-mail address.");

    const account = await findAccount(value);
    const uid = account.uid;
    if ((await admins.doc(uid).get()).exists) throw new TeamError("already-exists", "That person is already an admin.");

    const profile = (await db.collection("users").doc(uid).get()).data() || {};
    const email = account.email || profile.email || "";
    const displayName = profile.fullName || account.displayName || "";
    await admins.doc(uid).set({
      email,
      displayName,
      role: "admin",
      createdAt: FieldValue.serverTimestamp(),
      addedByUid: callerUid,
      addedByEmail: callerEmail || "",
    });
    await audit(callerUid, "admin_added", uid, `Granted admin access to ${email || uid}`);
    return { uid, email, displayName };
  }

  async function listAdmins(callerUid) {
    await requireAdmin(callerUid);
    const snap = await admins.get();
    const rows = snap.docs.map((d) => {
      const v = d.data();
      return {
        uid: d.id,
        email: v.email || "",
        displayName: v.displayName || "",
        role: v.role || "admin",
        addedByEmail: v.addedByEmail || "",
        createdAtMs: v.createdAt && typeof v.createdAt.toMillis === "function" ? v.createdAt.toMillis() : null,
      };
    });
    rows.sort((a, b) => (a.createdAtMs || 0) - (b.createdAtMs || 0));
    return rows;
  }

  async function removeAdmin(callerUid, uid, label = "") {
    await requireAdmin(callerUid);
    const target = String(uid == null ? "" : uid).trim();
    if (!target || target.includes("/")) throw new TeamError("invalid-argument", "That is not a user id.");
    if (target === callerUid) throw new TeamError("failed-precondition", "You cannot remove your own admin access.");
    if (!(await admins.doc(target).get()).exists) throw new TeamError("not-found", "That person is not an admin.");
    await admins.doc(target).delete();
    await audit(callerUid, "admin_revoked", target, `Removed admin access${label ? ` from ${String(label).slice(0, 80)}` : ""}`);
    return { uid: target };
  }

  return { addAdmin, listAdmins, removeAdmin };
}

module.exports = { TeamError, createAdminTeamService };
