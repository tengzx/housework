# Firestore Tags Data Model

Use the following structure to store household-specific tags:

```
/households/{householdId}/tags/{tagId}
```

## Document Fields

| Field      | Type      | Description                                   |
|------------|-----------|-----------------------------------------------|
| `name`     | string    | Tag label (unique within the household)       |
| `createdAt`| timestamp | Server timestamp when the tag was created     |
| `updatedAt`| timestamp | Last update timestamp                         |
| `color`    | string    | Optional hex color code (e.g., `#FF9500`)     |

## Security Rules

Ensure that only members of the household can read/write:

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

## Client Recommendations

1. **Listen for Changes** – Add a snapshot listener on `/households/{householdId}/tags` and map documents to `TagItem`.
2. **Create Tags** – Write `{ name, createdAt, updatedAt }`, enforcing uniqueness via Firestore indexes or Cloud Functions.
3. **Rename/Delete** – Use document IDs to update or delete; update `updatedAt` on rename.
4. **Offline Cache** – Firestore SDK caches tags automatically; refresh or reattach listeners when switching households.

With this schema the iOS `TagStore` can listen to Firestore and sync tags across all devices.
