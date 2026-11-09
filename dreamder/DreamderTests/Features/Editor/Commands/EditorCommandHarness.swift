import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Testing
@testable import Dreamder

@MainActor
struct EditorCommandHarness {
    let fixture: HostedSourceEditorFixture
    let hosted: HostedSourceEditor
    let controller: TextViewController
    let textView: TextView

    var actions: EditorActionCoordinator {
        fixture.editorInstance.actions
    }

    var text: String {
        textView.string
    }

    var selections: [NSRange] {
        textView.selectionManager.textSelections.map(\.range).sorted { $0.location < $1.location }
    }

    var rendered: String {
        EditorMarkup(text: text, selections: selections).rendered
    }

    static func open(
        in directory: URL,
        fileName: String = "Sample.txt",
        markup: String,
        isEditable: Bool = true
    ) async throws -> Self {
        let parsed = EditorMarkup(markup)
        let fixture = try HostedSourceEditorFixture.make(
            in: directory,
            fileName: fileName,
            typeIdentifier: "public.plain-text",
            contents: parsed.text
        )
        let hosted = fixture.host(
            coordinators: [fixture.editorInstance.rangeTranslator],
            size: NSSize(width: 900, height: 600)
        )
        try await eventually { hosted.controller?.textView?.window === hosted.window }
        let controller = try #require(hosted.controller)
        let textView = try #require(controller.textView)
        textView.isEditable = true
        textView.replaceCharacters(in: NSRange(location: 0, length: textView.textStorage.length), with: parsed.text)
        textView.selectionManager.setSelectedRanges(parsed.selections)
        textView.isEditable = isEditable
        return Self(fixture: fixture, hosted: hosted, controller: controller, textView: textView)
    }

    func setSelections(_ ranges: [NSRange]) {
        textView.selectionManager.setSelectedRanges(ranges)
    }

    func close() {
        hosted.close()
    }
}
