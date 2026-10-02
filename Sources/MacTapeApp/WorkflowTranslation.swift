import Foundation
import MacTapeCore

extension EditableWorkflow {
    init(core: Workflow) {
        self.init(
            id: core.id, name: core.name, summary: core.summary,
            createdAt: core.createdAt, updatedAt: core.updatedAt,
            accent: TapeAccent(rawValue: UserDefaults.standard.string(forKey: "accent.\(core.id)") ?? "indigo") ?? .indigo,
            steps: core.steps.map(EditableStep.init(core:)),
            variables: core.variables.map {
                WorkflowVariableDraft(
                    name: $0.name, value: $0.defaultValue ?? "", isSecret: $0.isSecret,
                    isRequired: $0.isRequired, summary: $0.summary, hasDefault: $0.defaultValue != nil
                )
            }
        )
    }

    var coreWorkflow: Workflow {
        Workflow(
            id: id, name: name, summary: summary, createdAt: createdAt, updatedAt: updatedAt,
            variables: variables.map {
                WorkflowVariable(
                    name: $0.name, defaultValue: $0.isSecret ? nil : ($0.hasDefault ? $0.value : nil),
                    summary: $0.summary, isRequired: $0.isRequired, isSecret: $0.isSecret
                )
            },
            steps: steps.map(\.coreStep)
        )
    }
}

extension EditableStep {
    init(core: WorkflowStep) {
        let noteLines = (core.note ?? "").split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let actionKind = ActionKind(rawValue: core.kind.rawValue) ?? .wait
        self.init(
            id: core.id, kind: actionKind,
            title: noteLines.first.flatMap { $0.isEmpty ? nil : String($0) } ?? actionKind.title,
            note: noteLines.count > 1 ? String(noteLines[1]) : "",
            isEnabled: core.isEnabled
        )
        originalAction = core.action
        switch core.action {
        case let .click(value):
            configuration.setSelector(value.selector)
            configuration.mouseButton = value.button
            configuration.clickCount = value.clickCount
        case let .typeText(value):
            if let selector = value.selector { configuration.setSelector(selector) }
            configuration.text = value.text
            configuration.clearExisting = value.clearExisting
        case let .shortcut(value): configuration.shortcut = Self.shortcutLabel(value)
        case let .wait(value): configuration.seconds = value.duration
        case let .openApp(value):
            configuration.application = value.bundleIdentifier
            configuration.timeout = value.timeout
        case let .waitForElement(value):
            configuration.setSelector(value.selector)
            configuration.timeout = value.timeout
        case let .assertElement(value):
            configuration.setSelector(value.selector)
            configuration.timeout = value.timeout
        case let .runShell(value):
            configuration.command = value.command
            configuration.timeout = value.timeout
            configuration.shell = value.shell
            configuration.workingDirectory = value.workingDirectory ?? ""
        }
    }

    var coreStep: WorkflowStep {
        let action: WorkflowStep.Action
        switch kind {
        case .click:
            action = .click(.init(selector: configuration.coreSelector, button: configuration.mouseButton, clickCount: configuration.clickCount))
        case .typeText:
            var value = WorkflowStep.TypeTextAction(text: configuration.text)
            if case let .typeText(original) = originalAction { value = original }
            value.text = configuration.text
            value.selector = configuration.coreSelector.isEmpty ? nil : configuration.coreSelector
            value.clearExisting = configuration.clearExisting
            action = .typeText(value)
        case .shortcut: action = .shortcut(Self.parseShortcut(configuration.shortcut))
        case .wait: action = .wait(.init(duration: configuration.seconds))
        case .openApp:
            var value = WorkflowStep.OpenAppAction(bundleIdentifier: configuration.application)
            if case let .openApp(original) = originalAction { value = original }
            value.bundleIdentifier = configuration.application.trimmingCharacters(in: .whitespacesAndNewlines)
            value.timeout = configuration.timeout
            action = .openApp(value)
        case .waitForElement:
            var value = WorkflowStep.WaitForElementAction(selector: configuration.coreSelector)
            if case let .waitForElement(original) = originalAction { value = original }
            value.selector = configuration.coreSelector
            value.timeout = configuration.timeout
            action = .waitForElement(value)
        case .assertElement:
            var value = WorkflowStep.AssertElementAction(selector: configuration.coreSelector)
            if case let .assertElement(original) = originalAction { value = original }
            value.selector = configuration.coreSelector
            value.timeout = configuration.timeout
            action = .assertElement(value)
        case .runShell:
            var value = WorkflowStep.RunShellAction(command: configuration.command)
            if case let .runShell(original) = originalAction { value = original }
            value.command = configuration.command
            value.timeout = configuration.timeout
            value.shell = configuration.shell
            value.workingDirectory = configuration.workingDirectory.isEmpty ? nil : configuration.workingDirectory
            action = .runShell(value)
        }
        let combinedNote = note.isEmpty ? title : "\(title)\n\(note)"
        return WorkflowStep(id: id, note: combinedNote.isEmpty ? nil : combinedNote, isEnabled: isEnabled, action: action)
    }

    static func shortcutLabel(_ value: WorkflowStep.ShortcutAction) -> String {
        let symbols: [KeyModifier: String] = [.control: "⌃", .option: "⌥", .shift: "⇧", .command: "⌘", .function: "fn+"]
        return value.modifiers.map { symbols[$0] ?? "" }.joined() + value.key
    }

    static func parseShortcut(_ label: String) -> WorkflowStep.ShortcutAction {
        var key = label.trimmingCharacters(in: .whitespacesAndNewlines)
        var modifiers: [KeyModifier] = []
        let names: [(KeyModifier, [String])] = [
            (.command, ["⌘", "command+", "cmd+"]), (.option, ["⌥", "option+", "alt+"]),
            (.control, ["⌃", "control+", "ctrl+"]), (.shift, ["⇧", "shift+"]), (.function, ["fn+"]),
        ]
        for (modifier, tokens) in names {
            for token in tokens where key.range(of: token, options: .caseInsensitive) != nil {
                modifiers.append(modifier)
                key = key.replacingOccurrences(of: token, with: "", options: .caseInsensitive)
            }
        }
        return .init(key: key.trimmingCharacters(in: .whitespaces), modifiers: modifiers)
    }
}

extension StepConfiguration {
    mutating func setSelector(_ value: ElementSelector) {
        originalSelector = value
        selector = value.title ?? ""
        role = value.role ?? ""
        identifier = value.identifier ?? ""
        accessibilityDescription = value.accessibilityDescription ?? ""
        targetBundleIdentifier = value.bundleIdentifier ?? ""
    }

    var coreSelector: ElementSelector {
        var result = originalSelector ?? ElementSelector()
        result.title = selector.isEmpty ? nil : selector
        result.role = role.isEmpty ? nil : role
        result.identifier = identifier.isEmpty ? nil : identifier
        result.accessibilityDescription = accessibilityDescription.isEmpty ? nil : accessibilityDescription
        result.bundleIdentifier = targetBundleIdentifier.isEmpty ? nil : targetBundleIdentifier
        return result
    }
}
