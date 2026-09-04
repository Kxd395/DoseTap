#!/usr/bin/env bash

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

tracked_finder_metadata="$(git ls-files | awk '$0 == ".DS_Store" || $0 ~ /\/\.DS_Store$/')"
if [[ -n "$tracked_finder_metadata" ]]; then
  printf '%s\n' "$tracked_finder_metadata" >&2
  fail "Finder metadata is tracked"
fi

refs_dir="$(git rev-parse --git-path refs)"
finder_refs="$(find "$refs_dir" -type f -name .DS_Store -print | sort)"
if [[ -n "$finder_refs" ]]; then
  printf '%s\n' "$finder_refs" >&2
  fail "Finder metadata is present in Git's ref namespace"
fi

duplicate_rules="$({
  awk '
    /^[[:space:]]*($|#)/ { next }
    {
      rule = $0
      sub(/[[:space:]]+$/, "", rule)
      if (++seen[rule] == 2) print rule
    }
  ' .gitignore
} | sort)"
if [[ -n "$duplicate_rules" ]]; then
  printf '%s\n' "$duplicate_rules" >&2
  fail ".gitignore contains duplicate active rules"
fi

for ignored_path in .DS_Store docs/.DS_Store .env .env.local .cache_ggshield; do
  if ! git check-ignore --no-index -q "$ignored_path"; then
    fail "required ignore rule does not cover $ignored_path"
  fi
done

set +e
fsck_output="$(git fsck --full 2>&1)"
fsck_status=$?
set -e
if [[ $fsck_status -ne 0 ]]; then
  printf '%s\n' "$fsck_output" >&2
  fail "git fsck --full failed"
fi
if grep -Eiq 'badRefName|badRefContent|invalid ref' <<<"$fsck_output"; then
  printf '%s\n' "$fsck_output" >&2
  fail "git fsck reported an invalid ref"
fi

dangling_count="$(grep -Ec '^dangling ' <<<"$fsck_output" || true)"
printf 'Repository hygiene passed: no tracked Finder metadata, no Finder refs, unique ignore rules, and valid Git refs.\n'
printf 'git fsck reported %s dangling objects; these are informational and are not removed by this check.\n' "$dangling_count"
