import Foundation
import MacTapeCore
import SwiftUI

enum SidebarSelection: Hashable {
    case welcome
    case templates
    case workflow(UUID)
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum TapeAccent: String, CaseIterable, Codable, Identifiable, Sendable {
    case indigo
    case cyan
    case mint
    case orange
    case pink

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .indigo: .indigo
        case .cyan: .cyan
        case .mint: .mint
        case .orange: .orange
        case .pink: .pink
        }
    }
}

struct EditableWorkflow: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var summary: String
    var createdAt: Date
    var updatedAt: Date
    var accent: TapeAccent
    var steps: [EditableStep]
    var variables: [WorkflowVariableDraft]
    var sourceTemplateID: String?

    init(
        id: UUID = UUID(),
        name: String,
        summary: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        accent: TapeAccent = .indigo,
        steps: [EditableStep] = [],
        variables: [WorkflowVariableDraft] = [],
        sourceTemplateID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.accent = accent
        self.steps = steps
        self.variables = variables
        self.sourceTemplateID = sourceTemplateID
    }

    var enabledStepCount: Int {
        steps.lazy.filter(\.isEnabled).count
    }
}

struct WorkflowVariableDraft: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var value: String
    var isSecret = false
    var isRequired = true
    var summary: String? = nil
    var hasDefault = true
}

struct EditableStep: Identifiable, Codable, Hashable, Sendable {
    enum ActionKind: String, CaseIterable, Codable, Identifiable, Sendable {
        case click
        case typeText
        case shortcut
        case wait
        case openApp
        case waitForElement
        case assertElement
        case runShell

        var id: String { rawValue }

        var title: String {
            switch self {
            case .click: "Click"
            case .typeText: "Type text"
            case .shortcut: "Keyboard shortcut"
            case .wait: "Wait"
            case .openApp: "Open app"
            case .waitForElement: "Wait for element"
            case .assertElement: "Verify element"
            case .runShell: "Run shell command"
            }
        }

        var icon: String {
            switch self {
            case .click: "cursorarrow.click.2"
            case .typeText: "keyboard"
            case .shortcut: "command"
            case .wait: "timer"
            case .openApp: "macwindow.on.rectangle"
            case .waitForElement: "eye"
            case .assertElement: "checkmark.seal"
            case .runShell: "terminal"
            }
        }

        var tint: Color {
            switch self {
            case .click: .indigo
            case .typeText: .cyan
            case .shortcut: .purple
            case .wait: .orange
            case .openApp: .blue
            case .waitForElement: .teal
            case .assertElement: .green
            case .runShell: .pink
            }
        }

        var defaultTitle: String { title }
    }

    var id: UUID
    var kind: ActionKind
    var title: String
    var note: String
    var isEnabled: Bool
    var configuration: StepConfiguration
    /// Retains advanced imported fields that the visual editor does not expose.
    var originalAction: WorkflowStep.Action? = nil

    init(
        id: UUID = UUID(),
        kind: ActionKind,
        title: String? = nil,
        note: String = "",
        isEnabled: Bool = true,
        configuration: StepConfiguration = .init()
    ) {
        self.id = id
        self.kind = kind
        self.title = title ?? kind.defaultTitle
        self.note = note
        self.isEnabled = isEnabled
        self.configuration = configuration
    }
}

struct StepConfiguration: Codable, Hashable, Sendable {
    var application: String = ""
    var selector: String = ""
    var text: String = ""
    var shortcut: String = ""
    var seconds: Double = 1
    var command: String = ""
    var timeout: Double = 10
    var redactInLogs: Bool = false
    var continueOnFailure: Bool = false
    var targetBundleIdentifier: String = ""
    var role: String = ""
    var identifier: String = ""
    var accessibilityDescription: String = ""
    var originalSelector: ElementSelector? = nil
    var clearExisting = false
    var mouseButton: MouseButton = .left
    var clickCount = 1
    var shell = "/bin/zsh"
    var workingDirectory = ""

    var compactSummary: String? {
        if !application.isEmpty { return application }
        if !selector.isEmpty { return selector }
        if !shortcut.isEmpty { return shortcut }
        if !command.isEmpty { return command }
        if !text.isEmpty { return text.count > 42 ? String(text.prefix(42)) + "…" : text }
        return nil
    }
}

struct WorkflowTemplate: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let summary: String
    let icon: String
    let accent: TapeAccent
    let useCase: String
    let steps: [EditableStep]
    let variables: [WorkflowVariableDraft]

    func instantiate() -> EditableWorkflow {
        EditableWorkflow(
            name: name,
            summary: summary,
            accent: accent,
            steps: steps.map {
                var copy = $0
                copy.id = UUID()
                return copy
            },
            variables: variables.map { WorkflowVariableDraft(name: $0.name, value: $0.value) },
            sourceTemplateID: id
        )
    }
}

