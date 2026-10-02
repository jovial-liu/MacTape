import Foundation

/// A deliberately narrow capability granting shell execution to exact workflow
/// step IDs and complete shell payloads. The default authorizes nothing; there is no implicit "trust
/// this workflow" path in the engine.
public struct ShellExecutionAuthorization: Hashable, Sendable {
    private var approvedActions: [UUID: WorkflowStep.RunShellAction]

    public static let denied = Self(approvedActions: [:])

    private init(approvedActions: [UUID: WorkflowStep.RunShellAction]) {
        self.approvedActions = approvedActions
    }

    /// Call only after a human or trusted policy has reviewed the corresponding
    /// shell actions after variable expansion. Changing the command, shell,
    /// working directory, environment, timeout, or step ID invalidates approval.
    public static func explicitlyApproving(steps: [WorkflowStep]) -> Self {
        var actions: [UUID: WorkflowStep.RunShellAction] = [:]
        for step in steps where step.isEnabled {
            if case let .runShell(action) = step.action { actions[step.id] = action }
        }
        return Self(approvedActions: actions)
    }

    public func permits(_ step: WorkflowStep) -> Bool {
        guard step.isEnabled, case let .runShell(action) = step.action else { return false }
        return approvedActions[step.id] == action
    }
}

public enum SafetyFindingSeverity: String, Codable, Hashable, Sendable {
    case warning
    case error
}

public struct SafetyFinding: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var severity: SafetyFindingSeverity
    public var code: String
    public var message: String
    public var stepID: UUID?

    public init(
        id: UUID = UUID(),
        severity: SafetyFindingSeverity,
        code: String,
        message: String,
        stepID: UUID? = nil
    ) {
        self.id = id
        self.severity = severity
        self.code = code
        self.message = message
        self.stepID = stepID
    }
}

public struct SafetyValidationReport: Codable, Hashable, Sendable {
    public var findings: [SafetyFinding]

    public init(findings: [SafetyFinding] = []) {
        self.findings = findings
    }

    public var errors: [SafetyFinding] {
        findings.filter { $0.severity == .error }
    }

    public var warnings: [SafetyFinding] {
        findings.filter { $0.severity == .warning }
    }

    public var isSafeToRun: Bool {
        errors.isEmpty
    }
}

public struct SafetyValidator: Sendable {
    public init() {}

    public func validate(
        _ workflow: Workflow,
        shellAuthorization: ShellExecutionAuthorization = .denied,
        requiresShellAuthorization: Bool = true
    ) -> SafetyValidationReport {
        var findings: [SafetyFinding] = []

        if Set(workflow.steps.map(\.id)).count != workflow.steps.count {
            findings.append(SafetyFinding(severity: .error, code: "duplicate-step-id", message: "Each workflow step must have a unique identity."))
        }

        for step in workflow.steps where step.isEnabled {
            switch step.action {
            case let .click(action):
                if action.selector.isEmpty {
                    findings.append(error("empty-selector", "Click requires a non-empty selector.", step))
                }
                if !(1...3).contains(action.clickCount) {
                    findings.append(error("invalid-click-count", "Click count must be between 1 and 3.", step))
                }

            case let .typeText(action):
                if let selector = action.selector, selector.isEmpty {
                    findings.append(error("empty-selector", "Text targeting requires a non-empty selector.", step))
                }
                if action.typingDelay < 0 || !action.typingDelay.isFinite {
                    findings.append(error("invalid-typing-delay", "Typing delay must be finite and non-negative.", step))
                }

            case let .shortcut(action):
                if action.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    findings.append(error("empty-shortcut-key", "Shortcut key cannot be empty.", step))
                }
                if !ShortcutKey.isSupported(action.key) {
                    findings.append(error("unsupported-shortcut-key", "Use a supported key name or a recorded keycode from 0 through 127.", step))
                }

            case let .wait(action):
                if action.duration < 0 || !action.duration.isFinite {
                    findings.append(error("invalid-duration", "Wait duration must be finite and non-negative.", step))
                }

            case let .openApp(action):
                if action.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    findings.append(error("empty-bundle-identifier", "Application bundle identifier cannot be empty.", step))
                }
                appendInvalidTimeout(action.timeout, step: step, to: &findings)

            case let .waitForElement(action):
                if action.selector.isEmpty {
                    findings.append(error("empty-selector", "Element wait requires a non-empty selector.", step))
                }
                appendInvalidTimeout(action.timeout, step: step, to: &findings)
                if action.pollingInterval <= 0 || !action.pollingInterval.isFinite {
                    findings.append(error("invalid-polling-interval", "Polling interval must be finite and positive.", step))
                }

            case let .assertElement(action):
                if action.selector.isEmpty {
                    findings.append(error("empty-selector", "Element assertion requires a non-empty selector.", step))
                }
                if action.timeout < 0 || !action.timeout.isFinite {
                    findings.append(error("invalid-timeout", "Assertion timeout must be finite and non-negative.", step))
                }

            case let .runShell(action):
                if requiresShellAuthorization && !shellAuthorization.permits(step) {
                    findings.append(
                        error(
                            "shell-not-authorized",
                            "Shell execution is blocked until this exact expanded command and configuration are explicitly authorized.",
                            step
                        )
                    )
                }
                if action.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    findings.append(error("empty-shell-command", "Shell command cannot be empty.", step))
                }
                if !action.shell.hasPrefix("/") {
                    findings.append(error("relative-shell-path", "Shell executable must use an absolute path.", step))
                }
                if let directory = action.workingDirectory, !directory.hasPrefix("/") {
                    findings.append(error("relative-working-directory", "Shell working directory must use an absolute path.", step))
                }
                if action.command.contains("\0") || action.shell.contains("\0") || action.workingDirectory?.contains("\0") == true || action.environment.contains(where: { $0.key.isEmpty || $0.key.contains("=") || $0.key.contains("\0") || $0.value.contains("\0") }) {
                    findings.append(error("invalid-shell-configuration", "Shell configuration contains an invalid process argument or environment entry.", step))
                }
                appendInvalidTimeout(action.timeout, step: step, to: &findings)
            }

            if let selector = selector(for: step) {
                if selector.index.map({ $0 < 0 }) == true || selector.path?.contains(where: { $0 < 0 }) == true {
                    findings.append(error("negative-selector-index", "Selector paths and occurrence indices must be non-negative.", step))
                }
                if selector.matchStrategy == .regularExpression {
                    let patterns = [selector.identifier, selector.title, selector.value, selector.accessibilityDescription].compactMap { $0 }
                    if patterns.contains(where: { (try? NSRegularExpression(pattern: $0)) == nil }) {
                        findings.append(error("invalid-selector-pattern", "Selector contains an invalid regular expression.", step))
                    }
                }
            }
        }

        return SafetyValidationReport(findings: findings)
    }

    private func selector(for step: WorkflowStep) -> ElementSelector? {
        switch step.action {
        case let .click(action): action.selector
        case let .typeText(action): action.selector
        case let .waitForElement(action): action.selector
        case let .assertElement(action): action.selector
        default: nil
        }
    }

    private func appendInvalidTimeout(
        _ timeout: TimeInterval,
        step: WorkflowStep,
        to findings: inout [SafetyFinding]
    ) {
        if timeout <= 0 || !timeout.isFinite {
            findings.append(error("invalid-timeout", "Timeout must be finite and positive.", step))
        }
    }

    private func error(_ code: String, _ message: String, _ step: WorkflowStep) -> SafetyFinding {
        SafetyFinding(severity: .error, code: code, message: message, stepID: step.id)
    }
}
