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
            infoRow("Environment", finding.environment ?? "--")
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
            // Screenshot/video frame
            if let snapshot = appState.screenSnapshots.last(where: { $0.screenshotPath != nil }),
               let path = snapshot.screenshotPath,
               let nsImage = NSImage(contentsOfFile: path) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 300)
                    .cornerRadius(12)
            } else {
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
            }

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

                Text("--:-- / --:--")
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
            // Show exploration action events if available
            let actions = appState.actionEvents
            if !actions.isEmpty {
                Text("Exploration Timeline (\(actions.count) actions)")
                    .font(AppFont.subheading())
                    .foregroundColor(AppColors.textPrimary)
                    .padding(.bottom, AppSpacing.xs)

                ForEach(actions, id: \.id) { action in
                    HStack(spacing: AppSpacing.md) {
                        Image(systemName: actionIcon(action.actionType))
                            .foregroundColor(action.result == "success" ? AppColors.success : AppColors.error)
                            .font(.system(size: 14))
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text("Step \(action.stepIndex)")
                                    .font(AppFont.mono(11))
                                    .foregroundColor(AppColors.textTertiary)
                                Text(action.actionType.capitalized)
                                    .font(AppFont.subheading())
                                    .foregroundColor(AppColors.textPrimary)
                            }
                            if let target = action.targetDescriptor, !target.isEmpty {
                                Text(target)
                                    .font(AppFont.caption())
                                    .foregroundColor(AppColors.textSecondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        Text(action.timestamp.formatted(date: .omitted, time: .standard))
                            .font(AppFont.mono(10))
                            .foregroundColor(AppColors.textTertiary)
                    }
                    .padding(.vertical, 2)
                }
            }

            // Also show phase events
            let events = appState.runPhaseEvents
            if !events.isEmpty {
                if !actions.isEmpty {
                    Divider().background(AppColors.border).padding(.vertical, AppSpacing.sm)
                    Text("Phase Events")
                        .font(AppFont.subheading())
                        .foregroundColor(AppColors.textPrimary)
                        .padding(.bottom, AppSpacing.xs)
                }
                ForEach(events, id: \.id) { event in
                    HStack(spacing: AppSpacing.md) {
                        Image(systemName: event.status == "completed" ? "checkmark.circle.fill" : (event.status == "failed" ? "xmark.circle.fill" : "circle"))
                            .foregroundColor(event.status == "completed" ? AppColors.success : (event.status == "failed" ? AppColors.error : AppColors.textTertiary))
                            .font(.system(size: 14))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.phase)
                                .font(AppFont.subheading())
                                .foregroundColor(AppColors.textPrimary)
                            Text(event.timestamp.formatted(date: .omitted, time: .standard))
                                .font(AppFont.caption())
                                .foregroundColor(AppColors.textSecondary)
                        }
                        Spacer()
                    }
                }
            }

            if actions.isEmpty && events.isEmpty {
                Text("No timeline data available")
                    .font(AppFont.caption())
                    .foregroundColor(AppColors.textTertiary)
            }
        }
        .cardStyle()
    }

    private func actionIcon(_ type: String) -> String {
        switch type.lowercased() {
        case "tap": return "hand.tap"
        case "type", "text": return "keyboard"
        case "scroll", "swipe": return "hand.draw"
        case "back": return "arrow.left"
        case "screenshot": return "camera"
        default: return "circle.fill"
        }
    }

    // MARK: - Environment Content
    private var environmentContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            envRow("Xcode Version", run?.xcodeVersion ?? "--")
            envRow("Simulator", run?.simulatorProfile ?? "--")
            envRow("Runtime", run?.resolvedRuntime ?? "--")
            envRow("Branch", run?.branch ?? "--")
            envRow("Commit", run?.commitSha ?? "--")
            envRow("Runner", run?.runnerId ?? "--")
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
            let logArtifacts = appState.artifacts.filter { $0.type == "build_log" || $0.type == "test_log" || $0.type == "device_log" }
            if logArtifacts.isEmpty {
                Text("No log data available")
                    .font(AppFont.caption())
                    .foregroundColor(AppColors.textTertiary)
                    .padding(AppSpacing.md)
            } else {
                ForEach(logArtifacts, id: \.id) { artifact in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(artifact.type)
                            .font(AppFont.subheading(12))
                            .foregroundColor(AppColors.accentBlue)
                        let logContent = (try? String(contentsOfFile: artifact.path, encoding: .utf8))?.suffix(2000) ?? "Unable to read log"
                        Text(String(logContent))
                            .font(AppFont.mono(11))
                            .foregroundColor(AppColors.textSecondary)
                            .padding(.vertical, 1)
                            .lineLimit(50)
                    }
                    .padding(.bottom, AppSpacing.sm)
                }
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
            let realArtifacts = appState.artifacts
            if realArtifacts.isEmpty {
                Text("No artifacts available")
                    .font(AppFont.caption())
                    .foregroundColor(AppColors.textTertiary)
            } else {
                ForEach(realArtifacts, id: \.id) { artifact in
                    HStack(spacing: AppSpacing.md) {
                        Image(systemName: artifactIcon(artifact.type))
                            .foregroundColor(AppColors.accentBlue)
                            .frame(width: 20)
                        Text(artifact.type)
                            .font(AppFont.body())
                            .foregroundColor(AppColors.textPrimary)
                        Spacer()
                        let size = fileSize(artifact.path)
                        Text(size)
                            .font(AppFont.caption())
                            .foregroundColor(AppColors.textSecondary)
                        Button(action: { NSWorkspace.shared.selectFile(artifact.path, inFileViewerRootedAtPath: "") }) {
                            Image(systemName: "arrow.down.circle")
                                .foregroundColor(AppColors.accentBlue)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, AppSpacing.xs)
                }
            }
        }
        .cardStyle()
    }

    private func artifactIcon(_ type: String) -> String {
        switch type {
        case "screenshot": return "photo"
        case "build_log", "test_log", "device_log": return "doc.text"
        case "xcresult": return "folder"
        default: return "doc"
        }
    }

    private func fileSize(_ path: String) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let bytes = attrs[.size] as? Int64 else { return "--" }
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1048576 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1048576.0)
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
                    Text(finding.impact ?? "No impact assessment available.")
                        .font(AppFont.caption())
                        .foregroundColor(AppColors.textSecondary)
                        .lineSpacing(3)
                }

                Divider().background(AppColors.border)

                // Affected Builds
                metaRow("Affected Builds", finding.affectedBuilds ?? "--")
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
