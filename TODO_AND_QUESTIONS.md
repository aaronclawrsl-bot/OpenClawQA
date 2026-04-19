# TODO & Questions

## Completed
- [x] Remove all mock/demo data from views and backend
- [x] Rewrite DatabaseManager — removed `seedDemoDataIfEmpty()`, added CRUD for artifacts & phase events
- [x] Rewrite OrchestratorService — real xcodebuild build/test pipeline with simctl
- [x] Rewrite RunnerService — `ProjectTarget` enum (.project/.workspace), public shell commands
- [x] Rewrite AppState — async run execution, auto-creates ResiLife project from local iosApp repo
- [x] Fix all views (Sidebar, Overview, RunDetail, Coverage, Insights, Integrations, Settings) to be data-driven
- [x] App builds successfully

## TODO — Not Yet Implemented

### Autonomous Exploration Engine
- The app references "autonomous exploration" in the UI (AI Analysis, coverage flow map) but there is no actual crawler/explorer that navigates the app, discovers screens, taps elements, etc.
- This is the core missing feature. Currently the app can build, install, launch, run xcodebuild tests, and collect logs/screenshots, but it cannot autonomously explore the app.

### Visual Regression / Screenshot Comparison
- No baseline screenshot comparison system exists. Screenshots are captured but never diffed.

### Screen Recording / Video Capture
- Video player area in RunDetailView is a placeholder. No `simctl io recordVideo` integration.

### Accessibility Tree Extraction
- No `simctl` accessibility snapshot or XCUIElement tree extraction implemented.

### Integration OAuth Flows
- Integration cards (GitHub, Jira, Slack, etc.) show from DB but "Configure" buttons are no-ops. No OAuth or webhook setup.

### Keychain ↔ Settings UI
- KeychainService exists but is not wired to the Settings > Test Credentials UI (edit buttons are no-ops).

### Notification System
- Settings toggles for notifications use `.constant()` bindings — not persisted.

### Coverage Flow Map Accuracy
- CoverageView generates a fixed set of screen names (Launch, Login, Home, Feed, etc.) as placeholders. Real coverage requires the exploration engine to report visited screens.

## Questions / Blockers

1. **ResiLife branch state**: The iosApp repo is on branch `issue-95-auth-email-provider-strategy`, not `main`. Should QA runs target main or the current branch?
2. **Test credentials**: Does ResiLife require login credentials for testing? If so, they need to be stored via KeychainService and passed to the test runner.
3. **ResiLife test targets**: `ResiLifeTests` and `ResiLifeUITests` exist but may have limited test coverage. The current pipeline runs `xcodebuild test` against them — are they expected to pass?
4. **Derived data isolation**: The orchestrator uses a temp derived data path. Should it share with the user's normal Xcode derived data?
5. **CI/CD integration**: Is this app intended to run locally only, or should it support remote runners / GitHub Actions triggers?
