import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                // Header
                overviewHeader
                // Stats Row
                statsRow
                // Main Content Grid
                HStack(alignment: .top, spacing: AppSpacing.xl) {
                    // Left column
                    VStack(spacing: AppSpacing.xl) {
                        recentRunSection
                        coverageSection
                    }
                    .frame(maxWidth: .infinity)

                    // Right column
                    VStack(spacing: AppSpacing.xl) {
                        findingsSummarySection
                        trendSection
                    }
                    .frame(width: 320)
                }
            }
            .padding(AppSpacing.xl)
        }
        .background(AppColors.windowBackground)
    }

    // MARK: - Header
    private var overviewHeader: some View {
        HStack {
            Text("Overview")
                .font(AppFont.title())
                .foregroundColor(AppColors.textPrimary)

            Spacer()

            if let run = appState.latestRun {
                HStack(spacing: AppSpacing.sm) {
                    Text("Last run:")
                        .font(AppFont.caption())
                        .foregroundColor(AppColors.textSecondary)
                    Text(run.startedAt?.formatted(date: .abbreviated, time: .shortened) ?? "--")
                        .font(AppFont.caption())
                        .foregroundColor(AppColors.textSecondary)

                    if run.status == .completed {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(AppColors.success)
                                .font(.system(size: 12))
                            Text("Completed")
                                .font(AppFont.caption())
                                .foregroundColor(AppColors.success)
                        }
                    }
                }
            }

            Button(action: { appState.startNewRun() }) {
                HStack(spacing: 6) {
                    if appState.isRunning {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                    }
                    Text(appState.isRunning ? appState.currentPhaseDetail : "Run New Check")
                        .font(AppFont.subheading(13))
                        .lineLimit(1)
                }
                .foregroundColor(.white)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
                .background(appState.isRunning ? AppColors.warning : AppColors.accentBlue)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(appState.isRunning)

            Button(action: {}) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.textSecondary)
                    .padding(AppSpacing.sm)
                    .background(AppColors.inputBackground)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Stats Row
    private var statsRow: some View {
        HStack(spacing: AppSpacing.lg) {
            if let run = appState.latestRun {
                StatCardView(
                    title: "Release Confidence",
                    value: "\(run.confidenceScore ?? 0)%",
                    subtitle: run.releaseReadiness == .ready ? "Ready to Ship 🚀" : "Review Recommended",
                    valueColor: run.confidenceScore ?? 0 >= 85 ? AppColors.success : AppColors.warning,
                    showProgress: true, progress: Double(run.confidenceScore ?? 0) / 100.0,
                    progressColor: run.confidenceScore ?? 0 >= 85 ? AppColors.success : AppColors.warning
                )

                StatCardView(
                    title: "Critical Issues",
                    value: "\(run.criticalFindings)",
                    subtitle: run.criticalFindings > 0 ? "Needs Attention" : "None",
                    valueColor: run.criticalFindings > 0 ? AppColors.critical : AppColors.success,
                    subtitleColor: run.criticalFindings > 0 ? AppColors.critical : AppColors.textSecondary
                )

                StatCardView(
                    title: "High Issues",
                    value: "\(run.highFindings)",
                    subtitle: run.highFindings > 0 ? "Review Recommended" : "None",
                    valueColor: run.highFindings > 0 ? AppColors.high : AppColors.success
                )

                StatCardView(
                    title: "Tests Executed",
                    value: "\(run.testsExecuted)",
                    subtitle: "Across \(run.flowsExplored) flows",
                    valueColor: AppColors.textPrimary
                )

                StatCardView(
                    title: "Duration",
                    value: run.durationFormatted,
                    subtitle: run.simulatorProfile ?? "iPhone 16 Pro",
                    valueColor: AppColors.textPrimary
                )
            }
        }
    }

    // MARK: - Recent Run
    private var recentRunSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                Text("Recent Run")
                    .font(AppFont.heading(16))
                    .foregroundColor(AppColors.textPrimary)
                if let run = appState.latestRun {
                    Circle().fill(run.status == .completed ? AppColors.success : (run.status == .failed ? AppColors.error : AppColors.warning)).frame(width: 6, height: 6)
                    Text(run.startedAt?.formatted(date: .abbreviated, time: .shortened) ?? "--")
                        .font(AppFont.caption())
                        .foregroundColor(AppColors.textSecondary)
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textSecondary)
                    Text("Triggered by \(run.triggerSource)")
                        .font(AppFont.caption())
                        .foregroundColor(AppColors.textSecondary)
                }
                Spacer()
            }

            // Screenshot gallery
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.md) {
                    let screenshots = explorationScreenshots
                    if screenshots.isEmpty {
                        ForEach(demoScreenshots, id: \.0) { screen in
                            VStack(spacing: AppSpacing.xs) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(AppColors.inputBackground)
                                    .frame(width: 120, height: 220)
                                    .overlay(
                                        VStack(spacing: 4) {
                                            Image(systemName: "iphone")
                                                .font(.system(size: 24))
                                                .foregroundColor(AppColors.textTertiary)
                                            Text(screen.1)
                                                .font(AppFont.caption(10))
                                                .foregroundColor(AppColors.textTertiary)
                                        }
                                    )
                                Text(screen.2)
                                    .font(AppFont.mono(10))
                                    .foregroundColor(AppColors.textTertiary)
                            }
                        }
                    } else {
                        ForEach(screenshots, id: \.id) { snapshot in
                            VStack(spacing: AppSpacing.xs) {
                                if let path = snapshot.screenshotPath,
                                   let nsImage = NSImage(contentsOfFile: path) {
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 120, height: 220)
                                        .cornerRadius(8)
                                } else {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(AppColors.inputBackground)
                                        .frame(width: 120, height: 220)
                                        .overlay(
                                            VStack(spacing: 4) {
                                                Image(systemName: "iphone")
                                                    .font(.system(size: 24))
                                                    .foregroundColor(AppColors.textTertiary)
                                                Text(snapshot.screenClassification ?? "Screen")
                                                    .font(AppFont.caption(10))
                                                    .foregroundColor(AppColors.textTertiary)
                                            }
                                        )
                                }
                                Text(snapshot.screenClassification ?? "Step \(snapshot.stepIndex)")
                                    .font(AppFont.mono(10))
                                    .foregroundColor(AppColors.textTertiary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .cardStyle()
    }

    private var demoScreenshots: [(String, String, String)] {
        guard let run = appState.latestRun, run.status == .completed else { return [] }
        // Show screens based on actual coverage
        let screens = ["Launch", "Login", "Home", "Feed", "Profile", "Settings"]
        let explored = min(screens.count, run.flowsExplored)
        return (0..<explored).map { i in
            ("\(i+1)", screens[i], String(format: "%02d:%02d", i * 5, i * 7))
        }
    }

    // Real screenshots from exploration, deduplicated by screen name (one per unique screen)
    private var explorationScreenshots: [ScreenSnapshot] {
        let snapshots = appState.screenSnapshots
        guard !snapshots.isEmpty else { return [] }
        var seen = Set<String>()
        var result: [ScreenSnapshot] = []
        for s in snapshots {
            let key = s.screenClassification ?? s.screenFingerprint
            if !seen.contains(key) {
                seen.insert(key)
                result.append(s)
            }
        }
        return result
    }

    // MARK: - Coverage
    private var coverageSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Coverage")
                .font(AppFont.heading(16))
                .foregroundColor(AppColors.textPrimary)

            HStack(alignment: .top, spacing: AppSpacing.xl) {
                // Percentage
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("\(Int(appState.latestRun?.coveragePercent ?? 87))%")
                        .font(AppFont.statValue(48))
                        .foregroundColor(AppColors.success)
                    Text("of app surface explored")
                        .font(AppFont.caption())
                        .foregroundColor(AppColors.textSecondary)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(AppColors.inputBackground)
                                .frame(height: 8)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(AppColors.success)
                                .frame(width: geo.size.width * (appState.latestRun?.coveragePercent ?? 87) / 100, height: 8)
                        }
                    }
                    .frame(height: 8)
                }
                .frame(width: 200)

                // Mini coverage chart placeholder
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    let cov = appState.latestRun?.coveragePercent ?? 0
                    coverageMiniBar("Screens", value: min(1.0, cov / 100))
                    coverageMiniBar("Flows", value: min(1.0, cov * 0.9 / 100))
                    coverageMiniBar("Actions", value: min(1.0, cov * 0.8 / 100))
                    coverageMiniBar("States", value: min(1.0, cov * 0.7 / 100))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .cardStyle()
    }

    private func coverageMiniBar(_ label: String, value: Double) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Text(label)
                .font(AppFont.caption())
                .foregroundColor(AppColors.textSecondary)
                .frame(width: 60, alignment: .trailing)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(AppColors.inputBackground)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(AppColors.success.opacity(0.7))
                        .frame(width: geo.size.width * value, height: 6)
                }
            }
            .frame(height: 6)
            Text("\(Int(value * 100))%")
                .font(AppFont.mono(10))
                .foregroundColor(AppColors.textSecondary)
                .frame(width: 32)
        }
    }

    // MARK: - Findings Summary
    private var findingsSummarySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Findings Summary")
                .font(AppFont.heading(16))
                .foregroundColor(AppColors.textPrimary)

            if let run = appState.latestRun {
                VStack(spacing: AppSpacing.sm) {
                    findingRow(severity: "Critical", count: run.criticalFindings, color: AppColors.critical)
                    findingRow(severity: "High", count: run.highFindings, color: AppColors.high)
                    findingRow(severity: "Medium", count: run.mediumFindings, color: AppColors.medium)
                    findingRow(severity: "Low", count: run.lowFindings, color: AppColors.low)
                    findingRow(severity: "Flaky", count: 0, color: AppColors.textTertiary)
                }
            }

            Button(action: { appState.selectedTab = .findings }) {
                HStack(spacing: 4) {
                    Text("View All Findings")
                        .font(AppFont.subheading(13))
                        .foregroundColor(AppColors.accentBlue)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.accentBlue)
                }
            }
            .buttonStyle(.plain)
        }
        .cardStyle()
    }

    private func findingRow(severity: String, count: Int, color: Color) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(count)")
                .font(AppFont.subheading(14))
                .foregroundColor(AppColors.textPrimary)
                .frame(width: 24, alignment: .leading)
            Text(severity)
                .font(AppFont.body())
                .foregroundColor(AppColors.textSecondary)
            Spacer()
        }
    }

    // MARK: - Trend
    private var trendSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                Text("Trend")
                    .font(AppFont.heading(16))
                    .foregroundColor(AppColors.textPrimary)
                Text("(Last 14 Runs)")
                    .font(AppFont.caption())
                    .foregroundColor(AppColors.textSecondary)
            }

            // Simple trend chart
            TrendChartView()
                .frame(height: 120)

            // Legend
            HStack(spacing: AppSpacing.lg) {
                legendItem("Confidence", color: AppColors.chartGreen)
                legendItem("Critical", color: AppColors.chartRed)
                legendItem("High", color: AppColors.chartOrange)
            }
        }
        .cardStyle()
    }

    private func legendItem(_ label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(AppFont.caption(10))
                .foregroundColor(AppColors.textSecondary)
        }
    }
}

