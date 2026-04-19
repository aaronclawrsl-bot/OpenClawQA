import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 220)

            Divider()
                .background(AppColors.border)

            if appState.showRunDetail, appState.selectedRunId != nil {
                RunDetailView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                mainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(AppColors.windowBackground)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var mainContent: some View {
        switch appState.selectedTab {
        case .overview:
            OverviewView()
        case .runs:
            RunsListView()
        case .findings:
            FindingsView()
        case .coverage:
            CoverageView()
        case .insights:
            InsightsView()
        case .integrations:
            IntegrationsView()
        case .settings:
            SettingsView()
        }
    }
}
