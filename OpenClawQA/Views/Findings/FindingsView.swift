import SwiftUI

struct FindingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedSeverityFilter: FindingSeverity? = nil
    @State private var searchText: String = ""

    private var filteredFindings: [QAFinding] {
        var result = appState.findings
        if let sev = selectedSeverityFilter {
            result = result.filter { $0.severity == sev }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.summary.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    var body: some View {
        HStack(spacing: 0) {
            // Findings list
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Findings")
                        .font(AppFont.title())
                        .foregroundColor(AppColors.textPrimary)
                    Spacer()
                }
                .padding(AppSpacing.xl)

                // Filter tabs
                HStack(spacing: AppSpacing.xs) {
                    filterTab("All", count: appState.findings.count, severity: nil)
                    filterTab("Critical", count: appState.findings.filter { $0.severity == .critical }.count, severity: .critical)
                    filterTab("High", count: appState.findings.filter { $0.severity == .high }.count, severity: .high)
                    filterTab("Medium", count: appState.findings.filter { $0.severity == .medium }.count, severity: .medium)
                    filterTab("Low", count: appState.findings.filter { $0.severity == .low }.count, severity: .low)

                    Spacer()

                    // Search
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.textTertiary)
                        TextField("Search findings...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(AppFont.body())
                            .foregroundColor(AppColors.textPrimary)
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, 6)
                    .background(AppColors.inputBackground)
                    .cornerRadius(6)
                    .frame(width: 200)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.bottom, AppSpacing.md)

                Divider().background(AppColors.border)

                // Findings list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredFindings) { finding in
                            FindingRowView(finding: finding, isSelected: finding.id == appState.selectedFindingId)
                                .onTapGesture { appState.selectFinding(finding.id) }
                            Divider().background(AppColors.borderSubtle)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Divider().background(AppColors.border)

            // Detail panel
            if let finding = appState.selectedFinding {
                findingDetailPanel(finding)
                    .frame(width: 380)
            }
        }
        .background(AppColors.windowBackground)
    }

    // MARK: - Filter Tab
    private func filterTab(_ label: String, count: Int, severity: FindingSeverity?) -> some View {
        Button(action: { selectedSeverityFilter = severity }) {
            HStack(spacing: 4) {
                Text(label)
                    .font(AppFont.subheading(12))
                Text("\(count)")
                    .font(AppFont.caption(11))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected(severity) ? AppColors.accentBlue.opacity(0.3) : AppColors.inputBackground)
                    .cornerRadius(4)
            }
            .foregroundColor(isSelected(severity) ? AppColors.textPrimary : AppColors.textSecondary)
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, 6)
            .background(isSelected(severity) ? AppColors.accentBlue.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private func isSelected(_ severity: FindingSeverity?) -> Bool {
        selectedSeverityFilter == severity
    }

    // MARK: - Finding Detail Panel
    private func findingDetailPanel(_ finding: QAFinding) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                // Header
                HStack {
                    SeverityBadge(severity: finding.severity)
                    Spacer()
                }

                Text(finding.title)
                    .font(AppFont.heading(18))
                    .foregroundColor(AppColors.textPrimary)

                // Info
                VStack(spacing: AppSpacing.sm) {
                    detailInfoRow("Flow", finding.flow ?? "--")
                    detailInfoRow("Screen", finding.screen ?? "--")
                    detailInfoRow("Environment", finding.environment ?? "iPhone 16 Pro (iOS 17.5)")
                    detailInfoRow("Occurred", finding.lastSeenAt.formatted(date: .abbreviated, time: .shortened))
                    detailInfoRow("State", finding.status.rawValue.capitalized)
                }

                Divider().background(AppColors.border)

                // AI Analysis
                if let analysis = finding.aiAnalysis {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("AI Analysis")
                            .font(AppFont.heading(14))
                            .foregroundColor(AppColors.textPrimary)
                        Text(analysis)
                            .font(AppFont.body())
                            .foregroundColor(AppColors.textSecondary)
                            .lineSpacing(3)
                    }
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
                            .lineSpacing(3)
                    }
                }

                Divider().background(AppColors.border)

                // Actions
                Button(action: {}) {
                    HStack {
                        Spacer()
                        Text("View Details")
                            .font(AppFont.subheading())
                        Spacer()
                    }
                    .foregroundColor(AppColors.accentBlue)
                    .padding(.vertical, AppSpacing.sm)
                    .background(AppColors.accentBlue.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(AppSpacing.lg)
        }
        .background(AppColors.cardBackground)
    }

    private func detailInfoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(AppFont.caption())
                .foregroundColor(AppColors.textSecondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(AppFont.body())
                .foregroundColor(AppColors.textPrimary)
            Spacer()
        }
    }
}

// MARK: - Finding Row
struct FindingRowView: View {
    let finding: QAFinding
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            SeverityBadge(severity: finding.severity)

            VStack(alignment: .leading, spacing: 4) {
                Text(finding.title)
                    .font(AppFont.subheading(13))
                    .foregroundColor(AppColors.textPrimary)
                HStack(spacing: AppSpacing.sm) {
                    if let flow = finding.flow {
                        Text(flow)
                            .font(AppFont.caption())
                            .foregroundColor(AppColors.textTertiary)
                    }
                }
            }

            Spacer()

            Text(finding.lastSeenAt.formatted(date: .abbreviated, time: .shortened))
                .font(AppFont.caption())
                .foregroundColor(AppColors.textTertiary)
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.md)
        .background(isSelected ? AppColors.selectedBackground : Color.clear)
        .contentShape(Rectangle())
    }
}
