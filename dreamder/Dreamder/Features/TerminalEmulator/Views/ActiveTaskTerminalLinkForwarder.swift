import Foundation
import SwiftTerm

final class ActiveTaskTerminalLinkForwarder: TerminalViewDelegate {
    private weak var view: CEActiveTaskTerminalView?

    init(view: CEActiveTaskTerminalView) {
        self.view = view
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        view?.sizeChanged(source: source, newCols: newCols, newRows: newRows)
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        view?.setTerminalTitle(source: source, title: title)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        view?.hostCurrentDirectoryUpdate(source: source, directory: directory)
    }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        view?.send(source: source, data: data)
    }

    func scrolled(source: TerminalView, position: Double) {
        view?.scrolled(source: source, position: position)
    }

    func clipboardCopy(source: TerminalView, content: Data) {
        view?.clipboardCopy(source: source, content: content)
    }

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
        view?.rangeChanged(source: source, startY: startY, endY: endY)
    }

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        view?.openConsoleLink(link: link, params: params)
    }
}
