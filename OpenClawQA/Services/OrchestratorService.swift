import Foundation

// MARK: - Orchestrator Service
// Coordinates the full QA run pipeline:
// checkout → build → boot → install → deterministic checks → exploration → analysis → report
final class OrchestratorService {
    static let shared = OrchestratorService()

    private let runner = RunnerService.shared
    private let db = DatabaseManager.shared
    private let explorer = ExplorationService.shared

    // MARK: - Run Configuration
    struct RunConfiguration {
        var simulatorName: String = "iPhone 16 Pro"
        var maxActions: Int = 25
        var timeoutSeconds: Int = 300
        var resolvedRuntime: String = "iOS 26.4"
        /// Launch arguments forwarded to the target app (e.g. ["--uitesting"])
        var appLaunchArgs: [String] = []
        /// Environment variables forwarded to the target app (e.g. ["UI_TEST_ROLE": "resident"])
        var appLaunchEnv: [String: String] = [:]

        static func from(project: QAProject) -> RunConfiguration {
            var config = RunConfiguration()
            // ResiLife: bypass auth with the same flags the EWAG test suite uses
            if project.bundleId == "com.elitepro.resilife" {
                config.appLaunchArgs = ["--uitesting"]
                config.appLaunchEnv = ["UI_TEST_ROLE": "resident"]
            }
            return config
        }
    }

    enum RunError: Error, LocalizedError {
        case buildFailed(String)
        case simulatorFailed(String)
        case installFailed(String)
        case launchFailed(String)
        case cancelled
        case noProject

        var errorDescription: String? {
            switch self {
            case .buildFailed(let msg): return "Build failed: \(msg)"
            case .simulatorFailed(let msg): return "Simulator failed: \(msg)"
            case .installFailed(let msg): return "Install failed: \(msg)"
            case .launchFailed(let msg): return "Launch failed: \(msg)"
            case .cancelled: return "Run was cancelled"
            case .noProject: return "No project configured"
            }
        }
    }

    struct RunResult {
        var status: RunStatus
        var phase: RunPhase
        var releaseReadiness: ReleaseReadiness
        var confidenceScore: Int
        var criticalFindings: Int
        var highFindings: Int
        var mediumFindings: Int
        var lowFindings: Int
        var testsExecuted: Int
        var flowsExplored: Int
        var coveragePercent: Double
        var xcodeVersion: String
        var simulatorProfile: String
        var resolvedRuntime: String
        var commitSha: String?
        var branch: String
        var buildLog: String
        var findings: [QAFinding]
        var artifacts: [QAArtifact]
        var phaseEvents: [RunPhaseEvent]
        var snapshots: [ScreenSnapshot]
        var actionEvents: [ActionEvent]
        var coverageNodes: [CoverageNode]
        var screensVisited: [String]
    }

