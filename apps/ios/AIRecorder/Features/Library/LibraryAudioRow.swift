import SwiftUI
import UIKit

struct LibraryAudioRow: View {
    let item: AudioItem
    let locale: Locale
    let isSelecting: Bool
    let isSelected: Bool
    let onToggle: () -> Void
    let onOpen: () -> Void
    let onSelectionDragChanged: (CGPoint, CGPoint) -> Void
    let onSelectionDragEnded: () -> Void
    let duration: (Int) -> String
    let state: (AudioItem) -> LibraryAudioStatus

    var body: some View {
        HStack(spacing: 12) {
            if isSelecting {
                selectionControl
            }

            Button {
                guard !isSelecting else { return }
                onOpen()
            } label: {
                VStack(alignment: .leading) {
                    Text(item.displayTitle(locale: locale))
                    HStack {
                        Text(duration(item.durationMilliseconds))
                        Text(shortLibraryDate(item.startedAt, locale: locale))
                        Spacer()
                        libraryStatus(state(item))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func libraryStatus(_ status: LibraryAudioStatus) -> some View {
        if let symbolNames = status.locationSymbolNames {
            HStack(spacing: 4) {
                ForEach(symbolNames, id: \.self) { symbolName in
                    Image(systemName: symbolName)
                        .accessibilityHidden(true)
                }
            }
            .symbolRenderingMode(.monochrome)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(status.localizedString))
        } else {
            Text(status.localizedString)
        }
    }

    private var selectionControl: some View {
        LibrarySelectionControl(
            identifier: "library-selection-\(item.id.uuidString)",
            title: item.displayTitle(locale: locale),
            isSelected: isSelected,
            onToggle: onToggle,
            onDragChanged: onSelectionDragChanged,
            onDragEnded: onSelectionDragEnded
        )
        .frame(width: 44, height: 44)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: LibrarySelectionControlFramesPreferenceKey.self,
                    value: [item.id: proxy.frame(in: .global)]
                )
            }
        }
    }
}

func shortLibraryDate(_ date: Date, locale: Locale) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.dateFormat = locale.language.languageCode?.identifier == "es" ? "dd/MM/yy" : "MM/dd/yy"
    return formatter.string(from: date)
}

private struct LibrarySelectionControl: UIViewRepresentable {
    let identifier: String
    let title: String
    let isSelected: Bool
    let onToggle: () -> Void
    let onDragChanged: (CGPoint, CGPoint) -> Void
    let onDragEnded: () -> Void

    func makeUIView(context: Context) -> SelectionControlView {
        let view = SelectionControlView()
        view.onToggle = onToggle
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        return view
    }

    func updateUIView(_ view: SelectionControlView, context: Context) {
        view.onToggle = onToggle
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        view.configure(identifier: identifier, title: title, isSelected: isSelected)
    }

    final class SelectionControlView: UIView, UIGestureRecognizerDelegate {
        let button = UIButton(type: .system)
        let panGesture: UIPanGestureRecognizer
        var onToggle: (() -> Void)?
        var onDragChanged: ((CGPoint, CGPoint) -> Void)?
        var onDragEnded: (() -> Void)?
        private var dragStartLocation: CGPoint?

        override init(frame: CGRect) {
            panGesture = UIPanGestureRecognizer()
            super.init(frame: frame)

            button.translatesAutoresizingMaskIntoConstraints = false
            button.addTarget(self, action: #selector(toggle), for: .touchUpInside)
            addSubview(button)
            NSLayoutConstraint.activate([
                button.leadingAnchor.constraint(equalTo: leadingAnchor),
                button.trailingAnchor.constraint(equalTo: trailingAnchor),
                button.topAnchor.constraint(equalTo: topAnchor),
                button.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])

            panGesture.delegate = self
            panGesture.cancelsTouchesInView = true
            panGesture.addTarget(self, action: #selector(handlePan(_:)))
            addGestureRecognizer(panGesture)
        }

        required init?(coder: NSCoder) { nil }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            var ancestor = superview
            while let view = ancestor {
                if let scrollView = view as? UIScrollView {
                    scrollView.panGestureRecognizer.require(toFail: panGesture)
                    return
                }
                ancestor = view.superview
            }
        }

        func configure(identifier: String, title: String, isSelected: Bool) {
            let imageName = isSelected ? "checkmark.circle.fill" : "circle"
            button.setImage(UIImage(systemName: imageName), for: .normal)
            button.tintColor = isSelected ? .tintColor : .secondaryLabel
            button.accessibilityIdentifier = identifier
            button.accessibilityLabel = "Select \(title)"
            button.accessibilityValue = isSelected ? "Selected" : "Not selected"
        }

        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            let velocity = panGesture.velocity(in: self)
            return abs(velocity.y) > abs(velocity.x)
        }

        @objc private func toggle() {
            onToggle?()
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            let location = gesture.location(in: nil)
            switch gesture.state {
            case .began:
                dragStartLocation = location
                onDragChanged?(location, location)
            case .changed:
                guard let dragStartLocation else { return }
                onDragChanged?(dragStartLocation, location)
            case .ended, .cancelled, .failed:
                dragStartLocation = nil
                onDragEnded?()
            default:
                break
            }
        }
    }
}
