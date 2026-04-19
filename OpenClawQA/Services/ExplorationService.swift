import Foundation

// MARK: - Exploration Service
// Manages the autonomous exploration harness:
// 1. Deploys/builds the XCUITest harness
// 2. Runs autonomous exploration against any iOS app
// 3. Parses OCQA_ protocol output in real-time
// 4. Creates findings, screen snapshots, action events
final class ExplorationService {
    static let shared = ExplorationService()
    private let runner = RunnerService.shared
    private let db = DatabaseManager.shared

    // Where the harness lives on disk
    private var harnessDir: String {
        // In production: bundled with the app
        // During dev: sibling directory
        let bundled = Bundle.main.resourcePath.map { $0 + "/Harness" } ?? ""
        if FileManager.default.fileExists(atPath: bundled + "/generate-harness-xcodeproj.rb") {
            return bundled
        }
        // Fall back to repo-relative path
        let repoHarness = NSHomeDirectory() + "/repos/OpenClawQA/Harness"
        if FileManager.default.fileExists(atPath: repoHarness + "/generate-harness-xcodeproj.rb") {
            return repoHarness
        }
        // Fall back to working directory relative
        return "./Harness"
    }

    private var harnessDerivedData: String {
        NSHomeDirectory() + "/Library/Application Support/OpenClawQA/HarnessDerivedData"
    }

    struct ExplorationResult {
        var actionsPerformed: Int
        var statesDiscovered: Int
        var screensVisited: [String] // screen titles
        var findings: [QAFinding]
        var snapshots: [ScreenSnapshot]
        var actionEvents: [ActionEvent]
        var transitions: [(from: String, to: String, action: String)]
        var coverageNodes: [CoverageNode]
        var explorationLog: String
        var xcresultPath: String?
    }

    struct ExplorationProgress {
        var action: Int
        var maxActions: Int
        var statesDiscovered: Int
        var currentScreen: String
        var latestAction: String
        var findings: [QAFinding]
    }

    // MARK: - Build Harness

    func ensureHarnessBuilt(simulator: String) async -> (success: Bool, log: String) {
        // Generate xcodeproj if needed
        let xcodeprojPath = harnessDir + "/OCQAHarness.xcodeproj/project.pbxproj"
        if !FileManager.default.fileExists(atPath: xcodeprojPath) {
            let genScript = harnessDir + "/generate-harness-xcodeproj.rb"
            _ = await runner.runShellCommand("ruby", arguments: [genScript])
        }

        // Build for testing
        let result = await runner.runShellCommand("xcodebuild", arguments: [
            "build-for-testing",
            "-project", harnessDir + "/OCQAHarness.xcodeproj",
            "-scheme", "OCQAHarnessUITests",
            "-destination", "platform=iOS Simulator,name=\(simulator)",
            "-derivedDataPath", harnessDerivedData,
            "-quiet"
        ])

        let success = result?.contains("BUILD SUCCEEDED") == true ||
                       result?.contains("** BUILD SUCCEEDED **") == true ||
                       (result != nil && !result!.contains("BUILD FAILED"))
        return (success, result ?? "No output")
    }

    // MARK: - Run Exploration

