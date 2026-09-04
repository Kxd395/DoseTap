#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "tempfile"
require_relative "../plane_tracker"

class FakePlaneTracker < PlaneTracker
  attr_reader :comments

  def initialize
    super
    @fake_states = [
      { "id" => "state-backlog", "name" => "Backlog" },
      { "id" => "state-todo", "name" => "Todo" },
      { "id" => "state-progress", "name" => "In Progress" },
      { "id" => "state-done", "name" => "Done" },
      { "id" => "state-cancelled", "name" => "Cancelled" }
    ]
    @fake_items = [
      {
        "id" => "item-34",
        "sequence_id" => 34,
        "name" => "Dose 2 reconciliation",
        "state" => "state-progress",
        "priority" => "urgent",
        "updated_at" => "2026-09-04T12:00:00Z"
      },
      {
        "id" => "item-39",
        "sequence_id" => 39,
        "name" => "Existing work",
        "state" => "state-todo",
        "priority" => "high",
        "updated_at" => "2026-09-04T12:00:00Z"
      }
    ]
    @comments = Hash.new { |hash, key| hash[key] = [] }
  end

  private

  def origin
    "http://plane.test"
  end

  def request_json(method, path, body: nil)
    return { "results" => @fake_states } if method == "get" && path.end_with?("/states/")
    return paged_items_response if method == "get" && path.start_with?(work_items_path + "?")

    if (match = path.match(%r{#{Regexp.escape(work_items_path)}([^/]+)/comments/([^/]+)/\z}))
      item_id = match[1]
      comment_id = match[2]
      comment = @comments[item_id].find { |candidate| candidate.fetch("id") == comment_id }
      raise PlaneTrackerError, "fake comment not found" unless comment
      if method == "patch"
        comment.merge!(body)
        comment["comment_stripped"] = strip_html(body.fetch("comment_html"))
        return comment
      end
    end

    if (match = path.match(%r{#{Regexp.escape(work_items_path)}([^/]+)/comments/\?limit=100\z}))
      return { "results" => @comments[match[1]] }
    end

    if (match = path.match(%r{#{Regexp.escape(work_items_path)}([^/]+)/comments/\z}))
      if method == "post"
        comment = body.merge(
          "id" => "comment-#{@comments[match[1]].length + 1}",
          "comment_stripped" => strip_html(body.fetch("comment_html"))
        )
        @comments[match[1]] << comment
        return comment
      end
    end

    if (match = path.match(%r{#{Regexp.escape(work_items_path)}([^/]+)/\z}))
      item = @fake_items.find { |candidate| candidate.fetch("id") == match[1] }
      raise PlaneTrackerError, "fake item not found" unless item
      if method == "patch"
        item.merge!(body)
        return item
      end
    end

    if method == "post" && path == work_items_path
      next_sequence = @fake_items.map { |item| item.fetch("sequence_id") }.max + 1
      item = {
        "id" => "item-#{next_sequence}",
        "sequence_id" => next_sequence,
        "name" => body.fetch("name"),
        "state" => body.fetch("state"),
        "priority" => body.fetch("priority"),
        "updated_at" => "2026-09-04T12:00:00Z"
      }
      @fake_items << item
      return item
    end

    raise PlaneTrackerError, "unhandled fake request #{method.upcase} #{path}"
  end

  def paged_items_response
    {
      "results" => @fake_items,
      "next_page_results" => false,
      "next_cursor" => "100:1:0"
    }
  end

  def strip_html(html)
    html.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
  end
end

class PlaneTrackerTest < Minitest::Test
  def setup
    @tracker = FakePlaneTracker.new
  end

  def test_preflight_uses_exact_identifier
    result = @tracker.preflight("DOSETAP-34")

    assert_equal true, result.fetch(:ok)
    assert_equal "Dose 2 reconciliation", result.fetch(:title)
    assert_equal "In Progress", result.fetch(:state)
  end

  def test_invalid_identifier_fails_closed
    error = assert_raises(PlaneTrackerError) { @tracker.preflight("DOSETAP-latest") }

    assert_match(/invalid work item identifier/, error.message)
  end

  def test_start_is_dry_run_by_default_and_apply_verifies_readback
    dry_run = @tracker.start("DOSETAP-39")
    assert_equal true, dry_run.fetch(:dry_run)
    assert_equal "Todo", @tracker.preflight("DOSETAP-39").fetch(:state)

    applied = @tracker.start("DOSETAP-39", apply: true)
    assert_equal true, applied.fetch(:applied)
    assert_equal "verified", applied.fetch(:readback)
    assert_equal "In Progress", @tracker.preflight("DOSETAP-39").fetch(:state)

    already_started = @tracker.start("DOSETAP-39", apply: true)
    assert_equal "verified", already_started.fetch(:readback)
  end

  def test_done_rejects_open_gates
    with_json(closeout_payload(open_gates: ["Signed-device acceptance remains open"], target_state: "Done", acceptance_complete: true)) do |path|
      error = assert_raises(PlaneTrackerError) do
        @tracker.closeout("DOSETAP-34", path, apply: true)
      end
      assert_match(/open_gates to be empty/, error.message)
    end
    assert_empty @tracker.comments["item-34"]
  end

  def test_done_rejects_non_passing_validation
    payload = closeout_payload(open_gates: [], target_state: "Done", acceptance_complete: true)
    payload.fetch("validation").first["result"] = "skipped"

    with_json(payload) do |path|
      error = assert_raises(PlaneTrackerError) do
        @tracker.closeout("DOSETAP-34", path, apply: true)
      end
      assert_match(/every validation result to be passed/, error.message)
    end
  end

  def test_closeout_rejects_item_that_was_not_started
    partial = closeout_payload(
      issue_identifier: "DOSETAP-39",
      open_gates: ["Implementation has not started"],
      target_state: "In Progress",
      acceptance_complete: false
    )

    with_json(partial) do |path|
      error = assert_raises(PlaneTrackerError) do
        @tracker.closeout("DOSETAP-39", path, apply: true)
      end
      assert_match(/expected In Progress after preflight\/start/, error.message)
    end
    assert_empty @tracker.comments["item-39"]
  end

  def test_closeout_requires_structured_gate_and_acceptance_fields
    payload = closeout_payload(
      open_gates: [""],
      target_state: "In Progress",
      acceptance_complete: false
    )

    with_json(payload) do |path|
      error = assert_raises(PlaneTrackerError) { @tracker.closeout("DOSETAP-34", path) }
      assert_match(/open_gates\[0\] must be a non-empty string/, error.message)
    end

    payload["open_gates"] = []
    payload.delete("acceptance_complete")
    with_json(payload) do |path|
      error = assert_raises(PlaneTrackerError) { @tracker.closeout("DOSETAP-34", path) }
      assert_match(/acceptance_complete must be true or false/, error.message)
    end

    payload["acceptance_complete"] = true
    with_json(payload) do |path|
      error = assert_raises(PlaneTrackerError) { @tracker.closeout("DOSETAP-34", path) }
      assert_match(/In Progress requires acceptance_complete=false/, error.message)
    end

    payload["acceptance_complete"] = false
    with_json(payload) do |path|
      error = assert_raises(PlaneTrackerError) { @tracker.closeout("DOSETAP-34", path) }
      assert_match(/requires a named open gate or non-passing validation/, error.message)
    end
  end

  def test_local_plane_host_guard_accepts_only_loopback_hosts
    assert @tracker.send(:local_plane_host?, "plane.localhost")
    assert @tracker.send(:local_plane_host?, "127.0.0.1")
    assert @tracker.send(:local_plane_host?, "::1")
    refute @tracker.send(:local_plane_host?, "api.plane.so")
    refute @tracker.send(:local_plane_host?, "plane.internal.example")
  end

  def test_closeout_upserts_one_workpad_and_verifies_state
    partial = closeout_payload(
      open_gates: ["Signed-device acceptance remains open"],
      target_state: "In Progress",
      acceptance_complete: false
    )

    with_json(partial) do |path|
      dry_run = @tracker.closeout("DOSETAP-34", path)
      assert_equal true, dry_run.fetch(:dry_run)
      assert_empty @tracker.comments["item-34"]

      applied = @tracker.closeout("DOSETAP-34", path, apply: true)
      assert_equal "verified", applied.fetch(:readback)
      assert_equal "created", applied.fetch(:workpad_action)
      assert_equal 1, @tracker.comments["item-34"].length

      updated = @tracker.closeout("DOSETAP-34", path, apply: true)
      assert_equal "updated", updated.fetch(:workpad_action)
      assert_equal 1, @tracker.comments["item-34"].length
    end

    @tracker.start("DOSETAP-39", apply: true)
    second_item = closeout_payload(
      issue_identifier: "DOSETAP-39",
      open_gates: ["A separate gate remains open"],
      target_state: "In Progress",
      acceptance_complete: false
    )
    with_json(second_item) do |path|
      @tracker.closeout("DOSETAP-39", path, apply: true)
    end
    refute_equal(
      @tracker.comments["item-34"].first.fetch("external_id"),
      @tracker.comments["item-39"].first.fetch("external_id")
    )

    complete = closeout_payload(open_gates: [], target_state: "Done", acceptance_complete: true)
    with_json(complete) do |path|
      result = @tracker.closeout("DOSETAP-34", path, apply: true)
      assert_equal "Done", result.fetch(:state)
      assert_equal "verified", result.fetch(:workpad)
      assert_equal 1, @tracker.comments["item-34"].length
    end
  end

  def test_create_is_dry_run_by_default_and_exact_title_is_idempotent
    input = {
      "title" => "Wire Plane closeout",
      "description_html" => "<p>Test</p>",
      "priority" => "high",
      "state" => "In Progress"
    }

    with_json(input) do |path|
      dry_run = @tracker.create(path)
      assert_equal true, dry_run.fetch(:dry_run)

      applied = @tracker.create(path, apply: true)
      assert_equal true, applied.fetch(:applied)
      assert_equal "DOSETAP-40", applied.fetch(:identifier)
      assert_equal "verified", applied.fetch(:readback)

      existing = @tracker.create(path, apply: true)
      assert_equal true, existing.fetch(:existing)
      assert_equal "DOSETAP-40", existing.fetch(:identifier)
      assert_equal "verified", existing.fetch(:readback)
    end

    input["title"] = "Invalid terminal task"
    input["state"] = "Done"
    with_json(input) do |path|
      error = assert_raises(PlaneTrackerError) { @tracker.create(path, apply: true) }
      assert_match(/new work item state must be one of Todo, In Progress/, error.message)
    end
  end

  private

  def closeout_payload(open_gates:, target_state:, acceptance_complete:, issue_identifier: "DOSETAP-34")
    {
      "issue_identifier" => issue_identifier,
      "summary" => "Implemented and verified the scoped behavior.",
      "changed_files" => ["tools/plane_tracker.rb"],
      "validation" => [
        {
          "command" => "ruby tools/tests/plane_tracker_test.rb",
          "result" => "passed",
          "evidence_class" => "automated"
        }
      ],
      "open_gates" => open_gates,
      "acceptance_complete" => acceptance_complete,
      "target_state" => target_state
    }
  end

  def with_json(payload)
    Tempfile.create(["plane-closeout", ".json"]) do |file|
      file.write(JSON.generate(payload))
      file.flush
      yield file.path
    end
  end
end
