# IOS_QA_PRODUCT_DEV_INSTRUCTIONS.md

## Purpose

This document is the authoritative technical product design and implementation specification for a macOS desktop application that delivers autonomous QA for iOS applications. It is written for a coding agent and must be treated as build instructions, not marketing copy. Implement exactly what is specified unless explicitly marked optional or future.

The product name used internally in this document is **OpenClaw QA**, but the codebase should avoid hard-coding branding where not necessary.

This product is a **macOS desktop QA control plane** for iOS apps. It connects to source repositories and selected external systems, builds customer apps, runs autonomous validation on iOS simulators and optionally real devices, captures artifacts, classifies failures, and pushes findings back into engineering workflows.

The initial product is **macOS desktop first**, not browser first.

---

## Implementation Status — READ THIS FIRST

> **Last updated: 2026-04-19**
>
> This section documents exactly what has been built, what works, what was learned, and what remains.
> An agent inheriting this project must read this section thoroughly before touching any code.

### Repository & Git

- **Repo**: `aaronclawrsl-bot/OpenClawQA` on GitHub (private)
- **Local (Linux build server)**: `/home/aaron/repos/OpenClawQA`
- **Local (Mac runner)**: `~/repos/OpenClawQA` on `taylorolsen-vogt@100.125.133.123` (Tailscale IP)
- **Branch**: `main` (only branch)
- **Commits** (oldest → newest):
  1. `0d1d624` — SwiftUI desktop app: full UI, 11 views, SQLite DB, models, services
  2. `afd41a7` — Remove all mock data, wire real xcodebuild/simctl backend pipeline
  3. `c71fbb1` — Wire autonomous exploration harness into the full orchestration pipeline
  4. `07af7c5` — Generalize explorer: snapshot-based tree reading (~60x faster), persistent-nav detection, depth-first prioritization, remove all app-specific code

### What Is Built (22 Swift files + 1 harness test file)

| Layer | Files | Status |
|-------|-------|--------|
| **Entry point** | `OpenClawQAApp.swift`, `ContentView.swift` | Working |
| **Models** | `Models.swift` | Complete: QAProject, QARun, QAFinding, ScreenSnapshot, ActionEvent, CoverageNode, RunPhaseEvent, QAArtifact, enums |
| **Database** | `DatabaseManager.swift` | SQLite3, 11 tables, CRUD for all model types |
| **Services** | `OrchestratorService.swift` | Full pipeline: git→build→boot→install→launch→explore→analyze→summarize |
| | `ExplorationService.swift` | Builds and runs harness, parses OCQA_ protocol in real-time |
| | `RunnerService.swift` | Shell command wrapper, xcodebuild, simctl |
| | `KeychainService.swift` | macOS Keychain read/write (stub, not wired to UI) |
| **Views** | `SidebarView`, `OverviewView`, `RunsListView`, `RunDetailView`, `FindingsView`, `CoverageView`, `InsightsView`, `IntegrationsView`, `SettingsView`, `ProjectSetupWizard`, `Components` | All data-driven, no mock data |
| **Theme** | `Theme.swift` | Colors, typography, spacing constants |
| **State** | `AppState.swift` | @Observable, async run execution, auto-creates ResiLife project from ~/repos/iosApp |
| **Harness** | `Harness/OCQAHarnessUITests/ExplorerTests.swift` (726 lines) | Fully generalized autonomous iOS exploration engine |

### What Works End-to-End

The full release check pipeline runs:
1. OrchestratorService detects git branch/commit from local repo
2. `xcodebuild build-for-testing` with isolated derived data
3. `xcrun simctl boot` + `simctl install` + launch screenshot
4. ExplorationService deploys the OCQAHarness XCUITest, parses OCQA_ protocol output in real-time
5. Findings classified (crash, dead_end, navigation_loop, build_failure, etc.)
6. Confidence score computed: `100 - (critical×25 + high×10 + medium×3 + low×1)`
7. Release readiness: ready (≥70) / caution (40–69) / blocked (<40)
8. All artifacts persisted to SQLite + local filesystem

### What Does NOT Work Yet

| Gap | Detail |
|-----|--------|
| **Visual regression** | Screenshots captured per-action in xcresult, but no baseline diffing system exists |
| **Video recording** | RunDetailView video area is a placeholder. See "Visual Media Acquisition" section below for the chosen approach |
| **Integration OAuth** | GitHub/Jira/Slack UI cards exist but Configure buttons are no-ops |
| **Keychain UI** | KeychainService exists but Settings > Test Credentials buttons are stubs |
| **Notification persistence** | Settings toggles use `.constant()` bindings — changes not saved |
| **OrchestratorService hardcodes** | `simulatorName = "iPhone 16 Pro"`, `maxActions: 200`, `timeoutSeconds: 1800` — should come from project config |

### Critical Performance Finding: Snapshot-Based Tree Reading

This is the single most important engineering finding in the project. **The autonomous explorer was unusable until this was discovered and fixed.** Any future work on the explorer must preserve this optimization.

**The problem**: XCUITest's standard element-by-element queries (`query.element(boundBy: i).frame`, `.label`, `.identifier`, `.isEnabled`) each make a separate IPC round-trip to the accessibility server. Reading 200+ elements this way takes 60–120 seconds per screen.

**The solution**: `XCUIElement.snapshot()` fetches the **entire accessibility tree in a single IPC call**. The snapshot object contains all attributes (frame, label, identifier, elementType, isEnabled, children) already materialized in memory.

**Performance comparison (25-action run on ResiLife):**

| Metric | Before snapshot (element-by-element) | After snapshot |
|--------|--------------------------------------|----------------|
| Actions completed | 3 of 25 (timeout at 5 min) | 25 of 25 |
| Test duration | 369 seconds | **51.5 seconds** |
| Speed | ~123 seconds/action | **~2 seconds/action** |
| Unique states discovered | 3 | 14 |
| Named screens detected | 0 ("Unknown" ×3) | 5 (Emma K, Good Afternoon Emma, Priya Nair, Edit Profile, nutrition tip) |

**Implementation**: `readViaSnapshot()` in ExplorerTests.swift. Falls back to `readElementByElement()` only if snapshot() throws (pre-Xcode 15 compatibility). The snapshot walker is recursive with a 200-element limit.

**Additional optimizations applied:**
- Eliminated second `readUITree()` call per action cycle (transition hash now computed cheaply from element count)
- Simplified animation settle from element-count comparison to fixed 0.3s delay
- Reduced app settle loop from 10 iterations to 5
- `detectTitle()` fixed to use `rawValue: 74` (NavigationBar) and `rawValue: 48` (StaticText) since `String(describing: elementType)` produces `XCUIElementType(rawValue: N)`, not human-readable names

### Exploration Engine Architecture (What Was Learned)

The harness went through three iterations. Key design decisions that work:

1. **Persistent-nav detection**: Tracks `elementScreenPresence` — which element keys appear on which screen hashes. Elements appearing on many screens (tab bar items) are deprioritized. Threshold: `max(2, totalDistinctStates / 2)`.

2. **Depth-first prioritization**: Within a screen, interactable elements sorted by:
   - Not-persistent over persistent (tab bar items pushed to bottom)
   - Least-visited element first
   - Content area (y < 88% screen height) over bottom bar
   - Base type priority: Cell(5) > Link/Button(4) > SegmentedControl/Picker(3) > TextField(2) > Switch/Toggle(1)

