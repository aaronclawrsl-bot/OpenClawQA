# IOS_TESTING_PRODUCT_DESIGN.md

## Purpose

This document is the authoritative technical product design and implementation specification for a macOS desktop application that delivers autonomous QA for iOS applications. It is written for a coding agent and must be treated as build instructions, not marketing copy. Implement exactly what is specified unless explicitly marked optional or future.

The product name used internally in this document is **OpenClaw QA**, but the codebase should avoid hard-coding branding where not necessary.

This product is a **macOS desktop QA control plane** for iOS apps. It connects to source repositories and selected external systems, builds customer apps, runs autonomous validation on iOS simulators and optionally real devices, captures artifacts, classifies failures, and pushes findings back into engineering workflows.

The initial product is **macOS desktop first**, not browser first.

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
Use **Swift + SwiftUI** for the desktop application.

### Local database
Use **SQLite** via a robust Swift persistence layer. Do not use Core Data unless absolutely necessary. Prefer explicit schema control.

### Orchestration service
Acceptable implementations:
- Swift executable
- Rust service with Swift bridge
- local HTTP/gRPC service
The simplest strong choice is **Swift for app + Swift local service** for early coherence.

### iOS app execution
Use:
- `xcodebuild`
- `simctl`
- XCTest / XCUITest
- parsing of `.xcresult`
- unified log collection where useful

### Avoid
- Making the core product Electron.
- Building the autonomous engine around brittle coordinate-only clicking.
- Requiring users to expose API model keys in the standard flow.

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

This is the moat. Build this carefully.

## Core objectives
- Explore arbitrary app surfaces without requiring exhaustive manual test scripts.
- Use stable identifiers when available.
- Use heuristics when identifiers are absent.
- Avoid infinite loops and repeated low-value interaction.
- Capture enough evidence to reproduce what happened.
- Prefer meaningful user-like flows over random tapping.

## Inputs
- accessibility tree
- currently visible UI elements
- app state history
- previous actions
- screenshots
- deterministic check definitions
- project auth configuration
- permission policy
- screen graph built during run

## Internal state model
For each step, track:
- visible elements
- candidate actions
- action scores
- current screen fingerprint
- previous screen fingerprint
- current path
- visited path signatures
- navigation stack estimate
- blockers
- expected vs observed result
- confidence in screen classification

### Screen fingerprint
A screen fingerprint should be built from:
- top-level accessibility labels/types
- navigation title
- tab state
- visible button labels
- collection/list structure hints
- stable screenshot hash
Use a fuzzy fingerprint plus exact signature.

## Action types
- tap element
- type into field
- submit form
- scroll vertically
- scroll horizontally
- swipe page
- dismiss modal
- go back
- handle system permission alert
- relaunch after crash if policy allows
- wait for transition
- no-op snapshot for comparison

## Required prioritization heuristic
Prioritize actions in this order when appropriate:
1. Deterministic check next step
2. Authentication completion
3. Permission handling
4. Primary CTA on new screen
5. Previously unseen navigation action
6. Tab switch to unexplored area
7. Detail drill-down into list item not yet seen
8. Back-navigation to branch to alternative path
9. Low-value repeated scrolls last

## Loop prevention
The engine must detect:
- repeated screen-action-screen cycles
- repeated screen fingerprints with no net change
- repeated failed interactions
- repeated modals or auth bounce loops

On loop detection:
- back out if possible
- mark dead-end if trapped
- lower future score for same action
- optionally relaunch from home state if configured

## Required exploration outputs
- screen graph
- action graph
- path list
- unexplored candidate list
- dead ends
- unstable transitions
- state traps

---

## Deterministic Checks

The product must support lightweight deterministic checks, but they are not the hero feature.

### Purpose
- validate critical flows reliably
- produce clean pass/fail outcomes
- provide structure before autonomous exploration

### Supported initial check types
- launch app
- login
- tab navigation
- open profile
- open settings
- logout
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

This product must heavily leverage accessibility metadata, but cannot assume perfect app instrumentation.

### Required best-case support
If app exposes accessibility identifiers and labels well, use them as first-class selectors.

### Required fallback support
If identifiers are missing:
- use accessibility labels/types
- use relative element position within stable containers
- use screen classification + element text
- reduce confidence appropriately

### Product UX requirement
The app should surface accessibility quality issues as developer-facing recommendations:
- missing identifiers on key actions
- ambiguous labels
- unstable duplicate controls
This is valuable and should be a separate recommendation type, not necessarily a failure.

---

## Build and Runner Requirements

## Local runner
Must support:
- repo checkout or local path
- isolated derived data location
- dependency bootstrap
- xcodebuild build
- simulator lifecycle
- app install/uninstall
- test execution
- artifact collection

## Remote runner
Design interfaces for:
- registered runner identity
- labels (xcode version, simulator availability, hardware profile)
- heartbeats
- job leasing
- secure secret access
- artifact upload
- run logs stream

## Xcode support
The product must handle multiple Xcode versions. Runner should report installed versions and chosen version per run.

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

Visual regression is a required major feature.

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
- screenshot diffing
- structural metadata from accessibility tree
- screen fingerprint matching
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

Every completed run must produce a release confidence result.

### Required output fields
- release_readiness: `ready`, `caution`, `blocked`
- confidence_score: 0–100
- summary_reason
- contributing_factors array

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
- screenshots
- replay video
- accessibility snapshots
- xcresult reference
- crash logs
- run summary JSON
- compare summary JSON

### Video requirement
If full-screen video recording is difficult in v1, ensure at minimum:
- timestamped screenshot timeline
- optional simulator screen recording when feasible
Design interface as if video exists; degrade gracefully with screenshot replay.

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

- Use macOS Keychain for secrets.
- Do not log secrets.
- Redact known secret values in logs and exported reports.
- Allow users to disable screenshot/video capture for sensitive screens in future design, but do not block v1 on it.
- Mark artifacts as local-only by default unless explicitly exported/shared.

---

## Coding Instructions for the Agent

### Implementation order
Build in this exact order unless blocked:

1. macOS app shell with navigation and project storage
2. local database schema and repositories
3. project setup wizard with repo/target detection
4. local runner service
5. structured command execution layer
6. xcodebuild + simctl orchestration
7. run model + phase event streaming into UI
8. deterministic checks execution
9. screenshot collection + artifact model
10. run detail screen
11. finding model + manual insertion from deterministic failures
12. accessibility snapshot extraction
13. autonomous exploration engine v1
14. findings classification engine
15. coverage visualization
16. GitHub integration
17. Slack integration
18. Jira integration
19. email integration
20. CI/CD trigger ingestion
21. comparison view
22. release confidence model
23. remote runner abstractions

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
