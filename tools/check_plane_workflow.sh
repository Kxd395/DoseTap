#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

required_files=(
  "AGENTS.md"
  "WORKFLOW.md"
  ".agents/plane-workflow.yml"
  ".env.example"
  "tools/plane_tracker.rb"
  "tools/tests/plane_tracker_test.rb"
  "docs/PLANNING.md"
)

for required_file in "${required_files[@]}"; do
  if [[ ! -f "$required_file" ]]; then
    echo "Plane workflow check failed: missing $required_file" >&2
    exit 1
  fi
done

ruby -c tools/plane_tracker.rb >/dev/null
ruby tools/plane_tracker.rb validate-config >/dev/null
ruby tools/tests/plane_tracker_test.rb

ruby <<'RUBY'
require "yaml"

workflow_text = File.read("WORKFLOW.md")
parts = workflow_text.split(/^---\s*$\n?/, 3)
abort "Plane workflow check failed: WORKFLOW.md YAML front matter missing" unless parts.length == 3

workflow = YAML.safe_load(parts[1], permitted_classes: [], aliases: false)
plane = YAML.safe_load(File.read(".agents/plane-workflow.yml"), permitted_classes: [], aliases: false)

checks = {
  "WORKFLOW tracker kind" => workflow.dig("tracker", "kind") == "plane",
  "agent YAML tracker kind" => plane.dig("tracker", "kind") == "plane",
  "current API resource" => plane.dig("tracker", "provider", "api_resource") == "work-items",
  "workspace alignment" => workflow.dig("tracker", "provider", "workspace_slug") == plane.dig("tracker", "provider", "workspace_slug"),
  "project alignment" => workflow.dig("tracker", "provider", "project_id") == plane.dig("tracker", "provider", "project_id"),
  "identifier alignment" => workflow.dig("tracker", "provider", "project_identifier") == plane.dig("tracker", "provider", "project_identifier"),
  "credential alignment" => workflow.dig("tracker", "provider", "api_key") == "$Plane_DoseTap_API",
  "base URL alignment" => workflow.dig("tracker", "provider", "endpoint") == "$PLANE_BASE_URL",
  "active states alignment" => workflow.dig("tracker", "active_states") == plane.dig("tracker", "active_states"),
  "terminal states alignment" => workflow.dig("tracker", "terminal_states") == plane.dig("tracker", "terminal_states"),
  "dry-run default" => plane.dig("completion", "dry_run_default") == true,
  "post-write readback" => plane.dig("completion", "require_post_write_readback") == true,
  "human gate preservation" => plane.dig("completion", "preserve_human_and_physical_gates") == true,
  "Done requires no open gates" => plane.dig("completion", "require_no_open_gates_for_done") == true,
  "fail-closed tracker policy" => plane.dig("completion", "tracker_failure_policy") == "fail_closed",
  "local Plane only" => plane.dig("security", "local_plane_only") == true,
  "idempotent duplicate-title policy" => plane.dig("identity", "duplicate_title_policy") == "return_existing_exact_match",
  "unattended handoff policy required" => plane.dig("orchestration", "unattended_handoff_policy_required") == true
}

failed = checks.reject { |_name, passed| passed }
unless failed.empty?
  failed.each_key { |name| warn "Plane workflow check failed: #{name}" }
  exit 1
end
RUBY

required_workflow_phrases=(
  "plane_tracker.rb preflight"
  "plane_tracker.rb start"
  "plane_tracker.rb closeout"
  "plane_tracker.rb verify"
  "post-write readback"
  "must not claim"
)

for phrase in "${required_workflow_phrases[@]}"; do
  if ! grep -Fqi "$phrase" WORKFLOW.md; then
    echo "Plane workflow check failed: WORKFLOW.md missing '$phrase'" >&2
    exit 1
  fi
done

if grep -Fqi "tracker.kind: linear" WORKFLOW.md || grep -Eq '^[[:space:]]*kind:[[:space:]]*linear[[:space:]]*$' WORKFLOW.md; then
  echo "Plane workflow check failed: active WORKFLOW.md still selects Linear" >&2
  exit 1
fi

if grep -Fq '/issues/' tools/plane_tracker.rb; then
  echo "Plane workflow check failed: helper uses deprecated Plane /issues/ API" >&2
  exit 1
fi

if ! grep -Eq '^\.env$' .gitignore; then
  echo "Plane workflow check failed: .env is not ignored" >&2
  exit 1
fi

if ! grep -Fqx 'PLANE_BASE_URL=http://plane.localhost:3301' .env.example; then
  echo "Plane workflow check failed: .env.example is missing the local Plane origin" >&2
  exit 1
fi

if ! grep -Fqx 'Plane_DoseTap_API=replace-with-local-plane-api-key' .env.example; then
  echo "Plane workflow check failed: .env.example is missing the safe API key placeholder" >&2
  exit 1
fi

if ! grep -Fq "tools/check_plane_workflow.sh" AGENTS.md; then
  echo "Plane workflow check failed: AGENTS.md does not require the validator" >&2
  exit 1
fi

echo "Plane workflow check passed"
