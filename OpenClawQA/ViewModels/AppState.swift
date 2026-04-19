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

    private let db = DatabaseManager.shared

    var currentProject: QAProject? {
        projects.first { $0.id == selectedProjectId }
    }

    var currentRun: QARun? {
        runs.first { $0.id == selectedRunId }
    }

    var latestRun: QARun? {
        runs.first
    }

    var selectedFinding: QAFinding? {
        findings.first { $0.id == selectedFindingId }
    }

    func loadData() {
        projects = db.fetchProjects()
        if selectedProjectId == nil { selectedProjectId = projects.first?.id }
        if let pid = selectedProjectId {
            runs = db.fetchRuns(projectId: pid)
            findings = db.fetchFindings(projectId: pid)
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
    }

    func selectFinding(_ id: String) {
        selectedFindingId = id
    }

    func dismissRunDetail() {
        showRunDetail = false
        selectedRunId = nil
    }

    func startNewRun() {
        guard let pid = selectedProjectId else { return }
        let run = QARun(
            id: "run-\(UUID().uuidString.prefix(8))", projectId: pid,
            triggerSource: "manual", branch: currentProject?.defaultBranch ?? "main",
            status: .queued, phase: .queued,
            xcodeVersion: "16.2", simulatorProfile: "iPhone 16 Pro (iOS 17.5)",
            startedAt: Date(),
            criticalFindings: 0, highFindings: 0, mediumFindings: 0, lowFindings: 0,
            testsExecuted: 0, flowsExplored: 0, coveragePercent: 0
        )
        db.insertRun(run)
        runs.insert(run, at: 0)
        selectedRunId = run.id
        showRunDetail = true
        // TODO: Spawn engine process for actual execution
    }
}
