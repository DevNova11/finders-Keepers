# Finders Keepers? — VIT Vellore Lost & Found

A Flutter app that connects people who lost items on campus with people who
found them. It uses a **verified ownership-claim + handover-code** process to
stop fraudulent claims, and keeps personal data private throughout.

| Requirement | Where |
|---|---|
| 01 Report lost/found items with descriptions, images, locations | `lib/screens/report_screen.dart` |
| 02 Searchable listing | `lib/screens/browse_screen.dart` (text search, lost/found, category, resolved filters) |
| 03 Approximate locations on a map | `lib/screens/map_screen.dart` (OpenStreetMap, ~100 m areas) |
| 04 Ownership claims | `lib/screens/claim_screen.dart` |
| 05 Ownership verification before handover | `lib/services/verification.dart`, `claim_review_screen.dart`, `my_claim_screen.dart`, `firestore.rules` |
| 06 Lost → found → claimed → returned tracking | `Item.status` + `history[]`, timeline on item page, rules-enforced state machine |
| 07 Interrupted submissions / bad network | `lib/services/outbox.dart`, draft autosave, Firestore offline cache |
| 08 Protect sensitive information | aliases, private subcollections, EXIF stripping, blur, approximate location, in-app chat |
| Bonus: offline-first | Firestore persistent cache + resumable outbox + drafts |
| Bonus: push notifications on matches | `functions/index.js` (FCM) + in-app watcher `lib/services/notifications.dart` |
| Bonus: image similarity | 64-bit dHash per photo (`lib/services/image_processing.dart`), used in match score |

Tech: **Flutter 3.47 · Riverpod 3 · Firebase Auth · Cloud Firestore ·
Firebase Storage · FCM · Cloud Functions · flutter_map (OpenStreetMap)**.

Database layout and workflow diagrams: [docs/DATABASE_AND_WORKFLOW.md](docs/DATABASE_AND_WORKFLOW.md).

---

## Quick start (demo mode — no setup)

The app ships with a placeholder `lib/firebase_options.dart`. While it is a
placeholder the app runs in **demo mode**: everything is stored on the device,
and three seeded demo students (Asha, Ben, Chen) let you play out the whole
flow on one phone by switching accounts from the Profile tab.

```bash
flutter pub get
flutter run                 # or: flutter build apk --release
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`.

### Suggested demo script (for the video)

1. Sign in as **Chen**. You see Chen's found *Student ID card* with the secret
   questions "What name is printed on the card?" / "What is your school / department?".
2. Switch account → **Asha**. Browse → open *Student ID card* → **This is mine — claim it**.
   Answer `Asha Raman` and `SENSE`, describe it, submit.
3. Switch to **Chen** → Activity → *To review*. The claim shows a **100 % match**
   (each answer ✓). Claim as **Ben** with wrong answers to see a weak score.
   Message the claimant in chat, then **Approve** Asha's claim (Ben's is auto-rejected).
4. Switch to **Asha** → Activity → My claims → the claim shows a **6-digit handover code**.
5. Switch to **Chen** → open the claim → enter the code → item becomes **Returned**
   (a wrong code is refused). The item timeline shows Found → Claimed → Returned.
6. Offline: Profile → **Simulate offline** → report an item → it waits under
   *Activity → Waiting to upload*; switch back online → it uploads by itself.
   Leave a report form half-filled and close the app → reopen the form → the draft is restored.
7. Matching: as **Ben**, report a *found* white earbuds case at the Food Court
   (near TT). Switch to **Asha** → her *White wireless earbuds* lost post lists it
   under **Possible matches** with a % score. (Live match notifications fire
   when a matching item arrives while you are signed in; with Firebase the
   Cloud Function pushes them even when the app is closed. Profile → *Test
   notification* shows what one looks like.)

---

## Firebase setup (production mode)

1. Create a Firebase project (console.firebase.google.com) and enable
   **Authentication → Email/Password**, **Cloud Firestore**, **Storage**.
