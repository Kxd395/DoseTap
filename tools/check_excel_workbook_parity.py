#!/usr/bin/env python3
"""Compare workbook package contents without interpreting or printing clinical data."""
import argparse
import json
import zipfile


def compare(before, after):
    with zipfile.ZipFile(before) as original, zipfile.ZipFile(after) as candidate:
        for archive in (original, candidate):
            names = archive.namelist()
            if len(names) != len(set(names)):
                raise ValueError("Archive contains duplicate member names")
            if archive.testzip() is not None:
                raise ValueError("Archive CRC check failed")
        if set(original.namelist()) != set(candidate.namelist()):
            raise ValueError("Workbook member sets differ")
        for name in original.namelist():
            if original.read(name) != candidate.read(name):
                raise ValueError("Workbook member contents differ")
        return {"members": len(original.namelist()), "identical_member_contents": True}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before")
    parser.add_argument("after")
    args = parser.parse_args()
    print(json.dumps(compare(args.before, args.after)))
