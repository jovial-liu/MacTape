import CoreGraphics
import Foundation
import XCTest
@testable import MacTapeCore

final class EngineSafetyTests: XCTestCase {
    func testShellApprovalIsBoundToAllExpandedPayloadFields() {
        let step = WorkflowStep.runShell(command: "exit 0", workingDirectory: "/tmp", environment: ["A": "B"], timeout: 2)
        let approval = ShellExecutionAuthorization.explicitlyApproving(steps: [step])
        XCTAssertTrue(approval.permits(step))
        XCTAssertFalse(ShellExecutionAuthorization.denied.permits(step))
        for field in 0..<6 {
            var changed = step
            guard case var .runShell(action) = changed.action else { return XCTFail() }
            switch field {
            case 0: action.command = "exit 1"
            case 1: action.shell = "/bin/sh"
            case 2: action.workingDirectory = "/"
            case 3: action.environment = ["A": "C"]
            case 4: action.timeout = 3
            default: changed.id = UUID()
            }
            changed.action = .runShell(action)
            XCTAssertFalse(approval.permits(changed), "Changed field \(field) must revoke approval")
        }
    }

    func testShellStructureIsValidatedEvenWithoutApproval() {
        let workflow = Workflow(name: "Invalid shell", steps: [.runShell(command: "", shell: "sh", workingDirectory: "relative", timeout: -1)])
        let codes = Set(SafetyValidator().validate(workflow).errors.map(\.code))
        XCTAssertTrue(codes.isSuperset(of: ["shell-not-authorized", "empty-shell-command", "relative-shell-path", "relative-working-directory", "invalid-timeout"]))
        let previewCodes = Set(SafetyValidator().validate(workflow, requiresShellAuthorization: false).errors.map(\.code))
        XCTAssertFalse(previewCodes.contains("shell-not-authorized"))
        XCTAssertTrue(previewCodes.contains("empty-shell-command"))
    }

    func testDuplicateIdentityAndInvalidSelectorAreRejected() {
        let step = WorkflowStep.click(selector: ElementSelector(role: "AXButton", path: [-1], index: -2))
        let report = SafetyValidator().validate(Workflow(name: "Invalid", steps: [step, step]))
        XCTAssertTrue(report.errors.contains { $0.code == "duplicate-step-id" })
        XCTAssertTrue(report.errors.contains { $0.code == "negative-selector-index" })
    }

    func testAmbiguousCandidatesFailUnlessOccurrenceIsExplicit() throws {
        XCTAssertThrowsError(try SelectorCandidateSelection.selectIndex(scores: [0.9, 0.87], requestedIndex: nil, minimumScore: 0.6, ambiguityMargin: 0.05)) { error in
            XCTAssertEqual(error as? SelectorResolutionError, .ambiguousMatch)
        }
        XCTAssertEqual(try SelectorCandidateSelection.selectIndex(scores: [0.9, 0.9], requestedIndex: 1, minimumScore: 0.6, ambiguityMargin: 0.05), 1)
        XCTAssertEqual(try SelectorCandidateSelection.selectIndex(scores: [0.9, 0.7], requestedIndex: nil, minimumScore: 0.6, ambiguityMargin: 0.05), 0)
        XCTAssertThrowsError(try SelectorCandidateSelection.selectIndex(scores: [0.9], requestedIndex: -1, minimumScore: 0.6, ambiguityMargin: 0.05))
        XCTAssertThrowsError(try SelectorCandidateSelection.selectIndex(scores: [0.4], requestedIndex: nil, minimumScore: 0.6, ambiguityMargin: 0.05))
    }

    func testSnapshotPreservesApplicationAndOmitsIncompletePathAndValue() {
        let snapshot = AXElementSnapshot(processIdentifier: 123, bundleIdentifier: "com.example.App", role: "AXButton", ancestors: [AXAncestorComponent(childIndex: nil), AXAncestorComponent(childIndex: 2)])
        XCTAssertEqual(snapshot.elementSelector.bundleIdentifier, "com.example.App")
        XCTAssertNil(snapshot.elementSelector.path)
        XCTAssertNil(snapshot.elementSelector.value)
    }

    func testRecordedHardwareKeysRoundTripAndOrdinaryTypingIsIgnored() throws {
        XCTAssertEqual(try ShortcutKey.keyCode(for: "keycode:123"), 123)
        XCTAssertFalse(ShortcutKey.isSupported("keycode:128"))
        XCTAssertFalse(ShortcutKey.isSupported("keycode:-1"))
        XCTAssertFalse(RecorderEventPolicy.recordsShortcut(flags: [], allowsOptionOnly: false))
        XCTAssertFalse(RecorderEventPolicy.recordsShortcut(flags: [.maskShift], allowsOptionOnly: false))
        XCTAssertFalse(RecorderEventPolicy.recordsShortcut(flags: [.maskAlternate], allowsOptionOnly: false))
        XCTAssertTrue(RecorderEventPolicy.recordsShortcut(flags: [.maskCommand, .maskShift], allowsOptionOnly: false))
        XCTAssertTrue(RecorderEventPolicy.recordsShortcut(flags: [.maskControl], allowsOptionOnly: false))
    }
}
