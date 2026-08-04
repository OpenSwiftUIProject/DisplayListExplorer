public struct DisplayListPreview: Equatable, Sendable {
    public let items: [DisplayListPreviewItem]
    public let approximations: [String]

    public init(items: [DisplayListPreviewItem], approximations: [String] = []) {
        self.items = items
        self.approximations = approximations
    }
}

public struct DisplayListPreviewPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = DisplayListPreviewPoint(x: 0, y: 0)
}

public struct DisplayListPreviewSize: Equatable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public static let zero = DisplayListPreviewSize(width: 0, height: 0)
}

public struct DisplayListPreviewRect: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let zero = DisplayListPreviewRect(x: 0, y: 0, width: 0, height: 0)
}

public struct DisplayListPreviewTransform: Equatable, Sendable {
    public let a: Double
    public let b: Double
    public let c: Double
    public let d: Double
    public let tx: Double
    public let ty: Double

    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
    }
}

public enum DisplayListPreviewPathCommand: Equatable, Sendable {
    case move(DisplayListPreviewPoint)
    case line(DisplayListPreviewPoint)
    case quad(control: DisplayListPreviewPoint, end: DisplayListPreviewPoint)
    case cubic(
        control1: DisplayListPreviewPoint,
        control2: DisplayListPreviewPoint,
        end: DisplayListPreviewPoint
    )
    case close
}

public struct DisplayListPreviewPath: Equatable, Sendable {
    public let commands: [DisplayListPreviewPathCommand]

    public init(commands: [DisplayListPreviewPathCommand]) {
        self.commands = commands
    }
}

public struct DisplayListPreviewShadow: Equatable, Sendable {
    public let color: String
    public let radius: Double
    public let offset: DisplayListPreviewPoint

    public init(color: String, radius: Double, offset: DisplayListPreviewPoint) {
        self.color = color
        self.radius = radius
        self.offset = offset
    }
}

public indirect enum DisplayListPreviewContent: Equatable, Sendable {
    case color(String)
    case text(String, size: DisplayListPreviewSize)
    case image
    case shape(path: DisplayListPreviewPath, color: String?, evenOdd: Bool)
    case shadow(path: DisplayListPreviewPath, style: DisplayListPreviewShadow)
    case placeholder(String)
    case flattened(origin: DisplayListPreviewPoint, items: [DisplayListPreviewItem])
}

public enum DisplayListPreviewEffect: Equatable, Sendable {
    case identity
    case opacity(Double)
    case blendMode(String)
    case clip(path: DisplayListPreviewPath, evenOdd: Bool)
    case transform(DisplayListPreviewTransform)
    case filter(String)
}

public indirect enum DisplayListPreviewItemValue: Equatable, Sendable {
    case empty
    case content(DisplayListPreviewContent)
    case effect(DisplayListPreviewEffect, children: [DisplayListPreviewItem])
    case states(children: [DisplayListPreviewItem])
}

public struct DisplayListPreviewItem: Equatable, Sendable {
    public let identity: String
    public let frame: DisplayListPreviewRect
    public let value: DisplayListPreviewItemValue

    public init(identity: String, frame: DisplayListPreviewRect, value: DisplayListPreviewItemValue) {
        self.identity = identity
        self.frame = frame
        self.value = value
    }
}

public enum DisplayListPreviewConverter {
    public static func convert(_ source: String) throws -> DisplayListPreview {
        guard source.contains(where: { !$0.isWhitespace }) else {
            throw DisplayListDescriptionError.emptyInput
        }

        var lexer = Lexer(source: source)
        let tokens = try lexer.lex()
        var parser = Parser(tokens: tokens)
        let expression = try parser.parse()
        var builder = DisplayListPreviewBuilder()
        return try builder.render(expression)
    }
}

private struct DisplayListPreviewBuilder {
    private var approximations: [String] = []

    mutating func render(_ expression: SExpression) throws -> DisplayListPreview {
        guard expression.head == "display-list" else {
            throw DisplayListDescriptionError.expectedDisplayList(actual: expression.summary)
        }

        let items = renderItems(directLists(in: expression, headed: "item"))
        return DisplayListPreview(items: items, approximations: approximations)
    }

