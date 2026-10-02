import Foundation
import XCTest
@testable import MacTapeCore

final class VariableTemplateTests: XCTestCase {
    func testExpansionSupportsWhitespaceUnicodeAndRepeatedTokens() throws {
        let result = try VariableTemplate.expand(
            "你好，{{ name }} / {{name}} — {{emoji}}",
            using: ["name": "MacTape", "emoji": "🎬"]
        )

        XCTAssertEqual(result, "你好，MacTape / MacTape — 🎬")
    }

    func testEscapedOpeningTokenRemainsLiteral() throws {
        let result = try VariableTemplate.expand(
            #"Keep \{{ name }}; expand {{ name }}"#,
            using: ["name": "Ada"]
        )

        XCTAssertEqual(result, "Keep {{ name }}; expand Ada")
    }

    func testMissingVariablePolicies() throws {
        let template = "before {{ missing }} after"

        XCTAssertThrowsError(try VariableTemplate.expand(template, using: [:])) { error in
            XCTAssertEqual(error as? VariableTemplateError, .missingValue(name: "missing"))
        }
        XCTAssertEqual(
            try VariableTemplate.expand(template, using: [:], missing: .preserve),
            template
        )
        XCTAssertEqual(
            try VariableTemplate.expand(template, using: [:], missing: .empty),
            "before  after"
        )
    }

    func testMalformedTokensHavePreciseErrors() {
        XCTAssertThrowsError(try VariableTemplate.expand("x {{ name", using: [:])) { error in
            XCTAssertEqual(error as? VariableTemplateError, .unclosedPlaceholder(offset: 2))
        }
        XCTAssertThrowsError(try VariableTemplate.expand("{{   }}", using: [:])) { error in
            XCTAssertEqual(error as? VariableTemplateError, .emptyPlaceholder(offset: 0))
        }
        XCTAssertThrowsError(try VariableTemplate.expand("{{ a {{ b }}", using: [:])) { error in
            XCTAssertEqual(
                error as? VariableTemplateError,
                .invalidPlaceholder(name: "a {{ b", offset: 0)
            )
        }
    }

    func testResolverAppliesDefaultsOverridesOptionalValuesAndTransitiveReferences() throws {
        let resolver = WorkflowVariableResolver(
            definitions: [
                .init(name: "first", defaultValue: "Ada"),
                .init(name: "greeting", defaultValue: "Hello {{ first }}"),
                .init(name: "message", defaultValue: "{{ greeting }}!"),
                .init(name: "optional", isRequired: false),
            ]
        )

        let defaults = try resolver.resolve()
        let overrides = try resolver.resolve(overrides: ["first": "Grace", "extra": "value"])

        XCTAssertEqual(defaults["message"], "Hello Ada!")
        XCTAssertEqual(defaults["optional"], "")
        XCTAssertEqual(overrides["message"], "Hello Grace!")
        XCTAssertEqual(overrides["extra"], "value")
    }

    func testResolverRejectsMissingDuplicateInvalidAndCyclicDefinitions() {
        XCTAssertThrowsError(
            try WorkflowVariableResolver(definitions: [.init(name: "required")]).resolve()
        ) { error in
            XCTAssertEqual(error as? VariableTemplateError, .missingValue(name: "required"))
        }

        XCTAssertThrowsError(
            try WorkflowVariableResolver(
                definitions: [
                    .init(name: "same", defaultValue: "a"),
                    .init(name: " same ", defaultValue: "b"),
                ]
            ).resolve()
        ) { error in
            XCTAssertEqual(error as? VariableTemplateError, .duplicateDefinition(name: "same"))
        }

        XCTAssertThrowsError(
            try WorkflowVariableResolver(definitions: [.init(name: "  ", defaultValue: "a")]).resolve()
        ) { error in
            XCTAssertEqual(
                error as? VariableTemplateError,
                .invalidPlaceholder(name: "  ", offset: 0)
            )
        }

        XCTAssertThrowsError(
            try WorkflowVariableResolver(
                definitions: [
                    .init(name: "a", defaultValue: "{{ b }}"),
                    .init(name: "b", defaultValue: "{{ a }}"),
                ]
            ).resolve()
        ) { error in
            XCTAssertEqual(
                error as? VariableTemplateError,
                .cyclicReference(path: ["a", "b", "a"])
            )
        }
    }

