# Repository Guidelines

## Project Structure & Module Organization
The SwiftUI app lives in `houseWork/`, with `houseWorkApp.swift` bootstrapping the scene and `ContentView.swift` defining the primary UI. Shared assets (colors, icons, app icon variants) reside under `houseWork/Assets.xcassets/`. Unit tests are grouped in `houseWorkTests/` and exercise view logic with XCTest, while UI automation goes in `houseWorkUITests/` using launch tests and scenario coverage. Keep any new supporting files (helpers, modifiers, models) close to the feature folder they serve to limit cross-target dependency churn.

### Architecture layering
- Cross-feature stores, models, and platform services must live under `houseWork/Core` (e.g., `Core/Services/Auth/AuthStore.swift`, `Core/Models/HouseholdMember.swift`). Feature folders under `houseWork/Features` should only contain scene-specific Views/ViewModels and localized helpers.
- Shared UI utilities, modifiers, and styling live in `houseWork/Shared`, and should never import feature-specific code. This ensures files can be promoted to standalone SPM targets later.
- All SwiftUI Views participating in MVVM must delegate state/side-effects to a sibling `ViewModel` type (e.g., `TaskBoardView` ↔ `TaskBoardViewModel`, `LoginView` ↔ `LoginViewModel`). Views render, ViewModels own `@Published` UI state, inject stores/services via initializers, and expose async intents.
- Root composition happens in `ContentView`/`ContentViewModel`: create shared stores once, inject them into feature ViewModels, and pass those ViewModels down. Avoid direct `@EnvironmentObject` references inside leaf views when the dependency is better owned by a ViewModel.
- Stores that interact with Firebase must depend on protocol-based services (`AuthenticationService`, `HouseholdService`, `TagService`, `TaskBoardService`) instead of calling `Auth.auth()` or `Firestore.firestore()` directly. Provide in-memory service implementations so unit tests can run without the backend, and inject the service via initializers.
- When adding new ViewModels or reducers, add at least one unit test under `houseWorkTests/` showing how to replace the injected services/stores with in-memory fakes. Tests should exercise derived state (filters, validation, etc.) rather than just instantiation.

### Localization
- All user-facing strings must go through `Localizable.strings` files (`Base.lproj`, `en.lproj`, `zh-Hans.lproj`). Never hard-code English text inside Swift code; instead, define a key and reference it via `LocalizedStringKey` or `String(localized:)`.
- Prefer passing `LocalizedStringKey` down to reusable components (`Label`, `RangeChip`, `TaskCardButton`, etc.) so they can render localized text automatically.
- When interpolating values, add format strings to `Localizable.strings` (e.g., `"catalog.success.assigned" = "\"%@\" assigned to %@";`) and build the final string via `String(format:template, value1, value2)`.
- Example:
  ```swift
  // Localizable.strings
  "taskBoard.button.start" = "Start";

  // SwiftUI view
  TaskCardButton(
      title: LocalizedStringKey("taskBoard.button.start"),
      systemImage: "play.circle.fill",
      style: .borderedProminent
  ) { await viewModel.startTask(task) }
  ```
- Whenever you add a new screen, update all three localization files (Base, zh-Hans, en) in the same PR so forcing the language toggle never exposes raw keys or fallback text.

## Build, Test, and Development Commands
Use Xcode for day-to-day iteration: `xed houseWork.xcodeproj`. Continuous builds should rely on `xcodebuild -scheme houseWork -destination 'platform=iOS Simulator,name=iPhone 15' build` to surface compiler warnings reproducibly. Run the whole test suite with `xcodebuild -scheme houseWork -destination 'platform=iOS Simulator,name=iPhone 15' test`. When you need a clean slate before debugging provisioning or asset issues, run `xcodebuild clean -scheme houseWork`.
The app must stay compatible with iOS 15, so avoid APIs or deployment-target changes that drop support for that OS unless explicitly approved.

## Must-Follow Interaction Rules
- Every tappable control must call the shared `Haptics.impact()` helper (light style) before executing its action so button taps always produce a subtle vibration.
- All user-facing strings must be sourced from `Localizable.strings` and rendered via `LocalizedStringKey` (or `String(localized:)` when formatting is unavoidable). Reusable components should receive `LocalizedStringKey` inputs so localization never regresses.

## Coding Style & Naming Conventions
Follow standard Swift style: 4-space indentation, braces on the same line, and 120-character line guidance. Types, views, and protocols use UpperCamelCase (e.g., `TasksDashboardView`); functions, properties, and local variables use lowerCamelCase. Derive view file names from the main type (`TaskRow.swift` defines `TaskRow`). Prefer `struct` + `View` for SwiftUI components, keep modifiers readable by grouping related ones, and extract reusable styling into extensions under an adjacent `Modifiers` or `Components` subfolder when it improves clarity.

## Testing Guidelines
Place unit specs beside mirrored production files in `houseWorkTests/` and suffix classes with `Tests` (`ContentViewModelTests`). UI tests belong in `houseWorkUITests/` and should reset app state in `setUpWithError`. Aim to cover new view models and state reducers with XCT assertions plus snapshot or UI validation when rendering changes. Always run `xcodebuild test …` before pushing, and include focused test-only fixtures instead of reusing production models.

## Commit & Pull Request Guidelines
Write concise, imperative commit subjects (e.g., `Add task list filter state`). Squash noisy WIP commits locally before opening a PR. Each PR must describe the change, list verification steps (command, simulator, iOS version), and attach screenshots or screen recordings for UI-affecting updates. Reference issue IDs when available and call out any follow-up work so reviewers can plan next iterations.
