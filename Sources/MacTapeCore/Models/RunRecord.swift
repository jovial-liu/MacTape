import Foundation

public enum RunStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case queued
    case running
    case succeeded
    case failed
    case cancelled
}

public enum StepRunStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case pending
    case running
    case succeeded
    case failed
    case skipped
    case cancelled
}

public enum DiagnosticSeverity: String, Codable, CaseIterable, Hashable, Sendable {
    case information
    case warning
    case error
}

/// A structured message suitable for both the UI and persisted run history.
public struct Diagnostic: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var severity: DiagnosticSeverity
    public var code: String
    public var message: String
    public var stepID: UUID?
    public var context: [String: String]

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        severity: DiagnosticSeverity,
        code: String,
        message: String,
        stepID: UUID? = nil,
        context: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.severity = severity
        self.code = code
        self.message = message
        self.stepID = stepID
        self.context = context
    }
}

public struct StepRunRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var stepID: UUID
    /// Zero-based index in the workflow at the time of the run.
    public var stepIndex: Int
    public var actionKind: WorkflowStep.Action.Kind
    public var startedAt: Date?
    public var finishedAt: Date?
    public var status: StepRunStatus
    public var diagnostics: [Diagnostic]

    public init(
        id: UUID = UUID(),
        stepID: UUID,
        stepIndex: Int,
        actionKind: WorkflowStep.Action.Kind,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        status: StepRunStatus = .pending,
        diagnostics: [Diagnostic] = []
    ) {
        self.id = id
        self.stepID = stepID
        self.stepIndex = stepIndex
        self.actionKind = actionKind
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.diagnostics = diagnostics
    }

    public var duration: TimeInterval? {
        guard let startedAt, let finishedAt else { return nil }
        return finishedAt.timeIntervalSince(startedAt)
    }
}

public struct RunRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var workflowID: UUID
    public var workflowName: String
    public var startedAt: Date
    public var finishedAt: Date?
    public var status: RunStatus
    /// Names only: secret and non-secret values are deliberately not persisted.
    public var suppliedVariables: [String]
    public var steps: [StepRunRecord]
    public var diagnostics: [Diagnostic]

    public init(
        id: UUID = UUID(),
        workflowID: UUID,
        workflowName: String,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        status: RunStatus = .queued,
        suppliedVariables: [String] = [],
        steps: [StepRunRecord] = [],
        diagnostics: [Diagnostic] = []
    ) {
        self.id = id
        self.workflowID = workflowID
        self.workflowName = workflowName
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.suppliedVariables = suppliedVariables.sorted()
        self.steps = steps
        self.diagnostics = diagnostics
    }

    public var duration: TimeInterval? {
        finishedAt?.timeIntervalSince(startedAt)
    }
}

public typealias WorkflowRunRecord = RunRecord
public typealias WorkflowDiagnostic = Diagnostic
