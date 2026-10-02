import Darwin
import Foundation
import MacTapeCore

@main
struct MacTapeCLI {
    static func main() async {
        do {
            let status = try await run(Array(CommandLine.arguments.dropFirst()))
            Darwin.exit(status)
        } catch {
            FileHandle.standardError.write(Data("mactape: \(error.localizedDescription)\n".utf8))
            Darwin.exit(1)
        }
    }

    private static func run(_ arguments: [String]) async throws -> Int32 {
        guard let command = arguments.first else {
            printHelp()
            return 0
        }

        switch command {
        case "help", "--help", "-h":
            printHelp()
            return 0
        case "version", "--version", "-v":
            print("mactape \(MacTapeCore.productVersion) (workflow format \(MacTapeCore.formatVersion))")
            return 0
        case "validate":
            return try validate(arguments: Array(arguments.dropFirst()))
        case "inspect":
            return try inspect(arguments: Array(arguments.dropFirst()))
        case "format":
            return try format(arguments: Array(arguments.dropFirst()))
        case "list":
            return try await list(arguments: Array(arguments.dropFirst()))
        default:
            throw CLIError.unknownCommand(command)
        }
    }

    private static func validate(arguments: [String]) throws -> Int32 {
        guard let path = arguments.first else { throw CLIError.missingPath("validate") }
        try checkArguments(arguments, allowedFlags: ["--json"])
        let workflow = try readWorkflow(at: path)
        let findings = validate(workflow)

        if arguments.contains("--json") {
            let report = ValidationReport(
                path: URL(fileURLWithPath: path).standardizedFileURL.path,
                workflowID: workflow.id,
                valid: !findings.contains { $0.severity == .error },
                findings: findings
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            print(String(decoding: try encoder.encode(report), as: UTF8.self))
        } else {
            print("\(workflow.name) — \(workflow.steps.count) steps")
            if findings.isEmpty {
                print("✓ Valid MacTape workflow")
            } else {
                for finding in findings {
                    let prefix = finding.severity == .error ? "✗" : "!"
                    let location = finding.step.map { " step \($0 + 1):" } ?? ":"
                    print("\(prefix)\(location) \(finding.message)")
                }
            }
        }

        return findings.contains { $0.severity == .error } ? 2 : 0
    }

    private static func inspect(arguments: [String]) throws -> Int32 {
        guard let path = arguments.first else { throw CLIError.missingPath("inspect") }
        try checkArguments(arguments, allowedFlags: [])
        let workflow = try readWorkflow(at: path)

        print("\(workflow.name)")
        if !workflow.summary.isEmpty { print("  \(workflow.summary)") }
        print("  id       \(workflow.id.uuidString.lowercased())")
        print("  format   \(workflow.formatVersion)")
        print("  steps    \(workflow.enabledSteps.count) enabled / \(workflow.steps.count) total")
        print("  inputs   \(workflow.variables.count)")
        print("")

        for (index, step) in workflow.steps.enumerated() {
            let state = step.isEnabled ? " " : "○"
            let kind = step.kind.rawValue.padding(toLength: 16, withPad: " ", startingAt: 0)
            print("\(state) \(String(format: "%2d", index + 1))  \(kind) \(stepSummary(step))")
        }
        return 0
    }

    private static func format(arguments: [String]) throws -> Int32 {
        guard let path = arguments.first else { throw CLIError.missingPath("format") }
        try checkArguments(arguments, allowedFlags: ["--check"])
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let codec = WorkflowCodec()
        let workflow = try codec.decode(Data(contentsOf: url))
        let canonical = try codec.encode(workflow)

        if arguments.contains("--check") {
            let existing = try Data(contentsOf: url)
            if existing == canonical {
                print("✓ Already canonical: \(url.path)")
                return 0
            }
            print("! Formatting differs: \(url.path)")
            return 3
        }

        try canonical.write(to: url, options: .atomic)
        print("✓ Formatted \(url.path)")
        return 0
    }

    private static func list(arguments: [String]) async throws -> Int32 {
        guard arguments.isEmpty || (arguments.count == 2 && arguments[0] == "--directory") else {
            throw CLIError.invalidArguments("list accepts only --directory <path>")
        }
        let directory: URL
        if let index = arguments.firstIndex(of: "--directory") {
            guard arguments.indices.contains(index + 1) else { throw CLIError.missingOptionValue("--directory") }
            directory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        } else {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            directory = support
                .appendingPathComponent("MacTape", isDirectory: true)
                .appendingPathComponent("Workflows", isDirectory: true)
        }

        let library = try await WorkflowStore(directory: directory).scan()
        let workflows = library.workflows
        for issue in library.issues {
            FileHandle.standardError.write(Data("warning: \(issue.fileName): \(issue.reason)\n".utf8))
        }
        if workflows.isEmpty {
            print("No workflows in \(directory.path)")
            return 0
        }
        for workflow in workflows {
            print("\(workflow.id.uuidString.lowercased())\t\(workflow.enabledSteps.count) steps\t\(workflow.name)")
        }
        return 0
    }

    private static func readWorkflow(at path: String) throws -> Workflow {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        return try WorkflowCodec().decode(Data(contentsOf: url))
    }

    private static func checkArguments(_ arguments: [String], allowedFlags: Set<String>) throws {
        guard let path = arguments.first, !path.hasPrefix("--"),
              arguments.dropFirst().allSatisfy({ allowedFlags.contains($0) }),
              Set(arguments.dropFirst()).count == arguments.count - 1 else {
            throw CLIError.invalidArguments("unexpected or repeated option; run 'mactape help'")
        }
    }

    private static func validate(_ workflow: Workflow) -> [ValidationFinding] {
        var findings: [ValidationFinding] = []
        if workflow.formatVersion > MacTapeCore.formatVersion {
            findings.append(.init(severity: .error, message: "Workflow format is newer than this build supports."))
        }
        if workflow.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            findings.append(.init(severity: .error, message: "Workflow name is empty."))
        }
        if workflow.steps.isEmpty {
            findings.append(.init(severity: .warning, message: "Workflow contains no steps."))
        }

        let variableNames = Set(workflow.variables.map(\.name))
        if variableNames.count != workflow.variables.count {
            findings.append(.init(severity: .error, message: "Variable names must be unique."))
        }

        if Set(workflow.steps.map(\.id)).count != workflow.steps.count {
            findings.append(.init(severity: .error, message: "Step IDs must be unique."))
        }

        // Structural validation does not grant execution authority. An otherwise
        // valid shell step remains a warning here and blocked in the runner.
        for finding in SafetyValidator().validate(workflow).findings {
            let severity: ValidationFinding.Severity = finding.code == "shell-not-authorized"
                ? .warning : (finding.severity == .error ? .error : .warning)
            let stepIndex = finding.stepID.flatMap { id in workflow.steps.firstIndex { $0.id == id } }
            findings.append(.init(severity: severity, step: stepIndex, message: finding.message))
        }

        // Required inputs are expected at run time; every other expansion error
        // indicates a broken document. Never print expanded input values.
        do {
            _ = try workflow.expandingVariables()
        } catch VariableTemplateError.missingValue {
            findings.append(.init(severity: .warning, message: "This workflow needs variable values at run time."))
        } catch {
            findings.append(.init(severity: .error, message: "Variable definitions or placeholders are invalid."))
        }
        return findings
    }