    func runExploration(
        bundleId: String,
        simulator: String,
        simulatorUDID: String?,
        maxActions: Int,
        timeoutSeconds: Int,
        projectId: String,
        runId: String,
        artifactDir: String,
        onProgress: @escaping (ExplorationProgress) -> Void
    ) async -> ExplorationResult {
        var findings: [QAFinding] = []
        var snapshots: [ScreenSnapshot] = []
        var actionEvents: [ActionEvent] = []
        var transitions: [(from: String, to: String, action: String)] = []
        var screenNames = Set<String>()
        var screenHashes: [String: String] = [:] // hash -> title
        var allOutput = ""
        var actionsPerformed = 0
        var statesDiscovered = 0

        // Write config for harness
        let configJson = """
        {"OCQA_BUNDLE_ID":"\(bundleId)","OCQA_MAX_ACTIONS":"\(maxActions)","OCQA_TIMEOUT_SECONDS":"\(timeoutSeconds)"}
        """
        let configPath = "/tmp/ocqa-run-config.json"
        try? configJson.write(toFile: configPath, atomically: true, encoding: .utf8)

        // Also write to simulator's tmp if we have UDID
        if let udid = simulatorUDID {
            let simData = NSHomeDirectory() + "/Library/Developer/CoreSimulator/Devices/\(udid)/data/tmp"
            try? configJson.write(toFile: simData + "/ocqa-run-config.json", atomically: true, encoding: .utf8)
        }

        // Result bundle path
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let resultBundlePath = artifactDir + "/exploration-\(timestamp).xcresult"

        // Run the exploration test
        let process = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()

        let xcodebuildPath = "/usr/bin/xcodebuild"
        if FileManager.default.fileExists(atPath: xcodebuildPath) {
            process.executableURL = URL(fileURLWithPath: xcodebuildPath)
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["xcodebuild"]
        }

        var args = [
            "test-without-building",
            "-project", harnessDir + "/OCQAHarness.xcodeproj",
            "-scheme", "OCQAHarnessUITests",
            "-destination", "platform=iOS Simulator,name=\(simulator)",
            "-only-testing:OCQAHarnessUITests/ExplorerTests/testAutonomousExploration",
            "-derivedDataPath", harnessDerivedData,
            "-resultBundlePath", resultBundlePath
        ]

        if FileManager.default.fileExists(atPath: xcodebuildPath) {
            process.arguments = args
        } else {
            process.arguments = (process.arguments ?? []) + args
        }

        process.standardOutput = outPipe
        process.standardError = errPipe
        process.environment = ProcessInfo.processInfo.environment

        // Buffer for line-based parsing
        var lineBuffer = ""
        var stepIndex = 0
        var currentScreenTitle = "Unknown"
        var currentHash = ""

        // Real-time output parsing
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self = self else { return }
            let data = handle.availableData
            guard !data.isEmpty else { return }
            guard let chunk = String(data: data, encoding: .utf8) else { return }

            allOutput += chunk
            lineBuffer += chunk

            while let newlineRange = lineBuffer.range(of: "\n") {
                let line = String(lineBuffer[lineBuffer.startIndex..<newlineRange.lowerBound])
                lineBuffer = String(lineBuffer[newlineRange.upperBound...])

                self.parseLine(
                    line, projectId: projectId, runId: runId,
                    stepIndex: &stepIndex,
                    currentScreenTitle: &currentScreenTitle,
                    currentHash: &currentHash,
                    findings: &findings, snapshots: &snapshots,
                    actionEvents: &actionEvents, transitions: &transitions,
                    screenNames: &screenNames, screenHashes: &screenHashes,
                    actionsPerformed: &actionsPerformed,
                    statesDiscovered: &statesDiscovered,
                    artifactDir: artifactDir,
                    onProgress: onProgress
                )
            }
        }

