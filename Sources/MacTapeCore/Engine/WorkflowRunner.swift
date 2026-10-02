import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

public enum WorkflowRunEvent: Sendable {
    case runStarted(runID: UUID, workflowID: UUID, dryRun: Bool)
    case stepStarted(
        runID: UUID,
        stepID: UUID,
        index: Int,
        kind: WorkflowStep.Action.Kind,
        dryRun: Bool
    )
    case stepFinished(
        runID: UUID,
        stepID: UUID,
        index: Int,
        status: StepRunStatus
    )
    case runFinished(RunRecord)
}

public struct WorkflowRunnerOptions: Sendable {
    public var dryRun: Bool
    public var defaultStepTimeout: TimeInterval
    public var shellAuthorization: ShellExecutionAuthorization
    public var eventHandler: (@Sendable (WorkflowRunEvent) -> Void)?

    public init(
        dryRun: Bool = false,
        defaultStepTimeout: TimeInterval = 30,
        shellAuthorization: ShellExecutionAuthorization = .denied,
        eventHandler: (@Sendable (WorkflowRunEvent) -> Void)? = nil
    ) {
        self.dryRun = dryRun
        self.defaultStepTimeout = defaultStepTimeout
        self.shellAuthorization = shellAuthorization
        self.eventHandler = eventHandler
    }
}

public enum WorkflowRunnerFailureReason: Sendable, Equatable {
    case cancelled
    case stepFailed(stepID: UUID, code: String)
}

public struct WorkflowRunFailure: Error, LocalizedError, Sendable {
    public var reason: WorkflowRunnerFailureReason
    public var record: RunRecord

    public init(reason: WorkflowRunnerFailureReason, record: RunRecord) {
        self.reason = reason
        self.record = record
    }

    public var errorDescription: String? {
        switch reason {
        case .cancelled:
            "The workflow run was cancelled."
        case .stepFailed:
            "A workflow step failed. Inspect the structured run record for details."
        }
    }
}

public enum WorkflowRunnerError: Error, LocalizedError, Sendable {
    case alreadyRunning
    case invalidDefaultTimeout
    case safetyValidationFailed(SafetyValidationReport)

    public var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            "This workflow runner is already executing a workflow."
        case .invalidDefaultTimeout:
            "The default step timeout must be finite and positive."
        case .safetyValidationFailed:
            "The workflow failed safety validation."
        }
    }
}

private enum WorkflowActionError: Error, Sendable {
    case timedOut
    case cancelled
    case applicationNotInstalled
    case applicationLaunchFailed
    case selectorNotResolved
    case clickFailed
    case focusFailed
    case applicationContextRequired
    case applicationFocusLost
    case ambiguousSelector
    case eventCreationFailed
    case unsupportedShortcutKey
    case assertionFailed
    case shellLaunchFailed
    case shellFailed

    var diagnosticCode: String {
        switch self {
        case .timedOut: "step-timeout"
        case .cancelled: "cancelled"
        case .applicationNotInstalled: "application-not-installed"
        case .applicationLaunchFailed: "application-launch-failed"
        case .selectorNotResolved: "selector-not-resolved"
        case .clickFailed: "click-failed"
        case .focusFailed: "focus-failed"
        case .applicationContextRequired: "application-context-required"
        case .applicationFocusLost: "application-focus-lost"
        case .ambiguousSelector: "selector-ambiguous"
        case .eventCreationFailed: "input-event-creation-failed"
        case .unsupportedShortcutKey: "unsupported-shortcut-key"
        case .assertionFailed: "assertion-failed"
        case .shellLaunchFailed: "shell-launch-failed"
        case .shellFailed: "shell-failed"
        }
    }

