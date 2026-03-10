#!/usr/bin/env bash
# ci_watch.sh — Live CI run monitor with visible progress
# Usage:
#   tools/ci_watch.sh              # watches the latest run on the current branch
#   tools/ci_watch.sh <run-id>     # watches a specific run
#   tools/ci_watch.sh --pr <n>     # watches the latest run for PR #n
#
# Requires: gh (GitHub CLI), jq

set -euo pipefail

# ── colours (if terminal supports them) ──────────────────────────
RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[0;33m'
CYN='\033[0;36m'; BLD='\033[1m'; DIM='\033[2m'; RST='\033[0m'

POLL_INTERVAL=15   # seconds between refreshes

# ── spinner frames ───────────────────────────────────────────────
SPINNER=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

# ── resolve run ID ───────────────────────────────────────────────
resolve_run_id() {
  if [[ "${1:-}" == "--pr" && -n "${2:-}" ]]; then
    gh run list --json databaseId,headBranch,status \
      --jq ".[0].databaseId" \
      -L 1 \
      --branch "$(gh pr view "$2" --json headRefName -q .headRefName)" 2>/dev/null
  elif [[ -n "${1:-}" && "${1:-}" =~ ^[0-9]+$ ]]; then
    echo "$1"
  else
    # latest run on current branch
    local branch
    branch=$(git rev-parse --abbrev-ref HEAD)
    gh run list --branch "$branch" --json databaseId -q '.[0].databaseId' -L 1 2>/dev/null
  fi
}

# ── format elapsed time ─────────────────────────────────────────
format_elapsed() {
  local secs=$1
  if (( secs < 0 )); then secs=0; fi
  if (( secs < 60 )); then
    echo "${secs}s"
  elif (( secs < 3600 )); then
    echo "$(( secs / 60 ))m $(( secs % 60 ))s"
  else
    echo "$(( secs / 3600 ))h $(( (secs % 3600) / 60 ))m"
  fi
}

# ── parse ISO8601 to epoch (macOS + Linux) ───────────────────────
iso_to_epoch() {
  local ts="$1"
  [[ -z "$ts" || "$ts" == "null" ]] && return 1
  # Strip fractional seconds if present: 2026-01-15T20:56:40.123Z → 2026-01-15T20:56:40Z
  ts="${ts%%.*}Z"
  ts="${ts%%ZZ}Z"  # avoid double Z
  if date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null; then
    return 0
  elif date -d "$ts" +%s 2>/dev/null; then
    return 0
  fi
  return 1
}

# ── status icon ──────────────────────────────────────────────────
status_icon() {
  case "$1" in
    success)    echo -e "${GRN}✓${RST}" ;;
    failure)    echo -e "${RED}✗${RST}" ;;
    cancelled)  echo -e "${YEL}⊘${RST}" ;;
    skipped)    echo -e "${DIM}–${RST}" ;;
    in_progress|queued|waiting|pending)
                echo -e "${CYN}●${RST}" ;;
    *)          echo -e "${DIM}?${RST}" ;;
  esac
}