3. **Stuck recovery**: `repeatedStateCount >= 3` → scroll up; `>= 4` → scroll down; `>= 5` → tryGoBack() (checks nav bar back button, then Close/Cancel/Done/Dismiss buttons, then edge-swipe)

4. **System alert handling**: `addUIInterruptionMonitor` auto-taps Allow/OK/Continue on iOS permission dialogs

5. **Snapshot-based elements have nil xcElement**: When using snapshot-based tree reading, `SimpleElement.xcElement` is nil. Text field typing falls back to identifier-based lookup or first responder.

6. **Screen fingerprint is structural, not visual**: Hash built from `type:identifier:isEnabled` for all elements. Fast to compute, stable across animation frames, but does not detect visual-only changes (that requires screenshot diff).

---

## Product Goals

### Primary goal
Allow a user to connect an iOS repo and repeatedly answer:

- Did the app build?
- Did the app launch?
- What screens and flows were explored?
- What bugs, regressions, dead ends, crashes, layout issues, and broken states were discovered?
- What changed versus the previous run?
- Is this build safe enough to ship?

### Secondary goals
- Make setup dramatically easier than assembling XCUITest + CI + manual screenshots + crash triage by hand.
- Make artifacts first-class: video, screenshots, logs, accessibility tree, reproduction steps, environment metadata.
- Integrate into real engineering workflows: GitHub, Jira, Slack, email, CI/CD.
- Make autonomous exploration the product moat, not traditional scripted-test authoring.
- Support deterministic smoke checks and autonomous exploration in the same platform.
- Support repo-native workflows: branch, commit SHA, PR, release candidate, environment.
- Use outcome language, not test-framework language.

### Non-goals for v1
- Android support.
- Browser-first SaaS dashboard.
- Rich manual test-case authoring UI.
- User-managed LLM provider configuration in the main product flow.
- Fully automatic backend seeding for arbitrary repos. Design extension points for it, but do not make product success depend on it.

---

## Product Form Factor

Build a native **macOS desktop application** with local UI and a local orchestration layer. The desktop app may communicate with a local background service and one or more remote services.

### Why macOS desktop first
- The platform is inherently tied to Xcode, Simulator, and Apple toolchains.
- A local macOS app reduces friction for teams that already build locally.
- It allows direct access to local repos, local simulators, developer certs, and local logs.
- It provides a path to both local execution mode and remote runner mode.

### Required operating modes
Implement both of the following modes, even if remote mode is initially less complete:

1. **Local Runner Mode**
   - The desktop app runs builds and tests on the user's local Mac.
   - Best for early adopters, internal use, and debugging.
   - Must have first-class support.

2. **Remote Runner Mode**
   - The desktop app acts as the control plane while jobs run on registered remote Mac runners.
   - The desktop app must be architected so this is possible without rethinking core abstractions.
   - The user experience should be nearly identical except for runner selection and setup.

---

## Core Product Principles

### 1. Repo-centric, not test-suite-centric
The main unit of work is a **project** connected to an iOS repository.

### 2. Exploration-centric, not manual-script-centric
Do not make the central UI about manually authored tests. The primary UX is:
- connect repo
- configure build + credentials + environment
- run smoke or autonomous sweep
- inspect findings
- compare against previous run
- export or sync findings

### 3. Evidence-first
Every meaningful finding must link to evidence:
- screenshot
- video replay segment
- logs
- screen metadata
- environment
- exact reproduction sequence

### 4. Release-focused
The product should make it easy to answer “should I merge / should I release” rather than merely “did some tests pass”.

### 5. Minimal provider surface
Users should connect only business-critical integrations:
- GitHub
- Jira
- Slack or a messaging integration
- Email delivery
- CI/CD trigger sources (Jenkins, Xcode Cloud, GitHub Actions initially, with extensibility)
Do not expose raw model-provider setup in the primary UX.

---

## External Integrations Allowed

The product should support connecting only the following categories initially:

### Required integrations
1. **GitHub**
2. **Jira**
3. **Slack**
4. **Email delivery**
5. **CI/CD providers**
   - GitHub Actions
   - Jenkins
   - Xcode Cloud

### Optional future integrations
- Linear
- Microsoft Teams
- Bitbucket
- GitLab
- Buildkite
- CircleCI

### Explicit product guidance
Do not design the initial product around broad arbitrary plugin support. Build a clean integration abstraction internally, but expose only the integrations listed above.

---

## High-Level Architecture

Implement the system using these layers.

### Layer A: macOS desktop app
Responsibilities:
- UI
- project setup
- repo selection
- credentials input
- integration setup
- run launch / cancel / retry
- findings browser
- artifact viewer
- comparisons
- runner management
- preferences
- local state cache

### Layer B: local orchestration service
A local service process that the desktop UI talks to over IPC or localhost HTTP/gRPC. Responsibilities:
- job scheduling
- command execution
- xcodebuild orchestration
- simulator/device orchestration
- artifact collection
- structured event stream
- secure secret access
- worker lifecycle
- logs

This may be embedded or separately launched, but architect it as a separable service.

### Layer C: execution adapters
Adapters for:
- GitHub repo sync / checkout
- dependency install
- Xcode build and test
- Simulator control
- XCUITest driver control
- accessibility tree extraction
- screenshot/video collection
- crash log collection
- log streaming
- CI event ingestion
- issue export
- notification dispatch

### Layer D: autonomous QA engine
Responsibilities:
- state modeling
- action selection
- loop prevention
- screen classification
- finding detection
- issue severity scoring
- repro generation
- run summarization
- comparison to previous runs

### Layer E: persistence
There are two persistence scopes:

1. **Local embedded database**
   - primary for desktop-first mode
   - SQLite required
   - stores projects, runs, findings, settings, credentials references, environment snapshots, artifacts metadata

2. **Optional remote backend**
   - design for future sync
   - not required to block v1
   - must be possible to add later without reworking models

### Layer F: artifact storage
Artifacts may be stored locally first. Design storage abstraction with two implementations:
- local filesystem artifact store
- remote object store (future)

---

## Technology Requirements

### macOS app
Use **Swift + SwiftUI** for the desktop application. **This is implemented.** The app targets macOS 14+ and uses `@Observable` (not `@ObservationObject`) for state management.

### Local database
Use **SQLite** via direct `sqlite3` C API in Swift (not GRDB, not Core Data). **This is implemented.** `DatabaseManager.swift` manages 11 tables with explicit schema control. Tables: projects, runs, findings, finding_links, screen_snapshots, action_events, artifacts, run_phase_events, suppression_rules, runners, integration_connections.

### Orchestration service
Currently implemented as an **embedded Swift singleton** (`OrchestratorService.shared`) within the desktop app process. It coordinates builds, simulators, exploration, and analysis sequentially. It is not yet a separate daemon process. The architecture supports extraction into a separate service if needed, but for local runner mode the embedded approach works.

### iOS app execution
Uses:
- `xcodebuild build-for-testing` and `xcodebuild test-without-building` (harness)
- `xcrun simctl` (boot, install, launch, terminate, screenshot, device listing)
- XCUITest via the OCQAHarness project (ExplorerTests.swift)
- `xcrun xcresulttool` for extracting screenshots and test summaries from `.xcresult` bundles
- Process + Pipe for real-time stdout parsing of OCQA_ protocol markers

### Harness build system
The harness at `Harness/` uses a Ruby script (`generate-harness-xcodeproj.rb`) to produce `OCQAHarness.xcodeproj`. This avoids checking in Xcode project files. The harness contains:
- `OCQAHarness/AppDelegate.swift` — minimal host app (required by XCUITest)
- `OCQAHarnessUITests/ExplorerTests.swift` — the autonomous exploration engine

