import SwiftUI

// MARK: - Persistent Settings Manager
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var notifyOnRunComplete: Bool {
        didSet { UserDefaults.standard.set(notifyOnRunComplete, forKey: "notifyOnRunComplete") }
    }
    @Published var notifyOnCriticalFinding: Bool {
        didSet { UserDefaults.standard.set(notifyOnCriticalFinding, forKey: "notifyOnCriticalFinding") }
    }
    @Published var notifyOnBuildFailure: Bool {
        didSet { UserDefaults.standard.set(notifyOnBuildFailure, forKey: "notifyOnBuildFailure") }
    }
    @Published var dailyDigest: Bool {
        didSet { UserDefaults.standard.set(dailyDigest, forKey: "dailyDigest") }
    }
    @Published var keepVideosForFailedOnly: Bool {
        didSet { UserDefaults.standard.set(keepVideosForFailedOnly, forKey: "keepVideosForFailedOnly") }
    }
    @Published var verboseLogging: Bool {
        didSet { UserDefaults.standard.set(verboseLogging, forKey: "verboseLogging") }
    }
    @Published var includeAccessibilitySnapshots: Bool {
        didSet { UserDefaults.standard.set(includeAccessibilitySnapshots, forKey: "includeAccessibilitySnapshots") }
    }

    private init() {
        let defaults = UserDefaults.standard
        // Register defaults for first launch
        defaults.register(defaults: [
            "notifyOnRunComplete": true,
            "notifyOnCriticalFinding": true,
            "notifyOnBuildFailure": true,
            "dailyDigest": false,
            "keepVideosForFailedOnly": false,
            "verboseLogging": false,
            "includeAccessibilitySnapshots": true
        ])
        self.notifyOnRunComplete = defaults.bool(forKey: "notifyOnRunComplete")
        self.notifyOnCriticalFinding = defaults.bool(forKey: "notifyOnCriticalFinding")
        self.notifyOnBuildFailure = defaults.bool(forKey: "notifyOnBuildFailure")
        self.dailyDigest = defaults.bool(forKey: "dailyDigest")
        self.keepVideosForFailedOnly = defaults.bool(forKey: "keepVideosForFailedOnly")
        self.verboseLogging = defaults.bool(forKey: "verboseLogging")
        self.includeAccessibilitySnapshots = defaults.bool(forKey: "includeAccessibilitySnapshots")
    }
}

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var settings = AppSettings.shared
    @State private var selectedSection: String = "General"
    @State private var projectName: String = ""
    @State private var defaultEnvironment: String = ""
    @State private var defaultRunType: String = "Full Exploration"
    @State private var autoStartOnCommit: Bool = true
    @State private var compareAgainstPrevious: Bool = true
    @State private var generateAIDescriptions: Bool = true

    // Credential editing state
    @State private var editingCredentialKey: String?
    @State private var credentialEditValue: String = ""
    @State private var storedCredentialKeys: [String] = []

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
        .onAppear {
            if let p = appState.currentProject {
                projectName = p.name
                defaultEnvironment = appState.latestRun?.simulatorProfile ?? "iPhone 16 Pro"
            }
        }
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

                ForEach(availableSimulators(), id: \.self) { sim in
                    HStack {
                        Image(systemName: "iphone")
                            .foregroundColor(AppColors.textSecondary)
                        Text(sim)
                            .font(AppFont.body())
                            .foregroundColor(AppColors.textPrimary)
                        Spacer()
                        if sim == defaultEnvironment {
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

                credentialRow("TEST_EMAIL")
                credentialRow("TEST_PASSWORD")

                // Inline editor
                if let key = editingCredentialKey {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("Edit \(key)")
                            .font(AppFont.subheading(12))
                            .foregroundColor(AppColors.textPrimary)
                        HStack {
                            SecureField("Enter value", text: $credentialEditValue)
                                .textFieldStyle(.plain)
                                .font(AppFont.mono(12))
                                .foregroundColor(AppColors.textPrimary)
                                .padding(AppSpacing.sm)
                                .background(AppColors.inputBackground)
                                .cornerRadius(4)
                            Button("Save") {
                                let _ = KeychainService.shared.save(key: key, value: credentialEditValue)
                                credentialEditValue = ""
                                editingCredentialKey = nil
                                storedCredentialKeys = KeychainService.shared.listKeys()
                            }
                            .font(AppFont.subheading(12))
                            .foregroundColor(.white)
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.vertical, 6)
                            .background(AppColors.accentBlue)
                            .cornerRadius(6)
                            .buttonStyle(.plain)
                            Button("Cancel") {
                                credentialEditValue = ""
                                editingCredentialKey = nil
                            }
                            .font(AppFont.subheading(12))
                            .foregroundColor(AppColors.textSecondary)
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(AppSpacing.md)
                    .background(AppColors.cardBackground)
                    .cornerRadius(6)
                }
            }
            .onAppear { storedCredentialKeys = KeychainService.shared.listKeys() }
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
            settingsToggle("Notify on run complete", isOn: $settings.notifyOnRunComplete)
            settingsToggle("Notify on critical finding", isOn: $settings.notifyOnCriticalFinding)
            settingsToggle("Notify on build failure", isOn: $settings.notifyOnBuildFailure)
            settingsToggle("Daily digest email", isOn: $settings.dailyDigest)

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
            settingsToggle("Keep videos for failed runs only", isOn: $settings.keepVideosForFailedOnly)

            Divider().background(AppColors.border)

            settingsDropdown("Derived Data Mode", value: "Isolated")
            settingsToggle("Verbose logging", isOn: $settings.verboseLogging)
            settingsToggle("Include accessibility snapshots in artifacts", isOn: $settings.includeAccessibilitySnapshots)

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
                    Text(databaseSize())
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

    private func credentialRow(_ key: String) -> some View {
        let hasValue = storedCredentialKeys.contains(key)
        return HStack {
            Text(key)
                .font(AppFont.mono(12))
                .foregroundColor(AppColors.textSecondary)
            Spacer()
            Text(hasValue ? "••••••••" : "Not set")
                .font(AppFont.mono(12))
                .foregroundColor(hasValue ? AppColors.textTertiary : AppColors.warning)
            Button("Edit") {
                editingCredentialKey = key
                credentialEditValue = ""
            }
            .font(AppFont.caption())
            .foregroundColor(AppColors.accentBlue)
            .buttonStyle(.plain)
            if hasValue {
                Button("Clear") {
                    let _ = KeychainService.shared.delete(key: key)
                    storedCredentialKeys = KeychainService.shared.listKeys()
                }
                .font(AppFont.caption())
                .foregroundColor(AppColors.error)
                .buttonStyle(.plain)
            }
        }
        .padding(AppSpacing.md)
        .background(AppColors.inputBackground)
        .cornerRadius(6)
    }

    private func availableSimulators() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "list", "devices", "available", "-j"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devices = json["devices"] as? [String: [[String: Any]]] else {
            return [defaultEnvironment].filter { !$0.isEmpty }
        }
        var names: [String] = []
        for (runtime, deviceList) in devices {
            for device in deviceList {
                if let name = device["name"] as? String, let state = device["state"] as? String {
                    let runtimeShort = runtime.components(separatedBy: ".").last?.replacingOccurrences(of: "-", with: ".") ?? ""
                    names.append("\(name) (\(runtimeShort)) - \(state)")
                }
            }
        }
        return Array(names.prefix(8))
    }

    private func databaseSize() -> String {
        let path = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first ?? ""
        let dbPath = (path as NSString).appendingPathComponent("OpenClawQA/openclaw-qa.db")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: dbPath),
              let bytes = attrs[.size] as? Int64 else { return "--" }
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1048576 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1048576.0)
    }
}
