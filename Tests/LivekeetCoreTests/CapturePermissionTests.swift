import Foundation
import ScreenCaptureKit
import XCTest
@testable import LivekeetCore

final class CapturePermissionTests: XCTestCase {
    func testScreenCaptureDenialOffersTheMatchingPrivacySettings() throws {
        let error = NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue)
        let translated = try XCTUnwrap(CaptureError.translatingScreenCaptureError(error) as? CaptureError)
        XCTAssertEqual(translated.privacySettingsURL?.absoluteString,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        XCTAssertTrue(translated.localizedDescription.contains("System audio access is blocked"))
        XCTAssertEqual(CaptureError.microphonePermissionDenied.privacySettingsURL?.absoluteString,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        XCTAssertNil(CaptureError.noDisplay.privacySettingsURL)
    }

    func testOtherCaptureErrorsAreNotMisreportedAsPermissionDenials() {
        for error in [NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.failedToStart.rawValue),
                      NSError(domain: "OtherSubsystem", code: SCStreamError.Code.userDeclined.rawValue)] {
            let result = CaptureError.translatingScreenCaptureError(error) as NSError
            XCTAssertEqual(result.domain, error.domain)
            XCTAssertEqual(result.code, error.code)
        }
    }
}
