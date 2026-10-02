import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

public enum AXSnapshotError: Error, LocalizedError, Sendable, Equatable {
    case accessibilityPermissionRequired
    case noElementAtPoint(CGPoint)
    case attributeReadFailed(attribute: String, code: Int32)

    public var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            "Accessibility permission is required to inspect application UI."
        case let .noElementAtPoint(point):
            "No accessible element was found at (\(point.x), \(point.y))."
        case let .attributeReadFailed(attribute, code):
            "Could not read Accessibility attribute \(attribute) (AXError \(code))."
        }
    }
}

/// A Sendable handle around an AXUIElement. AXUIElement is an immutable Core
/// Foundation reference. Calls that use the handle can still fail when the
/// owning application exits or mutates its accessibility tree.
public struct AXElementReference: @unchecked Sendable {
    public let element: AXUIElement

    public init(_ element: AXUIElement) {
        self.element = element
    }
}

/// One stable-ish component in an element's ancestry. `childIndex` is only a
/// fallback: identifiers, roles, and labels are preferred because indices move.
public struct AXAncestorComponent: Codable, Hashable, Sendable {
    public var role: String?
    public var subrole: String?
    public var identifier: String?
    public var title: String?
    public var childIndex: Int?

    public init(
        role: String? = nil,
        subrole: String? = nil,
        identifier: String? = nil,
        title: String? = nil,
        childIndex: Int? = nil
    ) {
        self.role = role
        self.subrole = subrole
        self.identifier = identifier
        self.title = title
        self.childIndex = childIndex
    }
}

/// Privacy-preserving selector material extracted from an AX element.
///
/// This type deliberately has no `value` property. In particular, text-field
/// contents are never read while recording because they may contain secrets.
public struct AXSelectorFeatures: Codable, Hashable, Sendable {
    public var bundleIdentifier: String?
    public var role: String?
    public var subrole: String?
    public var identifier: String?
    public var title: String?
    public var accessibilityDescription: String?
    public var frame: CGRect?
    public var ancestors: [AXAncestorComponent]

    public init(
        bundleIdentifier: String? = nil,
        role: String? = nil,
        subrole: String? = nil,
        identifier: String? = nil,
        title: String? = nil,
        accessibilityDescription: String? = nil,
        frame: CGRect? = nil,
        ancestors: [AXAncestorComponent] = []
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.role = role
        self.subrole = subrole
        self.identifier = identifier
        self.title = title
        self.accessibilityDescription = accessibilityDescription
        self.frame = frame
        self.ancestors = ancestors
    }
}

/// A point-in-time, non-secret view of an Accessibility element.
public struct AXElementSnapshot: Codable, Hashable, Sendable {
    public var processIdentifier: pid_t
    public var bundleIdentifier: String?
    public var applicationName: String?
    public var role: String?
    public var subrole: String?
    public var identifier: String?
    public var title: String?
    public var accessibilityDescription: String?
    public var help: String?
    public var frame: CGRect?
    public var isEnabled: Bool?
    public var isFocused: Bool?
    public var ancestors: [AXAncestorComponent]

    public init(
        processIdentifier: pid_t,
        bundleIdentifier: String? = nil,
        applicationName: String? = nil,
        role: String? = nil,
        subrole: String? = nil,
        identifier: String? = nil,
        title: String? = nil,
        accessibilityDescription: String? = nil,
        help: String? = nil,
        frame: CGRect? = nil,
        isEnabled: Bool? = nil,
        isFocused: Bool? = nil,
        ancestors: [AXAncestorComponent] = []
    ) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.role = role
        self.subrole = subrole
        self.identifier = identifier
        self.title = title
        self.accessibilityDescription = accessibilityDescription
        self.help = help
        self.frame = frame
        self.isEnabled = isEnabled
        self.isFocused = isFocused
        self.ancestors = ancestors
    }

    public var selectorFeatures: AXSelectorFeatures {
        AXSelectorFeatures(
            bundleIdentifier: bundleIdentifier,
            role: role,
            subrole: subrole,
            identifier: identifier,
            title: title,
            accessibilityDescription: accessibilityDescription,
            frame: frame,
            ancestors: ancestors
        )
    }

    /// Builds the persistent workflow selector used by MacTape documents.
    /// Text-field values are intentionally omitted even though the model can
    /// represent one for manually-authored assertions.
    public var elementSelector: ElementSelector {
        ElementSelector(
            bundleIdentifier: bundleIdentifier,
            role: role,
            subrole: subrole,
            identifier: identifier,
            title: title,
            value: nil,
            accessibilityDescription: accessibilityDescription,
            path: ancestors.isEmpty || ancestors.contains(where: { $0.childIndex == nil }) ? nil : ancestors.compactMap(\.childIndex),
            matchStrategy: .exact
        )
    }
}

/// Synchronous AX inspection primitives. Keeping these calls synchronous makes
/// it explicit that callers should move broad tree scans off the main thread.
public struct AXSnapshotter: Sendable {
    public var maximumAncestorDepth: Int
    public var maximumSiblingScan: Int

    public init(maximumAncestorDepth: Int = 12, maximumSiblingScan: Int = 200) {
        self.maximumAncestorDepth = max(0, maximumAncestorDepth)
        self.maximumSiblingScan = max(1, maximumSiblingScan)
    }

