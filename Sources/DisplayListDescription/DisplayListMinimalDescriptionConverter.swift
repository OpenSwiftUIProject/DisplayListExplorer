public struct DisplayListMinimalDescriptionConversion: Equatable, Sendable {
    public let description: String
    public let usedEncodingIDs: Set<String>
    public let spans: [DisplayListDescriptionSpan]

    public init(
        description: String,
        usedEncodingIDs: Set<String>,
        spans: [DisplayListDescriptionSpan] = []
    ) {
        self.description = description
        self.usedEncodingIDs = usedEncodingIDs
        self.spans = spans
    }
}

public enum DisplayListMinimalDescriptionConverter {
    public static func convert(_ source: String) throws -> DisplayListMinimalDescriptionConversion {
        guard source.contains(where: { !$0.isWhitespace }) else {
            throw DisplayListDescriptionError.emptyInput
        }

        var lexer = Lexer(source: source)
        let tokens = try lexer.lex()
        var parser = Parser(tokens: tokens)
        let expression = try parser.parse()
        return try MinimalDescriptionRenderer().render(expression)
    }
}

private struct MinimalDescriptionRenderer {
    func render(_ expression: SExpression) throws -> DisplayListMinimalDescriptionConversion {
        guard expression.head == "DL" else {
            throw DisplayListDescriptionError.expectedMinimalDescription(actual: expression.summary)
        }

        let rendered = try renderDisplayList(expression)
        let spans = rendered.spans.enumerated().map { index, span in
            DisplayListDescriptionSpan(
                occurrenceID: "r\(index)",
                encodingID: span.encodingID,
                sourceStart: span.sourceRange.lowerBound,
                sourceEnd: span.sourceRange.upperBound,
                outputStart: span.outputRange.lowerBound,
                outputEnd: span.outputRange.upperBound
            )
        }
        return DisplayListMinimalDescriptionConversion(
            description: rendered.text,
            usedEncodingIDs: Set(spans.map(\.encodingID)),
            spans: spans
        )
    }

    private func renderDisplayList(_ expression: SExpression) throws -> Rendered {
        var rendered = Rendered()
        let start = rendered.utf16Count
        rendered.append("(display-list")

        for child in payload(of: expression) {
            guard child.head?.hasPrefix("I:") == true else {
                throw unsupported("Expected an I:n item inside DL.", expression: child)
            }
            rendered.append("\n")
            rendered.include(try renderItem(child, indentation: 1))
        }

        rendered.append(")")
        rendered.addSpan(
            "structure.dl",
            sourceRange: expression.range,
            outputRange: SourceRange(lowerBound: start, upperBound: rendered.utf16Count)
        )
        return rendered
    }

    private func renderItem(_ expression: SExpression, indentation: Int) throws -> Rendered {
        guard let head = expression.head,
              head.hasPrefix("I:"),
              !head.dropFirst(2).isEmpty else {
            throw unsupported("Expected an item token in the form I:n.", expression: expression)
        }

        let identity = String(head.dropFirst(2))
        let values = Array(payload(of: expression))
        guard values.count <= 1 else {
            throw unsupported("An I:n item can contain only one content, effect, or states value.", expression: expression)
        }

        var rendered = Rendered(indentationText(indentation))
        let start = rendered.utf16Count
        rendered.append("(item #:identity \(identity) #:version ?")
        rendered.append("\n\(indentationText(indentation + 1))(frame (? ?; ? ?))")

        if let value = values.first {
            if value.atom != nil {
                rendered.append("\n\(indentationText(indentation + 1))(content-seed ?)")
                rendered.append("\n")
                rendered.include(try renderContent(value, indentation: indentation + 1))
            } else {
                switch value.head {
                case "F":
                    rendered.append("\n\(indentationText(indentation + 1))(content-seed ?)")
                    rendered.append("\n")
                    rendered.include(try renderFlattened(value, indentation: indentation + 1))
                case "E":
                    rendered.append("\n")
                    rendered.include(try renderEffect(value, indentation: indentation + 1))
                case "states":
                    rendered.append("\n")
                    rendered.include(try renderStates(value, indentation: indentation + 1))
                default:
                    throw unsupported("Unsupported value inside I:n.", expression: value)
                }
            }
        }

        rendered.append(")")
        rendered.addSpan(
            "structure.item",
            sourceRange: expression.range,
            outputRange: SourceRange(lowerBound: start, upperBound: rendered.utf16Count)
        )
        return rendered
    }

