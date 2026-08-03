public struct DisplayListDescriptionConversion: Equatable, Sendable {
    public let minimalDescription: String
    public let usedEncodingIDs: Set<String>

    public init(minimalDescription: String, usedEncodingIDs: Set<String>) {
        self.minimalDescription = minimalDescription
        self.usedEncodingIDs = usedEncodingIDs
    }
}

public enum DisplayListDescriptionError: Error, Equatable, CustomStringConvertible, Sendable {
    case emptyInput
    case syntax(message: String, line: Int, column: Int)
    case expectedDisplayList(actual: String)
    case unsupported(message: String)

    public var description: String {
        switch self {
        case .emptyInput:
            return "Paste a DisplayList description to begin."
        case let .syntax(message, line, column):
            return "Line \(line), column \(column): \(message)"
        case let .expectedDisplayList(actual):
            return "Expected a (display-list …) expression, found \(actual)."
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

private struct SourceLocation: Equatable, Sendable {
    var line: Int
    var column: Int
}

private struct Token: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case leftParenthesis
        case rightParenthesis
        case atom(String)
    }

    var kind: Kind
    var location: SourceLocation
}

private struct Lexer {
    private let characters: [Character]
    private var index = 0
    private var line = 1
    private var column = 1

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
            switch character {
            case "(":
                tokens.append(Token(kind: .leftParenthesis, location: location))
                advance()
            case ")":
                tokens.append(Token(kind: .rightParenthesis, location: location))
                advance()
            case "\"":
                tokens.append(Token(kind: .atom(try readQuotedAtom(from: location)), location: location))
            default:
                tokens.append(Token(kind: .atom(readAtom()), location: location))
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

private indirect enum SExpression: Equatable, Sendable {
    case atom(String)
    case list([SExpression])

    var atom: String? {
        guard case let .atom(value) = self else { return nil }
        return value
    }

    var elements: [SExpression]? {
        guard case let .list(elements) = self else { return nil }
        return elements
    }

    var head: String? {
        elements?.first?.atom
    }

    var summary: String {
        switch self {
        case let .atom(value):
            return value
        case .list:
            return "a list"
        }
    }
}

private struct Parser {
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
            return .atom(value)
        case .rightParenthesis:
            throw syntax("Unexpected closing parenthesis.", at: token.location)
        case .leftParenthesis:
            var elements: [SExpression] = []
            while let next = current {
                if next.kind == .rightParenthesis {
                    index += 1
                    return .list(elements)
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

private struct Rendered {
    var text: String
    var usedEncodingIDs: Set<String>

    init(_ text: String, _ encodingID: String? = nil) {
        self.text = text
        if let encodingID {
            usedEncodingIDs = [encodingID]
        } else {
            usedEncodingIDs = []
        }
    }

    mutating func include(_ rendered: Rendered) {
        text += rendered.text
        usedEncodingIDs.formUnion(rendered.usedEncodingIDs)
    }

    mutating func mark(_ encodingID: String) {
        usedEncodingIDs.insert(encodingID)
    }
}

private struct Renderer {
    func render(_ expression: SExpression) throws -> DisplayListDescriptionConversion {
        guard expression.head == "display-list" else {
            throw DisplayListDescriptionError.expectedDisplayList(actual: expression.summary)
        }

        var rendered = Rendered("(DL", "structure.dl")
        for item in directLists(in: expression, headed: "item") {
            rendered.include(try renderItem(item))
        }
        rendered.text += ")"
        return DisplayListDescriptionConversion(
            minimalDescription: rendered.text,
            usedEncodingIDs: rendered.usedEncodingIDs
        )
    }

    private func renderItem(_ item: SExpression) throws -> Rendered {
        let identity = atom(after: "#:identity", in: item) ?? "0"
        var rendered = Rendered("(I:\(identity)", "structure.item")

        let children = directLists(in: item)
        if children.contains(where: { $0.head == "content-seed" }) {
            guard let content = children.first(where: { ContentKind(head: $0.head) != nil }) else {
                throw DisplayListDescriptionError.unsupported(
                    message: "This item contains content-seed but no supported content value."
                )
            }
            rendered.include(try renderContent(content))
        } else if let effect = children.first(where: { $0.head == "effect" }) {
            rendered.include(try renderEffect(effect))
        } else if let states = children.first(where: { $0.head == "states" }) {
            rendered.include(try renderStates(states))
        }

        rendered.text += ")"
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
            return Rendered(" B", "content.backdrop")
        case .color:
            return Rendered(" C", "content.color")
        case .chameleonColor:
            return Rendered(" CH", "content.chameleon-color")
        case .image:
            return Rendered(" IM", "content.image")
        case .shape:
            return Rendered(" S", "content.shape")
        case .shadow:
            return Rendered(" SH", "content.shadow")
        case .platformView:
            return Rendered(" PV", "content.platform-view")
        case .platformLayer:
            return Rendered(" PL", "content.platform-layer")
        case .text:
            return Rendered(" T", "content.text")
        case .drawing:
            return Rendered(" D", "content.drawing")
        case .view:
            let type = atom(after: "#:type", in: content) ?? "unknown"
            return Rendered(" V:\(type)", "content.view")
        case .placeholder:
            let identity = directAtoms(in: content).dropFirst().first ?? "unknown"
            return Rendered(" @\(identity)", "content.placeholder")
        case .flattened:
            var rendered = Rendered("(F", "content.flattened")
            for item in directLists(in: content, headed: "item") {
                rendered.include(try renderItem(item))
            }
            rendered.text += ")"
            return rendered
        }
    }

    private func renderEffect(_ effect: SExpression) throws -> Rendered {
        var rendered = Rendered("(E", "structure.effect")

        if contains("#:geometry-group", in: effect) {
            rendered.text += " GG"
            rendered.mark("effect.geometry-group")
        } else if contains("#:compositing-group", in: effect) {
            rendered.text += " CG"
            rendered.mark("effect.compositing-group")
        } else if contains("#:backdrop-group", in: effect) {
            rendered.text += " BG"
            rendered.mark("effect.backdrop-group")
        } else if let archive = atom(after: "#:archive", in: effect) {
            rendered.text += " A:\(archive)"
            rendered.mark("effect.archive")
        } else if directAtoms(in: effect).contains(where: PropertyKeyword.all.contains) {
            rendered.text += " PR"
            rendered.mark("effect.properties")
        } else if contains("#:platform-group", in: effect) {
            rendered.text += " PG"
            rendered.mark("effect.platform-group")
        } else if contains("#:opacity", in: effect) {
            rendered.text += " O"
            rendered.mark("effect.opacity")
        } else if contains("#:blend-mode", in: effect) {
            rendered.text += " B"
            rendered.mark("effect.blend-mode")
        } else if let value = directLists(in: effect).compactMap({ expression -> (SExpression, EffectKind)? in
            guard let kind = EffectKind(head: expression.head) else { return nil }
            return (expression, kind)
        }).first {
            rendered.include(renderEffectKind(value.1, expression: value.0))
        }

        for item in directLists(in: effect, headed: "item") {
            rendered.include(try renderItem(item))
        }
        rendered.text += ")"
        return rendered
    }

    private func renderEffectKind(_ kind: EffectKind, expression: SExpression) -> Rendered {
        switch kind {
        case .clip:
            return Rendered(" C", "effect.clip")
        case .mask:
            return Rendered(" M", "effect.mask")
        case .transform:
            return Rendered(" T", "effect.transform")
        case .filter:
            return Rendered(" F", "effect.filter")
        case .animation:
            return Rendered(" AN", "effect.animation")
        case .contentTransition:
            return Rendered(" TR", "effect.content-transition")
        case .view:
            let type = atom(after: "#:type", in: expression) ?? "unknown"
            return Rendered("(V:\(type))", "effect.view")
        case .accessibility:
            return Rendered(" AX", "effect.accessibility")
        case .state:
            let hash = directAtoms(in: expression).dropFirst().first ?? "unknown"
            return Rendered(" H:\(hash)", "effect.state")
        case .interpolatorRoot:
            return Rendered(" IR", "effect.interpolator-root")
        case .interpolatorLayer:
            return Rendered(" IL", "effect.interpolator-layer")
        case .interpolatorAnimation:
            return Rendered(" IA", "effect.interpolator-animation")
        }
    }

    private func renderStates(_ states: SExpression) throws -> Rendered {
        var rendered = Rendered("(states", "structure.states")
        for state in directLists(in: states, headed: "state") {
            let hash = directAtoms(in: state).dropFirst().first ?? "unknown"
            rendered.text += "(\(hash)"
            rendered.mark("structure.state-hash")
            for item in directLists(in: state, headed: "item") {
                rendered.include(try renderItem(item))
            }
            rendered.text += ")"
        }
        rendered.text += ")"
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

    private func contains(_ atom: String, in expression: SExpression) -> Bool {
        directAtoms(in: expression).contains(atom)
    }

    private func atom(after keyword: String, in expression: SExpression) -> String? {
        let atoms = directAtoms(in: expression)
        guard let index = atoms.firstIndex(of: keyword), atoms.indices.contains(index + 1) else {
            return nil
        }
        return atoms[index + 1]
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
    ]
}
