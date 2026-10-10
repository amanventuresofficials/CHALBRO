# ChalBro web hand-off

ChalBro is a Flutter app (Android app already live on Google Play). This package is the **web version**
for iOS and desktop users, plus the Firebase backend it shares with the Android app.

**Refreshed 2026-10-08 to match Android build `1.0.0+10` (build 9 adds a Logout button on the Complete Profile page; build 7 fixed a Home-screen crash that build 6 had on Android; build 8 starts new wallets at ₹0 when Razorpay is on).** What changed since the first hand-off: helpers are shown by
first name only and their full details appear only after they are hired; a task is private to the poster and the hired
helper once assigned; an admin-controlled discount (see "Payments switch"); clearer "what is missing" messages on the
sign-in and profile forms; rewritten Firestore rules with an automated test suite (`backend/rules_test`).
New in `1.0.0+6` (see section 6): the app reports its own errors to the owner (app / payment / database), users can
report a task or a person, and the owner can switch the app into maintenance mode, close sign-ups, set a minimum app
version and task price limits from the admin panel (the admin panel itself is a separate project, `admin_panel/`).

```
chalbro_web_handoff/
  frontend/          Built, deploy-ready website (upload this to the domain)
  frontend_source/   Flutter source, only needed if you want to change/rebuild the site
  backend/           Cloud Functions (+ tests) + Firestore/Storage rules + indexes + rules tests (backend/rules_test)
  firebase.json      Firebase deploy config (hosting + rules + functions)
  .env.example       Every config value in one place (see below)
```

## 1. Host the website (any host)

Upload the contents of `frontend/` to the web root of your domain. Requirements:

- **HTTPS is required** (sign-in and secure storage need it).
- **Single-page-app fallback**: any path that isn't a real file must serve `index.html`.

nginx:
```nginx
location / { try_files $uri $uri/ /index.html; }
location = /index.html { add_header Cache-Control "no-cache"; }
location = /config.js  { add_header Cache-Control "no-cache"; }
```
Apache (`.htaccess`):
```apache
RewriteEngine On
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.html [L]
```
Using Firebase Hosting instead: from this folder run `firebase deploy --only hosting`.

## 2. Authorize your domain (required, or sign-in fails)

In the Firebase project `chal-bro` (you need to be added as a member of it):

1. **Firebase Console > Authentication > Settings > Authorized domains** -> add your domain.
2. **Google sign-in**: Google Cloud Console > APIs & Services > Credentials > the *Web client (auto created by Google Service)*
   -> add `https://YOUR-DOMAIN` under **Authorized JavaScript origins**.
3. **Phone sign-in** needs nothing else (invisible reCAPTCHA is automatic once the domain is authorized).
4. Recommended: Cloud Console > Credentials > the browser key `AIzaSyA68T53L1Fb2Ft_wMhT3f0UVE0gfqvzaMc`
   -> restrict to **HTTP referrers** = your domain.

## 3. Optional: the "Nearby" map

Edit `frontend/config.js` on the server and set `googleMapsApiKey` (Maps JavaScript API key, restricted to your domain).
Without a key the app works; only the map is unavailable. No rebuild is needed.

## 4. Backend (Firebase)

