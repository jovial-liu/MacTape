import Foundation

public enum WorkflowStoreError: Error, Equatable, Hashable, Sendable {
    case notFound(id: UUID)
    case alreadyExists(id: UUID)
    case pathIsNotDirectory(URL)
    case invalidDocument(fileName: String, reason: String)
}

extension WorkflowStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .notFound(id):
            "Workflow \(id.uuidString) was not found."
        case let .alreadyExists(id):
            "Workflow \(id.uuidString) already exists."
        case let .pathIsNotDirectory(url):
            "The workflow storage path is not a directory: \(url.path)"
        case let .invalidDocument(fileName, reason):
            "Could not read \(fileName): \(reason)"
        }
    }
}

/// A library entry that could not be loaded. Scanning never edits the entry;
/// callers can surface its location so the user can recover or import it.
public struct WorkflowLibraryIssue: Identifiable, Hashable, Sendable {
    public var fileURL: URL
    public var reason: String

    public var id: URL { fileURL }
    public var fileName: String { fileURL.lastPathComponent }

    public init(fileURL: URL, reason: String) {
        self.fileURL = fileURL
        self.reason = reason
    }
}

public struct WorkflowLibrarySnapshot: Hashable, Sendable {
    public var workflows: [Workflow]
    public var issues: [WorkflowLibraryIssue]

    public init(workflows: [Workflow], issues: [WorkflowLibraryIssue]) {
        self.workflows = workflows
        self.issues = issues
    }
}

/// Actor-isolated persistence for `.mactape` workflow documents.
public actor WorkflowStore {
    public nonisolated let directory: URL
    private let codec: WorkflowCodec

    /// Creates a store rooted at an explicit directory. The directory is created
    /// lazily, which makes this initializer convenient for tests and portable CLI
    /// usage.
    public init(directory: URL, codec: WorkflowCodec = WorkflowCodec()) {
        self.directory = directory.standardizedFileURL
        self.codec = codec
    }

    /// Creates the default store at
    /// `~/Library/Application Support/<applicationName>/<folderName>`.
    public init(
        applicationName: String = "MacTape",
        folderName: String = "Workflows",
        codec: WorkflowCodec = WorkflowCodec()
    ) throws {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        self.directory = applicationSupport
            .appendingPathComponent(applicationName, isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
            .standardizedFileURL
        self.codec = codec
    }

    public nonisolated func fileURL(for id: UUID) -> URL {
        directory
            .appendingPathComponent(id.uuidString.lowercased(), isDirectory: false)
            .appendingPathExtension(WorkflowCodec.fileExtension)
    }

    /// Lists valid workflows, newest first. Use `scan()` to also display any
    /// unreadable entries. One bad document never hides the rest of the library.
    public func list() throws -> [Workflow] {
        try scan().workflows
    }

    /// Reads the managed library without mutating, deleting, or quarantining any
    /// entry. A library uses canonical UUID filenames; portable documents with
    /// other names should be added using `importWorkflow(from:)`.
    public func scan() throws -> WorkflowLibrarySnapshot {
        try ensureDirectoryExists()
        let fileManager = FileManager.default
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == WorkflowCodec.fileExtension }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var workflows: [Workflow] = []
        var issues: [WorkflowLibraryIssue] = []
        workflows.reserveCapacity(urls.count)
        for url in urls {
            do {
                let workflow = try readLibraryDocument(at: url)
                guard url.lastPathComponent == fileURL(for: workflow.id).lastPathComponent else {
                    issues.append(.init(
                        fileURL: url,
                        reason: "The filename does not match this workflow's ID. Use Import to add this document safely."
                    ))
                    continue
                }
                workflows.append(workflow)
            } catch {
                issues.append(.init(
                    fileURL: url,
                    reason: error.localizedDescription
                ))
            }
        }

        let sortedWorkflows = workflows.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            if $0.name != $1.name { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return $0.id.uuidString < $1.id.uuidString
        }
        return WorkflowLibrarySnapshot(workflows: sortedWorkflows, issues: issues)
    }

    public func load(id: UUID) throws -> Workflow {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw WorkflowStoreError.notFound(id: id)
        }
        do {
            let workflow = try readLibraryDocument(at: url)
            guard workflow.id == id else {
                throw WorkflowStoreError.invalidDocument(
                    fileName: url.lastPathComponent,
                    reason: "The document ID does not match its filename. Use Import to recover this document."
                )
            }
            return workflow
        } catch let error as WorkflowStoreError {
            throw error
        } catch {
            throw WorkflowStoreError.invalidDocument(
                fileName: url.lastPathComponent,
                reason: error.localizedDescription
            )
        }
    }

    /// Saves using `Data.write(options: .atomic)`, so readers never observe a
    /// partially written workflow.
    @discardableResult
    public func save(_ workflow: Workflow) throws -> URL {
        try ensureDirectoryExists()
        let url = fileURL(for: workflow.id)
        let data = try codec.encode(workflow)
        try data.write(to: url, options: .atomic)
        return url
    }

    public func delete(id: UUID) throws {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw WorkflowStoreError.notFound(id: id)
        }
        try FileManager.default.removeItem(at: url)
    }

    /// Imports and persists a document. Existing IDs are protected by default.
    @discardableResult
    public func importWorkflow(
        from sourceURL: URL,
        replacingExisting: Bool = false
    ) throws -> Workflow {
        let workflow: Workflow
        do {
            workflow = try codec.decode(Data(contentsOf: sourceURL))
        } catch {
            throw WorkflowStoreError.invalidDocument(
                fileName: sourceURL.lastPathComponent,
                reason: error.localizedDescription
            )
        }

        if !replacingExisting, FileManager.default.fileExists(atPath: fileURL(for: workflow.id).path) {
            throw WorkflowStoreError.alreadyExists(id: workflow.id)
        }
        try save(workflow)
        return workflow
    }

    /// Writes a portable copy without changing the store.
    public func export(_ workflow: Workflow, to destinationURL: URL) throws {
        try codec.encode(workflow).write(to: destinationURL, options: .atomic)
    }

    private func readLibraryDocument(at url: URL) throws -> Workflow {
        let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard properties.isRegularFile == true, properties.isSymbolicLink != true else {
            throw WorkflowStoreError.invalidDocument(
                fileName: url.lastPathComponent,
                reason: "A library entry must be a regular file, not a directory or symbolic link."
            )
        }
        return try codec.decode(Data(contentsOf: url, options: .mappedIfSafe))
    }

    private func ensureDirectoryExists() throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw WorkflowStoreError.pathIsNotDirectory(directory)
            }
            return
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
