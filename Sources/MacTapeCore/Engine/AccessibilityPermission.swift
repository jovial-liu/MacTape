import AppKit
import ApplicationServices
import Foundation

/// The only authorization state exposed by the macOS Accessibility API.
///
/// macOS intentionally does not distinguish between a user who has not been
/// prompted yet and one who declined the prompt, so both map to `notGranted`.
public enum AccessibilityPermissionStatus: String, Codable, Sendable {
    case granted
    case notGranted
}

/// Read and request the Accessibility permission required to inspect and
/// operate user-interface elements in other applications.
public enum AccessibilityPermission {
    public static var status: AccessibilityPermissionStatus {
        AXIsProcessTrusted() ? .granted : .notGranted
    }

    public static var isGranted: Bool {
        status == .granted
    }

    /// Requests Accessibility access by asking macOS to display its standard
    /// consent prompt. The returned value is the state *at the time of this
    /// call*; granting access in System Settings may happen asynchronously.
    @discardableResult
    public static func request() -> AccessibilityPermissionStatus {
        // Referencing kAXTrustedCheckOptionPrompt directly is diagnosed as
        // shared mutable state under Swift 6 because the C SDK imports it as a
        // global `CFString?`. Its documented constant value is stable.
        let promptKey = "AXTrustedCheckOptionPrompt"
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options) ? .granted : .notGranted
    }

    /// Opens the Accessibility privacy pane. This is useful after the system
    /// prompt has already been dismissed and macOS will not show it again.
    @discardableResult
    public static func openSystemSettings() -> Bool {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return false
        }
        return NSWorkspace.shared.open(url)
    }
}

/// Input Monitoring is separate from Accessibility on current macOS releases.
/// A listen-only CGEvent tap may require both permissions, depending on the
/// event types and OS configuration.
public enum InputMonitoringPermission {
    public static var isGranted: Bool {
        CGPreflightListenEventAccess()
    }

    @discardableResult
    public static func request() -> Bool {
        CGRequestListenEventAccess()
    }

    @discardableResult
    public static func openSystemSettings() -> Bool {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        ) else {
            return false
        }
        return NSWorkspace.shared.open(url)
    }
}
