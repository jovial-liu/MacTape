import Foundation

public enum MouseButton: String, Codable, CaseIterable, Hashable, Sendable {
    case left
    case right
    case middle
}

public enum KeyModifier: String, Codable, CaseIterable, Hashable, Sendable {
    case command
    case option
    case control
    case shift
    case function
}

public enum ElementAssertion: Hashable, Sendable {
    case exists
    case doesNotExist
    case enabled
    case disabled
    case valueEquals(String)
    case valueContains(String)
    case titleEquals(String)
    case titleContains(String)
}

extension ElementAssertion: Codable {
    private enum Kind: String, Codable {
        case exists
        case doesNotExist
        case enabled
        case disabled
        case valueEquals
        case valueContains
        case titleEquals
        case titleContains
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .exists:
            self = .exists
        case .doesNotExist:
            self = .doesNotExist
        case .enabled:
            self = .enabled
        case .disabled:
            self = .disabled
        case .valueEquals:
            self = .valueEquals(try container.decode(String.self, forKey: .value))
        case .valueContains:
            self = .valueContains(try container.decode(String.self, forKey: .value))
        case .titleEquals:
            self = .titleEquals(try container.decode(String.self, forKey: .value))
        case .titleContains:
            self = .titleContains(try container.decode(String.self, forKey: .value))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .exists:
            try container.encode(Kind.exists, forKey: .type)
        case .doesNotExist:
            try container.encode(Kind.doesNotExist, forKey: .type)
        case .enabled:
            try container.encode(Kind.enabled, forKey: .type)
        case .disabled:
            try container.encode(Kind.disabled, forKey: .type)
        case let .valueEquals(value):
            try container.encode(Kind.valueEquals, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .valueContains(value):
            try container.encode(Kind.valueContains, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .titleEquals(value):
            try container.encode(Kind.titleEquals, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .titleContains(value):
            try container.encode(Kind.titleContains, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }

    func expandingVariables(
        using values: [String: String],
        missing policy: MissingVariablePolicy
    ) throws -> Self {
        switch self {
        case .exists, .doesNotExist, .enabled, .disabled:
            self
        case let .valueEquals(value):
            .valueEquals(try VariableTemplate.expand(value, using: values, missing: policy))
        case let .valueContains(value):
            .valueContains(try VariableTemplate.expand(value, using: values, missing: policy))
        case let .titleEquals(value):
            .titleEquals(try VariableTemplate.expand(value, using: values, missing: policy))
        case let .titleContains(value):
            .titleContains(try VariableTemplate.expand(value, using: values, missing: policy))
        }
    }
}

/// One editable, identifiable action in a workflow.
public struct WorkflowStep: Identifiable, Codable, Hashable, Sendable {
    public struct ClickAction: Codable, Hashable, Sendable {
        public var selector: ElementSelector
        public var button: MouseButton
        public var clickCount: Int

        public init(
            selector: ElementSelector,
            button: MouseButton = .left,
            clickCount: Int = 1
        ) {
            self.selector = selector
            self.button = button
            self.clickCount = clickCount
        }
    }

    public struct TypeTextAction: Codable, Hashable, Sendable {
        public var text: String
        public var selector: ElementSelector?
        public var clearExisting: Bool
        /// Delay between generated keystrokes, in seconds.
        public var typingDelay: TimeInterval

        public init(
            text: String,
            selector: ElementSelector? = nil,
            clearExisting: Bool = false,
            typingDelay: TimeInterval = 0
        ) {
            self.text = text
            self.selector = selector
            self.clearExisting = clearExisting
            self.typingDelay = typingDelay
        }
    }

    public struct ShortcutAction: Codable, Hashable, Sendable {
        public var key: String
        public var modifiers: [KeyModifier]

        public init(key: String, modifiers: [KeyModifier] = [.command]) {
            self.key = key
            let requested = Set(modifiers)
            self.modifiers = KeyModifier.allCases.filter(requested.contains)
        }
    }

    public struct WaitAction: Codable, Hashable, Sendable {
        public var duration: TimeInterval

        public init(duration: TimeInterval) {
            self.duration = duration
        }
    }

    public struct OpenAppAction: Codable, Hashable, Sendable {
        public var bundleIdentifier: String
        public var arguments: [String]
        public var waitUntilRunning: Bool
        public var timeout: TimeInterval

        public init(
            bundleIdentifier: String,
            arguments: [String] = [],
            waitUntilRunning: Bool = true,
            timeout: TimeInterval = 10
        ) {
            self.bundleIdentifier = bundleIdentifier
            self.arguments = arguments
            self.waitUntilRunning = waitUntilRunning
            self.timeout = timeout
        }
    }

    public struct WaitForElementAction: Codable, Hashable, Sendable {
        public var selector: ElementSelector
        public var timeout: TimeInterval
        public var pollingInterval: TimeInterval

        public init(
            selector: ElementSelector,
            timeout: TimeInterval = 10,
            pollingInterval: TimeInterval = 0.2
        ) {
            self.selector = selector
            self.timeout = timeout
            self.pollingInterval = pollingInterval
        }
    }

    public struct AssertElementAction: Codable, Hashable, Sendable {
        public var selector: ElementSelector
        public var assertion: ElementAssertion
        public var timeout: TimeInterval

        public init(
            selector: ElementSelector,
            assertion: ElementAssertion = .exists,
            timeout: TimeInterval = 0
        ) {
            self.selector = selector
            self.assertion = assertion
            self.timeout = timeout
        }
    }

    public struct RunShellAction: Codable, Hashable, Sendable {
        public var command: String
        public var shell: String
        public var workingDirectory: String?
        public var environment: [String: String]
        public var timeout: TimeInterval

        public init(
            command: String,
            shell: String = "/bin/zsh",
            workingDirectory: String? = nil,
            environment: [String: String] = [:],
            timeout: TimeInterval = 60
        ) {
            self.command = command
            self.shell = shell
            self.workingDirectory = workingDirectory
            self.environment = environment
            self.timeout = timeout
        }
    }

    public enum Action: Hashable, Sendable {
        public enum Kind: String, Codable, CaseIterable, Hashable, Sendable {
            case click
            case typeText
            case shortcut
            case wait
            case openApp
            case waitForElement
            case assertElement
            case runShell
        }

        case click(ClickAction)
        case typeText(TypeTextAction)
        case shortcut(ShortcutAction)
        case wait(WaitAction)
        case openApp(OpenAppAction)
        case waitForElement(WaitForElementAction)
        case assertElement(AssertElementAction)
        case runShell(RunShellAction)

        public var kind: Kind {
            switch self {
            case .click: .click
            case .typeText: .typeText
            case .shortcut: .shortcut
            case .wait: .wait
            case .openApp: .openApp
            case .waitForElement: .waitForElement
            case .assertElement: .assertElement
            case .runShell: .runShell
            }
        }
    }

    public var id: UUID
    public var note: String?
    public var isEnabled: Bool
    public var action: Action

    public init(
        id: UUID = UUID(),
        note: String? = nil,
        isEnabled: Bool = true,
        action: Action
    ) {
        self.id = id
        self.note = note
        self.isEnabled = isEnabled
        self.action = action
    }

    public var kind: Action.Kind { action.kind }

    public static func click(
        id: UUID = UUID(),
        selector: ElementSelector,
        button: MouseButton = .left,
        clickCount: Int = 1,
        note: String? = nil,
        isEnabled: Bool = true
    ) -> Self {
        Self(
            id: id,
            note: note,
            isEnabled: isEnabled,
            action: .click(.init(selector: selector, button: button, clickCount: clickCount))
        )
    }

    public static func typeText(
        id: UUID = UUID(),
        text: String,
        selector: ElementSelector? = nil,
        clearExisting: Bool = false,
        typingDelay: TimeInterval = 0,
        note: String? = nil,
        isEnabled: Bool = true
    ) -> Self {
        Self(
            id: id,
            note: note,
            isEnabled: isEnabled,
            action: .typeText(
                .init(
                    text: text,
                    selector: selector,
                    clearExisting: clearExisting,
                    typingDelay: typingDelay
                )
            )
        )
    }

    public static func shortcut(
        id: UUID = UUID(),
        key: String,
        modifiers: [KeyModifier] = [.command],
        note: String? = nil,
        isEnabled: Bool = true
    ) -> Self {
        Self(
            id: id,
            note: note,
            isEnabled: isEnabled,
            action: .shortcut(.init(key: key, modifiers: modifiers))
        )
    }

    public static func wait(
        id: UUID = UUID(),
        duration: TimeInterval,
        note: String? = nil,
        isEnabled: Bool = true
    ) -> Self {
        Self(
            id: id,
            note: note,
            isEnabled: isEnabled,
            action: .wait(.init(duration: duration))
        )
    }

    public static func openApp(
        id: UUID = UUID(),
        bundleIdentifier: String,
        arguments: [String] = [],
        waitUntilRunning: Bool = true,
        timeout: TimeInterval = 10,
        note: String? = nil,
        isEnabled: Bool = true
    ) -> Self {
        Self(
            id: id,
            note: note,
            isEnabled: isEnabled,
            action: .openApp(
                .init(
                    bundleIdentifier: bundleIdentifier,
                    arguments: arguments,
                    waitUntilRunning: waitUntilRunning,
                    timeout: timeout
                )
            )
        )
    }

    public static func waitForElement(
        id: UUID = UUID(),
        selector: ElementSelector,
        timeout: TimeInterval = 10,
        pollingInterval: TimeInterval = 0.2,
        note: String? = nil,
        isEnabled: Bool = true
    ) -> Self {
        Self(
            id: id,
            note: note,
            isEnabled: isEnabled,
            action: .waitForElement(
                .init(selector: selector, timeout: timeout, pollingInterval: pollingInterval)
            )
        )
    }

    public static func assertElement(
        id: UUID = UUID(),
        selector: ElementSelector,
        assertion: ElementAssertion = .exists,
        timeout: TimeInterval = 0,
        note: String? = nil,
        isEnabled: Bool = true
    ) -> Self {
        Self(
            id: id,
            note: note,
            isEnabled: isEnabled,
            action: .assertElement(
                .init(selector: selector, assertion: assertion, timeout: timeout)
            )
        )
    }

    public static func runShell(
        id: UUID = UUID(),
        command: String,
        shell: String = "/bin/zsh",
        workingDirectory: String? = nil,
        environment: [String: String] = [:],
        timeout: TimeInterval = 60,
        note: String? = nil,
        isEnabled: Bool = true
    ) -> Self {
        Self(
            id: id,
            note: note,
            isEnabled: isEnabled,
            action: .runShell(
                .init(
                    command: command,
                    shell: shell,
                    workingDirectory: workingDirectory,
                    environment: environment,
                    timeout: timeout
                )
            )
        )
    }

    public func expandingVariables(
        using values: [String: String],
        missing policy: MissingVariablePolicy = .error
    ) throws -> Self {
        var copy = self
        copy.note = try note.map { try VariableTemplate.expand($0, using: values, missing: policy) }
        copy.action = try action.expandingVariables(using: values, missing: policy)
        return copy
    }
}

extension WorkflowStep.Action: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case selector
        case button
        case clickCount
        case text
        case clearExisting
        case typingDelay
        case key
        case modifiers
        case duration
        case bundleIdentifier
        case arguments
        case waitUntilRunning
        case timeout
        case pollingInterval
        case assertion
        case command
        case shell
        case workingDirectory
        case environment
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(Kind.self, forKey: .type)

        switch type {
        case .click:
            self = .click(
                .init(
                    selector: try container.decode(ElementSelector.self, forKey: .selector),
                    button: try container.decodeIfPresent(MouseButton.self, forKey: .button) ?? .left,
                    clickCount: try container.decodeIfPresent(Int.self, forKey: .clickCount) ?? 1
                )
            )
        case .typeText:
            self = .typeText(
                .init(
                    text: try container.decode(String.self, forKey: .text),
                    selector: try container.decodeIfPresent(ElementSelector.self, forKey: .selector),
                    clearExisting: try container.decodeIfPresent(Bool.self, forKey: .clearExisting) ?? false,
                    typingDelay: try container.decodeIfPresent(TimeInterval.self, forKey: .typingDelay) ?? 0
                )
            )
        case .shortcut:
            self = .shortcut(
                .init(
                    key: try container.decode(String.self, forKey: .key),
                    modifiers: try container.decodeIfPresent([KeyModifier].self, forKey: .modifiers) ?? [.command]
                )
            )
        case .wait:
            self = .wait(.init(duration: try container.decode(TimeInterval.self, forKey: .duration)))
        case .openApp:
            self = .openApp(
                .init(
                    bundleIdentifier: try container.decode(String.self, forKey: .bundleIdentifier),
                    arguments: try container.decodeIfPresent([String].self, forKey: .arguments) ?? [],
                    waitUntilRunning: try container.decodeIfPresent(Bool.self, forKey: .waitUntilRunning) ?? true,
                    timeout: try container.decodeIfPresent(TimeInterval.self, forKey: .timeout) ?? 10
                )
            )
        case .waitForElement:
            self = .waitForElement(
                .init(
                    selector: try container.decode(ElementSelector.self, forKey: .selector),
                    timeout: try container.decodeIfPresent(TimeInterval.self, forKey: .timeout) ?? 10,
                    pollingInterval: try container.decodeIfPresent(TimeInterval.self, forKey: .pollingInterval) ?? 0.2
                )
            )
        case .assertElement:
            self = .assertElement(
                .init(
                    selector: try container.decode(ElementSelector.self, forKey: .selector),
                    assertion: try container.decodeIfPresent(ElementAssertion.self, forKey: .assertion) ?? .exists,
                    timeout: try container.decodeIfPresent(TimeInterval.self, forKey: .timeout) ?? 0
                )
            )
        case .runShell:
            self = .runShell(
                .init(
                    command: try container.decode(String.self, forKey: .command),
                    shell: try container.decodeIfPresent(String.self, forKey: .shell) ?? "/bin/zsh",
                    workingDirectory: try container.decodeIfPresent(String.self, forKey: .workingDirectory),
                    environment: try container.decodeIfPresent([String: String].self, forKey: .environment) ?? [:],
                    timeout: try container.decodeIfPresent(TimeInterval.self, forKey: .timeout) ?? 60
                )
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .type)

        switch self {
        case let .click(action):
            try container.encode(action.selector, forKey: .selector)
            try container.encode(action.button, forKey: .button)
            try container.encode(action.clickCount, forKey: .clickCount)
        case let .typeText(action):
            try container.encode(action.text, forKey: .text)
            try container.encodeIfPresent(action.selector, forKey: .selector)
            try container.encode(action.clearExisting, forKey: .clearExisting)
            try container.encode(action.typingDelay, forKey: .typingDelay)
        case let .shortcut(action):
            try container.encode(action.key, forKey: .key)
            try container.encode(action.modifiers, forKey: .modifiers)
        case let .wait(action):
            try container.encode(action.duration, forKey: .duration)
        case let .openApp(action):
            try container.encode(action.bundleIdentifier, forKey: .bundleIdentifier)
            try container.encode(action.arguments, forKey: .arguments)
            try container.encode(action.waitUntilRunning, forKey: .waitUntilRunning)
            try container.encode(action.timeout, forKey: .timeout)
        case let .waitForElement(action):
            try container.encode(action.selector, forKey: .selector)
            try container.encode(action.timeout, forKey: .timeout)
            try container.encode(action.pollingInterval, forKey: .pollingInterval)
        case let .assertElement(action):
            try container.encode(action.selector, forKey: .selector)
            try container.encode(action.assertion, forKey: .assertion)
            try container.encode(action.timeout, forKey: .timeout)
        case let .runShell(action):
            try container.encode(action.command, forKey: .command)
            try container.encode(action.shell, forKey: .shell)
            try container.encodeIfPresent(action.workingDirectory, forKey: .workingDirectory)
            try container.encode(action.environment, forKey: .environment)
            try container.encode(action.timeout, forKey: .timeout)
        }
    }

    fileprivate func expandingVariables(
        using values: [String: String],
        missing policy: MissingVariablePolicy
    ) throws -> Self {
        switch self {
        case let .click(action):
            return .click(
                .init(
                    selector: try action.selector.expandingVariables(using: values, missing: policy),
                    button: action.button,
                    clickCount: action.clickCount
                )
            )
        case let .typeText(action):
            return .typeText(
                .init(
                    text: try VariableTemplate.expand(action.text, using: values, missing: policy),
                    selector: try action.selector?.expandingVariables(using: values, missing: policy),
                    clearExisting: action.clearExisting,
                    typingDelay: action.typingDelay
                )
            )
        case let .shortcut(action):
            return .shortcut(
                .init(
                    key: try VariableTemplate.expand(action.key, using: values, missing: policy),
                    modifiers: action.modifiers
                )
            )
        case let .wait(action):
            return .wait(action)
        case let .openApp(action):
            return .openApp(
                .init(
                    bundleIdentifier: try VariableTemplate.expand(
                        action.bundleIdentifier,
                        using: values,
                        missing: policy
                    ),
                    arguments: try action.arguments.map {
                        try VariableTemplate.expand($0, using: values, missing: policy)
                    },
                    waitUntilRunning: action.waitUntilRunning,
                    timeout: action.timeout
                )
            )
        case let .waitForElement(action):
            return .waitForElement(
                .init(
                    selector: try action.selector.expandingVariables(using: values, missing: policy),
                    timeout: action.timeout,
                    pollingInterval: action.pollingInterval
                )
            )
        case let .assertElement(action):
            return .assertElement(
                .init(
                    selector: try action.selector.expandingVariables(using: values, missing: policy),
                    assertion: try action.assertion.expandingVariables(using: values, missing: policy),
                    timeout: action.timeout
                )
            )
        case let .runShell(action):
            var environment: [String: String] = [:]
            for key in action.environment.keys.sorted() {
                let expandedKey = try VariableTemplate.expand(key, using: values, missing: policy)
                guard environment[expandedKey] == nil else {
                    throw VariableTemplateError.duplicateEnvironmentKey(name: expandedKey)
                }
                if let value = action.environment[key] {
                    environment[expandedKey] = try VariableTemplate.expand(value, using: values, missing: policy)
                }
            }
            return .runShell(
                .init(
                    command: try VariableTemplate.expand(action.command, using: values, missing: policy),
                    shell: try VariableTemplate.expand(action.shell, using: values, missing: policy),
                    workingDirectory: try action.workingDirectory.map {
                        try VariableTemplate.expand($0, using: values, missing: policy)
                    },
                    environment: environment,
                    timeout: action.timeout
                )
            )
        }
    }
}

public typealias ClickAction = WorkflowStep.ClickAction
public typealias TypeTextAction = WorkflowStep.TypeTextAction
public typealias ShortcutAction = WorkflowStep.ShortcutAction
public typealias WaitAction = WorkflowStep.WaitAction
public typealias OpenAppAction = WorkflowStep.OpenAppAction
public typealias WaitForElementAction = WorkflowStep.WaitForElementAction
public typealias AssertElementAction = WorkflowStep.AssertElementAction
public typealias RunShellAction = WorkflowStep.RunShellAction
