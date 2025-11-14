# Development Guide

## Architecture Overview
The app uses SwiftUI for UI + navigation, Combine for in-memory state, and Firebase (Auth, Firestore, Storage) for backend services. Each screen binds to a small view model responsible for fetching documents, mutating state, and emitting events to SwiftUI via `@StateObject`. Firestore acts as the single source of truth: `/households` store membership + settings, `/chores` hold the live task board, and `/completions` form the immutable audit log used for stats.

## Module & Project Structure
```
houseWork/
 ├─ App/houseWorkApp.swift        // Entry point, environment injection
 ├─ Features/
 │   ├─ ChoreCatalog              // Create/select chore templates
 │   ├─ TaskBoard                 // Assignment + completion UI
 │   └─ Analytics                 // Scorecards, leaderboards
 ├─ Shared/
 │   ├─ Models (Household, Chore, Completion, MemberStats)
 │   ├─ Services (FirestoreService, AuthService, StorageService)
 │   ├─ ViewModifiers & Components (ScoreBadge, MemberAvatar)
 │   └─ Utils (DateFormatting, ErrorHandling)
 ├─ Resources/Assets.xcassets
 └─ Tests/
     ├─ Unit (ViewModel, Services)
     └─ UI (Scenario-driven flows)
```
Create folders as needed; keep feature-specific models + services inside the feature to limit coupling.

## Environment & Tooling
1. Install Xcode 15+, CocoaPods (if Firebase via pods) or Swift Package Manager.
2. Add Firebase config (`GoogleService-Info.plist`) to `houseWork/Resources`.
3. Configure Firebase project with Authentication (Email/Password + optionally Apple), Firestore (native mode), and Storage buckets.
4. Copy `.env.sample` to `.env` (contains Firebase keys, default household id) and load via build settings.

## Firestore Data Contracts
- `/users/{userId}` → `displayName`, `avatarURL`, `role`.
- `/households/{householdId}` → `name`, `inviteCode`, `members[]`.
- `/households/{householdId}/chores/{choreId}` → `title`, `description`, `tags[]`, `baseScore`, `dueDate`, `assignedTo[]`, `status`.
- `/households/{householdId}/completions/{completionId}` → `choreId`, `completedBy`, `completedAt`, `awardedScore`, `proofURL`.
- `/households/{householdId}/stats/{userId}` → cached aggregates (`totalScore`, `weeklyCount`, `streakDays`).

Enforce Firestore rules so only household members can read/write their documents; require admin role for template edits.

## Data Flow & State Management
1. `AuthService` ensures an authenticated Firebase user and loads household context.
2. `FirestoreService` exposes async sequences (or Combine publishers) for chore lists and completions, mapped into domain models.
3. View models (e.g., `TaskBoardViewModel`) subscribe to those publishers, derive UI state, and expose intent methods (`markComplete`, `assignMember`).
4. Mutations write through to Firestore; optimistic updates keep UI responsive. Failures surface via a shared `AlertState`.
5. Analytics view model aggregates `/completions` and `/stats` to build per-user leaderboards.

## Build, Run, & Testing
- Local run: `xed houseWork.xcodeproj` then select `houseWork` scheme, iPhone 15 simulator.
- CLI build: `xcodebuild -scheme houseWork -destination 'platform=iOS Simulator,name=iPhone 15' build`.
- Tests: `xcodebuild -scheme houseWork -destination 'platform=iOS Simulator,name=iPhone 15' test`.
- Unit tests mock Firestore via in-memory adapters; UI tests seed fake data through a `MockFirebaseService`.

## Deployment & Release
1. Configure Firebase environments (dev/staging/prod) with separate project IDs.
2. Use Xcode Cloud or Fastlane for CI to run lint + tests on every PR.
3. Archive via Xcode, upload with Transporter/TestFlight, and distribute builds to household testers.
4. Maintain release notes focusing on new chores features, analytics enhancements, and database migrations.