# ── main loop ────────────────────────────────────────────────────
main() {
  local run_id
  run_id=$(resolve_run_id "$@")

  if [[ -z "$run_id" ]]; then
    echo -e "${RED}Error:${RST} Could not find a CI run. Pass a run ID or use --pr <n>."
    exit 1
  fi

  echo -e "${BLD}Watching CI run ${CYN}${run_id}${RST}"
  echo ""

  local spin_idx=0
  local iteration=0

  while true; do
    # Fetch full run + jobs data in one call
    local data
    data=$(gh run view "$run_id" --json status,conclusion,name,startedAt,updatedAt,jobs \
      2>/dev/null) || {
      echo -e "${RED}Failed to fetch run data. Check run ID and network.${RST}"
      exit 1
    }

    local run_status run_conclusion run_name started_at
    run_status=$(echo "$data" | jq -r '.status')
    run_conclusion=$(echo "$data" | jq -r '.conclusion // empty')
    run_name=$(echo "$data" | jq -r '.name // "CI"')
    started_at=$(echo "$data" | jq -r '.startedAt // empty')

    # Calculate total elapsed
    local total_elapsed=""
    if [[ -n "$started_at" ]]; then
      local start_epoch now_epoch
      start_epoch=$(iso_to_epoch "$started_at" || echo "")
      now_epoch=$(date +%s)
      if [[ -n "$start_epoch" ]]; then
        total_elapsed=$(format_elapsed $(( now_epoch - start_epoch )))
      fi
    fi

    # Clear previous output (move up N lines)
    if (( iteration > 0 )); then
      local lines_to_clear
      lines_to_clear=$(echo "$data" | jq '.jobs | length')
      # +4 for header lines
      for _ in $(seq 1 $(( lines_to_clear + 5 ))); do
        printf '\033[1A\033[2K'
      done
    fi

    # ── Header ──
    local header_icon
    if [[ "$run_status" == "completed" ]]; then
      header_icon=$(status_icon "${run_conclusion:-unknown}")
    else
      header_icon="${SPINNER[$spin_idx]}"
      spin_idx=$(( (spin_idx + 1) % ${#SPINNER[@]} ))
    fi

    echo -e "${header_icon} ${BLD}${run_name}${RST}  ${DIM}run #${run_id}${RST}  ${DIM}elapsed: ${total_elapsed:-?}${RST}"
    echo -e "${DIM}$(printf '%.0s─' {1..60})${RST}"

    # ── Jobs table ──
    local job_count
    job_count=$(echo "$data" | jq '.jobs | length')
    for (( j=0; j<job_count; j++ )); do
      local name status conclusion started completed
      name=$(echo "$data" | jq -r ".jobs[$j].name")
      status=$(echo "$data" | jq -r ".jobs[$j].status")
      conclusion=$(echo "$data" | jq -r ".jobs[$j].conclusion // \"\"")
      started=$(echo "$data" | jq -r ".jobs[$j].startedAt // \"\"")
      completed=$(echo "$data" | jq -r ".jobs[$j].completedAt // \"\"")

      local icon elapsed_str=""

      if [[ "$status" == "completed" ]]; then
        icon=$(status_icon "$conclusion")
        if [[ -n "$started" && "$started" != "null" && -n "$completed" && "$completed" != "null" ]]; then
          local s_epoch c_epoch
          s_epoch=$(iso_to_epoch "$started" || echo "")
          c_epoch=$(iso_to_epoch "$completed" || echo "")
          if [[ -n "$s_epoch" && -n "$c_epoch" ]]; then
            elapsed_str="${DIM}$(format_elapsed $(( c_epoch - s_epoch )))${RST}"
          fi
        fi
      else
        icon=$(status_icon "$status")
        if [[ -n "$started" && "$started" != "null" ]]; then
          local s_epoch now_epoch
          s_epoch=$(iso_to_epoch "$started" || echo "")
          now_epoch=$(date +%s)
          if [[ -n "$s_epoch" ]]; then
            elapsed_str="${YEL}$(format_elapsed $(( now_epoch - s_epoch )))${RST}"
          fi
        fi
      fi

      printf "  %b %-40s %b\n" "$icon" "$name" "$elapsed_str"
    done

    echo -e "${DIM}$(printf '%.0s─' {1..60})${RST}"

    # ── Completed? ──
    if [[ "$run_status" == "completed" ]]; then
      local pass_count fail_count
      pass_count=$(echo "$data" | jq '[.jobs[] | select(.conclusion == "success")] | length')
      fail_count=$(echo "$data" | jq '[.jobs[] | select(.conclusion == "failure")] | length')
      local skip_count
      skip_count=$(echo "$data" | jq '[.jobs[] | select(.conclusion == "skipped")] | length')

      if [[ "${run_conclusion}" == "success" ]]; then
        echo -e "${GRN}${BLD}All checks passed${RST} (${pass_count} passed, ${skip_count} skipped)  ${DIM}total: ${total_elapsed:-?}${RST}"
      else
        echo -e "${RED}${BLD}CI failed${RST} (${pass_count} passed, ${fail_count} failed, ${skip_count} skipped)  ${DIM}total: ${total_elapsed:-?}${RST}"
        echo ""
        echo -e "${RED}Failed jobs:${RST}"
        echo "$data" | jq -r '.jobs[] | select(.conclusion == "failure") | "  ✗ \(.name)"'
        echo ""
        echo -e "View details: ${CYN}gh run view ${run_id} --log-failed${RST}"
      fi
      break
    fi

    # ── Summary line while running ──
    local active_count pending_count done_count
    active_count=$(echo "$data" | jq '[.jobs[] | select(.status == "in_progress")] | length')
    pending_count=$(echo "$data" | jq '[.jobs[] | select(.status == "queued" or .status == "waiting")] | length')
    done_count=$(echo "$data" | jq '[.jobs[] | select(.status == "completed")] | length')
    local total_count
    total_count=$(echo "$data" | jq '.jobs | length')

    echo -e "${DIM}${done_count}/${total_count} done · ${active_count} running · ${pending_count} queued · refreshing every ${POLL_INTERVAL}s${RST}"

    sleep "$POLL_INTERVAL"
    iteration=$((iteration + 1))
  done
}

main "$@"