        // Also capture stderr
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let chunk = String(data: data, encoding: .utf8) {
                allOutput += chunk
            }
        }

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            allOutput += "\nProcess launch failed: \(error.localizedDescription)"
        }

        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil

        // Save exploration log
        let logPath = artifactDir + "/exploration.log"
        try? allOutput.write(toFile: logPath, atomically: true, encoding: .utf8)

        // Extract screenshots from xcresult if available
        if FileManager.default.fileExists(atPath: resultBundlePath) {
            await extractScreenshots(from: resultBundlePath, to: artifactDir, runId: runId, snapshots: &snapshots)
        }

        // Build coverage nodes from screen data
        let coverageNodes = buildCoverageNodes(screenHashes: screenHashes, transitions: transitions)

        return ExplorationResult(
            actionsPerformed: actionsPerformed,
            statesDiscovered: statesDiscovered,
            screensVisited: Array(screenNames).sorted(),
            findings: findings,
            snapshots: snapshots,
            actionEvents: actionEvents,
            transitions: transitions,
            coverageNodes: coverageNodes,
            explorationLog: allOutput,
            xcresultPath: FileManager.default.fileExists(atPath: resultBundlePath) ? resultBundlePath : nil
        )
    }

    // MARK: - Line Parser

    private func parseLine(
        _ line: String,
        projectId: String, runId: String,
        stepIndex: inout Int,
        currentScreenTitle: inout String,
        currentHash: inout String,
        findings: inout [QAFinding],
        snapshots: inout [ScreenSnapshot],
        actionEvents: inout [ActionEvent],
        transitions: inout [(from: String, to: String, action: String)],
        screenNames: inout Set<String>,
        screenHashes: inout [String: String],
        actionsPerformed: inout Int,
        statesDiscovered: inout Int,
        artifactDir: String,
        onProgress: @escaping (ExplorationProgress) -> Void
    ) {
        // Parse OCQA_STATE lines
        if line.hasPrefix("OCQA_STATE:{") {
            if let json = parseJSON(String(line.dropFirst("OCQA_STATE:".count))) {
                let screen = json["screen"] as? String ?? "Unknown"
                let hash = json["hash"] as? String ?? ""
                let elements = json["elements"] as? Int ?? 0

                currentScreenTitle = screen
                currentHash = hash
                screenNames.insert(screen)
                screenHashes[hash] = screen

                let snapshot = ScreenSnapshot(
                    id: UUID().uuidString, runId: runId,
                    stepIndex: stepIndex, timestamp: Date(),
                    screenFingerprint: hash,
                    screenClassification: screen
                )
                snapshots.append(snapshot)
                statesDiscovered = screenHashes.count
            }
        }

        // Parse OCQA_ACTION lines
        if line.hasPrefix("OCQA_ACTION:{") {
            if let json = parseJSON(String(line.dropFirst("OCQA_ACTION:".count))) {
                let actionType = json["type"] as? String ?? "tap"
                let target = json["target"] as? String ?? ""
                let step = json["step"] as? Int ?? stepIndex

                stepIndex = step
                actionsPerformed = step

                let event = ActionEvent(
                    id: UUID().uuidString, runId: runId,
                    stepIndex: step,
                    sourceSnapshotId: snapshots.last?.id,
                    actionType: actionType,
                    targetDescriptor: target,
                    result: "success",
                    timestamp: Date()
                )
                actionEvents.append(event)
            }
        }

        // Parse OCQA_ISSUE lines
        if line.hasPrefix("OCQA_ISSUE:{") {
            if let json = parseJSON(String(line.dropFirst("OCQA_ISSUE:".count))) {
                let issueType = json["type"] as? String ?? "unknown"
                let severity = json["severity"] as? String ?? "medium"
                let title = json["title"] as? String ?? "Unknown issue"
                let screen = json["screen"] as? String ?? currentScreenTitle
                let step = json["step"] as? Int ?? stepIndex

                let findingSeverity: FindingSeverity
                switch severity {
                case "critical": findingSeverity = .critical
                case "high": findingSeverity = .high
                case "low": findingSeverity = .low
                default: findingSeverity = .medium
                }

                let findingCategory: FindingCategory
                switch issueType {
                case "crash": findingCategory = .crash
                case "dead_end": findingCategory = .navigationDeadEnd
                case "navigation_loop": findingCategory = .repeatedLoop
                case "unresponsive": findingCategory = .unresponsiveElement
                case "blank_screen": findingCategory = .blankScreen
                default: findingCategory = .navigationDeadEnd
                }

                let finding = QAFinding(
                    id: UUID().uuidString, projectId: projectId, runId: runId,
                    signatureHash: "\(issueType)-\(screen.hashValue)",
                    category: findingCategory,
                    title: title,
                    summary: "Detected during autonomous exploration at step \(step) on screen '\(screen)'",
                    severity: findingSeverity, confidence: 0.85, status: .open,
                    firstSeenAt: Date(), lastSeenAt: Date(),
                    reproSteps: "Step \(step) during autonomous exploration",
                    flow: "Exploration", screen: screen,
                    occurrences: 1
                )
                findings.append(finding)
            }
        }

        // Parse OCQA_TRANSITION lines
        if line.hasPrefix("OCQA_TRANSITION:{") {
            if let json = parseJSON(String(line.dropFirst("OCQA_TRANSITION:".count))) {
                let from = json["from"] as? String ?? ""
                let to = json["to"] as? String ?? ""
                let action = json["action"] as? String ?? ""
                let fromHash = json["fromHash"] as? String ?? ""
                let toHash = json["toHash"] as? String ?? ""

                transitions.append((from: from, to: to, action: action))

                // Track screen names
                if !from.isEmpty { screenNames.insert(from); screenHashes[fromHash] = from }
                if !to.isEmpty { screenNames.insert(to); screenHashes[toHash] = to }
            }
        }

        // Parse OCQA_PROGRESS lines
        if line.hasPrefix("OCQA_PROGRESS:{") {
            if let json = parseJSON(String(line.dropFirst("OCQA_PROGRESS:".count))) {
                let action = json["action"] as? Int ?? actionsPerformed
                let max = json["max"] as? Int ?? 200
                let states = json["states"] as? Int ?? statesDiscovered

                actionsPerformed = action
                statesDiscovered = states

                let progress = ExplorationProgress(
                    action: action, maxActions: max,
                    statesDiscovered: states,
                    currentScreen: currentScreenTitle,
                    latestAction: actionEvents.last?.actionType ?? "",
                    findings: findings
                )
                onProgress(progress)
            }
        }

        // Parse OCQA_COMPLETE lines
        if line.hasPrefix("OCQA_COMPLETE:{") {
            if let json = parseJSON(String(line.dropFirst("OCQA_COMPLETE:".count))) {
                actionsPerformed = json["actions"] as? Int ?? actionsPerformed
                statesDiscovered = json["states"] as? Int ?? statesDiscovered
            }
        }
    }

    // MARK: - Screenshot Extraction

    private func extractScreenshots(from xcresultPath: String, to outputDir: String, runId: String, snapshots: inout [ScreenSnapshot]) async {
        let screenshotDir = outputDir + "/screenshots"
        try? FileManager.default.createDirectory(atPath: screenshotDir, withIntermediateDirectories: true)

        // Use xcresulttool to list attachments
        let listResult = await runner.runShellCommand("xcrun", arguments: [
            "xcresulttool", "get", "--format", "json",
            "--path", xcresultPath
        ])

        guard let listResult = listResult else { return }

        // Extract test attachment references
        // xcresulttool output is complex nested JSON; extract attachment IDs
        if let data = listResult.data(using: .utf8),
           let _ = try? JSONSerialization.jsonObject(with: data) {
            // For each snapshot that doesn't have a screenshot path, try to extract
            // The attachments are named "state_N_ScreenName"
            let exportResult = await runner.runShellCommand("xcrun", arguments: [
                "xcresulttool", "export",
                "--type", "file",
                "--path", xcresultPath,
                "--output-path", screenshotDir
            ])

            // Find extracted PNG files
            let extractedFiles = await runner.runShellCommand("find", arguments: [
                screenshotDir, "-name", "*.png", "-o", "-name", "*.jpg"
            ])
            if let files = extractedFiles {
                let paths = files.components(separatedBy: "\n").filter { !$0.isEmpty }.sorted()
                // Match screenshots to snapshots by index
                for (i, path) in paths.enumerated() where i < snapshots.count {
                    snapshots[i] = ScreenSnapshot(
                        id: snapshots[i].id, runId: snapshots[i].runId,
                        stepIndex: snapshots[i].stepIndex,
                        timestamp: snapshots[i].timestamp,
                        screenFingerprint: snapshots[i].screenFingerprint,
                        screenshotPath: path,
                        accessibilityTreeJson: snapshots[i].accessibilityTreeJson,
                        screenClassification: snapshots[i].screenClassification,
                        parentSnapshotId: snapshots[i].parentSnapshotId
                    )
                }
            }
        }
    }

    // MARK: - Coverage Node Builder

    private func buildCoverageNodes(
        screenHashes: [String: String],
        transitions: [(from: String, to: String, action: String)]
    ) -> [CoverageNode] {
        var nodes: [String: CoverageNode] = [:]

        // Create a node for each unique screen
        let uniqueScreens = Array(Set(screenHashes.values))
        let gridColumns = max(1, Int(ceil(sqrt(Double(uniqueScreens.count)))))

        for (index, screenName) in uniqueScreens.sorted().enumerated() {
            let row = index / gridColumns
            let col = index % gridColumns
            let x = CGFloat(col) * 200 + 100
            let y = CGFloat(row) * 150 + 80

            nodes[screenName] = CoverageNode(
                id: "node-\(screenName.hashValue)",
                name: screenName,
                coveragePercent: 100,
                status: .visited,
                position: CGPoint(x: x, y: y),
                connections: []
            )
        }

        // Add connections from transitions
        for transition in transitions {
            if var fromNode = nodes[transition.from], nodes[transition.to] != nil {
                let toId = "node-\(transition.to.hashValue)"
                if !fromNode.connections.contains(toId) {
                    fromNode.connections.append(toId)
                    nodes[transition.from] = fromNode
                }
            }
        }

        return Array(nodes.values)
    }

    // MARK: - JSON Helper

    private func parseJSON(_ str: String) -> [String: Any]? {
        guard let data = str.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }
}
