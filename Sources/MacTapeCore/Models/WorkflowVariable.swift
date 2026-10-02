import Foundation

/// A declared input to a workflow.
///
/// Variable names are referenced as `{{ variableName }}` in step strings. Secret
/// variables should normally omit `defaultValue` so credentials are never stored
/// in a `.mactape` document.
public struct WorkflowVariable: Codable, Hashable, Sendable, Identifiable {
    public var name: String
    public var defaultValue: String?
    public var summary: String?
    public var isRequired: Bool
    public var isSecret: Bool

    public var id: String { name }

    public init(
        name: String,
        defaultValue: String? = nil,
        summary: String? = nil,
        isRequired: Bool = true,
        isSecret: Bool = false
    ) {
        self.name = name
        self.defaultValue = defaultValue
        self.summary = summary
        self.isRequired = isRequired
        self.isSecret = isSecret
    }
}

public enum MissingVariablePolicy: String, Codable, CaseIterable, Hashable, Sendable {
    /// Throw `VariableTemplateError.missingValue`.
    case error
    /// Leave the original `{{ name }}` token in place.
    case preserve
    /// Replace an unresolved token with an empty string.
    case empty
}

public enum VariableTemplateError: Error, Equatable, Hashable, Sendable {
    case unclosedPlaceholder(offset: Int)
    case emptyPlaceholder(offset: Int)
    case invalidPlaceholder(name: String, offset: Int)
    case missingValue(name: String)
    case duplicateDefinition(name: String)
    case cyclicReference(path: [String])
    case expansionTooLarge(maximumBytes: Int)
    case referenceDepthExceeded(maximumDepth: Int)
    case tooManyVariables(maximum: Int)
    case duplicateEnvironmentKey(name: String)
}

extension VariableTemplateError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .unclosedPlaceholder(offset):
            "Unclosed variable placeholder at character \(offset)."
        case let .emptyPlaceholder(offset):
            "Empty variable placeholder at character \(offset)."
        case let .invalidPlaceholder(name, offset):
            "Invalid variable placeholder “\(name)” at character \(offset)."
        case let .missingValue(name):
            "No value was provided for variable “\(name)”."
        case let .duplicateDefinition(name):
            "Variable “\(name)” is declared more than once."
        case let .cyclicReference(path):
            "Variable values contain a cycle: \(path.joined(separator: " -> "))."
        case let .expansionTooLarge(maximumBytes):
            "Variable expansion exceeds the \(maximumBytes)-byte safety limit."
        case let .referenceDepthExceeded(maximumDepth):
            "Variable references exceed the maximum depth of \(maximumDepth)."
        case let .tooManyVariables(maximum):
            "A workflow may resolve at most \(maximum) variables."
        case let .duplicateEnvironmentKey(name):
            "More than one environment entry expands to “\(name)”."
        }
    }
}

/// Expands `{{ name }}` placeholders in workflow strings.
///
/// Prefix an opening token with a backslash (`\{{ name }}`) to keep it literal.
public enum VariableTemplate {
    public static let maximumExpandedBytes = 1_024 * 1_024

    public static func expand(
        _ template: String,
        using values: [String: String],
        missing policy: MissingVariablePolicy = .error
    ) throws -> String {
        try render(template, missing: policy) { values[$0] }
    }

    static func render(
        _ template: String,
        missing policy: MissingVariablePolicy,
        lookup: (String) throws -> String?
    ) throws -> String {
        guard template.utf8.count <= maximumExpandedBytes else {
            throw VariableTemplateError.expansionTooLarge(maximumBytes: maximumExpandedBytes)
        }
        var result = ""
        result.reserveCapacity(template.count)
        var cursor = template.startIndex
        var characterOffset = 0
        var resultBytes = 0

        func append(_ value: String) throws {
            let bytes = value.utf8.count
            guard bytes <= maximumExpandedBytes - resultBytes else {
                throw VariableTemplateError.expansionTooLarge(maximumBytes: maximumExpandedBytes)
            }
            result.append(value)
            resultBytes += bytes
        }

        while cursor < template.endIndex {
            let remainder = template[cursor...]

            if remainder.hasPrefix("\\{{") {
                try append("{{")
                cursor = template.index(cursor, offsetBy: 3)
                characterOffset += 3
                continue
            }

            guard remainder.hasPrefix("{{") else {
                try append(String(template[cursor]))
                cursor = template.index(after: cursor)
                characterOffset += 1
                continue
            }

            let tokenOffset = characterOffset
            let bodyStart = template.index(cursor, offsetBy: 2)
            guard let closingRange = template.range(of: "}}", range: bodyStart..<template.endIndex) else {
                throw VariableTemplateError.unclosedPlaceholder(offset: tokenOffset)
            }

            let rawName = template[bodyStart..<closingRange.lowerBound]
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                throw VariableTemplateError.emptyPlaceholder(offset: tokenOffset)
            }
            guard !name.contains("{{"), !name.contains("}}") else {
                throw VariableTemplateError.invalidPlaceholder(name: name, offset: tokenOffset)
            }

            if let value = try lookup(name) {
                try append(value)
            } else {
                switch policy {
                case .error:
                    throw VariableTemplateError.missingValue(name: name)
                case .preserve:
                    try append(String(template[cursor..<closingRange.upperBound]))
                case .empty:
                    break
                }
            }

            characterOffset += template.distance(from: cursor, to: closingRange.upperBound)
            cursor = closingRange.upperBound
        }

