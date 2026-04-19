import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedSection: String = "General"
    @State private var projectName: String = "ResiLife iOS"
    @State private var defaultEnvironment: String = "iPhone 15 Pro (iOS 17.5)"
    @State private var defaultRunType: String = "Full Exploration"
    @State private var autoStartOnCommit: Bool = true
    @State private var compareAgainstPrevious: Bool = true
    @State private var generateAIDescriptions: Bool = true

    let sections = ["General", "Project", "Environments", "AI & Analysis", "Notifications", "Integrations", "Team", "Advanced"]

    var body: some View {
        HStack(spacing: 0) {
            // Settings sidebar
            VStack(spacing: 2) {
                ForEach(sections, id: \.self) { section in
                    Button(action: { selectedSection = section }) {
                        HStack {
                            Text(section)
                                .font(AppFont.subheading(13))
                                .foregroundColor(selectedSection == section ? AppColors.textPrimary : AppColors.textSecondary)
                            Spacer()
                        }
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)
                        .background(selectedSection == section ? AppColors.accentBlue.opacity(0.15) : Color.clear)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .frame(width: 180)
            .padding(AppSpacing.lg)
            .background(AppColors.cardBackground)

            Divider().background(AppColors.border)

            // Settings content
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    Text(selectedSection)
                        .font(AppFont.title())
                        .foregroundColor(AppColors.textPrimary)

                    switch selectedSection {
                    case "General":
                        generalSettings
                    case "Project":
                        projectSettings
                    case "Environments":
                        environmentSettings
                    case "AI & Analysis":
                        aiSettings
                    case "Notifications":
                        notificationSettings
                    case "Integrations":
                        integrationsSettings
                    case "Team":
                        teamSettings
                    case "Advanced":
                        advancedSettings
                    default:
                        EmptyView()
                    }
                }
                .padding(AppSpacing.xl)
            }
            .frame(maxWidth: .infinity)
        }
        .background(AppColors.windowBackground)
    }

    // MARK: - General Settings
    private var generalSettings: some View {
        VStack(spacing: AppSpacing.xl) {
            settingsField("Project Name", value: $projectName)
            settingsDropdown("Default Environment", value: defaultEnvironment)
            settingsDropdown("Default Run Type", value: defaultRunType)

            Divider().background(AppColors.border)

            settingsToggle("Auto-start run on new commit", isOn: $autoStartOnCommit)
            settingsToggle("Compare against previous successful run", isOn: $compareAgainstPrevious)
            settingsToggle("Generate AI issue descriptions", isOn: $generateAIDescriptions)
        }
    }

    // MARK: - Project Settings
    private var projectSettings: some View {
        VStack(spacing: AppSpacing.xl) {
            if let project = appState.currentProject {
                settingsReadOnly("Repository", value: project.repoIdentifier)
                settingsReadOnly("Default Branch", value: project.defaultBranch)
                settingsReadOnly("Workspace", value: project.workspacePath ?? "--")
                settingsReadOnly("Scheme", value: project.scheme)
                settingsReadOnly("Configuration", value: project.configuration)
                settingsReadOnly("Bundle ID", value: project.bundleId)
                settingsReadOnly("Runner Mode", value: project.runnerMode.capitalized)
            }
        }
    }

    // MARK: - Environment Settings
    private var environmentSettings: some View {
        VStack(spacing: AppSpacing.xl) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("Simulator Profiles")
                    .font(AppFont.heading(16))
                    .foregroundColor(AppColors.textPrimary)

                ForEach(["iPhone 16 Pro (iOS 17.5)", "iPhone 16 Pro Max (iOS 17.5)", "iPhone SE (iOS 17.5)", "iPad Pro 12.9\" (iOS 17.5)"], id: \.self) { sim in
                    HStack {
                        Image(systemName: "iphone")
                            .foregroundColor(AppColors.textSecondary)
                        Text(sim)
                            .font(AppFont.body())
                            .foregroundColor(AppColors.textPrimary)
                        Spacer()
                        if sim == "iPhone 16 Pro (iOS 17.5)" {
                            Text("Default")
                                .font(AppFont.caption(10))
                                .foregroundColor(AppColors.accentBlue)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppColors.accentBlue.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                    .padding(AppSpacing.md)
                    .background(AppColors.inputBackground)
                    .cornerRadius(6)
                }
            }

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("Test Credentials")
                    .font(AppFont.heading(16))
                    .foregroundColor(AppColors.textPrimary)

                HStack {
                    Text("TEST_EMAIL")
                        .font(AppFont.mono(12))
                        .foregroundColor(AppColors.textSecondary)
                    Spacer()
                    Text("••••••••")
                        .font(AppFont.mono(12))
                        .foregroundColor(AppColors.textTertiary)
                    Button("Edit") {}
                        .font(AppFont.caption())
                        .foregroundColor(AppColors.accentBlue)
                        .buttonStyle(.plain)
                }
                .padding(AppSpacing.md)
                .background(AppColors.inputBackground)
                .cornerRadius(6)

                HStack {
                    Text("TEST_PASSWORD")
                        .font(AppFont.mono(12))
                        .foregroundColor(AppColors.textSecondary)
                    Spacer()
                    Text("••••••••")
                        .font(AppFont.mono(12))
                        .foregroundColor(AppColors.textTertiary)
                    Button("Edit") {}
                        .font(AppFont.caption())
                        .foregroundColor(AppColors.accentBlue)
                        .buttonStyle(.plain)
                }
                .padding(AppSpacing.md)
                .background(AppColors.inputBackground)
                .cornerRadius(6)
            }
        }
    }

    // MARK: - AI & Analysis Settings
    private var aiSettings: some View {
        VStack(spacing: AppSpacing.xl) {
            settingsDropdown("Analysis Depth", value: "Balanced")

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("Analysis depth controls how thoroughly the autonomous engine explores your app.")
                    .font(AppFont.caption())
                    .foregroundColor(AppColors.textTertiary)

                VStack(spacing: AppSpacing.sm) {
                    analysisOption("Fast", "Quick smoke check — builds, launches, checks critical paths only", false)
                    analysisOption("Balanced", "Moderate exploration with smart prioritization", true)
                    analysisOption("Deep Analysis", "Maximum coverage, thorough state exploration", false)
                }
            }

            Divider().background(AppColors.border)

            settingsDropdown("Max Exploration Depth", value: "20 screens")
            settingsDropdown("Max Actions per Run", value: "400")
            settingsDropdown("Timeout", value: "30 minutes")
        }
    }

    private func analysisOption(_ name: String, _ desc: String, _ selected: Bool) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                .foregroundColor(selected ? AppColors.accentBlue : AppColors.textTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(AppFont.subheading())
                    .foregroundColor(AppColors.textPrimary)
                Text(desc)
                    .font(AppFont.caption())
                    .foregroundColor(AppColors.textSecondary)
            }
            Spacer()
        }
        .padding(AppSpacing.md)
        .background(selected ? AppColors.accentBlue.opacity(0.05) : Color.clear)
        .cornerRadius(6)
    }

    // MARK: - Notification Settings
    private var notificationSettings: some View {
        VStack(spacing: AppSpacing.xl) {
            settingsToggle("Notify on run complete", isOn: .constant(true))
            settingsToggle("Notify on critical finding", isOn: .constant(true))
            settingsToggle("Notify on build failure", isOn: .constant(true))
            settingsToggle("Daily digest email", isOn: .constant(false))

            Divider().background(AppColors.border)

            settingsDropdown("Slack Channel", value: "#qa-alerts")
            settingsDropdown("Email Recipients", value: "3 recipients configured")
        }
    }

    // MARK: - Integrations Settings
    private var integrationsSettings: some View {
        VStack(spacing: AppSpacing.xl) {
            Text("Manage integration connections from the Integrations tab.")
                .font(AppFont.body())
                .foregroundColor(AppColors.textSecondary)

            Button(action: { appState.selectedTab = .integrations }) {
                Text("Go to Integrations")
                    .font(AppFont.subheading())
                    .foregroundColor(AppColors.accentBlue)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Team Settings
    private var teamSettings: some View {
        VStack(spacing: AppSpacing.xl) {
            Text("Team management features will be available in a future update.")
                .font(AppFont.body())
                .foregroundColor(AppColors.textSecondary)
        }
    }

    // MARK: - Advanced Settings
    private var advancedSettings: some View {
        VStack(spacing: AppSpacing.xl) {
            settingsDropdown("Artifact Retention", value: "30 days")
            settingsToggle("Keep videos for failed runs only", isOn: .constant(false))

            Divider().background(AppColors.border)

            settingsDropdown("Derived Data Mode", value: "Isolated")
            settingsToggle("Verbose logging", isOn: .constant(false))
            settingsToggle("Include accessibility snapshots in artifacts", isOn: .constant(true))

            Divider().background(AppColors.border)

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("Database")
                    .font(AppFont.heading(16))
                    .foregroundColor(AppColors.textPrimary)

                HStack {
                    Text("Location")
                        .font(AppFont.body())
                        .foregroundColor(AppColors.textSecondary)
                    Spacer()
                    Text("~/Library/Application Support/OpenClawQA/")
                        .font(AppFont.mono(11))
                        .foregroundColor(AppColors.textTertiary)
                }

                HStack {
                    Text("Size")
                        .font(AppFont.body())
                        .foregroundColor(AppColors.textSecondary)
                    Spacer()
                    Text("2.4 MB")
                        .font(AppFont.mono(11))
                        .foregroundColor(AppColors.textTertiary)
                }

                Button(action: {}) {
                    Text("Export Database")
                        .font(AppFont.subheading(12))
                        .foregroundColor(AppColors.textSecondary)
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.vertical, 6)
                        .background(AppColors.inputBackground)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Reusable Setting Components
    private func settingsField(_ label: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(label)
                .font(AppFont.body())
                .foregroundColor(AppColors.textSecondary)
            TextField("", text: value)
                .textFieldStyle(.plain)
                .font(AppFont.body())
                .foregroundColor(AppColors.textPrimary)
                .padding(AppSpacing.md)
                .background(AppColors.inputBackground)
                .cornerRadius(6)
        }
    }

    private func settingsReadOnly(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(AppFont.body())
                .foregroundColor(AppColors.textSecondary)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .font(AppFont.body())
                .foregroundColor(AppColors.textPrimary)
            Spacer()
        }
    }

    private func settingsDropdown(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(label)
                .font(AppFont.body())
                .foregroundColor(AppColors.textSecondary)
            HStack {
                Text(value)
                    .font(AppFont.body())
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.textTertiary)
            }
            .padding(AppSpacing.md)
            .background(AppColors.inputBackground)
            .cornerRadius(6)
        }
    }

    private func settingsToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label)
                .font(AppFont.body())
                .foregroundColor(AppColors.textPrimary)
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .tint(AppColors.accentBlue)
        }
    }
}
