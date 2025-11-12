# Firebase Auth Integration Guide

This guide explains the steps required to configure Firebase Authentication and Firestore for the houseWork app.

## 1. Create a Firebase Project
1. Visit [https://console.firebase.google.com](https://console.firebase.google.com) and sign in with the team Google account.
2. Click `Add project`, choose a project name, and pick the region closest to your primary users.
3. Enable or disable Google Analytics according to team policy, then create the project.

## 2. Register the iOS App
1. In the Firebase console click `Add app -> iOS`.
2. Use the Xcode bundle identifier (e.g., `com.company.houseWork`).
3. Download the generated `GoogleService-Info.plist` and place it under `houseWork/`, ensuring it is included in the target's Copy Bundle Resources phase.

## 3. Enable Firebase Authentication
1. Navigate to `Build -> Authentication` and click `Get started`.
2. Under `Sign-in method`, enable the required providers:
   - Email/Password (mandatory)
   - Optional providers such as Apple/Google if needed
3. Use the `Users` tab or CLI scripts to create test accounts.

## 4. Initialize Firestore
1. Go to `Build -> Firestore Database`, choose `Create database`.
2. Select `Production mode`, reusing the same region as Auth.
3. Create the following collection paths (via console or script):
   - `/households/{householdId}/tags/{tagId}`
   - `/households/{householdId}/chores/{choreId}`
   - `/households/{householdId}/tasks/{taskId}`
4. Note the Firebase project ID and Web API Key for Xcode configuration.

## 5. Security Rules
Example rule that restricts access to members of the household:

```rules
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /households/{householdId}/{document=**} {
      allow read, write: if request.auth != null &&
        request.auth.token.householdId == householdId;
    }
  }
}
```

Adjust the rule to match your membership model (custom claims or membership documents).

## 6. Install Firebase SDKs via SPM
1. `File -> Add Packages -> https://github.com/firebase/firebase-ios-sdk`
2. Add `FirebaseAuth`, `FirebaseFirestore`, and any other necessary modules.
3. In `houseWorkApp.swift` import `FirebaseCore` and call `FirebaseApp.configure()`.

## 7. Handle Sensitive Files
1. Add `GoogleService-Info.plist` to `.gitignore` or manage it securely in CI.
2. Document Firebase project ID/API key handling (e.g., xcconfig or environment variables).

## 8. Test the Integration
1. Run on simulator/device and log in with the test account.
2. Create/complete tasks and verify Firestore writes.
3. Watch Xcode logs for Auth/Firestore errors and adjust configuration or rules as needed.

After completing these steps, the app is ready to use Firebase Auth and Firestore in production.
