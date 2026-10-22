#!/usr/bin/env python3
"""Check the required inventory call without accepting comments or string text.

This is a lexical check, not Swift control-flow analysis. String interpolation
is conservatively excluded with the containing literal; it cannot satisfy the
required standalone export statement.
"""

import pathlib
import re
import sys


CALL = re.compile(
    r"^\s*(?:(?:let|var)\s+\w+\s*=\s*|return\s+)?"
    r"try\s+repo\.inventoryExportRecords\s*\(", re.MULTILINE
)
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


def interpolation_end(source, index):
    depth = 1
    while index < len(source):
        if source.startswith(("//", "/*"), index):
            index = comment_end(source, index)
        elif (match := STRING_START.match(source, index)) is not None:
            index = string_end(source, match)
        else:
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
        elif (match := STRING_START.match(source, index)) is not None:
            index = string_end(source, match)
        else:
            index += 1
            continue
        for position in range(start, index):
            if source[position] not in "\r\n":
                output[position] = " "
    return "".join(output)


def main():
    if len(sys.argv) != 2:
        print("Usage: check_inventory_export_call.py <Swift export file>", file=sys.stderr)
        return 2
    try:
        source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
        return 0 if CALL.search(code_only(source)) else 1
    except (OSError, UnicodeError, ValueError) as error:
        print(f"Inventory export source check failed: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
