import SwiftUI

struct ProjectSetupWizard: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var currentStep: Int = 0
    @State private var repoSource: String = "github"
    @State private var repoURL: String = ""
    @State private var localPath: String = ""
    @State private var projectName: String = ""
    @State private var scheme: String = ""
    @State private var workspace: String = ""
    @State private var bundleId: String = ""
    @State private var runnerMode: String = "local"
    @State private var simulatorTarget: String = "iPhone 16 Pro"

    let steps = ["Repository", "Build Target", "Runner", "Credentials", "Integrations", "Review"]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Project Setup")
                    .font(AppFont.heading())
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .foregroundColor(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(AppSpacing.xl)

            // Progress steps
            HStack(spacing: 0) {
                ForEach(0..<steps.count, id: \.self) { i in
                    stepIndicator(index: i, label: steps[i])
                    if i < steps.count - 1 {
                        Rectangle()
                            .fill(i < currentStep ? AppColors.accentBlue : AppColors.border)
                            .frame(height: 2)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.bottom, AppSpacing.xl)

            Divider().background(AppColors.border)

            // Step content
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    switch currentStep {
                    case 0: repoStep
                    case 1: buildTargetStep
                    case 2: runnerStep
                    case 3: credentialsStep
                    case 4: integrationsStep
                    case 5: reviewStep
                    default: EmptyView()
                    }
                }
                .padding(AppSpacing.xl)
            }
            .frame(maxHeight: .infinity)

            Divider().background(AppColors.border)

            // Navigation buttons
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        currentStep -= 1
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AppColors.textSecondary)
                }

                Spacer()

                if currentStep < steps.count - 1 {
                    Button(action: { currentStep += 1 }) {
                        Text("Continue")
                            .foregroundColor(.white)
                            .padding(.horizontal, AppSpacing.xl)
                            .padding(.vertical, AppSpacing.sm)
                            .background(AppColors.accentBlue)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: createProject) {
                        Text("Create Project")
                            .foregroundColor(.white)
                            .padding(.horizontal, AppSpacing.xl)
                            .padding(.vertical, AppSpacing.sm)
                            .background(AppColors.success)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(AppSpacing.xl)
        }
        .frame(width: 700, height: 600)
        .background(AppColors.windowBackground)
    }

    // MARK: - Step Indicator
    private func stepIndicator(index: Int, label: String) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(index <= currentStep ? AppColors.accentBlue : AppColors.inputBackground)
                    .frame(width: 28, height: 28)
                if index < currentStep {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Text("\(index + 1)")
                        .font(AppFont.caption(11))
                        .foregroundColor(index == currentStep ? .white : AppColors.textTertiary)
                }
            }
            Text(label)
                .font(AppFont.caption(10))
                .foregroundColor(index <= currentStep ? AppColors.textPrimary : AppColors.textTertiary)
        }
    }

    // MARK: - Steps
    private var repoStep: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            Text("Select Repository")
                .font(AppFont.heading())
                .foregroundColor(AppColors.textPrimary)

            HStack(spacing: AppSpacing.lg) {
                repoOption("github", "GitHub", "Clone from GitHub", "chevron.left.forwardslash.chevron.right")
                repoOption("local", "Local Folder", "Select a local repository", "folder")
            }

            if repoSource == "github" {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("Repository URL or owner/name")
                        .font(AppFont.body())
                        .foregroundColor(AppColors.textSecondary)
                    TextField("e.g., EWAG-dev/iosApp", text: $repoURL)
                        .textFieldStyle(.plain)
                        .font(AppFont.body())
                        .foregroundColor(AppColors.textPrimary)
                        .padding(AppSpacing.md)
                        .background(AppColors.inputBackground)
                        .cornerRadius(6)
                }
            } else {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("Local Repository Path")
                        .font(AppFont.body())
                        .foregroundColor(AppColors.textSecondary)
                    HStack {
                        TextField("/path/to/repo", text: $localPath)
                            .textFieldStyle(.plain)
                            .font(AppFont.mono(12))
                            .foregroundColor(AppColors.textPrimary)
                            .padding(AppSpacing.md)
                            .background(AppColors.inputBackground)
                            .cornerRadius(6)
                        Button("Browse...") {}
                            .buttonStyle(.plain)
                            .foregroundColor(AppColors.accentBlue)
                    }
                }
            }
        }
    }

    private func repoOption(_ value: String, _ title: String, _ desc: String, _ icon: String) -> some View {
        Button(action: { repoSource = value }) {
            VStack(spacing: AppSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(repoSource == value ? AppColors.accentBlue : AppColors.textTertiary)
                Text(title)
                    .font(AppFont.subheading())
                    .foregroundColor(AppColors.textPrimary)
                Text(desc)
                    .font(AppFont.caption())
                    .foregroundColor(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(AppSpacing.xl)
            .background(repoSource == value ? AppColors.accentBlue.opacity(0.1) : AppColors.inputBackground)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(repoSource == value ? AppColors.accentBlue : AppColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var buildTargetStep: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            Text("Configure Build Target")
                .font(AppFont.heading())
                .foregroundColor(AppColors.textPrimary)

            wizardField("Project Name", text: $projectName, placeholder: "My iOS App")
            wizardField("Workspace / Project", text: $workspace, placeholder: "MyApp.xcworkspace")
            wizardField("Scheme", text: $scheme, placeholder: "MyApp")
            wizardField("Bundle Identifier", text: $bundleId, placeholder: "com.example.myapp")
        }
    }

    private var runnerStep: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            Text("Select Runner")
                .font(AppFont.heading())
                .foregroundColor(AppColors.textPrimary)

            HStack(spacing: AppSpacing.lg) {
                runnerOption("local", "Local Runner", "Build and test on this Mac", "desktopcomputer")
                runnerOption("remote", "Remote Runner", "Use a registered remote Mac", "network")
            }

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Simulator Target")
                    .font(AppFont.body())
                    .foregroundColor(AppColors.textSecondary)
                TextField("iPhone 16 Pro", text: $simulatorTarget)
                    .textFieldStyle(.plain)
                    .font(AppFont.body())
                    .foregroundColor(AppColors.textPrimary)
                    .padding(AppSpacing.md)
                    .background(AppColors.inputBackground)
                    .cornerRadius(6)
            }
        }
    }

    private func runnerOption(_ value: String, _ title: String, _ desc: String, _ icon: String) -> some View {
        Button(action: { runnerMode = value }) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(runnerMode == value ? AppColors.accentBlue : AppColors.textTertiary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(AppFont.subheading())
                        .foregroundColor(AppColors.textPrimary)
                    Text(desc)
                        .font(AppFont.caption())
                        .foregroundColor(AppColors.textSecondary)
                }
                Spacer()
                Image(systemName: runnerMode == value ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(runnerMode == value ? AppColors.accentBlue : AppColors.textTertiary)
            }
            .padding(AppSpacing.lg)
            .background(runnerMode == value ? AppColors.accentBlue.opacity(0.1) : AppColors.inputBackground)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(runnerMode == value ? AppColors.accentBlue : AppColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var credentialsStep: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            Text("Test Credentials")
                .font(AppFont.heading())
                .foregroundColor(AppColors.textPrimary)

            Text("Credentials are stored securely in the macOS Keychain.")
                .font(AppFont.caption())
                .foregroundColor(AppColors.textSecondary)

            wizardField("Test Email (TEST_EMAIL)", text: .constant(""), placeholder: "test@example.com")
            wizardSecureField("Test Password (TEST_PASSWORD)", placeholder: "••••••••")
        }
    }

    private var integrationsStep: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            Text("Connect Integrations")
                .font(AppFont.heading())
                .foregroundColor(AppColors.textPrimary)

            Text("You can skip this step and configure integrations later.")
                .font(AppFont.caption())
                .foregroundColor(AppColors.textSecondary)

            ForEach(["GitHub", "Jira", "Slack", "Email"], id: \.self) { integration in
                HStack {
                    Text(integration)
                        .font(AppFont.subheading())
                        .foregroundColor(AppColors.textPrimary)
                    Spacer()
                    Button("Connect") {}
                        .buttonStyle(.plain)
                        .foregroundColor(AppColors.accentBlue)
                }
                .padding(AppSpacing.md)
                .background(AppColors.inputBackground)
                .cornerRadius(6)
            }
        }
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            Text("Review Configuration")
                .font(AppFont.heading())
                .foregroundColor(AppColors.textPrimary)

            VStack(spacing: AppSpacing.sm) {
                reviewRow("Repository", repoSource == "github" ? repoURL : localPath)
                reviewRow("Project Name", projectName)
                reviewRow("Workspace", workspace)
                reviewRow("Scheme", scheme)
                reviewRow("Bundle ID", bundleId)
                reviewRow("Runner", runnerMode.capitalized)
                reviewRow("Simulator", simulatorTarget)
            }
            .cardStyle()
        }
    }

    // MARK: - Helpers
    private func wizardField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(label)
                .font(AppFont.body())
                .foregroundColor(AppColors.textSecondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(AppFont.body())
                .foregroundColor(AppColors.textPrimary)
                .padding(AppSpacing.md)
                .background(AppColors.inputBackground)
                .cornerRadius(6)
        }
    }

    private func wizardSecureField(_ label: String, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(label)
                .font(AppFont.body())
                .foregroundColor(AppColors.textSecondary)
            SecureField(placeholder, text: .constant(""))
                .textFieldStyle(.plain)
                .font(AppFont.body())
                .foregroundColor(AppColors.textPrimary)
                .padding(AppSpacing.md)
                .background(AppColors.inputBackground)
                .cornerRadius(6)
        }
    }

    private func reviewRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(AppFont.body())
                .foregroundColor(AppColors.textSecondary)
                .frame(width: 120, alignment: .leading)
            Text(value.isEmpty ? "--" : value)
                .font(AppFont.body())
                .foregroundColor(AppColors.textPrimary)
            Spacer()
        }
    }

    private func createProject() {
        let project = QAProject(
            name: projectName.isEmpty ? "New Project" : projectName,
            repoType: repoSource,
            repoIdentifier: repoSource == "github" ? repoURL : "",
            localRepoPath: repoSource == "local" ? localPath : nil,
            workspacePath: workspace.isEmpty ? nil : workspace,
            scheme: scheme, bundleId: bundleId, runnerMode: runnerMode
        )
        DatabaseManager.shared.insertProject(project)
        appState.loadData()
        appState.selectProject(project.id)
        dismiss()
    }
}