extension WorkflowTemplate {
    static let builtIns: [WorkflowTemplate] = [
        .init(
            id: "finder-downloads",
            name: "Downloads, Ready",
            summary: "Open Finder and navigate to Downloads using a reviewable keyboard shortcut.",
            icon: "arrow.down.doc.fill",
            accent: .cyan,
            useCase: "Everyday Mac",
            steps: [
                .init(kind: .openApp, title: "Bring Finder forward", note: "Does not move or delete any files.", configuration: .init(application: "com.apple.finder")),
                .init(kind: .shortcut, title: "Open Downloads", note: "Finder's built-in Option–Command–L shortcut.", configuration: .init(shortcut: "⌥⌘L")),
                .init(kind: .wait, title: "Let the window settle", configuration: .init(seconds: 0.5)),
            ],
            variables: []
        ),
        .init(
            id: "textedit-draft",
            name: "A Fresh Draft",
            summary: "Create a TextEdit document and type a reusable greeting. Nothing is saved or sent.",
            icon: "doc.text.fill",
            accent: .mint,
            useCase: "Reusable inputs",
            steps: [
                .init(kind: .openApp, title: "Open TextEdit", note: "If a file-open dialog is already visible, dismiss it before running.", configuration: .init(application: "com.apple.TextEdit")),
                .init(kind: .shortcut, title: "Create a new document", configuration: .init(shortcut: "⌘N")),
                .init(kind: .wait, title: "Wait for the document", configuration: .init(seconds: 0.8)),
                .init(kind: .typeText, title: "Type your greeting", note: "This text is explicit; MacTape never records ordinary typing.", configuration: .init(text: "Hello, {{name}}!\n\nRecorded once. Reviewed before every replay.")),
            ],
            variables: [
                .init(name: "name", value: "MacTape"),
            ]
        ),
        .init(
            id: "safe-first-run",
            name: "Your First Dry Run",
            summary: "A permission-free introduction: check that Calculator is installed and preview a wait.",
            icon: "checkmark.shield.fill",
            accent: .orange,
            useCase: "Getting started",
            steps: [
                .init(kind: .openApp, title: "Check Calculator", note: "Dry Run checks installation without opening the app. Run opens it.", configuration: .init(application: "com.apple.calculator")),
                .init(kind: .wait, title: "Preview a short wait", note: "Dry Run does not actually wait. A live run waits one second.", configuration: .init(seconds: 1)),
            ],
            variables: []
        ),
    ]
}

enum RunMode: String, Codable, Sendable {
    case dryRun
    case live

    var title: String {
        switch self {
        case .dryRun: "Dry Run"
        case .live: "Run"
        }
    }
}

enum RunPhase: Equatable {
    case idle
    case recording
    case preparing(RunMode)
    case running(RunMode)
    case paused(RunMode)
    case succeeded(RunMode)
    case failed(RunMode, String)

    var isActive: Bool {
        switch self {
        case .recording, .preparing, .running, .paused: true
        default: false
        }
    }

    var mode: RunMode? {
        switch self {
        case let .preparing(mode), let .running(mode), let .paused(mode), let .succeeded(mode), let .failed(mode, _): mode
        case .idle, .recording: nil
        }
    }

    var title: String {
        switch self {
        case .idle: "Ready"
        case .recording: "Recording"
        case let .preparing(mode): "Preparing \(mode.title)"
        case let .running(mode): mode.title
        case let .paused(mode): "\(mode.title) Paused"
        case .succeeded: "Completed"
        case .failed: "Stopped"
        }
    }

    var systemImage: String {
        switch self {
        case .idle: "circle"
        case .recording: "record.circle.fill"
        case .preparing: "hourglass"
        case .running: "play.circle.fill"
        case .paused: "pause.circle.fill"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "exclamationmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .idle: .secondary
        case .recording: .red
        case .preparing: .orange
        case .running: .blue
        case .paused: .orange
        case .succeeded: .green
        case .failed: .red
        }
    }
}

struct RunLogEntry: Identifiable, Equatable {
    enum Level: String {
        case info
        case success
        case warning
        case error

        var icon: String {
            switch self {
            case .info: "circle.fill"
            case .success: "checkmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .error: "xmark.octagon.fill"
            }
        }

        var tint: Color {
            switch self {
            case .info: .secondary
            case .success: .green
            case .warning: .orange
            case .error: .red
            }
        }
    }

    let id: UUID
    let date: Date
    let level: Level
    let message: String
    let stepID: UUID?

    init(id: UUID = UUID(), date: Date = .now, level: Level, message: String, stepID: UUID? = nil) {
        self.id = id
        self.date = date
        self.level = level
        self.message = message
        self.stepID = stepID
    }
}

enum AutomationPermission: String, CaseIterable, Identifiable, Sendable {
    case accessibility
    case inputMonitoring

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibility: "Accessibility"
        case .inputMonitoring: "Input Monitoring"
        }
    }

    var detail: String {
        switch self {
        case .accessibility: "Find and interact with visible controls during a tape."
        case .inputMonitoring: "Record clicks and shortcuts only while recording is active."
        }
    }

    var icon: String {
        switch self {
        case .accessibility: "accessibility"
        case .inputMonitoring: "keyboard.badge.ellipsis"
        }
    }

    var isRequired: Bool {
        self == .accessibility || self == .inputMonitoring
    }
}

enum PermissionState: String, Sendable {
    case unknown
    case granted
    case denied

    var title: String {
        switch self {
        case .unknown: "Not checked"
        case .granted: "Allowed"
        case .denied: "Needs access"
        }
    }
}
