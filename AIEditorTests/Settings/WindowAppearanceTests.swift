import Testing
import UIKit
@testable import AIEditor

struct WindowAppearanceTests {
    @Test func systemFollowsTheSystemStyle() {
        #expect(AppearancePreference.light.interfaceStyle == .light)
        #expect(AppearancePreference.dark.interfaceStyle == .dark)
        #expect(AppearancePreference.system.interfaceStyle == .unspecified)
    }
}
