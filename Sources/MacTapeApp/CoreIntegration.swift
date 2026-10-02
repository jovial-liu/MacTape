import AppKit
import Foundation
import MacTapeCore
import UniformTypeIdentifiers

extension AppModel {
    func loadLibraryWithCore() async {
        do {
            let store = try WorkflowStore()
            workflowStore = store
            let snapshot = try await store.scan()
            let existing = Set(workflows.map(\.id))
            workflows.append(contentsOf: snapshot.workflows.filter { !existing.contains($0.id) }.map(EditableWorkflow.init(core:)))
            persistenceMessage = "Saved on this Mac"
            if !snapshot.issues.isEmpty {
                userFacingError = "\(snapshot.issues.count) workflow file(s) could not be loaded. Valid tapes remain available; damaged originals were not changed. Inspect the Workflow Folder in Settings."
            }
        } catch { reportStorageError(error) }
    }

    func saveWorkflowWithCore(_ workflow: EditableWorkflow) {
        guard let store = workflowStore else { persistenceMessage = "Not saved — library unavailable"; return }
        let previous = storageTask
        let document = workflow.coreWorkflow
        UserDefaults.standard.set(workflow.accent.rawValue, forKey: "accent.\(workflow.id)")
        persistenceMessage = "Saving…"
        storageTask = Task { [weak self] in
            await previous?.value
            do { try await store.save(document); self?.persistenceMessage = "Saved on this Mac" }
            catch { self?.reportStorageError(error) }
        }
    }