// MARK: - Stat Card
struct StatCardView: View {
    let title: String
    let value: String
    var subtitle: String = ""
    var valueColor: Color = AppColors.textPrimary
    var subtitleColor: Color = AppColors.textSecondary
    var showProgress: Bool = false
    var progress: Double = 0
    var progressColor: Color = AppColors.success

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(title)
                .font(AppFont.caption())
                .foregroundColor(AppColors.textSecondary)

            Text(value)
                .font(AppFont.statValue(32))
                .foregroundColor(valueColor)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(AppFont.caption())
                    .foregroundColor(subtitleColor)
            }

            if showProgress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(AppColors.inputBackground)
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(progressColor)
                            .frame(width: geo.size.width * progress, height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: AppSpacing.md)
    }
}

// MARK: - Trend Chart
struct TrendChartView: View {
    @EnvironmentObject var appState: AppState

    var confidenceData: [Double] {
        let runs = Array(appState.runs.reversed().suffix(14))
        if runs.isEmpty { return [] }
        return runs.map { Double($0.confidenceScore ?? 0) }
    }

    var criticalData: [Double] {
        let runs = Array(appState.runs.reversed().suffix(14))
        if runs.isEmpty { return [] }
        return runs.map { Double($0.criticalFindings) }
    }

    var highData: [Double] {
        let runs = Array(appState.runs.reversed().suffix(14))
        if runs.isEmpty { return [] }
        return runs.map { Double($0.highFindings) }
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            if confidenceData.isEmpty {
                VStack {
                    Spacer()
                    Text("No run data yet")
                        .font(AppFont.caption())
                        .foregroundColor(AppColors.textTertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ZStack {
                    ForEach(0..<4) { i in
                        let y = h * Double(i) / 3.0
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: w, y: y))
                        }
                        .stroke(AppColors.border.opacity(0.3), lineWidth: 0.5)
                    }

                    chartLine(data: confidenceData, maxVal: 100, color: AppColors.chartGreen, size: geo.size)
                    chartLine(data: criticalData.map { $0 * 10 }, maxVal: 100, color: AppColors.chartRed, size: geo.size, dashed: true)
                    chartLine(data: highData.map { $0 * 10 }, maxVal: 100, color: AppColors.chartOrange, size: geo.size, dashed: true)
                }
            }
        }
    }

    private func chartLine(data: [Double], maxVal: Double, color: Color, size: CGSize, dashed: Bool = false) -> some View {
        Path { path in
            guard data.count > 1 else { return }
            let stepX = size.width / Double(data.count - 1)
            for (i, val) in data.enumerated() {
                let x = Double(i) * stepX
                let y = size.height * (1 - val / maxVal)
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
        }
        .stroke(color, style: StrokeStyle(lineWidth: 1.5, dash: dashed ? [4, 3] : []))
    }
}
