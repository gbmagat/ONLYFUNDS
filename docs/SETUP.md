# Setup and troubleshooting

## Dependencies

Install Flutter with a Dart SDK compatible with `^3.9.0`, then run `flutter doctor` and `flutter pub get` from the repository root. Keep `pubspec.lock` when reproducing the project; upgrading dependencies is a separate change.

## Firebase configuration

The checked-in client configuration identifies the original Firebase project. Use a separate project for local demos rather than assuming access to that backend.

1. Create a project in the [Firebase console](https://console.firebase.google.com/).
2. Enable **Authentication → Sign-in method → Email/Password**.
3. Create a **Cloud Firestore** database and choose its location.
4. Install the [Firebase CLI](https://firebase.google.com/docs/cli) and follow the [FlutterFire setup instructions](https://firebase.google.com/docs/flutter/setup). From the repository root, run:

   ```sh
   firebase login
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```

5. Select your own project and mobile platforms. Verify that `lib/firebase_options.dart` and platform configuration files refer to your project. The Android application ID is currently `com.example.onlyfunds_v1`; the iOS bundle ID in the committed Firebase options is `com.example.onlyfundsV1`.
6. Deploy the Firestore rules before using the app. All application records live under `users/{uid}`, and `firestore.rules` lets each signed-in user read and write only their own records, including nested monthly records. The [rules tests](../CONTRIBUTING.md#firestore-rules-tests) check this on the local emulator. From the repository root, run `firebase deploy --only firestore:rules`. The file does not show which rules are currently deployed; check the Firebase console.

Do not leave a database open in test mode for a shared demo. Use disposable data. Never commit service-account credentials, private keys, or Firebase CLI tokens.

The app creates documents during registration and record entry; there is no migration or seed command. Monthly parent documents may have no fields or may not exist even when their subcollections contain data.

## Launch

```sh
flutter devices
flutter run -d <device-id>
```

Android is the simplest starting point on Windows. iOS requires macOS, Xcode, and Flutter/Firebase platform setup. Configuration in source does not mean either platform has been verified on your machine.

## Android release builds

Release builds are signed with your own upload key when `android/key.properties` exists. Without that file they fall back to the debug key: `flutter run --release` works, but the build cannot be published to Google Play.

1. Create an upload keystore. In PowerShell:

   ```powershell
   keytool -genkey -v -keystore $env:USERPROFILE\upload-keystore.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

2. Create `android/key.properties` with the passwords you chose and the keystore's location. Replace the capitalised values, and use double backslashes in Windows paths:

   ```properties
   storePassword=YOUR_STORE_PASSWORD
   keyPassword=YOUR_KEY_PASSWORD
   keyAlias=upload
   storeFile=C:\\Users\\YOUR_USER_NAME\\upload-keystore.jks
   ```

3. Build with `flutter build appbundle`.

`key.properties` and keystore files are git-ignored. Never commit them, and keep a backup of the keystore and its passwords. Before publishing, also replace the placeholder application ID `com.example.onlyfunds_v1`. That requires registering the new ID as an Android app in Firebase and replacing `android/app/google-services.json`.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Dependency resolution fails | Confirm Dart satisfies `^3.9.0`. Investigate package constraints before upgrading the lockfile. |
| Email/password registration fails | Enable the Email/Password provider in the selected Firebase project. |
| Firestore returns `permission-denied` | Confirm you are signed in and that `firestore.rules` is deployed to the selected project. |
| `npm ci` fails in `firestore-tests` | Use Node.js 24.12 or later, which `@firebase/rules-unit-testing` 6 requires. |
| Rules tests cannot start the emulator | Install Java 21 or later and make sure `java` is on your `PATH`. Port 8080 must be free, so stop any other Firestore emulator first. |
| Unsupported Firebase platform | Committed options support Android/iOS only. Configure other platforms and verify plugin compatibility first. |
| Empty dashboard/history | Add income first. These views read the current calendar month. |
| Expense rejected | The expense exceeds the recorded monthly balance. Savings deposits also consume that balance. |
| Prediction unavailable | Expenses in at least three completed calendar months are required; the current month does not count. Fitting errors or non-positive results can also prevent a prediction. |
| Notification settings reset | Preferences/history are held in memory; persistent storage is not implemented. |

See [development and validation](../CONTRIBUTING.md) for checks. The unit and widget tests run without Firebase and do not cover the Firebase-backed pages. The rules tests check `firestore.rules` on the local emulator, not the rules deployed to your project.
