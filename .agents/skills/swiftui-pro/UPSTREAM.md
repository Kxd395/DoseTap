# SwiftUI Pro in DoseTap

Status: Current repository-local agent guidance. This installation changes no app behavior.

Source: [Paul Hudson's SwiftUI Agent Skill](https://github.com/twostraws/SwiftUI-Agent-Skill), version **2.0.0**, retrieved on **2026-10-17** at commit [`ce32af1693b9e78a7d22ff48001c97a304d32063`](https://github.com/twostraws/SwiftUI-Agent-Skill/tree/ce32af1693b9e78a7d22ff48001c97a304d32063).

## Use

Open the checkout containing this directory. On the next agent turn, invoke `$swiftui-pro` with the desired SwiftUI task. Agents following [AGENTS.md](../../../AGENTS.md) also read the skill for relevant implementation and review work. If a client does not discover repository skills automatically, explicitly ask it to read [SKILL.md](SKILL.md) and the relevant references.

Example: `$swiftui-pro Review the daytime check-in for accessibility and unnecessary steps.` This requests a review; request implementation separately when fixes are wanted.

The skill is stored in this checkout, not installed globally. Other worktrees gain it when these commits are integrated into them. Discovery in a client pointed at a different checkout is not established by this installation.

## DoseTap compatibility

The project's AGENTS.md, constitution, SSOT, architecture and validation requirements govern application changes. Upstream includes newer-toolchain and device claims that this installation does not independently validate. Check the actual project settings, installed SDK/compiler and authoritative platform documentation before adopting version-specific recommendations; preserve the deployment targets and language settings.

Keep `DoseCore` platform-free, core time injected, and storage access through `SessionRepository`. Do not convert to Observation or SwiftData, replace UIKit, rearrange features, alter persisted questionnaire values, or modernize unrelated code merely because a reference recommends a general pattern. Required UI/simulator checks and physical acceptance remain in force.

## Packaging and attribution

- [LICENSE](LICENSE) is the upstream root MIT license, copyright 2026 Paul Hudson.
- [SOURCE.json](SOURCE.json) records the full upstream revision and SHA-256 hashes of all 17 retained upstream files. Those files are copied without content changes.
- The retained `swiftui-pro/` payload comprises `SKILL.md`, 12 reference documents, `agents/openai.yaml`, and both icon assets. The upstream root license is added here.
- The redundant Claude plugin directory `.claude-plugin/` and nested `skills/` layout are omitted. The downloaded archive represents the nested references symlink as a plain text stub; shipping that layout would leave a broken alternate entrypoint.
- `SOURCE.json` and this file are DoseTap integration records, not upstream content. No executable scripts, hooks or external tool dependencies are included in the retained payload.

## Updating

Updates are manual and scoped to this directory. Select a full upstream commit, use the trusted skill-installer's GitHub helper to download `swiftui-pro` into a fresh ignored `.build/` staging directory with `--ref` and `--dest`, and fetch that same revision's root LICENSE. Review the complete diff and compatibility changes before replacing files.

Retain the canonical payload listed above, preserve attribution, regenerate `SOURCE.json` hashes from the downloaded bytes, and verify that every skill reference and icon resolves locally. Update this record's version, revision and date together. Follow the normal Plane workflow and repository checks; no automatic upstream updates are configured.
