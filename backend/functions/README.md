# ChalBro Cloud Functions

| Function | Trigger | What it does |
|----------|---------|--------------|
| `createRazorpayOrder` | app call | Works out what the poster pays (agreed price minus the admin's discount) and creates the Razorpay order. The amount never comes from the app. |
| `verifyRazorpayPayment` | app call | Checks the payment really happened for that task and amount, completes the task, credits the helper's `earnings` (90%), writes the review and the history entries, and tells the helper. It first settles any `feeDue` the helper owes from cash jobs, and, if direct payouts are on and a UPI id is linked, moves the balance into a withdrawal that `autoPayWithdrawal` sends. |
| `claimCashPayment` | app call | The poster says the job was paid in cash. Only while payments are on. The helper is asked to confirm. |
| `answerCashPayment` | app call | The helper confirms (task completes as a cash job, helper owes the 10% fee as `feeDue`) or says they did not get it (claim cleared). |
| `autoPayWithdrawal` | new `withdrawals/{id}` | When direct payouts are on, claims the withdrawal (`processing`) and sends it to the UPI id through RazorpayX. On an API error it goes back to `pending` for a person; if the network died it stays `processing` with a warning. |
| `razorpayXWebhook` | HTTPS | RazorpayX reports how a payout ended: processed -> `approved`, reversed/failed/rejected/cancelled -> `rejected` and the money returns to the helper's earnings. Signature-checked. |
| `sendPushNotification` | new notification | Sends a push for every in-app notification. |

## Settings and secrets

**`functions/.env`** (never committed) holds only harmless ids, see `.env.example`:

```
RAZORPAY_KEY_ID=...            # Razorpay dashboard > Settings > API keys (not secret)
RAZORPAYX_ACCOUNT_NUMBER=      # only for direct UPI payouts (RazorpayX dashboard)
```

**The two secrets live in Google Secret Manager**, not in a file, not in the code and not in the deployed bundle. Each is
handed, as an ordinary environment variable, only to the functions that need it (see `PAYMENT_SECRETS` / `WEBHOOK_SECRETS`
in `index.js`). You type each value once; it is never shown again:

```
firebase functions:secrets:set RAZORPAY_KEY_SECRET        # the Razorpay Key Secret
firebase functions:secrets:set RAZORPAYX_WEBHOOK_SECRET   # any long random text (the same text goes into the RazorpayX webhook)
```

Do not put those two names in `.env` as well: Firebase refuses to deploy when a name is in both places. To change a secret
later run the same command again, then redeploy the functions. For the local emulator put the values in
`functions/.secret.local` (git-ignored). Deploying needs the Blaze plan; Secret Manager is part of it.

Why: a secret in `.env` is uploaded with the code to a storage bucket and sits in a file on your PC. In Secret Manager it is
encrypted, access is controlled by Google IAM and every read is logged. Server errors are also scrubbed: a secret value can
never end up in the error logs (`errorlog.js`, tested).

The switches themselves are in the admin panel (Payments & Discount): `useRazorpay` and `autoPayout` in `metadata/paymentConfig`.

## Phone sign-in captcha switch (admin panel > App Settings)

`captcha.js` + three functions: `reportPhoneAuthIssue` (the app reports "too many requests" / captcha failures, it only adds to
a counter in `phoneAuthEvents`), `captchaOnConfigWrite` (applies the choice saved in `metadata/captchaConfig`) and `captchaGuard`
(every 2 minutes: turns Auto on/off, refreshes `metadata/captchaStatus`, deletes old counters). They set ONE field of Firebase's
config, `recaptchaConfig.phoneEnforcementState`: Off = `AUDIT` (a failed check never blocks), On = `ENFORCE`. `OFF` is never used.
Nothing changes until an admin saves a choice once.

One-time setup: the functions run as `chal-bro@appspot.gserviceaccount.com`; if the admin panel shows "Firebase said no (403)",
give that account the role **Firebase Authentication Admin** (Google Cloud Console > IAM). The first deploy of `captchaGuard`
also enables Cloud Scheduler.

## Tests

```
cd functions && npm test      # unit tests: money maths, RazorpayX client, error logging, captcha switch


# from the project folder (chalbroo): the real functions against the Firestore emulator
firebase emulators:exec --only firestore --project demo-chalbro "node functions/test/payments.e2e.js"
firebase emulators:exec --only firestore --project demo-chalbro "node functions/test/cash_payout.e2e.js"
firebase emulators:exec --only firestore --project demo-chalbro "node functions/test/captcha.e2e.js"   # captcha switch (Firebase's setting replaced by a stand-in)
```

The end-to-end tests replace Razorpay and RazorpayX with stand-ins and refuse to run unless `FIRESTORE_EMULATOR_HOST` is set, so they can never touch the live project.

## Adding an admin

```
cd functions
node scripts/add_admin.js --email person@gmail.com --name "Their Name"
```

It asks for the new person's password and for the e-mail + password of an EXISTING admin (typed on screen, hidden, never stored), creates their sign-in and adds them to the admin list with an audit-log line. Needs no service-account key. A Google-only admin cannot be used to run it; use the admin panel's *Admin Team* page instead. Tested against the emulators (`npm run test:add-admin`, 7 checks).
