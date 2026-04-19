import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Logo / Title
            HStack(spacing: 8) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(AppColors.accentBlue)
                Text("OpenClaw QA")
                    .font(AppFont.heading(16))
                    .foregroundColor(AppColors.textPrimary)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, 20)
            .padding(.bottom, AppSpacing.md)

            // Project selector
            projectSelector
                .padding(.horizontal, AppSpacing.md)
                .padding(.bottom, AppSpacing.lg)

            // Navigation items
            VStack(spacing: 2) {
                ForEach(NavigationTab.allCases) { tab in
                    sidebarItem(tab)
                }
            }
            .padding(.horizontal, AppSpacing.sm)

            Spacer()

            // Project info section
            if let project = appState.currentProject {
                projectInfoSection(project)
            }

            Divider().background(AppColors.border).padding(.horizontal, AppSpacing.lg)

            // User info
            userInfoSection
        }
        .frame(maxHeight: .infinity)
        .background(AppColors.sidebarBackground)
    }

    // MARK: - Project Selector
    private var projectSelector: some View {
        Menu {
            ForEach(appState.projects) { project in
                Button(project.name) {
                    appState.selectProject(project.id)
                }
            }
            Divider()
            Button {
                appState.showProjectSetup = true
            } label: {
                Label("New Project...", systemImage: "plus")
            }
        } label: {
            HStack {
                Text(appState.currentProject?.name ?? "Select Project")
                    .font(AppFont.subheading())
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.textSecondary)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(AppColors.inputBackground)
            .cornerRadius(6)
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - Sidebar Item
    private func sidebarItem(_ tab: NavigationTab) -> some View {
        Button {
            appState.selectedTab = tab
            appState.showRunDetail = false
        } label: {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14))
                    .foregroundColor(appState.selectedTab == tab ? AppColors.accentBlue : AppColors.textSecondary)
                    .frame(width: 20)
                Text(tab.rawValue)
                    .font(AppFont.subheading())
                    .foregroundColor(appState.selectedTab == tab ? AppColors.textPrimary : AppColors.textSecondary)
                Spacer()
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(appState.selectedTab == tab ? AppColors.sidebarSelected.opacity(0.15) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Project Info
    private func projectInfoSection(_ project: QAProject) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("PROJECT")
                .font(AppFont.caption(10))
                .foregroundColor(AppColors.textTertiary)
                .tracking(1.2)

            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.textSecondary)
                Text(project.defaultBranch)
                    .font(AppFont.caption())
                    .foregroundColor(AppColors.textSecondary)
            }

            if let run = appState.latestRun {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "number")
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textSecondary)
                    Text(run.shortCommit)
                        .font(AppFont.mono(11))
                        .foregroundColor(AppColors.textSecondary)
                }

                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textSecondary)
                    Text(run.startedAt?.formatted(date: .abbreviated, time: .shortened) ?? "--")
                        .font(AppFont.caption())
                        .foregroundColor(AppColors.textSecondary)
                }
            }

            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "app.badge")
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.textSecondary)
                Text("iOS App 1.4.2 (45)")
                    .font(AppFont.caption())
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
    }

    // MARK: - User Info
    private var userInfoSection: some View {
        HStack(spacing: AppSpacing.md) {
            Circle()
                .fill(AppColors.accentPurple.opacity(0.3))
                .frame(width: 32, height: 32)
                .overlay(
                    Text("AJ")
                        .font(AppFont.caption(11))
                        .foregroundColor(AppColors.accentPurple)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Alex Johnson")
                    .font(AppFont.subheading(12))
                    .foregroundColor(AppColors.textPrimary)
                Text("alex@resilife.app")
                    .font(AppFont.caption(10))
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
    }
}
