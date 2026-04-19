# TODO & Questions

## Completed
- [x] Remove all mock/demo data from views and backend
- [x] Rewrite DatabaseManager — removed `seedDemoDataIfEmpty()`, added CRUD for artifacts & phase events
- [x] Rewrite OrchestratorService — real xcodebuild build/test pipeline with simctl
- [x] Rewrite RunnerService — `ProjectTarget` enum (.project/.workspace), public shell commands
- [x] Rewrite AppState — async run execution, auto-creates ResiLife project from local iosApp repo
- [x] Fix all views (Sidebar, Overview, RunDetail, Coverage, Insights, Integrations, Settings) to be data-driven
- [x] App builds successfully
- [x] Autonomous Exploration Engine — Harness/OCQAHarnessUITests/ExplorerTests.swift implements fully generalized autonomous iOS exploration. Features: depth-first prioritization (content before tab bars), persistent-nav detection (auto-deprioritizes elements appearing across screens), dynamic screen bounds (no hardcoded device dimensions), system alert handling (`addUIInterruptionMonitor`), keyboard dismissal, animation settle detection, crash recovery, loop detection, scroll-then-back stuck recovery. OCQA_ protocol output parsed real-time by ExplorationService.swift.
- [x] Coverage Flow Map Accuracy — CoverageView now uses real screen names and transition data from the exploration engine via OCQA_TRANSITION events.
- [x] Accessibility Tree Extraction — `testDumpUITree` exports full element tree via OCQA_UITREE protocol. Exploration loop reads up to 500 elements per screen with type, identifier, label, frame, enabled/hittable state.

## TODO — Not Yet Implemented

### Visual Regression / Screenshot Comparison
- Screenshots are captured per-action during exploration (attached to xcresult). No baseline diffing system exists yet.
- **Approach**: Store baseline screenshots per screen hash in SQLite. On subsequent runs, compare via pixel-diff or perceptual hash. Flag regressions as findings.

### Screen Recording / Video Capture
- The exploration harness captures per-action screenshots as XCTest attachments (in the `.xcresult` bundle).
- For full video recording, two approaches are available:
  1. **`xcrun simctl io <UDID> recordVideo`**: Start before exploration, stop after. Simple but produces one long video.
  2. **`ios-agent record-test`** (used by `~/.openclaw/scripts/ewag-capture.sh`): Records via XCUITest, extracts from xcresult, converts MP4→WebM with ffmpeg, uploads to Google Drive. More mature pipeline.
- **Status**: Not yet wired into ExplorationService. The xcresult path is already returned; screenshots can be extracted with `xcresulttool`.
- RunDetailView's video player area is still a placeholder.

### Integration OAuth Flows
- Integration cards (GitHub, Jira, Slack, etc.) show from DB but "Configure" buttons are no-ops. No OAuth or webhook setup.

### Keychain ↔ Settings UI
- KeychainService exists but is not wired to the Settings > Test Credentials UI (edit buttons are no-ops).

### Notification System
- Settings toggles for notifications use `.constant()` bindings — not persisted.

## Questions / Blockers

1. **ResiLife branch state**: Always target `main`. ✅ Resolved.
2. **Test credentials**: Does ResiLife require login credentials for testing? If so, they need to be stored via KeychainService and passed to the test runner. The explorer currently types generic test data (test@example.com, TestPass123!) when it encounters text fields.
3. **ResiLife test targets**: `ResiLifeTests` and `ResiLifeUITests` exist but may have limited test coverage. The current pipeline runs `xcodebuild test` against them — are they expected to pass?
4. **Derived data isolation**: The orchestrator uses a temp derived data path (`/tmp/openclaw-qa-derived/<runId>`). This is fine for isolation.
5. **CI/CD integration**: Is this app intended to run locally only, or should it support remote runners / GitHub Actions triggers?

## Aaron Next Steps
> Tasks that require a human to unblock development.

### 1. Test Credentials for ResiLife
- The explorer types generic placeholder text into login fields. **If ResiLife requires real auth**, create test account credentials and add them to the project config (`QAProject.testCredentials` or similar).
- Consider: does the app have a "demo mode" or test environment bypass?

### 2. Keychain / macOS Permissions on Taylor's Mac
- OpenClawQA needs Keychain access to store credentials. First run on Mac will prompt for permission — approve it.
- XCUITest automation requires "Accessibility" permission for the test runner process. Verify in System Settings → Privacy & Security → Accessibility.

### 3. Code Signing for Harness
- The OCQAHarness xcodeproj uses automatic signing with `DEVELOPMENT_TEAM = ""`. If Xcode prompts for a team, select Taylor's Apple Developer account.
- For physical device testing (not just simulator), a provisioning profile is needed.

### 4. GitHub Credentials on Mac
- Git push from Mac fails (`fatal: could not read Username`). The Mac's `osxkeychain` credential helper has no stored token.
- **Fix**: Either add a GitHub PAT to the Mac's keychain, or continue the current workflow (push from Linux only, Mac pulls).

### 5. Integration OAuth Setup
- GitHub, Jira, Slack integration cards are UI stubs. To wire them:
  - **GitHub**: Create an OAuth App or use a PAT. Store in KeychainService.
  - **Jira**: Create API token at id.atlassian.com.
  - **Slack**: Create a Slack app with incoming webhook.
- This is blocked on Aaron deciding which integrations are priority.

### 6. Video Capture Pipeline Decision
- Choose between:
  - (A) `simctl io recordVideo` — simple, one command, produces .mov
  - (B) `ios-agent record-test` via ewag-capture.sh — more mature, handles conversion/upload
- Once decided, the wiring into ExplorationService is straightforward.

### 7. Google Drive Upload for Artifacts
- ewag-capture.sh already handles Google Drive upload. To reuse for OpenClawQA artifacts:
  - Verify `~/.openclaw/credentials/google_client_secret.json` is configured
  - The upload function can be called post-exploration to push screenshots/videos to Drive