    var safeMessage: String {
        switch self {
        case .timedOut: "The step exceeded its configured timeout."
        case .cancelled: "The step was cancelled before completion."
        case .applicationNotInstalled: "The requested application is not installed."
        case .applicationLaunchFailed: "macOS could not launch the requested application."
        case .selectorNotResolved: "The target UI element could not be resolved."
        case .clickFailed: "The target did not accept the requested click action."
        case .focusFailed: "The target UI element could not be focused."
        case .applicationContextRequired: "Choose a target application or add an Open App step before sending input."
        case .applicationFocusLost: "The target application could not be focused, or focus changed before input was sent."
        case .ambiguousSelector: "Several UI elements match this selector. Add more specific attributes or choose an occurrence index."
        case .eventCreationFailed: "macOS could not create an input event."
        case .unsupportedShortcutKey: "The shortcut key is not supported by this runner."
        case .assertionFailed: "The element assertion did not become true."
        case .shellLaunchFailed: "The explicitly authorized shell process could not start."
        case .shellFailed: "The explicitly authorized shell process exited unsuccessfully."
        }
    }
}

/// Executes validated workflows serially. The actor is intentionally single-run
/// so cancellation and the current application context cannot cross run bounds.
public actor WorkflowRunner {
    private let resolver: SelectorResolver
    private let safetyValidator: SafetyValidator
    private var activeRunID: UUID?
    private var cancellationRequested = false

    public init(
        resolver: SelectorResolver = SelectorResolver(),
        safetyValidator: SafetyValidator = SafetyValidator()
    ) {
        self.resolver = resolver
        self.safetyValidator = safetyValidator
    }

    public var isRunning: Bool {
        activeRunID != nil
    }

    /// Requests cancellation at the next safe boundary. Long waits, polling,
    /// typing, and shell execution check this flag repeatedly.
    public func cancel() {
        guard activeRunID != nil else { return }
        cancellationRequested = true
    }

    /// Runs a workflow using caller-supplied variable values.
    ///
    /// Neither values nor expanded action payloads are included in events,
    /// diagnostics, or the returned RunRecord. Only supplied variable *names*
    /// are retained. This remains true for non-secret variables as a simple,
    /// auditable invariant.
    public func run(
        _ workflow: Workflow,
        variableValues: [String: String] = [:],
        options: WorkflowRunnerOptions = WorkflowRunnerOptions()
    ) async throws -> RunRecord {
        guard activeRunID == nil else { throw WorkflowRunnerError.alreadyRunning }
        guard options.defaultStepTimeout > 0, options.defaultStepTimeout.isFinite else {
            throw WorkflowRunnerError.invalidDefaultTimeout
        }

        // Expand before authorization: a reviewed template is not approval for
        // arbitrary runtime substitutions in a shell command.
        let expandedWorkflow = try workflow.expandingVariables(overrides: variableValues)
        let safetyReport = safetyValidator.validate(
            expandedWorkflow,
            shellAuthorization: options.shellAuthorization,
            requiresShellAuthorization: !options.dryRun
        )
        guard safetyReport.isSafeToRun else {
            throw WorkflowRunnerError.safetyValidationFailed(safetyReport)
        }

        // Expansion is memory-only. Persisted models and event payloads retain
        // the source templates, never their runtime substitutions.
        let runID = UUID()
        activeRunID = runID
        cancellationRequested = false
        defer {
            activeRunID = nil
            cancellationRequested = false
        }

        var record = RunRecord(
            id: runID,
            workflowID: workflow.id,
            workflowName: workflow.name,
            status: .running,
            suppliedVariables: Array(variableValues.keys),
            steps: workflow.steps.enumerated().map { index, step in
                StepRunRecord(
                    stepID: step.id,
                    stepIndex: index,
                    actionKind: step.kind,
                    status: step.isEnabled ? .pending : .skipped
                )
            }
        )
        emit(.runStarted(runID: runID, workflowID: workflow.id, dryRun: options.dryRun), options)

        var currentBundleIdentifier: String?

        for (index, step) in expandedWorkflow.steps.enumerated() {
            guard step.isEnabled else { continue }

            do {
                try ensureNotCancelled()
            } catch {
                record = cancelRecord(record, currentStepIndex: nil)
                emit(.runFinished(record), options)
                throw WorkflowRunFailure(reason: .cancelled, record: record)
            }

            record.steps[index].status = .running
            record.steps[index].startedAt = Date()
            emit(
                .stepStarted(
                    runID: runID,
                    stepID: step.id,
                    index: index,
                    kind: step.kind,
                    dryRun: options.dryRun
                ),
                options
            )

            do {
                let timeout = timeout(for: step, defaultTimeout: options.defaultStepTimeout)
                currentBundleIdentifier = try await executeWithTimeout(
                    timeout,
                    step: step,
                    currentBundleIdentifier: currentBundleIdentifier,
                    options: options
                )
                record.steps[index].status = .succeeded
                record.steps[index].finishedAt = Date()
                emit(
                    .stepFinished(
                        runID: runID,
                        stepID: step.id,
                        index: index,
                        status: .succeeded
                    ),
                    options
                )
            } catch is CancellationError {
                record.steps[index].status = .cancelled
                record.steps[index].finishedAt = Date()
                record = cancelRecord(record, currentStepIndex: index)
                emit(
                    .stepFinished(
                        runID: runID,
                        stepID: step.id,
                        index: index,
                        status: .cancelled
                    ),
                    options
                )
                emit(.runFinished(record), options)
                throw WorkflowRunFailure(reason: .cancelled, record: record)
            } catch {
                if cancellationRequested {
                    record.steps[index].status = .cancelled
                    record.steps[index].finishedAt = Date()
                    record = cancelRecord(record, currentStepIndex: index)
                    emit(
                        .stepFinished(
                            runID: runID,
                            stepID: step.id,
                            index: index,
                            status: .cancelled
                        ),
                        options
                    )
                    emit(.runFinished(record), options)
                    throw WorkflowRunFailure(reason: .cancelled, record: record)
                }

                let diagnostic = safeDiagnostic(for: error, stepID: step.id)
                record.steps[index].status = .failed
                record.steps[index].finishedAt = Date()
                record.steps[index].diagnostics.append(diagnostic)
                record.status = .failed
                record.finishedAt = Date()
                record.diagnostics.append(diagnostic)
                emit(
                    .stepFinished(
                        runID: runID,
                        stepID: step.id,
                        index: index,
                        status: .failed
                    ),
                    options
                )
                emit(.runFinished(record), options)
                throw WorkflowRunFailure(
                    reason: .stepFailed(stepID: step.id, code: diagnostic.code),
                    record: record
                )
            }
        }

        record.status = .succeeded
        record.finishedAt = Date()
        emit(.runFinished(record), options)
        return record
    }

    private func executeWithTimeout(
        _ timeout: TimeInterval,
        step: WorkflowStep,
        currentBundleIdentifier: String?,
        options: WorkflowRunnerOptions
    ) async throws -> String? {
        try await withThrowingTaskGroup(of: Optional<String>.self) { group in
            defer { group.cancelAll() }
            group.addTask { [self] in
                try await execute(
                    step,
                    currentBundleIdentifier: currentBundleIdentifier,
                    options: options
                )
            }
            group.addTask {
                try await ContinuousClock().sleep(for: Self.duration(seconds: timeout))
                throw WorkflowActionError.timedOut
            }

            guard let result = try await group.next() else {
                throw WorkflowActionError.timedOut
            }
            return result
        }
    }

    private func execute(
        _ step: WorkflowStep,
        currentBundleIdentifier: String?,
        options: WorkflowRunnerOptions
    ) async throws -> String? {
        try ensureNotCancelled()

        switch step.action {
        case let .openApp(action):
            if options.dryRun {
                guard await WorkspaceApplicationLauncher.isInstalled(action.bundleIdentifier) else {
                    throw WorkflowActionError.applicationNotInstalled
                }
            } else {
                do {
                    try await WorkspaceApplicationLauncher.launch(action)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    throw WorkflowActionError.applicationLaunchFailed
                }
            }
            return action.bundleIdentifier

        case let .wait(action):
            if !options.dryRun {
                try await cancellableSleep(seconds: action.duration)
            }

        case let .click(action):
            let targetBundle = action.selector.bundleIdentifier ?? currentBundleIdentifier
            let candidate = try resolve(
                action.selector,
                bundleIdentifier: targetBundle
            )
            if !options.dryRun {
                try await activateTarget(targetBundle)
                try await click(action, candidate: candidate)
            }
            return targetBundle

        case let .shortcut(action):
            let keyCode = try ShortcutKey.keyCode(for: action.key)
            if !options.dryRun {
                try await activateTarget(currentBundleIdentifier)
                try await postShortcut(keyCode: keyCode, modifiers: action.modifiers, bundleIdentifier: currentBundleIdentifier)
            }

        case let .typeText(action):
            let targetBundle = action.selector?.bundleIdentifier ?? currentBundleIdentifier
            if !options.dryRun { try await activateTarget(targetBundle) }
            if let selector = action.selector {
                let candidate = try resolve(selector, bundleIdentifier: targetBundle)
                if !options.dryRun {
                    try focus(candidate.element.element)
                }
            }
            if !options.dryRun {
                if action.clearExisting {
                    try await postShortcut(keyCode: 0, modifiers: [.command], bundleIdentifier: targetBundle) // Command-A
                    try await postShortcut(keyCode: 51, modifiers: [], bundleIdentifier: targetBundle) // Delete
                }
                try await postText(action.text, delay: action.typingDelay, bundleIdentifier: targetBundle)
            }
            return targetBundle

        case let .waitForElement(action):
            let targetBundle = action.selector.bundleIdentifier ?? currentBundleIdentifier
            if options.dryRun {
                _ = try resolve(action.selector, bundleIdentifier: targetBundle)
            } else {
                try await waitForElement(action, bundleIdentifier: targetBundle)
            }
            return targetBundle

        case let .assertElement(action):
            let targetBundle = action.selector.bundleIdentifier ?? currentBundleIdentifier
            let timeout = options.dryRun ? 0 : action.timeout
            try await waitForAssertion(
                selector: action.selector,
                assertion: action.assertion,
                timeout: timeout,
                bundleIdentifier: targetBundle
            )
            return targetBundle

        case let .runShell(action):
            // SafetyValidator has already verified this exact payload. Repeat
            // the capability check at the mutation boundary (defense in depth).
            guard options.dryRun || options.shellAuthorization.permits(step) else {
                throw WorkflowActionError.shellLaunchFailed
            }
            if !options.dryRun {
                try await runShell(action)
            }
        }

        return currentBundleIdentifier
    }

    private func resolve(
        _ selector: ElementSelector,
        bundleIdentifier: String?
    ) throws -> SelectorCandidate {
        do {
            return try resolver.resolve(selector, bundleIdentifier: bundleIdentifier)
        } catch SelectorResolutionError.ambiguousMatch {
            throw WorkflowActionError.ambiguousSelector
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw WorkflowActionError.selectorNotResolved
        }
    }

    private func click(
        _ action: WorkflowStep.ClickAction,
        candidate: SelectorCandidate
    ) async throws {
        try ensureNotCancelled()
        if action.button == .left, action.clickCount == 1 {
            let result = AXUIElementPerformAction(
                candidate.element.element,
                kAXPressAction as CFString
            )
            if result == .success { return }
        }

        // Coordinates are derived only from a freshly resolved live element,
        // never from the original recording location or stale snapshot frame.
        guard let frame = AXAttribute.frame(from: candidate.element.element), !frame.isEmpty else {
            throw WorkflowActionError.clickFailed
        }
        let point = CGPoint(x: frame.midX, y: frame.midY)
        try await postMouseClicks(
            at: point,
            button: action.button,
            count: action.clickCount,
            bundleIdentifier: candidate.snapshot.bundleIdentifier
        )
    }

    private func postMouseClicks(
        at point: CGPoint,
        button: MouseButton,
        count: Int,
        bundleIdentifier: String?
    ) async throws {
        let mouseButton: CGMouseButton
        let downType: CGEventType
        let upType: CGEventType
        switch button {
        case .left:
            mouseButton = .left
            downType = .leftMouseDown
            upType = .leftMouseUp
        case .right:
            mouseButton = .right
            downType = .rightMouseDown
            upType = .rightMouseUp
        case .middle:
            mouseButton = .center
            downType = .otherMouseDown
            upType = .otherMouseUp
        }

        for index in 1...count {
            try ensureNotCancelled()
            try await verifyTarget(bundleIdentifier)
            guard
                let down = CGEvent(
                    mouseEventSource: nil,
                    mouseType: downType,
                    mouseCursorPosition: point,
                    mouseButton: mouseButton
                ),
                let up = CGEvent(
                    mouseEventSource: nil,
                    mouseType: upType,
                    mouseCursorPosition: point,
                    mouseButton: mouseButton
                )
            else {
                throw WorkflowActionError.eventCreationFailed
            }
            down.setIntegerValueField(.mouseEventClickState, value: Int64(index))
            up.setIntegerValueField(.mouseEventClickState, value: Int64(index))
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            if index < count {
                try await cancellableSleep(seconds: 0.08)
            }
        }
    }

    private func focus(_ element: AXUIElement) throws {
        let result = AXUIElementSetAttributeValue(
            element,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )
        guard result == .success else { throw WorkflowActionError.focusFailed }
    }

    private func postShortcut(keyCode: CGKeyCode, modifiers: [KeyModifier], bundleIdentifier: String?) async throws {
        try ensureNotCancelled()
        try await verifyTarget(bundleIdentifier)
        guard
            let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
            let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        else {
            throw WorkflowActionError.eventCreationFailed
        }
        let flags = Self.eventFlags(for: modifiers)
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func postText(_ text: String, delay: TimeInterval, bundleIdentifier: String?) async throws {
        for character in text {
            try ensureNotCancelled()
            try await verifyTarget(bundleIdentifier)
            guard
                let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            else {
                throw WorkflowActionError.eventCreationFailed
            }

            var utf16 = Array(String(character).utf16)
            utf16.withUnsafeBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { return }
                down.keyboardSetUnicodeString(
                    stringLength: buffer.count,
                    unicodeString: baseAddress
                )
                up.keyboardSetUnicodeString(
                    stringLength: buffer.count,
                    unicodeString: baseAddress
                )
            }
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)

            if delay > 0 {
                try await cancellableSleep(seconds: delay)
            }
            // Overwrite the transient buffer promptly. Swift strings remain
            // value types in memory, but no copy is retained by the runner.
            utf16.withUnsafeMutableBufferPointer { buffer in
                buffer.initialize(repeating: 0)
            }
        }
    }

    private func waitForElement(
        _ action: WorkflowStep.WaitForElementAction,
        bundleIdentifier: String?
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.duration(seconds: action.timeout))

        while true {
            try ensureNotCancelled()
            do {
                _ = try resolver.resolve(action.selector, bundleIdentifier: bundleIdentifier)
                return
            } catch SelectorResolutionError.noMatch {
                // A missing element may appear before the polling deadline.
            }
            guard clock.now < deadline else { throw WorkflowActionError.selectorNotResolved }
            try await cancellableSleep(seconds: action.pollingInterval)
        }
    }

    private func waitForAssertion(
        selector: ElementSelector,
        assertion: ElementAssertion,
        timeout: TimeInterval,
        bundleIdentifier: String?
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.duration(seconds: timeout))

        while true {
            try ensureNotCancelled()
            if try assertionPasses(
                selector: selector,
                assertion: assertion,
                bundleIdentifier: bundleIdentifier
            ) {
                return
            }
            guard clock.now < deadline else { throw WorkflowActionError.assertionFailed }
            try await cancellableSleep(seconds: 0.2)
        }
    }

    private func assertionPasses(
        selector: ElementSelector,
        assertion: ElementAssertion,
        bundleIdentifier: String?
    ) throws -> Bool {
        let candidate: SelectorCandidate
        do {
            candidate = try resolver.resolve(selector, bundleIdentifier: bundleIdentifier)
        } catch SelectorResolutionError.noMatch {
            return assertion == .doesNotExist
        }

        let element = candidate.element.element

        switch assertion {
        case .exists:
            return true
        case .doesNotExist:
            return false
        case .enabled:
            return AXAttribute.bool(kAXEnabledAttribute, from: element) == true
        case .disabled:
            return AXAttribute.bool(kAXEnabledAttribute, from: element) == false
        case let .valueEquals(expected):
            return Self.stringValue(
                AXAttribute.copy(kAXValueAttribute, from: element)
            ) == expected
        case let .valueContains(expected):
            return Self.stringValue(
                AXAttribute.copy(kAXValueAttribute, from: element)
            )?.contains(expected) == true
        case let .titleEquals(expected):
            return AXAttribute.string(kAXTitleAttribute, from: element) == expected
        case let .titleContains(expected):
            return AXAttribute.string(kAXTitleAttribute, from: element)?.contains(expected) == true
        }
    }

    private func runShell(_ action: WorkflowStep.RunShellAction) async throws {
        let managed = ManagedProcess()
        let process = managed.process
        process.executableURL = URL(fileURLWithPath: action.shell)
        process.arguments = ["-c", action.command]
        if let workingDirectory = action.workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
        }
        process.environment = ProcessInfo.processInfo.environment.merging(action.environment) { _, new in new }
        // Never capture shell output: commands frequently print secrets.
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw WorkflowActionError.shellLaunchFailed
        }

        do {
            while managed.isRunning {
                try ensureNotCancelled()
                try await cancellableSleep(seconds: 0.05)
            }
        } catch {
            await managed.terminateAndWait()
            throw error
        }

        guard managed.terminationStatus == 0 else {
            throw WorkflowActionError.shellFailed
        }
    }

    private func activateTarget(_ bundleIdentifier: String?) async throws {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { throw WorkflowActionError.applicationContextRequired }
        try ensureNotCancelled()
        guard await WorkspaceApplicationLauncher.activate(bundleIdentifier) else { throw WorkflowActionError.applicationFocusLost }
        // Activation is asynchronous in macOS. Do not send input until the
        // requested app is actually frontmost, with a short cancellable bound.
        for _ in 0..<20 {
            if await WorkspaceApplicationLauncher.isFrontmost(bundleIdentifier) { return }
            try await cancellableSleep(seconds: 0.05)
        }
        throw WorkflowActionError.applicationFocusLost
    }

    private func verifyTarget(_ bundleIdentifier: String?) async throws {
        guard let bundleIdentifier else { throw WorkflowActionError.applicationContextRequired }
        guard await WorkspaceApplicationLauncher.isFrontmost(bundleIdentifier) else { throw WorkflowActionError.applicationFocusLost }
        try ensureNotCancelled()
    }

    private func cancellableSleep(seconds: TimeInterval) async throws {
        guard seconds > 0 else {
            try ensureNotCancelled()
            return
        }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.duration(seconds: seconds))

        while clock.now < deadline {
            try ensureNotCancelled()
            let remaining = clock.now.duration(to: deadline)
            let slice = min(remaining, .milliseconds(100))
            try await clock.sleep(for: slice)
        }
        try ensureNotCancelled()
    }

    private func ensureNotCancelled() throws {
        if cancellationRequested || Task.isCancelled {
            throw CancellationError()
        }
    }

    private func timeout(for step: WorkflowStep, defaultTimeout: TimeInterval) -> TimeInterval {
        switch step.action {
        case let .wait(action):
            max(defaultTimeout, action.duration + 1)
        case let .openApp(action):
            action.timeout
        case let .waitForElement(action):
            max(defaultTimeout, action.timeout + 1)
        case let .assertElement(action):
            max(defaultTimeout, action.timeout + 1)
        case let .runShell(action):
            action.timeout
        default:
            defaultTimeout
        }
    }

    private func cancelRecord(_ record: RunRecord, currentStepIndex: Int?) -> RunRecord {
        var copy = record
        copy.status = .cancelled
        copy.finishedAt = Date()
        if let currentStepIndex {
            for index in copy.steps.indices where index > currentStepIndex && copy.steps[index].status == .pending {
                copy.steps[index].status = .cancelled
            }
        } else {
            for index in copy.steps.indices where copy.steps[index].status == .pending {
                copy.steps[index].status = .cancelled
            }
        }
        return copy
    }

    private func safeDiagnostic(for error: Error, stepID: UUID) -> Diagnostic {
        let actionError: WorkflowActionError
        if let known = error as? WorkflowActionError {
            actionError = known
        } else if error is SelectorResolutionError {
            actionError = (error as? SelectorResolutionError) == .ambiguousMatch ? .ambiguousSelector : .selectorNotResolved
        } else {
            actionError = .eventCreationFailed
        }
        return Diagnostic(
            severity: .error,
            code: actionError.diagnosticCode,
            message: actionError.safeMessage,
            stepID: stepID
        )
    }

    private func emit(_ event: WorkflowRunEvent, _ options: WorkflowRunnerOptions) {
        options.eventHandler?(event)
    }

    private static func eventFlags(for modifiers: [KeyModifier]) -> CGEventFlags {
        var flags: CGEventFlags = []
        for modifier in modifiers {
            switch modifier {
            case .command: flags.insert(.maskCommand)
            case .option: flags.insert(.maskAlternate)
            case .control: flags.insert(.maskControl)
            case .shift: flags.insert(.maskShift)
            case .function: flags.insert(.maskSecondaryFn)
            }
        }
        return flags
    }

    private static func stringValue(_ value: CFTypeRef?) -> String? {
        switch value {
        case let string as String:
            string
        case let number as NSNumber:
            number.stringValue
        default:
            nil
        }
    }

    private static func duration(seconds: TimeInterval) -> Duration {
        let nanoseconds = seconds * 1_000_000_000
        if nanoseconds >= Double(Int64.max) { return .nanoseconds(Int64.max) }
        return .nanoseconds(Int64(max(0, nanoseconds.rounded())))
    }
}

