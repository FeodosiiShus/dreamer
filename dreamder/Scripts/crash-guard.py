#!/usr/bin/env python3
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_DIRECTORIES = tuple(os.path.join(ROOT, name) for name in ("Dreamder", "OpenWithDreamder"))
ALLOWLIST = os.path.join(ROOT, "Scripts", "crash-guard-allowlist.txt")

TOKEN = re.compile(r'//|/\*|#*"""|#*"|#+/')
INTERPOLATION_TOKEN = re.compile(r'//|/\*|#*"""|#*"|#+/|[()]')
STRING_OPEN = re.compile(r'(#*)("""|")')
REGEX_OPEN = re.compile(r'(#+)/')

DIRECT_RULES = (
    ("fatalError", re.compile(r"(?<![\w.])(?:Swift\.)?fatalError\s*\(")),
    ("preconditionFailure", re.compile(r"(?<![\w.])(?:Swift\.)?preconditionFailure\s*\(")),
    ("precondition", re.compile(r"(?<![\w.])(?:Swift\.)?precondition\s*\(")),
    ("assertionFailure", re.compile(r"(?<![\w.])(?:Swift\.)?assertionFailure\s*\(")),
    ("assert", re.compile(r"(?<![\w.])(?:Swift\.)?assert\s*\(")),
    ("unowned", re.compile(r"(?<![\w.])unowned\b")),
)

TYPE_NAME = r"[A-Z]\w*(?:\.[A-Z]\w*)*(?:<[^<>=]*(?:<[^<>=]*>[^<>=]*)*>)?"
TYPE_EXPRESSION = r"(?:" + TYPE_NAME + r"|\[[^\]=]*\]|\([^()=]*\))"
IMPLICITLY_UNWRAPPED = re.compile(r"(?:(?<![?:]):\s*|->\s*)" + TYPE_EXPRESSION + r"!(?![=\w])")
POSTFIX_RULES = re.compile(r"(?P<try>\btry!)|(?P<as>\bas!)|(?P<unwrap>(?<=[\w)\]])!(?!=))")


def blank(text):
    return re.sub(r"[^\n]", " ", text)


class Sanitizer:
    def __init__(self, text):
        self.text = text
        self.length = len(text)
        self.out = []

    def run(self):
        self.code(0, False)
        return "".join(self.out)

    def code(self, index, interpolation):
        text = self.text
        pattern = INTERPOLATION_TOKEN if interpolation else TOKEN
        depth = 0
        while index < self.length:
            match = pattern.search(text, index)
            if match is None:
                self.out.append(text[index:])
                return self.length
            self.out.append(text[index:match.start()])
            index = match.start()
            token = match.group(0)
            if token == "//":
                end = text.find("\n", index)
                end = self.length if end < 0 else end
                self.out.append(blank(text[index:end]))
                index = end
            elif token == "/*":
                index = self.block_comment(index)
            elif token == "(":
                depth += 1
                self.out.append("(")
                index += 1
            elif token == ")":
                if depth == 0:
                    return index
                depth -= 1
                self.out.append(")")
                index += 1
            elif token.endswith("/") and token.startswith("#"):
                index = self.extended_regex(index)
            else:
                string_match = STRING_OPEN.match(text, index)
                index = self.string(string_match)
        return index

    def block_comment(self, index):
        text = self.text
        depth = 0
        end = index
        while end < self.length:
            if text.startswith("/*", end):
                depth += 1
                end += 2
            elif text.startswith("*/", end):
                depth -= 1
                end += 2
                if depth == 0:
                    break
            else:
                end += 1
        self.out.append(blank(text[index:end]))
        return end

    def extended_regex(self, index):
        text = self.text
        hashes = REGEX_OPEN.match(text, index).group(1)
        terminator = "/" + hashes
        end = text.find(terminator, index + len(hashes) + 1)
        end = self.length if end < 0 else end + len(terminator)
        self.out.append(blank(text[index:end]))
        return end

    def string(self, match):
        text = self.text
        hashes, quote = match.group(1), match.group(2)
        terminator = quote + hashes
        escape = "\\" + hashes
        multiline = quote == '"""'
        self.out.append('"' + blank(match.group(0))[1:])
        index = match.end()
        while index < self.length:
            if not multiline and text[index] == "\n":
                return index
            if text.startswith(escape, index):
                after = index + len(escape)
                if after < self.length and text[after] == "(":
                    self.out.append(blank(text[index:after + 1]))
                    index = self.code(after + 1, True)
                    if index < self.length:
                        self.out.append(" ")
                        index += 1
                    continue
                end = min(after + 1, self.length)
                self.out.append(blank(text[index:end]))
                index = end
                continue
            if text.startswith(terminator, index):
                self.out.append(blank(terminator)[1:] + '"')
                return index + len(terminator)
            self.out.append(blank(text[index]))
            index += 1
        return index


def findings_for(sanitized):
    found = []
    for number, line in enumerate(sanitized.split("\n"), start=1):
        if not line.strip():
            continue
        for kind, rule in DIRECT_RULES:
            if rule.search(line):
                found.append((number, kind))
        unwrapped_positions = set()
        for match in IMPLICITLY_UNWRAPPED.finditer(line):
            unwrapped_positions.add(match.end() - 1)
            found.append((number, "implicitlyUnwrappedOptional"))
        for match in POSTFIX_RULES.finditer(line):
            if match.group("try"):
                found.append((number, "try!"))
            elif match.group("as"):
                found.append((number, "as!"))
            elif match.start() not in unwrapped_positions:
                found.append((number, "forceUnwrap"))
    return sorted(set(found))


def swift_files():
    for source in SOURCE_DIRECTORIES:
        for directory, directories, names in os.walk(source):
            directories.sort()
            for name in sorted(names):
                if name.endswith(".swift"):
                    yield os.path.join(directory, name)


def load_allowlist():
    entries = set()
    if not os.path.exists(ALLOWLIST):
        return entries
    with open(ALLOWLIST, encoding="utf-8") as handle:
        for number, raw in enumerate(handle, start=1):
            line = raw.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            parts = line.split("|", 2)
            if len(parts) != 3:
                print(f"error: {os.path.relpath(ALLOWLIST, ROOT)}:{number} must be path|kind|source line", file=sys.stderr)
                sys.exit(2)
            entries.add((parts[0].strip(), parts[1].strip(), parts[2].strip()))
    return entries


def main():
    allowlist = load_allowlist()
    used = set()
    violations = []
    for path in swift_files():
        with open(path, encoding="utf-8", errors="replace") as handle:
            source = handle.read()
        sanitized = Sanitizer(source).run()
        lines = source.split("\n")
        relative = os.path.relpath(path, ROOT)
        for number, kind in findings_for(sanitized):
            trimmed = lines[number - 1].strip()
            key = (relative, kind, trimmed)
            if key in allowlist:
                used.add(key)
            else:
                violations.append((relative, number, kind, trimmed))

    for relative, number, kind, trimmed in violations:
        print(f"{relative}:{number} {kind}")
        print(f"    {trimmed}")

    for entry in sorted(allowlist - used):
        print(f"warning: stale allowlist entry {entry[0]}|{entry[1]}|{entry[2]}", file=sys.stderr)

    if violations:
        counts = {}
        for _, _, kind, _ in violations:
            counts[kind] = counts.get(kind, 0) + 1
        summary = ", ".join(f"{kind} {count}" for kind, count in sorted(counts.items()))
        print(f"\ncrash guard: {len(violations)} finding(s) ({summary})")
        return 1
    print("crash guard: clean")
    return 0


sys.exit(main())
