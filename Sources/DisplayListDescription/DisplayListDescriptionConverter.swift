public struct DisplayListDescriptionConversion: Equatable, Sendable {
    public let minimalDescription: String
    public let usedEncodingIDs: Set<String>
    public let spans: [DisplayListDescriptionSpan]

    public init(
        minimalDescription: String,
        usedEncodingIDs: Set<String>,
        spans: [DisplayListDescriptionSpan] = []
    ) {
        self.minimalDescription = minimalDescription
        self.usedEncodingIDs = usedEncodingIDs
        self.spans = spans
    }
}

public struct DisplayListDescriptionSpan: Equatable, Sendable {
    public let occurrenceID: String
    public let encodingID: String
    public let sourceStart: Int
    public let sourceEnd: Int
    public let outputStart: Int
    public let outputEnd: Int

    public init(
        occurrenceID: String,
        encodingID: String,
        sourceStart: Int,
        sourceEnd: Int,
        outputStart: Int,
        outputEnd: Int
    ) {
        self.occurrenceID = occurrenceID
        self.encodingID = encodingID
        self.sourceStart = sourceStart
        self.sourceEnd = sourceEnd
        self.outputStart = outputStart
        self.outputEnd = outputEnd
    }
}

public enum DisplayListDescriptionError: Error, Equatable, CustomStringConvertible, Sendable {
    case emptyInput
    case syntax(message: String, line: Int, column: Int)
    case expectedDisplayList(actual: String)
    case expectedMinimalDescription(actual: String)
    case unsupported(message: String)

    public var description: String {
        switch self {
        case .emptyInput:
            return "Paste a DisplayList description or minimalDescription to begin."
        case let .syntax(message, line, column):
            return "Line \(line), column \(column): \(message)"
        case let .expectedDisplayList(actual):
            return "Expected a (display-list …) expression, found \(actual)."
        case let .expectedMinimalDescription(actual):
            return "Expected a (DL …) minimalDescription expression, found \(actual)."
        case let .unsupported(message):
            return message
        }
    }
}

public enum DisplayListDescriptionConverter {
    public static func convert(_ source: String) throws -> DisplayListDescriptionConversion {
        guard source.contains(where: { !$0.isWhitespace }) else {
            throw DisplayListDescriptionError.emptyInput
        }

        var lexer = Lexer(source: source)
        let tokens = try lexer.lex()
        var parser = Parser(tokens: tokens)
        let expression = try parser.parse()
        return try Renderer().render(expression)
    }
}

// MARK: - S-expression parsing

struct SourceLocation: Equatable, Sendable {
    var line: Int
    var column: Int
}

struct SourceRange: Equatable, Sendable {
    var lowerBound: Int
    var upperBound: Int
}

struct Token: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case leftParenthesis
        case rightParenthesis
        case atom(String)
    }

    var kind: Kind
    var location: SourceLocation
    var range: SourceRange
}

struct Lexer {
    private let characters: [Character]
    private var index = 0
    private var line = 1
    private var column = 1
    private var utf16Offset = 0

    init(source: String) {
        characters = Array(source)
    }

    mutating func lex() throws -> [Token] {
        var tokens: [Token] = []

        while let character = current {
            if character.isWhitespace {
                advance()
                continue
            }

            let location = SourceLocation(line: line, column: column)
            let startOffset = utf16Offset
            switch character {
            case "(":
                advance()
                tokens.append(Token(
                    kind: .leftParenthesis,
                    location: location,
                    range: SourceRange(lowerBound: startOffset, upperBound: utf16Offset)
                ))
            case ")":
                advance()
                tokens.append(Token(
                    kind: .rightParenthesis,
                    location: location,
                    range: SourceRange(lowerBound: startOffset, upperBound: utf16Offset)
                ))
            case "\"":
                tokens.append(Token(
                    kind: .atom(try readQuotedAtom(from: location)),
                    location: location,
                    range: SourceRange(lowerBound: startOffset, upperBound: utf16Offset)
                ))
            default:
                tokens.append(Token(
                    kind: .atom(readAtom()),
                    location: location,
                    range: SourceRange(lowerBound: startOffset, upperBound: utf16Offset)
                ))
            }
        }

        return tokens
    }

    private var current: Character? {
        index < characters.count ? characters[index] : nil
    }

    private mutating func advance() {
        guard let current else { return }
        index += 1
        utf16Offset += String(current).utf16.count
        if current == "\n" {
            line += 1
            column = 1
        } else {
            column += 1
        }
    }

