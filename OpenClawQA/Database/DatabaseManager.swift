import Foundation
import SQLite3

// MARK: - Database Manager
final class DatabaseManager {
    static let shared = DatabaseManager()
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.openclaw.database", qos: .userInitiated)

    private init() {
        openDatabase()
        createTables()
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Open Database
    private func openDatabase() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("OpenClawQA")
        try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
        let dbPath = appDir.appendingPathComponent("openclaw-qa.db").path

        // Open in serialized mode (SQLITE_OPEN_FULLMUTEX) for thread-safe access
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(dbPath, &db, flags, nil) != SQLITE_OK {
            print("Error opening database: \(String(cString: sqlite3_errmsg(db)))")
        }
        execute("PRAGMA journal_mode=WAL")
        execute("PRAGMA foreign_keys=ON")
    }

    // MARK: - Execute
    @discardableResult
    private func execute(_ sql: String) -> Bool {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            if let error = error {
                print("SQL Error: \(String(cString: error))")
                sqlite3_free(error)
            }
            return false
        }
        return true
    }

    /// Serialize all DB access to prevent concurrent access crashes
    private func synchronized<T>(_ work: () -> T) -> T {
        queue.sync { work() }
    }

    // MARK: - Create Tables
    private func createTables() {
        execute("""
            CREATE TABLE IF NOT EXISTS projects (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                repo_type TEXT NOT NULL DEFAULT 'github',
                repo_identifier TEXT NOT NULL DEFAULT '',
                local_repo_path TEXT,
                default_branch TEXT NOT NULL DEFAULT 'main',
                workspace_path TEXT,
                project_path TEXT,
                scheme TEXT NOT NULL DEFAULT '',
                configuration TEXT NOT NULL DEFAULT 'Debug',
                bundle_id TEXT NOT NULL DEFAULT '',
                runner_mode TEXT NOT NULL DEFAULT 'local',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
        """)

        execute("""
            CREATE TABLE IF NOT EXISTS runs (
                id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL REFERENCES projects(id),
                trigger_source TEXT NOT NULL DEFAULT 'manual',
                trigger_metadata TEXT,
                branch TEXT NOT NULL DEFAULT 'main',
                commit_sha TEXT,
                pr_number INTEGER,
                status TEXT NOT NULL DEFAULT 'queued',
                phase TEXT NOT NULL DEFAULT 'queued',
                runner_id TEXT,
                xcode_version TEXT,
                simulator_profile TEXT,
                resolved_runtime TEXT,
                started_at TEXT,
                ended_at TEXT,
                confidence_score INTEGER,
                release_readiness TEXT,
                critical_findings INTEGER NOT NULL DEFAULT 0,
                high_findings INTEGER NOT NULL DEFAULT 0,
                medium_findings INTEGER NOT NULL DEFAULT 0,
                low_findings INTEGER NOT NULL DEFAULT 0,
                tests_executed INTEGER NOT NULL DEFAULT 0,
                flows_explored INTEGER NOT NULL DEFAULT 0,
                coverage_percent REAL NOT NULL DEFAULT 0,
                duration_ms INTEGER
            )
        """)

        execute("""
            CREATE TABLE IF NOT EXISTS findings (
                id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL REFERENCES projects(id),
                run_id TEXT NOT NULL REFERENCES runs(id),
                signature_hash TEXT NOT NULL,
                category TEXT NOT NULL,
                subtype TEXT,
                title TEXT NOT NULL,
                summary TEXT NOT NULL DEFAULT '',
                severity TEXT NOT NULL DEFAULT 'medium',
                confidence REAL NOT NULL DEFAULT 0.8,
                status TEXT NOT NULL DEFAULT 'open',
                first_seen_at TEXT NOT NULL,
                last_seen_at TEXT NOT NULL,
                evidence TEXT,
                repro_steps TEXT,
                metadata TEXT,
                flow TEXT,
                screen TEXT,
                environment TEXT,
                occurrences INTEGER NOT NULL DEFAULT 1,
                ai_analysis TEXT,
                suggested_fix TEXT,
                impact TEXT,
                affected_builds TEXT,
                assignee TEXT
            )
        """)

        execute("""
            CREATE TABLE IF NOT EXISTS screen_snapshots (
                id TEXT PRIMARY KEY,
                run_id TEXT NOT NULL REFERENCES runs(id),
                step_index INTEGER NOT NULL,
                timestamp TEXT NOT NULL,
                screen_fingerprint TEXT NOT NULL,
                screenshot_path TEXT,
                accessibility_tree_json TEXT,
                screen_classification TEXT,
                parent_snapshot_id TEXT
            )
        """)

        execute("""
            CREATE TABLE IF NOT EXISTS action_events (
                id TEXT PRIMARY KEY,
                run_id TEXT NOT NULL REFERENCES runs(id),
                step_index INTEGER NOT NULL,
                source_snapshot_id TEXT,
                action_type TEXT NOT NULL,
                target_descriptor TEXT,
                result TEXT NOT NULL DEFAULT 'success',
                timestamp TEXT NOT NULL,
                duration_ms INTEGER,
                produced_snapshot_id TEXT
            )
        """)

        execute("""
            CREATE TABLE IF NOT EXISTS environment_profiles (
                id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL REFERENCES projects(id),
                name TEXT NOT NULL,
                simulator_profile TEXT NOT NULL DEFAULT '',
                env_vars TEXT,
                launch_args TEXT,
                seed_strategy_type TEXT,
                reset_strategy_type TEXT,
                credentials_ref TEXT
            )
        """)

        execute("""
            CREATE TABLE IF NOT EXISTS integration_connections (
                id TEXT PRIMARY KEY,
                type TEXT NOT NULL,
                display_name TEXT NOT NULL,
                account_identifier TEXT,
                is_connected INTEGER NOT NULL DEFAULT 0,
                config_json TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
        """)

        execute("""
            CREATE TABLE IF NOT EXISTS artifacts (
                id TEXT PRIMARY KEY,
                run_id TEXT NOT NULL REFERENCES runs(id),
                type TEXT NOT NULL,
                path TEXT NOT NULL,
                metadata TEXT,
                created_at TEXT NOT NULL
            )
        """)

        execute("""
            CREATE TABLE IF NOT EXISTS runners (
                id TEXT PRIMARY KEY,
                mode TEXT NOT NULL DEFAULT 'local',
                display_name TEXT NOT NULL,
                capabilities TEXT,
                health_status TEXT NOT NULL DEFAULT 'healthy',
                xcode_versions TEXT,
                simulators TEXT,
                last_seen_at TEXT NOT NULL
            )
        """)

        execute("""
            CREATE TABLE IF NOT EXISTS run_phase_events (
                id TEXT PRIMARY KEY,
                run_id TEXT NOT NULL REFERENCES runs(id),
                phase TEXT NOT NULL,
                substep TEXT,
                status TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                payload TEXT
            )
        """)

        execute("""
            CREATE TABLE IF NOT EXISTS suppression_rules (
                id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL REFERENCES projects(id),
                rule_json TEXT NOT NULL,
                created_at TEXT NOT NULL,
                active INTEGER NOT NULL DEFAULT 1
            )
        """)
    }

    // MARK: - Date Formatting
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func dateStr(_ date: Date) -> String { Self.iso.string(from: date) }
    private func parseDate(_ str: String) -> Date { Self.iso.date(from: str) ?? Date() }

    // MARK: - Projects CRUD
    func fetchProjects() -> [QAProject] {
        synchronized {
            var projects: [QAProject] = []
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT * FROM projects ORDER BY updated_at DESC", -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    projects.append(projectFromRow(stmt!))
                }
            }
            sqlite3_finalize(stmt)
            return projects
        }
    }

    func insertProject(_ p: QAProject) {
        synchronized {
            let sql = "INSERT INTO projects (id, name, repo_type, repo_identifier, local_repo_path, default_branch, workspace_path, project_path, scheme, configuration, bundle_id, runner_mode, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                bindText(stmt, 1, p.id); bindText(stmt, 2, p.name); bindText(stmt, 3, p.repoType)
                bindText(stmt, 4, p.repoIdentifier); bindText(stmt, 5, p.localRepoPath)
                bindText(stmt, 6, p.defaultBranch); bindText(stmt, 7, p.workspacePath)
                bindText(stmt, 8, p.projectPath); bindText(stmt, 9, p.scheme)
                bindText(stmt, 10, p.configuration); bindText(stmt, 11, p.bundleId)
                bindText(stmt, 12, p.runnerMode); bindText(stmt, 13, dateStr(p.createdAt))
                bindText(stmt, 14, dateStr(p.updatedAt))
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    // MARK: - Runs CRUD
    func fetchRuns(projectId: String) -> [QARun] {
        synchronized {
            var runs: [QARun] = []
            var stmt: OpaquePointer?
            let sql = "SELECT * FROM runs WHERE project_id = ? ORDER BY started_at DESC"
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                bindText(stmt, 1, projectId)
                while sqlite3_step(stmt) == SQLITE_ROW {
                    runs.append(runFromRow(stmt!))
                }
            }
            sqlite3_finalize(stmt)
            return runs
        }
    }

    func insertRun(_ r: QARun) {
        synchronized {
            let sql = """
                INSERT INTO runs (id, project_id, trigger_source, trigger_metadata, branch, commit_sha, pr_number,
                status, phase, runner_id, xcode_version, simulator_profile, resolved_runtime, started_at, ended_at,
                confidence_score, release_readiness, critical_findings, high_findings, medium_findings, low_findings,
                tests_executed, flows_explored, coverage_percent, duration_ms) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                bindText(stmt, 1, r.id); bindText(stmt, 2, r.projectId)
                bindText(stmt, 3, r.triggerSource); bindText(stmt, 4, r.triggerMetadata)
                bindText(stmt, 5, r.branch); bindText(stmt, 6, r.commitSha)
                if let pr = r.prNumber { sqlite3_bind_int(stmt, 7, Int32(pr)) } else { sqlite3_bind_null(stmt, 7) }
                bindText(stmt, 8, r.status.rawValue); bindText(stmt, 9, r.phase.rawValue)
                bindText(stmt, 10, r.runnerId); bindText(stmt, 11, r.xcodeVersion)
                bindText(stmt, 12, r.simulatorProfile); bindText(stmt, 13, r.resolvedRuntime)
                bindText(stmt, 14, r.startedAt.map { dateStr($0) })
                bindText(stmt, 15, r.endedAt.map { dateStr($0) })
                if let cs = r.confidenceScore { sqlite3_bind_int(stmt, 16, Int32(cs)) } else { sqlite3_bind_null(stmt, 16) }
                bindText(stmt, 17, r.releaseReadiness?.rawValue)
                sqlite3_bind_int(stmt, 18, Int32(r.criticalFindings))
                sqlite3_bind_int(stmt, 19, Int32(r.highFindings))
                sqlite3_bind_int(stmt, 20, Int32(r.mediumFindings))
                sqlite3_bind_int(stmt, 21, Int32(r.lowFindings))
                sqlite3_bind_int(stmt, 22, Int32(r.testsExecuted))
                sqlite3_bind_int(stmt, 23, Int32(r.flowsExplored))
                sqlite3_bind_double(stmt, 24, r.coveragePercent)
                if let d = r.durationMs { sqlite3_bind_int(stmt, 25, Int32(d)) } else { sqlite3_bind_null(stmt, 25) }
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    func updateRunStatus(_ runId: String, status: RunStatus, phase: RunPhase) {
        synchronized {
            execute("UPDATE runs SET status = '\(status.rawValue)', phase = '\(phase.rawValue)' WHERE id = '\(runId)'")
        }
    }

    // MARK: - Findings CRUD
    func fetchFindings(projectId: String) -> [QAFinding] {
        synchronized {
            var findings: [QAFinding] = []
            var stmt: OpaquePointer?
            let sql = "SELECT * FROM findings WHERE project_id = ? ORDER BY severity ASC, last_seen_at DESC"
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                bindText(stmt, 1, projectId)
                while sqlite3_step(stmt) == SQLITE_ROW {
                    findings.append(findingFromRow(stmt!))
                }
            }
            sqlite3_finalize(stmt)
            return findings
        }
    }

    func fetchFindingsForRun(_ runId: String) -> [QAFinding] {
        synchronized {
            var findings: [QAFinding] = []
            var stmt: OpaquePointer?
            let sql = "SELECT * FROM findings WHERE run_id = ? ORDER BY severity ASC"
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                bindText(stmt, 1, runId)
                while sqlite3_step(stmt) == SQLITE_ROW {
                    findings.append(findingFromRow(stmt!))
                }
            }
            sqlite3_finalize(stmt)
            return findings
        }
    }

    func insertFinding(_ f: QAFinding) {
        synchronized {
            let sql = """
                INSERT INTO findings (id, project_id, run_id, signature_hash, category, subtype, title, summary,
                severity, confidence, status, first_seen_at, last_seen_at, evidence, repro_steps, metadata,
                flow, screen, environment, occurrences, ai_analysis, suggested_fix, impact, affected_builds, assignee)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                bindText(stmt, 1, f.id); bindText(stmt, 2, f.projectId); bindText(stmt, 3, f.runId)
                bindText(stmt, 4, f.signatureHash); bindText(stmt, 5, f.category.rawValue)
                bindText(stmt, 6, f.subtype); bindText(stmt, 7, f.title); bindText(stmt, 8, f.summary)
                bindText(stmt, 9, f.severity.rawValue); sqlite3_bind_double(stmt, 10, f.confidence)
                bindText(stmt, 11, f.status.rawValue); bindText(stmt, 12, dateStr(f.firstSeenAt))
                bindText(stmt, 13, dateStr(f.lastSeenAt)); bindText(stmt, 14, f.evidence)
                bindText(stmt, 15, f.reproSteps); bindText(stmt, 16, f.metadata)
                bindText(stmt, 17, f.flow); bindText(stmt, 18, f.screen); bindText(stmt, 19, f.environment)
                sqlite3_bind_int(stmt, 20, Int32(f.occurrences)); bindText(stmt, 21, f.aiAnalysis)
                bindText(stmt, 22, f.suggestedFix); bindText(stmt, 23, f.impact)
                bindText(stmt, 24, f.affectedBuilds); bindText(stmt, 25, f.assignee)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    // MARK: - Integrations
    func fetchIntegrations() -> [IntegrationConnection] {
        synchronized {
            var items: [IntegrationConnection] = []
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT * FROM integration_connections ORDER BY type", -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    items.append(integrationFromRow(stmt!))
                }
            }
            sqlite3_finalize(stmt)
            return items
        }
    }

    func insertIntegration(_ i: IntegrationConnection) {
        synchronized {
            let sql = "INSERT INTO integration_connections (id, type, display_name, account_identifier, is_connected, config_json, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?)"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                bindText(stmt, 1, i.id); bindText(stmt, 2, i.type.rawValue); bindText(stmt, 3, i.displayName)
                bindText(stmt, 4, i.accountIdentifier); sqlite3_bind_int(stmt, 5, i.isConnected ? 1 : 0)
                bindText(stmt, 6, i.configJson); bindText(stmt, 7, dateStr(i.createdAt)); bindText(stmt, 8, dateStr(i.updatedAt))
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    // MARK: - Runners
    func fetchRunners() -> [QARunner] {
        synchronized {
            var items: [QARunner] = []
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT * FROM runners ORDER BY display_name", -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    items.append(runnerFromRow(stmt!))
                }
            }
            sqlite3_finalize(stmt)
            return items
        }
    }

    // MARK: - Screen Snapshots CRUD
    func insertScreenSnapshot(_ s: ScreenSnapshot) {
        synchronized {
            let sql = """
                INSERT INTO screen_snapshots (id, run_id, step_index, timestamp, screen_fingerprint,
                screenshot_path, accessibility_tree_json, screen_classification, parent_snapshot_id)
                VALUES (?,?,?,?,?,?,?,?,?)
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                bindText(stmt, 1, s.id); bindText(stmt, 2, s.runId)
                sqlite3_bind_int(stmt, 3, Int32(s.stepIndex))
                bindText(stmt, 4, dateStr(s.timestamp))
                bindText(stmt, 5, s.screenFingerprint)
                bindText(stmt, 6, s.screenshotPath)
                bindText(stmt, 7, s.accessibilityTreeJson)
                bindText(stmt, 8, s.screenClassification)
                bindText(stmt, 9, s.parentSnapshotId)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    func fetchScreenSnapshots(runId: String) -> [ScreenSnapshot] {
        synchronized {
            var items: [ScreenSnapshot] = []
            var stmt: OpaquePointer?
            let sql = "SELECT * FROM screen_snapshots WHERE run_id = ? ORDER BY step_index"
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                bindText(stmt, 1, runId)
                while sqlite3_step(stmt) == SQLITE_ROW {
                    items.append(ScreenSnapshot(
                        id: colText(stmt!, 0), runId: colText(stmt!, 1),
                        stepIndex: colInt(stmt!, 2),
                        timestamp: parseDate(colText(stmt!, 3)),
                        screenFingerprint: colText(stmt!, 4),
                        screenshotPath: colOptText(stmt!, 5),
                        accessibilityTreeJson: colOptText(stmt!, 6),
                        screenClassification: colOptText(stmt!, 7),
                        parentSnapshotId: colOptText(stmt!, 8)
                    ))
                }
            }
            sqlite3_finalize(stmt)
            return items
        }
    }

    // MARK: - Action Events CRUD
    func insertActionEvent(_ e: ActionEvent) {
        synchronized {
            let sql = """
                INSERT INTO action_events (id, run_id, step_index, source_snapshot_id, action_type,
                target_descriptor, result, timestamp, duration_ms, produced_snapshot_id)
                VALUES (?,?,?,?,?,?,?,?,?,?)
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                bindText(stmt, 1, e.id); bindText(stmt, 2, e.runId)
                sqlite3_bind_int(stmt, 3, Int32(e.stepIndex))
                bindText(stmt, 4, e.sourceSnapshotId)
                bindText(stmt, 5, e.actionType)
                bindText(stmt, 6, e.targetDescriptor)
                bindText(stmt, 7, e.result)
                bindText(stmt, 8, dateStr(e.timestamp))
                if let d = e.durationMs { sqlite3_bind_int(stmt, 9, Int32(d)) } else { sqlite3_bind_null(stmt, 9) }
                bindText(stmt, 10, e.producedSnapshotId)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    func fetchActionEvents(runId: String) -> [ActionEvent] {
        synchronized {
            var items: [ActionEvent] = []
            var stmt: OpaquePointer?
            let sql = "SELECT * FROM action_events WHERE run_id = ? ORDER BY step_index"
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                bindText(stmt, 1, runId)
                while sqlite3_step(stmt) == SQLITE_ROW {
                    items.append(ActionEvent(
                        id: colText(stmt!, 0), runId: colText(stmt!, 1),
                        stepIndex: colInt(stmt!, 2),
                        sourceSnapshotId: colOptText(stmt!, 3),
                        actionType: colText(stmt!, 4),
                        targetDescriptor: colOptText(stmt!, 5),
                        result: colText(stmt!, 6),
                        timestamp: parseDate(colText(stmt!, 7)),
                        durationMs: colOptInt(stmt!, 8),
                        producedSnapshotId: colOptText(stmt!, 9)
                    ))
                }
            }
            sqlite3_finalize(stmt)
            return items
        }
    }

    // MARK: - Helpers
    private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value = value {
            sqlite3_bind_text(stmt, index, (value as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func colText(_ stmt: OpaquePointer, _ index: Int32) -> String {
        if let cStr = sqlite3_column_text(stmt, index) { return String(cString: cStr) }
        return ""
    }

    private func colOptText(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        if sqlite3_column_type(stmt, index) == SQLITE_NULL { return nil }
        if let cStr = sqlite3_column_text(stmt, index) { return String(cString: cStr) }
        return nil
    }

    private func colInt(_ stmt: OpaquePointer, _ index: Int32) -> Int {
        Int(sqlite3_column_int(stmt, index))
    }

    private func colOptInt(_ stmt: OpaquePointer, _ index: Int32) -> Int? {
        if sqlite3_column_type(stmt, index) == SQLITE_NULL { return nil }
        return Int(sqlite3_column_int(stmt, index))
    }

    private func colDouble(_ stmt: OpaquePointer, _ index: Int32) -> Double {
        sqlite3_column_double(stmt, index)
    }

    // MARK: - Row Parsers
    private func projectFromRow(_ stmt: OpaquePointer) -> QAProject {
        QAProject(
            id: colText(stmt, 0), name: colText(stmt, 1), repoType: colText(stmt, 2),
            repoIdentifier: colText(stmt, 3), localRepoPath: colOptText(stmt, 4),
            defaultBranch: colText(stmt, 5), workspacePath: colOptText(stmt, 6),
            projectPath: colOptText(stmt, 7), scheme: colText(stmt, 8),
            configuration: colText(stmt, 9), bundleId: colText(stmt, 10),
            runnerMode: colText(stmt, 11), createdAt: parseDate(colText(stmt, 12)),
            updatedAt: parseDate(colText(stmt, 13))
        )
    }

    private func runFromRow(_ stmt: OpaquePointer) -> QARun {
        QARun(
            id: colText(stmt, 0), projectId: colText(stmt, 1),
            triggerSource: colText(stmt, 2), triggerMetadata: colOptText(stmt, 3),
            branch: colText(stmt, 4), commitSha: colOptText(stmt, 5),
            prNumber: colOptInt(stmt, 6),
            status: RunStatus(rawValue: colText(stmt, 7)) ?? .queued,
            phase: RunPhase(rawValue: colText(stmt, 8)) ?? .queued,
            runnerId: colOptText(stmt, 9), xcodeVersion: colOptText(stmt, 10),
            simulatorProfile: colOptText(stmt, 11), resolvedRuntime: colOptText(stmt, 12),
            startedAt: colOptText(stmt, 13).map { parseDate($0) },
            endedAt: colOptText(stmt, 14).map { parseDate($0) },
            confidenceScore: colOptInt(stmt, 15),
            releaseReadiness: colOptText(stmt, 16).flatMap { ReleaseReadiness(rawValue: $0) },
            criticalFindings: colInt(stmt, 17), highFindings: colInt(stmt, 18),
            mediumFindings: colInt(stmt, 19), lowFindings: colInt(stmt, 20),
            testsExecuted: colInt(stmt, 21), flowsExplored: colInt(stmt, 22),
            coveragePercent: colDouble(stmt, 23), durationMs: colOptInt(stmt, 24)
        )
    }

    private func findingFromRow(_ stmt: OpaquePointer) -> QAFinding {
        QAFinding(
            id: colText(stmt, 0), projectId: colText(stmt, 1), runId: colText(stmt, 2),
            signatureHash: colText(stmt, 3),
            category: FindingCategory(rawValue: colText(stmt, 4)) ?? .crash,
            subtype: colOptText(stmt, 5), title: colText(stmt, 6), summary: colText(stmt, 7),
            severity: FindingSeverity(rawValue: colText(stmt, 8)) ?? .medium,
            confidence: colDouble(stmt, 9),
            status: FindingStatus(rawValue: colText(stmt, 10)) ?? .open,
            firstSeenAt: parseDate(colText(stmt, 11)), lastSeenAt: parseDate(colText(stmt, 12)),
            evidence: colOptText(stmt, 13), reproSteps: colOptText(stmt, 14),
            metadata: colOptText(stmt, 15), flow: colOptText(stmt, 16),
            screen: colOptText(stmt, 17), environment: colOptText(stmt, 18),
            occurrences: colInt(stmt, 19), aiAnalysis: colOptText(stmt, 20),
            suggestedFix: colOptText(stmt, 21), impact: colOptText(stmt, 22),
            affectedBuilds: colOptText(stmt, 23), assignee: colOptText(stmt, 24)
        )
    }

    private func integrationFromRow(_ stmt: OpaquePointer) -> IntegrationConnection {
        IntegrationConnection(
            id: colText(stmt, 0),
            type: IntegrationType(rawValue: colText(stmt, 1)) ?? .github,
            displayName: colText(stmt, 2), accountIdentifier: colOptText(stmt, 3),
            isConnected: colInt(stmt, 4) == 1, configJson: colOptText(stmt, 5),
            createdAt: parseDate(colText(stmt, 6)), updatedAt: parseDate(colText(stmt, 7))
        )
    }

    private func runnerFromRow(_ stmt: OpaquePointer) -> QARunner {
        let xcVersions = (colOptText(stmt, 5) ?? "").split(separator: ",").map(String.init)
        let sims = (colOptText(stmt, 6) ?? "").split(separator: ",").map(String.init)
        return QARunner(
            id: colText(stmt, 0), mode: colText(stmt, 1), displayName: colText(stmt, 2),
            capabilities: colOptText(stmt, 3), healthStatus: colText(stmt, 4),
            xcodeVersions: xcVersions, simulators: sims, lastSeenAt: parseDate(colText(stmt, 7))
        )
    }

    // MARK: - Update Run (full)
    func updateRun(_ r: QARun) { synchronized {
        let sql = """
            UPDATE runs SET status = ?, phase = ?, runner_id = ?, xcode_version = ?,
            simulator_profile = ?, resolved_runtime = ?, started_at = ?, ended_at = ?,
            confidence_score = ?, release_readiness = ?, critical_findings = ?, high_findings = ?,
            medium_findings = ?, low_findings = ?, tests_executed = ?, flows_explored = ?,
            coverage_percent = ?, duration_ms = ?, commit_sha = ?, branch = ?
            WHERE id = ?
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, 1, r.status.rawValue)
            bindText(stmt, 2, r.phase.rawValue)
            bindText(stmt, 3, r.runnerId)
            bindText(stmt, 4, r.xcodeVersion)
            bindText(stmt, 5, r.simulatorProfile)
            bindText(stmt, 6, r.resolvedRuntime)
            bindText(stmt, 7, r.startedAt.map { dateStr($0) })
            bindText(stmt, 8, r.endedAt.map { dateStr($0) })
            if let cs = r.confidenceScore { sqlite3_bind_int(stmt, 9, Int32(cs)) } else { sqlite3_bind_null(stmt, 9) }
            bindText(stmt, 10, r.releaseReadiness?.rawValue)
            sqlite3_bind_int(stmt, 11, Int32(r.criticalFindings))
            sqlite3_bind_int(stmt, 12, Int32(r.highFindings))
            sqlite3_bind_int(stmt, 13, Int32(r.mediumFindings))
            sqlite3_bind_int(stmt, 14, Int32(r.lowFindings))
            sqlite3_bind_int(stmt, 15, Int32(r.testsExecuted))
            sqlite3_bind_int(stmt, 16, Int32(r.flowsExplored))
            sqlite3_bind_double(stmt, 17, r.coveragePercent)
            if let d = r.durationMs { sqlite3_bind_int(stmt, 18, Int32(d)) } else { sqlite3_bind_null(stmt, 18) }
            bindText(stmt, 19, r.commitSha)
            bindText(stmt, 20, r.branch)
            bindText(stmt, 21, r.id)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    } }

    // MARK: - Artifacts CRUD
    func insertArtifact(_ a: QAArtifact) { synchronized {
        let sql = "INSERT INTO artifacts (id, run_id, type, path, metadata, created_at) VALUES (?,?,?,?,?,?)"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, 1, a.id); bindText(stmt, 2, a.runId)
            bindText(stmt, 3, a.type); bindText(stmt, 4, a.path)
            bindText(stmt, 5, a.metadata); bindText(stmt, 6, dateStr(a.createdAt))
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    } }

    func fetchArtifacts(runId: String) -> [QAArtifact] { synchronized {
        var items: [QAArtifact] = []
        var stmt: OpaquePointer?
        let sql = "SELECT * FROM artifacts WHERE run_id = ? ORDER BY created_at"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, 1, runId)
            while sqlite3_step(stmt) == SQLITE_ROW {
                items.append(QAArtifact(
                    id: colText(stmt!, 0), runId: colText(stmt!, 1),
                    type: colText(stmt!, 2), path: colText(stmt!, 3),
                    metadata: colOptText(stmt!, 4), createdAt: parseDate(colText(stmt!, 5))
                ))
            }
        }
        sqlite3_finalize(stmt)
        return items
    } }

    // MARK: - Run Phase Events CRUD
    func insertRunPhaseEvent(_ e: RunPhaseEvent) { synchronized {
        let sql = "INSERT INTO run_phase_events (id, run_id, phase, substep, status, timestamp, payload) VALUES (?,?,?,?,?,?,?)"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, 1, e.id); bindText(stmt, 2, e.runId)
            bindText(stmt, 3, e.phase); bindText(stmt, 4, e.substep)
            bindText(stmt, 5, e.status); bindText(stmt, 6, dateStr(e.timestamp))
            bindText(stmt, 7, e.payload)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    } }

    func fetchRunPhaseEvents(runId: String) -> [RunPhaseEvent] { synchronized {
        var items: [RunPhaseEvent] = []
        var stmt: OpaquePointer?
        let sql = "SELECT * FROM run_phase_events WHERE run_id = ? ORDER BY timestamp"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, 1, runId)
            while sqlite3_step(stmt) == SQLITE_ROW {
                items.append(RunPhaseEvent(
                    id: colText(stmt!, 0), runId: colText(stmt!, 1),
                    phase: colText(stmt!, 2), substep: colOptText(stmt!, 3),
                    status: colText(stmt!, 4), timestamp: parseDate(colText(stmt!, 5)),
                    payload: colOptText(stmt!, 6)
                ))
            }
        }
        sqlite3_finalize(stmt)
        return items
    } }

    // MARK: - Delete All Data (for reset)
    func deleteAllData() { synchronized {
        execute("DELETE FROM findings")
        execute("DELETE FROM run_phase_events")
        execute("DELETE FROM artifacts")
        execute("DELETE FROM runs")
        execute("DELETE FROM integration_connections")
        execute("DELETE FROM projects")
    } }
}
