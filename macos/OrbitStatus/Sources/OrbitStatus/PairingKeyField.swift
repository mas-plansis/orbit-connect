import AppKit
import SwiftUI

struct PairingKeyField: View {
    @Binding var text: String
    let submit: () -> Void

    private let accent = OrbitConnectTheme.accent
    private let border = OrbitConnectTheme.border
    private let ink = OrbitConnectTheme.ink

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "key.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: 18, height: 18)

            SecurePairingKeyTextField(text: $text, submit: submit)
                .frame(maxWidth: .infinity, minHeight: 24)

            Button(action: paste) {
                Label("Вставить", systemImage: "doc.on.clipboard")
                    .font(OrbitConnectTheme.compactFont)
            }
            .buttonStyle(.plain)
            .foregroundStyle(accent)
            .help("Вставить ключ из буфера обмена")
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(OrbitConnectTheme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(border))
    }

    private func paste() {
        guard let value = NSPasteboard.general.string(forType: .string) else { return }
        text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct SecurePairingKeyTextField: NSViewRepresentable {
    @Binding var text: String
    let submit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, submit: submit)
    }

    func makeNSView(context: Context) -> NSSecureTextField {
        let field = NSSecureTextField()
        field.delegate = context.coordinator
        field.placeholderString = "Ключ связи"
        field.font = NSFont.systemFont(ofSize: 14)
        field.textColor = NSColor.labelColor
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.lineBreakMode = .byTruncatingMiddle
        field.maximumNumberOfLines = 1
        field.target = context.coordinator
        field.action = #selector(Coordinator.submitField)
        return field
    }

    func updateNSView(_ field: NSSecureTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding private var text: String
        private let submit: () -> Void

        init(text: Binding<String>, submit: @escaping () -> Void) {
            _text = text
            self.submit = submit
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text = field.stringValue
        }

        @objc func submitField() {
            submit()
        }
    }
}
