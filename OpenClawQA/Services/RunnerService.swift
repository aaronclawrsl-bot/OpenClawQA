import Foundation

// MARK: - Runner Service
// Manages local and remote runners for executing QA checks
final class RunnerService {
    static let shared = RunnerService()

    private init() {}

    struct RunnerHealth {
        var isOnline: Bool
        var xcodeVersion: String?
        var availableSimulators: [String]
        var diskFreeGB: Double?
        var lastChecked: Date
    }

    // Check local runner health
    func checkLocalHealth() async -> RunnerHealth {
        let xcodeVersion = await runCommand("xcodebuild", arguments: ["-version"])
        let simList = await runCommand("xcrun", arguments: ["simctl", "list", "devices", "available", "-j"])

        return RunnerHealth(
            isOnline: true,
            xcodeVersion: xcodeVersion?.components(separatedBy: "\n").first,
            availableSimulators: parseSimulators(simList ?? ""),
            diskFreeGB: checkDiskSpace(),
            lastChecked: Date()
        )
    }

    // Boot simulator
    func bootSimulator(udid: String) async -> Bool {
        let result = await runCommand("xcrun", arguments: ["simctl", "boot", udid])
        return result != nil
    }

    // Build project
    func buildProject(workspace: String, scheme: String, simulator: String, derivedDataPath: String) async -> (success: Bool, log: String) {
        let args = [
            "build-for-testing",
            "-workspace", workspace,
            "-scheme", scheme,
            "-destination", "platform=iOS Simulator,name=\(simulator)",
            "-derivedDataPath", derivedDataPath,
            "-quiet"
        ]
        let result = await runCommand("xcodebuild", arguments: args)
        return (result != nil, result ?? "Build failed")
    }

    // Run tests
    func runTests(workspace: String, scheme: String, simulator: String, testClass: String?) async -> (success: Bool, log: String) {
        var args = [
            "test",
            "-workspace", workspace,
            "-scheme", scheme,
            "-destination", "platform=iOS Simulator,name=\(simulator)",
            "-parallel-testing-enabled", "NO"
        ]
        if let testClass = testClass {
            args += ["-only-testing", testClass]
        }
        let result = await runCommand("xcodebuild", arguments: args)
        return (result != nil, result ?? "Test execution failed")
    }

    // MARK: - Remote Runner
    func executeOnRemoteRunner(host: String, user: String, command: String) async -> String? {
        let args = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=15",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=20",
            "\(user)@\(host)",
            command
        ]
        return await runCommand("ssh", arguments: args)
    }

    // MARK: - Helpers
    private func runCommand(_ command: String, arguments: [String]) async -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/\(command)")
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func parseSimulators(_ json: String) -> [String] {
        // Simple parser - extract device names from simctl JSON
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devices = obj["devices"] as? [String: [[String: Any]]] else { return [] }

        var names: [String] = []
        for (runtime, deviceList) in devices {
            for device in deviceList {
                if let name = device["name"] as? String,
                   let state = device["state"] as? String,
                   device["isAvailable"] as? Bool == true {
                    let osVersion = runtime.components(separatedBy: ".").last ?? ""
                    names.append("\(name) (\(osVersion)) - \(state)")
                }
            }
        }
        return names.sorted()
    }

    private func checkDiskSpace() -> Double? {
        let fileManager = FileManager.default
        guard let attrs = try? fileManager.attributesOfFileSystem(forPath: "/"),
              let freeSpace = attrs[.systemFreeSize] as? Int64 else { return nil }
        return Double(freeSpace) / 1_073_741_824 // Convert to GB
    }
}