    public func element(at point: CGPoint) throws -> AXElementReference {
        guard AccessibilityPermission.isGranted else {
            throw AXSnapshotError.accessibilityPermissionRequired
        }

        let systemWide = AXUIElementCreateSystemWide()
        var found: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(
            systemWide,
            Float(point.x),
            Float(point.y),
            &found
        )
        guard error == .success, let found else {
            throw AXSnapshotError.noElementAtPoint(point)
        }
        return AXElementReference(found)
    }

    public func snapshot(at point: CGPoint) throws -> AXElementSnapshot {
        try snapshot(of: element(at: point))
    }

    public func snapshot(of reference: AXElementReference) throws -> AXElementSnapshot {
        let element = reference.element
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)

        let application = NSRunningApplication(processIdentifier: pid)
        let secure = AXAttribute.isSecureTextField(element)
        return AXElementSnapshot(
            processIdentifier: pid,
            bundleIdentifier: application?.bundleIdentifier,
            applicationName: application?.localizedName,
            role: AXAttribute.string(kAXRoleAttribute, from: element),
            subrole: AXAttribute.string(kAXSubroleAttribute, from: element),
            identifier: AXAttribute.string(kAXIdentifierAttribute, from: element),
            title: secure ? nil : AXAttribute.string(kAXTitleAttribute, from: element),
            accessibilityDescription: secure ? nil : AXAttribute.string(kAXDescriptionAttribute, from: element),
            help: secure ? nil : AXAttribute.string(kAXHelpAttribute, from: element),
            frame: AXAttribute.frame(from: element),
            isEnabled: AXAttribute.bool(kAXEnabledAttribute, from: element),
            isFocused: AXAttribute.bool(kAXFocusedAttribute, from: element),
            ancestors: ancestorPath(startingAt: element)
        )
    }

    private func ancestorPath(startingAt element: AXUIElement) -> [AXAncestorComponent] {
        guard maximumAncestorDepth > 0 else { return [] }

        var result: [AXAncestorComponent] = []
        var child = element

        for _ in 0..<maximumAncestorDepth {
            guard let parent = AXAttribute.element(kAXParentAttribute, from: child) else {
                break
            }

            result.append(
                AXAncestorComponent(
                    role: AXAttribute.string(kAXRoleAttribute, from: parent),
                    subrole: AXAttribute.string(kAXSubroleAttribute, from: parent),
                    identifier: AXAttribute.string(kAXIdentifierAttribute, from: parent),
                    title: AXAttribute.string(kAXTitleAttribute, from: parent),
                    childIndex: childIndex(of: child, in: parent)
                )
            )
            child = parent
        }

        // Root-to-leaf order makes path comparison and serialization intuitive.
        return result.reversed()
    }

    private func childIndex(of child: AXUIElement, in parent: AXUIElement) -> Int? {
        let children = AXAttribute.elements(kAXChildrenAttribute, from: parent)
        for (index, sibling) in children.prefix(maximumSiblingScan).enumerated()
        where CFEqual(sibling, child) {
            return index
        }
        return nil
    }
}

/// Shared, intentionally non-throwing AX attribute readers. A disappearing UI
/// element is normal during automation; callers decide which missing fields
/// matter. Value reads are blocked centrally for secure text fields; ordinary
/// recording never requests this attribute, even for non-secure fields.
enum AXAttribute {
    static func copy(_ attribute: String, from element: AXUIElement) -> CFTypeRef? {
        if attribute == kAXValueAttribute, isSecureTextField(element) { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    static func isSecureTextField(_ element: AXUIElement) -> Bool {
        string(kAXSubroleAttribute, from: element) == kAXSecureTextFieldSubrole
    }

    static func string(_ attribute: String, from element: AXUIElement) -> String? {
        copy(attribute, from: element) as? String
    }

    static func bool(_ attribute: String, from element: AXUIElement) -> Bool? {
        if let value = copy(attribute, from: element) as? Bool {
            return value
        }
        return (copy(attribute, from: element) as? NSNumber)?.boolValue
    }

    static func element(_ attribute: String, from element: AXUIElement) -> AXUIElement? {
        guard let value = copy(attribute, from: element), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    static func elements(_ attribute: String, from element: AXUIElement) -> [AXUIElement] {
        copy(attribute, from: element) as? [AXUIElement] ?? []
    }

    static func frame(from element: AXUIElement) -> CGRect? {
        guard
            let positionRaw = copy(kAXPositionAttribute, from: element),
            let sizeRaw = copy(kAXSizeAttribute, from: element),
            CFGetTypeID(positionRaw) == AXValueGetTypeID(),
            CFGetTypeID(sizeRaw) == AXValueGetTypeID()
        else {
            return nil
        }

        let positionValue = unsafeDowncast(positionRaw, to: AXValue.self)
        let sizeValue = unsafeDowncast(sizeRaw, to: AXValue.self)

        var point = CGPoint.zero
        var size = CGSize.zero
        guard
            AXValueGetValue(positionValue, .cgPoint, &point),
            AXValueGetValue(sizeValue, .cgSize, &size)
        else {
            return nil
        }
        guard point.x.isFinite, point.y.isFinite, size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin: point, size: size)
    }
}
