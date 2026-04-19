import SwiftUI

// MARK: - Severity Badge
struct SeverityBadge: View {
    let severity: FindingSeverity
    var compact: Bool = false

    var body: some View {
        Text(severity.rawValue.uppercased())
            .font(compact ? AppFont.caption(9) : AppFont.caption(10))
            .foregroundColor(.white)
            .padding(.horizontal, compact ? 4 : 8)
            .padding(.vertical, compact ? 2 : 3)
            .background(badgeColor)
            .cornerRadius(4)
    }

    private var badgeColor: Color {
        switch severity {
        case .critical: return AppColors.critical
        case .high: return AppColors.high
        case .medium: return AppColors.medium
        case .low: return AppColors.low
        }
    }
}

// MARK: - Status Indicator
struct StatusIndicator: View {
    let status: RunStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(status.rawValue.capitalized)
                .font(AppFont.caption())
                .foregroundColor(statusColor)
        }
    }

    private var statusColor: Color {
        switch status {
        case .completed: return AppColors.success
        case .failed: return AppColors.error
        case .cancelled: return AppColors.textTertiary
        case .exploring, .building, .analyzing, .preparing, .booting, .installing, .deterministicChecks, .summarizing:
            return AppColors.running
        case .queued: return AppColors.pending
        }
    }
}

// MARK: - Confidence Gauge
struct ConfidenceGauge: View {
    let score: Int
    var size: CGFloat = 60

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppColors.inputBackground, lineWidth: 4)
            Circle()
                .trim(from: 0, to: Double(score) / 100.0)
                .stroke(gaugeColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text("\(score)%")
                    .font(AppFont.subheading(size * 0.25))
                    .foregroundColor(gaugeColor)
            }
        }
        .frame(width: size, height: size)
    }

    private var gaugeColor: Color {
        if score >= 85 { return AppColors.success }
        if score >= 70 { return AppColors.warning }
        return AppColors.error
    }
}

// MARK: - Release Readiness Badge
struct ReleaseReadinessBadge: View {
    let readiness: ReleaseReadiness

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
            Text(label)
                .font(AppFont.subheading(12))
        }
        .foregroundColor(color)
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.xs)
        .background(color.opacity(0.1))
        .cornerRadius(6)
    }

    private var icon: String {
        switch readiness {
        case .ready: return "checkmark.shield.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .blocked: return "xmark.shield.fill"
        }
    }

    private var label: String {
        switch readiness {
        case .ready: return "Ready to Ship"
        case .caution: return "Review Recommended"
        case .blocked: return "Release Blocked"
        }
    }

    private var color: Color {
        switch readiness {
        case .ready: return AppColors.success
        case .caution: return AppColors.warning
        case .blocked: return AppColors.error
        }
    }
}

// MARK: - Empty State View
struct EmptyStateView: View {
    let icon: String
    let title: String
    let description: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(AppColors.textTertiary)

            Text(title)
                .font(AppFont.heading())
                .foregroundColor(AppColors.textSecondary)

            Text(description)
                .font(AppFont.body())
                .foregroundColor(AppColors.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            if let actionLabel = actionLabel, let action = action {
                Button(action: action) {
                    Text(actionLabel)
                        .font(AppFont.subheading())
                        .foregroundColor(.white)
                        .padding(.horizontal, AppSpacing.xl)
                        .padding(.vertical, AppSpacing.sm)
                        .background(AppColors.accentBlue)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
