# GitHub Branch Protection — Recommended Settings

Status: Current configuration guide; remote state not reverified
Last reviewed: 2026-09-02

Apply these rules through GitHub settings. Re-read the remote branch protection and the actual CI check names before each release.

## Last recorded remote status

The governance report recorded this state on 2026-02-09. It was not reverified from GitHub during the 2026-09-02 local documentation pass:
- required checks: `CI / SSOT integrity check`, `CI / SwiftPM tests`, `CI / Xcode simulator tests`
- strict status checks (branch must be up to date): enabled
- admin enforcement: enabled
- force pushes: disabled
- deletions: disabled
- conversation resolution before merge: enabled

## Recommended Rules for `main`

| Setting | Value | Rationale |
|---------|-------|-----------|
| **Require a pull request before merging** | ✅ On | Prevents direct pushes; forces CI to run |
| Require approvals | 0 (solo dev) / 1+ (team) | Scale with team size |
| **Require status checks to pass** | ✅ On | Gates on CI results |
| Required checks | Names from the latest successful required workflows | Check names can change when workflow jobs are renamed; verify them remotely |
| **Require branches to be up to date** | ✅ On | Prevents stale merges |
| **Do not allow bypassing the above settings** | ✅ On | Applies even to admins |
| Require linear history | Optional | Nice for clean history |
| Allow force pushes | ❌ Off | Prevents history destruction |
| Allow deletions | ❌ Off | Protects main |

## How to Apply

1. Go to: `https://github.com/Kxd395/DoseTap/settings/branches`
2. Click **Add branch protection rule**
3. Branch name pattern: `main`
4. Check the settings above
5. Click **Create** / **Save changes**

### Optional Additional Checks

If you want extra guardrails from `.github/workflows/ci-swift.yml`, also require:
- `Swift CI / Build & Test`
- `Swift CI / Storage Enforcement Guard`
- `Swift CI / Production print() Ban`
- `Swift CI / Xcode iOS Build`

## Feature Branch Convention

- Feature branches: `NNN-short-name` (e.g., `004-dosing-amount-model`)
- No protection rules on feature branches (allows fast iteration)
- All feature branches merge to `main` via PR only

## For Solo Development

Even as a solo developer, requiring PRs for `main` ensures:
- CI runs on every change before it reaches main
- You get a reviewable history of what changed and why
- Reverts are clean (revert the PR, not individual commits)
- If you add AI agents or collaborators later, the guard is already in place
