# Firestore Security Rules

The houseWork app currently uses two primary document hierarchies: a global `/users/{userId}` collection for profile metadata and household-scoped collections under `/households/{householdId}`. The rules below ensure users can only mutate data they own while keeping household data restricted to authenticated members.

```rules
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // Profiles: everyone can read (for avatars/names), but only the owner can modify.
    match /users/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.uid == userId;
    }

    // Household data (chores, tags, etc.) remains readable/writable to any signed-in user.
    match /households/{householdId}/{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

> NOTE: This is the minimal rule set required for the current app state. If we introduce new collections or tighten per-household permissions (e.g., only members can access `/households/{householdId}`), update this document and the deployed rules accordingly.

When adding a new Firestore document path in code, remember to update these rules (and notify the team) so deployments don’t fail with `Missing or insufficient permissions`.