    private func renderContent(_ expression: SExpression, indentation: Int) throws -> Rendered {
        guard let token = expression.atom else {
            throw unsupported("Expected a content token.", expression: expression)
        }

        let value: (text: String, encodingID: String)
        switch token {
        case "B":
            value = ("(backdrop *)", "content.backdrop")
        case "C":
            value = ("(color ?)", "content.color")
        case "CH":
            value = ("(chameleon-color *)", "content.chameleon-color")
        case "IM":
            value = ("(image #:size (?, ?))", "content.image")
        case "S":
            value = ("(shape (path *) (paint *) (style *))", "content.shape")
        case "SH":
            value = ("(shadow (path *) (shadow *))", "content.shadow")
        case "PV":
            value = ("(platform-view *)", "content.platform-view")
        case "PL":
            value = ("(platform-layer *)", "content.platform-layer")
        case "T":
            value = ("(text ? #:size (?, ?))", "content.text")
        case "D":
            value = ("(drawing *)", "content.drawing")
        case let token where token.hasPrefix("V:") && token.count > 2:
            value = ("(view #:type \(token.dropFirst(2)))", "content.view")
        case let token where token.hasPrefix("@") && token.count > 1:
            value = ("(placeholder \(token.dropFirst()))", "content.placeholder")
        default:
            throw unsupported("Unsupported minimalDescription content token “\(token)”.", expression: expression)
        }

        return mappedExpression(
            value.text,
            encodingID: value.encodingID,
            source: expression.range,
            indentation: indentation
        )
    }

    private func renderFlattened(_ expression: SExpression, indentation: Int) throws -> Rendered {
        var rendered = Rendered(indentationText(indentation))
        let start = rendered.utf16Count
        rendered.append("(flattened")

        let children = Array(payload(of: expression))
        if children.isEmpty {
            rendered.append(" *")
        } else {
            for child in children {
                guard child.head?.hasPrefix("I:") == true else {
                    throw unsupported("Expected an I:n item inside F.", expression: child)
                }
                rendered.append("\n")
                rendered.include(try renderItem(child, indentation: indentation + 1))
            }
        }

        rendered.append(")")
        rendered.addSpan(
            "content.flattened",
            sourceRange: expression.range,
            outputRange: SourceRange(lowerBound: start, upperBound: rendered.utf16Count)
        )
        return rendered
    }

    private func renderEffect(_ expression: SExpression, indentation: Int) throws -> Rendered {
        var marker: SExpression?
        var items: [SExpression] = []

        for value in payload(of: expression) {
            if value.head?.hasPrefix("I:") == true {
                items.append(value)
            } else if marker == nil {
                marker = value
            } else {
                throw unsupported("An E value can contain only one effect encoding.", expression: value)
            }
        }

        var rendered = Rendered(indentationText(indentation))
        let start = rendered.utf16Count
        rendered.append("(effect")

        if let marker {
            let fragment = try effectFragment(for: marker)
            let fragmentStart = rendered.utf16Count
            rendered.append(" \(fragment.text)")
            rendered.addSpan(
                fragment.encodingID,
                sourceRange: marker.range,
                outputRange: SourceRange(
                    lowerBound: fragmentStart + 1,
                    upperBound: rendered.utf16Count
                )
            )
        } else {
            rendered.append(" *")
        }

        for item in items {
            rendered.append("\n")
            rendered.include(try renderItem(item, indentation: indentation + 1))
        }

        rendered.append(")")
        rendered.addSpan(
            "structure.effect",
            sourceRange: expression.range,
            outputRange: SourceRange(lowerBound: start, upperBound: rendered.utf16Count)
        )
        return rendered
    }

