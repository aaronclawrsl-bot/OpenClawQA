import SwiftUI
import Combine

// MARK: - Navigation
enum NavigationTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case runs = "Runs"
    case findings = "Findings"
    case coverage = "Coverage"
    case insights = "Insights"
    case integrations = "Integrations"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .runs: return "play.circle"
        case .findings: return "exclamationmark.triangle"
        case .coverage: return "map"
        case .insights: return "chart.bar"
        case .integrations: return "link"
        case .settings: return "gearshape"
        }
    }
}

// MARK: - App State
@MainActor
final class AppState: ObservableObject {
    @Published var selectedTab: NavigationTab = .overview
    @Published var selectedProjectId: String?
    @Published var selectedRunId: String?
    @Published var selectedFindingId: String?
    @Published var showProjectSetup: Bool = false
    @Published var showRunDetail: Bool = false

    @Published var projects: [QAProject] = []
    @Published var runs: [QARun] = []
    @Published var findings: [QAFinding] = []
    @Published var integrations: [IntegrationConnection] = []
    @Published var artifacts: [QAArtifact] = []
    @Published var runPhaseEvents: [RunPhaseEvent] = []
    @Published var screenSnapshots: [ScreenSnapshot] = []
    @Published var actionEvents: [ActionEvent] = []
    @Published var coverageNodes: [CoverageNode] = []

    var latestRun: QARun? { runs.first }

    @Published var isRunning: Bool = false
    @Published var currentPhase: RunPhase = .queued
    @Published var currentPhaseDetail: String = ""
    @Published var runError: String?

    private let db = DatabaseManager.shared
    private let orchestrator = OrchestratorService.shared

    var currentProject: QAProject? {
        projects.first { $0.id == selectedProjectId }
    }

    var currentRun: QARun? {
        runs.first { $0.id == selectedRunId }
    }

    var selectedFinding: QAFinding? {
        findings.first { $0.id == selectedFindingId }
    }

    func loadData() {
        projects = db.fetchProjects()

        // Auto-create ResiLife project if no projects exist and repo is present
        if projects.isEmpty {
            let candidatePaths = [
                NSHomeDirectory() + "/repos/EWAG-dev-iosApp",
                NSHomeDirectory() + "/repos/iosApp",
                NSHomeDirectory() + "/Developer/iosApp",
                NSHomeDirectory() + "/Projects/iosApp"
            ]
            for repoPath in candidatePaths {
                if FileManager.default.fileExists(atPath: repoPath + "/EWAG.xcodeproj") {
                    let project = QAProject(
                        id: "proj-resilife-\(UUID().uuidString.prefix(8))",
                        name: "ResiLife iOS",
                        repoType: "local",
                        repoIdentifier: "EWAG-dev/iosApp",
                        localRepoPath: repoPath,
                        defaultBranch: "main",
                        projectPath: repoPath + "/EWAG.xcodeproj",
                        scheme: "ResiLife",
                        configuration: "Debug",
                        bundleId: "com.elitepro.resilife",
                        runnerMode: "local"
                    )
                    db.insertProject(project)
                    projects = db.fetchProjects()
                    break
                }
            }
        }

        if selectedProjectId == nil { selectedProjectId = projects.first?.id }
        if let pid = selectedProjectId {
            runs = db.fetchRuns(projectId: pid)
            findings = db.fetchFindings(projectId: pid)
            // Load data for the latest run so overview shows screenshots/actions
            if let latestId = runs.first?.id {
                screenSnapshots = db.fetchScreenSnapshots(runId: latestId)
                actionEvents = db.fetchActionEvents(runId: latestId)
                artifacts = db.fetchArtifacts(runId: latestId)
            }
        }
        integrations = db.fetchIntegrations()
    }

    func selectProject(_ id: String) {
        selectedProjectId = id
        runs = db.fetchRuns(projectId: id)
        findings = db.fetchFindings(projectId: id)
        selectedRunId = nil
        selectedFindingId = nil
        showRunDetail = false
    }

