import Foundation
import Testing
@testable import AIEditor

struct VoiceSelectionTests {
    private let voices = [
        VoiceInfo(identifier: "en-US.standard", language: "en-US", quality: .standard),
        VoiceInfo(identifier: "en-GB.premium", language: "en-GB", quality: .premium),
        VoiceInfo(identifier: "en-US.enhanced", language: "en-US", quality: .enhanced),
        VoiceInfo(identifier: "ru-RU.standard", language: "ru-RU", quality: .standard),
        VoiceInfo(identifier: "ru-RU.enhanced", language: "ru-RU", quality: .enhanced),
    ]
    private let english = "The weather is lovely today, so let's go for a long walk in the park."
    private let russian = "Сегодня отличная погода, давайте прогуляемся по парку подольше."

    @Test func detectsLanguageOfText() {
        #expect(VoiceSelection.language(of: english) == "en")
        #expect(VoiceSelection.language(of: russian) == "ru")
    }

    @Test func russianTextGetsRussianVoiceRegardlessOfUserLocale() {
        let voice = VoiceSelection.voice(for: russian, among: voices, userLocale: Locale(identifier: "en_US"))
        #expect(voice?.identifier == "ru-RU.enhanced")
    }

    @Test func prefersUserRegionOverQuality() {
        let voice = VoiceSelection.voice(for: english, among: voices, userLocale: Locale(identifier: "en_US"))
        #expect(voice?.identifier == "en-US.enhanced")
    }

    @Test func prefersBestQualityWhenRegionDoesNotMatch() {
        let voice = VoiceSelection.voice(for: english, among: voices, userLocale: Locale(identifier: "ru_RU"))
        #expect(voice?.identifier == "en-GB.premium")
    }

    @Test func undeterminedTextFallsBackToUserLanguage() {
        let voice = VoiceSelection.voice(for: "42", among: voices, userLocale: Locale(identifier: "ru_RU"))
        #expect(voice?.language == "ru-RU")
    }

    @Test func noVoiceForLanguageReturnsNil() {
        let german = "Das Wetter ist heute wunderschön, lass uns lange im Park spazieren gehen."
        #expect(VoiceSelection.voice(for: german, among: voices, userLocale: Locale(identifier: "en_US")) == nil)
    }
}