    func testRuntimeOverridesRemainLiteralIncludingPasswordsWithTemplateSyntax() throws {
        let secret = #"password-{{ undefined }}-\{{ literal }}"#
        let resolver = WorkflowVariableResolver(definitions: [
            .init(name: "password", isSecret: true),
            .init(name: "message", defaultValue: "Use {{ password }}"),
        ])
        let values = try resolver.resolve(overrides: ["password": secret])
        XCTAssertEqual(values["password"], secret)
        XCTAssertEqual(values["message"], "Use \(secret)")
        XCTAssertEqual(try VariableTemplate.expand("{{ message }}", using: values), "Use \(secret)")
    }

    func testRuntimeOverridesCanBreakDefaultCyclesAndNormalizeNames() throws {
        let resolver = WorkflowVariableResolver(definitions: [
            .init(name: "a", defaultValue: "{{ b }}"),
            .init(name: " b ", defaultValue: "{{ a }}"),
        ])
        XCTAssertEqual(try resolver.resolve(overrides: [" b ": "literal"]), ["a": "literal", "b": "literal"])
        XCTAssertThrowsError(try resolver.resolve(overrides: ["b": "one", " b ": "two"])) { error in
            XCTAssertEqual(error as? VariableTemplateError, .duplicateDefinition(name: "b"))
        }
    }

    func testOversizedTemplateExpansionFailsBeforeUnboundedAllocation() {
        let limit = VariableTemplate.maximumExpandedBytes
        let value = String(repeating: "x", count: limit)
        XCTAssertThrowsError(try VariableTemplate.expand("{{ value }}x", using: ["value": value])) { error in
            XCTAssertEqual(error as? VariableTemplateError, .expansionTooLarge(maximumBytes: limit))
        }
        XCTAssertThrowsError(try VariableTemplate.expand(value + "x", using: [:])) { error in
            XCTAssertEqual(error as? VariableTemplateError, .expansionTooLarge(maximumBytes: limit))
        }
    }

    func testDeepReferencesAndExcessiveVariableCountsFailCleanly() {
        let definitions: [WorkflowVariable] = (0...WorkflowVariableResolver.maximumReferenceDepth).map {
            .init(name: String(format: "v%03d", $0), defaultValue: "{{ \(String(format: "v%03d", $0 + 1)) }}")
        } + [.init(name: String(format: "v%03d", WorkflowVariableResolver.maximumReferenceDepth + 1), defaultValue: "end")]
        XCTAssertThrowsError(try WorkflowVariableResolver(definitions: definitions).resolve()) { error in
            XCTAssertEqual(
                error as? VariableTemplateError,
                .referenceDepthExceeded(maximumDepth: WorkflowVariableResolver.maximumReferenceDepth)
            )
        }

        let tooMany = (0...WorkflowVariableResolver.maximumVariables).map {
            WorkflowVariable(name: "v\($0)", defaultValue: "")
        }
        XCTAssertThrowsError(try WorkflowVariableResolver(definitions: tooMany).resolve()) { error in
            XCTAssertEqual(error as? VariableTemplateError, .tooManyVariables(maximum: WorkflowVariableResolver.maximumVariables))
        }
    }

    func testUnicodeErrorOffsetsRemainCharacterBased() {
        XCTAssertThrowsError(try VariableTemplate.expand("🎬中 {{ ok }} {{", using: ["ok": "yes"])) { error in
            XCTAssertEqual(error as? VariableTemplateError, .unclosedPlaceholder(offset: 12))
        }
    }