2. Connect the app. This replaces the placeholder options, and the app switches to Firebase automatically:
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```
3. Deploy security rules and indexes:
   ```bash
   firebase deploy --only firestore,storage
   ```
4. (Optional, Blaze plan) deploy Cloud Functions for push notifications,
   server-side match alerts and claim rate-limiting:
   ```bash
   cd functions
   npm install
   firebase deploy --only functions
   ```
5. Campus settings live in `lib/config/app_config.dart`. It is set up for
   **VIT Vellore**: map centre, 17 campus landmarks (Main Gate, TT, SJT, SMV,
   GDN, PRP, library, Food Court, MH/LH, grounds…, coordinates from
   OpenStreetMap), sign-up restricted to `@vitstudent.ac.in` / `@vit.ac.in`,
   and the Main Gate security desk as the recommended handover point.

You can also test everything against the Firebase Emulator Suite
(`firebase emulators:start`, configured in `firebase.json`).

---

## Ownership verification mechanism

The goal: the person who walks away with the item must be the person who can
prove they own it, and the finder never has to trust a stranger's word or
exchange phone numbers.

### Layer 1 — accountable identities
* Sign-up with campus e-mail only (`allowedEmailDomains`), and **e-mail
  verification is required** before posting, claiming or chatting
  (checked in the UI *and* via `request.auth.token.email_verified` in the rules).
* A **declaration** checkbox on each claim; suspicious posts can be reported.

### Layer 2 — secret knowledge (challenge questions)
* When reporting a found item, the finder writes 1–3 **private questions**
  about details not visible in the public post or photos (suggested per
  category: lock-screen wallpaper, contents, stickers, last 4 digits…), plus the answers.
* Answers are **normalised** (case, punctuation, articles) and stored only as
  **salted SHA-256 hashes** in `items/{id}/private/secret`, readable only by
  the finder. Alternatives are allowed (`3|three`). Claimants only ever see the questions.
* The public description is kept deliberately vague; the form reminds the finder.

### Layer 3 — the claim
* The claimant answers the questions, describes unique details, and may
  attach a proof photo (receipt, older photo with the item). A claim is
  visible only to the claimant and the finder.
* **One attempt per user per item**: claim ids are `{itemId}_{uid}` and the
  rules forbid recreating them, so answers cannot be brute-forced.
* A Cloud Function flags users who submit more than 5 claims in 24 h; the
  finder sees a red warning on flagged claims.

### Layer 4 — finder review
* The finder's app hashes each submitted answer with the item's salt and
  compares it with the stored hashes → per-question ✓/✗ and an overall score
  (strong / partial / weak).
* The finder can ask follow-up questions in the private claim chat, then
  approves or rejects. Approving atomically moves the item to **claimed** and
  rejects all other pending claims.

### Layer 5 — handover code (proof at the moment of exchange)
* On approval, the **claimant's** device generates a random 6-digit code;
  only its salted hash is written to the claim (the plain code is kept in a
  claimant-only document).
* At the meet-up (recommended: campus security desk) the claimant reads the
  code aloud and the finder types it in. Firestore rules recompute
  `sha256(code + salt)` and only then allow claim → **completed** and
  item → **returned**. The item therefore goes to the *approved* claimant,
  not to someone who merely saw the chat.

---

## Privacy protections
* Others see only an alias ("Asha R."); e-mail, full name and phone number are never displayed.
* Public map pins are snapped to a ~110 m grid and drawn as an area; the exact
  spot is stored in the reporter-only private document.
* Photos are re-encoded on the device before upload → **EXIF/GPS metadata removed**,
  resized to ≤1280 px; sensitive categories (ID cards, wallets, phones, laptops)
  are **blurred by default**.
* Claim answers, proof photos and chats are readable only by the two parties
  (Firestore + Storage rules).
* Chat warns before sending something that looks like a phone number or e-mail.
* Clients cannot delete anything; abuse reports are write-only.

## Offline & interrupted submissions
* **Drafts**: the report and claim forms autosave (including copied photos) and restore on reopen.
* **Outbox**: on submit, photos are processed locally and the submission is persisted
  to disk, then uploaded in the background. Uploads resume from the last
  successful photo and retry with exponential backoff and on reconnect.
  Client-generated ids make retries idempotent (no duplicates).
* **Firestore offline cache**: browsing, the map and your items work offline;
  writes are queued and synced automatically. An offline banner shows the state.

## Project structure
```
lib/
  config/app_config.dart        campus settings
  models/models.dart            Item, ItemSecret, Claim, ChatMessage, enums
  services/
    backend.dart                backend interface
    firebase_backend.dart       Firestore / Auth / Storage implementation
    local_backend.dart          on-device demo implementation
    outbox.dart                 resumable offline submission queue
    verification.dart           answer hashing, scoring, handover codes
    image_processing.dart       EXIF strip, blur, resize, dHash
    matching.dart               lost↔found match scoring, keywords, location snapping
    notifications.dart          local + FCM notifications, match watcher
  screens/                      UI
firestore.rules, storage.rules  server-side enforcement
functions/index.js              push notifications, match alerts, rate limiting
test/logic_test.dart            unit tests for verification, matching, privacy, search
```

## Tests
```bash
flutter test
```