@MainActor
private enum WorkspaceApplicationLauncher {
    static func isInstalled(_ bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    static func isRunning(_ bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    static func activate(_ bundleIdentifier: String) -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else { return false }
        return app.activate()
    }

    static func isFrontmost(_ bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier
    }

    static func launch(_ action: WorkflowStep.OpenAppAction) async throws {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: action.bundleIdentifier
        ) else {
            throw WorkflowActionError.applicationNotInstalled
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = action.arguments
        configuration.activates = true

        let completion = LaunchCompletion()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                guard completion.install(continuation) else { return }
                NSWorkspace.shared.openApplication(
                    at: url,
                    configuration: configuration
                ) { _, error in
                    if let error {
                        completion.finish(.failure(error))
                    } else {
                        completion.finish(.success(()))
                    }
                }
            }
        } onCancel: {
            // macOS cannot retract an already-submitted launch request, but a
            // stalled callback must not keep a cancelled workflow alive.
            completion.finish(.failure(CancellationError()))
        }
        if action.waitUntilRunning {
            while !NSRunningApplication.runningApplications(withBundleIdentifier: action.bundleIdentifier).contains(where: \.isFinishedLaunching) {
                try await Task.sleep(for: .milliseconds(50))
            }
        }
    }
}

private final class LaunchCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, any Error>?
    private var result: Result<Void, any Error>?

    func install(_ continuation: CheckedContinuation<Void, any Error>) -> Bool {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(with: result)
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func finish(_ result: Result<Void, any Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

private final class ManagedProcess: @unchecked Sendable {
    let process = Process()

    var isRunning: Bool { process.isRunning }
    var terminationStatus: Int32 { process.terminationStatus }

    func terminateAndWait() async {
        if process.isRunning {
            process.terminate()
        }
        for _ in 0..<10 where process.isRunning {
            // Cleanup must finish even when the workflow task is cancelled.
            await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.02) { continuation.resume() }
            }
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }
}

enum ShortcutKey {
    private static let codes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5,
        "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
        "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
        "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "return": 36, "enter": 36, "l": 37, "j": 38, "'": 39,
        "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45,
        "m": 46, ".": 47, "tab": 48, "space": 49, "`": 50,
        "delete": 51, "backspace": 51, "escape": 53, "esc": 53,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96,
        "f6": 97, "f7": 98, "f8": 100, "f9": 101, "f10": 109,
        "f11": 103, "f12": 111, "home": 115, "end": 119,
        "pageup": 116, "pagedown": 121, "left": 123, "right": 124,
        "down": 125, "up": 126,
    ]

    static func keyCode(for key: String) throws -> CGKeyCode {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("keycode:"), let code = UInt16(normalized.dropFirst(8)), code <= 127 { return code }
        guard let code = codes[normalized] else {
            throw WorkflowActionError.unsupportedShortcutKey
        }
        return code
    }

    static func isSupported(_ key: String) -> Bool { (try? keyCode(for: key)) != nil }
}
