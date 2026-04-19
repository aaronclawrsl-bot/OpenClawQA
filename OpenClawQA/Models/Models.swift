import Foundation

// MARK: - Project
struct QAProject: Identifiable, Codable {
    let id: String
    var name: String
    var repoType: String // "local", "github"
    var repoIdentifier: String
    var localRepoPath: String?
    var defaultBranch: String
    var workspacePath: String?
    var projectPath: String?
    var scheme: String
    var configuration: String
    var bundleId: String
    var runnerMode: String // "local", "remote"
    var createdAt: Date
    var updatedAt: Date

    init(id: String = UUID().uuidString, name: String, repoType: String = "github",
         repoIdentifier: String = "", localRepoPath: String? = nil,
         defaultBranch: String = "main", workspacePath: String? = nil,
         projectPath: String? = nil, scheme: String = "", configuration: String = "Debug",
         bundleId: String = "", runnerMode: String = "local",
         createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.name = name; self.repoType = repoType
        self.repoIdentifier = repoIdentifier; self.localRepoPath = localRepoPath
        self.defaultBranch = defaultBranch; self.workspacePath = workspacePath
        self.projectPath = projectPath; self.scheme = scheme
        self.configuration = configuration; self.bundleId = bundleId
        self.runnerMode = runnerMode; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

// MARK: - Run
struct QARun: Identifiable, Codable {
    let id: String
    var projectId: String
    var triggerSource: String // "manual", "ci", "schedule", "github_push", "pr"
    var triggerMetadata: String? // JSON
    var branch: String
    var commitSha: String?
    var prNumber: Int?
    var status: RunStatus
    var phase: RunPhase
    var runnerId: String?
    var xcodeVersion: String?
    var simulatorProfile: String?
    var resolvedRuntime: String?
    var startedAt: Date?
    var endedAt: Date?
    var confidenceScore: Int?
    var releaseReadiness: ReleaseReadiness?
    var criticalFindings: Int
    var highFindings: Int
    var mediumFindings: Int
    var lowFindings: Int
    var testsExecuted: Int
    var flowsExplored: Int
    var coveragePercent: Double
    var durationMs: Int?

    var durationFormatted: String {
        guard let ms = durationMs else { return "--" }
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes)m \(seconds)s"
    }

    var shortCommit: String {
        guard let sha = commitSha else { return "--" }
        return String(sha.prefix(7))
    }
}

enum RunStatus: String, Codable, CaseIterable {
    case queued, preparing, building, booting, installing
    case deterministicChecks = "deterministic_checks"
    case exploring, analyzing, summarizing
    case completed, failed, cancelled
}

enum RunPhase: String, Codable, CaseIterable {
    case queued, preparing, building, booting, installing
    case deterministicChecks = "deterministic_checks"
    case exploring, analyzing, summarizing
    case completed, failed, cancelled
}

enum ReleaseReadiness: String, Codable {
    case ready, caution, blocked
}

// MARK: - Finding
struct QAFinding: Identifiable, Codable {
    let id: String
    var projectId: String
    var runId: String
    var signatureHash: String
    var category: FindingCategory
    var subtype: String?
    var title: String
    var summary: String
    var severity: FindingSeverity
    var confidence: Double
    var status: FindingStatus
    var firstSeenAt: Date
    var lastSeenAt: Date
    var evidence: String? // JSON
    var reproSteps: String? // JSON
    var metadata: String? // JSON
    var flow: String?
    var screen: String?
    var environment: String?
    var occurrences: Int
    var aiAnalysis: String?
    var suggestedFix: String?
    var impact: String?
    var affectedBuilds: String?
    var assignee: String?
}

enum FindingCategory: String, Codable, CaseIterable {
    case buildFailure = "build_failure"
    case launchFailure = "launch_failure"
    case crash
    case deterministicCheckFailure = "deterministic_check_failure"
    case unresponsiveElement = "unresponsive_element"
    case navigationDeadEnd = "navigation_dead_end"
    case repeatedLoop = "repeated_loop"
    case visualRegression = "visual_regression"
    case layoutOverlap = "layout_overlap"
    case textClipping = "text_clipping"
    case missingAsset = "missing_asset"
    case blankScreen = "blank_screen"
    case authFailure = "auth_failure"
    case networkErrorSurface = "network_error_surface"
    case permissionBlocker = "permission_blocker"
    case unexpectedModal = "unexpected_modal"
    case performanceTimeout = "performance_timeout"
    case appHang = "app_hang"
}

enum FindingSeverity: String, Codable, CaseIterable {
    case critical, high, medium, low

