import SwiftUI

struct DocumentCommandActions {
    let canReload: Bool
    let canNavigatePrevious: Bool
    let canNavigateNext: Bool
    let canRefreshSiblingNavigation: Bool
    let reload: () -> Void
    let navigatePrevious: () -> Void
    let navigateNext: () -> Void
    let refreshSiblingNavigation: () -> Void
    let zoomIn: () -> Void
    let zoomOut: () -> Void
    let zoomReset: () -> Void
}

private struct DocumentCommandActionsKey: FocusedValueKey {
    typealias Value = DocumentCommandActions
}

extension FocusedValues {
    var documentCommandActions: DocumentCommandActions? {
        get { self[DocumentCommandActionsKey.self] }
        set { self[DocumentCommandActionsKey.self] = newValue }
    }
}

struct DocumentCommands: Commands {
    @FocusedValue(\.documentCommandActions) private var actions

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Previous Markdown File") {
                actions?.navigatePrevious()
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            .disabled(actions?.canNavigatePrevious != true)

            Button("Next Markdown File") {
                actions?.navigateNext()
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            .disabled(actions?.canNavigateNext != true)

            Button("Refresh Sibling Navigation…") {
                actions?.refreshSiblingNavigation()
            }
            .disabled(actions?.canRefreshSiblingNavigation != true)

            Divider()

            Button("Reload") {
                actions?.reload()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(actions?.canReload != true)

            Divider()

            Button("Zoom In") {
                actions?.zoomIn()
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(actions == nil)

            Button("Zoom Out") {
                actions?.zoomOut()
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(actions == nil)

            Button("Actual Size") {
                actions?.zoomReset()
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(actions == nil)
        }
    }
}