    private func effectFragment(for expression: SExpression) throws -> (text: String, encodingID: String) {
        if let token = expression.atom {
            switch token {
            case "GG":
                return ("#:geometry-group", "effect.geometry-group")
            case "CG":
                return ("#:compositing-group", "effect.compositing-group")
            case "BG":
                return ("#:backdrop-group ?", "effect.backdrop-group")
            case "PR":
                return ("#:properties *", "effect.properties")
            case "PG":
                return ("#:platform-group", "effect.platform-group")
            case "O":
                return ("#:opacity ?", "effect.opacity")
            case "B":
                return ("#:blend-mode ?", "effect.blend-mode")
            case "C":
                return ("(clip *)", "effect.clip")
            case "M":
                return ("(mask *)", "effect.mask")
            case "T":
                return ("(transform *)", "effect.transform")
            case "F":
                return ("(filter *)", "effect.filter")
            case "AN":
                return ("(animation *)", "effect.animation")
            case "TR":
                return ("(contentTransition *)", "effect.content-transition")
            case "AX":
                return ("(accessibility *)", "effect.accessibility")
            case "PL":
                return ("(platform *)", "effect.platform")
            case "IR":
                return ("(interpolatorRoot *)", "effect.interpolator-root")
            case "IL":
                return ("(interpolatorLayer #:serial ?)", "effect.interpolator-layer")
            case "IA":
                return ("(interpolator-animation *)", "effect.interpolator-animation")
            case let token where token.hasPrefix("A:") && token.count > 2:
                return ("#:archive \(token.dropFirst(2))", "effect.archive")
            case let token where token.hasPrefix("H:") && token.count > 2:
                return ("(state \(token.dropFirst(2)))", "effect.state")
            default:
                throw unsupported("Unsupported minimalDescription effect token “\(token)”.", expression: expression)
            }
        }

        if let head = expression.head,
           head.hasPrefix("V:"),
           head.count > 2,
           payload(of: expression).isEmpty {
            return ("(view #:type \(head.dropFirst(2)))", "effect.view")
        }

        throw unsupported("Unsupported nested minimalDescription effect value.", expression: expression)
    }

    private func renderStates(_ expression: SExpression, indentation: Int) throws -> Rendered {
        var rendered = Rendered(indentationText(indentation))
        let start = rendered.utf16Count
        rendered.append("(states")

        for variant in payload(of: expression) {
            guard variant.elements != nil, let hash = variant.head else {
                throw unsupported("Expected a (hash …) value inside states.", expression: variant)
            }
            rendered.append("\n")
            rendered.include(try renderStateVariant(variant, hash: hash, indentation: indentation + 1))
        }

        rendered.append(")")
        rendered.addSpan(
            "structure.states",
            sourceRange: expression.range,
            outputRange: SourceRange(lowerBound: start, upperBound: rendered.utf16Count)
        )
        return rendered
    }

    private func renderStateVariant(
        _ expression: SExpression,
        hash: String,
        indentation: Int
    ) throws -> Rendered {
        var rendered = Rendered(indentationText(indentation))
        let start = rendered.utf16Count
        rendered.append("(state \(hash)")

        for child in payload(of: expression) {
            guard child.head?.hasPrefix("I:") == true else {
                throw unsupported("Expected an I:n item inside a state variant.", expression: child)
            }
            rendered.append("\n")
            rendered.include(try renderItem(child, indentation: indentation + 1))
        }

        rendered.append(")")
        rendered.addSpan(
            "structure.state-hash",
            sourceRange: expression.range,
            outputRange: SourceRange(lowerBound: start, upperBound: rendered.utf16Count)
        )
        return rendered
    }

    private func mappedExpression(
        _ text: String,
        encodingID: String,
        source: SourceRange,
        indentation: Int
    ) -> Rendered {
        var rendered = Rendered(indentationText(indentation))
        let start = rendered.utf16Count
        rendered.append(text)
        rendered.addSpan(
            encodingID,
            sourceRange: source,
            outputRange: SourceRange(lowerBound: start, upperBound: rendered.utf16Count)
        )
        return rendered
    }

    private func payload(of expression: SExpression) -> ArraySlice<SExpression> {
        expression.elements?.dropFirst() ?? []
    }

    private func indentationText(_ level: Int) -> String {
        String(repeating: "  ", count: level)
    }

    private func unsupported(_ message: String, expression: SExpression) -> DisplayListDescriptionError {
        .unsupported(message: "\(message) Near \(expression.summary).")
    }
}
