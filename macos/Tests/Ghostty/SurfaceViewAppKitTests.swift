@testable import Ghostty
import AppKit
import Testing

struct SurfaceViewAppKitTests {
    @Test(arguments: [
        ("\u{0008}", true),
        ("\u{001F}", true),
        ("\u{007F}", false),
        (" ", false),
        ("h", false),
        ("", false),
        ("\u{0009}x", false),
        ("\u{0009}\u{0009}", false),
    ])
    func suppressesOnlySingleC0ControlTextWhileComposing(
        text: String,
        expected: Bool
    ) {
        #expect(
            Ghostty.SurfaceView.shouldSuppressComposingControlInput(
                text,
                composing: true
            ) == expected
        )
    }

    @Test func doesNotSuppressControlTextWhenNotComposing() {
        #expect(
            Ghostty.SurfaceView.shouldSuppressComposingControlInput(
                "\u{0008}",
                composing: false
            ) == false
        )
    }

    @Test func doesNotSuppressMissingText() {
        #expect(
            Ghostty.SurfaceView.shouldSuppressComposingControlInput(
                nil,
                composing: true
            ) == false
        )
    }

    @Test(arguments: [
        NSEvent.ModifierFlags.control,
        NSEvent.ModifierFlags.command,
        NSEvent.ModifierFlags([.control, .shift]),
        NSEvent.ModifierFlags([.command, .shift]),
    ])
    func bypassesInputMethodForNonTextShortcutModifiers(
        modifiers: NSEvent.ModifierFlags
    ) {
        #expect(
            Ghostty.SurfaceView.shouldBypassInputMethod(
                eventModifiers: modifiers,
                translationModifiers: modifiers,
                hasMarkedText: false
            )
        )
    }

    @Test func bypassesInputMethodForOptionTranslatedToAlt() {
        #expect(
            Ghostty.SurfaceView.shouldBypassInputMethod(
                eventModifiers: .option,
                translationModifiers: [],
                hasMarkedText: false
            )
        )
    }

    @Test func preservesInputMethodForTextProducingOption() {
        #expect(
            Ghostty.SurfaceView.shouldBypassInputMethod(
                eventModifiers: .option,
                translationModifiers: .option,
                hasMarkedText: false
            ) == false
        )
    }

    @Test func preservesInputMethodWhileComposing() {
        #expect(
            Ghostty.SurfaceView.shouldBypassInputMethod(
                eventModifiers: [.control, .option, .command],
                translationModifiers: [.control, .option, .command],
                hasMarkedText: true
            ) == false
        )
    }
}
