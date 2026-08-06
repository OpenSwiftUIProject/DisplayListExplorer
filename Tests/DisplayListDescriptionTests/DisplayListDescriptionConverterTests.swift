import XCTest
@testable import DisplayListDescription

final class DisplayListDescriptionConverterTests: XCTestCase {
    func testConvertsContentViewUsageCapturedOnIPhone17Pro() throws {
        let usage = try fixture(
            "Usage.swift",
            in: "ContentView-iPhone-17-Pro"
        )
        let description = try fixture(
            "DisplayList.description",
            in: "ContentView-iPhone-17-Pro"
        )
        let expectedMinimalDescription = try fixture(
            "DisplayList.minimalDescription",
            in: "ContentView-iPhone-17-Pro"
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        let result = try DisplayListDescriptionConverter.convert(description)

        XCTAssertTrue(usage.contains("struct ContentView: View"))
        XCTAssertEqual(result.minimalDescription, expectedMinimalDescription)
        XCTAssertEqual(result.usedEncodingIDs, [
            "content.color",
            "content.shape",
            "content.text",
            "structure.dl",
            "structure.effect",
            "structure.item",
        ])
    }

    func testConvertsContentEncodings() throws {
        let description = """
        (display-list
          (item #:version 0
            (frame (0.0 0.0; 0.0 0.0)))
          (item #:version 0
            (frame (0.0 0.0; 0.0 0.0))
            (content-seed 1)
            (backdrop (scale 2.0)))
          (item #:identity 2 #:version 0
            (frame (0.0 0.0; 0.0 0.0))
            (content-seed 1)
            (color #FFFFFFFF))
          (item #:version 0
            (frame (0.0 0.0; 0.0 0.0))
            (content-seed 1)
            (chameleon-color (color #000000FF)))
          (item #:version 0
            (frame (0.0 0.0; 0.0 0.0))
            (content-seed 1)
            (image #:size (10.0 5.0)))
          (item #:version 0
            (frame (0.0 0.0; 0.0 0.0))
            (content-seed 1)
            (shape (path 1 2 m 4 2 l) (paint P) (style S)))
          (item #:version 0
            (frame (0.0 0.0; 0.0 0.0))
            (content-seed 1)
            (shadow (path 1 2 m) (shadow ResolvedShadowStyle())))
          (item #:version 0
            (frame (0.0 0.0; 0.0 0.0))
            (content-seed 1)
            (platform-view))
          (item #:version 0
            (frame (0.0 0.0; 0.0 0.0))
            (content-seed 1)
            (platform-layer))
          (item #:version 0
            (frame (0.0 0.0; 0.0 0.0))
            (content-seed 1)
            (text "Hello" #:size (100.0, 20.0)))
          (item #:version 0
            (frame (0.0 0.0; 0.0 0.0))
            (content-seed 1)
            (flattened
              (item #:version 0
                (frame (0.0 0.0; 0.0 0.0))
                (content-seed 2)
                (color #FFFFFFFF))))
          (item #:version 0
            (frame (0.0 0.0; 0.0 0.0))
            (content-seed 1)
            (drawing #:accelerated))
          (item #:version 0
            (frame (0.0 0.0; 0.0 0.0))
            (content-seed 1)
            (view #:type EmptyViewFactory))
          (item #:version 0
            (frame (0.0 0.0; 0.0 0.0))
            (content-seed 1)
            (placeholder #7)))
        """

        let result = try DisplayListDescriptionConverter.convert(description)

        XCTAssertEqual(
            result.minimalDescription,
            "(DL(I:0)(I:0 B)(I:2 C)(I:0 CH)(I:0 IM)(I:0 S)(I:0 SH)(I:0 PV)(I:0 PL)(I:0 T)(I:0(F(I:0 C)))(I:0 D)(I:0 V:EmptyViewFactory)(I:0 @#7))"
        )
        XCTAssertTrue(result.usedEncodingIDs.contains("content.flattened"))
        XCTAssertTrue(result.usedEncodingIDs.contains("content.placeholder"))
    }

    func testConvertsEffectEncodingsAndChildren() throws {
        let description = """
        (display-list
          (item #:version 0 (frame (0 0; 0 0)) (effect))
          (item #:version 0 (frame (0 0; 0 0)) (effect #:geometry-group))
          (item #:version 0 (frame (0 0; 0 0)) (effect #:compositing-group))
          (item #:version 0 (frame (0 0; 0 0)) (effect #:backdrop-group true))
          (item #:version 0 (frame (0 0; 0 0)) (effect #:archive nil))
          (item #:version 0 (frame (0 0; 0 0)) (effect #:privacy-sensitive))
          (item #:version 0 (frame (0 0; 0 0)) (effect #:platform-group))
          (item #:version 0 (frame (0 0; 0 0)) (effect #:opacity 0.5))
          (item #:version 0 (frame (0 0; 0 0)) (effect #:blend-mode normal))
          (item #:version 0 (frame (0 0; 0 0)) (effect (clip (path))))
          (item #:version 0 (frame (0 0; 0 0)) (effect (mask)))
          (item #:version 0 (frame (0 0; 0 0)) (effect (transform affine())))
          (item #:version 0 (frame (0 0; 0 0)) (effect (filter (blur))))
          (item #:version 0 (frame (0 0; 0 0)) (effect (animation)))
          (item #:version 0 (frame (0 0; 0 0)) (effect (contentTransition)))
          (item #:version 0 (frame (0 0; 0 0)) (effect (view #:type EmptyViewFactory)))
          (item #:version 0 (frame (0 0; 0 0)) (effect (accessibility)))
          (item #:version 0 (frame (0 0; 0 0)) (effect (state #abc)))
          (item #:version 0 (frame (0 0; 0 0)) (effect (interpolatorRoot)))
          (item #:version 0 (frame (0 0; 0 0)) (effect (interpolatorLayer #:serial 7)))
          (item #:version 0 (frame (0 0; 0 0)) (effect (interpolator-animation)))
          (item #:identity 9 #:version 0
            (frame (0 0; 0 0))
            (effect #:opacity 0.5
              (item #:identity 10 #:version 0
                (frame (0 0; 0 0))
                (content-seed 1)
                (color #FFFFFFFF)))))
        """

        let result = try DisplayListDescriptionConverter.convert(description)

        XCTAssertEqual(
            result.minimalDescription,
            "(DL(I:0(E))(I:0(E GG))(I:0(E CG))(I:0(E BG))(I:0(E A:nil))(I:0(E PR))(I:0(E PG))(I:0(E O))(I:0(E B))(I:0(E C))(I:0(E M))(I:0(E T))(I:0(E F))(I:0(E AN))(I:0(E TR))(I:0(E(V:EmptyViewFactory)))(I:0(E AX))(I:0(E H:#abc))(I:0(E IR))(I:0(E IL))(I:0(E IA))(I:9(E O(I:10 C))))"
        )
        XCTAssertTrue(result.usedEncodingIDs.contains("effect.opacity"))
        XCTAssertTrue(result.usedEncodingIDs.contains("effect.view"))
    }

    func testConvertsStates() throws {
        let description = """
        (display-list
          (item #:version 0
            (frame (0 0; 0 0))
            (states
              (state #abc
                (item #:version 0
                  (frame (0 0; 0 0))
                  (content-seed 1)
                  (color #FFFFFFFF))))))
        """

        let result = try DisplayListDescriptionConverter.convert(description)

        XCTAssertEqual(result.minimalDescription, "(DL(I:0(states(#abc(I:0 C)))))")
        XCTAssertTrue(result.usedEncodingIDs.contains("structure.states"))
        XCTAssertTrue(result.usedEncodingIDs.contains("structure.state-hash"))
    }

    func testProducesLinkedUTF16RangesForExplorerHighlights() throws {
        let description = """
        (display-list
          (item #:identity 7 #:version 0
            (frame (0 0; 10 10))
            (content-seed 1)
            (text "Hello 🙂" #:size (10, 10))))
        """

        let result = try DisplayListDescriptionConverter.convert(description)
        let textSpan = try XCTUnwrap(result.spans.first { $0.encodingID == "content.text" })
        let itemSpan = try XCTUnwrap(result.spans.first { $0.encodingID == "structure.item" })
        let rootSpan = try XCTUnwrap(result.spans.first { $0.encodingID == "structure.dl" })

        XCTAssertEqual(utf16Slice(description, textSpan.sourceStart, textSpan.sourceEnd), "(text \"Hello 🙂\" #:size (10, 10))")
        XCTAssertEqual(utf16Slice(result.minimalDescription, textSpan.outputStart, textSpan.outputEnd), "T")
        XCTAssertEqual(utf16Slice(result.minimalDescription, itemSpan.outputStart, itemSpan.outputEnd), "(I:7 T)")
        XCTAssertEqual(utf16Slice(result.minimalDescription, rootSpan.outputStart, rootSpan.outputEnd), result.minimalDescription)
        XCTAssertEqual(Set(result.spans.map(\.occurrenceID)).count, result.spans.count)
    }

    func testReportsSyntaxLocation() {
        XCTAssertThrowsError(try DisplayListDescriptionConverter.convert("(display-list\n  (item)")) { error in
            guard case let DisplayListDescriptionError.syntax(message, line, column) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(message, "Missing closing parenthesis.")
            XCTAssertEqual(line, 1)
            XCTAssertEqual(column, 1)
        }
    }

    func testRejectsNonDisplayListRoot() {
        XCTAssertThrowsError(try DisplayListDescriptionConverter.convert("(item)")) { error in
            XCTAssertEqual(
                error as? DisplayListDescriptionError,
                .expectedDisplayList(actual: "a list")
            )
        }
    }

    func testReportsUnsupportedContentNameAndSuggestedSpelling() {
        let description = """
        (display-list
          (item #:identity 4 #:version 2
            (frame {{12, 8.3333333333333339}, {164, 40}})
            (content-seed 5)
            (platformView DemoPlatformViewFactory())))
        """

        XCTAssertThrowsError(try DisplayListDescriptionConverter.convert(description)) { error in
            XCTAssertEqual(
                error as? DisplayListDescriptionError,
                .unsupported(
                    message: "Item identity 4 contains unsupported DisplayList content “platformView”. Did you mean “platform-view”?"
                )
            )
        }
    }

    private func utf16Slice(_ text: String, _ start: Int, _ end: Int) -> String {
        let codeUnits = Array(text.utf16)
        return String(decoding: codeUnits[start..<end], as: UTF16.self)
    }

    private func fixture(_ name: String, in directory: String) throws -> String {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: name,
                withExtension: "txt",
                subdirectory: "Fixtures/\(directory)"
            ),
            "Missing fixture: \(directory)/\(name).txt"
        )
        return try String(contentsOf: url, encoding: .utf8)
    }
}
