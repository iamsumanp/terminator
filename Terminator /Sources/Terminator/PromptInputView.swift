import SwiftUI
import AppKit

struct PromptInputView: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let onSend: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused, onSend: onSend)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder

        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.backgroundColor = .clear
        textView.textColor = NSColor.white.withAlphaComponent(0.95)
        textView.insertionPointColor = .white
        textView.font = .systemFont(ofSize: 15, weight: .regular)
        textView.textContainerInset = NSSize(width: 2, height: 8)
        context.coordinator.textView = textView
        textView.string = text
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        if textView.string != text {
            textView.string = text
        }

        if isFocused, textView.window?.firstResponder != textView {
            textView.window?.makeFirstResponder(textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var isFocused: Bool
        let onSend: () -> Void
        weak var textView: NSTextView?

        init(text: Binding<String>, isFocused: Binding<Bool>, onSend: @escaping () -> Void) {
            self._text = text
            self._isFocused = isFocused
            self.onSend = onSend
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            text = textView.string
        }

        func textDidBeginEditing(_ notification: Notification) {
            isFocused = true
        }

        func textDidEndEditing(_ notification: Notification) {
            isFocused = false
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if NSEvent.modifierFlags.contains(.shift) {
                    return false
                }
                onSend()
                return true
            }
            return false
        }
    }
}
