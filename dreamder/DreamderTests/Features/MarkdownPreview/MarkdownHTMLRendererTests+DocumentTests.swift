import Foundation
import Testing
@testable import Dreamder

extension MarkdownHTMLRendererTests {
    @Test
    func documentEmbedsBaseURLBodyAndStylesheet() {
        let baseURL = URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        let document = MarkdownHTMLRenderer.documentHTML(
            body: "<p>hi</p>",
            baseURL: baseURL,
            palette: MarkdownPreviewFixtures.darkPalette
        )
        #expect(document.contains("<base href=\"file:///tmp/project/\">"))
        #expect(document.contains("<p>hi</p>"))
        #expect(document.contains("font: 0.9em \"JetBrains Mono\""))
        #expect(document.contains("<style>"))
    }

    @Test
    func documentWithoutBaseURL() {
        let document = MarkdownHTMLRenderer.documentHTML(
            body: "<p>hi</p>",
            baseURL: nil,
            palette: MarkdownPreviewFixtures.darkPalette
        )
        #expect(!document.contains("<base"))
        #expect(document.contains("<p>hi</p>"))
    }

    @Test
    func emptyDocument() {
        #expect(plainHTML("") == "")
    }

    @Test
    func exclamationMarkOutsideImageTerminates() {
        let markdown = "Don't be shy, jump right in and be part of the discussion!"
        let html = plainHTML(markdown)
        #expect(html == "<p>Don't be shy, jump right in and be part of the discussion!</p>")
    }

    @Test
    func exclamationMarkBeforeLinkTerminates() {
        let html = plainHTML("Hello! [link](a.md) and ![img](i.png) and !")
        #expect(html == "<p>Hello! <a href=\"a.md\">link</a> and <img src=\"i.png\" alt=\"img\" /> and !</p>")
    }

    @Test
    func admonitionMarkerTerminates() {
        let html = plainHTML("> [!IMPORTANT]\n> Not for production.")
        #expect(html == "<blockquote>\n<p>[!IMPORTANT]\nNot for production.</p>\n</blockquote>")
    }

    @Test
    func readmeHeaderRenders() {
        let markdown = """
        <p align="center">
          <img src="https://github.com/FeodosiiShus/dreamer/blob/main/\
        .github/Dreamder-Icon-128@2x.png?raw=true" height="128">
          <h1 align="center">Dreamder for macOS</h1>
        </p>

        <p align="center">
          <a aria-label="Follow Dreamder on X" href="https://x.com/DreamderApp" target="_blank">
            <img alt="" src="https://img.shields.io/badge/Follow%20@DreamderApp-black.svg?style=for-the-badge&logo=X">
          </a>
        </p>

        [![GitHub release](https://img.shields.io/github/v/release/FeodosiiShus/dreamer?color=orange\
        &label=latest%20release&sort=semver&style=flat-square)\
        ](https://github.com/FeodosiiShus/dreamer/releases/latest)

        > [!IMPORTANT]
        > Dreamder is currently in development and not yet recommended for production use, however you can \
        take part in shaping it's future by test-driving \
        [pre-release versions](https://github.com/FeodosiiShus/dreamer/releases) and \
        [submitting an issue](https://github.com/FeodosiiShus/dreamer/issues) to let us know what you think.

        ## Table of Contents

        - [Motivation](#motivation)
        - [Mission](#mission)
        """
        let html = plainHTML(markdown)

        #expect(!html.isEmpty)
        #expect(html.contains("<p align=\"center\">"))
        let iconSource = "https://github.com/FeodosiiShus/dreamer/blob/main/.github/Dreamder-Icon-128@2x.png?raw=true"
        #expect(html.contains("<img src=\"" + iconSource + "\" height=\"128\">"))
        #expect(html.contains("<h1 align=\"center\">Dreamder for macOS</h1>"))
        #expect(html.contains("<a aria-label=\"Follow Dreamder on X\" href=\"https://x.com/DreamderApp\">"))
        #expect(!html.contains("target="))
        #expect(!html.contains("&lt;p align="))
        #expect(html.contains("<blockquote>"))
        #expect(html.contains("<h2>Table of Contents</h2>"))
        #expect(html.contains("<li><a href=\"#motivation\">Motivation</a></li>"))
    }

    @Test
    func readmeCommunityParagraphRenders() {
        let markdown = """
        Join our growing community on [Discord](https://discord.gg/vChUXVf9Em) and \
        [GitHub Discussions](https://github.com/orgs/DreamderApp/discussions) where we discuss and \
        collaborate on all things Dreamder. Don't be shy, jump right in and be part of the discussion!

        > [!NOTE]
        > We hold a weekly meetup on Discord **every Saturday at 3pm UTC** where we discuss latests \
        development, feature requests, goals, and priorities.
        >
        > [**Join us**](https://discord.gg/KvdE3wYKNR?event=1189275961456336937)
        """
        let html = plainHTML(markdown)

        #expect(html.contains("<a href=\"https://discord.gg/vChUXVf9Em\">Discord</a>"))
        #expect(html.contains("be part of the discussion!</p>"))
        #expect(html.contains("<strong>every Saturday at 3pm UTC</strong>"))
        let joinLink = "<a href=\"https://discord.gg/KvdE3wYKNR?event=1189275961456336937\">"
        #expect(html.contains(joinLink + "<strong>Join us</strong></a>"))
    }

    @Test
    func readmeContributorTableRenders() {
        let markdown = """
        <!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
        <table>
          <tbody>
            <tr>
              <td align="center" valign="top" width="14.28%">\
        <a href="http://www.austincondiff.com">\
        <img src="https://avatars.githubusercontent.com/u/806104?v=4?s=100" width="100px;" alt="Austin Condiff"/>\
        <br /><sub><b>Austin Condiff</b></sub></a><br />\
        <a href="#design-austincondiff" title="Design">🎨</a> \
        <a href="https://github.com/FeodosiiShus/dreamer/commits?author=austincondiff" title="Code">💻</a></td>
            </tr>
          </tbody>
        </table>

        | Name | Role |
        |---|---|
        | Austin Condiff | Design |
        """
        let html = plainHTML(markdown)

        #expect(html.contains("<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->"))
        #expect(html.contains("<table>"))
        #expect(html.contains("<td align=\"center\" valign=\"top\" width=\"14.28%\">"))
        #expect(html.contains("<td>Austin Condiff</td>"))
    }

    @Test
    func fullReadmeTerminates() {
        let paragraph = """
        <p align="center">
          <a aria-label="Join the community on Discord" href="https://discord.gg/vChUXVf9Em" target="_blank">
            <img alt="" src="https://img.shields.io/badge/Join%20the%20community-black.svg\
        ?style=for-the-badge&logo=Discord">
          </a>
        </p>

        > [!IMPORTANT]
        > Not for production use! Read [the docs](https://example.com) and [![badge](i.png)](u) first!

        - [Anchor](#anchor) and **bold** and *em* and `code` and <not-a-tag>
        """
        let markdown = Array(repeating: paragraph, count: 200).joined(separator: "\n\n")
        let html = plainHTML(markdown)

        #expect(html.contains("<blockquote>"))
        #expect(html.contains("Not for production use! Read <a href=\"https://example.com\">the docs</a>"))
        #expect(!html.contains("<not-a-tag>"))
        #expect(html.count > markdown.count)
    }
}