    private mutating func readAtom() -> String {
        var value = ""
        while let character = current,
              !character.isWhitespace,
              character != "(",
              character != ")" {
            value.append(character)
            advance()
        }
        return value
    }

    private mutating func readQuotedAtom(from location: SourceLocation) throws -> String {
        var value = "\""
        advance()
        var isEscaped = false

        while let character = current {
            value.append(character)
            advance()

            if isEscaped {
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "\"" {
                return value
            }
        }

        throw DisplayListDescriptionError.syntax(
            message: "Unterminated quoted string.",
            line: location.line,
            column: location.column
        )
    }
}

indirect enum SExpression: Equatable, Sendable {
    case atom(String, SourceRange)
    case list([SExpression], SourceRange)

    var atom: String? {
        guard case let .atom(value, _) = self else { return nil }
        return value
    }

    var elements: [SExpression]? {
        guard case let .list(elements, _) = self else { return nil }
        return elements
    }

    var range: SourceRange {
        switch self {
        case let .atom(_, range), let .list(_, range):
            return range
        }
    }

    var head: String? {
        elements?.first?.atom
    }

    var summary: String {
        switch self {
        case let .atom(value, _):
            return value
        case .list:
            return "a list"
        }
    }
}

struct Parser {
    private let tokens: [Token]
    private var index = 0

    init(tokens: [Token]) {
        self.tokens = tokens
    }

    mutating func parse() throws -> SExpression {
        guard !tokens.isEmpty else {
            throw DisplayListDescriptionError.emptyInput
        }

        let result = try parseExpression()
        if let token = current {
            throw syntax("Unexpected content after the top-level expression.", at: token.location)
        }
        return result
    }

    private var current: Token? {
        index < tokens.count ? tokens[index] : nil
    }

    private mutating func parseExpression() throws -> SExpression {
        guard let token = current else {
            let location = tokens.last?.location ?? SourceLocation(line: 1, column: 1)
            throw syntax("Unexpected end of input.", at: location)
        }

        index += 1
        switch token.kind {
        case let .atom(value):
            return .atom(value, token.range)
        case .rightParenthesis:
            throw syntax("Unexpected closing parenthesis.", at: token.location)
        case .leftParenthesis:
            var elements: [SExpression] = []
            while let next = current {
                if next.kind == .rightParenthesis {
                    index += 1
                    return .list(elements, SourceRange(
                        lowerBound: token.range.lowerBound,
                        upperBound: next.range.upperBound
                    ))
                }
                elements.append(try parseExpression())
            }
            throw syntax("Missing closing parenthesis.", at: token.location)
        }
    }

    private func syntax(_ message: String, at location: SourceLocation) -> DisplayListDescriptionError {
        .syntax(message: message, line: location.line, column: location.column)
    }
}

// MARK: - Minimal description rendering

struct PendingSpan {
    var encodingID: String
    var sourceRange: SourceRange
    var outputRange: SourceRange
}

struct Rendered {
    var text: String
    var spans: [PendingSpan] = []

    init(_ text: String = "") {
        self.text = text
    }

    var utf16Count: Int {
        text.utf16.count
    }

    mutating func append(_ fragment: String) {
        text += fragment
    }

    mutating func appendEncoding(
        _ fragment: String,
        encodingID: String,
        sourceRange: SourceRange,
        trimLeadingWhitespace: Bool = true
    ) {
        let start = utf16Count
        text += fragment
        let leadingCount = trimLeadingWhitespace
            ? fragment.prefix(while: \.isWhitespace).utf16.count
            : 0
        addSpan(
            encodingID,
            sourceRange: sourceRange,
            outputRange: SourceRange(lowerBound: start + leadingCount, upperBound: utf16Count)
        )
    }

    mutating func include(_ rendered: Rendered) {
        let offset = utf16Count
        text += rendered.text
        spans += rendered.spans.map { span in
            PendingSpan(
                encodingID: span.encodingID,
                sourceRange: span.sourceRange,
                outputRange: SourceRange(
                    lowerBound: span.outputRange.lowerBound + offset,
                    upperBound: span.outputRange.upperBound + offset
                )
            )
        }
    }