    var sortOrder: Int {
        switch self {
        case .critical: return 0
        case .high: return 1
        case .medium: return 2
        case .low: return 3
        }
    }
}

enum FindingStatus: String, Codable, CaseIterable {
    case open, acknowledged, linked, suppressed, resolved, regressed
}

// MARK: - Screen Snapshot
struct ScreenSnapshot: Identifiable, Codable {
    let id: String
    var runId: String
    var stepIndex: Int
    var timestamp: Date
    var screenFingerprint: String
    var screenshotPath: String?
    var accessibilityTreeJson: String?
    var screenClassification: String?
    var parentSnapshotId: String?
}

// MARK: - Action Event
struct ActionEvent: Identifiable, Codable {
    let id: String
    var runId: String
    var stepIndex: Int
    var sourceSnapshotId: String?
    var actionType: String
    var targetDescriptor: String? // JSON
    var result: String
    var timestamp: Date
    var durationMs: Int?
    var producedSnapshotId: String?
}

// MARK: - Environment Profile
struct EnvironmentProfile: Identifiable, Codable {
    let id: String
    var projectId: String
    var name: String
    var simulatorProfile: String
    var envVars: String? // JSON
    var launchArgs: String? // JSON
    var seedStrategyType: String?
    var resetStrategyType: String?
    var credentialsRef: String?
}

// MARK: - Integration
struct IntegrationConnection: Identifiable, Codable {
    let id: String
    var type: IntegrationType
    var displayName: String
    var accountIdentifier: String?
    var isConnected: Bool
    var configJson: String?
    var createdAt: Date
    var updatedAt: Date
}

enum IntegrationType: String, Codable, CaseIterable {
    case github, jira, slack, email, jenkins, xcodeCloud = "xcode_cloud", githubActions = "github_actions"
}

// MARK: - Artifact
struct QAArtifact: Identifiable, Codable {
    let id: String
    var runId: String
    var type: String // "screenshot", "video", "log", "xcresult", "crash_log"
    var path: String
    var metadata: String? // JSON
    var createdAt: Date
}

// MARK: - Runner
struct QARunner: Identifiable, Codable {
    let id: String
    var mode: String // "local", "remote"
    var displayName: String
    var capabilities: String? // JSON
    var healthStatus: String // "healthy", "degraded", "offline"
    var xcodeVersions: [String]
    var simulators: [String]
    var lastSeenAt: Date
}

// MARK: - Suppression Rule
struct SuppressionRule: Identifiable, Codable {
    let id: String
    var projectId: String
    var ruleJson: String
    var createdAt: Date
    var active: Bool
}

// MARK: - Run Phase Event
struct RunPhaseEvent: Identifiable, Codable {
    let id: String
    var runId: String
    var phase: String
    var substep: String?
    var status: String
    var timestamp: Date
    var payload: String? // JSON
}

// MARK: - Insight / Trend Data
struct InsightTrend {
    var confidenceTrend: Double // percentage change
    var bugsFound: Int
    var avgRunTimeMinutes: Int
    var flakyTests: Int
    var topIssueCategories: [(String, Int)]
    var recentActivity: [(String, String)] // (timestamp, description)
}

// MARK: - Coverage Node (for Flow Map)
struct CoverageNode: Identifiable {
    let id: String
    var name: String
    var coveragePercent: Int
    var status: CoverageNodeStatus
    var position: CGPoint
    var connections: [String] // IDs of connected nodes
}

enum CoverageNodeStatus: String {
    case visited, partial, notVisited, blocked
}
