import AppKit
import ApplicationServices
import Foundation

public enum SelectorResolutionError: Error, LocalizedError, Sendable, Equatable {
    case accessibilityPermissionRequired
    case emptySelector
    case applicationNotRunning(bundleIdentifier: String)
    case noFrontmostApplication
    case noMatch(minimumScore: Double)
    case ambiguousMatch
    case searchLimitReached

    public var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            "Accessibility permission is required to resolve UI selectors."
        case .emptySelector:
            "An empty selector cannot be resolved safely."
        case let .applicationNotRunning(bundleIdentifier):
            "Application \(bundleIdentifier) is not running."
        case .noFrontmostApplication:
            "There is no frontmost application to search."
        case let .noMatch(minimumScore):
            "No accessible element met the selector score threshold of \(minimumScore)."
        case .ambiguousMatch:
            "Several accessible elements match with similar confidence. Add a more specific selector or an explicit occurrence index."
        case .searchLimitReached:
            "The accessibility search reached its time or tree-size limit before all candidates could be checked."
        }
    }
}

public struct SelectorResolverConfiguration: Sendable, Hashable {
    public var maximumDepth: Int
    public var maximumNodes: Int
    public var maximumChildrenPerNode: Int
    public var minimumScore: Double
    public var ambiguityMargin: Double
    public var searchTimeout: TimeInterval

    public init(
        maximumDepth: Int = 24,
        maximumNodes: Int = 10_000,
        maximumChildrenPerNode: Int = 1_000,
        minimumScore: Double = 0.60,
        ambiguityMargin: Double = 0.05,
        searchTimeout: TimeInterval = 5
    ) {
        self.maximumDepth = max(1, maximumDepth)
        self.maximumNodes = max(1, maximumNodes)
        self.maximumChildrenPerNode = max(1, maximumChildrenPerNode)
        self.minimumScore = minimumScore.isFinite ? min(max(minimumScore, 0.01), 1) : 0.60
        self.ambiguityMargin = ambiguityMargin.isFinite ? min(max(ambiguityMargin, 0), 1) : 0.05
        self.searchTimeout = searchTimeout.isFinite && searchTimeout > 0 ? searchTimeout : 5
    }
}

public struct SelectorMatchReason: Codable, Hashable, Sendable {
    public var attribute: String
    public var matched: Bool
    public var weight: Double

    public init(attribute: String, matched: Bool, weight: Double) {
        self.attribute = attribute
        self.matched = matched
        self.weight = weight
    }
}

public struct SelectorCandidate: @unchecked Sendable {
    public var element: AXElementReference
    public var snapshot: AXElementSnapshot
    public var score: Double
    public var path: [Int]
    public var reasons: [SelectorMatchReason]

    public init(
        element: AXElementReference,
        snapshot: AXElementSnapshot,
        score: Double,
        path: [Int],
        reasons: [SelectorMatchReason]
    ) {
        self.element = element
        self.snapshot = snapshot
        self.score = score
        self.path = path
        self.reasons = reasons
    }
}

/// Resolves semantic selectors against a live macOS Accessibility tree.
/// Candidate collection is bounded by depth and node limits so a malformed or
/// enormous application tree cannot hang a workflow indefinitely.
public struct SelectorResolver: Sendable {
    public var configuration: SelectorResolverConfiguration
    public var snapshotter: AXSnapshotter

    public init(
        configuration: SelectorResolverConfiguration = SelectorResolverConfiguration(),
        snapshotter: AXSnapshotter = AXSnapshotter()
    ) {
        self.configuration = configuration
        self.snapshotter = snapshotter
    }

    public func resolve(
        _ selector: ElementSelector,
        bundleIdentifier: String? = nil,
        root explicitRoot: AXElementReference? = nil
    ) throws -> SelectorCandidate {
        let matches = try candidates(
            for: selector,
            bundleIdentifier: bundleIdentifier,
            root: explicitRoot
        ).filter { $0.score >= configuration.minimumScore }

        let index = try SelectorCandidateSelection.selectIndex(
            scores: matches.map(\.score),
            requestedIndex: selector.index,
            minimumScore: configuration.minimumScore,
            ambiguityMargin: configuration.ambiguityMargin
        )
        return matches[index]
    }

