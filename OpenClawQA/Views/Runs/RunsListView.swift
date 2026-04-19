import SwiftUI

struct RunsListView: View {
    @EnvironmentObject var appState: AppState
    @State private var branchFilter: String = "All Branches"
    @State private var envFilter: String = "All Environments"

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Runs")
                    .font(AppFont.title())
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                Button(action: { appState.startNewRun() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                        Text("Run New Check")
                            .font(AppFont.subheading(13))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.sm)
                    .background(AppColors.accentBlue)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(AppSpacing.xl)

            // Filters
            HStack(spacing: AppSpacing.md) {
                filterDropdown(label: branchFilter, icon: "arrow.triangle.branch")
                filterDropdown(label: envFilter, icon: "desktopcomputer")
                Spacer()
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.bottom, AppSpacing.lg)

            // Table Header
            HStack(spacing: 0) {
                Text("Status").frame(width: 60, alignment: .leading)
                Text("Run").frame(width: 160, alignment: .leading)
                Text("Triggered By").frame(width: 120, alignment: .leading)
                Text("Branch").frame(width: 140, alignment: .leading)
                Text("Commit").frame(width: 80, alignment: .leading)
                Text("Duration").frame(width: 80, alignment: .leading)
                Text("Confidence").frame(width: 90, alignment: .leading)
                Text("Issues").frame(width: 100, alignment: .leading)
                Spacer()
            }
            .font(AppFont.caption())
            .foregroundColor(AppColors.textTertiary)
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.sm)
            .background(AppColors.cardBackground)

            Divider().background(AppColors.border)

            // Rows
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(appState.runs) { run in
                        RunRowView(run: run)
                            .onTapGesture { appState.selectRun(run.id) }
                        Divider().background(AppColors.borderSubtle)
                    }
                }
            }
        }
        .background(AppColors.windowBackground)
    }

    private func filterDropdown(label: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(AppColors.textSecondary)
            Text(label)
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
}

// MARK: - Run Row
struct RunRowView: View {
    let run: QARun

    var body: some View {
        HStack(spacing: 0) {
            // Status indicator
            statusIcon
                .frame(width: 60, alignment: .leading)

            // Run time
            VStack(alignment: .leading, spacing: 2) {
                Text(run.startedAt?.formatted(date: .abbreviated, time: .shortened) ?? "--")
                    .font(AppFont.subheading(13))
                    .foregroundColor(AppColors.textPrimary)
            }
            .frame(width: 160, alignment: .leading)

            // Triggered By
            Text(run.triggerSource)
                .font(AppFont.body())
                .foregroundColor(AppColors.textSecondary)
                .frame(width: 120, alignment: .leading)

            // Branch
            HStack(spacing: 4) {
                Text(run.branch)
                    .font(AppFont.mono(12))
                    .foregroundColor(AppColors.accentBlue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppColors.accentBlue.opacity(0.1))
                    .cornerRadius(4)
            }
            .frame(width: 140, alignment: .leading)

            // Commit
            Text(run.shortCommit)
                .font(AppFont.mono(12))
                .foregroundColor(AppColors.textSecondary)
                .frame(width: 80, alignment: .leading)

            // Duration
            Text(run.durationFormatted)
                .font(AppFont.body())
                .foregroundColor(AppColors.textSecondary)
                .frame(width: 80, alignment: .leading)

            // Confidence
            HStack(spacing: 4) {
                Text("\(run.confidenceScore ?? 0)%")
                    .font(AppFont.subheading(13))
                    .foregroundColor(confidenceColor)
            }
            .frame(width: 90, alignment: .leading)

            // Issues
            HStack(spacing: 6) {
                if run.criticalFindings > 0 {
                    issueBadge(count: run.criticalFindings, color: AppColors.critical)
                }
                if run.highFindings > 0 {
                    issueBadge(count: run.highFindings, color: AppColors.high)
                }
                let other = run.mediumFindings + run.lowFindings
                if other > 0 {
                    issueBadge(count: other, color: AppColors.textTertiary)
                }
            }
            .frame(width: 100, alignment: .leading)

            Spacer()

            Image(systemName: "ellipsis")
                .foregroundColor(AppColors.textTertiary)
                .padding(.trailing, AppSpacing.sm)
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.md)
        .contentShape(Rectangle())
    }

    private var statusIcon: some View {
        Group {
            switch run.status {
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(AppColors.success)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(AppColors.error)
            case .exploring, .building, .analyzing:
                Image(systemName: "arrow.clockwise.circle.fill")
                    .foregroundColor(AppColors.running)
            default:
                Image(systemName: "clock.fill")
                    .foregroundColor(AppColors.pending)
            }
        }
        .font(.system(size: 16))
    }

    private var confidenceColor: Color {
        guard let score = run.confidenceScore else { return AppColors.textTertiary }
        if score >= 85 { return AppColors.success }
        if score >= 70 { return AppColors.warning }
        return AppColors.error
    }

    private func issueBadge(count: Int, color: Color) -> some View {
        HStack(spacing: 2) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(count)")
                .font(AppFont.caption(11))
                .foregroundColor(color)
        }
    }
}
