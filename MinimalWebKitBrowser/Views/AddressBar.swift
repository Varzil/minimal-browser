import SwiftUI

// MARK: - AddressBar
//
// A single combined "search or URL" field. Tracks the active tab's URL but
// lets the user type freely; syncing pauses while focused so typing isn't
// clobbered mid-keystroke by page URL updates.
//
// Auto-focuses when:
//   • A new blank tab is created (via focusAddressBarRequest from TabManager)
//   • The user clicks the field

struct AddressBar: View {
    let tab: Tab?
    let onSubmit: (String) -> Void

    /// External focus trigger: when this changes, the field focuses.
    let focusTrigger: Int

    @State private var text: String = ""
    @FocusState private var focused: Bool

    private var secure: Bool { tab?.isSecure ?? false }
    private var isBlankTab: Bool { tab?.pendingURL == nil }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: secure ? "lock.fill" : "magnifyingglass")
                .foregroundStyle(secure ? .green : .secondary)
                .font(.system(size: 11))
                .accessibilityHidden(true)

            TextField("Search or enter address", text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .font(.system(size: 14))
                .onSubmit {
                    onSubmit(text)
                    focused = false
                }
                .accessibilityLabel("Address bar")

            if !text.isEmpty {
                Button {
                    text = ""
                    focused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.background.opacity(0.6))
                .strokeBorder(.tertiary, lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onTapGesture { focused = true }
        // Auto-focus when a new tab is created (focusTrigger increments).
        .onChange(of: focusTrigger) { _, _ in
            text = ""
            focused = true
        }
        // Sync from the tab only when the user isn't actively editing.
        .onChange(of: tab?.displayURL) { _, newValue in
            if !focused { text = newValue ?? "" }
        }
        .onAppear {
            if isBlankTab { focused = true }
            if !focused { text = tab?.displayURL ?? "" }
        }
        .onChange(of: tab?.id) { _, _ in
            // Switching tabs refreshes the field to the new tab's URL.
            if !focused { text = tab?.displayURL ?? "" }
            // Auto-focus if the new tab is blank (just created).
            if isBlankTab { focused = true }
        }
    }
}
