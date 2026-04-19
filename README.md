# OpenClaw QA — macOS Desktop App

Native macOS desktop application for autonomous iOS QA testing powered by OpenClaw.

## Architecture

- **UI**: SwiftUI (macOS 14+), dark theme
- **Database**: SQLite3 (native C API, no dependencies)
- **Secrets**: macOS Keychain via Security framework
- **Engine**: Bridges to existing Node.js orchestration engine at `~/repos/openclaw-qa/engine/`
- **Runners**: Local (xcodebuild + simctl) and remote (SSH) execution

## Screens

| Screen | Description |
|--------|-------------|
| Overview | Dashboard with release confidence, findings summary, trends |
| Runs | Run history with filtering and status tracking |
| Run Detail | Deep dive into a run with findings, timeline, logs, artifacts |
| Findings | All findings with severity filtering and AI analysis |
| Coverage | Flow map visualization and screen coverage grid |
| Insights | Trends, issue categories, and activity feed |
| Integrations | GitHub, Jira, Slack, Email, Jenkins connections |
| Settings | Project config, environments, AI tuning, notifications |

## Build

```bash
# Generate Xcode project (run on Mac)
ruby generate-xcodeproj.rb

# Build
xcodebuild -project OpenClawQA.xcodeproj -scheme OpenClawQA -configuration Debug

# Or deploy from Linux and build on Mac
bash scripts/deploy-and-build.sh
```

## Development Workflow

Code is edited on Linux (Jerry), deployed to Taylor's Mac via SCP/rsync, and built with xcodebuild remotely. This follows the EWAG dev/build infrastructure pattern.

## Project Structure

```
OpenClawQA/
├── App/                    # App entry point, main content view
├── Theme/                  # Colors, typography, spacing
├── Models/                 # Data models (Project, Run, Finding, etc.)
├── Database/               # SQLite manager with schema + demo data
├── ViewModels/             # Observable app state
├── Views/
│   ├── Sidebar/            # Navigation sidebar
│   ├── Overview/           # Dashboard
│   ├── Runs/               # Run list
│   ├── RunDetail/          # Run detail with findings
│   ├── Findings/           # Findings browser
│   ├── Coverage/           # Flow map + coverage grid
│   ├── Insights/           # Trends dashboard
│   ├── Integrations/       # Integration cards
│   ├── Settings/           # Settings panels
│   ├── Components/         # Reusable UI components
│   └── ProjectSetup/       # New project wizard
├── Services/               # Runner, Orchestrator, Keychain services
└── Resources/              # Info.plist, Assets.xcassets
```

## Requirements

- macOS 14.0+
- Xcode 16.2+
- Ruby (for project generation)
