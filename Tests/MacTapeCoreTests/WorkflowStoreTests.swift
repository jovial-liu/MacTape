import Foundation
import XCTest
@testable import MacTapeCore

final class WorkflowStoreTests: XCTestCase {
    func testSaveLoadListAndDeleteInCustomDirectory() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkflowStore(directory: directory)
        let older = makeWorkflow(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Older",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = makeWorkflow(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "Newer",
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        let savedURL = try await store.save(older)
        _ = try await store.save(newer)
        let loaded = try await store.load(id: older.id)
        let listed = try await store.list()

        XCTAssertEqual(savedURL.pathExtension, "mactape")
        XCTAssertEqual(savedURL.lastPathComponent, "00000000-0000-0000-0000-000000000001.mactape")
        XCTAssertEqual(loaded, older)
        XCTAssertEqual(listed.map(\.id), [newer.id, older.id])
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: directory.path).filter {
                !$0.hasSuffix(".mactape")
            },
            []
        )

        try await store.delete(id: older.id)
        do {
            _ = try await store.load(id: older.id)
            XCTFail("Expected notFound")
        } catch {
            XCTAssertEqual(error as? WorkflowStoreError, .notFound(id: older.id))
        }
    }

    func testSaveAtomicallyReplacesExistingWorkflow() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkflowStore(directory: directory)
        var workflow = makeWorkflow(name: "First")

        _ = try await store.save(workflow)
        workflow.name = "Updated"
        _ = try await store.save(workflow)

        let loaded = try await store.load(id: workflow.id)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(loaded.name, "Updated")
        XCTAssertEqual(files, [store.fileURL(for: workflow.id).lastPathComponent])
    }

    func testImportProtectsExistingIDAndExportWritesPortableDocument() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sourceURL = directory.appendingPathComponent("source.mactape")
        let exportURL = directory.appendingPathComponent("exported.mactape")
        let libraryURL = directory.appendingPathComponent("library", isDirectory: true)
        let workflow = makeWorkflow(name: "Imported")
        try WorkflowCodec().encode(workflow).write(to: sourceURL)
        let store = WorkflowStore(directory: libraryURL)

        let imported = try await store.importWorkflow(from: sourceURL)
        XCTAssertEqual(imported, workflow)

        do {
            _ = try await store.importWorkflow(from: sourceURL)
            XCTFail("Expected alreadyExists")
        } catch {
            XCTAssertEqual(error as? WorkflowStoreError, .alreadyExists(id: workflow.id))
        }

        try await store.export(workflow, to: exportURL)
        let exported = try WorkflowCodec().decode(Data(contentsOf: exportURL))
        XCTAssertEqual(exported, workflow)
    }

    func testMalformedDocumentIsReportedWithoutHidingValidWorkflows() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let malformedURL = directory.appendingPathComponent("broken.mactape")
        try Data("not JSON".utf8).write(to: malformedURL)
        let store = WorkflowStore(directory: directory)
        let valid = makeWorkflow(name: "Still available")
        try await store.save(valid)

        let snapshot = try await store.scan()
        let listed = try await store.list()
        XCTAssertEqual(snapshot.workflows, [valid])
        XCTAssertEqual(listed, [valid])
        XCTAssertEqual(snapshot.issues.map(\.fileName), ["broken.mactape"])
        XCTAssertFalse(try XCTUnwrap(snapshot.issues.first).reason.isEmpty)
        XCTAssertEqual(try Data(contentsOf: malformedURL), Data("not JSON".utf8))
    }

    func testPortableFilenamesAreReportedAndImportRecoversTheDocument() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("My workflow.mactape")
        let workflow = makeWorkflow(name: "Portable document")
        try WorkflowCodec().encode(workflow).write(to: source)
        let store = WorkflowStore(directory: directory)

        let before = try await store.scan()
        XCTAssertTrue(before.workflows.isEmpty)
        XCTAssertEqual(before.issues.map(\.fileName), ["My workflow.mactape"])
        XCTAssertTrue(try XCTUnwrap(before.issues.first).reason.contains("Import"))

        let imported = try await store.importWorkflow(from: source)
        let after = try await store.scan()
        XCTAssertEqual(imported, workflow)
        XCTAssertEqual(after.workflows, [workflow])
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testMismatchedDocumentIDCannotLoadAsAnotherWorkflow() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = WorkflowStore(directory: directory)
        let requestedID = UUID()
        let workflow = makeWorkflow(name: "Unexpected ID")
        try WorkflowCodec().encode(workflow).write(to: store.fileURL(for: requestedID))

        do {
            _ = try await store.load(id: requestedID)
            XCTFail("Expected invalidDocument")
        } catch let WorkflowStoreError.invalidDocument(_, reason) {
            XCTAssertTrue(reason.contains("ID"))
        }
        let snapshot = try await store.scan()
        XCTAssertTrue(snapshot.workflows.isEmpty)
        XCTAssertEqual(snapshot.issues.count, 1)
    }

    func testLibraryRejectsDirectoriesAndSymbolicLinksWithoutFollowingThem() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let document = makeWorkflow(name: "External")
        let source = directory.appendingPathComponent("external.json")
        try WorkflowCodec().encode(document).write(to: source)
        let store = WorkflowStore(directory: directory)
        let link = store.fileURL(for: document.id)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("folder.mactape"),
            withIntermediateDirectories: true
        )

        let snapshot = try await store.scan()
        XCTAssertTrue(snapshot.workflows.isEmpty)
        XCTAssertEqual(snapshot.issues.count, 2)
        XCTAssertTrue(snapshot.issues.allSatisfy { $0.reason.contains("regular file") })
        do {
            _ = try await store.load(id: document.id)
            XCTFail("Expected a symbolic link to be rejected")
        } catch is WorkflowStoreError {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testHiddenFilesAndNonDocumentsAreIgnored() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("ignored".utf8).write(to: directory.appendingPathComponent(".backup.mactape"))
        try Data("ignored".utf8).write(to: directory.appendingPathComponent("notes.txt"))

        let snapshot = try await WorkflowStore(directory: directory).scan()
        XCTAssertEqual(snapshot, .init(workflows: [], issues: []))
    }

    func testPathThatIsAFileIsRejected() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("file".utf8).write(to: directory)
        let store = WorkflowStore(directory: directory)

        do {
            _ = try await store.list()
            XCTFail("Expected pathIsNotDirectory")
        } catch {
            XCTAssertEqual(
                error as? WorkflowStoreError,
                .pathIsNotDirectory(directory.standardizedFileURL)
            )
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MacTapeTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeWorkflow(
        id: UUID = UUID(),
        name: String,
        updatedAt: Date = Date(timeIntervalSince1970: 100)
    ) -> Workflow {
        Workflow(
            id: id,
            name: name,
            createdAt: Date(timeIntervalSince1970: 50),
            updatedAt: updatedAt,
            steps: [.wait(duration: 0.1)]
        )
    }
}