    public func candidates(
        for selector: ElementSelector,
        bundleIdentifier: String? = nil,
        root explicitRoot: AXElementReference? = nil
    ) throws -> [SelectorCandidate] {
        guard AccessibilityPermission.isGranted else {
            throw SelectorResolutionError.accessibilityPermissionRequired
        }
        guard !selector.isEmpty else {
            throw SelectorResolutionError.emptySelector
        }

        let root = try explicitRoot ?? applicationRoot(bundleIdentifier: bundleIdentifier ?? selector.bundleIdentifier)
        let deadline = Date().addingTimeInterval(configuration.searchTimeout)
        var queue: [SearchNode] = [SearchNode(element: root.element, depth: 0, path: [])]
        var cursor = 0
        var visited = Set<AXElementIdentity>()
        var scored: [ScoredElement] = []

        while cursor < queue.count, visited.count < configuration.maximumNodes {
            try Task.checkCancellation()
            guard Date() < deadline else { throw SelectorResolutionError.searchLimitReached }
            let node = queue[cursor]
            cursor += 1
            AXUIElementSetMessagingTimeout(node.element, 0.2)

            let identity = AXElementIdentity(node.element)
            guard visited.insert(identity).inserted else { continue }

            let score = score(element: node.element, path: node.path, selector: selector)
            if score.score >= configuration.minimumScore {
                scored.append(
                    ScoredElement(
                        element: node.element,
                        score: score.score,
                        path: node.path,
                        reasons: score.reasons,
                        traversalOrder: cursor
                    )
                )
            }

            let children = AXAttribute.elements(kAXChildrenAttribute, from: node.element)
            guard children.isEmpty || node.depth < configuration.maximumDepth,
                  children.count <= configuration.maximumChildrenPerNode,
                  queue.count + children.count <= configuration.maximumNodes else {
                throw SelectorResolutionError.searchLimitReached
            }
            for (index, child) in children.prefix(configuration.maximumChildrenPerNode).enumerated() {
                queue.append(
                    SearchNode(
                        element: child,
                        depth: node.depth + 1,
                        path: node.path + [index]
                    )
                )
            }
        }
        guard cursor == queue.count else { throw SelectorResolutionError.searchLimitReached }

        // Highest confidence first. Tree order is a deterministic tie breaker,
        // which also gives ElementSelector.index stable occurrence semantics.
        scored.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.traversalOrder < $1.traversalOrder
        }

