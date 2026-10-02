import Foundation
import XCTest
@testable import MacTapeCore

final class WorkflowCodingTests: XCTestCase {
    func testAllStepActionsRoundTripThroughCanonicalJSON() throws {
        let workflow = makeWorkflow()
        let codec = WorkflowCodec()

        let first = try codec.encode(workflow)
        let second = try codec.encode(workflow)
        let decoded = try codec.decode(first)
        let json = try XCTUnwrap(String(data: first, encoding: .utf8))

        XCTAssertEqual(first, second)
        XCTAssertEqual(decoded, workflow)
        XCTAssertTrue(json.hasSuffix("\n"))
        XCTAssertTrue(json.contains(#""formatVersion" : 1"#))
        XCTAssertTrue(json.contains(#""type" : "click""#))
        XCTAssertTrue(json.contains(#""type" : "typeText""#))
        XCTAssertTrue(json.contains(#""type" : "shortcut""#))
        XCTAssertTrue(json.contains(#""type" : "wait""#))
        XCTAssertTrue(json.contains(#""type" : "openApp""#))
        XCTAssertTrue(json.contains(#""type" : "waitForElement""#))
        XCTAssertTrue(json.contains(#""type" : "assertElement""#))
        XCTAssertTrue(json.contains(#""type" : "runShell""#))
        XCTAssertTrue(json.contains("2023-11-14T22:13:20.125Z"))
        XCTAssertTrue(json.contains("https://example.com/path"))
        XCTAssertFalse(json.contains(#""_0""#))
        XCTAssertFalse(json.contains(#"\/"#))
    }

    func testActionDecoderProvidesStableDefaultsForHandWrittenDocuments() throws {
        let decoder = JSONDecoder()

        let click = try decoder.decode(
            WorkflowStep.Action.self,
            from: Data(#"{"type":"click","selector":{"matchStrategy":"exact"}}"#.utf8)
        )
        let openApp = try decoder.decode(
            WorkflowStep.Action.self,
            from: Data(#"{"type":"openApp","bundleIdentifier":"com.apple.TextEdit"}"#.utf8)
        )

        guard case let .click(clickAction) = click else {
            return XCTFail("Expected click")
        }
        XCTAssertEqual(clickAction.button, .left)
        XCTAssertEqual(clickAction.clickCount, 1)

        guard case let .openApp(openAction) = openApp else {
            return XCTFail("Expected openApp")
        }
        XCTAssertEqual(openAction.arguments, [])
        XCTAssertTrue(openAction.waitUntilRunning)
        XCTAssertEqual(openAction.timeout, 10)
    }

    func testUnsupportedFormatVersionIsRejected() throws {
        var workflow = makeWorkflow()
        workflow.formatVersion = 99
        let codec = WorkflowCodec()

        XCTAssertThrowsError(try codec.encode(workflow)) { error in
            XCTAssertEqual(
                error as? WorkflowCodecError,
                .unsupportedFormatVersion(found: 99, supported: MacTapeCore.formatVersion)
            )
        }
        XCTAssertThrowsError(try codec.decode(#"{"formatVersion":99,"steps":[{"type":"futureAction"}]}"#)) { error in
            XCTAssertEqual(
                error as? WorkflowCodecError,
                .unsupportedFormatVersion(found: 99, supported: MacTapeCore.formatVersion)
            )
        }
    }

    func testLegacyV1SelectorsDecodeWithoutApplicationScopeOrExplicitStrategy() throws {
        let selector = try JSONDecoder().decode(
            ElementSelector.self,
            from: Data(#"{"role":"AXButton","title":"Save"}"#.utf8)
        )
        XCTAssertNil(selector.bundleIdentifier)
        XCTAssertEqual(selector.matchStrategy, .exact)
        XCTAssertEqual(selector.role, "AXButton")
        XCTAssertEqual(selector.title, "Save")
        XCTAssertFalse(selector.isEmpty)
    }

    func testApplicationScopeAndOccurrenceCannotLocateAnElementAlone() {
        XCTAssertTrue(ElementSelector().isEmpty)
        XCTAssertTrue(ElementSelector(bundleIdentifier: "com.apple.TextEdit").isEmpty)
        XCTAssertTrue(ElementSelector(index: 0).isEmpty)
        XCTAssertTrue(ElementSelector(bundleIdentifier: "com.apple.TextEdit", title: "", path: [], index: 1).isEmpty)
        XCTAssertFalse(ElementSelector(role: "AXButton").isEmpty)
        XCTAssertFalse(ElementSelector(path: [0]).isEmpty)
    }

    func testApplicationScopeRoundTripsAndDoesNotChangeFormatVersion() throws {
        let workflow = makeWorkflow()
        let codec = WorkflowCodec()
        let json = try codec.encodeToString(workflow)
        let decoded = try codec.decode(json)
        guard case let .click(click) = decoded.steps[0].action else {
            return XCTFail("Expected click")
        }
        XCTAssertEqual(click.selector.bundleIdentifier, "com.example.Editor")
        XCTAssertEqual(decoded.formatVersion, 1)
        XCTAssertTrue(json.contains(#""bundleIdentifier" : "com.example.Editor""#))
    }

    func testLegacyWholeSecondDatesAndFutureUnknownFieldsAreAccepted() throws {
        let codec = WorkflowCodec()
        let json = try codec.encodeToString(makeWorkflow())
            .replacingOccurrences(of: "2023-11-14T22:13:20.125Z", with: "2023-11-14T22:13:20Z")
            .replacingOccurrences(of: #""formatVersion" : 1"#, with: #""futureOptionalMetadata": true, "formatVersion" : 1"#)
        let decoded = try codec.decode(json)
        XCTAssertEqual(decoded.createdAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testMalformedRequiredFieldsUnknownActionsAndStrategiesAreRejected() throws {
        let codec = WorkflowCodec()
        let json = try codec.encodeToString(makeWorkflow())
        XCTAssertThrowsError(try codec.decode(#"{"name":"Missing version"}"#))
        XCTAssertThrowsError(try codec.decode(json.replacingOccurrences(of: #""type" : "click""#, with: #""type" : "unknown""#)))
        XCTAssertThrowsError(try codec.decode(json.replacingOccurrences(of: #""matchStrategy" : "contains""#, with: #""matchStrategy" : "fuzzy""#)))
        XCTAssertThrowsError(try codec.decode(json.replacingOccurrences(of: "2023-11-14T22:13:20.125Z", with: "not-a-date")))
    }

    func testOversizedDocumentsAreRejectedBeforeParsing() {
        let count = WorkflowCodec.maximumDocumentBytes + 1
        XCTAssertThrowsError(try WorkflowCodec().decode(Data(repeating: 0x20, count: count))) { error in
            XCTAssertEqual(
                error as? WorkflowCodecError,
                .documentTooLarge(bytes: count, maximum: WorkflowCodec.maximumDocumentBytes)
            )
        }
    }

    func testInvalidDatesCannotBeWritten() {
        var workflow = makeWorkflow()
        workflow.createdAt = Date(timeIntervalSince1970: .nan)
        XCTAssertThrowsError(try WorkflowCodec().encode(workflow)) { error in
            XCTAssertEqual(error as? WorkflowCodecError, .invalidDate(field: "createdAt"))
        }
        workflow.createdAt = Date(timeIntervalSince1970: 1)
        workflow.updatedAt = Date(timeIntervalSince1970: .infinity)
        XCTAssertThrowsError(try WorkflowCodec().encode(workflow)) { error in
            XCTAssertEqual(error as? WorkflowCodecError, .invalidDate(field: "updatedAt"))
        }
    }

    func testRunRecordsAreCodableHashableAndDoNotPersistVariableValues() throws {
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let stepID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let diagnostic = Diagnostic(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            timestamp: startedAt,
            severity: .error,
            code: "AX.permission",
            message: "Accessibility permission is required",
            stepID: stepID,
            context: ["app": "TextEdit"]
        )
        let step = StepRunRecord(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            stepID: stepID,
            stepIndex: 2,
            actionKind: .click,
            startedAt: startedAt,
            finishedAt: startedAt.addingTimeInterval(1.5),
            status: .failed,
            diagnostics: [diagnostic]
        )
        let run = RunRecord(
            id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
            workflowID: makeWorkflow().id,
            workflowName: "Demo",
            startedAt: startedAt,
            finishedAt: startedAt.addingTimeInterval(2),
            status: .failed,
            suppliedVariables: ["password", "name"],
            steps: [step],
            diagnostics: [diagnostic]
        )

        let data = try JSONEncoder().encode(run)
        let decoded = try JSONDecoder().decode(RunRecord.self, from: data)

        XCTAssertEqual(decoded, run)
        XCTAssertEqual(run.suppliedVariables, ["name", "password"])
        XCTAssertEqual(run.duration, 2)
        XCTAssertEqual(step.duration, 1.5)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("hunter2"))
        assertProtocolConformance(run)
        assertProtocolConformance(diagnostic)
    }

    private func assertProtocolConformance<T: Codable & Hashable & Sendable>(_: T) {}

    private func makeWorkflow() -> Workflow {
        let selector = ElementSelector(
            bundleIdentifier: "com.example.Editor",
            role: "AXButton",
            subrole: "AXCloseButton",
            identifier: "save-button",
            title: "Save",
            value: "https://example.com/path",
            accessibilityDescription: "Save document",
            path: [0, 2, 1],
            index: 0,
            matchStrategy: .contains
        )
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000.125)

        return Workflow(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Every action",
            summary: "A complete codec fixture",
            createdAt: createdAt,
            updatedAt: createdAt.addingTimeInterval(2),
            variables: [
                WorkflowVariable(
                    name: "name",
                    defaultValue: "MacTape",
                    summary: "Display name",
                    isRequired: true
                ),
                WorkflowVariable(name: "password", summary: "Runtime secret", isSecret: true),
            ],
            steps: [
                .click(
                    id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
                    selector: selector,
                    button: .right,
                    clickCount: 2
                ),
                .typeText(
                    id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
                    text: "Hello {{ name }}",
                    selector: selector,
                    clearExisting: true,
                    typingDelay: 0.03
                ),
                .shortcut(
                    id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
                    key: "s",
                    modifiers: [.shift, .command]
                ),
                .wait(
                    id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!,
                    duration: 0.5
                ),
                .openApp(
                    id: UUID(uuidString: "10000000-0000-0000-0000-000000000005")!,
                    bundleIdentifier: "com.apple.TextEdit",
                    arguments: ["--new"],
                    timeout: 12
                ),
                .waitForElement(
                    id: UUID(uuidString: "10000000-0000-0000-0000-000000000006")!,
                    selector: selector,
                    timeout: 8,
                    pollingInterval: 0.1
                ),
                .assertElement(
                    id: UUID(uuidString: "10000000-0000-0000-0000-000000000007")!,
                    selector: selector,
                    assertion: .valueContains("ready"),
                    timeout: 2
                ),
                .runShell(
                    id: UUID(uuidString: "10000000-0000-0000-0000-000000000008")!,
                    command: "echo {{ name }}",
                    workingDirectory: "/tmp",
                    environment: ["LANG": "en_US.UTF-8"],
                    timeout: 5,
                    note: "Local command",
                    isEnabled: false
                ),
            ]
        )
    }
}