        return result
    }
}

/// Resolves declared defaults and run-time overrides.
///
/// Defaults may reference other variables. Run-time overrides are always literal
/// text: a password containing `{{ braces }}` must never become a template.
public struct WorkflowVariableResolver: Hashable, Sendable {
    public static let maximumVariables = 1_024
    public static let maximumReferenceDepth = 128
    public static let maximumResolvedBytes = 8 * 1_024 * 1_024

    public var definitions: [WorkflowVariable]

    public init(definitions: [WorkflowVariable]) {
        self.definitions = definitions
    }

    public func resolve(overrides: [String: String] = [:]) throws -> [String: String] {
        guard definitions.count <= Self.maximumVariables, overrides.count <= Self.maximumVariables else {
            throw VariableTemplateError.tooManyVariables(maximum: Self.maximumVariables)
        }
        var rawValues: [String: String] = [:]
        var literalValues: [String: String] = [:]
        var seen = Set<String>()

        for key in overrides.keys.sorted() {
            let name = try Self.normalizedName(key)
            guard literalValues[name] == nil else {
                throw VariableTemplateError.duplicateDefinition(name: name)
            }
            literalValues[name] = overrides[key]
        }

        for definition in definitions {
            let name = try Self.normalizedName(definition.name)
            guard seen.insert(name).inserted else {
                throw VariableTemplateError.duplicateDefinition(name: name)
            }

            if literalValues[name] == nil {
                if let defaultValue = definition.defaultValue {
                    rawValues[name] = defaultValue
                } else if definition.isRequired {
                    throw VariableTemplateError.missingValue(name: name)
                } else {
                    rawValues[name] = ""
                }
            }
        }

        var resolved: [String: String] = [:]
        var resolvedBytes = 0

        func cache(_ value: String, named name: String) throws {
            let bytes = value.utf8.count
            guard bytes <= VariableTemplate.maximumExpandedBytes else {
                throw VariableTemplateError.expansionTooLarge(maximumBytes: VariableTemplate.maximumExpandedBytes)
            }
            guard bytes <= Self.maximumResolvedBytes - resolvedBytes else {
                throw VariableTemplateError.expansionTooLarge(maximumBytes: Self.maximumResolvedBytes)
            }
            resolved[name] = value
            resolvedBytes += bytes
        }

        let names = Set(rawValues.keys).union(literalValues.keys)
        guard names.count <= Self.maximumVariables else {
            throw VariableTemplateError.tooManyVariables(maximum: Self.maximumVariables)
        }
        for name in literalValues.keys.sorted() {
            if let value = literalValues[name] { try cache(value, named: name) }
        }

        func resolveValue(named name: String, path: [String]) throws -> String? {
            if let value = resolved[name] {
                return value
            }
            guard let rawValue = rawValues[name] else {
                return nil
            }
            if path.contains(name) {
                let cycleStart = path.firstIndex(of: name) ?? path.startIndex
                throw VariableTemplateError.cyclicReference(path: Array(path[cycleStart...]) + [name])
            }
            guard path.count < Self.maximumReferenceDepth else {
                throw VariableTemplateError.referenceDepthExceeded(maximumDepth: Self.maximumReferenceDepth)
            }

            let expanded = try VariableTemplate.render(rawValue, missing: .error) { referencedName in
                try resolveValue(named: referencedName, path: path + [name])
            }
            try cache(expanded, named: name)
            return expanded
        }

        for name in rawValues.keys.sorted() {
            _ = try resolveValue(named: name, path: [])
        }
        return resolved
    }

    private static func normalizedName(_ value: String) throws -> String {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("{{"), !name.contains("}}") else {
            throw VariableTemplateError.invalidPlaceholder(name: value, offset: 0)
        }
        return name
    }
}
