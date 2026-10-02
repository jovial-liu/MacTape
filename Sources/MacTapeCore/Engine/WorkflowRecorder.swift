import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// A global, listen-only interaction recorder.
///
/// Privacy invariant: the recorder never asks CGEvent for Unicode text and it
/// ignores ordinary key presses. Only mouse-down events and explicitly
/// modified shortcuts are emitted.
public final class WorkflowRecorder: @unchecked Sendable {
    public typealias InteractionHandler = @Sendable (RecordedInteraction) -> Void
    public typealias StateHandler = @Sendable (RecorderState) -> Void

    private final class EventTapContext {
        weak var recorder: WorkflowRecorder?

        init(recorder: WorkflowRecorder) {
            self.recorder = recorder
        }
    }

    private let configuration: RecorderConfiguration
    private let lock = NSLock()
    private let processingQueue = DispatchQueue(
        label: "dev.mactape.recorder.processing",
        qos: .userInitiated
    )

    private var storedState: RecorderState = .idle
    private var interactionHandler: InteractionHandler?
    private var stateHandler: StateHandler?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var eventRunLoop: CFRunLoop?
    private var retainedContext: UnsafeMutableRawPointer?

    public init(configuration: RecorderConfiguration = RecorderConfiguration()) {
        self.configuration = configuration
    }

    deinit {
        stop()
    }

    public var state: RecorderState {
        lock.lock()
        defer { lock.unlock() }
        return storedState
    }

    public func setInteractionHandler(_ handler: InteractionHandler?) {
        lock.lock()
        interactionHandler = handler
        lock.unlock()
    }

    public func setStateHandler(_ handler: StateHandler?) {
        lock.lock()
        stateHandler = handler
        lock.unlock()
    }

    public func start() throws {
        guard AccessibilityPermission.isGranted else {
            throw RecorderError.accessibilityPermissionRequired
        }

        if !InputMonitoringPermission.isGranted {
            if configuration.requestsInputMonitoringPermission {
                _ = InputMonitoringPermission.request()
            }
            guard InputMonitoringPermission.isGranted else {
                throw RecorderError.inputMonitoringPermissionRequired
            }
        }

        lock.lock()
        guard storedState == .idle || isFailed(storedState) else {
            lock.unlock()
            throw RecorderError.alreadyRunning
        }
        storedState = .starting
        lock.unlock()
        transition(to: .starting)

        let context = EventTapContext(recorder: self)
        let contextPointer = Unmanaged.passRetained(context).toOpaque()
        let mask = Self.eventMask

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: Self.eventTapCallback,
            userInfo: contextPointer
        ) else {
            Unmanaged<EventTapContext>.fromOpaque(contextPointer).release()
            transition(to: .failed(message: RecorderError.eventTapCreationFailed.localizedDescription))
            throw RecorderError.eventTapCreationFailed
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            Unmanaged<EventTapContext>.fromOpaque(contextPointer).release()
            transition(to: .failed(message: RecorderError.eventTapCreationFailed.localizedDescription))
            throw RecorderError.eventTapCreationFailed
        }

        lock.lock()
        guard storedState == .starting else {
            lock.unlock()
            CFMachPortInvalidate(tap)
            Unmanaged<EventTapContext>.fromOpaque(contextPointer).release()
            transition(to: .idle)
            return
        }
        eventTap = tap
        runLoopSource = source
        retainedContext = contextPointer
        lock.unlock()