### Avoid
- Making the core product Electron.
- Building the autonomous engine around brittle coordinate-only clicking. (**Already avoided**: the explorer uses accessibility tree + structural heuristics. Coordinates are only used for the final tap, derived from element frame geometry.)
- Requiring users to expose API model keys in the standard flow.
- **Per-element IPC queries for UI tree reading.** Always use `XCUIElement.snapshot()` for bulk tree reads. See "Critical Performance Finding" in the Implementation Status section.

---

## Desktop App Information Architecture

The macOS app must contain the following top-level navigation sections.

### 1. Projects
Purpose:
- create/open/manage connected QA projects
- repo setup
- integration status
- environment setup
- credentials configuration

### 2. Runs
Purpose:
- list all runs
- filter by project, branch, environment, status, severity
- compare runs
- rerun or clone configuration

### 3. Findings
Purpose:
- cross-run issue feed
- severity triage
- dedupe and group similar findings
- assign/export/suppress

### 4. Coverage
Purpose:
- show what the autonomous engine explored
- screen graph
- flow graph
- path depth
- dead ends
- unvisited or unstable surfaces

### 5. Environments
Purpose:
- simulator/device targets
- test accounts
- app env vars
- launch args
- backend mode tags
- seed state descriptors

### 6. Integrations
Purpose:
- GitHub
- Jira
- Slack
- Email
- CI/CD

### 7. Settings
Purpose:
- app preferences
- analysis depth
- retention
- privacy
- notifications
- local storage
- runner settings

### 8. Runner Control
Purpose:
- local runner health
- remote runner registration and status
- queue visibility
- concurrency controls
- simulator inventory
- Xcode versions

Do not make “Tests” a primary top-level item in the initial product. Scripted or deterministic flows should appear as reusable checks under project configuration, not as the identity of the product.

---

## Core User Workflows

## Workflow 1: Create project from repo

### Entry
User opens app and clicks **New Project**.

### Required flow
1. User selects repo source:
   - local folder
   - clone from GitHub
2. App detects:
   - `.xcworkspace`
   - `.xcodeproj`
   - available shared schemes
   - package manager hints (SwiftPM, CocoaPods)
3. App presents detected build targets and asks user to confirm:
   - workspace or project
   - scheme
   - target app bundle
   - preferred simulator target
4. App asks user to choose run mode:
   - local runner
   - remote runner
5. App saves project shell.
6. App prompts user for project config completion.

### Required validation
- Fail fast if no buildable iOS app target is found.
- If multiple plausible targets exist, force explicit user choice.
- Save the raw scan result as structured data.

---

## Workflow 2: Configure project

Each project must have an explicit configuration object. The UI should edit it directly.

### Required project configuration fields
- project name
- repo path or GitHub repo reference
- default branch
- workspace path or project path
- scheme
- configuration (`Debug`, `Release`, or custom)
- app target bundle identifier
- launch arguments
- environment variables
- simulator/device target profile
- authentication mode
- test credentials references
- deterministic checks enabled
- autonomous exploration enabled
- max run duration
- max exploration depth
- permissions handling policy
- notification policy
- artifact retention policy
- integration sync policy

### Project config file
Generate and maintain a human-readable file in repo or alongside project metadata:

`.openclaw.yml`

The app must be able to read and write this file. The file is the portable spec for a project and should be source-controllable if desired.

### Required `.openclaw.yml` structure
```yaml
version: 1
platform: ios
repo:
  source: github
  owner: your-org
  name: your-app
  default_branch: main
build:
  workspace: YourApp.xcworkspace
  project:
  scheme: YourApp
  configuration: Debug
  derived_data_mode: isolated
app:
  bundle_id: com.example.yourapp
  launch_arguments:
    - -UITestMode
    - YES
  environment:
    API_BASE_URL: https://staging.example.com
    FEATURE_FLAG_X: "true"
runner:
  mode: local
  xcode_version: "16.0"
  simulator:
    device: "iPhone 16 Pro"
    os: "latest"
auth:
  mode: credential_form
  credentials:
    email_env: TEST_EMAIL
    password_env: TEST_PASSWORD
checks:
  deterministic:
    enabled: true
    suites:
      - launch
      - login_smoke
      - tab_navigation
  autonomous:
    enabled: true
    max_duration_minutes: 30
    max_actions: 400
    max_depth: 20
permissions:
  camera: deny
  notifications: allow
  photos: deny
integrations:
  github:
    enabled: true
    pr_comments: true
  jira:
    enabled: false
  slack:
    enabled: true
    channel: "#ios-qa"
notifications:
  on_run_complete: true
  on_critical_finding: true
retention:
  local_days: 30
  keep_videos_for_failed_runs_only: false
```

---

## Workflow 3: Connect integrations

### GitHub
Required capabilities:
- sign in via OAuth or PAT
- select org/repo
- read branches, commits, PR metadata
- post PR comments
- create check-run style statuses where possible
- attach links back to findings

### Jira
Required capabilities:
- sign in
- choose site/project
- map severity to issue priority
- create issues from findings
- update existing linked issues
- optionally comment on linked issues with rerun results

### Slack
Required capabilities:
- connect workspace
- choose channel per project
- send run summaries
- send critical finding alerts
- include deep links back into desktop app if feasible
- attach image/video previews or export links

### Email delivery
Required capabilities:
- SMTP or transaction email integration abstraction
- support sending:
  - run completed summary
  - critical findings
  - daily digest (future)
- allow recipient lists per project

### CI/CD
Required integrations:
- GitHub Actions
- Jenkins
- Xcode Cloud

Required capabilities:
- receive build/commit trigger context
- start QA run from commit/branch/PR metadata
- associate run with CI build identifier
- optionally block release decision via generated status

Do not overgeneralize. Implement separate adapters with a normalized event structure.

---

## Workflow 4: Run a release check

### Definition
A release check is the primary user-triggered action.

### UI
Prominent button: **Run Release Check**

Secondary actions:
- Run Smoke Pass
- Run Autonomous Sweep
- Rerun Last Configuration

### Release check pipeline
1. Resolve project configuration.
2. Resolve runner.
3. Create isolated run record.
4. Checkout correct repo revision.
5. Prepare build environment.
6. Install dependencies if needed.
7. Build app.
8. Boot simulator/device.
9. Install app.
10. Run deterministic smoke checks.
11. Run autonomous exploration.
12. Collect artifacts and logs continuously.
13. Classify findings.
14. Compare against previous baseline if available.
15. Produce release confidence result.
16. Dispatch integrations.
17. Persist all results.

### Required statuses
- queued
- preparing
- building
- booting
- installing
- deterministic_checks
- exploring
- analyzing
- summarizing
- completed
- failed
- cancelled

The UI must show exact current phase and step detail.

---

## Workflow 5: Inspect run results

### Run details screen must include
- project
- run id
- branch
- commit SHA
- PR number if present
- trigger source (manual, CI, schedule)
- runner used
- start/end time
- Xcode version
- simulator/device profile
- app build info if detectable
- release confidence score
- summary counts:
  - critical findings
  - high
  - medium
  - low
  - crashes
  - dead ends
  - visual regressions
  - deterministic failures
- exploration stats:
  - screens visited
  - actions executed
  - unique paths
  - max depth
  - loops avoided
  - permission prompts handled