    private static func stepSummary(_ step: WorkflowStep) -> String {
        switch step.action {
        case let .click(action):
            action.selector.title ?? action.selector.identifier ?? action.selector.role ?? "element"
        case let .typeText(action):
            action.text.contains("{{") ? action.text : "\(action.text.prefix(32))"
        case let .shortcut(action):
            (action.modifiers.map(\.rawValue) + [action.key.uppercased()]).joined(separator: "+")
        case let .wait(action):
            "\(action.duration)s"
        case let .openApp(action):
            action.bundleIdentifier
        case let .waitForElement(action):
            action.selector.title ?? action.selector.identifier ?? "element"
        case let .assertElement(action):
            action.selector.title ?? action.selector.identifier ?? "element"
        case let .runShell(action):
            String(action.command.prefix(48))
        }
    }

    private static func printHelp() {
        print(
            """
            MacTape \(MacTapeCore.productVersion) — readable macOS workflow automation

            USAGE
              mactape validate <workflow.mactape> [--json]
              mactape inspect  <workflow.mactape>
              mactape format   <workflow.mactape> [--check]
              mactape list     [--directory <path>]
              mactape version

            Live replay is intentionally initiated from the MacTape app, where
            every step and permission is visible before execution.
            """
        )
    }
}

private enum CLIError: LocalizedError {
    case unknownCommand(String)
    case missingPath(String)
    case missingOptionValue(String)
    case invalidArguments(String)

    var errorDescription: String? {
        switch self {
        case let .unknownCommand(command):
            "unknown command '\(command)'. Run 'mactape help'."
        case let .missingPath(command):
            "'\(command)' requires a .mactape file path."
        case let .missingOptionValue(option):
            "\(option) requires a value."
        case let .invalidArguments(message):
            message
        }
    }
}

private struct ValidationReport: Codable {
    let path: String
    let workflowID: UUID
    let valid: Bool
    let findings: [ValidationFinding]
}

private struct ValidationFinding: Codable {
    enum Severity: String, Codable {
        case warning
        case error
    }

    let severity: Severity
    var step: Int?
    let message: String

    init(severity: Severity, step: Int? = nil, message: String) {
        self.severity = severity
        self.step = step
        self.message = message
    }
}
