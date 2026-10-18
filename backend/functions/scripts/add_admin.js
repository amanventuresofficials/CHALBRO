#!/usr/bin/env node
"use strict";
/**
 * Adds someone as a ChalBro ADMIN (can sign in at https://chalbro-admin.web.app).
 *
 *   cd chalbroo/functions
 *   node scripts/add_admin.js --email person@gmail.com [--name "Their Name"]
 *
 * What it does, in plain words
 *   1. asks you for the NEW person's password (typed on screen, hidden) and creates their sign-in
 *      (or, if they already have one, checks that password),
 *   2. asks for the e-mail and password of an EXISTING admin (you) and signs in as them,
 *   3. as that admin, writes the new person into the `admins` list and adds a line to the audit log.
 *
 * It uses the same public sign-in service the website uses, so it needs NO service-account key, no
 * gcloud and no special access: only an existing admin who signs in with e-mail + password (a Google-only
 * admin cannot be used here; add the person from the admin panel's "Admin Team" page instead).
 * Nothing is stored or written to disk; passwords live in memory only while the script runs.
 *
 * Options:  --project chal-bro   --api-key <web api key>   (defaults are this app's)
 * Local test (emulators): set FIREBASE_AUTH_EMULATOR_HOST and FIRESTORE_EMULATOR_HOST.
 */
const readline = require("readline");

const WEB_API_KEY = "AIzaSyA68T53L1Fb2Ft_wMhT3f0UVE0gfqvzaMc"; // public by design (it is inside the website)

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    if (argv[i].startsWith("--")) out[argv[i].slice(2)] = argv[i + 1] && !argv[i + 1].startsWith("--") ? argv[++i] : true;
  }
  return out;
}

function ask(question, hidden = false) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout, terminal: true });
    rl.stdoutMuted = false;
    rl._writeToOutput = (s) => { if (!rl.stdoutMuted) rl.output.write(s); };
    rl.question(question, (answer) => {
      rl.close();
      if (hidden) process.stdout.write("\n");
      resolve(answer.trim());
    });
    if (hidden) rl.stdoutMuted = true; // the prompt is already printed; hide what is typed
  });
}

function endpoints(env, project, apiKey) {
  const authHost = env.FIREBASE_AUTH_EMULATOR_HOST;
  const fsHost = env.FIRESTORE_EMULATOR_HOST;
  return {
    auth: authHost
      ? (m) => `http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:${m}?key=fake`
      : (m) => `https://identitytoolkit.googleapis.com/v1/accounts:${m}?key=${apiKey}`,
    docs: fsHost
      ? `http://${fsHost}/v1/projects/${project}/databases/(default)/documents`
      : `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`,
  };
}

async function postJson(url, body, headers = {}) {
  const res = await fetch(url, {
    method: "POST",
    // The web key may be restricted to the websites; say which site is asking, as a browser would.
    headers: { "Content-Type": "application/json", Referer: "https://chalbro-admin.web.app/", ...headers },
    body: JSON.stringify(body),
  });
  const json = await res.json().catch(() => ({}));
  return { ok: res.ok, status: res.status, json };
}

const authMessage = (json) => (json && json.error && json.error.message) || "unknown error";

/** Finds or creates the new person's sign-in. Returns { uid, created }. */
async function ensureUser(urls, email, password, name) {
  const created = await postJson(urls.auth("signUp"), { email, password, returnSecureToken: true });
  if (created.ok) {
    if (name) await postJson(urls.auth("update"), { idToken: created.json.idToken, displayName: name, returnSecureToken: false });
    return { uid: created.json.localId, created: true };
  }
  if (!String(authMessage(created.json)).startsWith("EMAIL_EXISTS")) {
    throw new Error(`Could not create the sign-in: ${authMessage(created.json)}`);
  }
  const existing = await postJson(urls.auth("signInWithPassword"), { email, password, returnSecureToken: true });
  if (!existing.ok) {
    throw new Error("That e-mail already has a sign-in, and the password you typed is not its password.");
  }
  return { uid: existing.json.localId, created: false };
}

async function signInAsAdmin(urls, email, password) {
  const r = await postJson(urls.auth("signInWithPassword"), { email, password, returnSecureToken: true });
  if (!r.ok) throw new Error(`Could not sign in as the existing admin (${authMessage(r.json)}).`);
  return { uid: r.json.localId, email: r.json.email || email, token: r.json.idToken };
}

const str = (v) => ({ stringValue: String(v) });
const ts = () => ({ timestampValue: new Date().toISOString() });

async function grantAdmin(urls, admin, uid, email, name) {
  const headers = { Authorization: `Bearer ${admin.token}` };
  const check = await fetch(`${urls.docs}/admins/${uid}`, { headers });
  if (check.status === 200) return { already: true };
  if (check.status !== 404) throw new Error(`The admin list could not be read (HTTP ${check.status}). Is ${admin.email} really an admin?`);

  const fields = {
    email: str(email),
    displayName: str(name || email),
    role: str("admin"),
    createdAt: ts(),
    addedByUid: str(admin.uid),
    addedByEmail: str(admin.email),
  };
  const write = await fetch(`${urls.docs}/admins/${uid}?currentDocument.exists=false`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json", ...headers },
    body: JSON.stringify({ fields }),
  });
  if (!write.ok) {
    throw new Error(`The admin list refused the change (HTTP ${write.status}). Only an existing admin can add admins.`);
  }
  // The same audit line the admin panel writes.
  await fetch(`${urls.docs}/adminLogs`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: JSON.stringify({
      fields: {
        adminUid: str(admin.uid),
        action: str("admin_added"),
        targetId: str(uid),
        details: str(`Granted admin access to ${email} (add_admin script)`),
        timestamp: ts(),
      },
    }),
  });
  return { already: false };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const env = process.env;
  const email = String(args.email || "").trim().toLowerCase();
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    console.error('Usage: node scripts/add_admin.js --email person@gmail.com [--name "Their Name"]');
    process.exit(2);
  }
  const urls = endpoints(env, args.project || "chal-bro", args["api-key"] || WEB_API_KEY);

  console.log(`\nAdding ${email} as an admin.\n`);
  // Passwords may be given through the environment for automated tests only; normally you type them.
  const newPassword = env.ADD_ADMIN_NEW_PASSWORD || (await ask(`Password for ${email} (at least 8 characters, make it strong): `, true));
  if (newPassword.length < 8) throw new Error("The password must have at least 8 characters.");
  const adminEmail = (env.ADD_ADMIN_BY_EMAIL || (await ask("E-mail of an EXISTING admin (you): "))).toLowerCase();
  const adminPassword = env.ADD_ADMIN_BY_PASSWORD || (await ask("That admin's password: ", true));

  const target = await ensureUser(urls, email, newPassword, args.name);
  console.log(target.created ? "Created the sign-in." : "The sign-in already existed; its password is correct.");
  const admin = await signInAsAdmin(urls, adminEmail, adminPassword);
  const result = await grantAdmin(urls, admin, target.uid, email, args.name);
  console.log(result.already
    ? `${email} was already an admin.`
    : `Done. ${email} is now an admin and can sign in at https://chalbro-admin.web.app with that password.`);
  console.log("Tip: they should change the password after the first login.");
}

module.exports = { parseArgs, endpoints, ensureUser, signInAsAdmin, grantAdmin };

if (require.main === module) {
  main().then(() => process.exit(0)).catch((e) => { console.error(`\nNot done: ${e.message}`); process.exit(1); });
}
