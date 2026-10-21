import AppKit
import ApplicationServices

/// Moves keyboard focus to the frontmost window on a given display using the
/// macOS Accessibility API.
final class FocusController {

    /// Returns true if Accessibility is already trusted. If not, prompts the user
    /// (System Settings → Privacy & Security → Accessibility).
    @discardableResult
    func ensureAccessibilityPermission(prompt: Bool = true) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Finds the frontmost normal window whose center lies on the target screen
    /// and gives it keyboard focus.
    func focusFrontmostWindow(onScreenIndex index: Int) {
        let screens = ScreenMapper.sortedScreens()
        guard index >= 0, index < screens.count else { return }

        let targetCG = cgRect(for: screens[index])

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return }

        // CGWindowList is ordered front-to-back, so the first match is frontmost.
        for info in infoList {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t else { continue }
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }

            // Ignore tiny helper windows / status popovers.
            if bounds.width < 120 || bounds.height < 80 { continue }

            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            if targetCG.contains(center) {
                raiseAndActivate(pid: pid, targetCG: targetCG, cgBounds: bounds)
                return
            }
        }
    }

    // MARK: - Private

    /// Converts an `NSScreen.frame` (bottom-left origin) to CoreGraphics
    /// top-left-origin coordinates used by CGWindow / Accessibility.
    private func cgRect(for screen: NSScreen) -> CGRect {
        let primaryHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.main?.frame.height
            ?? screen.frame.height
        let f = screen.frame
        return CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)
    }

    private func raiseAndActivate(pid: pid_t, targetCG: CGRect, cgBounds: CGRect) {
        // Activate the app FIRST. Activating an already-frontmost app restores its
        // previous key window, which would override our choice — so we select the
        // target window *after* activation (and again shortly after, to win the race).
        NSRunningApplication(processIdentifier: pid)?
            .activate(options: [.activateIgnoringOtherApps])

        applyFocus(pid: pid, targetCG: targetCG, cgBounds: cgBounds)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            self?.applyFocus(pid: pid, targetCG: targetCG, cgBounds: cgBounds)
        }
    }

    /// Raise and focus the target app's window that sits on the target screen.
    private func applyFocus(pid: pid_t, targetCG: CGRect, cgBounds: CGRect) {
        let appElement = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement],
              let window = bestWindow(in: windows, targetCG: targetCG, cgBounds: cgBounds) else {
            return
        }

        AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, window)
    }

    /// Chooses the app window to focus: first any window centered on the target
    /// screen; otherwise the closest bounds match; otherwise the first window.
    private func bestWindow(in windows: [AXUIElement],
                            targetCG: CGRect,
                            cgBounds: CGRect) -> AXUIElement? {
        // 1. Window whose center is on the target screen.
        for window in windows {
            guard let frame = axBounds(of: window) else { continue }
            let center = CGPoint(x: frame.midX, y: frame.midY)
            if targetCG.contains(center) { return window }
        }

        // 2. Closest window to the CoreGraphics bounds we found.
        var closest: AXUIElement?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for window in windows {
            guard let frame = axBounds(of: window) else { continue }
            let dx = frame.midX - cgBounds.midX
            let dy = frame.midY - cgBounds.midY
            let distance = dx * dx + dy * dy
            if distance < bestDistance {
                bestDistance = distance
                closest = window
            }
        }
        if let closest = closest { return closest }

        // 3. Fallback: first window if nothing else resolved.
        return windows.first
    }

    private func axBounds(of window: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success else {
            return nil
        }
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }
}
