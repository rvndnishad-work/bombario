# Accounts: Google and Facebook sign-in

Sign-in is optional. Everyone starts as a guest with progress saved on the
phone. Signing in (Settings → Account) copies that progress to the player's
account, and signing in on another phone brings it back: achievements add
up, counters keep the higher value, Daily Dungeon times keep the faster one,
and name and hat come along.

| Piece | Where |
| --- | --- |
| Sign-in and sync logic | `apps/mobile/lib/account/` |
| Settings rows | `apps/mobile/lib/ui/account_section.dart` |
| Firebase config (placeholder until set up) | `apps/mobile/lib/firebase_options.dart` |
| Facebook ids, Android | `apps/mobile/android/app/src/main/res/values/facebook.xml` |
| Facebook ids, iOS | `apps/mobile/ios/Runner/Info.plist` |
| Facebook switch | `apps/mobile/lib/account/account_config.dart` |
| Database rules | `firebase/firestore.rules` |

Until the Firebase project exists the app runs guest-only and Settings says
sign-in isn't set up. Nothing crashes without it.

Profiles live in Firestore at `users/{uid}`: `name`, `skin`, `unlocked`,
`stats`, `updatedAt`. Players can only read and write their own document.

## 1. Firebase project

1. Open <https://console.firebase.google.com>, choose **Create a project**,
   name it `bombario`. Google Analytics is not needed.
2. **Build → Authentication → Get started → Sign-in method**: enable
   **Google** and pick your support email.
3. **Build → Firestore Database → Create database**: production mode, a
   region near your players. Then open the **Rules** tab, replace everything
   with the contents of `firebase/firestore.rules`, and **Publish**.

## 2. Register the apps

In **Project settings → General → Your apps**:

1. **Android**: package name `dev.bombario.bombario`, nickname Bombario,
   and the **SHA-1** fingerprint of the signing key (release builds are
   signed with the debug key for now, so one fingerprint covers both). On
   Windows:

   ```
   keytool -list -v -alias androiddebugkey -storepass android -keystore %USERPROFILE%\.android\debug.keystore
   ```

   Download `google-services.json`.
2. **iOS**: bundle id `dev.bombario.bombario`. Download
   `GoogleService-Info.plist`.

Send both files to the project thread. Claude turns them into
`lib/firebase_options.dart` (the same file `flutterfire configure` would
write) and adds the iOS URL scheme for Google sign-in.

If you add a real release key later, add its SHA-1 to the Android app too.

## 3. Facebook

1. Open <https://developers.facebook.com/apps>, **Create app**, use case
   **Authenticate and request data from users with Facebook Login**, name it
   Bombario.
2. **App settings → Basic**: note the **App ID** and **App secret**. Fill in a
   privacy policy URL and category (needed to go live).
3. **App settings → Advanced → Security**: note the **Client token**.
4. Firebase console, **Authentication → Sign-in method → Add provider →
   Facebook**: enable it, paste the App ID and App secret, and copy the
   **OAuth redirect URI** it shows.
5. Back in Facebook, **Facebook Login → Settings → Valid OAuth Redirect
   URIs**: paste that URI and save.
6. **App settings → Basic → Add platform**:
   - Android: package `dev.bombario.bombario`, class
     `dev.bombario.bombario.MainActivity`, and the **key hash** (the SHA-1
     from step 2 in base64; Claude can work it out from the SHA-1).
   - iOS: bundle id `dev.bombario.bombario`.
7. Send the **App ID** and **Client token** to the project thread. Both ship
   inside the app anyway. Keep the App secret in Firebase only.

Claude then fills the ids into `facebook.xml` and `Info.plist` and sets
`facebookLoginEnabled = true`.

While the Facebook app is in development mode only you and the testers
listed under **App roles** can sign in. Switch it to **Live** before release.

## Doing it yourself instead

`flutterfire configure --project=<project-id> --platforms=android,ios` in
`apps/mobile` writes `lib/firebase_options.dart` over the placeholder. It
needs the Firebase CLI (`npm install -g firebase-tools`, `firebase login`)
and `dart pub global activate flutterfire_cli`.

## Before publishing

- Google Play and the App Store require an in-app way to delete an account:
  Settings → Account → Delete account removes the account and its cloud
  profile (progress on the phone stays).
- The Daily Dungeon leaderboard still trusts times the phone reports. The
  next step is for the room server to check a Firebase ID token with each
  submission.
