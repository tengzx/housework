# AGENTS

## Internationalization Rules

- All user-facing text must be internationalized from the start. Do not ship hardcoded Chinese or English strings in new features.
- This applies to all visible copy, including:
  - page titles
  - buttons
  - alerts
  - sheets
  - empty states
  - placeholders
  - filter labels
  - status text
  - toolbar items
  - notification content
  - accessibility labels and hints

## Localization Implementation

- Add every new localization key to both:
  - `HealthDataExport/Resources/I18n/zh-Hans.json`
  - `HealthDataExport/Resources/I18n/en.json`
- Keep keys semantically grouped, for example:
  - `fitness.session.*`
  - `record.action.*`
  - `calendar.event_form.*`
- Reuse existing keys when the wording matches. Do not create duplicate keys for the same meaning.

## Which Helper To Use

- In app UI code, prefer `L10n.tr(...)`.
- In shared or lower-level code that should not depend on view-layer localization context, use `SharedL10n.tr(...)`.
- When adding formatted copy, always localize the full template string instead of concatenating fragments in code.

## Forbidden Patterns

- Do not hardcode user-visible strings like:
  - `Text("开始")`
  - `Button("Save")`
  - `errorMessage = "加载失败"`
- Do not assemble sentences by string concatenation when a localized format string should be used instead.

## Delivery Expectation

- Any feature work is incomplete until required localization keys are added and wired.
- Before finishing, check that newly added keys resolve correctly and do not fall back to raw key names in the UI.

## Repository Collaboration Defaults

- The frontend app repository is `/Users/tengzx/myProject/HealthDataExport`.
- The backend repository is `/Users/tengzx/myProject/life-os`.
- For product feature development, treat frontend and backend implementation as one scope by default. Complete the required API, persistence/query logic, app integration, localization, and proportional tests in both repositories unless the user explicitly limits the request to one side.
- When the user says `提交代码推送远端`, treat it as applying to both the frontend app and backend by default.
- For that request, stage, commit, and push each repository to its own remote unless the user explicitly says otherwise.
- After writing this rule into `AGENTS.md`, do not add extra explanation about the convention in normal follow-up replies unless the user asks for it.
