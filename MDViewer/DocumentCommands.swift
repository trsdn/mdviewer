import SwiftUI

struct DocumentCommandActions {
    let canReload: Bool
    let canNavigatePrevious: Bool
    let canNavigateNext: Bool
    let canRefreshSiblingNavigation: Bool
    let canFind: Bool
    let canQuickOpen: Bool
    let canShowOutline: Bool
    let canToggleFolderNavigator: Bool
    let canChooseFolderNavigatorRoot: Bool
    let canRevealInFolderNavigator: Bool
    let reload: () -> Void
    let navigatePrevious: () -> Void
    let navigateNext: () -> Void
    let refreshSiblingNavigation: () -> Void
    let showFind: () -> Void
    let findNext: () -> Void
    let findPrevious: () -> Void
    let showQuickOpen: () -> Void
    let showOutline: () -> Void
    let toggleFolderNavigator: () -> Void
    let chooseFolderNavigatorRoot: () -> Void
    let revealInFolderNavigator: () -> Void
    let printDocument: () -> Void
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
        CommandGroup(after: .newItem) {
            Button("Open Folder…") {
                actions?.chooseFolderNavigatorRoot()
            }
            .disabled(actions?.canChooseFolderNavigatorRoot != true)
        }

        CommandGroup(replacing: .printItem) {
            Button("Print…") {
                actions?.printDocument()
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(actions == nil)
        }

        CommandGroup(after: .textEditing) {
            Button("Find…") {
                actions?.showFind()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(actions?.canFind != true)

            Button("Find Next") {
                actions?.findNext()
            }
            .keyboardShortcut("g", modifiers: .command)
            .disabled(actions?.canFind != true)

            Button("Find Previous") {
                actions?.findPrevious()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(actions?.canFind != true)
        }

        CommandGroup(after: .toolbar) {
            Button("Folder Navigator") {
                actions?.toggleFolderNavigator()
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .disabled(actions?.canToggleFolderNavigator != true)

            Button("Reveal Current Document in Folder Navigator") {
                actions?.revealInFolderNavigator()
            }
            .disabled(actions?.canRevealInFolderNavigator != true)

            Divider()

            Button("Quick Open…") {
                actions?.showQuickOpen()
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(actions?.canQuickOpen != true)

            Button("Document Outline") {
                actions?.showOutline()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(actions?.canShowOutline != true)

            Divider()

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
