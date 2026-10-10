# Firestore rules tests

Run from this folder after `npm install`:

    npm test

It starts the Firestore emulator (needs Java) and replays the app's real queries and
writes against `../firestore.rules`. Run it after ANY change to the rules, before deploying.
