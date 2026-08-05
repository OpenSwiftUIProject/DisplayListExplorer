import XCTest
@testable import DisplayListDescription

final class DisplayListPreviewConverterTests: XCTestCase {
    func testBuildsDefaultIPhone17ProSample() throws {
        let description = """
        (display-list
          (item #:version 9
            (frame (189.33333333333331 430.0; 23.0 22.0))
            (effect
              (item #:version 8
                (frame (0.0 0.0; 23.0 22.0))
                (content-seed 17)
                (drawing #:offset (-1.0 0.0)))))
          (item #:identity 2 #:version 7
            (frame (153.66666666666666 453.66666666666663; 94.66666666666666 20.333333333333332))
            (effect
              (item #:version 4
                (frame (0.0 0.0; 94.66666666666666 20.333333333333332))
                (content-seed 9)
                (text "Hello, world!" #:size (94.66666666666666, 20.333333333333332))))))
        """

        let conversion = try DisplayListDescriptionConverter.convert(description)
        let preview = try DisplayListPreviewConverter.convert(description)

        XCTAssertEqual(conversion.minimalDescription, "(DL(I:0(E(I:0 D)))(I:2(E(I:0 T))))")
        XCTAssertEqual(preview.items.count, 2)
        XCTAssertEqual(preview.items[0].frame.x, 189.33333333333331)
        XCTAssertEqual(preview.items[0].frame.y, 430)
        guard case let .effect(_, imageChildren) = preview.items[0].value,
              case .content(.placeholder("Drawing")) = imageChildren.first?.value,
              case let .effect(_, textChildren) = preview.items[1].value,
              case let .content(.text(text, size)) = textChildren.first?.value else {
            return XCTFail("Expected the sample drawing and text layers.")
        }
        XCTAssertEqual(text, "Hello, world!")
        XCTAssertEqual(size.width, 94.66666666666666)
        XCTAssertEqual(size.height, 20.333333333333332)
    }

    func testBuildsPreviewFromCapturedDisplayList() throws {
        let description = try fixture(
            "DisplayList.description",
            directory: "ContentView-iPhone-17-Pro"
        )

        let preview = try DisplayListPreviewConverter.convert(description)

        XCTAssertEqual(preview.items.count, 9)
        XCTAssertEqual(
            preview.items[0].frame,
            DisplayListPreviewRect(
                x: 69.33333333333333,
                y: 285,
                width: 263.66666666666663,
                height: 33.666666666666664
            )
        )
        guard case let .effect(_, children) = preview.items[0].value,
              case let .content(.text(text, size)) = children.first?.value else {
            return XCTFail("Expected the first effect to contain text.")
        }
        XCTAssertEqual(text, "OpenSwiftUI Example")
        XCTAssertEqual(
            size,
            DisplayListPreviewSize(
                width: 263.66666666666663,
                height: 33.666666666666664
            )
        )

        guard case let .content(.color(color)) = preview.items[2].value else {
            return XCTFail("Expected the third item to contain color.")
        }
        XCTAssertEqual(color, "#FF383CFF")

        guard case let .content(.shape(path, color, evenOdd)) = preview.items[5].value else {
            return XCTFail("Expected the sixth item to contain a shape.")
        }
        XCTAssertNil(color)
        XCTAssertFalse(evenOdd)
        XCTAssertEqual(path.commands.count, 6)
        XCTAssertEqual(path.commands.first, .move(.init(x: 60, y: 30)))
        XCTAssertEqual(path.commands.last, .close)
        XCTAssertTrue(preview.approximations.contains { $0.contains("Shape paint") })
    }

    func testDecodesEveryCoreGraphicsPathDescriptionCommand() throws {
        let description = """
        (display-list
          (item #:identity 1 #:version 1
            (frame (0 0; 120 120))
            (content-seed 1)
            (shape
              (path 0 0 m 10 10 l 20 0 30 10 q 40 0 50 20 60 10 c 70 20 t 80 10 90 20 v 100 10 110 20 y 1 2 3 4 re h)
              (paint unknown)
              (style FillStyle(isEOFilled: true, isAntialiased: true)))))
        """

        let preview = try DisplayListPreviewConverter.convert(description)
        guard case let .content(.shape(path, _, evenOdd)) = preview.items.first?.value else {
            return XCTFail("Expected a parsed shape.")
        }

        XCTAssertTrue(evenOdd)
        XCTAssertEqual(path.commands.count, 13)
        XCTAssertEqual(path.commands[0], .move(.init(x: 0, y: 0)))
        XCTAssertEqual(
            path.commands[2],
            .quad(control: .init(x: 20, y: 0), end: .init(x: 30, y: 10))
        )
        XCTAssertEqual(
            path.commands[3],
            .cubic(
                control1: .init(x: 40, y: 0),
                control2: .init(x: 50, y: 20),
                end: .init(x: 60, y: 10)
            )
        )
    }

    func testDecodesRenderableEffectsAndFallbackContent() throws {
        let description = """
        (display-list
          (item #:identity 1 #:version 1
            (frame (10 20; 100 80))
            (effect #:opacity 0.4
              (item #:version 1
                (frame (0 0; 100 80))
                (content-seed 1)
                (image #:size (100, 80)))))
          (item #:identity 2 #:version 1
            (frame (0 0; 50 50))
            (effect
              (transform affine(__C.CGAffineTransform(a: 1.0, b: 0.0, c: 0.0, d: 1.0, tx: 4.0, ty: 8.0)))
              (item #:version 1
                (frame (0 0; 50 50))
                (content-seed 1)
                (platform-view)))))
        """

        let preview = try DisplayListPreviewConverter.convert(description)
        guard case let .effect(.opacity(opacity), children) = preview.items[0].value else {
            return XCTFail("Expected opacity effect.")
        }
        XCTAssertEqual(opacity, 0.4)
        XCTAssertEqual(children.count, 1)
        XCTAssertEqual(children[0].value, .content(.image))

        guard case let .effect(.transform(transform), transformedChildren) = preview.items[1].value else {
            return XCTFail("Expected affine transform effect.")
        }
        XCTAssertEqual(transform.tx, 4)
        XCTAssertEqual(transform.ty, 8)
        XCTAssertEqual(transformedChildren[0].value, .content(.placeholder("Platform view")))
    }

    private func fixture(_ name: String, directory: String) throws -> String {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: name,
                withExtension: "txt",
                subdirectory: "Fixtures/\(directory)"
            )
        )
        return try String(contentsOf: url, encoding: .utf8)
    }
}
