import SwiftUI

struct CoverageView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedCoverageTab: String = "Flow Map"

    let coverageNodes: [CoverageNode] = [
        CoverageNode(id: "launch", name: "Launch", coveragePercent: 100, status: .visited,
                     position: CGPoint(x: 80, y: 200), connections: ["onboarding"]),
        CoverageNode(id: "onboarding", name: "Onboarding", coveragePercent: 100, status: .visited,
                     position: CGPoint(x: 200, y: 200), connections: ["login"]),
        CoverageNode(id: "login", name: "Login", coveragePercent: 100, status: .visited,
                     position: CGPoint(x: 320, y: 200), connections: ["home"]),
        CoverageNode(id: "home", name: "Home", coveragePercent: 100, status: .visited,
                     position: CGPoint(x: 440, y: 200), connections: ["property_list", "messages", "profile", "settings"]),
        CoverageNode(id: "property_list", name: "Property List", coveragePercent: 100, status: .visited,
                     position: CGPoint(x: 580, y: 100), connections: ["property_detail", "preferences"]),
        CoverageNode(id: "property_detail", name: "Property\nDetail", coveragePercent: 100, status: .visited,
                     position: CGPoint(x: 700, y: 50), connections: []),
        CoverageNode(id: "preferences", name: "Preferences", coveragePercent: 100, status: .visited,
                     position: CGPoint(x: 700, y: 150), connections: []),
        CoverageNode(id: "payments", name: "Payments", coveragePercent: 60, status: .partial,
                     position: CGPoint(x: 580, y: 200), connections: []),
        CoverageNode(id: "messages", name: "Messages", coveragePercent: 50, status: .partial,
                     position: CGPoint(x: 580, y: 300), connections: []),
        CoverageNode(id: "profile", name: "Profile", coveragePercent: 75, status: .partial,
                     position: CGPoint(x: 440, y: 350), connections: []),
        CoverageNode(id: "settings", name: "Settings", coveragePercent: 0, status: .notVisited,
                     position: CGPoint(x: 320, y: 350), connections: []),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Coverage")
                    .font(AppFont.title())
                    .foregroundColor(AppColors.textPrimary)
                Spacer()

                // Zoom controls
                HStack(spacing: AppSpacing.sm) {
                    Button(action: {}) {
                        Image(systemName: "plus.magnifyingglass")
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    Button(action: {}) {
                        Image(systemName: "minus.magnifyingglass")
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(AppSpacing.xl)

            // Tab bar
            HStack(spacing: 0) {
                coverageTab("Flow Map")
                coverageTab("Screen Coverage")
                Spacer()
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.bottom, AppSpacing.md)

            Divider().background(AppColors.border)

            // Flow Map
            ZStack {
                // Background
                AppColors.windowBackground

                if selectedCoverageTab == "Flow Map" {
                    flowMapContent
                } else {
                    screenCoverageContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Footer stats
            HStack(spacing: AppSpacing.xl) {
                HStack(spacing: AppSpacing.sm) {
                    legendDot(.visited)
                    Text("Visited").font(AppFont.caption()).foregroundColor(AppColors.textSecondary)
                }
                HStack(spacing: AppSpacing.sm) {
                    legendDot(.partial)
                    Text("Partial").font(AppFont.caption()).foregroundColor(AppColors.textSecondary)
                }
                HStack(spacing: AppSpacing.sm) {
                    legendDot(.notVisited)
                    Text("Not Visited").font(AppFont.caption()).foregroundColor(AppColors.textSecondary)
                }
                HStack(spacing: AppSpacing.sm) {
                    legendDot(.blocked)
                    Text("Blocked").font(AppFont.caption()).foregroundColor(AppColors.textSecondary)
                }

                Spacer()

                Text("38 flows discovered  ·  213 tests executed  ·  87% of app surface explored")
                    .font(AppFont.caption())
                    .foregroundColor(AppColors.textSecondary)
            }
            .padding(AppSpacing.lg)
            .background(AppColors.cardBackground)
        }
        .background(AppColors.windowBackground)
    }

    // MARK: - Tab
    private func coverageTab(_ label: String) -> some View {
        Button(action: { selectedCoverageTab = label }) {
            Text(label)
                .font(AppFont.subheading(13))
                .foregroundColor(selectedCoverageTab == label ? AppColors.textPrimary : AppColors.textSecondary)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
                .background(selectedCoverageTab == label ? AppColors.accentBlue.opacity(0.15) : AppColors.inputBackground)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Flow Map
    private var flowMapContent: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / 800, geo.size.height / 450)

            ZStack {
                // Connections
                ForEach(coverageNodes) { node in
                    ForEach(node.connections, id: \.self) { targetId in
                        if let target = coverageNodes.first(where: { $0.id == targetId }) {
                            Path { path in
                                path.move(to: CGPoint(
                                    x: node.position.x * scale + 40,
                                    y: node.position.y * scale
                                ))
                                path.addLine(to: CGPoint(
                                    x: target.position.x * scale - 40,
                                    y: target.position.y * scale
                                ))
                            }
                            .stroke(AppColors.border, lineWidth: 1.5)
                        }
                    }
                }

                // Nodes
                ForEach(coverageNodes) { node in
                    coverageNodeView(node, scale: scale)
                        .position(x: node.position.x * scale, y: node.position.y * scale)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func coverageNodeView(_ node: CoverageNode, scale: CGFloat) -> some View {
        VStack(spacing: 4) {
            Text(node.name)
                .font(AppFont.subheading(11))
                .foregroundColor(AppColors.textPrimary)
                .multilineTextAlignment(.center)

            Text("\(node.coveragePercent)%")
                .font(AppFont.mono(10))
                .foregroundColor(nodeColor(node.status))
        }
        .frame(width: 80 * scale, height: 50 * scale)
        .background(AppColors.cardBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(nodeColor(node.status), lineWidth: 2)
        )
    }

    // MARK: - Screen Coverage
    private var screenCoverageContent: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()),
                GridItem(.flexible()), GridItem(.flexible())
            ], spacing: AppSpacing.lg) {
                ForEach(coverageNodes) { node in
                    VStack(spacing: AppSpacing.sm) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppColors.inputBackground)
                            .frame(height: 120)
                            .overlay(
                                VStack(spacing: 4) {
                                    Image(systemName: "rectangle.portrait")
                                        .font(.system(size: 24))
                                        .foregroundColor(nodeColor(node.status).opacity(0.6))
                                    Text("\(node.coveragePercent)%")
                                        .font(AppFont.subheading())
                                        .foregroundColor(nodeColor(node.status))
                                }
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(nodeColor(node.status).opacity(0.3), lineWidth: 1)
                            )

                        Text(node.name)
                            .font(AppFont.caption())
                            .foregroundColor(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(AppSpacing.xl)
        }
    }

    // MARK: - Helpers
    private func nodeColor(_ status: CoverageNodeStatus) -> Color {
        switch status {
        case .visited: return AppColors.success
        case .partial: return AppColors.warning
        case .notVisited: return AppColors.textTertiary
        case .blocked: return AppColors.error
        }
    }

    private func legendDot(_ status: CoverageNodeStatus) -> some View {
        Circle()
            .fill(nodeColor(status))
            .frame(width: 8, height: 8)
    }
}