    // Execute a full release check against a real project
    func executeReleaseCheck(
        project: QAProject,
        runId: String,
        configuration: RunConfiguration? = nil,
        onPhaseChange: @escaping (RunPhase, String) -> Void
    ) async throws -> RunResult {
        let config = configuration ?? RunConfiguration.from(project: project)
        let startTime = Date()
        var phaseEvents: [RunPhaseEvent] = []
        var findings: [QAFinding] = []
        var artifacts: [QAArtifact] = []

        func recordPhase(_ phase: RunPhase, substep: String, status: String = "started") {
            let event = RunPhaseEvent(
                id: UUID().uuidString, runId: runId,
                phase: phase.rawValue, substep: substep,
                status: status, timestamp: Date()
            )
            phaseEvents.append(event)
            db.insertRunPhaseEvent(event)
        }

        guard let repoPath = project.localRepoPath else {
            throw RunError.noProject
        }

        // ===== 1. PREPARING =====
        onPhaseChange(.preparing, "Resolving project configuration...")
        recordPhase(.preparing, substep: "Resolving configuration")

        let gitBranch = await runner.runShellCommand("git", arguments: ["-C", repoPath, "branch", "--show-current"]) ?? "unknown"
        let gitCommit = await runner.runShellCommand("git", arguments: ["-C", repoPath, "rev-parse", "--short", "HEAD"]) ?? "unknown"
        let branch = gitBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        let commitSha = gitCommit.trimmingCharacters(in: .whitespacesAndNewlines)

        let xcodeVersionRaw = await runner.runShellCommand("xcodebuild", arguments: ["-version"]) ?? "Unknown"
        let xcodeVersion = xcodeVersionRaw.components(separatedBy: "\n").first?.replacingOccurrences(of: "Xcode ", with: "") ?? "Unknown"

        let simulatorName = config.simulatorName
        let simulatorUDID = await runner.findSimulatorUDID(name: simulatorName)
        let resolvedRuntime = config.resolvedRuntime
        let simulatorProfile = "\(simulatorName) (\(resolvedRuntime))"

        recordPhase(.preparing, substep: "Configuration resolved", status: "completed")

        // ===== 2. BUILDING =====
        onPhaseChange(.building, "Building \(project.scheme)...")
        recordPhase(.building, substep: "xcodebuild build-for-testing")
        let buildStartTime = Date()

        let derivedDataPath = "/tmp/openclaw-qa-derived/\(runId)"
        let buildResult: (success: Bool, log: String)

        if let projectPath = project.projectPath, !projectPath.isEmpty {
            buildResult = await runner.buildProject(
                projectOrWorkspace: .project(projectPath),
                scheme: project.scheme,
                simulator: simulatorName,
                derivedDataPath: derivedDataPath
            )
        } else if let workspacePath = project.workspacePath, !workspacePath.isEmpty {
            buildResult = await runner.buildProject(
                projectOrWorkspace: .workspace(workspacePath),
                scheme: project.scheme,
                simulator: simulatorName,
                derivedDataPath: derivedDataPath
            )
        } else {
            throw RunError.buildFailed("No project or workspace path configured")
        }

        let buildDuration = Date().timeIntervalSince(buildStartTime)

        let logDir = NSHomeDirectory() + "/Library/Application Support/OpenClawQA/artifacts/\(runId)"
        try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)
        let buildLogPath = logDir + "/build.log"
        try? buildResult.log.write(toFile: buildLogPath, atomically: true, encoding: .utf8)
        artifacts.append(QAArtifact(
            id: UUID().uuidString, runId: runId, type: "build_log",
            path: buildLogPath,
            metadata: "{\"size_bytes\": \(buildResult.log.utf8.count), \"duration_s\": \(Int(buildDuration))}",
            createdAt: Date()
        ))

        if !buildResult.success {
            recordPhase(.building, substep: "Build failed", status: "failed")
            let buildFindings = parseBuildErrors(log: buildResult.log, projectId: project.id, runId: runId)
            findings.append(contentsOf: buildFindings)

            return RunResult(
                status: .failed, phase: .building,
                releaseReadiness: .blocked, confidenceScore: 0,
                criticalFindings: buildFindings.filter { $0.severity == .critical }.count,
                highFindings: buildFindings.filter { $0.severity == .high }.count,
                mediumFindings: buildFindings.filter { $0.severity == .medium }.count,
                lowFindings: buildFindings.filter { $0.severity == .low }.count,
                testsExecuted: 0, flowsExplored: 0, coveragePercent: 0,
                xcodeVersion: xcodeVersion, simulatorProfile: simulatorProfile,
                resolvedRuntime: resolvedRuntime,
                commitSha: commitSha, branch: branch,
                buildLog: buildResult.log, findings: findings, artifacts: artifacts,
                phaseEvents: phaseEvents,
                snapshots: [], actionEvents: [], coverageNodes: [], screensVisited: []
            )
        }

        recordPhase(.building, substep: "Build succeeded", status: "completed")
        let warningFindings = parseBuildWarnings(log: buildResult.log, projectId: project.id, runId: runId)
        findings.append(contentsOf: warningFindings)

        // ===== 3. BOOTING SIMULATOR =====
        onPhaseChange(.booting, "Booting \(simulatorProfile)...")
        recordPhase(.booting, substep: "Booting \(simulatorName)")

