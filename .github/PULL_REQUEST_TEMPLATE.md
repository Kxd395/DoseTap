## Summary

<!-- Brief description of what this PR does -->

## Type of Change

- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to change)
- [ ] Documentation update

## Testing

- [ ] I have run `swift test -q` and all tests pass
- [ ] I have tested the changes locally in the simulator
- [ ] I have added tests that prove my fix/feature works

## SSOT Compliance

- [ ] If this changes behavior, I have updated `docs/SSOT/README.md`
- [ ] If this changes navigation or contracts, I have updated `docs/SSOT/navigation.md` or `docs/SSOT/contracts/*`
- [ ] I have run `bash tools/ssot_check.sh` and reviewed any warnings

## Build Tracking

- [ ] App-facing changes bump `CURRENT_PROJECT_VERSION`
- [ ] Major behavior, storage, sync, or dosing changes bump `MARKETING_VERSION`
- [ ] I have run `bash tools/check_app_version.sh`

## For Release PRs

If this PR is a release (version bump, tag):

- [ ] I have completed the [Release Checklist](../docs/RELEASE_CHECKLIST.md)
- [ ] Version and build numbers are updated in the Xcode project
- [ ] CHANGELOG.md is updated

---

Closes #<!-- issue number if applicable -->
