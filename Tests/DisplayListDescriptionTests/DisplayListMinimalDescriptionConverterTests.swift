import XCTest
@testable import DisplayListDescription

final class DisplayListMinimalDescriptionConverterTests: XCTestCase {
    func testReconstructsDescriptionWithExplicitLossPlaceholders() throws {
        let minimalDescription = "(DL(I:7 C)(I:8(E O(I:9 T))))"

        let result = try DisplayListMinimalDescriptionConverter.convert(minimalDescription)

        XCTAssertEqual(
            result.description,
            """
            (display-list
              (item #:identity 7 #:version ?
                (frame (? ?; ? ?))
                (content-seed ?)
                (color ?))
              (item #:identity 8 #:version ?
                (frame (? ?; ? ?))
                (effect #:opacity ?
                  (item #:identity 9 #:version ?
                    (frame (? ?; ? ?))
                    (content-seed ?)
                    (text ? #:size (?, ?))))))
            """
        )
        XCTAssertEqual(
            try DisplayListDescriptionConverter.convert(result.description).minimalDescription,
            minimalDescription
        )
        XCTAssertTrue(result.description.contains("?"))
        XCTAssertEqual(Set(result.spans.map(\.occurrenceID)).count, result.spans.count)
    }

    func testRoundTripsEverySupportedMinimalEncoding() throws {
        let minimalDescription = """
        (DL(I:0)(I:0 B)(I:2 C)(I:0 CH)(I:0 IM)(I:0 S)(I:0 SH)(I:0 PV)(I:0 PL)(I:0 T)(I:0(F(I:0 C)))(I:0 D)(I:0 V:EmptyViewFactory)(I:0 @#7)(I:0(E))(I:0(E GG))(I:0(E CG))(I:0(E BG))(I:0(E A:nil))(I:0(E PR))(I:0(E PG))(I:0(E O))(I:0(E B))(I:0(E C))(I:0(E M))(I:0(E T))(I:0(E F))(I:0(E AN))(I:0(E TR))(I:0(E(V:EmptyViewFactory)))(I:0(E AX))(I:0(E PL))(I:0(E H:#abc))(I:0(E IR))(I:0(E IL))(I:0(E IA))(I:0(states(#abc(I:0 C)))))
        """

        let reconstructed = try DisplayListMinimalDescriptionConverter.convert(minimalDescription)
        let roundTrip = try DisplayListDescriptionConverter.convert(reconstructed.description)

        XCTAssertEqual(roundTrip.minimalDescription, minimalDescription)
        XCTAssertEqual(roundTrip.usedEncodingIDs, reconstructed.usedEncodingIDs)
        XCTAssertTrue(reconstructed.description.contains("(effect *)"))
        XCTAssertTrue(reconstructed.description.contains("#:properties *"))
        XCTAssertTrue(reconstructed.description.contains("(platform *)"))
    }

    func testRoundTripsContentViewIPhone17ProFixture() throws {
        let minimalDescription = try fixture(
            "DisplayList.minimalDescription",
            in: "ContentView-iPhone-17-Pro"
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        let reconstructed = try DisplayListMinimalDescriptionConverter.convert(minimalDescription)
        let roundTrip = try DisplayListDescriptionConverter.convert(reconstructed.description)

        XCTAssertEqual(roundTrip.minimalDescription, minimalDescription)
        XCTAssertEqual(
            reconstructed.description.components(separatedBy: "(item ").count - 1,
            12
        )
    }

    func testRejectsNonMinimalDescriptionRoot() {
        XCTAssertThrowsError(try DisplayListMinimalDescriptionConverter.convert("(display-list)")) { error in
            XCTAssertEqual(
                error as? DisplayListDescriptionError,
                .expectedMinimalDescription(actual: "a list")
            )
        }
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