### Artifact panes
Required panes:
- video replay
- screenshots timeline
- findings feed
- logs
- environment metadata
- accessibility snapshots
- screen graph / path graph
- diff vs previous run

### Required video behavior
- show full replay video if available
- show timeline markers for findings
- clicking a finding jumps to its timestamp

### Screenshot behavior
- timeline or gallery
- clicking screenshot opens full-screen viewer
- show associated screen metadata and step number

---

## Workflow 6: Findings triage

### Finding model
A finding is a structured object with:
- stable id
- project id
- run id
- category
- subtype
- title
- summary
- severity
- confidence
- evidence links
- exact repro sequence
- first seen
- last seen
- screen identifiers
- hash/dedupe signature
- issue linkage data
- status

### Required finding categories
- build_failure
- launch_failure
- crash
- deterministic_check_failure
- unresponsive_element
- navigation_dead_end
- repeated_loop
- visual_regression
- layout_overlap
- text_clipping
- missing_asset
- blank_screen
- auth_failure
- network_error_surface
- permission_blocker
- unexpected_modal
- performance_timeout
- app_hang

### Finding statuses
- open
- acknowledged
- linked
- suppressed
- resolved
- regressed

### Finding detail screen must show
- summary
- severity and confidence
- evidence gallery
- timestamp in replay
- exact steps
- screen context
- environment
- suggested root-cause hints
- export actions
- linked GitHub/Jira references

### Suppression behavior
Allow per-project suppression rules based on:
- title hash
- screen
- category
- environment
- severity threshold
Suppression must never delete history.

---

## Workflow 7: Compare runs

### Compare screen must show
- run A vs run B
- build metadata diff
- findings added / removed / changed
- screenshots diff
- exploration coverage delta
- release confidence delta
- environment differences

### Use cases
- compare PR vs base branch
- compare today vs yesterday
- compare before and after fix

### Required compare outputs
- new findings
- resolved findings
- severity escalation
- visual changes
- flow coverage changes
- unexplored area changes

---

## Autonomous Exploration Engine

This is the moat. It is built and working. The following section describes both the design intent and the actual implementation.

### Implementation Reference

The engine lives in `Harness/OCQAHarnessUITests/ExplorerTests.swift` (726 lines). It is a standard XCUITest that attaches to any iOS app via bundle ID, explores autonomously, and communicates results via stdout markers (the OCQA_ protocol).

**It is fully generalized — no app-specific code, no hardcoded identifiers, no hardcoded screen dimensions.** This was explicitly designed and tested to work against any iOS application.

### OCQA_ Protocol Specification

The harness communicates to the host process (ExplorationService.swift) via stdout markers. Each marker is a single line starting with a prefix:

```
OCQA_STATE:exploration_started max_actions=25
OCQA_STATE:{"screen":"Good Afternoon, Emma","hash":"8a00a4bb","elements":82,"action":7}
OCQA_ACTION:{"type":"tap","target":"Reserve Spot","elementType":"XCUIElementType(rawValue: 9)","step":9,"x":329,"y":372}
OCQA_TRANSITION:{"from":"Good Afternoon, Emma","fromHash":"8a00a4bb","to":"pending","toHash":"0009e04f","action":"Reserve Spot"}
OCQA_PROGRESS:{"action":9,"max":25,"states":7}
OCQA_ISSUE:{"type":"navigation_loop","severity":"high","title":"Navigation loop on Home","screen":"Home","step":14}
OCQA_COMPLETE:{"actions":25,"states":14,"issues":4,"screens":"Edit Profile,Emma K,Good Afternoon, Emma,Priya Nair"}
OCQA_UITREE_START / OCQA_UITREE_END — wraps full accessibility tree JSON dump (testDumpUITree mode)
```

ExplorationService.swift parses these in real-time via Pipe readabilityHandler and creates QAFinding, ScreenSnapshot, ActionEvent, and CoverageNode records.

### Test Entry Points

ExplorerTests.swift provides multiple XCTest methods the orchestrator can invoke:

| Method | Purpose |
|--------|---------|
| `testAutonomousExploration` | Full autonomous loop: read tree → pick action → act → detect transition → repeat |
| `testDumpUITree` | One-shot: read accessibility tree, emit OCQA_UITREE JSON |
| `testTapAtCoordinate` | Single tap at (x,y) — for engine-directed actions |
| `testTapById` | Single tap by accessibility identifier |
| `testSwipe` | Swipe in configured direction |
| `testTypeText` | Type text into identified or first text field |
| `testGoBack` | Navigate back (nav bar button or edge swipe) |
| `testScreenshot` | Capture and attach a screenshot |

### Configuration

The harness reads config from `/tmp/ocqa-run-config.json`:
```json
{
  "OCQA_BUNDLE_ID": "com.example.app",
  "OCQA_MAX_ACTIONS": "200",
  "OCQA_TIMEOUT_SECONDS": "1800"
}
```
Falls back to environment variables if not found.

## Core objectives
- Explore arbitrary app surfaces without requiring exhaustive manual test scripts.
- Use stable identifiers when available.
- Use heuristics when identifiers are absent.
- Avoid infinite loops and repeated low-value interaction.
- Capture enough evidence to reproduce what happened.
- Prefer meaningful user-like flows over random tapping.

## Inputs
- accessibility tree (via XCUIElement.snapshot() — single IPC call)
- currently visible UI elements
- app state history
- previous actions
- screenshots (attached to xcresult per action)
- deterministic check definitions
- project auth configuration
- permission policy
- screen graph built during run

## Internal state model
For each step, track:
- visible elements (via snapshot-based tree read, up to 200 elements)
- candidate actions (filtered by isEnabled && isInteractable && isHittable)
- action scores (computed by `prioritizeElements()` — see prioritization below)
- current screen fingerprint (structural hash of type:identifier:isEnabled for all elements)
- previous screen fingerprint
- elementScreenPresence map (element key → set of screen hashes it appeared on)
- actionCounts map (element key → number of times acted upon)
- totalDistinctStates counter
- repeatedStateCount (consecutive identical state hashes)
- stateTransitions array
- issues array

### Screen fingerprint
Implemented in `computeHash()`:
- Concatenates `type:identifier:isEnabled` for all elements, joined by `|`
- Applies djb2 hash → hex string
- This is a **structural** fingerprint, not visual. Two screens with identical element trees but different rendered content (e.g., different list data) will hash the same.
- For visual-level change detection, use screenshot diffing (not yet implemented).

### Screen title detection
Implemented in `detectTitle()`:
- First checks for NavigationBar elements (`rawValue: 74`) — returns identifier or label
- Falls back to largest StaticText (`rawValue: 48`) in the top 25% of the screen
- This works well in practice: detected "Good Afternoon, Emma", "Priya Nair", "Edit Profile", "Emma K"

## Action types
- tap element (via coordinate, derived from element frame)
- type into text field (with heuristic text: email→test@example.com, password→TestPass123!, phone→5551234567, name→Test User, zip→90210, search→test, default→test input)
- scroll vertically (normalized coordinate drag 0.78↔0.30)
- go back (nav bar button → Close/Cancel/Done/Dismiss buttons → edge swipe)
- handle system permission alert (via addUIInterruptionMonitor: Allow, Allow While Using App, OK, Continue, Allow Full Access)
- dismiss keyboard (tap above keyboard frame)
- screenshot (attached per action as XCTest attachment)

## Implemented prioritization heuristic

The `prioritizeElements()` function sorts interactable elements by this priority (highest first):

