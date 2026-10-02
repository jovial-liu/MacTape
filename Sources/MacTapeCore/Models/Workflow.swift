import Foundation

/// A portable MacTape automation document.
public struct Workflow: Identifiable, Codable, Hashable, Sendable {
    public var formatVersion: Int
    public var id: UUID
    public var name: String
    public var summary: String
    public var createdAt: Date
    public var updatedAt: Date
    public var variables: [WorkflowVariable]
    public var steps: [WorkflowStep]

    public init(
        formatVersion: Int = MacTapeCore.formatVersion,
        id: UUID = UUID(),
        name: String,
        summary: String = "",
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        variables: [WorkflowVariable] = [],
        steps: [WorkflowStep] = []
    ) {
        self.formatVersion = formatVersion
        self.id = id
        self.name = name
        self.summary = summary
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.variables = variables
        self.steps = steps
    }

    public var enabledSteps: [WorkflowStep] {
        steps.filter(\.isEnabled)
    }

    /// Returns a runtime copy with all variable-bearing strings expanded.
    /// Definitions remain on the copy so the source metadata is not lost.
    public func expandingVariables(overrides: [String: String] = [:]) throws -> Self {
        let values = try WorkflowVariableResolver(definitions: variables).resolve(overrides: overrides)
        var copy = self
        copy.name = try VariableTemplate.expand(name, using: values)
        copy.summary = try VariableTemplate.expand(summary, using: values)
        copy.steps = try steps.map { try $0.expandingVariables(using: values) }
        return copy
    }
}
