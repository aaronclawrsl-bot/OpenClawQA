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
                    insightStatCard(
                        title: "Release Confidence Trend",
                        value: "+18%",
                        valueColor: AppColors.success,
                        icon: "arrow.up.right"
                    )
                    insightStatCard(
                        title: "Bugs Found",
                        value: "23",
                        valueColor: AppColors.error,
                        icon: "ladybug"
                    )
                    insightStatCard(
                        title: "Avg. Run Time",
                        value: "32m",
                        valueColor: AppColors.accentBlue,
                        icon: "clock"
                    )
                    insightStatCard(
                        title: "Flaky Tests",
                        value: "3",
                        valueColor: AppColors.warning,
                        icon: "arrow.triangle.2.circlepath"
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
                issueCategoryBar("Functional", count: 12, maxCount: 12, color: AppColors.critical)
                issueCategoryBar("UI / Layout", count: 6, maxCount: 12, color: AppColors.high)
                issueCategoryBar("Performance", count: 3, maxCount: 12, color: AppColors.warning)
                issueCategoryBar("Other", count: 2, maxCount: 12, color: AppColors.textTertiary)
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
                activityRow("May 24, 9:41 AM", "2 critical issues found in PR #248")
                activityRow("May 24, 8:09 AM", "QA check completed on main")
                activityRow("May 23, 11:22 PM", "New run triggered by push")
                activityRow("May 23, 6:15 PM", "PR #248 QA check started")
                activityRow("May 23, 11:02 AM", "Scheduled run completed")
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
}
