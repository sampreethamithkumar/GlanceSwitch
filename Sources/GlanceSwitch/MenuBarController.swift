import AppKit

/// Owns the menu-bar item and coordinates the detector + focus controller.
final class MenuBarController: NSObject, NSMenuDelegate {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let detector = GazeDetector()
    private let focus = FocusController()
    private let prefs = Preferences.shared

    // Dwell state.
    private var lastCandidate: Int?
    private var candidateSince = Date.distantPast
    private var currentFocusedScreen = -1

    // Set the GLANCE_DEBUG env var to log head-yaw and target screen to stderr.
    private let debug = ProcessInfo.processInfo.environment["GLANCE_DEBUG"] != nil
    private var lastDebugLog = Date.distantPast

    override init() {
        super.init()
        buildMenu()

        detector.onPose = { [weak self] yaw, pitch in
            DispatchQueue.main.async { self?.handlePose(yaw: yaw, pitch: pitch) }
        }

        if prefs.enabled {
            enableTracking()
        }
        refreshUI()
    }

    func shutdown() {
        detector.stop()
    }

    // MARK: - Menu

    private func buildMenu() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "Glance Switch")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()

        let header = NSMenuItem(title: "Glance Switch", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        menu.addItem(makeItem("Enable focus follow", #selector(toggleEnabled), tag: Tag.enabled))
        menu.addItem(.separator())

        let cameraItem = NSMenuItem(title: "Camera", action: nil, keyEquivalent: "")
        cameraItem.tag = Tag.cameraMenu
        let cameraSubmenu = NSMenu()
        cameraItem.submenu = cameraSubmenu
        menu.addItem(cameraItem)

        menu.addItem(makeItem("Invert left/right", #selector(toggleInvert), tag: Tag.invert))

        let sensitivityItem = NSMenuItem(title: "Sensitivity", action: nil, keyEquivalent: "")
        sensitivityItem.tag = Tag.sensitivityMenu
        let sensitivitySubmenu = NSMenu()
        for preset in Self.sensitivityPresets {
            let item = NSMenuItem(title: preset.label, action: #selector(selectSensitivity(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.maxYaw
            sensitivitySubmenu.addItem(item)
        }
        sensitivityItem.submenu = sensitivitySubmenu
        menu.addItem(sensitivityItem)
        menu.addItem(makeItem("Grant Accessibility access…", #selector(openAccessibility), tag: Tag.accessibility))
        menu.addItem(makeItem("Camera privacy settings…", #selector(openCameraSettings), tag: Tag.camera))
        menu.addItem(.separator())

        let status = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        status.isEnabled = false
        status.tag = Tag.status
        menu.addItem(status)
        menu.addItem(.separator())

        menu.addItem(makeItem("Quit Glance Switch", #selector(quit), tag: Tag.quit))

        menu.delegate = self
        statusItem.menu = menu
    }

    /// Refresh dynamic items (camera list, status) whenever the menu opens so
    /// hot-plugged cameras and display changes show up.
    func menuWillOpen(_ menu: NSMenu) {
        rebuildCameraMenu()
        refreshUI()
    }

    private func rebuildCameraMenu() {
        guard let submenu = statusItem.menu?.item(withTag: Tag.cameraMenu)?.submenu else { return }
        submenu.removeAllItems()

        let systemDefault = NSMenuItem(title: "System default", action: #selector(selectCamera(_:)), keyEquivalent: "")
        systemDefault.target = self
        systemDefault.representedObject = ""   // empty string == use default
        systemDefault.state = (prefs.cameraUniqueID == nil) ? .on : .off
        submenu.addItem(systemDefault)

        let cameras = GazeDetector.availableCameras()
        if !cameras.isEmpty { submenu.addItem(.separator()) }

        for camera in cameras {
            let item = NSMenuItem(title: camera.localizedName, action: #selector(selectCamera(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = camera.uniqueID
            item.state = (prefs.cameraUniqueID == camera.uniqueID) ? .on : .off
            submenu.addItem(item)
        }
    }

    private func makeItem(_ title: String, _ action: Selector, tag: Int) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.tag = tag
        return item
    }

    private enum Tag {
        static let enabled = 1
        static let invert = 2
        static let accessibility = 3
        static let camera = 4
        static let status = 5
        static let quit = 6
        static let cameraMenu = 7
        static let sensitivityMenu = 8
    }

    /// Sensitivity presets: larger `maxYaw` means you must turn your head further
    /// before focus moves (so small movements within a screen are ignored).
    private static let sensitivityPresets: [(label: String, maxYaw: Double)] = [
        ("High — small head turns", 0.55),
        ("Medium", 0.85),
        ("Low — large head turns", 1.20)
    ]

    // MARK: - Actions

    @objc private func selectSensitivity(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        prefs.maxYaw = value
        refreshUI()
    }

    @objc private func selectCamera(_ sender: NSMenuItem) {
        let id = sender.representedObject as? String ?? ""
        prefs.cameraUniqueID = id.isEmpty ? nil : id
        // Apply immediately if we're currently tracking.
        if prefs.enabled {
            detector.restart { [weak self] ok in
                guard let self = self, !ok else { return }
                self.prefs.enabled = false
                self.refreshUI()
                self.showCameraDeniedAlert()
            }
            resetDwell()
        }
    }

    @objc private func toggleEnabled() {
        prefs.enabled.toggle()
        if prefs.enabled {
            enableTracking()
        } else {
            disableTracking()
        }
        refreshUI()
    }

    @objc private func toggleInvert() {
        prefs.invert.toggle()
        refreshUI()
    }

    @objc private func openAccessibility() {
        focus.ensureAccessibilityPermission(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openCameraSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Tracking lifecycle

    private func enableTracking() {
        focus.ensureAccessibilityPermission(prompt: true)
        resetDwell()
        detector.start { [weak self] ok in
            guard let self = self else { return }
            if !ok {
                self.prefs.enabled = false
                self.refreshUI()
                self.showCameraDeniedAlert()
            }
        }
    }

    private func disableTracking() {
        detector.stop()
        resetDwell()
    }

    private func resetDwell() {
        lastCandidate = nil
        candidateSince = .distantPast
        currentFocusedScreen = -1
    }

    // MARK: - Gaze handling

    private func handlePose(yaw: Double, pitch: Double) {
        guard prefs.enabled else { return }

        // Looking down (or far up) — e.g. glancing at the keyboard. Hold the
        // current screen instead of drifting to the middle.
        if abs(pitch) > prefs.pitchLimit {
            if debug, Date().timeIntervalSince(lastDebugLog) >= 0.3 {
                lastDebugLog = Date()
                FileHandle.standardError.write(
                    String(format: "[GlanceSwitch] pitch=%+.3f rad  (looking away/down — holding display #%d)\n",
                           pitch, currentFocusedScreen).data(using: .utf8)!)
            }
            // Reset dwell candidate so we don't instantly commit a stale target
            // the moment the head comes back up.
            lastCandidate = currentFocusedScreen
            return
        }

        let screens = ScreenMapper.sortedScreens()
        let target = ScreenMapper.screenIndex(forYaw: yaw,
                                              maxYaw: prefs.maxYaw,
                                              invert: prefs.invert,
                                              screenCount: screens.count,
                                              currentIndex: currentFocusedScreen,
                                              hysteresis: prefs.hysteresis)
        guard let target = target else {
            if debug, Date().timeIntervalSince(lastDebugLog) >= 0.3 {
                lastDebugLog = Date()
                FileHandle.standardError.write(
                    String(format: "[GlanceSwitch] yaw=%+.3f rad  (only %d display — nothing to switch)\n",
                           yaw, screens.count).data(using: .utf8)!)
            }
            return
        }

        if debug, Date().timeIntervalSince(lastDebugLog) >= 0.3 {
            lastDebugLog = Date()
            let turn = yaw < -0.05 ? "head LEFT " : (yaw > 0.05 ? "head RIGHT" : "head centre")
            let position: String
            if target == 0 { position = "LEFT-most" }
            else if target == screens.count - 1 { position = "RIGHT-most" }
            else { position = "middle" }
            FileHandle.standardError.write(
                String(format: "[GlanceSwitch] %@  yaw=%+.3f pitch=%+.3f  -> display #%d (%@ of %d)  [focused #%d]\n",
                       turn, yaw, pitch, target, position, screens.count, currentFocusedScreen).data(using: .utf8)!)
        }

        if target != lastCandidate {
            lastCandidate = target
            candidateSince = Date()
            return
        }

        // Candidate is stable; commit once dwell time has elapsed and it differs
        // from where focus already is.
        if target != currentFocusedScreen,
           Date().timeIntervalSince(candidateSince) >= prefs.dwellSeconds {
            currentFocusedScreen = target
            if debug {
                FileHandle.standardError.write(
                    String(format: "[GlanceSwitch] >>> switching focus to display #%d\n", target).data(using: .utf8)!)
            }
            focus.focusFrontmostWindow(onScreenIndex: target)
        }
    }

    // MARK: - UI state

    private func refreshUI() {
        guard let menu = statusItem.menu else { return }
        menu.item(withTag: Tag.enabled)?.state = prefs.enabled ? .on : .off
        menu.item(withTag: Tag.invert)?.state = prefs.invert ? .on : .off

        if let sensitivitySubmenu = menu.item(withTag: Tag.sensitivityMenu)?.submenu {
            for item in sensitivitySubmenu.items {
                guard let value = item.representedObject as? Double else { continue }
                item.state = abs(value - prefs.maxYaw) < 0.001 ? .on : .off
            }
        }

        let screenCount = ScreenMapper.sortedScreens().count
        let statusText: String
        if prefs.enabled {
            statusText = screenCount > 1
                ? "Tracking \(screenCount) displays…"
                : "Only 1 display detected"
        } else {
            statusText = "Paused"
        }
        menu.item(withTag: Tag.status)?.title = statusText

        if let button = statusItem.button {
            let symbol = prefs.enabled ? "eye" : "eye.slash"
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Glance Switch")
            button.image?.isTemplate = true
        }
    }

    private func showCameraDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = "Camera access needed"
        alert.informativeText = "Glance Switch needs the camera to see which screen you're facing. "
            + "Enable it in System Settings → Privacy & Security → Camera, then toggle it back on."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            openCameraSettings()
        }
    }
}
