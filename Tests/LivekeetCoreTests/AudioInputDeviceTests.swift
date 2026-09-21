import XCTest
@testable import LivekeetCore

final class AudioInputDeviceTests: XCTestCase {
    let devices = [
        AudioInputDevice(id: "uid-a", name: "USB Mic A", isDefault: true),
        AudioInputDevice(id: "uid-b", name: "USB Mic B", isDefault: false)
    ]

    func testResolvesIndexUIDAndExactName() throws {
        XCTAssertEqual(try AudioInputDevice.resolve("1", in: devices).id, "uid-b")
        XCTAssertEqual(try AudioInputDevice.resolve("uid-a", in: devices).id, "uid-a")
        XCTAssertEqual(try AudioInputDevice.resolve("usb mic a", in: devices).id, "uid-a")
        XCTAssertEqual(try AudioInputDevice.resolve("Mic B", in: devices).id, "uid-b")
    }

    func testRejectsAmbiguousMissingAndInvalidIndex() {
        for input in ["USB", "missing", "-1", "2", ""] {
            XCTAssertThrowsError(try AudioInputDevice.resolve(input, in: devices))
        }
    }
}
