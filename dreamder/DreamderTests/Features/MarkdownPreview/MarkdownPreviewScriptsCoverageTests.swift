import Testing
@testable import Dreamder

@Suite
struct MarkdownPreviewScriptsCoverageTests {
    @Test
    func replaceBodyScriptEmbedsTheBodyLiteralAndTheFollowFlag() {
        #expect(
            MarkdownPreviewScripts.replaceBodyScript(bodyLiteral: "\"<p>x</p>\"", follow: true)
                == "window.dreamderPreview && window.dreamderPreview.replaceBody(\"<p>x</p>\", true);"
        )
        #expect(
            MarkdownPreviewScripts.replaceBodyScript(bodyLiteral: "\"\"", follow: false)
                == "window.dreamderPreview && window.dreamderPreview.replaceBody(\"\", false);"
        )
    }

    @Test
    func anchorScriptEmbedsTheIdentifierLiteral() {
        #expect(
            MarkdownPreviewScripts.anchorScript(identifierLiteral: "\"intro\"")
                == "window.dreamderPreview && window.dreamderPreview.scrollToAnchor(\"intro\");"
        )
    }

    @Test
    func pageScriptInstallsTheEntryPointsOnce() {
        #expect(MarkdownPreviewScripts.pageScript.contains("window.dreamderPreview = {"))
        #expect(MarkdownPreviewScripts.pageScript.contains("var FOLLOW_TIME_MS = 40;"))
        #expect(MarkdownPreviewScripts.pageScript.contains("var ATTRIBUTE = \"md-src-pos\";"))
    }
}
