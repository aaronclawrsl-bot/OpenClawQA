import SwiftUI

struct InsightsView: View {
    @EnvironmentObject var appState: AppState
    @State private var timePeriod: String = "Last 14 Days"

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                // Header
                HStack {
                    Text("Insights")
                        .font(AppFont.title())
                        .foregroundColor(AppColors.textPrimary)
                    Spacer()

                    Menu {
                        Button("Last 7 Days") { timePeriod = "Last 7 Days" }
                        Button("Last 14 Days") { timePeriod = "Last 14 Days" }
                        Button("Last 30 Days") { timePeriod = "Last 30 Days" }
                    } label: {
                        HStack(spacing: 4) {
                            Text(timePeriod)
                                .font(AppFont.body())
                                .foregroundColor(AppColors.textSecondary)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9))
                                .foregroundColor(AppColors.textTertiary)
                        }
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, 6)
                        .background(AppColors.inputBackground)
                        .cornerRadius(6)
                    }
                    .menuStyle(.borderlessButton)
                }

                // Stats grid
                HStack(spacing: AppSpacing.lg) {
                    let confTrend = computeConfidenceTrend()
                    let totalFindings = appState.findings.count
                    let avgDuration = computeAvgDuration()

                    insightStatCard(
                        title: "Release Confidence Trend",
                        value: confTrend >= 0 ? "+\(confTrend)%" : "\(confTrend)%",
                        valueColor: confTrend >= 0 ? AppColors.success : AppColors.error,
                        icon: confTrend >= 0 ? "arrow.up.right" : "arrow.down.right"
                    )
                    insightStatCard(
                        title: "Bugs Found",
                        value: "\(totalFindings)",
                        valueColor: totalFindings > 0 ? AppColors.error : AppColors.success,
                        icon: "ladybug"
                    )
                    insightStatCard(
                        title: "Avg. Run Time",
                        value: avgDuration,
                        valueColor: AppColors.accentBlue,
                        icon: "clock"
                    )
                    insightStatCard(
                        title: "Total Runs",
                        value: "\(appState.runs.count)",
                        valueColor: AppColors.warning,
                        icon: "play.circle"
                    )
                }

                // Bottom row
                HStack(alignment: .top, spacing: AppSpacing.xl) {
                    // Top Issue Categories
                    topIssueCategoriesCard
                        .frame(maxWidth: .infinity)

                    // Recent Activity
                    recentActivityCard
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(AppSpacing.xl)
        }
        .background(AppColors.windowBackground)
    }

    // MARK: - Stat Card
    private func insightStatCard(title: String, value: String, valueColor: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(title)
                .font(AppFont.caption())
                .foregroundColor(AppColors.textSecondary)

            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                Text(value)
                    .font(AppFont.statValue(36))
                    .foregroundColor(valueColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: AppSpacing.lg)
    }

    // MARK: - Top Issue Categories
    private var topIssueCategoriesCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            Text("Top Issue Categories")
                .font(AppFont.heading(16))
                .foregroundColor(AppColors.textPrimary)

            VStack(spacing: AppSpacing.md) {
                let cats = computeIssueCategories()
                let maxC = cats.map(\.1).max() ?? 1
                ForEach(cats, id: \.0) { cat in
                    issueCategoryBar(cat.0, count: cat.1, maxCount: max(1, maxC), color: categoryColor(cat.0))
                }
                if cats.isEmpty {
                    Text("No findings yet")
                        .font(AppFont.caption())
                        .foregroundColor(AppColors.textTertiary)
                }
            }
        }
        .cardStyle()
    }

    private func issueCategoryBar(_ label: String, count: Int, maxCount: Int, color: Color) -> some View {
        HStack(spacing: AppSpacing.md) {
            Text(label)
                .font(AppFont.body())
                .foregroundColor(AppColors.textSecondary)
                .frame(width: 100, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.inputBackground)
                        .frame(height: 16)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: max(4, geo.size.width * Double(count) / Double(maxCount)), height: 16)
                }
            }
            .frame(height: 16)

            Text("\(count)")
                .font(AppFont.subheading())
                .foregroundColor(AppColors.textPrimary)
                .frame(width: 30, alignment: .trailing)
        }
    }

    // MARK: - Recent Activity
    private var recentActivityCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            Text("Recent Activity")
                .font(AppFont.heading(16))
                .foregroundColor(AppColors.textPrimary)

            VStack(spacing: AppSpacing.md) {
                let activities = computeRecentActivity()
                ForEach(activities, id: \.0) { activity in
                    activityRow(activity.0, activity.1)
                }
                if activities.isEmpty {
                    Text("No activity yet")
                        .font(AppFont.caption())
                        .foregroundColor(AppColors.textTertiary)
                }
            }

            Button(action: {}) {
                Text("View All Insights")
                    .font(AppFont.subheading(13))
                    .foregroundColor(AppColors.accentBlue)
            }
            .buttonStyle(.plain)
        }
        .cardStyle()
    }

    private func activityRow(_ time: String, _ description: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            Text(time)
                .font(AppFont.caption())
                .foregroundColor(AppColors.textTertiary)
                .frame(width: 120, alignment: .leading)
            Text(description)
                .font(AppFont.body())
                .foregroundColor(AppColors.textSecondary)
            Spacer()
        }
    }

    // MARK: - Computed Insights

    private func computeConfidenceTrend() -> Int {
        let runs = appState.runs.prefix(10)
        guard runs.count >= 2 else { return 0 }
        let latest = runs.first?.confidenceScore ?? 0
        let previous = runs.dropFirst().first?.confidenceScore ?? 0
        return latest - previous
    }

    private func computeAvgDuration() -> String {
        let completedRuns = appState.runs.filter { $0.status == .completed && $0.durationMs != nil }
        guard !completedRuns.isEmpty else { return "--" }
        let avg = completedRuns.compactMap(\.durationMs).reduce(0, +) / completedRuns.count
        let minutes = avg / 60000
        return "\(minutes)m"
    }

    private func computeIssueCategories() -> [(String, Int)] {
        var cats: [String: Int] = [:]
        for f in appState.findings {
            let cat = categorizeForInsight(f.category)
            cats[cat, default: 0] += 1
        }
        return cats.sorted { $0.value > $1.value }
    }

    private func categorizeForInsight(_ category: FindingCategory) -> String {
        switch category {
        case .buildFailure, .launchFailure, .crash, .deterministicCheckFailure, .authFailure:
            return "Functional"
        case .layoutOverlap, .textClipping, .missingAsset, .blankScreen, .visualRegression:
            return "UI / Layout"
        case .performanceTimeout, .appHang:
            return "Performance"
        default:
            return "Other"
        }
    }

    private func categoryColor(_ name: String) -> Color {
        switch name {
        case "Functional": return AppColors.critical
        case "UI / Layout": return AppColors.high
        case "Performance": return AppColors.warning
        default: return AppColors.textTertiary
        }
    }

    private func computeRecentActivity() -> [(String, String)] {
        return appState.runs.prefix(5).map { run in
            let time = run.startedAt?.formatted(date: .abbreviated, time: .shortened) ?? "--"
            let desc: String
            if run.status == .completed {
                desc = "QA check completed on \(run.branch) — \(run.criticalFindings) critical, \(run.highFindings) high"
            } else if run.status == .failed {
                desc = "Run failed on \(run.branch)"
            } else {
                desc = "Run \(run.status.rawValue) on \(run.branch)"
            }
            return (time, desc)
        }
    }
}