    private mutating func renderItem(_ item: SExpression) -> DisplayListPreviewItem {
        let identity = atom(after: "#:identity", in: item) ?? "0"
        let frame = directLists(in: item, headed: "frame").first.flatMap(parseRect) ?? .zero
        let children = directLists(in: item)

        let value: DisplayListPreviewItemValue
        if children.contains(where: { $0.head == "content-seed" }) {
            let content = children.first {
                $0.head != "frame" && $0.head != "content-seed"
            }
            value = content.flatMap { renderContent($0) }.map(DisplayListPreviewItemValue.content) ?? .empty
        } else if let effect = children.first(where: { $0.head == "effect" }) {
            let nestedItems = renderItems(directLists(in: effect, headed: "item"))
            value = .effect(renderEffect(effect), children: nestedItems)
        } else if let states = children.first(where: { $0.head == "states" }) {
            let variants = directLists(in: states, headed: "state")
            if variants.count > 1 {
                note("State variants cannot be selected from a static description; the first variant is shown.")
            }
            let nestedItems = variants.first.map { renderItems(directLists(in: $0, headed: "item")) } ?? []
            value = .states(children: nestedItems)
        } else {
            value = .empty
        }

        return DisplayListPreviewItem(identity: identity, frame: frame, value: value)
    }