1. **Not persistent** over persistent: Elements appearing on fewer than `max(2, totalDistinctStates/2)` distinct screens are prioritized. This automatically deprioritizes tab bar icons, bottom navigation, and other omnipresent elements.
2. **Least-visited first**: Elements with fewer recorded taps (`actionCounts[key]`) are preferred.
3. **Content area over bottom bar**: Elements above 88% of screen height are preferred over those in the bottom bar area.
4. **Base type priority**: Cell/rawValue:75 (5) > Link/rawValue:39, Button/rawValue:9 (4) > SegmentedControl/Picker (3) > TextField/rawValue:49,50 (2) > Switch/Toggle/rawValue:40 (1) > Other (0)

An element is skipped if it has been acted upon 3+ times. If all elements exceed this, the first sorted element is used anyway.

## Loop prevention (implemented)
The engine detects:
- **Repeated state**: If same screen hash appears 3+ consecutive times → scroll up, then scroll down, then tryGoBack()
- **Navigation loop**: If last 8 state transitions contain ≤ 2 unique destination hashes → emit OCQA_ISSUE, tryGoBack()
- **Dead end**: If no interactable elements found → emit OCQA_ISSUE, tryGoBack, or terminate

On loop detection:
- Back out via nav bar back button, then Close/Cancel/Done/Dismiss buttons, then edge swipe
- Mark dead-end in findings
- Issue emitted as `navigation_loop` or `dead_end` with severity

## Required exploration outputs (all implemented)
- screen graph (via OCQA_TRANSITION: from→to with action label)
- action graph (via OCQA_ACTION: full action log with coordinates)
- state list (via OCQA_STATE: per-action screen state)
- issues (via OCQA_ISSUE: dead_end, navigation_loop, crash)
- OCQA_COMPLETE summary: actions, states, issues, screen names

---

## Deterministic Checks

The product must support lightweight deterministic checks, but they are not the hero feature.

### Current state
OrchestratorService runs a basic launch check: `simctl launch` → wait 3s → `simctl io screenshot` → `simctl terminate`. The launch screenshot is stored as an artifact. There is no structured check execution beyond this — the exploration engine handles the rest.

### Purpose
- validate critical flows reliably
- produce clean pass/fail outcomes
- provide structure before autonomous exploration

### Supported initial check types
- launch app ✅ (implemented)
- login (not yet — depends on test credentials)
- tab navigation (autonomous explorer does this naturally)
- open profile (autonomous explorer does this naturally)
- open settings (autonomous explorer does this naturally)
- logout (not yet)
- custom sequence (future advanced)

### Implementation requirement
Represent deterministic checks as structured steps, not arbitrary code in the first product UI. Under the hood you may compile them into XCTest behavior.

### Example structured deterministic check
```json
{
  "name": "login_smoke",
  "steps": [
    {"action": "wait_for", "target": "emailField"},
    {"action": "type", "target": "emailField", "value_from_secret": "TEST_EMAIL"},
    {"action": "type", "target": "passwordField", "value_from_secret": "TEST_PASSWORD"},
    {"action": "tap", "target": "loginButton"},
    {"action": "assert_visible", "target": "homeTab"}
  ]
}
```

### UI placement
Deterministic checks belong in:
- Project Configuration → Checks
not as a top-level “Test Explorer” product identity.

---

## Accessibility Strategy

This product heavily leverages accessibility metadata. The explorer already works across varying levels of app instrumentation.

### Current implementation
The explorer reads the full accessibility tree via `XCUIElement.snapshot()` and uses a layered identification strategy:
1. **Accessibility identifier** (e.g., `resident.menu.open`, `resident.home.wellnessCheckIn`) — most reliable, used for action keys and logging
2. **Accessibility label** (e.g., `"Reserve Spot"`, `"Back"`, `"house"`, `"paperplane.fill"`) — used when identifier is empty
3. **Frame position** (e.g., `frame:220x293`) — fallback when both identifier and label are empty
4. **Element type** (e.g., `rawValue: 9` = Button, `rawValue: 75` = Cell) — used for prioritization and interactability filtering

### Observed behavior in practice (ResiLife)
- Many ResiLife UI elements have good accessibility identifiers (e.g., `resident.home.curatedForYou`, `resident.sideMenu.overlay`)
- Some elements have only SF Symbol names as labels (e.g., `house`, `leaf`, `person.2`, `paperplane.fill`, `plus.circle.fill`, `xmark`)
- Some elements have empty identifier AND empty label — these fall back to frame-based keys and are still tapped successfully via coordinate
- NavigationBar titles are detected via `rawValue: 74`

### Required fallback support (implemented)
If identifiers are missing:
- use accessibility labels/types ✅
- use relative element position via frame coordinates ✅
- use screen classification + element text ✅
- reduce confidence appropriately (frame-based keys are less stable across screen sizes)

### Product UX requirement (future)
The app should surface accessibility quality issues as developer-facing recommendations:
- missing identifiers on key actions
- ambiguous labels
- unstable duplicate controls
This is valuable and should be a separate recommendation type, not necessarily a failure. **Not yet implemented.**

---

## Build and Runner Requirements

## Local runner (implemented)
Currently supports:
- repo checkout or local path ✅ (auto-detects `~/repos/iosApp`)
- isolated derived data location ✅ (`/tmp/openclaw-qa-derived/<runId>`)
- dependency bootstrap (not yet — no CocoaPods/SPM resolution step)
- xcodebuild build ✅ (build-for-testing with .project or .workspace)
- simulator lifecycle ✅ (boot, shutdown, install, launch, terminate, screenshot)
- app install/uninstall ✅ (via simctl install)
- test execution ✅ (xcodebuild test-without-building → harness)
- artifact collection ✅ (xcresult, build logs, launch screenshot, exploration log)

**Known limitation**: OrchestratorService hardcodes `simulatorName = "iPhone 16 Pro"`. Needs to be configurable from project settings.

## Remote runner (designed, not implemented)
Design interfaces for:
- registered runner identity
- labels (xcode version, simulator availability, hardware profile)
- heartbeats
- job leasing
- secure secret access
- artifact upload
- run logs stream

The current SSH-based workflow (Linux → Mac) is a manual prototype of remote runner mode. Formalizing this into the app's runner abstraction is a natural next step.

## Xcode support
The product must handle multiple Xcode versions. Runner should report installed versions and chosen version per run. **Currently**: OrchestratorService reads `xcodebuild -version` and stores the result.

## Simulator support
Required initial target profiles:
- latest iPhone flagship
- small-screen iPhone
- previous iOS version if available
- iPad optional but supported in model

Store simulator target as abstract profile plus resolved exact runtime.

---

## Secrets and Credentials

Do not store secrets in plain text.

### Required secret classes
- GitHub token or OAuth refresh token
- Jira token
- Slack token
- email SMTP or API credentials
- test account credentials
- repo environment secrets
- CI webhook secrets

### Storage requirement
Use macOS Keychain for local secrets. Database stores only references or encrypted metadata.

### Test credentials UX
Allow users to enter named secrets:
- TEST_EMAIL
- TEST_PASSWORD
- OTP seed (future)
- API token
These can be mapped into project config.

---

## Backend and Data Dependencies

The product must support the reality that many apps require a backend and seeded data.

### Required product position
Do not claim generic automatic backend setup for arbitrary repos.

### Required implementation
Support explicit **Environment Profiles** that define:
- API base URL
- staging vs prod-like tags
- launch args
- env vars
- authentication strategy
- optional pre-run shell command hook (advanced mode)
- optional reset endpoint call (if provided by customer)
- optional seed script command (if provided by customer)

