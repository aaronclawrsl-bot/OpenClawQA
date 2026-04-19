import Foundation

// MARK: - Runner Service
// Manages local and remote runners for executing QA checks
final class RunnerService {
    static let shared = RunnerService()

    private init() {}

    enum ProjectTarget {
        case project(String)   // -project path.xcodeproj
        case workspace(String) // -workspace path.xcworkspace
    }

    struct RunnerHealth {
        var isOnline: Bool
        var xcodeVersion: String?
        var availableSimulators: [String]
        var diskFreeGB: Double?
        var lastChecked: Date
    }

    // Check local runner health
    func checkLocalHealth() async -> RunnerHealth {
        let xcodeVersion = await runShellCommand("xcodebuild", arguments: ["-version"])
        let simList = await runShellCommand("xcrun", arguments: ["simctl", "list", "devices", "available", "-j"])

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
        let result = await runShellCommand("xcrun", arguments: ["simctl", "boot", udid])
        return result != nil
    }

    // Find simulator UDID by name
    func findSimulatorUDID(name: String) async -> String? {
        let json = await runShellCommand("xcrun", arguments: ["simctl", "list", "devices", "available", "-j"])
        guard let data = json?.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devices = obj["devices"] as? [String: [[String: Any]]] else { return nil }

        for (_, deviceList) in devices {
            for device in deviceList {
                if let deviceName = device["name"] as? String,
                   deviceName == name,
                   let udid = device["udid"] as? String,
                   device["isAvailable"] as? Bool == true {
                    return udid
                }
            }
        }
        return nil
    }

    // Build project (supports both -project and -workspace)
    func buildProject(projectOrWorkspace: ProjectTarget, scheme: String, simulator: String, derivedDataPath: String) async -> (success: Bool, log: String) {
        var args = ["build-for-testing"]

        switch projectOrWorkspace {
        case .project(let path):
            args += ["-project", path]
        case .workspace(let path):
            args += ["-workspace", path]
        }

        args += [
            "-scheme", scheme,
            "-destination", "platform=iOS Simulator,name=\(simulator)",
            "-derivedDataPath", derivedDataPath
        ]

        let result = await runShellCommand("xcodebuild", arguments: args)
        let success = result?.contains("BUILD SUCCEEDED") == true || result?.contains("** BUILD SUCCEEDED **") == true
        return (success, result ?? "Build produced no output")
    }

    // Run tests (supports both -project and -workspace)
    func runTests(projectOrWorkspace: ProjectTarget, scheme: String, simulator: String, derivedDataPath: String) async -> (success: Bool, log: String) {
        var args = ["test"]

        switch projectOrWorkspace {
        case .project(let path):
            args += ["-project", path]
        case .workspace(let path):
            args += ["-workspace", path]
        }

        args += [
            "-scheme", scheme,
            "-destination", "platform=iOS Simulator,name=\(simulator)",
            "-derivedDataPath", derivedDataPath,
            "-parallel-testing-enabled", "NO"
        ]

        let result = await runShellCommand("xcodebuild", arguments: args)
        let success = result?.contains("** TEST SUCCEEDED **") == true
        return (success, result ?? "Test execution produced no output")
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
        return await runShellCommand("ssh", arguments: args)
    }

    // MARK: - Video Recording

    /// Start recording the simulator screen. Returns the Process so it can be stopped later.
    func startVideoRecording(udid: String, outputPath: String) -> Process? {
        let process = Process()
        let paths = ["/usr/bin/xcrun", "/usr/local/bin/xcrun", "/opt/homebrew/bin/xcrun"]
        var execPath: String?
        for p in paths {
            if FileManager.default.fileExists(atPath: p) { execPath = p; break }
        }
        guard let resolvedPath = execPath else { return nil }

        process.executableURL = URL(fileURLWithPath: resolvedPath)
        process.arguments = ["simctl", "io", udid, "recordVideo", "--codec=h264", outputPath]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            return process
        } catch {
            return nil
        }
    }

    /// Stop a running video recording process gracefully via SIGINT.
    func stopVideoRecording(_ process: Process) {
        if process.isRunning {
            process.interrupt() // SIGINT triggers graceful stop
            process.waitUntilExit()
        }
    }

    // MARK: - Helpers (public for orchestrator access)
    func runShellCommand(_ command: String, arguments: [String]) async -> String? {
        let process = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()

        // Try common paths
        let paths = ["/usr/bin/\(command)", "/usr/local/bin/\(command)", "/opt/homebrew/bin/\(command)"]
        var execPath: String?
        for p in paths {
            if FileManager.default.fileExists(atPath: p) { execPath = p; break }
        }
        // Fall back to env lookup
        if execPath == nil {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + arguments
        } else {
            process.executableURL = URL(fileURLWithPath: execPath!)
            process.arguments = arguments
        }

        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()

            // Read pipes concurrently to avoid deadlock when output exceeds buffer size
            var outData = Data()
            var errData = Data()
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global().async {
                outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
            group.enter()
            DispatchQueue.global().async {
                errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
            process.waitUntilExit()
            group.wait()

            let output = String(data: outData, encoding: .utf8) ?? ""
            let errOutput = String(data: errData, encoding: .utf8) ?? ""
            return output + (errOutput.isEmpty ? "" : "\n" + errOutput)
        } catch {
            return nil
        }
    }

    private func parseSimulators(_ json: String) -> [String] {
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
        return Double(freeSpace) / 1_073_741_824
    }
}
