import AppKit

/// Maps head-yaw to a target display.
enum ScreenMapper {

    /// All active screens ordered left-to-right by their physical X position.
    static func sortedScreens() -> [NSScreen] {
        NSScreen.screens.sorted { $0.frame.minX < $1.frame.minX }
    }

    /// Convert a head-yaw value into an index into `sortedScreens()`.
    ///
    /// - A yaw of `-maxYaw` maps to the left-most screen, `+maxYaw` to the right-most.
    /// - `currentIndex` is where focus is now; `hysteresis` is how far (radians) the
    ///   head must turn *past* a screen boundary before switching. This stops small
    ///   movements within a screen from flipping the selection.
    /// - Returns `nil` when there is nothing to switch between (0 or 1 screen).
    static func screenIndex(forYaw yaw: Double,
                            maxYaw: Double,
                            invert: Bool,
                            screenCount: Int,
                            currentIndex: Int,
                            hysteresis: Double) -> Int? {
        guard screenCount > 1, maxYaw > 0 else { return nil }

        // Fold `invert` into the yaw sign (range is symmetric).
        let y = invert ? -yaw : yaw

        let raw = rawIndex(forYaw: y, maxYaw: maxYaw, screenCount: screenCount)

        // No established focus yet → accept the raw bucket.
        guard currentIndex >= 0, currentIndex < screenCount else { return raw }
        if raw == currentIndex { return currentIndex }

        // Apply hysteresis at the boundary we'd have to cross to leave the
        // current screen in the direction of travel.
        let direction = raw > currentIndex ? 1 : -1
        let boundaryIndex = currentIndex + (direction > 0 ? 1 : 0)
        let boundaryYaw = -maxYaw + (Double(boundaryIndex) / Double(screenCount)) * (2 * maxYaw)

        if direction > 0 {
            return y >= boundaryYaw + hysteresis ? raw : currentIndex
        } else {
            return y <= boundaryYaw - hysteresis ? raw : currentIndex
        }
    }

    private static func rawIndex(forYaw yaw: Double, maxYaw: Double, screenCount: Int) -> Int {
        var fraction = (yaw + maxYaw) / (2 * maxYaw)
        fraction = min(max(fraction, 0), 1)
        var index = Int(fraction * Double(screenCount))
        if index >= screenCount { index = screenCount - 1 }
        if index < 0 { index = 0 }
        return index
    }
}