### Environment profile fields
- name
- backend mode
- API host
- launch args
- env vars
- seed strategy
- reset strategy
- credentials set
- notes

### Seed strategy
Support these modes:
- none
- manual prerequisites
- shell command
- HTTP endpoint call
- custom script path

### Reset strategy
Support:
- app reinstall only
- keychain clear + app data reset
- custom shell command
- HTTP reset endpoint

### Important
The UI and docs must clearly tell users that good autonomous testing often requires a stable staging environment and seedable accounts. Support it well, but do not overpromise universal automation.

---

## Visual Regression System

Visual regression is a required major feature. **Not yet implemented**, but the data foundation is in place.

### Current state
- Per-action screenshots are captured as XCTest attachments in the xcresult bundle during exploration
- Screen fingerprints (structural hashes) are computed for every state
- ExplorationService has `extractScreenshots(from:to:runId:snapshots:)` to pull PNGs from xcresult
- No baseline storage or diffing exists yet

### Scope
Detect meaningful UI changes between comparable runs/screens:
- layout overlap
- missing elements
- clipping
- blank states
- severe spacing regressions
- unexpected modal overlays
- missing images or icons
- text overflow/truncation (where detectable)

### Implementation guidance
Use a combination of:
- screenshot diffing (pixel-level or perceptual hash)
- structural metadata from accessibility tree (the screen fingerprint already detects structural changes)
- screen fingerprint matching (already implemented — use hash to pair screens across runs)
- region-level change detection
- heuristics to ignore expected dynamic content where possible

### Baseline selection
Allow baseline selection by:
- previous run on same branch
- latest successful run on default branch
- manually pinned baseline

### Output
Each visual regression finding must show:
- before screenshot
- after screenshot
- highlighted diff region
- screen fingerprint match confidence

---

## Release Confidence Model

Every completed run produces a release confidence result. **This is implemented.**

### Implemented algorithm
```
score = 100 - (critical×25 + high×10 + medium×3 + low×1 + testFails×5)
readiness = score >= 70 ? .ready : score >= 40 ? .caution : .blocked
```

### Required output fields
- release_readiness: `ready`, `caution`, `blocked` ✅
- confidence_score: 0–100 ✅
- summary_reason ✅ (generated from findings counts)
- contributing_factors array (partially — findings counts are tracked, not yet a structured factors array)

### Inputs to confidence score
- build success
- launch success
- deterministic check results
- crash count
- critical/high finding count
- coverage breadth
- repeatability consistency if rerun available
- visual regression severity
- auth flow success
- dead-end count

### UI requirement
Prominently display:
- Release Ready / Caution / Blocked
- Confidence score
- Top reasons

This should be one of the main run-summary features.

---

## Notifications and Exports

## GitHub outputs
For PR-linked runs, support:
- PR summary comment
- commit status / check run style summary where possible
- link to top findings
- summary counts
- release readiness result

## Jira outputs
From a finding detail screen, allow:
- create Jira issue
- link to existing Jira issue
- update linked issue on rerun

Required payload:
- title
- summary
- severity
- environment
- repro steps
- attached screenshots
- video link or embedded reference if feasible

## Slack outputs
Support:
- run complete message
- critical finding message
- release blocked alert
- daily digest future-ready
Messages must include:
- project
- branch
- result
- top findings
- deep link or open action

## Email outputs
Support:
- run complete summary
- critical findings
- release blocked
Provide concise HTML and plain-text versions.

## Manual export
Manual export must exist but is not the hero feature.
Support:
- Markdown report
- PDF report
- JSON run package

---

## Required UI Screens in Detail

## Screen 1: Project List
Must show:
- project name
- repo
- default branch
- last run status
- release readiness of last run
- integration badges
- runner mode
- quick actions: Run Release Check, Open, Settings

## Screen 2: Project Overview
Must show:
- repo/branch
- current config summary
- latest run card
- release readiness card
- unresolved findings count
- coverage summary
- connected integrations
- environment profiles
- quick run buttons

## Screen 3: Project Setup Wizard
Multi-step:
1. repo selection
2. target detection
3. scheme/build confirmation
4. runner selection
5. credentials mapping
6. environment profile
7. integrations
8. confirmation

## Screen 4: Run List
Table or list with filters:
- status
- branch
- trigger source
- runner
- release readiness
- date
- severity counts

## Screen 5: Run Detail
This is the most important screen.
Layout sections:
- header summary
- phase timeline
- release readiness
- key metrics
- video replay
- screenshots
- findings feed
- logs
- environment
- coverage graph
- comparison tab

## Screen 6: Finding Feed
Cross-project or per-project mode.
Must support:
- filter by severity/category/status/branch/date
- search
- bulk suppress/link/assign
- group by finding signature

## Screen 7: Finding Detail
Must show:
- evidence
- repro steps
- exact environment
- timestamps
- related runs
- linked issue state
- suggested remediation hints
- suppression rule creation

## Screen 8: Coverage View
Must visualize:
- screen graph
- explored branches
- dead ends
- loops
- unstable screens
- unvisited candidate nodes
This replaces the misleading “manual test tree” concept.

## Screen 9: Environment Profiles
Must manage:
- simulator target profiles
- env vars
- launch args
- credential sets
- reset hooks
- seed hooks

## Screen 10: Integrations
Tabbed:
- GitHub
- Jira
- Slack
- Email
- CI/CD
Each tab must show:
- connection status
- project mapping
- sync behavior
- test message or connection validation

## Screen 11: Runner Control
Must show:
- local runner health
- queued jobs
- active jobs
- simulator inventory
- Xcode versions
- disk usage for artifacts
- remote runners if enabled

## Screen 12: Settings
Must show:
- general
- notifications
- storage
- privacy
- analysis mode
- advanced
Do not expose raw model provider selection. Use user-friendly policies like:
- Fast
- Balanced
- Deep Analysis

---

## Data Model Specification

Implement explicit tables or equivalent persisted models for:

### Project
- id
- name
- repo_type
- repo_identifier
- local_repo_path
- default_branch
- workspace_path
- project_path
- scheme
- configuration
- bundle_id
- runner_mode
- created_at
- updated_at

### ProjectConfig
- project_id
- launch_args_json
- environment_json
- auth_mode
- deterministic_checks_json
- autonomous_config_json
- permissions_json
- retention_json
- integrations_json

### EnvironmentProfile
- id
- project_id
- name
- simulator_profile
- env_vars_json
- launch_args_json
- seed_strategy_type
- seed_strategy_payload
- reset_strategy_type
- reset_strategy_payload
- credentials_ref

### IntegrationConnection
- id
- type
- display_name
- account_identifier
- auth_metadata
- created_at
- updated_at

### ProjectIntegration
- id
- project_id
- integration_connection_id
- config_json
- enabled

### Run
- id
- project_id
- trigger_source
- trigger_metadata_json
- branch
- commit_sha
- pr_number
- status
- phase
- runner_id
- xcode_version
- simulator_profile
- resolved_runtime
- started_at
- ended_at
- summary_json
- confidence_score
- release_readiness

### RunPhaseEvent
- id
- run_id
- phase
- substep
- status
- timestamp
- payload_json

### ScreenSnapshot
- id
- run_id
- step_index
- timestamp
- screen_fingerprint
- screenshot_path
- accessibility_tree_json
- visible_elements_json
- screen_classification
- parent_screen_snapshot_id

