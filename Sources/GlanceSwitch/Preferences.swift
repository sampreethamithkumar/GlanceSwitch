import Foundation

/// Lightweight persisted settings backed by UserDefaults.
final class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let enabled = "enabled"
        static let invert = "invert"
        static let dwellSeconds = "dwellSeconds"
        static let maxYaw = "maxYaw"
        static let hysteresis = "hysteresis"
        static let pitchLimit = "pitchLimit"
        static let cameraUniqueID = "cameraUniqueID"
    }

    private init() {}

    /// The `uniqueID` of the camera to use. `nil` means "system default camera".
    var cameraUniqueID: String? {
        get { defaults.string(forKey: Key.cameraUniqueID) }
        set { defaults.set(newValue, forKey: Key.cameraUniqueID) }
    }

    /// Whether gaze tracking is currently active.
    var enabled: Bool {
        get { defaults.object(forKey: Key.enabled) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }

    /// Flip left/right mapping (useful depending on camera mirroring / monitor layout).
    var invert: Bool {
        get { defaults.object(forKey: Key.invert) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.invert) }
    }

    /// How long (seconds) you must hold your gaze before focus moves. Prevents flicker.
    var dwellSeconds: Double {
        get { defaults.object(forKey: Key.dwellSeconds) as? Double ?? 0.45 }
        set { defaults.set(newValue, forKey: Key.dwellSeconds) }
    }

    /// Head-yaw magnitude (radians) treated as "looking fully to one side".
    /// Larger = you must turn your head more before focus moves to an outer screen.
    var maxYaw: Double {
        get { defaults.object(forKey: Key.maxYaw) as? Double ?? 0.85 }
        set { defaults.set(newValue, forKey: Key.maxYaw) }
    }

    /// Extra angle (radians) you must turn *past* a screen boundary before focus
    /// switches. Prevents small head movements near an edge from flipping screens.
    var hysteresis: Double {
        get { defaults.object(forKey: Key.hysteresis) as? Double ?? 0.10 }
        set { defaults.set(newValue, forKey: Key.hysteresis) }
    }

    /// If the head tilts up/down beyond this angle (radians), the current screen
    /// is held (no switching) — e.g. when you glance down at the keyboard.
    var pitchLimit: Double {
        get { defaults.object(forKey: Key.pitchLimit) as? Double ?? 0.30 }
        set { defaults.set(newValue, forKey: Key.pitchLimit) }
    }
}
