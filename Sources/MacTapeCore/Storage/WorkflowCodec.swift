import Foundation

public enum WorkflowCodecError: Error, Equatable, Hashable, Sendable {
    case unsupportedFormatVersion(found: Int, supported: Int)
    case documentTooLarge(bytes: Int, maximum: Int)
    case invalidDate(field: String)
}

extension WorkflowCodecError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .unsupportedFormatVersion(found, supported):
            "This workflow uses format version \(found); this MacTape build supports version \(supported)."
        case let .documentTooLarge(bytes, maximum):
            "This workflow is \(bytes) bytes; the maximum supported document size is \(maximum) bytes."
        case let .invalidDate(field):
            "The workflow's \(field) date must be finite."
        }
    }
}

/// Canonical JSON encoding for human-readable `.mactape` documents.
///
/// Keys are sorted, dates use ISO 8601 with fractional seconds, slashes remain
/// readable, and files end with a newline. A new encoder/decoder is created for
/// every operation, making this value safe to use across actors.
public struct WorkflowCodec: Hashable, Sendable {
    public static let fileExtension = "mactape"
    /// Workflow documents contain metadata and actions, not embedded media.
    /// Bounding input size prevents accidental multi-gigabyte JSON imports.
    public static let maximumDocumentBytes = 8 * 1_024 * 1_024

    public init() {}

    public func encode(_ workflow: Workflow) throws -> Data {
        try Self.checkFormatVersion(workflow.formatVersion)
        guard workflow.createdAt.timeIntervalSinceReferenceDate.isFinite else {
            throw WorkflowCodecError.invalidDate(field: "createdAt")
        }
        guard workflow.updatedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw WorkflowCodecError.invalidDate(field: "updatedAt")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.dateStyle.format(date))
        }

        var data = try encoder.encode(workflow)
        data.append(0x0A)
        try Self.checkSize(data.count)
        return data
    }

    public func decode(_ data: Data) throws -> Workflow {
        try Self.checkSize(data.count)
        // Read the version before interpreting actions. A future-format file
        // should report its version, not a misleading unknown-action error.
        let header = try JSONDecoder().decode(FormatHeader.self, from: data)
        try Self.checkFormatVersion(header.formatVersion)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            do {
                return try Self.dateStyle.parse(value)
            } catch {
                return try Self.dateStyleWithoutFractions.parse(value)
            }
        }

        return try decoder.decode(Workflow.self, from: data)
    }

    private struct FormatHeader: Decodable {
        var formatVersion: Int
    }

    private static func checkFormatVersion(_ version: Int) throws {
        guard version == MacTapeCore.formatVersion else {
            throw WorkflowCodecError.unsupportedFormatVersion(
                found: version,
                supported: MacTapeCore.formatVersion
            )
        }
    }

    private static func checkSize(_ bytes: Int) throws {
        guard bytes <= maximumDocumentBytes else {
            throw WorkflowCodecError.documentTooLarge(bytes: bytes, maximum: maximumDocumentBytes)
        }
    }

    public func decode(_ text: String) throws -> Workflow {
        try decode(Data(text.utf8))
    }

    public func encodeToString(_ workflow: Workflow) throws -> String {
        let data = try encode(workflow)
        guard let value = String(data: data, encoding: .utf8) else {
            preconditionFailure("JSONEncoder always emits valid UTF-8")
        }
        return value
    }

    private static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let dateStyleWithoutFractions = Date.ISO8601FormatStyle()
}
