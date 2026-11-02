import AppKit

extension DreamderWindowController {
    @IBAction func openSearchEverywhere(_ sender: Any?) {
        SearchEverywherePanelHost.shared.toggle(in: self)
    }

    @IBAction func openSearchEverywhereClasses(_ sender: Any?) {
        SearchEverywherePanelHost.shared.open(tab: .classes, in: self)
    }

    @IBAction func openSearchEverywhereFiles(_ sender: Any?) {
        SearchEverywherePanelHost.shared.open(tab: .files, in: self)
    }

    @IBAction func openSearchEverywhereSymbols(_ sender: Any?) {
        SearchEverywherePanelHost.shared.open(tab: .symbols, in: self)
    }

    @IBAction func openSearchEverywhereActions(_ sender: Any?) {
        SearchEverywherePanelHost.shared.open(tab: .actions, in: self)
    }

    @IBAction func openSearchEverywhereText(_ sender: Any?) {
        SearchEverywherePanelHost.shared.open(tab: .text, in: self)
    }
}