    func selectRun(_ id: String) {
        selectedRunId = id
        showRunDetail = true
        artifacts = db.fetchArtifacts(runId: id)
        runPhaseEvents = db.fetchRunPhaseEvents(runId: id)
        screenSnapshots = db.fetchScreenSnapshots(runId: id)
        actionEvents = db.fetchActionEvents(runId: id)

        // Rebuild coverage nodes from screen snapshots
        var uniqueScreens: [String: Int] = [:]
        for s in screenSnapshots {
            let name = s.screenClassification ?? "Unknown"
            uniqueScreens[name, default: 0] += 1
        }
        let sorted = uniqueScreens.keys.sorted()
        let gridColumns = max(1, Int(ceil(sqrt(Double(sorted.count)))))
        coverageNodes = sorted.enumerated().map { (i, name) in
            let row = i / gridColumns
            let col = i % gridColumns
            return CoverageNode(
                id: "node-\(name.hashValue)",
                name: name,
                coveragePercent: 100,
                status: .visited,
                position: CGPoint(x: CGFloat(col) * 200 + 100, y: CGFloat(row) * 150 + 80),
                connections: []
            )
        }
    }

    func selectFinding(_ id: String) {
        selectedFindingId = id
    }

    func dismissRunDetail() {
        showRunDetail = false
        selectedRunId = nil
    }

    func startNewRun() {
        guard let project = currentProject else { return }
        guard !isRunning else { return }

        let runId = "run-\(UUID().uuidString.prefix(8))"

        var run = QARun(
            id: runId, projectId: project.id,
            triggerSource: "manual", branch: project.defaultBranch,
            status: .queued, phase: .queued,
            startedAt: Date(),
            criticalFindings: 0, highFindings: 0, mediumFindings: 0, lowFindings: 0,
            testsExecuted: 0, flowsExplored: 0, coveragePercent: 0
        )
        db.insertRun(run)
        runs.insert(run, at: 0)
        selectedRunId = run.id
        showRunDetail = true
        isRunning = true
        runError = nil
        currentPhase = .queued
        currentPhaseDetail = "Starting..."

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let result = try await orchestrator.executeReleaseCheck(
                    project: project,
                    runId: runId,
                    onPhaseChange: { [weak self] phase, detail in
                        Task { @MainActor in
                            self?.currentPhase = phase
                            self?.currentPhaseDetail = detail
                            // Update the run in the list and persist to DB
                            if let index = self?.runs.firstIndex(where: { $0.id == runId }) {
                                self?.runs[index].phase = phase
                                self?.runs[index].status = phase == .completed ? .completed : (phase == .failed ? .failed : .exploring)
                                if let updatedRun = self?.runs[index] {
                                    self?.db.updateRun(updatedRun)
                                }
                            }
                        }
                    }
                )

                // Update run with results
                run.status = result.status
                run.phase = result.phase
                run.releaseReadiness = result.releaseReadiness
                run.confidenceScore = result.confidenceScore
                run.criticalFindings = result.criticalFindings
                run.highFindings = result.highFindings
                run.mediumFindings = result.mediumFindings
                run.lowFindings = result.lowFindings
                run.testsExecuted = result.testsExecuted
                run.flowsExplored = result.flowsExplored
                run.coveragePercent = result.coveragePercent
                run.xcodeVersion = result.xcodeVersion
                run.simulatorProfile = result.simulatorProfile
                run.resolvedRuntime = result.resolvedRuntime
                run.commitSha = result.commitSha
                run.branch = result.branch
                run.endedAt = Date()
                run.durationMs = Int(Date().timeIntervalSince(run.startedAt ?? Date()) * 1000)

                db.updateRun(run)

                // Insert findings
                for finding in result.findings {
                    db.insertFinding(finding)
                }

                // Insert artifacts
                for artifact in result.artifacts {
                    db.insertArtifact(artifact)
                }

                // Insert exploration data
                for snapshot in result.snapshots {
                    db.insertScreenSnapshot(snapshot)
                }
                for actionEvent in result.actionEvents {
                    db.insertActionEvent(actionEvent)
                }

                await MainActor.run {
                    if let index = self.runs.firstIndex(where: { $0.id == runId }) {
                        self.runs[index] = run
                    }
                    self.findings = self.db.fetchFindings(projectId: project.id)
                    self.screenSnapshots = result.snapshots
                    self.actionEvents = result.actionEvents
                    self.coverageNodes = result.coverageNodes
                    self.isRunning = false
                    self.currentPhaseDetail = "Run complete"
                }

            } catch {
                await MainActor.run {
                    self.runError = error.localizedDescription
                    self.isRunning = false
                    self.currentPhase = .failed
                    self.currentPhaseDetail = error.localizedDescription

                    run.status = .failed
                    run.phase = .failed
                    run.endedAt = Date()
                    run.durationMs = Int(Date().timeIntervalSince(run.startedAt ?? Date()) * 1000)
                    self.db.updateRun(run)

                    if let index = self.runs.firstIndex(where: { $0.id == runId }) {
                        self.runs[index] = run
                    }
                }
            }
        }
    }
}
