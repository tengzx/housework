# Repository Guidelines

## Project Structure & Module Organization
The SwiftUI app lives in `houseWork/`, with `houseWorkApp.swift` bootstrapping the scene and `ContentView.swift` defining the primary UI. Shared assets (colors, icons, app icon variants) reside under `houseWork/Assets.xcassets/`. Unit tests are grouped in `houseWorkTests/` and exercise view logic with XCTest, while UI automation goes in `houseWorkUITests/` using launch tests and scenario coverage. Keep any new supporting files (helpers, modifiers, models) close to the feature folder they serve to limit cross-target dependency churn.

### Architecture layering
- Cross-feature stores, models, and platform services must live under `houseWork/Core` (e.g., `Core/Services/Auth/AuthStore.swift`, `Core/Models/HouseholdMember.swift`). Feature folders under `houseWork/Features` should only contain scene-specific Views/ViewModels and localized helpers.
- Shared UI utilities, modifiers, and styling live in `houseWork/Shared`, and should never import feature-specific code. This ensures files can be promoted to standalone SPM targets later.
- All SwiftUI Views participating in MVVM must delegate state/side-effects to a sibling `ViewModel` type (e.g., `TaskBoardView` ↔ `TaskBoardViewModel`, `LoginView` ↔ `LoginViewModel`). Views render, ViewModels own `@Published` UI state, inject stores/services via initializers, and expose async intents.
- Root composition happens in `ContentView`/`ContentViewModel`: create shared stores once, inject them into feature ViewModels, and pass those ViewModels down. Avoid direct `@EnvironmentObject` references inside leaf views when the dependency is better owned by a ViewModel.

## Build, Test, and Development Commands
Use Xcode for day-to-day iteration: `xed houseWork.xcodeproj`. Continuous builds should rely on `xcodebuild -scheme houseWork -destination 'platform=iOS Simulator,name=iPhone 15' build` to surface compiler warnings reproducibly. Run the whole test suite with `xcodebuild -scheme houseWork -destination 'platform=iOS Simulator,name=iPhone 15' test`. When you need a clean slate before debugging provisioning or asset issues, run `xcodebuild clean -scheme houseWork`.
The app must stay compatible with iOS 15, so avoid APIs or deployment-target changes that drop support for that OS unless explicitly approved.

## Coding Style & Naming Conventions
Follow standard Swift style: 4-space indentation, braces on the same line, and 120-character line guidance. Types, views, and protocols use UpperCamelCase (e.g., `TasksDashboardView`); functions, properties, and local variables use lowerCamelCase. Derive view file names from the main type (`TaskRow.swift` defines `TaskRow`). Prefer `struct` + `View` for SwiftUI components, keep modifiers readable by grouping related ones, and extract reusable styling into extensions under an adjacent `Modifiers` or `Components` subfolder when it improves clarity.

## Testing Guidelines
Place unit specs beside mirrored production files in `houseWorkTests/` and suffix classes with `Tests` (`ContentViewModelTests`). UI tests belong in `houseWorkUITests/` and should reset app state in `setUpWithError`. Aim to cover new view models and state reducers with XCT assertions plus snapshot or UI validation when rendering changes. Always run `xcodebuild test …` before pushing, and include focused test-only fixtures instead of reusing production models.

## Commit & Pull Request Guidelines
Write concise, imperative commit subjects (e.g., `Add task list filter state`). Squash noisy WIP commits locally before opening a PR. Each PR must describe the change, list verification steps (command, simulator, iOS version), and attach screenshots or screen recordings for UI-affecting updates. Reference issue IDs when available and call out any follow-up work so reviewers can plan next iterations.
