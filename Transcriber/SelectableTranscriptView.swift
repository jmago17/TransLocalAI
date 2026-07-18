#if os(iOS)
import SwiftUI
import UIKit

/// Read-only transcript text whose selection edit menu offers "Replace & Save":
/// select a misheard word, enter the correct spelling, and the fix is applied
/// everywhere and remembered in the vocabulary for future transcriptions.
struct SelectableTranscriptView: UIViewRepresentable {
    let text: String
    var onReplaceAndSave: (String) -> Void

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.delegate = context.coordinator
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text {
            view.text = text
        }
        context.coordinator.onReplaceAndSave = onReplaceAndSave
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: fitted.height)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onReplaceAndSave: onReplaceAndSave)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onReplaceAndSave: (String) -> Void

        init(onReplaceAndSave: @escaping (String) -> Void) {
            self.onReplaceAndSave = onReplaceAndSave
        }

        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            guard range.length > 0 else { return nil }
            let selected = (textView.text as NSString)
                .substring(with: range)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !selected.isEmpty, !selected.contains("\n") else { return nil }

            let replace = UIAction(
                title: "Replace & Save",
                image: UIImage(systemName: "character.magnify")
            ) { [weak self] _ in
                self?.onReplaceAndSave(selected)
            }
            return UIMenu(children: suggestedActions + [replace])
        }
    }
}
#endif