    private mutating func renderContent(_ content: SExpression) -> DisplayListPreviewContent? {
        switch content.head {
        case "color":
            guard let color = firstColor(in: content) else {
                note("A color value could not be decoded and was left empty.")
                return nil
            }
            return .color(color)
        case "chameleon-color":
            guard let color = directLists(in: content, headed: "color").first.flatMap(firstColor) else {
                note("A chameleon color without a readable fallback was left empty.")
                return nil
            }
            note("Chameleon colors use their fallback color; runtime filters are not available in the description.")
            return .color(color)
        case "backdrop":
            if let color = directLists(in: content, headed: "color").first.flatMap(firstColor) {
                note("Backdrop content uses its fallback color; sampled backdrop pixels are unavailable.")
                return .color(color)
            }
            note("Backdrop content could not be reproduced and was left empty.")
            return nil
        case "text":
            note("Text uses the recorded size to infer a macOS system font point size; its color is approximate.")
            let quoted = directAtoms(in: content).dropFirst().first ?? "\"\""
            let recordedSize = point(after: "#:size", in: content).map {
                DisplayListPreviewSize(width: $0.x, height: $0.y)
            } ?? .zero
            return .text(unquote(quoted), size: recordedSize)
        case "image":
            note("Image pixels are omitted from DisplayList.description, so a placeholder is shown.")
            return .image
        case "shape":
            guard let pathExpression = directLists(in: content, headed: "path").first,
                  let path = parsePath(pathExpression) else {
                note("A shape path could not be decoded and was left empty.")
                return nil
            }
            let paint = directLists(in: content, headed: "paint").first.flatMap(firstColor)
            if paint == nil {
                note("Shape paint details are omitted from the description; a neutral preview color is used.")
            }
            return .shape(path: path, color: paint, evenOdd: fillIsEvenOdd(in: content))
        case "shadow":
            guard let pathExpression = directLists(in: content, headed: "path").first,
                  let path = parsePath(pathExpression) else {
                note("A shadow path could not be decoded and was left empty.")
                return nil
            }
            let shadowExpression = directLists(in: content, headed: "shadow").first
            let style = shadowExpression.map(parseShadow) ?? DisplayListPreviewShadow(
                color: "#00000066",
                radius: 4,
                offset: .zero
            )
            note("Shadows are approximated with the browser canvas shadow model.")
            return .shadow(path: path, style: style)
        case "flattened":
            let origin = point(after: "#:origin", in: content) ?? .zero
            return .flattened(
                origin: origin,
                items: renderItems(directLists(in: content, headed: "item"))
            )
        case "platform-view":
            note("Platform views are represented by labeled placeholders.")
            return .placeholder("Platform view")
        case "platform-layer":
            note("Platform layers are represented by labeled placeholders.")
            return .placeholder("Platform layer")
        case "drawing":
            note("Drawing payloads are omitted from the description and use a placeholder.")
            return .placeholder("Drawing")
        case "view":
            note("View factory payloads cannot be reconstructed and use a placeholder.")
            return .placeholder("View · \(atom(after: "#:type", in: content) ?? "unknown")")
        case "placeholder":
            return .placeholder("Placeholder · \(directAtoms(in: content).dropFirst().first ?? "unknown")")
        default:
            note("Unsupported content “\(content.head ?? "unknown")” was left empty.")
            return nil
        }
    }

    private mutating func renderEffect(_ effect: SExpression) -> DisplayListPreviewEffect {
        if let opacity = number(after: "#:opacity", in: effect) {
            return .opacity(max(0, min(1, opacity)))
        }

        if let blend = atom(after: "#:blend-mode", in: effect) {
            if let mode = canvasBlendMode(from: blend, atoms: allAtoms(in: effect)) {
                return .blendMode(mode)
            }
            note("An unknown blend mode was ignored.")
            return .identity
        }

        if let clip = directLists(in: effect, headed: "clip").first,
           let pathExpression = directLists(in: clip, headed: "path").first,
           let path = parsePath(pathExpression) {
            if allAtoms(in: clip).contains("ClipOptions") || allAtoms(in: clip).contains(where: { $0.contains("rawValue:") }) {
                note("Inverse clip options are not reproduced in the browser preview.")
            }
            return .clip(path: path, evenOdd: fillIsEvenOdd(in: clip))
        }

        if let transform = directLists(in: effect, headed: "transform").first,
           let affine = parseTransform(transform) {
            return .transform(affine)
        }

        if let filter = directLists(in: effect, headed: "filter").first {
            if let cssFilter = parseFilter(filter) {
                note("Graphics filters are approximated with browser canvas filters.")
                return .filter(cssFilter)
            }
            note("This graphics filter cannot be reproduced and was ignored.")
        }

        if directLists(in: effect, headed: "mask").first != nil {
            note("Display-list masks cannot be reconstructed from the static preview and were ignored.")
        }
        return .identity
    }

    private func parseRect(_ expression: SExpression) -> DisplayListPreviewRect? {
        let values = allAtoms(in: expression).dropFirst().compactMap(parseNumber)
        guard values.count >= 4 else { return nil }
        return DisplayListPreviewRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }

    private func parseTransform(_ expression: SExpression) -> DisplayListPreviewTransform? {
        let atoms = allAtoms(in: expression)
        guard let a = namedNumber("a:", in: atoms),
              let b = namedNumber("b:", in: atoms),
              let c = namedNumber("c:", in: atoms),
              let d = namedNumber("d:", in: atoms),
              let tx = namedNumber("tx:", in: atoms),
              let ty = namedNumber("ty:", in: atoms) else {
            return nil
        }
        return DisplayListPreviewTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
    }

    private func parseFilter(_ expression: SExpression) -> String? {
        guard let value = directLists(in: expression).first else { return nil }
        let amount = directAtoms(in: value).dropFirst().compactMap(parseNumber).first
        switch value.head {
        case "blur", "variable-blur":
            return "blur(\(number(after: "#:radius", in: value) ?? 0)px)"
        case "saturation":
            return "saturate(\(amount ?? 1))"
        case "brightness":
            return "brightness(\(max(0, 1 + (amount ?? 0))))"
        case "contrast":
            return "contrast(\(max(0, amount ?? 1)))"
        case "grayscale":
            return "grayscale(\(max(0, min(1, amount ?? 1))))"
        case "hue-rotation":
            let degrees = directAtoms(in: value).dropFirst().first.flatMap(parseNumber) ?? 0
            return "hue-rotate(\(degrees)deg)"
        case "color-invert":
            return "invert(1)"
        case "shadow":
            let atoms = allAtoms(in: value)
            let offset = namedPoint("offset", in: atoms) ?? .zero
            let radius = namedNumber("radius", in: atoms) ?? 0
            let color = atoms.compactMap(normalizedColor).first ?? "#00000066"
            return "drop-shadow(\(offset.x)px \(offset.y)px \(radius)px \(color))"
        default:
            return nil
        }
    }

    private func parseShadow(_ expression: SExpression) -> DisplayListPreviewShadow {
        let atoms = allAtoms(in: expression)
        let color = atoms.compactMap(normalizedColor).first ?? "#00000066"
        let radius = namedNumber("radius:", in: atoms) ?? 4
        let offset = namedPoint("offset:", in: atoms) ?? .zero
        return DisplayListPreviewShadow(color: color, radius: radius, offset: offset)
    }

    private func fillIsEvenOdd(in expression: SExpression) -> Bool {
        let atoms = allAtoms(in: expression)
        guard let index = atoms.firstIndex(where: { $0 == "isEOFilled:" || $0.hasPrefix("isEOFilled:") }) else {
            return false
        }
        if atoms[index] != "isEOFilled:" {
            return atoms[index].dropFirst("isEOFilled:".count).hasPrefix("true")
        }
        return atoms.indices.contains(index + 1) && atoms[index + 1].hasPrefix("true")
    }

    private func parsePath(_ expression: SExpression) -> DisplayListPreviewPath? {
        var commands: [DisplayListPreviewPathCommand] = []
        var numbers: [Double] = []
        var current = DisplayListPreviewPoint.zero
        var lastControl = DisplayListPreviewPoint.zero

        func point(_ xIndex: Int, _ yIndex: Int) -> DisplayListPreviewPoint {
            DisplayListPreviewPoint(x: numbers[xIndex], y: numbers[yIndex])
        }

        for atom in directAtoms(in: expression).dropFirst() {
            if let number = parseNumber(atom) {
                numbers.append(number)
                guard numbers.count <= 6 else { return nil }
                continue
            }

            switch atom {
            case "m" where numbers.count == 2:
                current = point(0, 1)
                lastControl = current
                commands.append(.move(current))
            case "l" where numbers.count == 2:
                current = point(0, 1)
                lastControl = current
                commands.append(.line(current))
            case "q" where numbers.count == 4:
                let control = point(0, 1)
                current = point(2, 3)
                lastControl = control
                commands.append(.quad(control: control, end: current))
            case "c" where numbers.count == 6:
                let control1 = point(0, 1)
                let control2 = point(2, 3)
                current = point(4, 5)
                lastControl = control2
                commands.append(.cubic(control1: control1, control2: control2, end: current))
            case "t" where numbers.count == 2:
                let control = DisplayListPreviewPoint(
                    x: current.x * 2 - lastControl.x,
                    y: current.y * 2 - lastControl.y
                )
                current = point(0, 1)
                lastControl = control
                commands.append(.quad(control: control, end: current))
            case "v" where numbers.count == 4:
                let control1 = current
                let control2 = point(0, 1)
                current = point(2, 3)
                lastControl = control2
                commands.append(.cubic(control1: control1, control2: control2, end: current))
            case "y" where numbers.count == 4:
                let control1 = point(0, 1)
                current = point(2, 3)
                lastControl = current
                commands.append(.cubic(control1: control1, control2: current, end: current))
            case "re" where numbers.count == 4:
                let x = numbers[0]
                let y = numbers[1]
                let width = numbers[2]
                let height = numbers[3]
                commands += [
                    .move(DisplayListPreviewPoint(x: x, y: y)),
                    .line(DisplayListPreviewPoint(x: x + width, y: y)),
                    .line(DisplayListPreviewPoint(x: x + width, y: y + height)),
                    .line(DisplayListPreviewPoint(x: x, y: y + height)),
                    .close,
                ]
                current = DisplayListPreviewPoint(x: x, y: y)
                lastControl = current
            case "h" where numbers.isEmpty:
                commands.append(.close)
                lastControl = .zero
            default:
                return nil
            }
            numbers.removeAll(keepingCapacity: true)
        }

        guard numbers.isEmpty, !commands.isEmpty else { return nil }
        return DisplayListPreviewPath(commands: commands)
    }

    private func canvasBlendMode(from value: String, atoms: [String]) -> String? {
        let namedModes: [(String, String)] = [
            ("multiply", "multiply"), ("screen", "screen"), ("overlay", "overlay"),
            ("darken", "darken"), ("lighten", "lighten"), ("colorDodge", "color-dodge"),
            ("colorBurn", "color-burn"), ("softLight", "soft-light"),
            ("hardLight", "hard-light"), ("difference", "difference"),
            ("exclusion", "exclusion"), ("hue", "hue"), ("saturation", "saturation"),
            ("luminosity", "luminosity"), ("sourceIn", "source-in"),
            ("sourceOut", "source-out"), ("sourceAtop", "source-atop"),
            ("destinationOver", "destination-over"), ("destinationIn", "destination-in"),
            ("destinationOut", "destination-out"), ("destinationAtop", "destination-atop"),
            ("xor", "xor"), ("plusLighter", "lighter"), ("normal", "source-over"),
        ]
        let joined = ([value] + atoms).joined(separator: " ")
        if let match = namedModes.first(where: { joined.contains($0.0) }) {
            return match.1
        }

        guard let rawValue = namedNumber("rawValue:", in: atoms).map(Int.init) else {
            return nil
        }
        let rawModes = [
            0: "source-over", 1: "multiply", 2: "screen", 3: "overlay", 4: "darken",
            5: "lighten", 6: "color-dodge", 7: "color-burn", 8: "soft-light",
            9: "hard-light", 10: "difference", 11: "exclusion", 12: "hue",
            13: "saturation", 14: "color", 15: "luminosity", 18: "source-in",
            19: "source-out", 20: "source-atop", 21: "destination-over",
            22: "destination-in", 23: "destination-out", 24: "destination-atop",
            25: "xor", 27: "lighter",
        ]
        return rawModes[rawValue]
    }

    private mutating func note(_ text: String) {
        if !approximations.contains(text) {
            approximations.append(text)
        }
    }

    private mutating func renderItems(_ expressions: [SExpression]) -> [DisplayListPreviewItem] {
        var items: [DisplayListPreviewItem] = []
        items.reserveCapacity(expressions.count)
        for expression in expressions {
            items.append(renderItem(expression))
        }
        return items
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

    private func allAtoms(in expression: SExpression) -> [String] {
        switch expression {
        case let .atom(value, _):
            return [value]
        case let .list(elements, _):
            return elements.flatMap(allAtoms)
        }
    }

    private func atom(after keyword: String, in expression: SExpression) -> String? {
        let atoms = directAtoms(in: expression)
        guard let index = atoms.firstIndex(of: keyword), atoms.indices.contains(index + 1) else {
            return nil
        }
        return atoms[index + 1]
    }

    private func number(after keyword: String, in expression: SExpression) -> Double? {
        atom(after: keyword, in: expression).flatMap(parseNumber)
    }

    private func point(after keyword: String, in expression: SExpression) -> DisplayListPreviewPoint? {
        guard let elements = expression.elements,
              let index = elements.firstIndex(where: { $0.atom == keyword }),
              elements.indices.contains(index + 1) else {
            return nil
        }
        let values = allAtoms(in: elements[index + 1]).compactMap(parseNumber)
        guard values.count >= 2 else { return nil }
        return DisplayListPreviewPoint(x: values[0], y: values[1])
    }

    private func namedNumber(_ name: String, in atoms: [String]) -> Double? {
        guard let index = atoms.firstIndex(where: { $0 == name || $0.hasPrefix(name) }) else {
            return nil
        }
        let atom = atoms[index]
        if atom.count > name.count, let value = parseNumber(String(atom.dropFirst(name.count))) {
            return value
        }
        guard atoms.indices.contains(index + 1) else { return nil }
        return parseNumber(atoms[index + 1])
    }

    private func namedPoint(_ name: String, in atoms: [String]) -> DisplayListPreviewPoint? {
        guard let index = atoms.firstIndex(where: { $0 == name || $0.hasPrefix(name) }) else {
            return nil
        }
        var values: [Double] = []
        if atoms[index].count > name.count,
           let value = parseNumber(String(atoms[index].dropFirst(name.count))) {
            values.append(value)
        }
        var next = index + 1
        while next < atoms.count, values.count < 2 {
            if let value = parseNumber(atoms[next]) {
                values.append(value)
            }
            next += 1
        }
        guard values.count == 2 else { return nil }
        return DisplayListPreviewPoint(x: values[0], y: values[1])
    }

    private func parseNumber(_ token: String) -> Double? {
        var value = token
        while let first = value.first, first == "(" || first == "[" {
            value.removeFirst()
        }
        while let last = value.last,
              last == "," || last == ";" || last == ")" || last == "]" {
            value.removeLast()
        }
        if value.hasSuffix("deg") {
            value.removeLast(3)
        }
        return Double(value)
    }

    private func firstColor(in expression: SExpression) -> String? {
        allAtoms(in: expression).compactMap(normalizedColor).first
    }

    private func normalizedColor(_ atom: String) -> String? {
        let characters = Array(atom)
        guard characters.count >= 9, characters[0] == "#" else { return nil }
        let digits = characters[1...8]
        guard digits.allSatisfy({ $0.isHexDigit }) else { return nil }
        return "#" + String(digits)
    }

    private func unquote(_ atom: String) -> String {
        guard atom.count >= 2, atom.first == "\"", atom.last == "\"" else { return atom }
        var result = ""
        var escaped = false
        for character in atom.dropFirst().dropLast() {
            if escaped {
                switch character {
                case "n": result.append("\n")
                case "r": result.append("\r")
                case "t": result.append("\t")
                default: result.append(character)
                }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                result.append(character)
            }
        }
        if escaped { result.append("\\") }
        return result
    }
}
