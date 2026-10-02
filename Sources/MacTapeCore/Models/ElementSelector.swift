import Foundation

/// A resilient, serializable description of an Accessibility element.
///
/// Selectors intentionally allow several attributes to be combined. The engine
/// should prefer semantic attributes (`identifier`, `role`, and `title`) and use
/// `path` only as a fallback because hierarchy positions can change between app
/// releases.
public struct ElementSelector: Codable, Hashable, Sendable {
    public enum MatchStrategy: String, Codable, CaseIterable, Hashable, Sendable {
        case exact
        case contains
        case beginsWith
        case regularExpression
    }

    /// Bundle identifier of the application that owns the element. Persisting
    /// this keeps selectors deterministic when a workflow spans several apps.
    public var bundleIdentifier: String?
    public var role: String?
    public var subrole: String?
    public var identifier: String?
    public var title: String?
    public var value: String?
    public var accessibilityDescription: String?
    public var path: [Int]?
    /// A zero-based occurrence when more than one element matches.
    public var index: Int?
    public var matchStrategy: MatchStrategy

    public init(
        bundleIdentifier: String? = nil,
        role: String? = nil,
        subrole: String? = nil,
        identifier: String? = nil,
        title: String? = nil,
        value: String? = nil,
        accessibilityDescription: String? = nil,
        path: [Int]? = nil,
        index: Int? = nil,
        matchStrategy: MatchStrategy = .exact
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.role = role
        self.subrole = subrole
        self.identifier = identifier
        self.title = title
        self.value = value
        self.accessibilityDescription = accessibilityDescription
        self.path = path
        self.index = index
        self.matchStrategy = matchStrategy
    }

    /// Whether the selector has no element-matching constraint.
    ///
    /// An application scope or occurrence index cannot identify an element on
    /// its own. Empty attributes and an empty hierarchy path are not locators.
    public var isEmpty: Bool {
        let attributes = [role, subrole, identifier, title, value, accessibilityDescription]
        return !attributes.contains { !($0 ?? "").isEmpty }
            && (path?.isEmpty ?? true)
    }

    private enum CodingKeys: String, CodingKey {
        case bundleIdentifier, role, subrole, identifier, title, value
        case accessibilityDescription, path, index, matchStrategy
    }

    /// Older v1 documents did not include application scope. Hand-authored
    /// selectors may omit their match strategy, which always defaults to exact.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            bundleIdentifier: try container.decodeIfPresent(String.self, forKey: .bundleIdentifier),
            role: try container.decodeIfPresent(String.self, forKey: .role),
            subrole: try container.decodeIfPresent(String.self, forKey: .subrole),
            identifier: try container.decodeIfPresent(String.self, forKey: .identifier),
            title: try container.decodeIfPresent(String.self, forKey: .title),
            value: try container.decodeIfPresent(String.self, forKey: .value),
            accessibilityDescription: try container.decodeIfPresent(String.self, forKey: .accessibilityDescription),
            path: try container.decodeIfPresent([Int].self, forKey: .path),
            index: try container.decodeIfPresent(Int.self, forKey: .index),
            matchStrategy: try container.decodeIfPresent(MatchStrategy.self, forKey: .matchStrategy) ?? .exact
        )
    }

    public func expandingVariables(
        using values: [String: String],
        missing policy: MissingVariablePolicy = .error
    ) throws -> Self {
        var copy = self
        copy.bundleIdentifier = try bundleIdentifier.map {
            try VariableTemplate.expand($0, using: values, missing: policy)
        }
        copy.role = try role.map { try VariableTemplate.expand($0, using: values, missing: policy) }
        copy.subrole = try subrole.map { try VariableTemplate.expand($0, using: values, missing: policy) }
        copy.identifier = try identifier.map { try VariableTemplate.expand($0, using: values, missing: policy) }
        copy.title = try title.map { try VariableTemplate.expand($0, using: values, missing: policy) }
        copy.value = try value.map { try VariableTemplate.expand($0, using: values, missing: policy) }
        copy.accessibilityDescription = try accessibilityDescription.map {
            try VariableTemplate.expand($0, using: values, missing: policy)
        }
        return copy
    }
}