    func deleteWorkflowWithCore(_ id: UUID) {
        guard let store = workflowStore else { return }
        let previous = storageTask
        storageTask = Task { [weak self] in
            await previous?.value
            do {
                let url = store.fileURL(for: id)
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                }
                guard let self else { return }
                self.workflows.removeAll { $0.id == id }
                if self.selectedWorkflowID == id { self.selection = .welcome; self.selectedStepID = nil }
                self.appendLog(.info, "Tape moved to Trash. Previous workflow actions were not reversed.")
            } catch { self?.reportStorageError(error) }
        }
    }

    func importWorkflow() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "mactape") ?? .json, .json]
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importWorkflow(from: url)
    }

    func importWorkflow(from url: URL) {
        guard !runPhase.isActive else { userFacingError = "Stop the current activity before importing."; return }
        Task { [weak self] in
            guard let self else { return }
            if !self.didBootstrap { await self.bootstrap() }
            guard let store = self.workflowStore else { return }
            await self.storageTask?.value
            do {
                var document = try WorkflowCodec().decode(Data(contentsOf: url))
                if self.workflows.contains(where: { $0.id == document.id }) {
                    document.id = UUID(); document.name += " (Imported Copy)"
                }
                let imported = EditableWorkflow(core: document)
                try await store.save(imported.coreWorkflow)
                self.workflows.insert(imported, at: 0)
                self.selection = .workflow(imported.id)
                self.selectedStepID = imported.steps.first?.id
                self.appendLog(.info, "Imported a tape without executing it. Review every action before running. Secret defaults are discarded.")
            } catch { self.reportStorageError(error) }
        }
    }

    func exportSelectedWorkflow() {
        guard let workflow = selectedWorkflow, let store = workflowStore else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "mactape") ?? .json]
        panel.nameFieldStringValue = workflow.name.replacingOccurrences(of: "/", with: "-") + ".mactape"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { [weak self] in
            do { try await store.export(workflow.coreWorkflow, to: url); self?.appendLog(.success, "Exported a portable tape. Review explicit text before sharing.") }
            catch { self?.reportStorageError(error) }
        }
    }

    func exportRunRecord() {
        guard let record = lastRunRecord else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "MacTape-run-\(record.id.uuidString.prefix(8)).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(record).write(to: url, options: .atomic)
        } catch { reportStorageError(error) }
    }

    func revealWorkflowFolder() {
        if let directory = workflowStore?.directory { NSWorkspace.shared.open(directory) }
    }

    private func reportStorageError(_ error: any Error) {
        persistenceMessage = "Storage needs attention"
        userFacingError = error.localizedDescription
        appendLog(.error, "Storage operation failed. Current in-memory edits were not discarded.")
    }

    func beginRecordingWithCore() {
        guard let id = selectedWorkflowID else { runPhase = .idle; return }
        refreshPermissions()
        guard AccessibilityPermission.isGranted, InputMonitoringPermission.isGranted else {
            runPhase = .idle; showsPermissionOnboarding = true
            appendLog(.warning, "Recording requires Accessibility and Input Monitoring. Editing remains available.")
            return
        }
        recordingWorkflowID = id; recordingAppIdentifier = nil; recordedInteractionCount = 0
        coreRecorder.setInteractionHandler { [weak self] event in
            Task { @MainActor in self?.appendRecordedInteraction(event) }
        }
        coreRecorder.setStateHandler { [weak self] state in
            Task { @MainActor in
                if case let .failed(message) = state {
                    self?.recordingWorkflowID = nil; self?.runPhase = .idle; self?.isStopping = false
                    self?.appendLog(.error, message)
                }
            }
        }
        do {
            try coreRecorder.start()
            appendLog(.info, "Recording clicks and Command/Control shortcuts. Ordinary typing is not captured. Stop from the menu-bar indicator.")
        } catch { recordingWorkflowID = nil; runPhase = .idle; appendLog(.error, error.localizedDescription) }
    }

    private func appendRecordedInteraction(_ event: RecordedInteraction) {
        guard runPhase == .recording, !isStopping, let id = recordingWorkflowID,
              let index = workflows.firstIndex(where: { $0.id == id }) else { return }
        var step: EditableStep
        let appID: String?
        switch event {
        case let .click(click):
            guard click.target?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            appID = click.target?.bundleIdentifier
            if let ownID = Bundle.main.bundleIdentifier, appID == ownID { return }
            if let target = click.target, !target.elementSelector.isEmpty {
                step = EditableStep(core: .click(selector: target.elementSelector, button: click.button == .right ? .right : (click.button == .other ? .middle : .left), clickCount: max(1, min(click.clickCount, 3))))
                step.title = "Click \(target.title ?? target.accessibilityDescription ?? target.role ?? "control")"
                step.note = "Review this recorded selector before replay."
            } else {
                step = EditableStep(kind: .click, title: "Unresolved click", note: "No accessible target. Add an exact selector before enabling this step.", isEnabled: false)
            }
        case let .shortcut(shortcut):
            appID = shortcut.bundleIdentifier
            guard let appID, appID != Bundle.main.bundleIdentifier else { return }
            var modifiers: [KeyModifier] = []
            if shortcut.modifiers.contains(.command) { modifiers.append(.command) }
            if shortcut.modifiers.contains(.control) { modifiers.append(.control) }
            if shortcut.modifiers.contains(.option) { modifiers.append(.option) }
            if shortcut.modifiers.contains(.shift) { modifiers.append(.shift) }
            if shortcut.modifiers.contains(.function) { modifiers.append(.function) }
            step = EditableStep(core: .shortcut(key: "keycode:\(shortcut.keyCode)", modifiers: modifiers))
            step.note = "Recorded physical key in \(appID); verify before running."
        }
        if let appID, appID != recordingAppIdentifier {
            var open = EditableStep(core: .openApp(bundleIdentifier: appID))
            open.title = "Activate \(NSRunningApplication.runningApplications(withBundleIdentifier: appID).first?.localizedName ?? appID)"
            workflows[index].steps.append(open); recordingAppIdentifier = appID
        }
        workflows[index].steps.append(step); workflows[index].updatedAt = .now
        selectedStepID = step.id; recordedInteractionCount += 1
        saveWorkflowWithCore(workflows[index])
        appendLog(step.isEnabled ? .info : .warning, "Captured \(step.kind.title.lowercased())\(step.isEnabled ? "." : "; target unresolved, step disabled.")", stepID: step.id)
        if recordedInteractionCount >= 1_000 { stop() }
    }

    func beginRunWithCore(workflow: EditableWorkflow, mode: RunMode) {
        let document = workflow.coreWorkflow
        guard mode != .live || !document.enabledSteps.contains(where: { $0.kind == .runShell }) else {
            runPhase = .failed(mode, "Shell execution disabled")
            appendLog(.error, "MacTape 0.1 desktop never authorizes shell execution. Disable shell steps for a live run, or use Dry Run to inspect safely.")
            return
        }
        guard let values = requestRuntimeVariables(for: document) else { runPhase = .idle; return }
        let generation = UUID(); activeRunGeneration = generation
        lastRunRecord = nil; isStopping = false
        let options = WorkflowRunnerOptions(dryRun: mode == .dryRun, eventHandler: { [weak self] event in
            Task { @MainActor in
                guard let self, self.activeRunGeneration == generation, self.runPhase.isActive else { return }
                self.receiveRunEvent(event, workflow: document, mode: mode)
            }
        })
        runnerTask = Task { [weak self] in
            guard let self else { return }
            do {
                let record = try await self.coreRunner.run(document, variableValues: values, options: options)
                self.finishRun(record, mode: mode)
            } catch let failure as WorkflowRunFailure { self.finishRun(failure.record, mode: mode) }
            catch {
                self.runPhase = .failed(mode, "Preflight failed"); self.isStopping = false; self.activeStepID = nil
                if case let WorkflowRunnerError.safetyValidationFailed(report) = error {
                    for finding in report.findings { self.appendLog(finding.severity == .error ? .error : .warning, finding.message, stepID: finding.stepID) }
                } else { self.appendLog(.error, error.localizedDescription) }
            }
        }
    }

    private func requestRuntimeVariables(for workflow: Workflow) -> [String: String]? {
        guard !workflow.variables.isEmpty else { return [:] }
        let alert = NSAlert()
        alert.messageText = "Inputs for this run"
        alert.informativeText = "Values are held in memory for this run only. Secret inputs have no saved default. Nothing has started."
        alert.addButton(withTitle: "Continue"); alert.addButton(withTitle: "Cancel")
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        var fields: [(String, NSTextField)] = []
        for variable in workflow.variables {
            let label = NSTextField(labelWithString: variable.name + (variable.isSecret ? " · secret" : ""))
            let field: NSTextField = variable.isSecret ? NSSecureTextField() : NSTextField()
            field.stringValue = variable.isSecret ? "" : (variable.defaultValue ?? "")
            field.placeholderString = variable.isRequired ? "Required input" : "Optional input"
            field.setAccessibilityLabel(variable.name)
            field.widthAnchor.constraint(equalToConstant: 360).isActive = true
            stack.addArrangedSubview(label); stack.addArrangedSubview(field); fields.append((variable.name, field))
        }
        stack.frame = NSRect(x: 0, y: 0, width: 360, height: CGFloat(workflow.variables.count) * 62)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 380, height: min(310, stack.frame.height)))
        scroll.hasVerticalScroller = true; scroll.documentView = stack; alert.accessoryView = scroll
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        var values: [String: String] = [:]
        for (name, field) in fields { values[name] = field.stringValue }
        return values
    }

    private func receiveRunEvent(_ event: WorkflowRunEvent, workflow: Workflow, mode: RunMode) {
        switch event {
        case .runStarted:
            runPhase = .running(mode)
            appendLog(.info, mode == .dryRun ? "Dry Run started. No workflow actions will be performed." : "Live run started. Stop is available in the menu bar.")
        case let .stepStarted(_, stepID, index, kind, _):
            activeStepID = stepID
            appendLog(.info, "\(mode == .dryRun ? "Checking" : "Running") step \(index + 1): \(kind.rawValue).", stepID: stepID)
        case let .stepFinished(_, stepID, index, status):
            runProgress = Double(workflow.steps.prefix(index + 1).filter(\.isEnabled).count) / Double(max(1, workflow.enabledSteps.count))
            appendLog(status == .succeeded ? .success : .warning, "Step \(index + 1) \(mode == .dryRun && status == .succeeded ? "checked without execution" : status.rawValue).", stepID: stepID)
        case .runFinished: break
        }
    }

    private func finishRun(_ record: RunRecord, mode: RunMode) {
        lastRunRecord = record; activeStepID = nil; isStopping = false
        for diagnostic in record.diagnostics + record.steps.flatMap(\.diagnostics) {
            appendLog(diagnostic.severity == .error ? .error : .warning, diagnostic.message, stepID: diagnostic.stepID)
        }
        switch record.status {
        case .succeeded:
            runPhase = .succeeded(mode); runProgress = 1
            appendLog(.success, mode == .dryRun ? "Dry Run completed against the current desktop. A later live run may differ." : "Run completed.")
            if playCompletionSound { NSSound(named: "Glass")?.play() }
            if !keepConsoleOpen { isConsoleVisible = false }
        case .cancelled:
            runPhase = .idle
            appendLog(.warning, "Cancelled at a safe boundary. Completed actions were not reversed.")
        default:
            runPhase = .failed(mode, "A step failed")
            appendLog(.error, "Run stopped after a failure. Later steps were not executed.")
        }
    }

    func stopCoreActivity() {
        if runPhase == .recording {
            coreRecorder.stop(); recordingWorkflowID = nil; recordingAppIdentifier = nil
            runPhase = .idle; isStopping = false
            appendLog(.success, "Recording stopped. Captured \(recordedInteractionCount) interactions; review before running.")
        } else {
            appendLog(.warning, "Cancellation requested. Waiting for a safe boundary…")
            runnerTask?.cancel()
            Task { await coreRunner.cancel() }
        }
    }

    func refreshPermissionsWithCore() {
        permissionStates[.accessibility] = AccessibilityPermission.isGranted ? .granted : .denied
        permissionStates[.inputMonitoring] = InputMonitoringPermission.isGranted ? .granted : .denied
    }

    func requestPermissionWithCore(_ permission: AutomationPermission) {
        switch permission {
        case .accessibility: AccessibilityPermission.request()
        case .inputMonitoring: _ = InputMonitoringPermission.request()
        }
        refreshPermissions()
        if permissionStates[permission] != .granted { openPermissionSettings(permission) }
    }
}
