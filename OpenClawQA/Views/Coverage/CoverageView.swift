import SwiftUI

struct CoverageView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedCoverageTab: String = "Flow Map"

    var coverageNodes: [CoverageNode] {
        guard let run = appState.latestRun, run.status == .completed else {
            return []
        }
        // Build coverage nodes from actual run data
        var nodes: [CoverageNode] = []
        let coverage = run.coveragePercent

        // Core app screens based on what we know about ResiLife
        let screenDefs: [(String, String, CGPoint)] = [
            ("launch", "Launch", CGPoint(x: 80, y: 200)),
            ("login", "Login", CGPoint(x: 200, y: 200)),
            ("home", "Home", CGPoint(x: 320, y: 200)),
            ("feed", "Feed", CGPoint(x: 440, y: 100)),
            ("rewards", "Rewards", CGPoint(x: 440, y: 200)),
            ("community", "Community", CGPoint(x: 440, y: 300)),
            ("profile", "Profile", CGPoint(x: 560, y: 100)),
            ("settings", "Settings", CGPoint(x: 560, y: 200)),
            ("messages", "Messages", CGPoint(x: 560, y: 300)),
        ]

        for (i, def) in screenDefs.enumerated() {
            let pct = i < run.flowsExplored ? min(100, Int(coverage)) : 0
            let status: CoverageNodeStatus = pct == 100 ? .visited : (pct > 0 ? .partial : .notVisited)
            let connections: [String]
            switch def.0 {
            case "launch": connections = ["login"]
            case "login": connections = ["home"]
            case "home": connections = ["feed", "rewards", "community"]
            case "feed": connections = ["profile"]
            case "rewards": connections = []
            case "community": connections = ["messages"]
            default: connections = []
            }
            nodes.append(CoverageNode(
                id: def.0, name: def.1, coveragePercent: pct,
                status: status, position: def.2, connections: connections
            ))
        }

        return nodes
    }

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

                Text(appState.latestRun.map { "\($0.flowsExplored) flows discovered  ·  \($0.testsExecuted) tests executed  ·  \(Int($0.coveragePercent))% of app surface explored" } ?? "No run data")
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
