# ChalBro web hand-off

ChalBro is a Flutter app (Android app already live on Google Play). This package is the **web version**
for iOS and desktop users, plus the Firebase backend it shares with the Android app.

```
chalbro_web_handoff/
  frontend/          Built, deploy-ready website (upload this to the domain)
  frontend_source/   Flutter source, only needed if you want to change/rebuild the site
  backend/           Cloud Functions + Firestore/Storage rules + indexes
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

> **Before deploying `firestore.rules`**: they were tightened (task updates are now role-checked, wallet writes restricted,
> notification `fromUid` enforced) but have **not yet been tested against every app flow** and are **not deployed** to
> production. Test on a copy or with the emulator first: post -> apply -> propose -> accept -> mark done -> pay.

### Payments switch
Payments are controlled live from Firestore, no app update needed. Create the document `metadata/paymentConfig`:

| field             | value | meaning |
|-------------------|-------|---------|
| `paymentsEnabled` | true  | master on/off for the Pay button |
| `useRazorpay`     | false | false = built-in dummy wallet, true = real Razorpay |

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

## Known limitations of the web build

- No push notifications on web (in-app notifications list still works).
- Real Razorpay payments: mobile only (see above).
- Photo upload works from the gallery/file picker; there is no live camera capture in browsers.
- Sign-in and photo upload could not be fully end-to-end tested in the packaging environment (Google sign-in needs a real
  account; phone sign-in reached Firebase's reCAPTCHA step). **Please test both on your real domain, including iPhone Safari,
  before launch.**
