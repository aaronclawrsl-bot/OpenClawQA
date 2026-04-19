import XCTest

/// Autonomous exploration engine for iOS QA.
/// Runs as a UI test that attaches to any app via bundle ID.
/// Communicates results via OCQA_ prefixed stdout markers.
///
/// Modes:
/// - testAutonomousExploration: Full autonomous exploration loop
/// - testDumpUITree: One-shot accessibility tree dump
/// - testTapAtCoordinate / testTapById: Single action for engine control
/// - testScreenshot: Capture and attach a screenshot
class ExplorerTests: XCTestCase {

    var app: XCUIApplication!
    var config: [String: String] = [:]

    var targetBundleId: String { config["OCQA_BUNDLE_ID"] ?? ProcessInfo.processInfo.environment["OCQA_BUNDLE_ID"] ?? "" }
    var maxActions: Int { Int(config["OCQA_MAX_ACTIONS"] ?? ProcessInfo.processInfo.environment["OCQA_MAX_ACTIONS"] ?? "200") ?? 200 }
    var timeoutSeconds: Int { Int(config["OCQA_TIMEOUT_SECONDS"] ?? ProcessInfo.processInfo.environment["OCQA_TIMEOUT_SECONDS"] ?? "1800") ?? 1800 }

    private func loadConfig() {
        let paths = [
            "/tmp/ocqa-run-config.json",
            NSTemporaryDirectory() + "ocqa-run-config.json",
            ProcessInfo.processInfo.environment["OCQA_CONFIG_PATH"] ?? "",
        ]
        for path in paths where !path.isEmpty {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
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
        app.activate()
        let started = app.wait(for: .runningForeground, timeout: 10)
        if !started {
            app.launch()
            _ = app.wait(for: .runningForeground, timeout: 10)
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
        let env = config.merging(ProcessInfo.processInfo.environment) { a, _ in a }
        guard let xStr = env["OCQA_TAP_X"], let yStr = env["OCQA_TAP_Y"],
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
        let env = config.merging(ProcessInfo.processInfo.environment) { a, _ in a }
        guard let identifier = env["OCQA_TAP_ID"], !identifier.isEmpty else {
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
        let dir = config["OCQA_SWIPE_DIR"] ?? ProcessInfo.processInfo.environment["OCQA_SWIPE_DIR"] ?? "up"
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
        let env = config.merging(ProcessInfo.processInfo.environment) { a, _ in a }
        guard let text = env["OCQA_TYPE_TEXT"] else {
            XCTFail("OCQA_TYPE_TEXT must be set")
            return
        }
        if let identifier = env["OCQA_TYPE_ID"], !identifier.isEmpty {
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
        let label = config["OCQA_SCREENSHOT_LABEL"] ?? ProcessInfo.processInfo.environment["OCQA_SCREENSHOT_LABEL"] ?? "screenshot"
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
        var didToggleRewardsToRedeem = false
        var actionCount = 0
        var issues: [(type: String, severity: String, title: String, desc: String)] = []
        var screenTitles: [String: String] = [:] // hash -> title
        let startTime = Date()

        if !targetBundleId.isEmpty {
            app.activate()
        } else {
            app.launch()
        }
        Thread.sleep(forTimeInterval: 2.0)

        print("OCQA_STATE:exploration_started max_actions=\(maxActions)")

        while actionCount < maxActions {
            if Date().timeIntervalSince(startTime) > timeoutSeconds {
                print("OCQA_STATE:timeout_reached")
                break
            }

            let elements = readUITree(app)
            let flat = flattenElements(elements)
            let stateHash = computeHash(flat)
            let screenTitle = detectTitle(flat)

            if let title = screenTitle {
                screenTitles[stateHash] = title
            }

            if previousStateHash == stateHash {
                repeatedStateCount += 1
            } else {
                repeatedStateCount = 0
            }
            previousStateHash = stateHash

            visitedStates.insert(stateHash)

            // Emit screen state — desktop app parses this
            let titleStr = screenTitle ?? "Unknown"
            let escapedTitle = titleStr.replacingOccurrences(of: "\"", with: "'")
            print("OCQA_STATE:{\"screen\":\"\(escapedTitle)\",\"hash\":\"\(stateHash)\",\"elements\":\(flat.count),\"action\":\(actionCount)}")

            // Screenshot
            let screenshot = app.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "state_\(actionCount)_\(titleStr.replacingOccurrences(of: " ", with: "_"))"
            attachment.lifetime = .keepAlways
            add(attachment)

            let interactable = flat.filter { $0.isEnabled && $0.isHittable && isInteractable($0.type) }

            // ---- Special case: Rewards Earn/Redeem toggle ----
            let onRewardsScreen = flat.contains(where: { $0.identifier == "resident.rewards.screen" })
            let showingEarnMode = flat.contains(where: { $0.identifier == "resident.rewards.earnHeader" })
            let showingRedeemMode = flat.contains(where: { $0.identifier == "resident.rewards.redeemHeader" })

            if onRewardsScreen && showingEarnMode && !didToggleRewardsToRedeem {
                if let redeemSegment = flat.first(where: {
                    $0.identifier == "resident.rewards.modePicker" &&
                    $0.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "redeem"
                }) {
                    let actionDesc = performCoordinateTap(in: app, at: CGPoint(x: redeemSegment.frame.midX, y: redeemSegment.frame.midY), label: "Redeem")
                    didToggleRewardsToRedeem = true
                    actionCount += 1
                    print("OCQA_ACTION:{\"type\":\"tap\",\"target\":\"Redeem\",\"step\":\(actionCount)}")
                    Thread.sleep(forTimeInterval: 0.8)
                    emitProgress(action: actionCount, maxActions: maxActions, states: visitedStates.count)
                    continue
                }
                if let redeemTab = interactable.first(where: {
                    $0.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "redeem"
                }) {
                    let _ = performSmartAction(on: redeemTab, in: app)
                    didToggleRewardsToRedeem = true
                    actionCount += 1
                    print("OCQA_ACTION:{\"type\":\"tap\",\"target\":\"Redeem\",\"step\":\(actionCount)}")
                    Thread.sleep(forTimeInterval: 0.8)
                    emitProgress(action: actionCount, maxActions: maxActions, states: visitedStates.count)
                    continue
                }
            }

            // ---- Repeated state: try scrolling ----
            if repeatedStateCount >= 2 {
                let _ = performScroll(in: app, upward: true)
                actionCount += 1
                print("OCQA_ACTION:{\"type\":\"scroll\",\"direction\":\"up\",\"step\":\(actionCount)}")
                Thread.sleep(forTimeInterval: 0.8)
                emitProgress(action: actionCount, maxActions: maxActions, states: visitedStates.count)
                continue
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
            let sorted = prioritizeElements(interactable)
            let sortedNoPickerContainer = sorted.filter { $0.identifier != "resident.rewards.modePicker" }
            let candidatePool = sortedNoPickerContainer.isEmpty ? sorted : sortedNoPickerContainer
            let target = candidatePool.first(where: { element in
                let key = actionKey(for: element)
                return (actionCounts[key] ?? 0) < 2
            }) ?? candidatePool.first
            guard let target else { break }

            let actionDesc = performSmartAction(on: target, in: app)
            actionCounts[actionKey(for: target), default: 0] += 1
            actionCount += 1

            // Emit action with detail for the desktop app
            let targetName = target.identifier.isEmpty ? target.label : target.identifier
            let escapedTarget = targetName.replacingOccurrences(of: "\"", with: "'")
            let actionType = (target.type.contains("TextField") || target.type.contains("SecureTextField") ||
                              target.type.contains("rawValue: 49") || target.type.contains("rawValue: 50")) ? "type" : "tap"
            print("OCQA_ACTION:{\"type\":\"\(actionType)\",\"target\":\"\(escapedTarget)\",\"elementType\":\"\(target.type)\",\"step\":\(actionCount),\"x\":\(Int(target.frame.midX)),\"y\":\(Int(target.frame.midY))}")

            Thread.sleep(forTimeInterval: 0.8)

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

            // ---- Track transition ----
            let newElements = readUITree(app)
            let newFlat = flattenElements(newElements)
            let newHash = computeHash(newFlat)
            stateTransitions.append((from: stateHash, to: newHash, action: actionDesc))

            // Emit transition for flow map
            let newTitle = detectTitle(newFlat) ?? "Unknown"
            let escapedNewTitle = newTitle.replacingOccurrences(of: "\"", with: "'")
            print("OCQA_TRANSITION:{\"from\":\"\(escapedTitle)\",\"fromHash\":\"\(stateHash)\",\"to\":\"\(escapedNewTitle)\",\"toHash\":\"\(newHash)\",\"action\":\"\(escapedTarget)\"}")

            // ---- Loop detection ----
            let recentStates = stateTransitions.suffix(6).map(\.to)
            if recentStates.count >= 6 && Set(recentStates).count <= 2 {
                if !(onRewardsScreen && (showingEarnMode || showingRedeemMode)) {
                    issues.append((type: "navigation_loop", severity: "high",
                                   title: "Navigation loop detected on \(titleStr)",
                                   desc: "Stuck cycling between states"))
                    print("OCQA_ISSUE:{\"type\":\"navigation_loop\",\"severity\":\"high\",\"title\":\"Navigation loop on \(escapedTitle)\",\"screen\":\"\(escapedTitle)\",\"step\":\(actionCount)}")
                }
                if !tryGoBack() { break }
            }

            emitProgress(action: actionCount, maxActions: maxActions, states: visitedStates.count)
        }

        // ---- Emit summary ----
        let uniqueScreens = screenTitles.values
        let screenList = Array(Set(uniqueScreens)).sorted().joined(separator: ",")
        print("OCQA_COMPLETE:{\"actions\":\(actionCount),\"states\":\(visitedStates.count),\"issues\":\(issues.count),\"screens\":\"\(screenList)\"}")

        // Final screenshot
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
        var elements: [SimpleElement] = []
        let query = app.descendants(matching: .any)
        _ = query.firstMatch.waitForExistence(timeout: 10)
        let count = query.count

        for i in 0..<min(count, 200) {
            let el = query.element(boundBy: i)
            guard el.exists else { continue }

            let frame = el.frame
            guard frame.width > 0, frame.height > 0,
                  frame.origin.x.isFinite, frame.origin.y.isFinite,
                  frame.width.isFinite, frame.height.isFinite else { continue }

            // Infer hittability from frame position vs screen bounds
            // Avoids calling el.isHittable which crashes on off-screen elements
            let screenW: CGFloat = 440
            let screenH: CGFloat = 956
            let screenRect = CGRect(x: 0, y: 0, width: screenW, height: screenH)
            let hittable = el.isEnabled && screenRect.contains(CGPoint(x: frame.midX, y: frame.midY))

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

    private func flattenElements(_ elements: [SimpleElement]) -> [SimpleElement] {
        return elements
    }

    private func actionKey(for element: SimpleElement) -> String {
        let id = element.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if !id.isEmpty { return "id:\(id)" }
        let label = element.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !label.isEmpty { return "label:\(label)" }
        return "frame:\(Int(element.frame.midX))x\(Int(element.frame.midY))"
    }

    /// djb2 hash of element structure — fingerprints the current screen
    private func computeHash(_ elements: [SimpleElement]) -> String {
        let structure = elements.map { "\($0.type):\($0.identifier):\($0.isEnabled)" }.joined(separator: "|")
        var hash: UInt64 = 5381
        for byte in structure.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }

    private func detectTitle(_ elements: [SimpleElement]) -> String? {
        // Try NavigationBar first
        if let navTitle = elements.first(where: { $0.type.contains("NavigationBar") }) {
            if !navTitle.identifier.isEmpty { return navTitle.identifier }
            if !navTitle.label.isEmpty { return navTitle.label }
        }
        // Fall back to largest static text in top 200px
        let topTexts = elements
            .filter { $0.type.contains("StaticText") && $0.frame.minY < 200 && !$0.label.isEmpty }
            .sorted { ($0.frame.width * $0.frame.height) > ($1.frame.width * $1.frame.height) }
        return topTexts.first?.label
    }

    private func isInteractable(_ type: String) -> Bool {
        let interactableRawValues = [9, 49, 50, 39, 75, 40, 42, 53, 54, 56]
        for rv in interactableRawValues {
            if type.contains("rawValue: \(rv)") { return true }
        }
        let types = ["Button", "TextField", "SecureTextField", "Link", "Cell",
                     "Switch", "Slider", "Tab", "MenuItem", "SegmentedControl"]
        return types.contains(where: { type.contains($0) })
    }

    /// Priority-weighted element selection:
    /// Button=5, Cell/Tab=4, Link=3, TextField=2, Switch=1
    /// Elements are shuffled first for variety, then sorted by priority
    private func prioritizeElements(_ elements: [SimpleElement]) -> [SimpleElement] {
        let priority: [(String, Int)] = [
            ("rawValue: 9", 5), ("rawValue: 75", 4), ("rawValue: 53", 4), ("rawValue: 39", 3),
            ("rawValue: 49", 2), ("rawValue: 50", 2), ("rawValue: 40", 1),
            ("Button", 5), ("Cell", 4), ("Tab", 4), ("Link", 3),
            ("TextField", 2), ("SecureTextField", 2), ("Switch", 1)
        ]
        return elements.shuffled().sorted { a, b in
            let pa = priority.first(where: { a.type.contains($0.0) })?.1 ?? 0
            let pb = priority.first(where: { b.type.contains($0.0) })?.1 ?? 0
            return pa > pb
        }
    }

    /// Smart action: coordinate-based tap (or type for text fields)
    /// Uses coordinate taps to avoid XCUITest isHittable crashes
    private func performSmartAction(on element: SimpleElement, in app: XCUIApplication) -> String {
        let frame = element.frame
        guard frame.width > 0, frame.height > 0 else {
            return "skip_invalid_frame"
        }

        let coord = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.midY))

        if element.type.contains("TextField") || element.type.contains("SecureTextField") ||
           element.type.contains("rawValue: 49") || element.type.contains("rawValue: 50") {
            coord.tap()
            Thread.sleep(forTimeInterval: 0.3)
            let testText = element.identifier.lowercased().contains("email") ? "test@example.com" :
                          element.identifier.lowercased().contains("password") ? "TestPass123" :
                          "test input"
            if let xcEl = element.xcElement, xcEl.exists {
                xcEl.typeText(testText)
            }
            return "type(\(element.identifier.isEmpty ? element.label : element.identifier), \"\(testText)\")"
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
        // Swipe from left edge
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
