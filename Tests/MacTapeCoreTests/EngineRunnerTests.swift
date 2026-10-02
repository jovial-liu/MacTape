import Foundation
import XCTest
@testable import MacTapeCore

@MainActor
final class EngineRunnerTests: XCTestCase {
    func testDryRunNeverExecutesShellAndRequiresNoShellApproval() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let marker = directory.appendingPathComponent("must-not-exist")
        let workflow = Workflow(name: "Dry run", steps: [.runShell(command: "/usr/bin/touch '\(marker.path)'"), .wait(duration: 30), .shortcut(key: "keycode:0")])
        let clock = ContinuousClock()
        let start = clock.now
        let record = try await WorkflowRunner().run(workflow, options: WorkflowRunnerOptions(dryRun: true))
        XCTAssertEqual(record.status, .succeeded)
        XCTAssertEqual(record.steps.map(\.status), [.succeeded, .succeeded, .succeeded])
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertLessThan(start.duration(to: clock.now), .seconds(2))
    }

    func testExpandedVariablesInvalidateTemplateApproval() async throws {
        let workflow = Workflow(name: "Expansion", variables: [WorkflowVariable(name: "result")], steps: [.runShell(command: "exit {{ result }}")])
        let approval = ShellExecutionAuthorization.explicitlyApproving(steps: workflow.steps)
        do {
            _ = try await WorkflowRunner().run(workflow, variableValues: ["result": "0"], options: WorkflowRunnerOptions(shellAuthorization: approval))
            XCTFail("Template approval must not authorize an expanded command")
        } catch WorkflowRunnerError.safetyValidationFailed(let report) {
            XCTAssertTrue(report.errors.contains { $0.code == "shell-not-authorized" })
        }
    }

    func testShellFailureDiagnosticsDoNotContainRuntimeValues() async throws {
        let secret = "RUNTIME_SECRET_SENTINEL_59317"
        let workflow = Workflow(name: "Redaction", variables: [WorkflowVariable(name: "token", isSecret: true)], steps: [.runShell(command: ": '{{ token }}'; exit 7")])
        let expanded = try workflow.expandingVariables(overrides: ["token": secret])
        let approval = ShellExecutionAuthorization.explicitlyApproving(steps: expanded.steps)
        do {
            _ = try await WorkflowRunner().run(workflow, variableValues: ["token": secret], options: WorkflowRunnerOptions(shellAuthorization: approval))
            XCTFail("Nonzero shell exit should fail")
        } catch let failure as WorkflowRunFailure {
            XCTAssertEqual(failure.record.status, .failed)
            XCTAssertEqual(failure.record.diagnostics.first?.code, "shell-failed")
            let encoded = try JSONEncoder().encode(failure.record)
            XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains(secret))
        }
    }

    func testShellHonorsItsOwnTimeoutRatherThanDefaultTimeout() async throws {
        let workflow = Workflow(name: "Timeout", steps: [.runShell(command: "exec /bin/sleep 10", timeout: 0.05)])
        let approval = ShellExecutionAuthorization.explicitlyApproving(steps: workflow.steps)
        let clock = ContinuousClock()
        let start = clock.now
        do {
            _ = try await WorkflowRunner().run(workflow, options: WorkflowRunnerOptions(defaultStepTimeout: 30, shellAuthorization: approval))
            XCTFail("Sleep should time out")
        } catch let failure as WorkflowRunFailure {
            XCTAssertEqual(failure.record.diagnostics.first?.code, "step-timeout")
            XCTAssertLessThan(start.duration(to: clock.now), .seconds(2))
        }
    }

    func testCancellationStopsWaitAndRunnerCanBeReused() async throws {
        let runner = WorkflowRunner()
        let task = Task { try await runner.run(Workflow(name: "Wait", steps: [.wait(duration: 30), .wait(duration: 30)])) }
        while !(await runner.isRunning) { await Task.yield() }
        await runner.cancel()
        do {
            _ = try await task.value
            XCTFail("Run should cancel")
        } catch let failure as WorkflowRunFailure {
            XCTAssertEqual(failure.reason, .cancelled)
            XCTAssertEqual(failure.record.status, .cancelled)
        }
        let isRunning = await runner.isRunning
        XCTAssertFalse(isRunning)
        let record = try await runner.run(Workflow(name: "Reuse", steps: [.wait(duration: 0)]))
        XCTAssertEqual(record.status, .succeeded)
    }

    func testLiveInputWithoutExplicitAppContextFailsBeforeSendingEvents() async throws {
        for step in [WorkflowStep.shortcut(key: "a"), .typeText(text: "do not send")] {
            do {
                _ = try await WorkflowRunner().run(Workflow(name: "No app", steps: [step]))
                XCTFail("Unscoped live input must fail")
            } catch let failure as WorkflowRunFailure {
                XCTAssertEqual(failure.record.diagnostics.first?.code, "application-context-required")
            }
        }
    }
}