        if let udid = simulatorUDID {
            _ = await runner.runShellCommand("xcrun", arguments: ["simctl", "shutdown", udid])
            try? await Task.sleep(nanoseconds: 500_000_000)

            let bootResult = await runner.bootSimulator(udid: udid)
            if !bootResult {
                let statusCheck = await runner.runShellCommand("xcrun", arguments: ["simctl", "list", "devices", udid])
                if statusCheck?.contains("Booted") != true {
                    throw RunError.simulatorFailed("Could not boot simulator \(simulatorName)")
                }
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        } else {
            throw RunError.simulatorFailed("Simulator '\(simulatorName)' not found")
        }

        recordPhase(.booting, substep: "Simulator booted", status: "completed")

        // ===== 4. INSTALLING APP =====
        onPhaseChange(.installing, "Installing \(project.bundleId) on simulator...")
        recordPhase(.installing, substep: "Installing app")

        let appPath = await findBuiltApp(derivedDataPath: derivedDataPath, scheme: project.scheme)
        if let appPath = appPath, let udid = simulatorUDID {
            let installResult = await runner.runShellCommand("xcrun", arguments: ["simctl", "install", udid, appPath])
            if installResult == nil {
                findings.append(QAFinding(
                    id: UUID().uuidString, projectId: project.id, runId: runId,
                    signatureHash: "install-failure", category: .launchFailure,
                    title: "App installation failed",
                    summary: "Could not install \(project.bundleId) on \(simulatorName)",
                    severity: .critical, confidence: 1.0, status: .open,
                    firstSeenAt: Date(), lastSeenAt: Date(),
                    environment: simulatorProfile, occurrences: 1
                ))
            }
        }

        recordPhase(.installing, substep: "App installed", status: "completed")

        // ===== 5. LAUNCH TEST =====
        onPhaseChange(.deterministicChecks, "Running launch check...")
        recordPhase(.deterministicChecks, substep: "Launch test")

        if let udid = simulatorUDID {
            _ = await runner.runShellCommand("xcrun", arguments: [
                "simctl", "launch", udid, project.bundleId
            ])
            try? await Task.sleep(nanoseconds: 3_000_000_000)

            let screenshotPath = logDir + "/launch_screenshot.png"
            _ = await runner.runShellCommand("xcrun", arguments: [
                "simctl", "io", udid, "screenshot", screenshotPath
            ])
            if FileManager.default.fileExists(atPath: screenshotPath) {
                artifacts.append(QAArtifact(
                    id: UUID().uuidString, runId: runId, type: "screenshot",
                    path: screenshotPath,
                    metadata: "{\"step\": \"launch\", \"screen\": \"Launch\"}",
                    createdAt: Date()
                ))
            }

            _ = await runner.runShellCommand("xcrun", arguments: ["simctl", "terminate", udid, project.bundleId])
        }

        recordPhase(.deterministicChecks, substep: "Launch check completed", status: "completed")

        // ===== 6. RUN TESTS + AUTONOMOUS EXPLORATION =====
        onPhaseChange(.exploring, "Running deterministic tests...")
        recordPhase(.exploring, substep: "Running xcodebuild test")

        var testsPassed = 0
        var testsFailed = 0
        var explorationSnapshots: [ScreenSnapshot] = []
        var explorationActions: [ActionEvent] = []
        var explorationCoverageNodes: [CoverageNode] = []
        var screensVisited: [String] = []

        // Skip xcodebuild test for the target project — the autonomous exploration
        // handles all test coverage. Project-native tests can be added later via
        // deterministic checks configuration.

        recordPhase(.exploring, substep: "Deterministic tests skipped (exploration-first mode)", status: "completed")

        // ===== 6b. AUTONOMOUS EXPLORATION =====
        onPhaseChange(.exploring, "Building exploration harness...")
        recordPhase(.exploring, substep: "Building exploration harness")

        let harnessBuild = await explorer.ensureHarnessBuilt(simulator: simulatorName)
        if harnessBuild.success {
            recordPhase(.exploring, substep: "Harness built", status: "completed")

            // Start video recording before exploration
            var videoProcess: Process?
            let videoPath = logDir + "/exploration-video.mov"
            if let udid = simulatorUDID {
                videoProcess = runner.startVideoRecording(udid: udid, outputPath: videoPath)
                if videoProcess != nil {
                    recordPhase(.exploring, substep: "Video recording started", status: "completed")
                    // Allow recording to initialize
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }

            onPhaseChange(.exploring, "Exploring app autonomously...")
            recordPhase(.exploring, substep: "Autonomous exploration started")

            let explorationResult = await explorer.runExploration(
                bundleId: project.bundleId,
                simulator: simulatorName,
                simulatorUDID: simulatorUDID,
                maxActions: config.maxActions,
                timeoutSeconds: config.timeoutSeconds,
                projectId: project.id,
                runId: runId,
                artifactDir: logDir,
                appLaunchArgs: config.appLaunchArgs,
                appLaunchEnv: config.appLaunchEnv,
                onProgress: { [weak self] progress in
                    Task { @MainActor in
                        onPhaseChange(.exploring,
                            "Exploring: \(progress.action)/\(progress.maxActions) actions, \(progress.statesDiscovered) screens — \(progress.currentScreen)")
                    }
                }
            )

            findings.append(contentsOf: explorationResult.findings)
            explorationSnapshots = explorationResult.snapshots
            explorationActions = explorationResult.actionEvents
            explorationCoverageNodes = explorationResult.coverageNodes
            screensVisited = explorationResult.screensVisited

            // Stop video recording
            if let vp = videoProcess {
                runner.stopVideoRecording(vp)
                // Allow file to finalize
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if FileManager.default.fileExists(atPath: videoPath) {
                    let videoAttrs = try? FileManager.default.attributesOfItem(atPath: videoPath)
                    let videoSize = (videoAttrs?[.size] as? Int64) ?? 0
                    artifacts.append(QAArtifact(
                        id: UUID().uuidString, runId: runId, type: "video",
                        path: videoPath,
                        metadata: "{\"source\": \"exploration\", \"size_bytes\": \(videoSize)}",
                        createdAt: Date()
                    ))
                    recordPhase(.exploring, substep: "Video recording saved", status: "completed")
                }
            }

            // Save exploration log as artifact
            let explorationLogPath = logDir + "/exploration.log"
            if FileManager.default.fileExists(atPath: explorationLogPath) {
                artifacts.append(QAArtifact(
                    id: UUID().uuidString, runId: runId, type: "exploration_log",
                    path: explorationLogPath,
                    metadata: "{\"actions\": \(explorationResult.actionsPerformed), \"states\": \(explorationResult.statesDiscovered), \"issues\": \(explorationResult.findings.count)}",
                    createdAt: Date()
                ))
            }

            // Save xcresult as artifact
            if let xcresultPath = explorationResult.xcresultPath {
                artifacts.append(QAArtifact(
                    id: UUID().uuidString, runId: runId, type: "xcresult",
                    path: xcresultPath,
                    metadata: "{\"source\": \"exploration\"}",
                    createdAt: Date()
                ))
            }

            recordPhase(.exploring, substep: "Exploration complete: \(explorationResult.actionsPerformed) actions, \(explorationResult.statesDiscovered) screens, \(explorationResult.findings.count) issues", status: "completed")
        } else {
            recordPhase(.exploring, substep: "Harness build failed — skipping exploration", status: "failed")
            let harnessLogPath = logDir + "/harness-build.log"
            try? harnessBuild.log.write(toFile: harnessLogPath, atomically: true, encoding: .utf8)
        }

        // ===== 7. ANALYZING =====
        onPhaseChange(.analyzing, "Classifying findings...")
        recordPhase(.analyzing, substep: "Classifying findings")

        if let udid = simulatorUDID {
            let deviceLogPath = logDir + "/device.log"
            let logResult = await runner.runShellCommand("xcrun", arguments: [
                "simctl", "spawn", udid, "log", "show",
                "--predicate", "subsystem == '\(project.bundleId)'",
                "--style", "compact", "--last", "5m"
            ])
            if let logResult = logResult {
                try? logResult.write(toFile: deviceLogPath, atomically: true, encoding: .utf8)
                artifacts.append(QAArtifact(
                    id: UUID().uuidString, runId: runId, type: "device_log",
                    path: deviceLogPath,
                    metadata: "{\"size_bytes\": \(logResult.utf8.count)}",
                    createdAt: Date()
                ))
            }
        }

        recordPhase(.analyzing, substep: "Analysis complete", status: "completed")

        // ===== 8. SUMMARIZING =====
        onPhaseChange(.summarizing, "Generating release confidence report...")
        recordPhase(.summarizing, substep: "Computing confidence score")

        let totalTests = testsPassed + testsFailed
        let criticalCount = findings.filter { $0.severity == .critical }.count
        let highCount = findings.filter { $0.severity == .high }.count
        let mediumCount = findings.filter { $0.severity == .medium }.count
        let lowCount = findings.filter { $0.severity == .low }.count

        // Separate build warnings from runtime/exploration issues
        let runtimeFindings = findings.filter { $0.category != .buildFailure }
        let runtimeCritical = runtimeFindings.filter { $0.severity == .critical }.count
        let runtimeHigh = runtimeFindings.filter { $0.severity == .high }.count
        let runtimeMedium = runtimeFindings.filter { $0.severity == .medium }.count

        // Confidence is driven by runtime issues; build warnings are informational
        var confidenceScore = 100
        confidenceScore -= runtimeCritical * 25
        confidenceScore -= runtimeHigh * 10
        confidenceScore -= runtimeMedium * 3
        // Build warnings: minor deduction, capped at -5
        let buildWarningCount = findings.filter { $0.category == .buildFailure && $0.severity == .low }.count
        confidenceScore -= min(5, buildWarningCount)
        if testsFailed > 0 { confidenceScore -= testsFailed * 5 }
        confidenceScore = max(0, min(100, confidenceScore))

        let readiness: ReleaseReadiness
        if criticalCount > 0 || confidenceScore < 50 {
            readiness = .blocked
        } else if highCount > 0 || confidenceScore < 80 {
            readiness = .caution
        } else {
            readiness = .ready
        }

        let flowsExplored = max(screensVisited.count, totalTests > 0 ? max(1, totalTests / 5) : 0)
        let coveragePercent: Double
        if !screensVisited.isEmpty {
            // Estimate coverage based on screens visited vs expected
            coveragePercent = min(100, Double(screensVisited.count) / 15.0 * 100)
        } else if totalTests > 0 {
            coveragePercent = min(100, Double(testsPassed) / Double(max(1, totalTests)) * 100)
        } else {
            coveragePercent = 0
        }

        recordPhase(.summarizing, substep: "Report generated", status: "completed")
        onPhaseChange(.completed, "Run complete")
        recordPhase(.completed, substep: "Run completed", status: "completed")

        return RunResult(
            status: .completed, phase: .completed,
            releaseReadiness: readiness, confidenceScore: confidenceScore,
            criticalFindings: criticalCount, highFindings: highCount,
            mediumFindings: mediumCount, lowFindings: lowCount,
            testsExecuted: totalTests + explorationActions.count,
            flowsExplored: flowsExplored,
            coveragePercent: coveragePercent,
            xcodeVersion: xcodeVersion, simulatorProfile: simulatorProfile,
            resolvedRuntime: resolvedRuntime,
            commitSha: commitSha, branch: branch,
            buildLog: buildResult.log, findings: findings, artifacts: artifacts,
            phaseEvents: phaseEvents,
            snapshots: explorationSnapshots,
            actionEvents: explorationActions,
            coverageNodes: explorationCoverageNodes,
            screensVisited: screensVisited
        )
    }

    // MARK: - Build Output Parsing

    private func parseBuildErrors(log: String, projectId: String, runId: String) -> [QAFinding] {
        var findings: [QAFinding] = []
        let lines = log.components(separatedBy: "\n")

        for line in lines {
            if line.contains(": error:") {
                let title = extractErrorMessage(from: line)
                let file = extractFilePath(from: line)
                findings.append(QAFinding(
                    id: UUID().uuidString, projectId: projectId, runId: runId,
                    signatureHash: "build-error-\(title.hashValue)",
                    category: .buildFailure, title: "Build error: \(String(title.prefix(120)))",
                    summary: line.trimmingCharacters(in: .whitespaces),
                    severity: .critical, confidence: 1.0, status: .open,
                    firstSeenAt: Date(), lastSeenAt: Date(),
                    reproSteps: "Build the project with xcodebuild",
                    flow: "Build", screen: file ?? "Unknown",
                    occurrences: 1
                ))
            }
        }

        if findings.isEmpty {
            let lastLines = lines.suffix(20).joined(separator: "\n")
            findings.append(QAFinding(
                id: UUID().uuidString, projectId: projectId, runId: runId,
                signatureHash: "build-failure-generic",
                category: .buildFailure, title: "Build failed",
                summary: "The build failed. Check build log for details.",
                severity: .critical, confidence: 1.0, status: .open,
                firstSeenAt: Date(), lastSeenAt: Date(),
                reproSteps: "Build the project with xcodebuild",
                metadata: lastLines, flow: "Build",
                occurrences: 1
            ))
        }

        return findings
    }

    private func parseBuildWarnings(log: String, projectId: String, runId: String) -> [QAFinding] {
        var findings: [QAFinding] = []
        var seenWarnings = Set<String>()
        let lines = log.components(separatedBy: "\n")

        for line in lines {
            if line.contains(": warning:") {
                let title = extractErrorMessage(from: line)
                let hash = "build-warning-\(title.hashValue)"
                guard !seenWarnings.contains(hash) else { continue }
                seenWarnings.insert(hash)

                let file = extractFilePath(from: line)
                findings.append(QAFinding(
                    id: UUID().uuidString, projectId: projectId, runId: runId,
                    signatureHash: hash,
                    category: .buildFailure, subtype: "warning",
                    title: "Build warning: \(String(title.prefix(100)))",
                    summary: line.trimmingCharacters(in: .whitespaces),
                    severity: .low, confidence: 0.9, status: .open,
                    firstSeenAt: Date(), lastSeenAt: Date(),
                    flow: "Build", screen: file ?? "Unknown",
                    occurrences: 1
                ))
            }
        }

        return findings
    }

    private func parseTestFailures(log: String, projectId: String, runId: String, environment: String) -> [QAFinding] {
        var findings: [QAFinding] = []
        let lines = log.components(separatedBy: "\n")

        for (index, line) in lines.enumerated() {
            if (line.contains("failed") && line.contains("XCTAssert")) ||
               (line.contains("Test Case") && line.contains("failed")) {
                let title = line.trimmingCharacters(in: .whitespaces)
                let start = max(0, index - 2)
                let end = min(lines.count - 1, index + 2)
                let context = lines[start...end].joined(separator: "\n")

                findings.append(QAFinding(
                    id: UUID().uuidString, projectId: projectId, runId: runId,
                    signatureHash: "test-failure-\(title.hashValue)",
                    category: .deterministicCheckFailure,
                    title: "Test failure: \(String(title.prefix(120)))",
                    summary: context,
                    severity: .high, confidence: 1.0, status: .open,
                    firstSeenAt: Date(), lastSeenAt: Date(),
                    reproSteps: "Run test suite with xcodebuild test",
                    flow: "Testing", environment: environment,
                    occurrences: 1
                ))
            }
        }

        return findings
    }

    private func parseTestCounts(log: String) -> (passed: Int, failed: Int) {
        var passed = 0
        var failed = 0
        let lines = log.components(separatedBy: "\n")

        for line in lines {
            if line.contains("Test Case") && line.contains("passed") {
                passed += 1
            } else if line.contains("Test Case") && line.contains("failed") {
                failed += 1
            }
        }

        for line in lines {
            if line.contains("Executed") && line.contains("tests") {
                if let match = line.range(of: #"Executed (\d+) tests?, with (\d+) failures?"#, options: .regularExpression) {
                    let matchStr = String(line[match])
                    let numbers = matchStr.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
                    if numbers.count >= 2 {
                        let total = Int(numbers[0]) ?? 0
                        let fails = Int(numbers[1]) ?? 0
                        passed = total - fails
                        failed = fails
                    }
                }
            }
        }

        return (passed, failed)
    }

    // MARK: - Helpers

    private func extractErrorMessage(from line: String) -> String {
        if let range = line.range(of: ": error: ") {
            return String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        if let range = line.range(of: ": warning: ") {
            return String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return line.trimmingCharacters(in: .whitespaces)
    }

    private func extractFilePath(from line: String) -> String? {
        if let colonRange = line.range(of: ":\\d+:\\d+:", options: .regularExpression) {
            return String(line[line.startIndex..<colonRange.lowerBound])
        }
        return nil
    }

    private func findBuiltApp(derivedDataPath: String, scheme: String) async -> String? {
        let buildDir = "\(derivedDataPath)/Build/Products"
        let result = await runner.runShellCommand("find", arguments: [buildDir, "-name", "*.app", "-maxdepth", "3"])
        if let result = result {
            let apps = result.components(separatedBy: "\n").filter { !$0.isEmpty }
            return apps.first { $0.contains("Debug-iphonesimulator") } ?? apps.first
        }
        return nil
    }
}