Needs the **Blaze (pay-as-you-go) plan** and the *Cloud Functions API* enabled -- neither is set up yet, so **no function is
deployed today** (this also means push notifications from the server aren't being sent yet).

```
cp backend/functions/.env.example backend/functions/.env    # then fill in the Razorpay keys
cd backend/functions && npm install && cd ../..
firebase deploy --only functions
```
Rules/indexes: `firebase deploy --only firestore:rules,firestore:indexes,storage`

> **`firestore.rules` are NOT deployed yet.** They were rewritten for this release (a task becomes private once someone is
> hired, task updates are role-checked, wallets/ratings cannot be self-edited, new `reviews` collection) and extended for
> `1.0.0+6` (new `errorLogs` and `reports` collections, admin-managed `admins`, admin broadcast notifications). They are
> covered by 163 automated emulator checks: `cd backend/rules_test && npm install && npm test`. Accepting an offer, paying
> (with a discount) and the resulting review record were also clicked through in the real app against the emulator.
>
> **Deploy order matters:** (1) `firebase deploy --only firestore:indexes` (safe, additive), (2) release the app version
> `1.0.0+10` (or at least `1.0.0+5`) to users, (3) only then `firebase deploy --only firestore:rules`. Older app builds
> (`1.0.0+4` and below) read tasks in ways the new rules block (Home "open tasks", My Tasks "Applied", profile reviews), so
> deploying the rules first would break them for anyone who has not updated. Until the rules are deployed, the admin
> panel's Reports, Admin Team, Errors & Health and Notifications pages show a "permission denied" notice, and the app's
> error reports are silently dropped (the app never shows an error for that).

### Two balances: practice wallet and real balance
Each user document has two numbers. `walletBalance` is **practice (test) credit**: ₹500 at sign-up, used while `useRazorpay` is false,
never withdrawable. `realBalance` is **real money**: it starts at 0 and only the `verifyRazorpayPayment` Cloud Function (Admin SDK) or an admin
can raise it; the owner of the account can only lower it (by withdrawing). The app shows `realBalance` (and the history entries tagged
`real: true`) while `useRazorpay` is true, and `walletBalance` (untagged history) while it is false. Switching Razorpay on or off deletes
nothing; the admin Revenue, Overview and Transactions pages count Razorpay payments only.

### Withdrawals (helpers taking money out)
Only while `useRazorpay` is true. In the app a helper enters an amount (₹100 to ₹100000) and a UPI ID; one batch writes `withdrawals/{id}`
(`uid, amount, paymentDetails, userName, status:'pending', timestamp`) AND lowers their `realBalance` by exactly that amount (the rules verify this with
`getAfter`, so the same money cannot be requested twice). The owner pays by hand from a banking app and presses the green tick in the admin
panel (`status:'approved'`, optional `paidReference`); rejecting refunds the real balance. Both outcomes notify the helper. Nothing is paid out automatically.

### Payments switch
Payments are controlled live from Firestore, no app update needed. The admin panel has a **"Payments & Discount"** screen
that edits the document `metadata/paymentConfig` for you; you can also create it by hand:

| field             | value | meaning |
|-------------------|-------|---------|
| `paymentsEnabled` | true  | master on/off for the Pay button |
| `useRazorpay`     | false | false = built-in dummy wallet, true = real Razorpay |
| `discountEnabled` | false | true = the poster gets the discount below |
| `discountPercent` | 10    | whole number 1-90; the poster pays that % less, the helper still earns 90% of the agreed price, ChalBro absorbs the difference |

The **web build does not support Razorpay checkout** (the Flutter Razorpay plugin is mobile-only). With
`useRazorpay = true`, web users see "Payments are only available in the mobile app". Adding Razorpay's web checkout
(`checkout.js`) is a future task and can reuse the existing `createRazorpayOrder` / `verifyRazorpayPayment` functions.

## 5. Rebuild from source (only if you change the app)

Use **Flutter 3.22.3 (stable)** -- please do not upgrade; the project's plugins are pinned to it.
```
cd frontend_source
flutter pub get
flutter build web --release        # output: build/web  (replace frontend/ with it, keep your config.js)
```

## 6. Owner tools added in `1.0.0+6` (what the app writes and reads)

| Firestore path | Written by | Read by | What it is |
|---|---|---|---|
| `errorLogs/{auto id}` | the app (any signed-in user) and the payment Cloud Functions | admin panel > Errors & Health | One record per problem: `category` (`app` / `payment` / `database`), `severity` (`fatal` / `error` / `warning`), `message`, `errorType`, `fingerprint` (groups the same problem), `context`, `uid` (only the user id, never name / phone / e-mail), `appVersion`, `platform`, `status` (`open` / `resolved` / `ignored`), `source` (`client` / `function`), `createdAt`, and optionally `stack`, `taskId`, `extra`. Users can only add records; only admins can read, change or delete them. |
| `reports/{reporterUid}_{task\|user}_{targetId}` | the app ("Report this task", "Report" on a profile) | admin panel > Reports | The document id allows one report per person per target. Reasons: spam, abuse, fraud, fake, inappropriate, other. |
| `metadata/appConfig` | admin panel > App Settings | the app (everyone, read-only) | `maintenanceMode`, `maintenanceMessage`, `minBuildNumber`, `allowNewRegistrations`, `minTaskPrice`, `maxTaskPrice`. Missing or unreadable means no restriction. The web build obeys maintenance mode and closed sign-ups but is never blocked by `minBuildNumber` (the web version is always the newest). |
| `users/{uid}/notifications/{id}` with `type: 'admin_broadcast'` | admin panel > Notifications | the user's app | Messages from the owner. They appear in the in-app notification list; once Cloud Functions are deployed the existing `sendPushNotification` function also sends them as push notifications. |
| `admins/{uid}` | admin panel > Admin Team | admin panel and the rules | Who is an admin. Only an existing admin can add or remove admins, and nobody can remove themselves. |

**How errors are recorded.** In the app, `lib/services/error_logger.dart` hooks Flutter's global error handlers and the
catch blocks around payments, uploads and database writes. It never blocks the UI, never records personal data (user id
only; e-mail addresses and long digit runs in messages are masked), sends at most 25 records per app session, sends the
same problem at most once per 10 minutes, and ignores plain connectivity noise. Errors before sign-in are not recorded
(the rules only let signed-in users write). In the Cloud Functions, `backend/functions/errorlog.js` does the same for
`createRazorpayOrder`, `verifyRazorpayPayment` and `sendPushNotification`: ordinary caller mistakes (not signed in, task
already paid ...) are ignored, a wrong payment signature or a mismatched payment is an `error`, and an unexpected failure
while verifying a payment is `fatal` because money may have been taken without the task being completed (the record then
carries the Razorpay order and payment ids so it can be found in the Razorpay dashboard). The payment signature is never
copied into a log record.

**Tests.** `backend/functions`: `npm test` (helpers, no emulator) and, from the folder that holds `firebase.json`,
`firebase emulators:exec --only firestore --project demo-chalbro "node backend/functions/test/payments.e2e.js"`
(runs the real payment functions against the emulator with a stand-in for Razorpay; it refuses to run without the emulator,
so it cannot touch the live project).

**Privacy / Play Console.** From `1.0.0+6` the app sends diagnostic information (user id, app version, device platform and
the error text) to Firebase. Update the Play Console *Data safety* form (crash logs / diagnostics, linked to the user's id,
not shared) and the privacy policy accordingly.

**Admin panel.** A separate Flutter-web project (`admin_panel/`, not part of this zip) gives the owner: revenue (ChalBro's own
earnings = what posters paid minus what helpers earned), errors and data checks, users, tasks, transactions, withdrawals, ID
verification, reports, broadcast notifications, payment/discount and app settings, admin team and an audit log. It uses the
rules in this package; see its own `README.md` for pages and hosting (hosting target `admin`).

## Known limitations of the web build

- No push notifications on web (in-app notifications list still works).
- Real Razorpay payments: mobile only (see above).
- Photo upload works from the gallery/file picker; there is no live camera capture in browsers.
- Sign-in and photo upload could not be fully tested in the packaging environment: Google sign-in needs a real account and
  phone sign-in makes Google show a human-check image challenge ("select all squares with ...") that automated tools cannot
  pass. The screens after sign-in (home, find helpers, profiles, task lists and details, accepting an offer, payment with
  discount, the profile form) were exercised against local Firebase emulators. **Please test both sign-in methods on your
  real domain, including iPhone Safari, before launch.**
- Phone sign-in on web prints "Failed to initialize reCAPTCHA Enterprise config. Triggering the reCAPTCHA v2 verification." in the
  browser console every time an OTP is sent. That is Firebase's normal fallback when reCAPTCHA Enterprise is not enabled for the
  project, not an error. Google may still show its image challenge ("select all squares ...") for some browsers.
- The "Uncaught Error ... ClientID not set" that older builds printed at start-up is fixed (the Google sign-in plugin is now only
  created on Android/iOS; web sign-in uses the Firebase popup).
- Privacy is enforced in the app and for task visibility by the rules, but **user profile documents are still readable by any
  signed-in user** (phone, email, ID-photo link). Truly hiding them until hire needs a data migration (moving private fields
  into a separate document); not done yet.
- The reviews list on a helper's profile only contains payments made from build 5 onwards (older tasks have no review record).
- The owner's error reports only exist from build `1.0.0+6` onwards, and only for signed-in users.
- Package pins to keep (Flutter 3.22.3): `package_info_plus 8.0.2` (9.x needs a newer Android Gradle plugin) and, in the
  admin panel, `fl_chart ^0.69.2` (0.70+ needs a newer Flutter).
