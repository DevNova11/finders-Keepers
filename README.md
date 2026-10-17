# Finders Keepers? — VIT Vellore Lost & Found

**▶ [Demo video](https://drive.google.com/file/d/1y1VixuSLc7D6gzmhPM_YbD6Z9WR3pedv/view?usp=drive_link)** ·
**⬇ [Download APK](https://github.com/DevNova11/finders-Keepers/releases/tag/v1.1.0)** ·
**🗂 [Database & workflow](docs/DATABASE_AND_WORKFLOW.md)**

A Flutter app that connects people who lost items on campus with people who
found them. It uses a **verified ownership-claim + handover-code** process to
stop fraudulent claims, and keeps personal data private throughout.

| Requirement | Where |
|---|---|
| 01 Report lost/found items with descriptions, images, locations | `lib/screens/report_screen.dart` |
| 02 Searchable listing | `lib/screens/browse_screen.dart` (text search, lost/found, category, resolved, nearest-first) |
| 03 Approximate locations on a map | `lib/screens/map_screen.dart` (OpenStreetMap, ~100 m areas) |
| 04 Ownership claims | `lib/screens/claim_screen.dart` |
| 05 Ownership verification before handover | `lib/services/verification.dart`, `claim_review_screen.dart`, `my_claim_screen.dart`, `firestore.rules` |
| 06 Lost → found → claimed → returned tracking | `Item.status` + `history[]`, timeline on item page, rules-enforced state machine |
| 07 Interrupted submissions / bad network | `lib/services/outbox.dart`, draft autosave, Firestore offline cache |
| 08 Protect sensitive information | aliases, private subcollections, EXIF stripping, blur, approximate location, in-app chat |
| Bonus: offline-first | Firestore persistent cache + resumable outbox + drafts |
| Bonus: notifications on matches | in-app match/claim alerts (`lib/services/notifications.dart`); FCM push via `functions/index.js` on the Blaze plan |
| Bonus: image similarity | 64-bit dHash fingerprint per photo (`lib/services/image_processing.dart`), used in match score |
| Bonus: location-based recommendations | "Near you" on Browse, nearest-first sort, your position on the map (`lib/services/location.dart`, `recommendNearby` in `matching.dart`) |
| Bonus: admin moderation interface | `lib/screens/admin_screen.dart`: reports queue, hide/restore posts, suspend accounts, campus stats |
| Bonus: secure in-app messaging | claim-scoped chat readable only by the two parties (`chat_screen.dart` + rules) |

Tech: **Flutter 3.47 · Riverpod 3 · Firebase Auth · Cloud Firestore ·
flutter_map (OpenStreetMap) · geolocator · FCM / Cloud Functions (optional)**.

Database layout and workflow diagrams: [docs/DATABASE_AND_WORKFLOW.md](docs/DATABASE_AND_WORKFLOW.md).

---

## Try it

The [GitHub release](https://github.com/DevNova11/finders-Keepers/releases) has two APKs:

| APK | What it is |
|---|---|
| `FindersKeepers-firebase.apk` | The real app, connected to Firebase project `finders-keepers-9b78c`. Sign up with your VIT e-mail and start using it straight away; data is shared between everyone using the app. |
| `FindersKeepers-demo.apk` | Self-contained demo: no sign-up, data stays on the phone, five sample accounts (3 students, a moderator and a spammer) so one person can play every role. |

Build them yourself:
```bash
flutter pub get
flutter build apk --release                      # Firebase app
flutter build apk --release --dart-define=DEMO=true   # demo build
```

### Demo script (demo APK, also used for the video)

1. Sign in as **Chen**. Chen's found *Student ID card* has the secret
   questions "What name is printed on the card?" / "What is your school / department?".
2. Switch account → **Asha**. Browse → open *Student ID card* → **This is mine — claim it**.
   Answer `Asha Raman` and `SENSE`, describe it, submit.
3. Switch to **Chen** → Activity → *To review*. The claim shows a **100 % match**
   (each answer ✓). Claim as **Ben** with wrong answers to see a weak score.
   Message the claimant in chat, then **Approve** Asha's claim (Ben's is auto-rejected).
4. Switch to **Asha** → Activity → My claims → the claim shows a **6-digit handover code**.
5. Switch to **Chen** → open the claim → enter the code → item becomes **Returned**
   (a wrong code is refused). The item timeline shows Found → Claimed → Returned.
6. **Near you**: on Browse tap **Enable** in the *Near you* card. Off campus it
   falls back to the campus centre. Items related to your own reports are
   ranked first ("Could be your …"). The ➤ button sorts the list nearest-first.
7. **Moderation**: sign in as **Campus Moderator** → Profile → *Moderation
   dashboard*. The scam post "Found iPhone 16 – pay Rs 500 to collect" has an
   open report → **Suspend poster** (hides the post too). Sign in as **Sam
   Spammer** to see the suspended screen. Check *Overview* for campus stats
   and *Hidden posts* to restore a post.
8. **Offline**: Profile → **Simulate offline** → report an item → it waits under
   *Activity → Waiting to upload*; switch back online → it uploads by itself.
   Leave a report form half-filled and close the app → reopen the form → the draft is restored.
9. **Matching**: as **Ben**, report a *found* white earbuds case at the Food Court
   (near TT). Switch to **Asha** → her *White wireless earbuds* lost post lists it
   under **Possible matches** with a % score.

---

## Firebase setup

The repo is already connected to Firebase project **`finders-keepers-9b78c`**
(`lib/firebase_options.dart`). To use your own project:

1. Create a Firebase project and enable **Authentication → Email/Password**
   and **Cloud Firestore**.
2. Connect the app:
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```
3. Deploy the security rules and indexes:
   ```bash
   firebase deploy --only firestore
   ```
4. **Make yourself a moderator**: sign in once, copy *Your user ID* from the
   Profile tab, then in the Firebase console → Firestore create a document
   `admins/<your user id>` (any field, e.g. `name: "Moderator"`). The
   *Moderation dashboard* appears in your Profile tab. Admins can only be
   added from the console; the rules forbid it from the app.
5. Campus settings live in `lib/config/app_config.dart`: VIT Vellore map
   centre, 17 landmarks (coordinates from OpenStreetMap), sign-up restricted
   to `@vitstudent.ac.in` / `@vit.ac.in`, and the Main Gate security desk as
   the recommended handover point.

### Free (Spark) plan vs Blaze

The project runs on the **free Spark plan**. Firebase Storage and Cloud
Functions need the pay-as-you-go **Blaze** plan, so on Spark:

* **Photos stay on the phone.** They are still processed (EXIF removed,
  blurred, fingerprinted) and the 64-bit fingerprint is uploaded, so
  image-similarity matching keeps working, but the photo itself isn't shared.
* **Notifications** come from the in-app watcher while the app is open
  (new possible match, new claim, claim decision).

After upgrading to Blaze:
```bash
# lib/config/app_config.dart → uploadPhotosToFirebase = true
firebase deploy --only storage
cd functions && npm install && firebase deploy --only functions
```
This turns on shared photos, proof photos on claims, server-side match push
notifications to closed apps, and the claim rate-limit flag.

---

## Ownership verification mechanism

The goal: the person who walks away with the item must be the person who can
prove they own it, and the finder never has to trust a stranger's word or
exchange phone numbers.

### Layer 1 — accountable identities
* Sign-up is restricted to campus e-mail addresses (`allowedEmailDomains`).
  E-mail verification is **off** to keep onboarding instant; it can be turned
  back on with `AppConfig.requireEmailVerification` plus the
  `email_verified` check in `canWrite()` in `firestore.rules`.
* A **declaration** checkbox on each claim. Suspicious posts can be reported,
  and moderators can hide them and **suspend** the account. The rules then
  block every write from that account.

### Layer 2 — secret knowledge (challenge questions)
* When reporting a found item, the finder writes 1–3 **private questions**
  about details not visible in the public post or photos (suggested per
  category: lock-screen wallpaper, contents, stickers, last 4 digits…), plus the answers.
* Answers are **normalised** (case, punctuation, articles) and stored only as
  **salted SHA-256 hashes** in `items/{id}/private/secret`, readable only by
  the finder. Alternatives are allowed (`3|three`). Claimants only ever see the questions.
* The public description is kept deliberately vague; the form reminds the finder.

### Layer 3 — the claim
* The claimant answers the questions and describes unique details (plus a
  proof photo on Blaze). A claim is visible only to the claimant and the finder.
* **One attempt per user per item**: claim ids are `{itemId}_{uid}` and the
  rules forbid recreating them, so answers cannot be brute-forced.
* On Blaze, a Cloud Function flags users who submit more than 5 claims in
  24 h; the finder sees a red warning on flagged claims.

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
* At the meet-up (recommended: Main Gate security desk) the claimant reads the
  code aloud and the finder types it in. Firestore rules recompute
  `sha256(code + salt)` and only then allow claim → **completed** and
  item → **returned**. The item therefore goes to the *approved* claimant,
  not to someone who merely saw the chat.

---

## Moderation

* Any signed-in user can **report a suspicious post** (item page → ⋮).
* Moderators (`admins/{uid}`) get a **Moderation dashboard** in Profile:
  * **Open reports**: view the post, **hide** it with a note shown to its
    author, **dismiss** the report, or **suspend the poster** (also hides the post).
  * **Hidden posts**: restore a post.
  * **Overview**: open lost/found counts, awaiting handover, returned,
    return rate, open reports, and the top loss hotspots on campus.
* Hidden posts disappear from listings, the map, matching and recommendations
  for everyone except their author. Suspended users see a suspended screen,
  and `firestore.rules` rejects all their writes.
* Moderators can only change `hidden` / `moderationNote` on items. They
  cannot edit content, claims or chats.

## Location-based recommendations
* **Near you** (top of Browse): open items within 1.5 km of your GPS
  position. Items relevant to your own open reports come first (e.g. a
  found item in the same category as something you lost: "Could be your
  'Black wallet'"), then the rest by distance.
* **Nearest first** (➤ on Browse) sorts the whole listing by distance and
  shows how far each item is.
* Your position appears as a blue dot on the map when you're on campus. When
  you're more than 3 km away, recommendations use the campus centre instead.
* Location is read on the device only and never uploaded.

## Privacy protections
* Others see only an alias ("Asha R."); e-mail, full name and phone number are never displayed.
* Public map pins are snapped to a ~110 m grid and drawn as an area; the exact
  spot is stored in the reporter-only private document.
* Photos are re-encoded on the device → **EXIF/GPS metadata removed**,
  resized to ≤1280 px; sensitive categories (ID cards, wallets, phones, laptops)
  are **blurred by default**. On the free plan they never leave the phone.
* Claim answers and chats are readable only by the two parties (rules).
* Chat warns before sending something that looks like a phone number or e-mail.
* Clients cannot delete anything; abuse reports are readable only by moderators.

## Offline & interrupted submissions
* **Drafts**: the report and claim forms autosave (including copied photos) and restore on reopen.
* **Outbox**: on submit, the submission is processed locally and persisted to
  disk, then uploaded in the background. It retries with exponential backoff
  and on reconnect, resuming from the last successful step.
  Client-generated ids make retries idempotent (no duplicates).
* **Firestore offline cache**: browsing, the map and your items work offline;
  writes are queued and synced automatically. An offline banner shows the state.

## Project structure
```
lib/
  config/app_config.dart        campus settings
  models/models.dart            Item, ItemSecret, Claim, ChatMessage, AbuseReport
  services/
    backend.dart                backend interface
    firebase_backend.dart       Firestore / Auth / Storage implementation
    local_backend.dart          on-device demo implementation
    outbox.dart                 resumable offline submission queue
    verification.dart           answer hashing, scoring, handover codes
    image_processing.dart       EXIF strip, blur, resize, dHash
    matching.dart               match scoring, Near-you ranking, keywords
    location.dart               GPS position (on-device only)
    notifications.dart          local + FCM notifications, match watcher
  screens/                      UI (incl. admin_screen.dart)
firestore.rules, storage.rules  server-side enforcement
functions/index.js              push notifications, match alerts, rate limiting (Blaze)
test/logic_test.dart            unit tests
```

## Tests
```bash
flutter test
```
21 unit tests cover answer hashing and scoring, handover codes, location
snapping, aliases, match scoring, image fingerprints and EXIF removal,
search filters, Near-you ranking and the moderation models.