    func testExpandingEnvironmentKeysCannotSilentlyOverwriteAnotherEntry() {
        let workflow = Workflow(name: "Collision", steps: [
            .runShell(command: "true", environment: ["TARGET_{{ suffix }}": "a", "TARGET_APP": "b"]),
        ])
        XCTAssertThrowsError(try workflow.expandingVariables(overrides: ["suffix": "APP"])) { error in
            XCTAssertEqual(error as? VariableTemplateError, .duplicateEnvironmentKey(name: "TARGET_APP"))
        }
    }

    func testWorkflowExpansionCoversEveryStringBearingActionField() throws {
        let selector = ElementSelector(
            bundleIdentifier: "com.example.{{ bundle }}",
            role: "AX{{ role }}",
            identifier: "{{ id }}",
            title: "Open {{ name }}",
            value: "{{ value }}",
            accessibilityDescription: "For {{ name }}"
        )
        let workflow = Workflow(
            name: "Run {{ name }}",
            summary: "For {{ name }}",
            variables: [
                .init(name: "name", defaultValue: "Notes"),
                .init(name: "role", defaultValue: "Button"),
                .init(name: "id", defaultValue: "open-button"),
                .init(name: "value", defaultValue: "ready"),
            ],
            steps: [
                .click(selector: selector, note: "Click {{ name }}"),
                .typeText(text: "Hello {{ name }}", selector: selector),
                .shortcut(key: "{{ key }}"),
                .wait(duration: 1),
                .openApp(bundleIdentifier: "com.example.{{ bundle }}", arguments: ["{{ arg }}"]),
                .waitForElement(selector: selector),
                .assertElement(selector: selector, assertion: .valueEquals("{{ value }}")),
                .runShell(
                    command: "echo {{ name }}",
                    shell: "{{ shell }}",
                    workingDirectory: "/tmp/{{ folder }}",
                    environment: ["TARGET_{{ suffix }}": "{{ name }}"]
                ),
            ]
        )
        let expanded = try workflow.expandingVariables(
            overrides: [
                "key": "k",
                "bundle": "Notes",
                "arg": "new",
                "shell": "/bin/zsh",
                "folder": "notes",
                "suffix": "APP",
            ]
        )

        XCTAssertEqual(expanded.name, "Run Notes")
        XCTAssertEqual(expanded.summary, "For Notes")
        XCTAssertEqual(expanded.steps[0].note, "Click Notes")

        guard case let .click(click) = expanded.steps[0].action else {
            return XCTFail("Expected click")
        }
        XCTAssertEqual(click.selector.role, "AXButton")
        XCTAssertEqual(click.selector.identifier, "open-button")
        XCTAssertEqual(click.selector.bundleIdentifier, "com.example.Notes")

        guard case let .typeText(typeText) = expanded.steps[1].action else {
            return XCTFail("Expected typeText")
        }
        XCTAssertEqual(typeText.text, "Hello Notes")
        XCTAssertEqual(typeText.selector?.title, "Open Notes")

        guard case let .shortcut(shortcut) = expanded.steps[2].action else {
            return XCTFail("Expected shortcut")
        }
        XCTAssertEqual(shortcut.key, "k")

        guard case let .openApp(openApp) = expanded.steps[4].action else {
            return XCTFail("Expected openApp")
        }
        XCTAssertEqual(openApp.bundleIdentifier, "com.example.Notes")
        XCTAssertEqual(openApp.arguments, ["new"])

        guard case let .assertElement(assertion) = expanded.steps[6].action else {
            return XCTFail("Expected assertElement")
        }
        XCTAssertEqual(assertion.assertion, .valueEquals("ready"))

        guard case let .runShell(shell) = expanded.steps[7].action else {
            return XCTFail("Expected runShell")
        }
        XCTAssertEqual(shell.command, "echo Notes")
        XCTAssertEqual(shell.shell, "/bin/zsh")
        XCTAssertEqual(shell.workingDirectory, "/tmp/notes")
        XCTAssertEqual(shell.environment, ["TARGET_APP": "Notes"])
    }
}
