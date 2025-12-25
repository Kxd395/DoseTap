#!/usr/bin/env python3
import os
import sys
import re

# Configuration
ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DOCS_DIR = os.path.join(ROOT_DIR, "docs")
SSOT_DIR = os.path.join(DOCS_DIR, "SSOT")

# Rules
RULES = [
    {
        "name": "No Core Data",
        "pattern": r"Core\s*Data|NSPersistentContainer|NSManagedObject",
        "exclude_files": ["AUDIT_LOG", "legacy", "archive", "EventStoreCoreData.swift"], # Allow in audit logs and legacy files
        "message": "Found reference to Core Data. Persistence is SQLite only."
    },
    {
        "name": "Correct Test Count",
        "pattern": r"Test Summary: \d+|Tests Passing: \d+|tests passing",
        "validator": lambda match: "207" in match.group(0),
        "message": "Found stale test count. Should be 207."
    },
    {
        "name": "Correct Event Count",
        "pattern": r"\d+ event types",
        "validator": lambda match: "13" in match.group(0),
        "message": "Found stale event count. Should be 13."
    },
    {
        "name": "No Stale Cooldowns",
        "pattern": r"water 300s|snack 900s",
        "message": "Found stale cooldown values (water 300s, snack 900s). Check SSOT."
    }
]

def scan_file(filepath):
    errors = []
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
            
        for rule in RULES:
            # Check exclusions
            if any(ex in filepath for ex in rule.get("exclude_files", [])):
                continue
                
            matches = re.finditer(rule["pattern"], content, re.IGNORECASE)
            for match in matches:
                is_valid = True
                if "validator" in rule:
                    is_valid = rule["validator"](match)
                
                if not is_valid:
                    errors.append(f"{rule['message']} (Found: '{match.group(0)}')")
                elif "validator" not in rule:
                     errors.append(f"{rule['message']} (Found: '{match.group(0)}')")

    except Exception as e:
        print(f"Error reading {filepath}: {e}")
        
    return errors

def main():
    print(f"🔍 Scanning documentation in {ROOT_DIR}...")
    all_errors = {}
    
    # Files to scan explicitly
    scan_targets = [
        "README.md",
        "docs/architecture.md",
        "docs/FEATURE_ROADMAP.md",
        "docs/IMPLEMENTATION_PLAN.md",
        "docs/PRD.md"
    ]
    
    for target in scan_targets:
        path = os.path.join(ROOT_DIR, target)
        if os.path.exists(path):
            errors = scan_file(path)
            if errors:
                all_errors[target] = errors
                
    if all_errors:
        print("\n❌ Documentation Drift Detected:")
        for file, errs in all_errors.items():
            print(f"\n📄 {file}:")
            for err in errs:
                print(f"  - {err}")
        sys.exit(1)
    else:
        print("\n✅ No documentation drift detected.")
        sys.exit(0)

if __name__ == "__main__":
    main()
