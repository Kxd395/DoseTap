#!/usr/bin/env python3
"""Check every inventory accessor occurrence after excluding inert source text.

This is a lexical check, not Swift control-flow analysis. String interpolation
is conservatively excluded with the containing literal; it cannot satisfy the
required standalone export statement.
"""

import pathlib
import re
import sys


ACCESSOR = re.compile(r"(?<![\w`])`?inventoryExportRecords`?(?![\w`])")
OWNERS = {
    "SettingsStudioExport.swift": "repo",
    "Storage/SessionRepositoryQueries.swift": "storage",
}
DECLARATIONS = {"Storage/SessionRepositoryQueries.swift", "Storage/EventStorage+Exports.swift"}
STUDIO = "SettingsStudioExport.swift"


def approved_calls(code, receiver):
    pattern = re.compile(
        r"(?:^|[;\n])\s*(?:(?:let|var)\s+\w+\s*=\s*|return\s+)?"
        r"try\s+" + receiver + r"\s*\.\s*(?P<name>inventoryExportRecords)\s*\("
    )
    return {match.start("name") for match in pattern.finditer(code)}


REGEX_START = re.compile(r"(\#+)/")
STRING_START = re.compile(r'(\#*)("""|")')


def comment_end(source, index):
    if source.startswith("//", index):
        end = source.find("\n", index)
        return len(source) if end == -1 else end
    depth = 1
    index += 2
    while index < len(source) and depth:
        if source.startswith("/*", index):
            depth += 1
            index += 2
        elif source.startswith("*/", index):
            depth -= 1
            index += 2
        else:
            index += 1
    if depth:
        raise ValueError("unterminated block comment")
    return index


def regex_end(source, match):
    """Skip unambiguous extended regex literals (SE-0354), not slash operators."""
    terminator = "/" + match.group(1)
    index = match.end()
    interpolation = "\\" + match.group(1) + "("
    multiline = re.match(r"[ \t]*\r?\n", source[index:]) is not None
    while index < len(source):
        if source.startswith(interpolation, index):
            raise ValueError("regex interpolation-like syntax requires guard review")
        elif source[index] == "\\":
            index += 2
        elif source.startswith(terminator, index):
            line_start = source.rfind("\n", 0, index) + 1
            if not multiline or not source[line_start:index].strip():
                return index + len(terminator)
            index += len(terminator)
        else:
            index += 1
    raise ValueError("unterminated extended regex literal")


def interpolation_end(source, index):
    depth = 1
    while index < len(source):
        if source.startswith(("//", "/*"), index):
            index = comment_end(source, index)
        elif (match := REGEX_START.match(source, index)) is not None:
            index = regex_end(source, match)
        elif (match := STRING_START.match(source, index)) is not None:
            index = string_end(source, match)
        else:
            if source[index] == "/":
                # Slash operators and bare regexes need Swift parser context.
                # Refuse this unsupported syntax rather than count regex tokens.
                raise ValueError("bare slash inside interpolation requires guard review")
            if source[index] == "(":
                depth += 1
            elif source[index] == ")":
                depth -= 1
                if depth == 0:
                    return index + 1
            index += 1
    raise ValueError("unterminated string interpolation")


def string_end(source, match):
    hashes, quotes = match.groups()
    terminator = quotes + hashes
    escape = "\\" + hashes
    index = match.end()
    while index < len(source):
        if source.startswith(escape + "(", index):
            index = interpolation_end(source, index + len(escape) + 1)
        elif source.startswith(escape, index):
            index += len(escape) + 1
        elif source.startswith(terminator, index):
            return index + len(terminator)
        else:
            index += 1
    raise ValueError("unterminated string literal")


def code_only(source):
    """Blank comments and strings, retaining line breaks and token separation."""
    output = list(source)
    index = 0
    while index < len(source):
        start = index
        if source.startswith(("//", "/*"), index):
            index = comment_end(source, index)
        elif (match := REGEX_START.match(source, index)) is not None:
            index = regex_end(source, match)
        elif (match := STRING_START.match(source, index)) is not None:
            index = string_end(source, match)
        else:
            if source[index] == "/" and source[index + 1:index + 2] not in (" ", "\t"):
                # SE-0354 bare regexes cannot begin with space/tab. Only retain
                # this unambiguous spaced operator form; all others need review.
                raise ValueError("bare regex or unspaced slash requires guard review")
            index += 1
            continue
        for position in range(start, index):
            if source[position] not in "\r\n":
                output[position] = " "
    return "".join(output)


def check_sources(app_root):
    violations = False
    required_call = False
    for path in sorted(app_root.rglob("*.swift")):
        source = path.read_text(encoding="utf-8")
        if "inventoryExportRecords" not in source:
            continue
        relative = path.relative_to(app_root).as_posix()
        code = code_only(source)
        calls = approved_calls(code, OWNERS[relative]) if relative in OWNERS else set()
        if relative == STUDIO and calls:
            required_call = True
        declarations = set()
        if relative in DECLARATIONS:
            declarations = {match.start("name") for match in re.finditer(
                r"\bfunc\s+(?P<name>inventoryExportRecords)\s*\(", code)}
        for match in ACCESSOR.finditer(code):
            if match.start() in calls or match.start() in declarations:
                continue
            line = code.count("\n", 0, match.start()) + 1
            if relative not in OWNERS:
                reason = "inventory export read outside reviewed repository/export owners"
            else:
                reason = "unchecked inventory export read; require a direct ordinary-try call"
            print(f"FAIL: {reason}: {path}:{line}")
            violations = True
    if not required_call:
        print("FAIL: Studio export must use the throwing repository inventoryExportRecords reader")
    return 1 if violations or not required_call else 0


def main():
    if len(sys.argv) != 2:
        print("Usage: check_inventory_export_call.py <app Swift directory>", file=sys.stderr)
        return 2
    try:
        return check_sources(pathlib.Path(sys.argv[1]))
    except (OSError, UnicodeError, ValueError) as error:
        print(f"Inventory export source check failed: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
