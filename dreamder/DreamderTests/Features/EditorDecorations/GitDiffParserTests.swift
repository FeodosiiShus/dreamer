import Testing
@testable import Dreamder

@Suite
struct GitDiffParserTests {
    @Test
    func parsesSingleLineModification() {
        let output = """
        diff --git a/f.txt b/f.txt
        index b00a0f1..85e1fae 100644
        --- a/f.txt
        +++ b/f.txt
        @@ -3 +3 @@ two
        -three
        +THREE
        """
        #expect(GitDiffParser.hunks(inDiff: output) == [
            GitDiffParser.Hunk(oldStart: 3, oldCount: 1, newStart: 3, newCount: 1)
        ])
    }

    @Test
    func parsesDeletionHunk() {
        let output = """
        @@ -6 +5,0 @@ five
        -six
        """
        #expect(GitDiffParser.hunks(inDiff: output) == [
            GitDiffParser.Hunk(oldStart: 6, oldCount: 1, newStart: 5, newCount: 0)
        ])
    }

    @Test
    func parsesInsertionHunk() {
        let output = """
        @@ -8,0 +8 @@ eight
        +nine
        """
        #expect(GitDiffParser.hunks(inDiff: output) == [
            GitDiffParser.Hunk(oldStart: 8, oldCount: 0, newStart: 8, newCount: 1)
        ])
    }

    @Test
    func parsesNewFileHunk() {
        let output = """
        diff --git a/new.txt b/new.txt
        new file mode 100644
        index 0000000..422c2b7
        --- /dev/null
        +++ b/new.txt
        @@ -0,0 +1,2 @@
        +a
        +b
        """
        #expect(GitDiffParser.hunks(inDiff: output) == [
            GitDiffParser.Hunk(oldStart: 0, oldCount: 0, newStart: 1, newCount: 2)
        ])
    }

    @Test
    func parsesMultipleHunks() {
        let output = """
        @@ -3 +3 @@ two
        -three
        +THREE
        @@ -6 +5,0 @@ five
        -six
        @@ -8,0 +8 @@ eight
        +nine
        """
        #expect(GitDiffParser.hunks(inDiff: output) == [
            GitDiffParser.Hunk(oldStart: 3, oldCount: 1, newStart: 3, newCount: 1),
            GitDiffParser.Hunk(oldStart: 6, oldCount: 1, newStart: 5, newCount: 0),
            GitDiffParser.Hunk(oldStart: 8, oldCount: 0, newStart: 8, newCount: 1)
        ])
    }

    @Test
    func ignoresNoNewlineMarker() {
        let output = """
        @@ -8,0 +8 @@ eight
        +nine
        \\ No newline at end of file
        """
        #expect(GitDiffParser.hunks(inDiff: output) == [
            GitDiffParser.Hunk(oldStart: 8, oldCount: 0, newStart: 8, newCount: 1)
        ])
    }

    @Test
    func ignoresFileHeaders() {
        let output = """
        diff --git a/f.txt b/f.txt
        --- a/f.txt
        +++ b/f.txt
        """
        #expect(GitDiffParser.hunks(inDiff: output).isEmpty)
    }

    @Test
    func rejectsCombinedDiffHeader() {
        #expect(GitDiffParser.hunks(inDiff: "@@@ -1,2 -1,2 +1,3 @@@").isEmpty)
    }

    @Test
    func ignoresSectionHeading() {
        #expect(GitDiffParser.hunk(fromHeader: "@@ -1,4 +1,4 @@ func greet() {") == GitDiffParser.Hunk(
            oldStart: 1,
            oldCount: 4,
            newStart: 1,
            newCount: 4
        ))
    }

    @Test
    func rejectsMalformedHeaders() {
        #expect(GitDiffParser.hunks(inDiff: "@@ -a +1 @@").isEmpty)
        #expect(GitDiffParser.hunks(inDiff: "@@ 1 +1 @@").isEmpty)
        #expect(GitDiffParser.hunks(inDiff: "@@ -1,2,3 +1 @@").isEmpty)
        #expect(GitDiffParser.hunks(inDiff: "@@ -1 +1").isEmpty)
    }

    @Test
    func treatsZeroStartAsValid() {
        #expect(GitDiffParser.hunk(fromHeader: "@@ -0,0 +0,0 @@") == GitDiffParser.Hunk(
            oldStart: 0,
            oldCount: 0,
            newStart: 0,
            newCount: 0
        ))
    }
}
