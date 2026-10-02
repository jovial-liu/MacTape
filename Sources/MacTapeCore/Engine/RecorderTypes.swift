import CoreGraphics
import Foundation

public enum RecordedMouseButton: String, Codable, Sendable {
    case left
    case right
    case other
}

public struct RecordedClick: Codable, Hashable, Sendable {
    public var timestamp: Date
    public var location: CGPoint
    public var button: RecordedMouseButton
    public var clickCount: Int
    public var target: AXElementSnapshot?

    public init(
        timestamp: Date,
        location: CGPoint,
        button: RecordedMouseButton,
        clickCount: Int,
        target: AXElementSnapshot?
    ) {
        self.timestamp = timestamp
        self.location = location
        self.button = button
        self.clickCount = clickCount
        self.target = target
    }
}

public struct RecordedShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let command = Self(rawValue: 1 << 0)
    public static let control = Self(rawValue: 1 << 1)
    public static let option = Self(rawValue: 1 << 2)
    public static let shift = Self(rawValue: 1 << 3)
    public static let function = Self(rawValue: 1 << 4)
}

/// A shortcut stores hardware key codes, not Unicode characters. This both
/// improves replay across keyboard layouts and ensures typed text is not logged.
public struct RecordedShortcut: Codable, Hashable, Sendable {
    public var timestamp: Date
    public var keyCode: UInt16
    public var modifiers: RecordedShortcutModifiers
    public var bundleIdentifier: String?

    public init(
        timestamp: Date,
        keyCode: UInt16,
        modifiers: RecordedShortcutModifiers,
        bundleIdentifier: String?
    ) {
        self.timestamp = timestamp
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.bundleIdentifier = bundleIdentifier
    }
}

public enum RecordedInteraction: Codable, Hashable, Sendable {
    case click(RecordedClick)
    case shortcut(RecordedShortcut)
}

public enum RecorderState: Equatable, Sendable {
    case idle
    case starting
    case recording
    case stopping
    case failed(message: String)
}

public struct RecorderConfiguration: Sendable {
    /// Option-only keystrokes can produce text on many keyboard layouts. They
    /// are therefore ignored by default. Command- or Control-modified keys are
    /// always treated as shortcuts; Shift and Option may accompany them.
    public var allowsOptionOnlyShortcuts: Bool
    public var requestsInputMonitoringPermission: Bool
    public var callbackQueue: DispatchQueue
    public var snapshotter: AXSnapshotter

    public init(
        allowsOptionOnlyShortcuts: Bool = false,
        requestsInputMonitoringPermission: Bool = false,
        callbackQueue: DispatchQueue = .main,
        snapshotter: AXSnapshotter = AXSnapshotter()
    ) {
        self.allowsOptionOnlyShortcuts = allowsOptionOnlyShortcuts
        self.requestsInputMonitoringPermission = requestsInputMonitoringPermission
        self.callbackQueue = callbackQueue
        self.snapshotter = snapshotter
    }
}

public enum RecorderError: Error, LocalizedError, Sendable, Equatable {
    case alreadyRunning
    case accessibilityPermissionRequired
    case inputMonitoringPermissionRequired
    case eventTapCreationFailed

    public var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            "The recorder is already running."
        case .accessibilityPermissionRequired:
            "Accessibility permission is required before recording."
        case .inputMonitoringPermissionRequired:
            "Input Monitoring permission is required before recording."
        case .eventTapCreationFailed:
            "macOS did not allow MacTape to create a listen-only event tap."
        }
    }
}