    mutating func addSpan(
        _ encodingID: String,
        sourceRange: SourceRange,
        outputRange: SourceRange
    ) {
        guard sourceRange.lowerBound < sourceRange.upperBound,
              outputRange.lowerBound < outputRange.upperBound else {
            return
        }
        spans.append(PendingSpan(
            encodingID: encodingID,
            sourceRange: sourceRange,
            outputRange: outputRange
        ))
    }
}

private struct Renderer {
    func render(_ expression: SExpression) throws -> DisplayListDescriptionConversion {
        guard expression.head == "display-list" else {
            throw DisplayListDescriptionError.expectedDisplayList(actual: expression.summary)
        }

        var rendered = Rendered("(DL")
        for item in directLists(in: expression, headed: "item") {
            rendered.include(try renderItem(item))
        }
        rendered.append(")")
        rendered.addSpan(
            "structure.dl",
            sourceRange: expression.range,
            outputRange: SourceRange(lowerBound: 0, upperBound: rendered.utf16Count)
        )
        let spans = rendered.spans.enumerated().map { index, span in
            DisplayListDescriptionSpan(
                occurrenceID: "o\(index)",
                encodingID: span.encodingID,
                sourceStart: span.sourceRange.lowerBound,
                sourceEnd: span.sourceRange.upperBound,
                outputStart: span.outputRange.lowerBound,
                outputEnd: span.outputRange.upperBound
            )
        }
        return DisplayListDescriptionConversion(
            minimalDescription: rendered.text,
            usedEncodingIDs: Set(spans.map(\.encodingID)),
            spans: spans
        )
    }

    private func renderItem(_ item: SExpression) throws -> Rendered {
        let identity = atom(after: "#:identity", in: item) ?? "0"
        var rendered = Rendered("(I:\(identity)")

        let children = directLists(in: item)
        if children.contains(where: { $0.head == "content-seed" }) {
            guard let content = children.first(where: { ContentKind(head: $0.head) != nil }) else {
                if let unsupportedHead = children.first(where: {
                    $0.head != "frame" && $0.head != "content-seed"
                })?.head {
                    var message = "Item identity \(identity) contains unsupported DisplayList content “\(unsupportedHead)”."
                    if let suggestion = ContentKind.suggestedHead(for: unsupportedHead) {
                        message += " Did you mean “\(suggestion)”?"
                    }
                    throw DisplayListDescriptionError.unsupported(message: message)
                }
                throw DisplayListDescriptionError.unsupported(
                    message: "Item identity \(identity) contains content-seed but no content value."
                )
            }
            rendered.include(try renderContent(content))
        } else if let effect = children.first(where: { $0.head == "effect" }) {
            rendered.include(try renderEffect(effect))
        } else if let states = children.first(where: { $0.head == "states" }) {
            rendered.include(try renderStates(states))
        }

        rendered.append(")")
        rendered.addSpan(
            "structure.item",
            sourceRange: item.range,
            outputRange: SourceRange(lowerBound: 0, upperBound: rendered.utf16Count)
        )
        return rendered
    }

    private func renderContent(_ content: SExpression) throws -> Rendered {
        guard let kind = ContentKind(head: content.head) else {
            throw DisplayListDescriptionError.unsupported(
                message: "Unsupported DisplayList content encoding: \(content.head ?? "unknown")."
            )
        }

        switch kind {
        case .backdrop:
            return renderEncoding(" B", id: "content.backdrop", source: content.range)
        case .color:
            return renderEncoding(" C", id: "content.color", source: content.range)
        case .chameleonColor:
            return renderEncoding(" CH", id: "content.chameleon-color", source: content.range)
        case .image:
            return renderEncoding(" IM", id: "content.image", source: content.range)
        case .shape:
            return renderEncoding(" S", id: "content.shape", source: content.range)
        case .shadow:
            return renderEncoding(" SH", id: "content.shadow", source: content.range)
        case .platformView:
            return renderEncoding(" PV", id: "content.platform-view", source: content.range)
        case .platformLayer:
            return renderEncoding(" PL", id: "content.platform-layer", source: content.range)
        case .text:
            return renderEncoding(" T", id: "content.text", source: content.range)
        case .drawing:
            return renderEncoding(" D", id: "content.drawing", source: content.range)
        case .view:
            let type = atom(after: "#:type", in: content) ?? "unknown"
            return renderEncoding(" V:\(type)", id: "content.view", source: content.range)
        case .placeholder:
            let identity = directAtoms(in: content).dropFirst().first ?? "unknown"
            return renderEncoding(" @\(identity)", id: "content.placeholder", source: content.range)
        case .flattened:
            var rendered = Rendered("(F")
            for item in directLists(in: content, headed: "item") {
                rendered.include(try renderItem(item))
            }
            rendered.append(")")
            rendered.addSpan(
                "content.flattened",
                sourceRange: content.range,
                outputRange: SourceRange(lowerBound: 0, upperBound: rendered.utf16Count)
            )
            return rendered
        }
    }