        let thread = Thread { [weak self] in
            self?.runEventTapLoop()
        }
        thread.name = "MacTape Event Recorder"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    public func stop() {
        let currentState = state
        guard currentState != .idle, currentState != .stopping else { return }
        transition(to: .stopping)

        lock.lock()
        let tap = eventTap
        let loop = eventRunLoop
        lock.unlock()

        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let loop {
            CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) { CFRunLoopStop(loop) }
            CFRunLoopWakeUp(loop)
        } else if tap == nil, isFailed(currentState) {
            transition(to: .idle)
        }
    }

    private func runEventTapLoop() {
        lock.lock()
        guard let tap = eventTap, let source = runLoopSource else {
            lock.unlock()
            transition(to: .failed(message: RecorderError.eventTapCreationFailed.localizedDescription))
            return
        }
        let loop = CFRunLoopGetCurrent()
        eventRunLoop = loop
        let shouldStart = storedState == .starting
        lock.unlock()

        guard shouldStart else {
            cleanupAfterEventLoop()
            return
        }

        CFRunLoopAddSource(loop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        transition(to: .recording)
        CFRunLoopRun()

        CFRunLoopRemoveSource(loop, source, .commonModes)
        cleanupAfterEventLoop()
    }

    private func cleanupAfterEventLoop() {
        lock.lock()
        let contextPointer = retainedContext
        retainedContext = nil
        eventTap = nil
        runLoopSource = nil
        eventRunLoop = nil
        lock.unlock()

        if let contextPointer {
            Unmanaged<EventTapContext>.fromOpaque(contextPointer).release()
        }
        transition(to: .idle)
    }

    private func receive(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            lock.lock()
            let tap = eventTap
            lock.unlock()
            if let tap, state == .recording {
                CGEvent.tapEnable(tap: tap, enable: true)
            }

        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            guard state == .recording else { return }
            recordClick(type: type, event: event)

        case .keyDown:
            guard state == .recording else { return }
            recordShortcut(event: event)

        default:
            break
        }
    }

    private func recordClick(type: CGEventType, event: CGEvent) {
        let point = event.location
        let clickCount = max(1, Int(event.getIntegerValueField(.mouseEventClickState)))
        let button: RecordedMouseButton = switch type {
        case .leftMouseDown: .left
        case .rightMouseDown: .right
        default: .other
        }
        let timestamp = Date()
        let snapshotter = configuration.snapshotter

        processingQueue.async { [weak self] in
            guard let self, self.state == .recording else { return }
            let snapshot = try? snapshotter.snapshot(at: point)
            guard snapshot?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            self.emit(
                .click(
                    RecordedClick(
                        timestamp: timestamp,
                        location: point,
                        button: button,
                        clickCount: clickCount,
                        target: snapshot
                    )
                )
            )
        }
    }

    private func recordShortcut(event: CGEvent) {
        let flags = event.flags

        // This guard is the recorder's central privacy boundary. Shift-only and
        // unmodified key presses are ordinary text and are never emitted.
        guard RecorderEventPolicy.recordsShortcut(flags: flags, allowsOptionOnly: configuration.allowsOptionOnlyShortcuts) else { return }
        let frontmost = NSWorkspace.shared.frontmostApplication
        guard frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }

        var modifiers: RecordedShortcutModifiers = []
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskSecondaryFn) { modifiers.insert(.function) }

        let keyCodeValue = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCodeValue >= 0, keyCodeValue <= Int64(UInt16.max) else { return }

        let shortcut = RecordedShortcut(
            timestamp: Date(),
            keyCode: UInt16(keyCodeValue),
            modifiers: modifiers,
            bundleIdentifier: frontmost?.bundleIdentifier
        )
        processingQueue.async { [weak self] in
            guard let self, self.state == .recording else { return }
            self.emit(.shortcut(shortcut))
        }
    }

    private func emit(_ interaction: RecordedInteraction) {
        lock.lock()
        let handler = interactionHandler
        lock.unlock()
        guard let handler else { return }
        configuration.callbackQueue.async {
            handler(interaction)
        }
    }

    private func transition(to newState: RecorderState) {
        lock.lock()
        storedState = newState
        let handler = stateHandler
        lock.unlock()
        guard let handler else { return }
        configuration.callbackQueue.async {
            handler(newState)
        }
    }

    private func isFailed(_ state: RecorderState) -> Bool {
        if case .failed = state { return true }
        return false
    }

    private static let eventMask: CGEventMask = {
        let types: [CGEventType] = [
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .keyDown,
        ]
        return types.reduce(CGEventMask(0)) { partial, type in
            partial | (CGEventMask(1) << type.rawValue)
        }
    }()

    private static let eventTapCallback: CGEventTapCallBack = {
        _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }
        let context = Unmanaged<EventTapContext>.fromOpaque(userInfo).takeUnretainedValue()
        context.recorder?.receive(type: type, event: event)
        return Unmanaged.passUnretained(event)
    }
}

enum RecorderEventPolicy {
    static func recordsShortcut(flags: CGEventFlags, allowsOptionOnly: Bool) -> Bool {
        flags.contains(.maskCommand) || flags.contains(.maskControl) || (allowsOptionOnly && flags.contains(.maskAlternate))
    }
}
