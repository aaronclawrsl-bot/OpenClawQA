import XCTest

/// Autonomous exploration engine for iOS QA.
/// Runs as a UI test that attaches to any app via bundle ID.
/// Communicates results via OCQA_ prefixed stdout markers.
///
/// Fully generalized — no app-specific logic. Uses depth-first exploration
/// that prioritizes in-screen content over persistent navigation (tab bars).
///
/// Modes:
/// - testAutonomousExploration: Full autonomous exploration loop
/// - testDumpUITree: One-shot accessibility tree dump
/// - testTapAtCoordinate / testTapById: Single action for engine control
/// - testScreenshot: Capture and attach a screenshot
class ExplorerTests: XCTestCase {

    var app: XCUIApplication!
    var config: [String: Any] = [:]
    /// Detected once at setUp; avoids hardcoded device dimensions
    private var screenBounds: CGRect = .zero

    var targetBundleId: String { config["OCQA_BUNDLE_ID"] as? String ?? ProcessInfo.processInfo.environment["OCQA_BUNDLE_ID"] ?? "" }
    var maxActions: Int { Int(config["OCQA_MAX_ACTIONS"] as? String ?? ProcessInfo.processInfo.environment["OCQA_MAX_ACTIONS"] ?? "200") ?? 200 }
    var timeoutSeconds: Int { Int(config["OCQA_TIMEOUT_SECONDS"] as? String ?? ProcessInfo.processInfo.environment["OCQA_TIMEOUT_SECONDS"] ?? "1800") ?? 1800 }
    /// Launch arguments to forward to the target app (e.g. ["--uitesting"])
    var appLaunchArgs: [String] { config["OCQA_APP_LAUNCH_ARGS"] as? [String] ?? [] }
    /// Environment variables to forward to the target app (e.g. ["UI_TEST_ROLE": "resident"])
    var appLaunchEnv: [String: String] {
        if let dict = config["OCQA_APP_LAUNCH_ENV"] as? [String: String] { return dict }
        return [:]
    }

    /// Resolve a string key: config (as String) -> process environment -> fallback
    private func resolve(_ key: String, fallback: String = "") -> String {
        if let v = config[key] as? String { return v }
        if let v = ProcessInfo.processInfo.environment[key], !v.isEmpty { return v }
        return fallback
    }

    private func loadConfig() {
        let paths = [
            "/tmp/ocqa-run-config.json",
            NSTemporaryDirectory() + "ocqa-run-config.json",
            ProcessInfo.processInfo.environment["OCQA_CONFIG_PATH"] ?? "",
        ]
        for path in paths where !path.isEmpty {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                config = dict
                return
            }
        }
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
        loadConfig()
        if !targetBundleId.isEmpty {
            app = XCUIApplication(bundleIdentifier: targetBundleId)
        } else {
            app = XCUIApplication()
        }

        // Handle system alerts (location, notifications, tracking, etc.)
        addUIInterruptionMonitor(withDescription: "System Alert") { alert in
            let allowLabels = ["Allow", "Allow While Using App", "OK", "Continue", "Allow Full Access"]
            for label in allowLabels {
                let btn = alert.buttons[label]
                if btn.exists {
                    btn.tap()
                    return true
                }
            }
            if alert.buttons.count > 0 {
                alert.buttons.element(boundBy: 0).tap()
                return true
            }
            return false
        }

        // Launch with auth-bypass args if configured, otherwise just activate
        if !appLaunchArgs.isEmpty || !appLaunchEnv.isEmpty {
            app.launchArguments = appLaunchArgs
            app.launchEnvironment = appLaunchEnv
            app.launch()
            _ = app.wait(for: .runningForeground, timeout: 10)
        } else {
            app.activate()
            let started = app.wait(for: .runningForeground, timeout: 10)
            if !started {
                app.launch()
                _ = app.wait(for: .runningForeground, timeout: 10)
            }
        }

