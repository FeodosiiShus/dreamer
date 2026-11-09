import SwiftUI

struct StatusBarProgressBar: View {
    let notification: TaskNotificationModel

    var body: some View {
        if let fraction = StatusBarProgressModel.fraction(of: notification) {
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .controlSize(.small)
        } else if StatusBarProgressModel.isIndeterminate(notification) {
            ProgressView()
                .progressViewStyle(.linear)
                .controlSize(.small)
        }
    }
}

struct StatusBarProgressPopover: View {
    let notifications: [TaskNotificationModel]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(notifications, id: \.id) { notification in
                VStack(alignment: .leading, spacing: 3) {
                    Text(notification.title)
                        .font(Islands.uiFont)
                        .foregroundStyle(Islands.foreground)
                        .lineLimit(1)
                    if let message = notification.message {
                        Text(message)
                            .font(Islands.smallFont)
                            .foregroundStyle(Islands.secondaryForeground)
                            .lineLimit(2)
                    }
                    StatusBarProgressBar(notification: notification)
                }
            }
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
        .accessibilityIdentifier("StatusBarProgressPopover")
    }
}

struct StatusBarProgressIndicator: View {
    let handler: TaskNotificationHandler

    @State private var presenter: StatusBarProgressPresenter

    init(handler: TaskNotificationHandler, presenter: StatusBarProgressPresenter = StatusBarProgressPresenter()) {
        self.handler = handler
        self._presenter = State(initialValue: presenter)
    }

    var model: StatusBarProgressModel {
        StatusBarProgressModel(notifications: handler.notifications)
    }

    var popoverBinding: Binding<Bool> {
        Binding(
            get: { presenter.isPresented(hasNotifications: !model.isEmpty) },
            set: presenter.setPresented
        )
    }

    func popoverContent() -> some View {
        StatusBarProgressPopover(notifications: model.entries)
    }

    var body: some View {
        let current = model
        Group {
            if let first = current.first {
                Button(action: presenter.toggle) {
                    HStack(spacing: 6) {
                        Text(first.title)
                            .font(Islands.smallFont)
                            .foregroundStyle(Islands.secondaryForeground)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 200, alignment: .trailing)
                        StatusBarProgressBar(notification: first)
                            .frame(width: 60)
                        if let counter = current.counterText {
                            Text(counter)
                                .font(Islands.smallFont)
                                .foregroundStyle(Islands.secondaryForeground)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(current.summaryHelp)
                .popover(isPresented: popoverBinding, arrowEdge: .top, content: popoverContent)
                .accessibilityIdentifier("StatusBarProgress")
            }
        }
        .onChange(of: current.isEmpty, presenter.emptinessChanged)
    }
}
