import AppKit
import MacTapeCore
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var workflows: [EditableWorkflow] = []
    @Published var selection: SidebarSelection = .welcome {
        didSet {
            if case .workflow = selection { return }
            selectedStepID = nil
        }
    }
    @Published var selectedStepID: UUID?
    @Published var runPhase: RunPhase = .idle
    @Published var runProgress: Double = 0
    @Published var activeStepID: UUID?
    @Published var consoleEntries: [RunLogEntry] = []
    @Published var isConsoleVisible = true
    @Published var isInspectorVisible = true
    @Published var showsPermissionOnboarding = false
    @Published var permissionStates: [AutomationPermission: PermissionState] = Dictionary(
        uniqueKeysWithValues: AutomationPermission.allCases.map { ($0, .unknown) }
    )
    @Published var sidebarSearch = ""
    @Published var userFacingError: String?
    @Published var persistenceMessage = "Loading library…"
    @Published var isStopping = false
    @Published var lastRunRecord: RunRecord?

    var workflowStore: WorkflowStore?
    let coreRunner = WorkflowRunner()
    let coreRecorder = WorkflowRecorder()
    var storageTask: Task<Void, Never>?
    var runnerTask: Task<Void, Never>?
    var didBootstrap = false
    var recordingWorkflowID: UUID?
    var recordingAppIdentifier: String?
    var recordedInteractionCount = 0
    var activeRunGeneration = UUID()
    @Published var appearance: AppAppearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Keys.appearance) }
    }
    @Published var confirmBeforeLiveRun: Bool {
        didSet { UserDefaults.standard.set(confirmBeforeLiveRun, forKey: Keys.confirmBeforeLiveRun) }
    }
    @Published var showStepNotes: Bool {
        didSet { UserDefaults.standard.set(showStepNotes, forKey: Keys.showStepNotes) }
    }
    @Published var keepConsoleOpen: Bool {
        didSet { UserDefaults.standard.set(keepConsoleOpen, forKey: Keys.keepConsoleOpen) }
    }
    @Published var playCompletionSound: Bool {
        didSet { UserDefaults.standard.set(playCompletionSound, forKey: Keys.playCompletionSound) }
    }

    let templates = WorkflowTemplate.builtIns

    private enum Keys {
        static let appearance = "appearance"
        static let confirmBeforeLiveRun = "confirmBeforeLiveRun"
        static let showStepNotes = "showStepNotes"
        static let keepConsoleOpen = "keepConsoleOpen"
        static let playCompletionSound = "playCompletionSound"
        static let completedOnboarding = "completedPermissionOnboarding"
    }

    init() {
        let defaults = UserDefaults.standard
        appearance = AppAppearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "system") ?? .system
        confirmBeforeLiveRun = defaults.object(forKey: Keys.confirmBeforeLiveRun) as? Bool ?? true
        showStepNotes = defaults.object(forKey: Keys.showStepNotes) as? Bool ?? true
        keepConsoleOpen = defaults.object(forKey: Keys.keepConsoleOpen) as? Bool ?? true
        playCompletionSound = defaults.object(forKey: Keys.playCompletionSound) as? Bool ?? false

        if !defaults.bool(forKey: Keys.completedOnboarding) {
            showsPermissionOnboarding = true
        }
    }

    var selectedWorkflowID: UUID? {
        guard case let .workflow(id) = selection else { return nil }
        return id
    }

    var selectedWorkflow: EditableWorkflow? {
        guard let id = selectedWorkflowID else { return nil }
        return workflows.first(where: { $0.id == id })
    }

    var selectedStep: EditableStep? {
        guard let workflow = selectedWorkflow, let selectedStepID else { return nil }
        return workflow.steps.first(where: { $0.id == selectedStepID })
    }

    var filteredWorkflows: [EditableWorkflow] {
        let query = sidebarSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return workflows }
        return workflows.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.summary.localizedCaseInsensitiveContains(query)
        }
    }

    var canRunSelection: Bool {
        guard let workflow = selectedWorkflow else { return false }
        return workflow.enabledStepCount > 0 && !runPhase.isActive
    }

    var canRecord: Bool {
        !runPhase.isActive || runPhase == .recording
    }

    func workflowBinding(for id: UUID) -> Binding<EditableWorkflow>? {
        guard workflows.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { [weak self] in
                self?.workflows.first(where: { $0.id == id })
                    ?? EditableWorkflow(name: "Unavailable", summary: "")
            },
            set: { [weak self] newValue in
                guard let self, let index = self.workflows.firstIndex(where: { $0.id == id }) else { return }
                var updated = newValue
                updated.updatedAt = .now
                self.workflows[index] = updated
                self.scheduleSave(updated)
            }
        )
    }

    func selectedStepBinding() -> Binding<EditableStep>? {
        guard let workflowID = selectedWorkflowID, let stepID = selectedStepID else { return nil }
        guard let workflowIndex = workflows.firstIndex(where: { $0.id == workflowID }) else { return nil }
        guard workflows[workflowIndex].steps.contains(where: { $0.id == stepID }) else { return nil }

        return Binding(
            get: { [weak self] in
                guard let self,
                      let workflow = self.workflows.first(where: { $0.id == workflowID }),
                      let step = workflow.steps.first(where: { $0.id == stepID })
                else {
                    return EditableStep(kind: .wait, title: "Unavailable")
                }
                return step
            },
            set: { [weak self] updatedStep in
                guard let self,
                      let workflowIndex = self.workflows.firstIndex(where: { $0.id == workflowID }),
                      let stepIndex = self.workflows[workflowIndex].steps.firstIndex(where: { $0.id == stepID })
                else { return }
                self.workflows[workflowIndex].steps[stepIndex] = updatedStep
                self.workflows[workflowIndex].updatedAt = .now
                self.scheduleSave(self.workflows[workflowIndex])
            }
        )
    }

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        refreshPermissions()
        await loadLibraryWithCore()
    }

    @discardableResult
    func createBlankWorkflow() -> UUID {
        let workflow = EditableWorkflow(
            name: "Untitled Tape",
            summary: "A reviewable Mac workflow.",
            accent: .indigo,
            steps: []
        )
        workflows.insert(workflow, at: 0)
        selection = .workflow(workflow.id)
        selectedStepID = workflow.steps.first?.id
        scheduleSave(workflow)
        return workflow.id
    }

    @discardableResult
    func createWorkflow(from template: WorkflowTemplate) -> UUID {
        let workflow = template.instantiate()
        workflows.insert(workflow, at: 0)
        selection = .workflow(workflow.id)
        selectedStepID = workflow.steps.first?.id
        scheduleSave(workflow)
        appendLog(.info, "Created “\(workflow.name)” from a template. It will not run until you press Dry Run or Run.")
        return workflow.id
    }

    func duplicateSelectedWorkflow() {
        guard var duplicate = selectedWorkflow else { return }
        duplicate.id = UUID()
        duplicate.name += " Copy"
        duplicate.createdAt = .now
        duplicate.updatedAt = .now
        duplicate.steps = duplicate.steps.map {
            var step = $0
            step.id = UUID()
            return step
        }
        workflows.insert(duplicate, at: 0)
        selection = .workflow(duplicate.id)
        selectedStepID = duplicate.steps.first?.id
        scheduleSave(duplicate)
    }

    func deleteWorkflow(id: UUID) {
        guard !runPhase.isActive else { return }
        scheduleDelete(id)
    }

    func addStep(kind: EditableStep.ActionKind = .click, after stepID: UUID? = nil) {
        guard let workflowID = selectedWorkflowID,
              let workflowIndex = workflows.firstIndex(where: { $0.id == workflowID })
        else { return }

        let step = EditableStep(kind: kind)
        if let stepID, let currentIndex = workflows[workflowIndex].steps.firstIndex(where: { $0.id == stepID }) {
            workflows[workflowIndex].steps.insert(step, at: currentIndex + 1)
        } else {
            workflows[workflowIndex].steps.append(step)
        }
        workflows[workflowIndex].updatedAt = .now
        selectedStepID = step.id
        scheduleSave(workflows[workflowIndex])
    }

    func duplicateSelectedStep() {
        guard let workflowID = selectedWorkflowID,
              let stepID = selectedStepID,
              let workflowIndex = workflows.firstIndex(where: { $0.id == workflowID }),
              let stepIndex = workflows[workflowIndex].steps.firstIndex(where: { $0.id == stepID })
        else { return }
        var copy = workflows[workflowIndex].steps[stepIndex]
        copy.id = UUID()
        copy.title += " Copy"
        workflows[workflowIndex].steps.insert(copy, at: stepIndex + 1)
        workflows[workflowIndex].updatedAt = .now
        selectedStepID = copy.id
        scheduleSave(workflows[workflowIndex])
    }

    func deleteSelectedStep() {
        guard let workflowID = selectedWorkflowID,
              let stepID = selectedStepID,
              let workflowIndex = workflows.firstIndex(where: { $0.id == workflowID }),
              let stepIndex = workflows[workflowIndex].steps.firstIndex(where: { $0.id == stepID })
        else { return }

        workflows[workflowIndex].steps.remove(at: stepIndex)
        workflows[workflowIndex].updatedAt = .now
        let remaining = workflows[workflowIndex].steps
        selectedStepID = remaining.indices.contains(stepIndex) ? remaining[stepIndex].id : remaining.last?.id
        scheduleSave(workflows[workflowIndex])
    }

    func moveSelectedStep(by offset: Int) {
        guard let workflowID = selectedWorkflowID,
              let stepID = selectedStepID,
              let workflowIndex = workflows.firstIndex(where: { $0.id == workflowID }),
              let source = workflows[workflowIndex].steps.firstIndex(where: { $0.id == stepID })
        else { return }
        let destination = source + offset
        guard workflows[workflowIndex].steps.indices.contains(destination) else { return }
        let step = workflows[workflowIndex].steps.remove(at: source)
        workflows[workflowIndex].steps.insert(step, at: destination)
        workflows[workflowIndex].updatedAt = .now
        scheduleSave(workflows[workflowIndex])
    }

    func toggleSelectedStep() {
        guard var binding = selectedStepBinding()?.wrappedValue else { return }
        binding.isEnabled.toggle()
        selectedStepBinding()?.wrappedValue = binding
    }

    func selectAdjacentStep(_ direction: Int) {
        guard let workflow = selectedWorkflow, !workflow.steps.isEmpty else { return }
        let current = selectedStepID.flatMap { id in workflow.steps.firstIndex(where: { $0.id == id }) } ?? 0
        let next = min(max(current + direction, 0), workflow.steps.count - 1)
        selectedStepID = workflow.steps[next].id
    }

    func toggleRecording() {
        if runPhase == .recording {
            stop()
            return
        }
        guard !runPhase.isActive else { return }
        runPhase = .recording
        isConsoleVisible = true
        appendLog(.info, "Recorder is starting…")
        beginRecordingWithCore()
    }

    func start(_ mode: RunMode) {
        guard canRunSelection, let workflow = selectedWorkflow else { return }
        if mode == .live, confirmBeforeLiveRun {
            let confirmation = NSAlert()
            confirmation.messageText = "Run “\(workflow.name)”?"
            confirmation.informativeText = "MacTape will perform \(workflow.enabledStepCount) enabled actions. Completed actions cannot be rolled back. Use Stop in the menu bar to cancel."
            confirmation.alertStyle = .warning
            confirmation.addButton(withTitle: "Run Now")
            confirmation.addButton(withTitle: "Cancel")
            guard confirmation.runModal() == .alertFirstButtonReturn else { return }
        }
        runPhase = .preparing(mode)
        runProgress = 0
        activeStepID = nil
        isConsoleVisible = true
        appendLog(.info, "Preparing \(mode.title.lowercased()) for “\(workflow.name)”.")
        beginRunWithCore(workflow: workflow, mode: mode)
    }

    func stop() {
        guard runPhase.isActive, !isStopping else { return }
        isStopping = true
        stopCoreActivity()
    }

    func clearConsole() {
        consoleEntries.removeAll()
    }

    func revealConsoleEntry(_ entry: RunLogEntry) {
        guard let stepID = entry.stepID else { return }
        selectedStepID = stepID
        isInspectorVisible = true
    }

    func completePermissionOnboarding() {
        UserDefaults.standard.set(true, forKey: Keys.completedOnboarding)
        showsPermissionOnboarding = false
    }

    func refreshPermissions() {
        refreshPermissionsWithCore()
    }

    func requestPermission(_ permission: AutomationPermission) {
        requestPermissionWithCore(permission)
    }

    func openPermissionSettings(_ permission: AutomationPermission) {
        let pane: String
        switch permission {
        case .accessibility: pane = "Privacy_Accessibility"
        case .inputMonitoring: pane = "Privacy_ListenEvent"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    func appendLog(_ level: RunLogEntry.Level, _ message: String, stepID: UUID? = nil) {
        consoleEntries.append(.init(level: level, message: message, stepID: stepID))
        if consoleEntries.count > 2_000 { consoleEntries.removeFirst(consoleEntries.count - 2_000) }
    }

    // MARK: - Core adaptation hooks

    private func scheduleSave(_ workflow: EditableWorkflow) {
        // Bound to MacTapeCore.WorkflowStore in CoreIntegration.swift.
        saveWorkflowWithCore(workflow)
    }

    private func scheduleDelete(_ id: UUID) {
        deleteWorkflowWithCore(id)
    }
}
