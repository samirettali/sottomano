import SwiftUI

/// The panel asks for one line of text. Drawn rather than an NSTextField: the
/// launcher already reads every key itself, and a text field in a borderless
/// panel would only add a first responder to fight with.
struct PromptView: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Style.font(size: Style.size - 5))
                .foregroundStyle(Style.text.opacity(0.7))

            Text(text + "|")
                .font(Style.font())
                .foregroundStyle(Style.text)
        }
        .frame(width: 520, alignment: .leading)
        .chrome()
    }
}