        return scored.compactMap { item in
            let reference = AXElementReference(item.element)
            guard let snapshot = try? snapshotter.snapshot(of: reference) else { return nil }
            return SelectorCandidate(
                element: reference,
                snapshot: snapshot,
                score: item.score,
                path: item.path,
                reasons: item.reasons
            )
        }
    }

    private func applicationRoot(bundleIdentifier: String?) throws -> AXElementReference {
        let application: NSRunningApplication
        if let bundleIdentifier {
            guard let match = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleIdentifier)
                .sorted(by: { lhs, rhs in
                    if lhs.isActive != rhs.isActive { return lhs.isActive }
                    return lhs.processIdentifier < rhs.processIdentifier
                })
                .first
            else {
                throw SelectorResolutionError.applicationNotRunning(
                    bundleIdentifier: bundleIdentifier
                )
            }
            application = match
        } else {
            guard let frontmost = NSWorkspace.shared.frontmostApplication else {
                throw SelectorResolutionError.noFrontmostApplication
            }
            application = frontmost
        }
        return AXElementReference(AXUIElementCreateApplication(application.processIdentifier))
    }

    private func score(
        element: AXUIElement,
        path: [Int],
        selector: ElementSelector
    ) -> (score: Double, reasons: [SelectorMatchReason]) {
        var reasons: [SelectorMatchReason] = []

        // Role and subrole are structural constraints, never fuzzy evidence.
        // A high-scoring label must not turn a button selector into a text field.
        if let role = selector.role, AXAttribute.string(kAXRoleAttribute, from: element) != role { return (0, []) }
        if let subrole = selector.subrole, AXAttribute.string(kAXSubroleAttribute, from: element) != subrole { return (0, []) }
        if selector.value != nil, AXAttribute.isSecureTextField(element) { return (0, []) }

        appendReason(
            name: "identifier",
            expected: selector.identifier,
            actual: AXAttribute.string(kAXIdentifierAttribute, from: element),
            strategy: selector.matchStrategy,
            weight: 0.42,
            to: &reasons
        )
        appendReason(
            name: "role",
            expected: selector.role,
            actual: AXAttribute.string(kAXRoleAttribute, from: element),
            strategy: .exact,
            weight: 0.15,
            to: &reasons
        )
        appendReason(
            name: "subrole",
            expected: selector.subrole,
            actual: AXAttribute.string(kAXSubroleAttribute, from: element),
            strategy: .exact,
            weight: 0.08,
            to: &reasons
        )
        appendReason(
            name: "title",
            expected: selector.title,
            actual: AXAttribute.string(kAXTitleAttribute, from: element),
            strategy: selector.matchStrategy,
            weight: 0.18,
            to: &reasons
        )
        appendReason(
            name: "accessibilityDescription",
            expected: selector.accessibilityDescription,
            actual: AXAttribute.string(kAXDescriptionAttribute, from: element),
            strategy: selector.matchStrategy,
            weight: 0.12,
            to: &reasons
        )

        // Reading AXValue is opt-in and used only for a manually-authored
        // selector. Snapshotting and recording never read this attribute.
        if selector.value != nil {
            appendReason(
                name: "value",
                expected: selector.value,
                actual: AXAttribute.string(kAXValueAttribute, from: element),
                strategy: selector.matchStrategy,
                weight: 0.05,
                to: &reasons
            )
        }

        if let expectedPath = selector.path {
            reasons.append(
                SelectorMatchReason(
                    attribute: "path",
                    matched: expectedPath == path,
                    weight: 0.12
                )
            )
        }

        let possible = reasons.reduce(0) { $0 + $1.weight }
        guard possible > 0 else { return (0, reasons) }
        let earned = reasons.filter(\.matched).reduce(0) { $0 + $1.weight }
        return (earned / possible, reasons)
    }

    private func appendReason(
        name: String,
        expected: String?,
        actual: String?,
        strategy: ElementSelector.MatchStrategy,
        weight: Double,
        to reasons: inout [SelectorMatchReason]
    ) {
        guard let expected else { return }
        reasons.append(
            SelectorMatchReason(
                attribute: name,
                matched: matches(actual, expected: expected, strategy: strategy),
                weight: weight
            )
        )
    }

    private func matches(
        _ actual: String?,
        expected: String,
        strategy: ElementSelector.MatchStrategy
    ) -> Bool {
        guard let actual else { return false }
        switch strategy {
        case .exact:
            return actual == expected
        case .contains:
            return actual.range(
                of: expected,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) != nil
        case .beginsWith:
            return actual.range(
                of: expected,
                options: [.anchored, .caseInsensitive, .diacriticInsensitive]
            ) != nil
        case .regularExpression:
            guard let expression = try? NSRegularExpression(pattern: expected) else {
                return false
            }
            let range = NSRange(actual.startIndex..<actual.endIndex, in: actual)
            return expression.firstMatch(in: actual, range: range) != nil
        }
    }
}

private struct SearchNode {
    var element: AXUIElement
    var depth: Int
    var path: [Int]
}

private struct ScoredElement {
    var element: AXUIElement
    var score: Double
    var path: [Int]
    var reasons: [SelectorMatchReason]
    var traversalOrder: Int
}

/// Pure selection policy, kept separate from AX so ambiguous-match behavior is
/// covered by deterministic tests without Accessibility permission.
enum SelectorCandidateSelection {
    static func selectIndex(scores: [Double], requestedIndex: Int?, minimumScore: Double, ambiguityMargin: Double) throws -> Int {
        let eligible = scores.indices.filter { scores[$0].isFinite && scores[$0] >= minimumScore }
        guard let first = eligible.first else { throw SelectorResolutionError.noMatch(minimumScore: minimumScore) }
        if let requestedIndex {
            guard eligible.indices.contains(requestedIndex) else { throw SelectorResolutionError.noMatch(minimumScore: minimumScore) }
            return eligible[requestedIndex]
        }
        if eligible.count > 1, scores[first] - scores[eligible[1]] <= ambiguityMargin + 0.000_000_1 {
            throw SelectorResolutionError.ambiguousMatch
        }
        return first
    }
}

private struct AXElementIdentity: Hashable {
    var element: AXUIElement
    var processIdentifier: pid_t
    var hash: CFHashCode

    init(_ element: AXUIElement) {
        self.element = element
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        processIdentifier = pid
        hash = CFHash(element)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.processIdentifier == rhs.processIdentifier && CFEqual(lhs.element, rhs.element)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(processIdentifier)
        hasher.combine(hash)
    }
}
