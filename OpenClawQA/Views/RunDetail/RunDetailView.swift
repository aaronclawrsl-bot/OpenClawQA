import SwiftUI

struct RunDetailView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedDetailTab: String = "Overview"

    private var run: QARun? { appState.currentRun }
    private var findings: [QAFinding] { appState.findings.filter { $0.runId == run?.id } }
    private var selectedFinding: QAFinding? {
        appState.selectedFinding ?? findings.first
    }

    let detailTabs = ["Overview", "Timeline", "Environment", "Logs", "Artifacts"]

    var body: some View {
        HStack(spacing: 0) {
            // Main content (left)
            VStack(spacing: 0) {
                runDetailHeader
                Divider().background(AppColors.border)

                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.xl) {
                        if let finding = selectedFinding {
                            findingHeader(finding)
                            findingInfo(finding)
                        }

                        // Video player area
                        videoPlayerArea

                        // Tab content
                        detailTabBar
                        detailTabContent
                    }
                    .padding(AppSpacing.xl)
                }
            }
            .frame(maxWidth: .infinity)

            Divider().background(AppColors.border)

            // Right panel - finding metadata
            if let finding = selectedFinding {
                findingMetadataPanel(finding)
                    .frame(width: 280)
            }
        }
        .background(AppColors.windowBackground)
        .onAppear {
            if let first = findings.first {
                appState.selectFinding(first.id)
            }
        }
    }

    // MARK: - Header
    private var runDetailHeader: some View {
        HStack {
            Button(action: { appState.dismissRunDetail() }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12))
                    Text("Run Details")
                        .font(AppFont.heading(16))
                }
                .foregroundColor(AppColors.textPrimary)
            }
            .buttonStyle(.plain)

            Text("–")
                .foregroundColor(AppColors.textTertiary)

            Text(run?.startedAt?.formatted(date: .abbreviated, time: .shortened) ?? "--")
                .font(AppFont.body())
                .foregroundColor(AppColors.textSecondary)

            Spacer()

            Button(action: {}) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10))
                    Text("View on GitHub")
                        .font(AppFont.subheading(12))
                }
                .foregroundColor(AppColors.textSecondary)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, 6)
                .background(AppColors.inputBackground)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

            Button(action: { appState.startNewRun() }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                    Text("Re-run This Check")
                        .font(AppFont.subheading(12))
                }
                .foregroundColor(.white)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, 6)
                .background(AppColors.accentBlue)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(AppSpacing.lg)
    }

    // MARK: - Finding Header
    private func findingHeader(_ finding: QAFinding) -> some View {
        HStack(spacing: AppSpacing.md) {
            Text(finding.title)
                .font(AppFont.heading(20))
                .foregroundColor(AppColors.textPrimary)

            SeverityBadge(severity: finding.severity)
        }
    }

    // MARK: - Finding Info Grid
    private func findingInfo(_ finding: QAFinding) -> some View {
        VStack(spacing: AppSpacing.sm) {
            infoRow("Flow", finding.flow ?? "--")
            infoRow("Screen", finding.screen ?? "--")
            infoRow("Environment", finding.environment ?? "iPhone 16 Pro (iOS 17.5)")
            infoRow("Occurred", finding.lastSeenAt.formatted(date: .abbreviated, time: .shortened)
                     + " (" + finding.lastSeenAt.formatted(.relative(presentation: .named)) + ")")
            infoRow("State", finding.status.rawValue.capitalized)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(AppFont.body())
                .foregroundColor(AppColors.textSecondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(AppFont.body())
                .foregroundColor(AppColors.textPrimary)
            Spacer()
        }
    }

    // MARK: - Video Player
    private var videoPlayerArea: some View {
        VStack(spacing: 0) {
            // Video frame
            RoundedRectangle(cornerRadius: 12)
                .fill(AppColors.inputBackground)
                .frame(height: 300)
                .overlay(
                    VStack(spacing: AppSpacing.md) {
                        Image(systemName: "iphone.gen3")
                            .font(.system(size: 48))
                            .foregroundColor(AppColors.textTertiary)
                        Text("Video replay")
                            .font(AppFont.caption())
                            .foregroundColor(AppColors.textTertiary)
                        Text("Screenshots and recordings from this run will appear here")
                            .font(AppFont.caption())
                            .foregroundColor(AppColors.textTertiary)
                    }
                )

            // Playback controls
            HStack {
                Button(action: {}) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14))
                        .foregroundColor(AppColors.textPrimary)
                }
                .buttonStyle(.plain)

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AppColors.inputBackground)
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AppColors.accentBlue)
                            .frame(width: geo.size.width * 0.35, height: 4)
                    }
                }
                .frame(height: 4)

                Text("00:12 / 02:34")
                    .font(AppFont.mono(11))
                    .foregroundColor(AppColors.textSecondary)

                HStack(spacing: AppSpacing.sm) {
                    Text("1x")
                        .font(AppFont.caption(11))
                        .foregroundColor(AppColors.textSecondary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(AppColors.textTertiary)
                }

                Button(action: {}) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(AppColors.cardBackground)
            .cornerRadius(8)
        }
    }

    // MARK: - Detail Tabs
    private var detailTabBar: some View {
        HStack(spacing: 0) {
            ForEach(detailTabs, id: \.self) { tab in
                Button(action: { selectedDetailTab = tab }) {
                    Text(tab)
                        .font(AppFont.subheading(13))
                        .foregroundColor(selectedDetailTab == tab ? AppColors.textPrimary : AppColors.textSecondary)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)
                }
                .buttonStyle(.plain)
                .overlay(alignment: .bottom) {
                    if selectedDetailTab == tab {
                        Rectangle()
                            .fill(AppColors.accentBlue)
                            .frame(height: 2)
                    }
                }
            }
            Spacer()
        }
        .background(AppColors.cardBackground)
        .cornerRadius(6)
    }

    @ViewBuilder
    private var detailTabContent: some View {
        switch selectedDetailTab {
        case "Overview":
            analysisContent
        case "Timeline":
            timelineContent
        case "Environment":
            environmentContent
        case "Logs":
            logsContent
        case "Artifacts":
            artifactsContent
        default:
            EmptyView()
        }
    }

    // MARK: - Analysis Content (matches mockup)
    private var analysisContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            // AI Analysis
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("AI Analysis")
                    .font(AppFont.heading(16))
                    .foregroundColor(AppColors.textPrimary)
                Text(selectedFinding?.aiAnalysis ?? "Analysis not available for this finding.")
                    .font(AppFont.body())
                    .foregroundColor(AppColors.textSecondary)
                    .lineSpacing(4)
            }
            .cardStyle()

            // Suggested Fix
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Suggested Fix")
                    .font(AppFont.heading(16))
                    .foregroundColor(AppColors.textPrimary)
                Text(selectedFinding?.suggestedFix ?? "No fix suggestion available.")
                    .font(AppFont.body())
                    .foregroundColor(AppColors.textSecondary)
                    .lineSpacing(4)
            }
            .cardStyle()
        }
    }

    // MARK: - Timeline Content
    private var timelineContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            let phases: [(String, String, String)] = [
                ("checkmark.circle.fill", "Preparing", "00:00 - 00:03"),
                ("checkmark.circle.fill", "Building", "00:03 - 05:42"),
                ("checkmark.circle.fill", "Installing", "05:42 - 05:58"),
                ("checkmark.circle.fill", "Deterministic Checks", "05:58 - 08:15"),
                ("checkmark.circle.fill", "Exploring", "08:15 - 28:30"),
                ("checkmark.circle.fill", "Analyzing", "28:30 - 31:45"),
                ("checkmark.circle.fill", "Completed", "31:45 - 32:14"),
            ]

            ForEach(phases, id: \.0) { phase in
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: phase.0)
                        .foregroundColor(AppColors.success)
                        .font(.system(size: 14))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(phase.1)
                            .font(AppFont.subheading())
                            .foregroundColor(AppColors.textPrimary)
                        Text(phase.2)
                            .font(AppFont.caption())
                            .foregroundColor(AppColors.textSecondary)
                    }
                    Spacer()
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Environment Content
    private var environmentContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            envRow("Xcode Version", run?.xcodeVersion ?? "16.2")
            envRow("Simulator", run?.simulatorProfile ?? "iPhone 16 Pro (iOS 17.5)")
            envRow("Runtime", run?.resolvedRuntime ?? "iOS 17.5")
            envRow("Branch", run?.branch ?? "main")
            envRow("Commit", run?.commitSha ?? "--")
            envRow("Runner", run?.runnerId ?? "Local Runner")
            envRow("Configuration", "Debug")
        }
        .cardStyle()
    }

    private func envRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(AppFont.body())
                .foregroundColor(AppColors.textSecondary)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .font(AppFont.mono(12))
                .foregroundColor(AppColors.textPrimary)
            Spacer()
        }
    }

    // MARK: - Logs Content
    private var logsContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            let sampleLogs = [
                "[09:15:22] Starting autonomous exploration...",
                "[09:15:23] Screen fingerprint: home_screen_v1",
                "[09:15:24] Found 12 interactive elements",
                "[09:15:25] Action: tap 'Login' button",
                "[09:15:26] Navigated to: login_screen",
                "[09:15:27] Screen fingerprint: login_screen_v1",
                "[09:15:28] Action: type email into emailField",
                "[09:15:30] Action: type password into passwordField",
                "[09:15:31] Action: tap 'Submit' button",
                "[09:15:35] WARNING: Login button appears enabled but did not trigger navigation",
                "[09:15:36] Finding detected: unresponsive_element (confidence: 0.87)",
                "[09:15:37] Screenshot captured: step_14_login_unresponsive.png",
            ]

            ForEach(sampleLogs, id: \.self) { line in
                Text(line)
                    .font(AppFont.mono(11))
                    .foregroundColor(line.contains("WARNING") ? AppColors.warning : AppColors.textSecondary)
                    .padding(.vertical, 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.md)
        .background(Color(hex: "0D1117"))
        .cornerRadius(8)
    }

    // MARK: - Artifacts Content
    private var artifactsContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            let artifacts: [(String, String, String)] = [
                ("photo", "Screenshots (47)", "12.3 MB"),
                ("video", "Screen Recording", "45.8 MB"),
                ("doc.text", "Build Log", "234 KB"),
                ("doc.text", "Explorer Log", "89 KB"),
                ("folder", "xcresult Bundle", "156.2 MB"),
                ("exclamationmark.triangle", "Crash Log", "12 KB"),
            ]

            ForEach(artifacts, id: \.0) { artifact in
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: artifact.0)
                        .foregroundColor(AppColors.accentBlue)
                        .frame(width: 20)
                    Text(artifact.1)
                        .font(AppFont.body())
                        .foregroundColor(AppColors.textPrimary)
                    Spacer()
                    Text(artifact.2)
                        .font(AppFont.caption())
                        .foregroundColor(AppColors.textSecondary)
                    Button(action: {}) {
                        Image(systemName: "arrow.down.circle")
                            .foregroundColor(AppColors.accentBlue)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, AppSpacing.xs)
            }
        }
        .cardStyle()
    }

    // MARK: - Finding Metadata Panel (right side)
    private func findingMetadataPanel(_ finding: QAFinding) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                // Impact
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("Impact")
                        .font(AppFont.heading(14))
                        .foregroundColor(AppColors.textPrimary)
                    Text(finding.impact ?? "Users cannot log in and are blocked from accessing the app.")
                        .font(AppFont.caption())
                        .foregroundColor(AppColors.textSecondary)
                        .lineSpacing(3)
                }

                Divider().background(AppColors.border)

                // Affected Builds
                metaRow("Affected Builds", finding.affectedBuilds ?? "1.4.2 (45)")
                metaRow("First Seen", finding.firstSeenAt.formatted(date: .abbreviated, time: .shortened))
                metaRow("Last Seen", finding.lastSeenAt.formatted(date: .abbreviated, time: .shortened))
                metaRow("Occurrences", "\(finding.occurrences)")

                Divider().background(AppColors.border)

                // Status
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("Status")
                        .font(AppFont.caption())
                        .foregroundColor(AppColors.textSecondary)
                    HStack {
                        Text(finding.status.rawValue.capitalized)
                            .font(AppFont.subheading())
                            .foregroundColor(AppColors.success)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10))
                            .foregroundColor(AppColors.textTertiary)
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, 6)
                    .background(AppColors.inputBackground)
                    .cornerRadius(6)
                }

                // Assignee
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("Assignee")
                        .font(AppFont.caption())
                        .foregroundColor(AppColors.textSecondary)
                    HStack {
                        Text(finding.assignee ?? "Unassigned")
                            .font(AppFont.subheading())
                            .foregroundColor(AppColors.textSecondary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10))
                            .foregroundColor(AppColors.textTertiary)
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, 6)
                    .background(AppColors.inputBackground)
                    .cornerRadius(6)
                }

                Divider().background(AppColors.border)

                // Create Issue button
                Button(action: {}) {
                    HStack {
                        Spacer()
                        Text("Create Issue")
                            .font(AppFont.subheading(14))
                        Spacer()
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, AppSpacing.md)
                    .background(AppColors.success)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)

                // Findings list for this run
                Divider().background(AppColors.border)

                Text("Run Findings")
                    .font(AppFont.heading(14))
                    .foregroundColor(AppColors.textPrimary)

                ForEach(findings) { f in
                    Button(action: { appState.selectFinding(f.id) }) {
                        HStack(spacing: AppSpacing.sm) {
                            SeverityBadge(severity: f.severity, compact: true)
                            Text(f.title)
                                .font(AppFont.caption())
                                .foregroundColor(f.id == finding.id ? AppColors.textPrimary : AppColors.textSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer()
                        }
                        .padding(AppSpacing.sm)
                        .background(f.id == finding.id ? AppColors.selectedBackground : Color.clear)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(AppSpacing.lg)
        }
        .background(AppColors.cardBackground)
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(AppFont.caption())
                .foregroundColor(AppColors.textSecondary)
            Text(value)
                .font(AppFont.subheading(13))
                .foregroundColor(AppColors.textPrimary)
        }
    }
}