    private func renderEncoding(_ text: String, id: String, source: SourceRange) -> Rendered {
        var rendered = Rendered()
        rendered.appendEncoding(text, encodingID: id, sourceRange: source)
        return rendered
    }

    private func renderEffect(_ effect: SExpression) throws -> Rendered {
        var rendered = Rendered("(E")

        if let range = atomRange(startingAt: "#:geometry-group", in: effect) {
            rendered.appendEncoding(" GG", encodingID: "effect.geometry-group", sourceRange: range)
        } else if let range = atomRange(startingAt: "#:compositing-group", in: effect) {
            rendered.appendEncoding(" CG", encodingID: "effect.compositing-group", sourceRange: range)
        } else if let range = atomRange(startingAt: "#:backdrop-group", in: effect, includeFollowingAtom: true) {
            rendered.appendEncoding(" BG", encodingID: "effect.backdrop-group", sourceRange: range)
        } else if let archive = atom(after: "#:archive", in: effect),
                  let range = atomRange(startingAt: "#:archive", in: effect, includeFollowingAtom: true) {
            rendered.appendEncoding(" A:\(archive)", encodingID: "effect.archive", sourceRange: range)
        } else if let property = directAtomExpressions(in: effect).first(where: { PropertyKeyword.all.contains($0.0) }) {
            rendered.appendEncoding(" PR", encodingID: "effect.properties", sourceRange: property.1)
        } else if let range = atomRange(startingAt: "#:platform-group", in: effect) {
            rendered.appendEncoding(" PG", encodingID: "effect.platform-group", sourceRange: range)
        } else if let range = atomRange(startingAt: "#:opacity", in: effect, includeFollowingAtom: true) {
            rendered.appendEncoding(" O", encodingID: "effect.opacity", sourceRange: range)
        } else if let range = atomRange(startingAt: "#:blend-mode", in: effect, includeFollowingAtom: true) {
            rendered.appendEncoding(" B", encodingID: "effect.blend-mode", sourceRange: range)
        } else if let value = directLists(in: effect).compactMap({ expression -> (SExpression, EffectKind)? in
            guard let kind = EffectKind(head: expression.head) else { return nil }
            return (expression, kind)
        }).first {
            rendered.include(renderEffectKind(value.1, expression: value.0))
        }

        for item in directLists(in: effect, headed: "item") {
            rendered.include(try renderItem(item))
        }
        rendered.append(")")
        rendered.addSpan(
            "structure.effect",
            sourceRange: effect.range,
            outputRange: SourceRange(lowerBound: 0, upperBound: rendered.utf16Count)
        )
        return rendered
    }

    private func renderEffectKind(_ kind: EffectKind, expression: SExpression) -> Rendered {
        switch kind {
        case .clip:
            return renderEncoding(" C", id: "effect.clip", source: expression.range)
        case .mask:
            return renderEncoding(" M", id: "effect.mask", source: expression.range)
        case .transform:
            return renderEncoding(" T", id: "effect.transform", source: expression.range)
        case .filter:
            return renderEncoding(" F", id: "effect.filter", source: expression.range)
        case .animation:
            return renderEncoding(" AN", id: "effect.animation", source: expression.range)
        case .contentTransition:
            return renderEncoding(" TR", id: "effect.content-transition", source: expression.range)
        case .view:
            let type = atom(after: "#:type", in: expression) ?? "unknown"
            return renderEncoding("(V:\(type))", id: "effect.view", source: expression.range)
        case .accessibility:
            return renderEncoding(" AX", id: "effect.accessibility", source: expression.range)
        case .platform:
            return renderEncoding(" PL", id: "effect.platform", source: expression.range)
        case .state:
            let hash = directAtoms(in: expression).dropFirst().first ?? "unknown"
            return renderEncoding(" H:\(hash)", id: "effect.state", source: expression.range)
        case .interpolatorRoot:
            return renderEncoding(" IR", id: "effect.interpolator-root", source: expression.range)
        case .interpolatorLayer:
            return renderEncoding(" IL", id: "effect.interpolator-layer", source: expression.range)
        case .interpolatorAnimation:
            return renderEncoding(" IA", id: "effect.interpolator-animation", source: expression.range)
        }
    }

