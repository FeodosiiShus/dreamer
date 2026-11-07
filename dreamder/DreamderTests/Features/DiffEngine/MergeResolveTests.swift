import Testing
import Foundation
@testable import Dreamder

@Suite struct MergeResolveTests {
    private func expectResolve(
        base: String,
        left: String,
        right: String,
        expected: String?,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let result = MergeResolveUtil.tryResolve(left: left, base: base, right: right)
        #expect(result == expected, "base: \(base), left: \(left), right: \(right)", sourceLocation: sourceLocation)
    }

    @Test func simple() {
        expectResolve(base: "", left: "", right: "", expected: "")
        expectResolve(base: "x x x", left: "x x x", right: "x x x", expected: "x x x")
        expectResolve(base: "x x x", left: "x Y x", right: "x x x", expected: "x Y x")
        expectResolve(base: "x x", left: "x x", right: "x Y x", expected: "x Y x")
        expectResolve(base: "x X x", left: "x x", right: "x X x", expected: "x x")
    }

    @Test func sameModification() {
        expectResolve(base: "x x x", left: "x Y x", right: "x Y x", expected: "x Y x")
        expectResolve(base: "x x", left: "x Y x", right: "x Y x", expected: "x Y x")
        expectResolve(base: "x X x", left: "x x", right: "x x", expected: "x x")
    }

    @Test func nonConflictingChanges() {
        expectResolve(base: "x x x", left: "x Y x x", right: "x x Z x", expected: "x Y x Z x")
        expectResolve(base: "x", left: "x Y", right: "Z x", expected: "Z x Y")
        expectResolve(base: "x x", left: "x", right: "Z x x", expected: "Z x")
    }

    @Test func failure() {
        expectResolve(base: "x x x", left: "x Y x", right: "x Z x", expected: nil)
        expectResolve(base: "x x", left: "x Y x", right: "x Z x", expected: nil)
    }

    @Test func confusingConflicts() {
        expectResolve(
            base: "version: 1.0.0",
            left: "version: 2.0.0",
            right: "version: 1.0.4",
            expected: "version: 2.0.4"
        )
    }

    @Test func regressions() {
        expectResolve(base: "i\n", left: "i", right: "\ni", expected: "i")

        expectResolve(
            base: "Y X Y",
            left: "Y C\nX\nC Y",
            right: "Y \nX\n Y",
            expected: "Y \nC\nX\nC Y"
        )

        let base = [
            "",
            "  public static class ChangeData {",
            "    @NotNull public final ChangeKind kind;",
            "    public final int otherPath;",
            "",
            "    public ChangeData(@NotNull ChangeKind kind, int otherPath) {",
            "      this.kind = kind;",
            "      this.otherPath = otherPath;",
            "    }",
            "",
            "    public boolean isRename() {",
            "      return kind.equals(ChangeKind.RENAMED_FROM) || kind.equals(ChangeKind.RENAMED_TO);",
            "    }",
            "",
            "    @Override",
            "    public int hashCode() {",
            "      return Objects.hash(kind, otherPath);",
            "    }",
            "  }",
            "",
            "  private enum ChangeKind {",
            "    MODIFIED((byte)0),",
            "    RENAMED_FROM((byte)1),",
            "    RENAMED_TO((byte)2);"
        ].joined(separator: "\n")

        let left = [
            "",
            "  public enum ChangeKind {",
            "    NOT_CHANGED((byte)-1),",
            "    MODIFIED((byte)0),",
            "    ADDED((byte)1),",
            "    REMOVED((byte)2);"
        ].joined(separator: "\n")

        let right = [
            "",
            "  public static class ChangeData {",
            "  @NotNull public final ChangeKind kind;",
            "  public final int otherPath;",
            "",
            "  public ChangeData(@NotNull ChangeKind kind, int otherPath) {",
            "    this.kind = kind;",
            "    this.otherPath = otherPath;",
            "  }",
            "",
            "  public boolean isRename() {",
            "    return kind.equals(ChangeKind.RENAMED_FROM) || kind.equals(ChangeKind.RENAMED_TO);",
            "  }",
            "",
            "  @Override",
            "  public int hashCode() {",
            "    return Objects.hash(kind, otherPath);",
            "  }",
            "}",
            "",
            "private enum ChangeKind {",
            "  MODIFIED((byte)0),",
            "  RENAMED_FROM((byte)1),",
            "  RENAMED_TO((byte)2);"
        ].joined(separator: "\n")

        let expected = [
            "",
            "  public enum ChangeKind {",
            "    NOT_CHANGED((byte)-1),",
            "  MODIFIED((byte)0),",
            "  ADDED((byte)1),",
            "  REMOVED((byte)2);"
        ].joined(separator: "\n")

        expectResolve(base: base, left: left, right: right, expected: expected)
    }
}
