# Findings Ledger Schema

Every finding MUST be added to both `findings.md` (as a structured entry) and `findings.json` (as a JSON object in the root array).

## Required Fields

```json
{
  "id": "AUD-001",
  "pillar": "security",
  "severity": "P0",
  "label": "CRITICAL",
  "category": "security",
  "title": "Short description of the finding",
  "evidence": [
    {
      "path": "ios/DoseTap/SomeFile.swift",
      "line_range": "12-15",
      "command": "command that revealed the issue",
      "output_snippet": "relevant output"
    }
  ],
  "blast_radius": "What systems/users are affected and how badly.",
  "fix": "Step-by-step remediation.",
  "verification": "Command or test that proves the fix works.",
  "effort_hours": 2,
  "interest_rate": "latent — description of carrying cost over time",
  "roi": "Very High"
}
```

## Valid Values

- **pillar**: `hygiene` | `universal` | `security` | `cicd` | `dx` | `strategy`
- **severity**: `P0` | `P1` | `P2` | `P3`
- **label**: `CRITICAL` | `HIGH` | `MEDIUM` | `LOW` (must match severity mapping)
- **category**: `correctness` | `security` | `architecture` | `process` | `docs` | `performance` | `observability` | `build`
- **interest_rate** prefix: `compounding` | `latent` | `linear` | `deferred_cliff`
- **roi**: `Very High` | `High` | `Medium` | `Low`

## ID Convention

- Sequential: `AUD-001`, `AUD-002`, etc.
- Each phase appends to the ledger — IDs are globally unique across all phases.