    private func renderStates(_ states: SExpression) throws -> Rendered {
        var rendered = Rendered("(states")
        for state in directLists(in: states, headed: "state") {
            let hash = directAtoms(in: state).dropFirst().first ?? "unknown"
            let stateStart = rendered.utf16Count
            rendered.append("(\(hash)")
            for item in directLists(in: state, headed: "item") {
                rendered.include(try renderItem(item))
            }
            rendered.append(")")
            rendered.addSpan(
                "structure.state-hash",
                sourceRange: state.range,
                outputRange: SourceRange(lowerBound: stateStart, upperBound: rendered.utf16Count)
            )
        }
        rendered.append(")")
        rendered.addSpan(
            "structure.states",
            sourceRange: states.range,
            outputRange: SourceRange(lowerBound: 0, upperBound: rendered.utf16Count)
        )
        return rendered
    }

    private func directLists(in expression: SExpression, headed head: String? = nil) -> [SExpression] {
        guard let elements = expression.elements else { return [] }
        return elements.dropFirst().filter {
            guard $0.elements != nil else { return false }
            return head == nil || $0.head == head
        }
    }

    private func directAtoms(in expression: SExpression) -> [String] {
        guard let elements = expression.elements else { return [] }
        return elements.compactMap(\.atom)
    }

    private func directAtomExpressions(in expression: SExpression) -> [(String, SourceRange)] {
        guard let elements = expression.elements else { return [] }
        return elements.compactMap { expression in
            guard let atom = expression.atom else { return nil }
            return (atom, expression.range)
        }
    }

    private func atom(after keyword: String, in expression: SExpression) -> String? {
        let atoms = directAtoms(in: expression)
        guard let index = atoms.firstIndex(of: keyword), atoms.indices.contains(index + 1) else {
            return nil
        }
        return atoms[index + 1]
    }

    private func atomRange(
        startingAt keyword: String,
        in expression: SExpression,
        includeFollowingAtom: Bool = false
    ) -> SourceRange? {
        let atoms = directAtomExpressions(in: expression)
        guard let index = atoms.firstIndex(where: { $0.0 == keyword }) else {
            return nil
        }
        let upperBound = includeFollowingAtom && atoms.indices.contains(index + 1)
            ? atoms[index + 1].1.upperBound
            : atoms[index].1.upperBound
        return SourceRange(lowerBound: atoms[index].1.lowerBound, upperBound: upperBound)
    }
}

private enum ContentKind {
    case backdrop
    case color
    case chameleonColor
    case image
    case shape
    case shadow
    case platformView
    case platformLayer
    case text
    case flattened
    case drawing
    case view
    case placeholder

    static func suggestedHead(for head: String) -> String? {
        switch head {
        case "chameleonColor": "chameleon-color"
        case "platformView": "platform-view"
        case "platformLayer": "platform-layer"
        default: nil
        }
    }

    init?(head: String?) {
        switch head {
        case "backdrop": self = .backdrop
        case "color": self = .color
        case "chameleon-color": self = .chameleonColor
        case "image": self = .image
        case "shape": self = .shape
        case "shadow": self = .shadow
        case "platform-view": self = .platformView
        case "platform-layer": self = .platformLayer
        case "text": self = .text
        case "flattened": self = .flattened
        case "drawing": self = .drawing
        case "view": self = .view
        case "placeholder": self = .placeholder
        default: return nil
        }
    }
}

private enum EffectKind {
    case clip
    case mask
    case transform
    case filter
    case animation
    case contentTransition
    case view
    case accessibility
    case platform
    case state
    case interpolatorRoot
    case interpolatorLayer
    case interpolatorAnimation

    init?(head: String?) {
        switch head {
        case "clip": self = .clip
        case "mask": self = .mask
        case "transform": self = .transform
        case "filter": self = .filter
        case "animation": self = .animation
        case "contentTransition": self = .contentTransition
        case "view": self = .view
        case "accessibility": self = .accessibility
        case "platform": self = .platform
        case "state": self = .state
        case "interpolatorRoot": self = .interpolatorRoot
        case "interpolatorLayer": self = .interpolatorLayer
        case "interpolator-animation": self = .interpolatorAnimation
        default: return nil
        }
    }
}

private enum PropertyKeyword {
    static let all: Set<String> = [
        "#:primary-fg-layer",
        "#:secondary-fg-layer",
        "#:tertiary-fg-layer",
        "#:quaternary-fg-layer",
        "#:ignores-events",
        "#:privacy-sensitive",
        "#:archives-interactive-controls",
        "#:screencapture-prohibited",
        "#:properties",
    ]
}