### ActionEvent
- id
- run_id
- step_index
- source_snapshot_id
- action_type
- target_descriptor_json
- result
- timestamp
- duration_ms
- produced_snapshot_id

### Finding
- id
- project_id
- run_id
- signature_hash
- category
- subtype
- title
- summary
- severity
- confidence
- status
- first_seen_at
- last_seen_at
- evidence_json
- repro_steps_json
- metadata_json

### FindingLink
- id
- finding_id
- link_type
- external_id
- external_url
- state_json

### Artifact
- id
- run_id
- type
- path
- metadata_json
- created_at

### SuppressionRule
- id
- project_id
- rule_json
- created_at
- active

### Runner
- id
- mode
- display_name
- capabilities_json
- health_status
- last_seen_at

---

## Command Execution Requirements

All shell and tool execution must be wrapped in structured commands with:
- command string or argument array
- working directory
- env
- timeout
- stdout capture
- stderr capture
- exit code
- start/end timestamps

Do not run critical operations without structured logging.

### Required tool wrappers
- git
- xcodebuild
- xcrun simctl
- security / keychain operations where needed
- xcresult parser
- crash log collector

---

## Artifact Requirements

For every run collect as applicable:
- structured logs
- build logs
- simulator/device logs
- screenshots (already captured per-action as XCTest attachments in xcresult)
- replay video (see Visual Media Acquisition below)
- accessibility snapshots (available via testDumpUITree)
- xcresult reference (already returned by ExplorationService)
- crash logs
- run summary JSON
- compare summary JSON

### Video requirement
The exploration harness captures per-action screenshots as XCTest attachments inside the `.xcresult` bundle. These are extractable via `xcrun xcresulttool export attachments`. This is the primary evidence mechanism today.

For full motion video or on-demand screenshot acquisition of specific screens, use the **Visual Media Acquisition** system described below.

---

## Visual Media Acquisition (ewag-capture.sh Integration)

### Purpose and Architecture

The project has a proven visual capture pipeline at `~/.openclaw/scripts/ewag-capture.sh` that handles screenshot and video recording via a Mac-hosted iOS agent. This system is the **chosen approach** for acquiring real rendered media when the automation needs it — not for routine per-action screenshots (those come from XCTest attachments) but for **targeted, high-fidelity captures** in specific situations:

1. **When the explorer gets stuck on ambiguous UI**: If the engine hits a navigation loop or dead-end and cannot determine what the screen actually looks like, it can request a real screenshot for diagnosis or human review.
2. **When visual regression detection needs a clean baseline**: Screenshot diffs require pixel-accurate captures at consistent states, not mid-transition XCTest snapshots.
3. **When aesthetic or layout feedback is needed**: For findings classified as `layout_overlap`, `text_clipping`, `blank_screen`, or `visual_regression`, attaching a real rendered screenshot or short video is more valuable than accessibility metadata alone.
4. **For run-level summary recordings**: A full-run screen recording (start before exploration, stop after) gives the user a video replay of exactly what happened.

### How ewag-capture.sh Works

The script orchestrates captures via SSH to the Mac runner:

- **Screenshot mode**: Runs an XCUITest case via `ios-agent test`, extracts PNG from the xcresult bundle via `xcresulttool export attachments`, copies to local storage, optionally uploads to Google Drive.
- **Record mode**: Runs `ios-agent record-test`, captures MP4, converts to WebM via ffmpeg, uploads.
- **Scroll mode**: Runs a scroll-through test case, records the scrolling, trims the lead-in, converts to WebM.

Key infrastructure facts:
- Mac runner: `taylorolsen-vogt@100.125.133.123` (Tailscale)
- ios-agent binary: `/Users/taylorolsen-vogt/ios-agent/ios-agent`
- Artifacts dir: `/Users/taylorolsen-vogt/ios-agent/artifacts/`
- Google Drive upload via `gog drive upload` (OAuth configured)
- ffmpeg on Linux host for MP4→WebM conversion

### Integration Path for OpenClawQA

The ExplorationService should be extended to support on-demand media acquisition:

1. **Run-level video**: Before calling `testAutonomousExploration`, optionally start `xcrun simctl io <UDID> recordVideo /tmp/ocqa-run-<runId>.mov`. After exploration completes, stop recording. Convert and store as run artifact. This is the simplest approach for full-run video.

2. **On-demand screenshot**: When the explorer detects a stuck state, dead-end, or visual finding, invoke `testScreenshot` (already implemented in ExplorerTests.swift) to capture a clean frame, or call `xcrun simctl io <UDID> screenshot` directly.

3. **Post-run screenshot extraction**: The xcresult bundle already contains per-action screenshots. ExplorationService.swift has `extractScreenshots(from:to:runId:snapshots:)` which calls `xcresulttool export attachments`. This is implemented but needs wiring to the artifact viewer in RunDetailView.

4. **Google Drive upload for shared artifacts**: For CI/CD or remote review scenarios, reuse ewag-capture.sh's Drive upload function (`gog drive upload`) to push findings screenshots to a shared folder.

### Important Design Constraint

Do NOT capture screenshots for every action via simctl or ios-agent during exploration. The per-action XCTest attachments in the xcresult bundle already serve this purpose and are collected at zero additional latency. External capture (simctl/ios-agent) should be reserved for:
- Run-level video (one start/stop per run)
- Targeted captures at finding points
- Baseline captures for visual regression
- Human-review escalation

---

## Error Handling Requirements

The product must distinguish clearly between:
- platform/setup errors
- build errors
- launch errors
- app failures
- autonomous engine uncertainty
- integration failures

Each error shown to user must include:
- what failed
- where it failed
- what data was captured
- next likely remediation step

Do not collapse everything into generic “Run failed”.

---

## Performance and Scalability Requirements

For local mode, optimize for responsiveness and clarity over large-scale throughput.

### Desktop UI requirements
- run lists and finding feeds must remain responsive with thousands of rows
- artifact loading must be lazy
- video/screenshots must not freeze the app
- logs must stream incrementally

### Remote architecture requirements
Design queue and runner abstractions so future concurrency is possible, but do not prematurely overengineer distributed systems beyond clean interfaces.

---

## Security and Privacy Requirements

- Use macOS Keychain for secrets. (`KeychainService.swift` exists but is not yet wired to UI.)
- Do not log secrets.
- Redact known secret values in logs and exported reports.
- Allow users to disable screenshot/video capture for sensitive screens in future design, but do not block v1 on it.
- Mark artifacts as local-only by default unless explicitly exported/shared.

---

## Mac Runner Environment

### Current Setup
- **Mac host**: `taylorolsen-vogt@100.125.133.123` (Tailscale IP)
- **Xcode**: 16.x on macOS 14.5
- **Simulators available**: iPhone 16 Pro (`CBF1BFB1`), iPhone 16 Pro Max (`13BE13C7`, iOS 18.3.1)
- **Git**: Can pull from GitHub, cannot push (no credential in osxkeychain). All pushes happen from the Linux build server.
- **ios-agent**: `/Users/taylorolsen-vogt/ios-agent/ios-agent` — a separate binary for test execution and recording (used by ewag-capture.sh)
- **App under test**: ResiLife (`com.elitepro.resilife`) at `~/repos/iosApp`
- **Harness derived data**: `/tmp/ocqa-harness-dd` (used during development testing) and `~/Library/Application Support/OpenClawQA/HarnessDerivedData` (production path)

### Running Tests from Linux (Current Development Workflow)

