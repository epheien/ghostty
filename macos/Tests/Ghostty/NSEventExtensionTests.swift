@testable import Ghostty
import AppKit
import Testing

struct NSEventExtensionTests {
    @Test func unshiftedCodepointPrefersTranslatedCharacter() {
        #expect(
            NSEvent.ghosttyUnshiftedCodepoint(
                translated: "a",
                shortcutFallback: "z"
            ) == 0x61
        )
    }

    @Test func unshiftedCodepointUsesShortcutFallback() {
        #expect(
            NSEvent.ghosttyUnshiftedCodepoint(
                translated: nil,
                shortcutFallback: "a"
            ) == 0x61
        )
    }

    @Test(arguments: ["", "ab", "👨‍👩‍👧‍👦"])
    func unshiftedCodepointRejectsNonScalarFallback(_ fallback: String) {
        #expect(
            NSEvent.ghosttyUnshiftedCodepoint(
                translated: nil,
                shortcutFallback: fallback
            ) == 0
        )
    }
}
