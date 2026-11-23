import XCTest
@testable import LumiCamera

final class CameraProfileTests: XCTestCase {
    func testLibraryHasProfilesAndUniqueIdentifiers() {
        XCTAssertGreaterThanOrEqual(ProfileLibrary.all.count, 10)
        XCTAssertEqual(Set(ProfileLibrary.all.map(\.id)).count, ProfileLibrary.all.count)
    }
    func testAspectRatiosArePositive() {
        for aspect in AspectOption.allCases { XCTAssertGreaterThan(aspect.ratio, 0) }
    }
    func testProfilesCanRoundTripCodable() throws {
        let profile = try XCTUnwrap(ProfileLibrary.all.first)
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(CameraProfile.self, from: data)
        XCTAssertEqual(profile, decoded)
    }
}