```bash
# Write config and run exploration
ssh taylorolsen-vogt@100.125.133.123 \
  "echo '{\"OCQA_BUNDLE_ID\":\"com.elitepro.resilife\",\"OCQA_MAX_ACTIONS\":\"25\",\"OCQA_TIMEOUT_SECONDS\":\"300\"}' > /tmp/ocqa-run-config.json && \
   xcodebuild test-without-building \
     -project ~/repos/OpenClawQA/Harness/OCQAHarness.xcodeproj \
     -scheme OCQAHarnessUITests \
     -destination 'platform=iOS Simulator,id=13BE13C7-7498-49DA-84BA-5F96A55A8AC7' \
     -only-testing:OCQAHarnessUITests/ExplorerTests/testAutonomousExploration \
     -derivedDataPath /tmp/ocqa-harness-dd 2>&1 > /tmp/ocqa-test-output.txt"

# Check results
ssh taylorolsen-vogt@100.125.133.123 "grep OCQA_ /tmp/ocqa-test-output.txt"
```

### When Running Locally on the Mac (Target State)

When the agent runs on the Mac directly, the SSH layer disappears. ExplorationService.swift already handles direct local execution via Process/Pipe. The orchestrator just needs to be invoked from the desktop app UI.

---

## Open Tasks for Next Agent

> Priority order. Items marked BLOCKED require human action first.

### 1. Wire Run-Level Video Recording
- Before `testAutonomousExploration`, start `xcrun simctl io <UDID> recordVideo /path/to/video.mov`
- After exploration, stop recording (kill the simctl process)
- Convert .mov to .mp4 or .webm
- Store as run artifact, wire to RunDetailView video player
- **Not blocked — can be implemented now**

### 2. Visual Regression Baseline System
- Store per-screen-hash baseline screenshots in SQLite (or filesystem with DB index)
- On subsequent runs, compare screenshots of matching screen hashes
- Use pixel diff or perceptual hash for change detection
- Flag regressions as findings with before/after evidence
- **Not blocked — screenshots already in xcresult**

### 3. Extract and Display Per-Action Screenshots
- ExplorationService.swift has `extractScreenshots(from:to:runId:snapshots:)` — verify it works
- Wire extracted screenshots to RunDetailView's screenshot timeline
- Each screenshot should link to its step number and screen state
- **Not blocked**

### 4. Make OrchestratorService Configurable
- Replace hardcoded `simulatorName = "iPhone 16 Pro"` with project config value
- Replace hardcoded `maxActions: 200`, `timeoutSeconds: 1800` with project-level settings
- Add simulator selection to ProjectSetupWizard
- **Not blocked**

### 5. Wire Keychain to Settings UI
- SettingsView has Test Credentials section with edit buttons — currently no-ops
- Wire to KeychainService.swift read/write
- Store secret references (not values) in project config
- **Not blocked**

### 6. Wire Notification Persistence
- Settings toggles for notifications use `.constant()` bindings
- Persist to UserDefaults or SQLite settings table
- **Not blocked**

### 7. (BLOCKED) Test Credentials for ResiLife
- The explorer types generic placeholder text into login fields
- If ResiLife requires real auth, Aaron needs to create test account credentials
- Consider: does the app have a demo mode? The current test data shows "Emma K" profile suggesting a seeded demo account exists

### 8. (BLOCKED) Integration OAuth Setup
- GitHub, Jira, Slack cards are UI stubs
- Aaron needs to decide which integrations are priority and create OAuth apps/API tokens
- The UI scaffolding is ready to receive wiring

### 9. (BLOCKED) GitHub Credentials on Mac
- Mac cannot push to GitHub — no stored credential
- Either add a PAT to Mac's osxkeychain, or continue pushing from Linux only
- Aaron's decision

---

## Coding Instructions for the Agent

### What is already built (do not rebuild)
The following are complete and working. Do not rewrite from scratch:

1. ✅ macOS app shell with navigation and project storage
2. ✅ local database schema (11 SQLite3 tables) and CRUD
3. ✅ project setup wizard with repo/target detection
4. ✅ local runner service (xcodebuild, simctl)
5. ✅ structured command execution layer
6. ✅ xcodebuild + simctl orchestration
7. ✅ run model + phase event streaming into UI
8. ✅ deterministic checks (launch check)
9. ✅ screenshot collection + artifact model
10. ✅ run detail screen
11. ✅ finding model + finding creation from exploration
12. ✅ accessibility snapshot extraction (testDumpUITree)
13. ✅ autonomous exploration engine (fully generalized, snapshot-optimized)
14. ✅ findings classification (crash, dead_end, navigation_loop, build_failure)
15. ✅ coverage visualization (CoverageView with real transition data)
16. ✅ release confidence model (score + readiness level)

### Implementation order for remaining work
Build in this order unless blocked:

1. **Wire run-level video recording** — simctl recordVideo start/stop around exploration
2. **Extract per-action screenshots from xcresult** — verify and wire to RunDetailView timeline
3. **Visual regression baseline system** — store baseline per screen hash, pixel diff on rerun
4. **Make OrchestratorService configurable** — simulator name, maxActions, timeout from project config
5. **Wire KeychainService to Settings UI** — test credentials edit buttons
6. **Persist notification settings** — replace `.constant()` bindings
7. **GitHub integration** — OAuth flow, PR comments, check-run status
8. **Slack integration** — webhook, run summaries, critical finding alerts
9. **Jira integration** — issue creation from findings
10. **Email integration** — SMTP/transactional for run summaries
11. **CI/CD trigger ingestion** — GitHub Actions, Xcode Cloud
12. **Comparison view** — run A vs run B diff
13. **Remote runner abstractions** — formalize the SSH-based workflow into proper runner protocol

### UI priorities
The first polished screens must be:
- Project Setup Wizard
- Project Overview
- Run Detail
- Finding Detail
- Coverage View

Do not spend early cycles polishing generic settings or team management.

### Naming guidance
Prefer product vocabulary:
- Run Release Check
- Autonomous Sweep
- Findings
- Coverage
- Release Readiness
Avoid:
- Test Explorer
- Suite Manager
- Case Library
unless added much later for advanced deterministic checks.

---

## Explicit Rejection of Misleading UI Concepts

Do not build the product as a traditional manual QA management system.

### Specifically avoid making these primary
- tree of hand-authored test cases as core navigation
- raw model picker in settings
- export center as a hero workflow
- simulator inventory as the main user value
- generic “AI settings” page with prompt knobs

If any of these are implemented, they must be secondary or advanced.

---

## Future Extensions To Design For Now

These are not required for initial completeness but the codebase must not preclude them:
- browser dashboard companion
- remote managed runner fleet
- real-device execution
- backend reset/seed marketplace
- schedule-based nightly runs
- flake detection across reruns
- performance profiling
- accessibility scoring
- Android support
- richer CI annotations
- LLM-assisted remediation suggestions
- organization/team multi-user sync backend

---

## Definition of Done For Product Vision

The product is directionally correct when a user can:

1. Install the macOS app.
2. Connect an iOS repo.
3. Configure build target, credentials, and environment.
4. Connect GitHub and Slack at minimum.
5. Click **Run Release Check**.
6. Watch structured progress in the macOS app.
7. Open a completed run and inspect:
   - replay video or screenshot timeline
   - findings
   - repro steps
   - logs
   - coverage graph
   - release readiness
8. Push a top finding to Jira or GitHub workflow.
9. Compare this run to a previous baseline.
10. Trust that the product is built around autonomous mobile QA rather than generic scripted testing.

This is the product to build.
