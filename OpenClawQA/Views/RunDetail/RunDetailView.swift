import SwiftUI
import AVKit

struct RunDetailView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedDetailTab: String = "Overview"
    @State private var videoPlayer: AVPlayer?
    @State private var loadedVideoPath: String?

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
                        // Run summary section
                        runSummarySection

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

            // Right panel - findings list & detail
            findingsPanel
                .frame(width: 320)
        }
        .background(AppColors.windowBackground)
        .onChange(of: appState.artifacts.count) { _ in
            loadVideoPlayerIfNeeded()
        }
        .onAppear {
            loadVideoPlayerIfNeeded()
        }
    }

    private func loadVideoPlayerIfNeeded() {
        if let videoArtifact = appState.artifacts.first(where: { $0.type == "video" }),
           FileManager.default.fileExists(atPath: videoArtifact.path),
           loadedVideoPath != videoArtifact.path {
            loadedVideoPath = videoArtifact.path
            videoPlayer = AVPlayer(url: URL(fileURLWithPath: videoArtifact.path))
            videoPlayer?.pause()
        }
    }

    // MARK: - Run Summary
    private var runSummarySection: some View {
        VStack(spacing: AppSpacing.lg) {
            // Release Readiness Banner
            if let run = run {
                HStack(spacing: AppSpacing.lg) {
                    // Confidence score
                    VStack(spacing: AppSpacing.xs) {
                        Text("\(run.confidenceScore ?? 0)")
                            .font(AppFont.statValue(48))
                            .foregroundColor(confidenceColor(run.confidenceScore ?? 0))
                        Text("Confidence")
                            .font(AppFont.caption())
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .frame(width: 100)

                    // Readiness badge
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: readinessIcon(run.releaseReadiness))
                                .font(.system(size: 20))
                                .foregroundColor(readinessColor(run.releaseReadiness))
                            Text(readinessLabel(run.releaseReadiness))
                                .font(AppFont.heading(20))
                                .foregroundColor(readinessColor(run.releaseReadiness))
                        }
                        Text(readinessDescription(run))
                            .font(AppFont.body())
                            .foregroundColor(AppColors.textSecondary)
                    }

                    Spacer()

                    // Quick stats
                    VStack(alignment: .trailing, spacing: AppSpacing.sm) {
                        HStack(spacing: AppSpacing.lg) {
                            statPill("Actions", "\(run.testsExecuted)", AppColors.accentBlue)
                            statPill("Screens", "\(run.flowsExplored)", AppColors.success)
                            statPill("Duration", run.durationFormatted, AppColors.textSecondary)
                        }
                        HStack(spacing: AppSpacing.lg) {
                            if run.criticalFindings > 0 { statPill("Critical", "\(run.criticalFindings)", AppColors.critical) }
                            if run.highFindings > 0 { statPill("High", "\(run.highFindings)", AppColors.high) }
                            if run.mediumFindings > 0 { statPill("Medium", "\(run.mediumFindings)", AppColors.medium) }
                            if run.lowFindings > 0 { statPill("Low", "\(run.lowFindings)", AppColors.low) }
                            if findings.isEmpty { statPill("Issues", "None", AppColors.success) }
                        }
                    }
                }
                .padding(AppSpacing.lg)
                .background(readinessColor(run.releaseReadiness).opacity(0.08))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(readinessColor(run.releaseReadiness).opacity(0.3), lineWidth: 1)
                )
            } else if appState.isRunning {
                // Running state
                HStack(spacing: AppSpacing.lg) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(width: 60)
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("Run In Progress")
                            .font(AppFont.heading(20))
                            .foregroundColor(AppColors.textPrimary)
                        Text(appState.currentPhaseDetail)
                            .font(AppFont.body())
                            .foregroundColor(AppColors.textSecondary)
                        // Phase badge
                        Text(appState.currentPhase.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(AppFont.mono(11))
                            .foregroundColor(AppColors.running)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AppColors.running.opacity(0.15))
                            .cornerRadius(4)
                    }
                    Spacer()
                }
                .padding(AppSpacing.lg)
                .background(AppColors.running.opacity(0.08))
                .cornerRadius(12)
            }

            // Environment info bar
            if let run = run, run.status == .completed || run.status == .failed {
                HStack(spacing: AppSpacing.xl) {
                    envChip("arrow.triangle.branch", run.branch)
                    if let sha = run.commitSha { envChip("number", String(sha.prefix(7))) }
                    if let xc = run.xcodeVersion { envChip("hammer", "Xcode \(xc)") }
                    if let sim = run.simulatorProfile { envChip("iphone", sim) }
                    Spacer()
                }
            }
        }
    }

    private func statPill(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(AppFont.subheading(14))
                .foregroundColor(color)
            Text(label)
                .font(AppFont.caption(10))
                .foregroundColor(AppColors.textTertiary)
        }
    }

    private func envChip(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(AppColors.textTertiary)
            Text(text)
                .font(AppFont.mono(11))
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(AppColors.inputBackground)
        .cornerRadius(4)
    }

    private func confidenceColor(_ score: Int) -> Color {
        if score >= 85 { return AppColors.success }
        if score >= 70 { return AppColors.warning }
        return AppColors.critical
    }

    private func readinessIcon(_ readiness: ReleaseReadiness?) -> String {
        switch readiness {
        case .ready: return "checkmark.shield.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .blocked: return "xmark.shield.fill"
        case nil: return "questionmark.circle"
        }
    }

    private func readinessColor(_ readiness: ReleaseReadiness?) -> Color {
        switch readiness {
        case .ready: return AppColors.success
        case .caution: return AppColors.warning
        case .blocked: return AppColors.critical
        case nil: return AppColors.textTertiary
        }
    }

    private func readinessLabel(_ readiness: ReleaseReadiness?) -> String {
        switch readiness {
        case .ready: return "Release Ready"
        case .caution: return "Review Recommended"
        case .blocked: return "Release Blocked"
        case nil: return "Pending"
        }
    }

    private func readinessDescription(_ run: QARun) -> String {
        let total = run.criticalFindings + run.highFindings + run.mediumFindings + run.lowFindings
        if total == 0 {
            return "No issues found. \(run.testsExecuted) actions executed across \(run.flowsExplored) screens."
        }
        var parts: [String] = []
        if run.criticalFindings > 0 { parts.append("\(run.criticalFindings) critical") }
        if run.highFindings > 0 { parts.append("\(run.highFindings) high") }
        if run.mediumFindings > 0 { parts.append("\(run.mediumFindings) medium") }
        if run.lowFindings > 0 { parts.append("\(run.lowFindings) low") }
        return "\(total) issue\(total == 1 ? "" : "s") found: \(parts.joined(separator: ", ")). \(run.testsExecuted) actions across \(run.flowsExplored) screens."
    }

    // MARK: - Findings Panel (right side)
    private var findingsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                Text("Findings (\(findings.count))")
                    .font(AppFont.heading(16))
                    .foregroundColor(AppColors.textPrimary)

                if findings.isEmpty {
                    VStack(spacing: AppSpacing.md) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 32))
                            .foregroundColor(AppColors.success)
                        Text("No issues found")
                            .font(AppFont.subheading())
                            .foregroundColor(AppColors.textSecondary)
                        Text("The exploration completed without detecting any issues.")
                            .font(AppFont.caption())
                            .foregroundColor(AppColors.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.xl)
                } else {
                    // Group build warnings together to avoid clutter
                    let buildWarnings = findings.filter { $0.category == .buildFailure && $0.severity == .low }
                    let runtimeFindings = findings.filter { !($0.category == .buildFailure && $0.severity == .low) }

                    // Show runtime findings first (ungrouped)
                    ForEach(runtimeFindings) { finding in
                        findingRow(finding)
                    }

                    // Collapsed build warnings group
                    if !buildWarnings.isEmpty {
                        buildWarningsGroup(buildWarnings)
                    }
                }

                // Selected finding detail
                if let finding = selectedFinding {
                    Divider().background(AppColors.border)

                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        Text(finding.title)
                            .font(AppFont.heading(14))
                            .foregroundColor(AppColors.textPrimary)

                        Text(finding.summary)
                            .font(AppFont.body())
                            .foregroundColor(AppColors.textSecondary)
                            .lineSpacing(3)

                        if let steps = finding.reproSteps {
                            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                Text("Reproduction Steps")
                                    .font(AppFont.caption())
                                    .foregroundColor(AppColors.textTertiary)
                                Text(steps)
                                    .font(AppFont.mono(11))
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }

                        HStack(spacing: AppSpacing.lg) {
                            metaRow("Flow", finding.flow ?? "--")
                            metaRow("Screen", finding.screen ?? "--")
                            metaRow("State", finding.status.rawValue.capitalized)
                        }
                    }
                }
            }
            .padding(AppSpacing.lg)
        }
        .background(AppColors.cardBackground)
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

    // MARK: - Finding Header (used in analysis tab)
    private func findingHeader(_ finding: QAFinding) -> some View {
        HStack(spacing: AppSpacing.md) {
            Text(finding.title)
                .font(AppFont.heading(16))
                .foregroundColor(AppColors.textPrimary)
            SeverityBadge(severity: finding.severity)
            Spacer()
        }
    }

    // MARK: - Video Player
    private var videoPlayerArea: some View {
        VStack(spacing: 0) {
            // Check for video artifact first
            if let player = videoPlayer {
                VideoPlayer(player: player)
                    .frame(maxHeight: 400)
                    .cornerRadius(12)
            }
            // Fall back to screenshot if available
            else if let snapshot = appState.screenSnapshots.last(where: { $0.screenshotPath != nil }),
               let path = snapshot.screenshotPath,
               let nsImage = NSImage(contentsOfFile: path) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 300)
                    .cornerRadius(12)
            } else if !appState.isRunning {
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

            // Screenshot gallery strip
            let screenshotSnapshots = appState.screenSnapshots.filter { $0.screenshotPath != nil }
            if !screenshotSnapshots.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.sm) {
                        ForEach(screenshotSnapshots, id: \.id) { snap in
                            if let path = snap.screenshotPath, let nsImage = NSImage(contentsOfFile: path) {
                                VStack(spacing: 2) {
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 60, height: 100)
                                        .cornerRadius(6)
                                        .clipped()
                                    Text("Step \(snap.stepIndex)")
                                        .font(AppFont.mono(9))
                                        .foregroundColor(AppColors.textTertiary)
                                }
                            }
                        }
                    }
                    .padding(.vertical, AppSpacing.sm)
                }
            }
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

    // MARK: - Analysis Content
    private var analysisContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            if let finding = selectedFinding {
                findingHeader(finding)

                // Summary
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("Summary")
                        .font(AppFont.heading(14))
                        .foregroundColor(AppColors.textPrimary)
                    Text(finding.summary)
                        .font(AppFont.body())
                        .foregroundColor(AppColors.textSecondary)
                        .lineSpacing(4)
                }
                .cardStyle()

                // AI Analysis
                if let analysis = finding.aiAnalysis {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("AI Analysis")
                            .font(AppFont.heading(14))
                            .foregroundColor(AppColors.textPrimary)
                        Text(analysis)
                            .font(AppFont.body())
                            .foregroundColor(AppColors.textSecondary)
                            .lineSpacing(4)
                    }
                    .cardStyle()
                }

                // Suggested Fix
                if let fix = finding.suggestedFix {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("Suggested Fix")
                            .font(AppFont.heading(14))
                            .foregroundColor(AppColors.textPrimary)
                        Text(fix)
                            .font(AppFont.body())
                            .foregroundColor(AppColors.textSecondary)
                            .lineSpacing(4)
                    }
                    .cardStyle()
                }
            } else {
                // Run overview when no finding selected
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    Text("Run Overview")
                        .font(AppFont.heading(16))
                        .foregroundColor(AppColors.textPrimary)

                    if let run = run {
                        let total = run.criticalFindings + run.highFindings + run.mediumFindings + run.lowFindings
                        if total == 0 {
                            HStack(spacing: AppSpacing.md) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(AppColors.success)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Clean Run")
                                        .font(AppFont.heading(16))
                                        .foregroundColor(AppColors.success)
                                    Text("The autonomous exploration completed \(run.testsExecuted) actions across \(run.flowsExplored) screens without detecting any issues.")
                                        .font(AppFont.body())
                                        .foregroundColor(AppColors.textSecondary)
                                }
                            }
                            .cardStyle()
                        } else {
                            Text("Select a finding from the panel on the right to see details.")
                                .font(AppFont.body())
                                .foregroundColor(AppColors.textSecondary)
                        }

                        // Exploration stats
                        HStack(spacing: AppSpacing.xl) {
                            explorationStat("Actions Executed", "\(run.testsExecuted)")
                            explorationStat("Screens Discovered", "\(run.flowsExplored)")
                            explorationStat("Coverage", "\(Int(run.coveragePercent))%")
                            explorationStat("Issues Found", "\(total)")
                        }
                        .cardStyle()
                    }
                }
            }
        }
    }

    private func explorationStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: AppSpacing.xs) {
            Text(value)
                .font(AppFont.statValue(28))
                .foregroundColor(AppColors.textPrimary)
            Text(label)
                .font(AppFont.caption())
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
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
            let logArtifacts = appState.artifacts.filter { $0.type == "build_log" || $0.type == "test_log" || $0.type == "device_log" || $0.type == "exploration_log" }
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
        case "video": return "video"
        case "build_log", "test_log", "device_log", "exploration_log": return "doc.text"
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

    // MARK: - Finding Row
    private func findingRow(_ finding: QAFinding) -> some View {
        Button(action: { appState.selectFinding(finding.id) }) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(spacing: AppSpacing.sm) {
                    SeverityBadge(severity: finding.severity, compact: true)
                    Text(finding.category.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(AppFont.caption(10))
                        .foregroundColor(AppColors.textTertiary)
                    Spacer()
                }
                Text(finding.title)
                    .font(AppFont.subheading(13))
                    .foregroundColor(finding.id == appState.selectedFindingId ? AppColors.textPrimary : AppColors.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let screen = finding.screen {
                    Text("Screen: \(screen)")
                        .font(AppFont.caption(10))
                        .foregroundColor(AppColors.textTertiary)
                }
            }
            .padding(AppSpacing.md)
            .background(finding.id == appState.selectedFindingId ? AppColors.selectedBackground : AppColors.inputBackground)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Build Warnings Group
    @State private var showBuildWarnings: Bool = false

    private func buildWarningsGroup(_ warnings: [QAFinding]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Button(action: { showBuildWarnings.toggle() }) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: showBuildWarnings ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textTertiary)
                    SeverityBadge(severity: .low, compact: true)
                    Text("Build Warnings")
                        .font(AppFont.subheading(13))
                        .foregroundColor(AppColors.textSecondary)
                    Spacer()
                    Text("\(warnings.count)")
                        .font(AppFont.mono(12))
                        .foregroundColor(AppColors.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(AppColors.inputBackground)
                        .cornerRadius(4)
                }
                .padding(AppSpacing.md)
                .background(AppColors.inputBackground)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            if showBuildWarnings {
                ForEach(warnings) { warning in
                    findingRow(warning)
                        .padding(.leading, AppSpacing.md)
                }
            }
        }
    }
}