        // Detect actual screen dimensions from the running app
        let windowFrame = app.windows.firstMatch.frame
        if windowFrame.width > 0 && windowFrame.height > 0 {
            screenBounds = windowFrame
        } else {
            screenBounds = app.frame
        }
    }

    // MARK: - UI Tree Dump

    func testDumpUITree() {
        let elements = readUITree(app)
        let state = buildAppState(elements: elements)
        emitUITree(state)
    }

    // MARK: - Tap Actions

    func testTapAtCoordinate() {
        let xStr = resolve("OCQA_TAP_X")
        let yStr = resolve("OCQA_TAP_Y")
        guard !xStr.isEmpty, !yStr.isEmpty,
              let x = Double(xStr), let y = Double(yStr) else {
            XCTFail("OCQA_TAP_X and OCQA_TAP_Y must be set")
            return
        }
        let coord = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: x, dy: y))
        coord.tap()
        print("OCQA_ACTION:{\"type\":\"tap\",\"x\":\(x),\"y\":\(y)}")
        Thread.sleep(forTimeInterval: 0.5)
    }

    func testTapById() {
        let identifier = resolve("OCQA_TAP_ID")
        guard !identifier.isEmpty else {
            XCTFail("OCQA_TAP_ID must be set")
            return
        }
        let queries: [XCUIElementQuery] = [
            app.buttons, app.staticTexts, app.cells,
            app.links, app.switches, app.textFields
        ]
        for query in queries {
            let element = query[identifier]
            if element.exists && element.isHittable {
                element.tap()
                print("OCQA_ACTION:{\"type\":\"tap\",\"identifier\":\"\(identifier)\"}")
                Thread.sleep(forTimeInterval: 0.5)
                return
            }
        }
        let predicate = NSPredicate(format: "label == %@", identifier)
        let match = app.descendants(matching: .any).matching(predicate).firstMatch
        if match.exists && match.isHittable {
            match.tap()
            print("OCQA_ACTION:{\"type\":\"tap\",\"label\":\"\(identifier)\"}")
        } else {
            print("OCQA_ACTION:{\"type\":\"tap\",\"identifier\":\"\(identifier)\",\"status\":\"not_found\"}")
        }
        Thread.sleep(forTimeInterval: 0.5)
    }

    // MARK: - Swipe Actions

    func testSwipe() {
        let dir = resolve("OCQA_SWIPE_DIR", fallback: "up")
        switch dir {
        case "up":    app.swipeUp()
        case "down":  app.swipeDown()
        case "left":  app.swipeLeft()
        case "right": app.swipeRight()
        default:      app.swipeUp()
        }
        print("OCQA_ACTION:{\"type\":\"swipe\",\"direction\":\"\(dir)\"}")
        Thread.sleep(forTimeInterval: 0.5)
    }

    // MARK: - Type Text

    func testTypeText() {
        let text = resolve("OCQA_TYPE_TEXT")
        guard !text.isEmpty else {
            XCTFail("OCQA_TYPE_TEXT must be set")
            return
        }
        let identifier = resolve("OCQA_TYPE_ID")
        if !identifier.isEmpty {
            let field = app.textFields[identifier]
            if field.exists {
                field.tap()
                field.typeText(text)
                print("OCQA_ACTION:{\"type\":\"typeText\",\"identifier\":\"\(identifier)\"}")
                return
            }
            let secure = app.secureTextFields[identifier]
            if secure.exists {
                secure.tap()
                secure.typeText(text)
                print("OCQA_ACTION:{\"type\":\"typeText\",\"identifier\":\"\(identifier)\"}")
                return
            }
        }
        let firstField = app.textFields.firstMatch
        if firstField.exists {
            firstField.tap()
            firstField.typeText(text)
        }
        print("OCQA_ACTION:{\"type\":\"typeText\"}")
    }

    // MARK: - Navigation

    func testGoBack() {
        let backButton = app.navigationBars.buttons.firstMatch
        if backButton.exists && backButton.isHittable {
            backButton.tap()
            print("OCQA_ACTION:{\"type\":\"back\",\"method\":\"button\"}")
        } else {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: end)
            print("OCQA_ACTION:{\"type\":\"back\",\"method\":\"swipe\"}")
        }
        Thread.sleep(forTimeInterval: 0.5)
    }

    // MARK: - Screenshot

    func testScreenshot() {
        let label = resolve("OCQA_SCREENSHOT_LABEL", fallback: "screenshot")
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = label
        attachment.lifetime = .keepAlways
        add(attachment)
        print("OCQA_ACTION:{\"type\":\"screenshot\",\"label\":\"\(label)\"}")
    }

    // MARK: - Full Autonomous Exploration

    func testAutonomousExploration() {
        let maxActions = self.maxActions
        let timeoutSeconds = Double(self.timeoutSeconds)

        var visitedStates = Set<String>()
        var stateTransitions: [(from: String, to: String, action: String)] = []
        var actionCounts: [String: Int] = [:]
        var previousStateHash: String?
        var repeatedStateCount = 0
        var actionCount = 0
        var issues: [(type: String, severity: String, title: String, desc: String)] = []
        var screenTitles: [String: String] = [:] // hash -> title
        /// Tracks element keys that appear in multiple distinct screen hashes — likely persistent nav
        var elementScreenPresence: [String: Set<String>] = [:]
        var totalDistinctStates = 0
        let startTime = Date()

        if !targetBundleId.isEmpty {
            app.activate()
        } else {
            app.launch()
        }

        // Wait for app to settle — poll until element count stabilizes
        var lastCount = 0
        for _ in 0..<5 {
            Thread.sleep(forTimeInterval: 0.4)
            let query = app.descendants(matching: .any)
            _ = query.firstMatch.waitForExistence(timeout: 3)
            let count = query.count
            if count > 10 && count == lastCount { break }
            lastCount = count
        }

        print("OCQA_STATE:exploration_started max_actions=\(maxActions)")

        // --- Login preamble: if credentials are provided and login fields are visible, log in first ---
        let testEmail = resolve("OCQA_TEST_EMAIL")
        let testPassword = resolve("OCQA_TEST_PASSWORD")
        if !testEmail.isEmpty, !testPassword.isEmpty {
            Thread.sleep(forTimeInterval: 1.0) // let app fully settle
            let allTextFields = app.textFields.allElementsBoundByIndex.filter { $0.exists && $0.frame.width > 0 }
            let allSecureFields = app.secureTextFields.allElementsBoundByIndex.filter { $0.exists && $0.frame.width > 0 }
            print("OCQA_STATE:login_preamble_fields textFields=\(allTextFields.count) secureFields=\(allSecureFields.count)")

            let emailField = allTextFields.first { f in
                let hint = (f.identifier + " " + (f.placeholderValue ?? "") + " " + f.label).lowercased()
                return hint.contains("email") || hint.contains("e-mail")
            } ?? (allSecureFields.count > 0 ? allTextFields.first : nil)

            let passwordField = allSecureFields.first
                ?? allTextFields.first { f in
                    let hint = (f.identifier + " " + (f.placeholderValue ?? "") + " " + f.label).lowercased()
                    return hint.contains("password") || hint.contains("passcode")
                }

            if let emailF = emailField, emailF.exists, let passF = passwordField, passF.exists {
                print("OCQA_STATE:login_preamble_attempting")
                emailF.tap()
                Thread.sleep(forTimeInterval: 0.3)
                emailF.typeText(testEmail)
                Thread.sleep(forTimeInterval: 0.3)

                passF.tap()
                Thread.sleep(forTimeInterval: 0.3)
                passF.typeText(testPassword)
                Thread.sleep(forTimeInterval: 0.3)

                // Dismiss keyboard
                let keyboard = app.keyboards.firstMatch
                if keyboard.exists {
                    let aboveKeyboard = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
                    aboveKeyboard.tap()
                    Thread.sleep(forTimeInterval: 0.3)
                }

                // Find and tap login/sign-in button
                let loginLabels = ["Log In", "Login", "Sign In", "Sign in", "log in", "LOG IN", "SIGN IN"]
                var tappedLogin = false
                for label in loginLabels {
                    let btn = app.buttons[label]
                    if btn.exists && btn.isHittable {
                        btn.tap()
                        tappedLogin = true
                        break
                    }
                    let st = app.staticTexts[label]
                    if st.exists && st.isHittable {
                        st.tap()
                        tappedLogin = true
                        break
                    }
                }
                if tappedLogin {
                    print("OCQA_STATE:login_preamble_submitted")
                    Thread.sleep(forTimeInterval: 3.0)
                    var lastC = 0
                    for _ in 0..<5 {
                        Thread.sleep(forTimeInterval: 0.5)
                        let c = app.descendants(matching: .any).count
                        if c > 10 && c == lastC { break }
                        lastC = c
                    }
                } else {
                    print("OCQA_STATE:login_preamble_no_submit_button")
                }
            }
        }

        // Trigger the interruption monitor on any pending system alerts
        app.tap()
        Thread.sleep(forTimeInterval: 0.3)

        while actionCount < maxActions {
            if Date().timeIntervalSince(startTime) > timeoutSeconds {
                print("OCQA_STATE:timeout_reached")
                break
            }

            let elements = readUITree(app)
            let stateHash = computeHash(elements)
            let screenTitle = detectTitle(elements)

            if let title = screenTitle {
                screenTitles[stateHash] = title
            }

            // Track which elements appear on which screens (for persistent-nav detection)
            if !visitedStates.contains(stateHash) {
                totalDistinctStates += 1
                for el in elements where el.isEnabled && isInteractable(el.type) {
                    let key = actionKey(for: el)
                    elementScreenPresence[key, default: []].insert(stateHash)
                }
            }

            if previousStateHash == stateHash {
                repeatedStateCount += 1
            } else {
                repeatedStateCount = 0
            }
            previousStateHash = stateHash

            visitedStates.insert(stateHash)

            // Emit screen state
            let titleStr = screenTitle ?? "Unknown"
            let escapedTitle = escapeJSON(titleStr)
            print("OCQA_STATE:{\"screen\":\"\(escapedTitle)\",\"hash\":\"\(stateHash)\",\"elements\":\(elements.count),\"action\":\(actionCount)}")

            // Screenshot
            let screenshot = app.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "state_\(actionCount)_\(titleStr.replacingOccurrences(of: " ", with: "_"))"
            attachment.lifetime = .keepAlways
            add(attachment)

            let interactable = elements.filter { $0.isEnabled && $0.isHittable && isInteractable($0.type) }

            // ---- Repeated state: try scroll, then go back ----
            if repeatedStateCount >= 3 {
                if repeatedStateCount <= 4 {
                    let direction = repeatedStateCount == 3
                    let _ = performScroll(in: app, upward: direction)
                    actionCount += 1
                    let dirStr = direction ? "up" : "down"
                    print("OCQA_ACTION:{\"type\":\"scroll\",\"direction\":\"\(dirStr)\",\"step\":\(actionCount)}")
                    Thread.sleep(forTimeInterval: 0.5)
                    emitProgress(action: actionCount, maxActions: maxActions, states: visitedStates.count)
                    continue
                } else {
                    if tryGoBack() {
                        actionCount += 1
                        print("OCQA_ACTION:{\"type\":\"back\",\"reason\":\"stuck\",\"step\":\(actionCount)}")
                        Thread.sleep(forTimeInterval: 0.5)
                        repeatedStateCount = 0
                        emitProgress(action: actionCount, maxActions: maxActions, states: visitedStates.count)
                        continue
                    }
                }
            }

            // ---- Dead end ----
            if interactable.isEmpty {
                let issueTitle = "Dead end: \(titleStr)"
                issues.append((type: "dead_end", severity: "medium", title: issueTitle, desc: "No interactable elements found"))
                print("OCQA_ISSUE:{\"type\":\"dead_end\",\"severity\":\"medium\",\"title\":\"\(escapedTitle)\",\"screen\":\"\(escapedTitle)\",\"step\":\(actionCount)}")
                if !tryGoBack() { break }
                actionCount += 1
                continue
            }

            // ---- Pick and execute action ----
            let persistentThreshold = max(2, totalDistinctStates / 2)
            let sorted = prioritizeElements(interactable, actionCounts: actionCounts,
                                            elementScreenPresence: elementScreenPresence,
                                            persistentThreshold: persistentThreshold,
                                            screenBounds: screenBounds)

            let target = sorted.first(where: { element in
                let key = actionKey(for: element)
                return (actionCounts[key] ?? 0) < 3
            }) ?? sorted.first
            guard let target else { break }

            if !isTextField(target.type) {
                dismissKeyboardIfNeeded()
            }

            let actionDesc = performSmartAction(on: target, in: app)
            actionCounts[actionKey(for: target), default: 0] += 1
            actionCount += 1

            let targetName = target.identifier.isEmpty ? target.label : target.identifier
            let escapedTarget = escapeJSON(targetName)
            let actionType = isTextField(target.type) ? "type" : "tap"
            print("OCQA_ACTION:{\"type\":\"\(actionType)\",\"target\":\"\(escapedTarget)\",\"elementType\":\"\(target.type)\",\"step\":\(actionCount),\"x\":\(Int(target.frame.midX)),\"y\":\(Int(target.frame.midY))}")

            Thread.sleep(forTimeInterval: 0.5)
            waitForAnimationsToSettle()

            // ---- Crash detection ----
            if !app.exists {
                issues.append((type: "crash", severity: "critical",
                               title: "App crashed",
                               desc: "App terminated after: \(actionDesc)"))
                print("OCQA_ISSUE:{\"type\":\"crash\",\"severity\":\"critical\",\"title\":\"App crashed\",\"action\":\"\(escapedTarget)\",\"step\":\(actionCount)}")
                app.activate()
                Thread.sleep(forTimeInterval: 3.0)
                if !app.exists { break }
            }

            // ---- Track transition (lightweight — full tree read deferred to next iteration) ----
            let postCount = app.descendants(matching: .any).count
            let cheapHash = String(format: "%08x", postCount ^ (postCount << 13))
            stateTransitions.append((from: stateHash, to: cheapHash, action: actionDesc))

            print("OCQA_TRANSITION:{\"from\":\"\(escapedTitle)\",\"fromHash\":\"\(stateHash)\",\"to\":\"pending\",\"toHash\":\"\(cheapHash)\",\"action\":\"\(escapedTarget)\"}")

            // ---- Loop detection ----
            let recentStates = stateTransitions.suffix(8).map(\.to)
            if recentStates.count >= 8 && Set(recentStates).count <= 2 {
                issues.append((type: "navigation_loop", severity: "high",
                               title: "Navigation loop detected on \(titleStr)",
                               desc: "Stuck cycling between states"))
                print("OCQA_ISSUE:{\"type\":\"navigation_loop\",\"severity\":\"high\",\"title\":\"Navigation loop on \(escapedTitle)\",\"screen\":\"\(escapedTitle)\",\"step\":\(actionCount)}")
                if !tryGoBack() { break }
            }

            emitProgress(action: actionCount, maxActions: maxActions, states: visitedStates.count)
        }

        let uniqueScreens = screenTitles.values
        let screenList = Array(Set(uniqueScreens)).sorted().joined(separator: ",")
        print("OCQA_COMPLETE:{\"actions\":\(actionCount),\"states\":\(visitedStates.count),\"issues\":\(issues.count),\"screens\":\"\(screenList)\"}")

        let finalScreenshot = app.screenshot()
        let finalAttachment = XCTAttachment(screenshot: finalScreenshot)
        finalAttachment.name = "final_state"
        finalAttachment.lifetime = .keepAlways
        add(finalAttachment)
    }

    // MARK: - Helpers

    private struct SimpleElement {
        let type: String
        let identifier: String
        let label: String
        let frame: CGRect
        let isEnabled: Bool
        let isHittable: Bool
        let xcElement: XCUIElement?
    }

    private func readUITree(_ app: XCUIApplication) -> [SimpleElement] {
        // Try snapshot-based read first — single IPC call, ~100x faster
        if let elements = readViaSnapshot(app), !elements.isEmpty {
            return elements
        }
        // Fallback to element-by-element read (pre-Xcode 15 or snapshot failure)
        return readElementByElement(app)
    }

    /// Reads the full UI tree via a single snapshot() call — dramatically faster than
    /// per-element queries since it's one IPC round-trip for the entire hierarchy.
    private func readViaSnapshot(_ app: XCUIApplication) -> [SimpleElement]? {
        guard let snapshot = try? app.snapshot() else { return nil }

        var elements: [SimpleElement] = []
        let limit = 200
        let safeScreen = screenBounds.width > 0 ? screenBounds : CGRect(x: 0, y: 0, width: 500, height: 1000)

        func walk(_ snap: XCUIElementSnapshot) {
            guard elements.count < limit else { return }

            let frame = snap.frame
            if frame.width > 0, frame.height > 0,
               frame.origin.x.isFinite, frame.origin.y.isFinite,
               frame.width.isFinite, frame.height.isFinite {

                let hittable = snap.isEnabled && safeScreen.contains(CGPoint(x: frame.midX, y: frame.midY))
                elements.append(SimpleElement(
                    type: String(describing: snap.elementType),
                    identifier: snap.identifier,
                    label: snap.label ?? "",
                    frame: frame,
                    isEnabled: snap.isEnabled,
                    isHittable: hittable,
                    xcElement: nil
                ))
            }

            for child in snap.children {
                guard elements.count < limit else { return }
                if let childSnap = child as? XCUIElementSnapshot {
                    walk(childSnap)
                }
            }
        }

        walk(snapshot)
        return elements
    }

    /// Fallback element-by-element read — slower but works on all Xcode versions.
    private func readElementByElement(_ app: XCUIApplication) -> [SimpleElement] {
        var elements: [SimpleElement] = []
        let query = app.descendants(matching: .any)
        _ = query.firstMatch.waitForExistence(timeout: 5)
        let count = query.count

        let safeScreen = screenBounds.width > 0 ? screenBounds : CGRect(x: 0, y: 0, width: 500, height: 1000)

        for i in 0..<min(count, 150) {
            let el = query.element(boundBy: i)
            guard el.exists else { continue }

            let frame = el.frame
            guard frame.width > 0, frame.height > 0,
                  frame.origin.x.isFinite, frame.origin.y.isFinite,
                  frame.width.isFinite, frame.height.isFinite else { continue }

            let hittable = el.isEnabled && safeScreen.contains(CGPoint(x: frame.midX, y: frame.midY))

            elements.append(SimpleElement(
                type: String(describing: el.elementType),
                identifier: el.identifier,
                label: el.label,
                frame: frame,
                isEnabled: el.isEnabled,
                isHittable: hittable,
                xcElement: el
            ))
        }
        return elements
    }

    private func actionKey(for element: SimpleElement) -> String {
        let id = element.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if !id.isEmpty { return "id:\(id)" }
        let label = element.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !label.isEmpty { return "label:\(label)" }
        return "frame:\(Int(element.frame.midX))x\(Int(element.frame.midY))"
    }

    private func computeHash(_ elements: [SimpleElement]) -> String {
        let structure = elements.map { "\($0.type):\($0.identifier):\($0.isEnabled)" }.joined(separator: "|")
        var hash: UInt64 = 5381
        for byte in structure.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }

    private func detectTitle(_ elements: [SimpleElement]) -> String? {
        // NavigationBar = rawValue: 74
        if let navTitle = elements.first(where: { $0.type.contains("rawValue: 74") || $0.type.contains("NavigationBar") }) {
            if !navTitle.identifier.isEmpty { return navTitle.identifier }
            if !navTitle.label.isEmpty { return navTitle.label }
        }
        let topThreshold = screenBounds.height > 0 ? screenBounds.height * 0.25 : 200.0
        // StaticText = rawValue: 48
        let topTexts = elements
            .filter { ($0.type.contains("rawValue: 48") || $0.type.contains("StaticText")) && $0.frame.minY < topThreshold && !$0.label.isEmpty }
            .sorted { ($0.frame.width * $0.frame.height) > ($1.frame.width * $1.frame.height) }
        return topTexts.first?.label
    }

    private func isInteractable(_ type: String) -> Bool {
        let interactableRawValues = [9, 49, 50, 39, 75, 40, 42, 53, 54, 56]
        for rv in interactableRawValues {
            if type.contains("rawValue: \(rv)") { return true }
        }
        let types = ["Button", "TextField", "SecureTextField", "Link", "Cell",
                     "Switch", "Slider", "Tab", "MenuItem", "SegmentedControl",
                     "Picker", "Toggle", "Stepper", "DatePicker"]
        return types.contains(where: { type.contains($0) })
    }

    private func isTextField(_ type: String) -> Bool {
        return type.contains("TextField") || type.contains("SecureTextField") ||
               type.contains("rawValue: 49") || type.contains("rawValue: 50")
    }

    private func prioritizeElements(
        _ elements: [SimpleElement],
        actionCounts: [String: Int],
        elementScreenPresence: [String: Set<String>],
        persistentThreshold: Int,
        screenBounds: CGRect
    ) -> [SimpleElement] {
        let bottomBarY = screenBounds.height > 0 ? screenBounds.height * 0.88 : 850.0

        return elements.sorted { a, b in
            let keyA = actionKey(for: a)
            let keyB = actionKey(for: b)

            let persistA = (elementScreenPresence[keyA]?.count ?? 0) >= persistentThreshold
            let persistB = (elementScreenPresence[keyB]?.count ?? 0) >= persistentThreshold
            if persistA != persistB { return !persistA }

            let countA = actionCounts[keyA] ?? 0
            let countB = actionCounts[keyB] ?? 0
            if countA != countB { return countA < countB }

            let inBarA = a.frame.midY > bottomBarY
            let inBarB = b.frame.midY > bottomBarY
            if inBarA != inBarB { return !inBarA }

            let pa = baseTypePriority(a.type)
            let pb = baseTypePriority(b.type)
            return pa > pb
        }
    }

    private func baseTypePriority(_ type: String) -> Int {
        if type.contains("Cell") || type.contains("rawValue: 75") { return 5 }
        if type.contains("Link") || type.contains("rawValue: 39") { return 4 }
        if type.contains("Button") || type.contains("rawValue: 9") { return 4 }
        if type.contains("SegmentedControl") || type.contains("Picker") { return 3 }
        if type.contains("TextField") || type.contains("rawValue: 49") || type.contains("rawValue: 50") { return 2 }
        if type.contains("Switch") || type.contains("Toggle") || type.contains("rawValue: 40") { return 1 }
        return 0
    }

    private func performSmartAction(on element: SimpleElement, in app: XCUIApplication) -> String {
        let frame = element.frame
        guard frame.width > 0, frame.height > 0 else {
            return "skip_invalid_frame"
        }

        let coord = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.midY))

        if isTextField(element.type) {
            coord.tap()
            Thread.sleep(forTimeInterval: 0.5)

            // Check if keyboard appeared — if not, the field didn't gain focus
            let keyboard = app.keyboards.firstMatch
            guard keyboard.waitForExistence(timeout: 1.0) else {
                let name = element.identifier.isEmpty ? element.label : element.identifier
                return "tap(\(name))_no_keyboard"
            }

            let hint = (element.identifier + " " + element.label).lowercased()
            let testText: String
            if hint.contains("email") || hint.contains("e-mail") {
                testText = resolve("OCQA_TEST_EMAIL", fallback: "test@example.com")
            } else if hint.contains("password") || hint.contains("passcode") {
                testText = resolve("OCQA_TEST_PASSWORD", fallback: "TestPass123!")
            } else if hint.contains("phone") || hint.contains("mobile") {
                testText = "5551234567"
            } else if hint.contains("name") || hint.contains("first") || hint.contains("last") {
                testText = "Test User"
            } else if hint.contains("zip") || hint.contains("postal") {
                testText = "90210"
            } else if hint.contains("search") {
                testText = "test"
            } else {
                testText = "test input"
            }
            if let xcEl = element.xcElement, xcEl.exists {
                xcEl.typeText(testText)
            } else {
                // Snapshot-based element — find the field closest to where we tapped
                let resolved: XCUIElement? = {
                    if !element.identifier.isEmpty {
                        let tf = app.textFields[element.identifier]
                        if tf.exists { return tf }
                        let stf = app.secureTextFields[element.identifier]
                        if stf.exists { return stf }
                    }
                    let allTextFields = app.textFields.allElementsBoundByIndex + app.secureTextFields.allElementsBoundByIndex
                    let tapped = CGPoint(x: frame.midX, y: frame.midY)
                    let closest = allTextFields
                        .filter { $0.exists && $0.frame.width > 0 }
                        .min(by: {
                            let d1 = abs($0.frame.midX - tapped.x) + abs($0.frame.midY - tapped.y)
                            let d2 = abs($1.frame.midX - tapped.x) + abs($1.frame.midY - tapped.y)
                            return d1 < d2
                        })
                    return closest
                }()
                if let resolved = resolved {
                    resolved.tap()
                    Thread.sleep(forTimeInterval: 0.3)
                    // Verify keyboard is still present before typing
                    if keyboard.exists {
                        resolved.typeText(testText)
                    }
                }
            }
            let name = element.identifier.isEmpty ? element.label : element.identifier
            return "type(\(name), \"\(testText)\")"
        }

        coord.tap()
        return "tap(\(element.identifier.isEmpty ? element.label : element.identifier))"
    }

    private func tryGoBack() -> Bool {
        let backButtons = app.navigationBars.buttons
        if backButtons.count > 0 {
            let first = backButtons.firstMatch
            if first.exists && first.isHittable {
                first.tap()
                Thread.sleep(forTimeInterval: 0.5)
                return true
            }
        }
        for label in ["Close", "Cancel", "Done", "Dismiss"] {
            let btn = app.buttons[label]
            if btn.exists && btn.isHittable {
                btn.tap()
                Thread.sleep(forTimeInterval: 0.5)
                return true
            }
        }
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        Thread.sleep(forTimeInterval: 0.5)
        return true
    }

    private func performScroll(in app: XCUIApplication, upward: Bool) -> String {
        let startY: CGFloat = upward ? 0.78 : 0.28
        let endY: CGFloat = upward ? 0.30 : 0.78
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY))
        start.press(forDuration: 0.05, thenDragTo: end)
        return upward ? "scroll_up" : "scroll_down"
    }

    private func performCoordinateTap(in app: XCUIApplication, at point: CGPoint, label: String) -> String {
        let coord = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point.x, dy: point.y))
        coord.tap()
        return "tap(\(label))"
    }

    private func waitForAnimationsToSettle() {
        Thread.sleep(forTimeInterval: 0.3)
    }

    private func dismissKeyboardIfNeeded() {
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists && keyboard.frame.height > 0 {
            let aboveKeyboard = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: screenBounds.width / 2, dy: keyboard.frame.minY - 20))
            aboveKeyboard.tap()
            Thread.sleep(forTimeInterval: 0.3)
        }
    }

    private func escapeJSON(_ str: String) -> String {
        return str
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "'")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private func emitUITree(_ state: (title: String?, elements: [SimpleElement])) {
        var json = "{\"screenTitle\":\"\(state.title ?? "Unknown")\",\"elements\":["
        let arr = state.elements.prefix(100).map { el in
            "{\"type\":\"\(el.type)\",\"id\":\"\(el.identifier)\",\"label\":\"\(el.label)\",\"enabled\":\(el.isEnabled),\"hittable\":\(el.isHittable),\"x\":\(Int(el.frame.midX)),\"y\":\(Int(el.frame.midY)),\"w\":\(Int(el.frame.width)),\"h\":\(Int(el.frame.height))}"
        }
        json += arr.joined(separator: ",")
        json += "]}"
        print("OCQA_UITREE_START")
        print(json)
        print("OCQA_UITREE_END")
    }

    private func buildAppState(elements: [SimpleElement]) -> (title: String?, elements: [SimpleElement]) {
        return (detectTitle(elements), elements)
    }

    private func emitProgress(action: Int, maxActions: Int, states: Int) {
        print("OCQA_PROGRESS:{\"action\":\(action),\"max\":\(maxActions),\"states\":\(states)}")
    }
}
