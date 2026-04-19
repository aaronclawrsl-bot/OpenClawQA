import SwiftUI

struct IntegrationsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                // Header
                HStack {
                    Text("Integrations")
                        .font(AppFont.title())
                        .foregroundColor(AppColors.textPrimary)
                    Spacer()

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

                // Integration cards grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ], spacing: AppSpacing.lg) {
                    ForEach(appState.integrations) { integration in
                        integrationCard(
                            icon: iconFor(integration.type.rawValue),
                            iconColor: colorFor(integration.type.rawValue),
                            name: integration.displayName,
                            detail: integration.isConnected ? "Connected" : "Disconnected",
                            isConnected: integration.isConnected
                        )
                    }

                    // Add Integration
                    addIntegrationCard
                }
            }
            .padding(AppSpacing.xl)
        }
        .background(AppColors.windowBackground)
    }

    // MARK: - Integration Card
    private func integrationCard(icon: String, iconColor: Color, name: String, detail: String, isConnected: Bool) -> some View {
        VStack(spacing: AppSpacing.lg) {
            // Icon
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(iconColor)
            }

            VStack(spacing: 4) {
                Text(name)
                    .font(AppFont.heading(16))
                    .foregroundColor(AppColors.textPrimary)

                Text(detail)
                    .font(AppFont.caption())
                    .foregroundColor(AppColors.textSecondary)
            }

            Button(action: {}) {
                Text("Configure")
                    .font(AppFont.subheading(12))
                    .foregroundColor(AppColors.textSecondary)
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, 6)
                    .background(AppColors.inputBackground)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.xl)
        .cardStyle(padding: 0)
    }

    // MARK: - Add Integration Card
    private var addIntegrationCard: some View {
        VStack(spacing: AppSpacing.lg) {
            ZStack {
                Circle()
                    .strokeBorder(AppColors.border, style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    .frame(width: 48, height: 48)
                Image(systemName: "plus")
                    .font(.system(size: 20))
                    .foregroundColor(AppColors.textTertiary)
            }

            VStack(spacing: 4) {
                Text("Add Integration")
                    .font(AppFont.heading(16))
                    .foregroundColor(AppColors.textSecondary)
                Text("Connect a new service")
                    .font(AppFont.caption())
                    .foregroundColor(AppColors.textTertiary)
            }

            Spacer().frame(height: 26) // Match button height
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.xl)
        .background(AppColors.cardBackground.opacity(0.5))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(AppColors.border, style: StrokeStyle(lineWidth: 1, dash: [6]))
        )
    }

    private func iconFor(_ type: String) -> String {
        switch type.lowercased() {
        case "github": return "chevron.left.forwardslash.chevron.right"
        case "jira": return "ticket"
        case "slack": return "number"
        case "email": return "envelope.fill"
        default: return "link"
        }
    }

    private func colorFor(_ type: String) -> Color {
        switch type.lowercased() {
        case "github": return .white
        case "jira": return AppColors.accentBlue
        case "slack": return AppColors.success
        case "email": return AppColors.error
        default: return AppColors.textSecondary
        }
    }
}
