#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "digest"
require "ipaddr"
require "json"
require "net/http"
require "open3"
require "optparse"
require "time"
require "uri"
require "yaml"

class PlaneTrackerError < StandardError; end

class PlaneTracker
  ROOT = File.expand_path("..", __dir__)
  DEFAULT_CONFIG = File.join(ROOT, ".agents", "plane-workflow.yml")
  ALLOWED_RESULTS = %w[passed failed skipped not_run].freeze

  def initialize(config_path: DEFAULT_CONFIG)
    @config_path = File.expand_path(config_path, ROOT)
    @config = YAML.safe_load(File.read(@config_path), permitted_classes: [], aliases: false)
    validate_config!
    @tracker = @config.fetch("tracker")
    @provider = @tracker.fetch("provider")
    @completion = @config.fetch("completion")
    @workpad = @config.fetch("workpad")
  rescue Errno::ENOENT => e
    raise PlaneTrackerError, "missing configuration: #{e.message}"
  rescue Psych::Exception => e
    raise PlaneTrackerError, "invalid YAML configuration: #{e.message}"
  end

  def validate_config!
    required = [
      ["tracker", "kind"],
      ["tracker", "provider", "base_url_env"],
      ["tracker", "provider", "api_key_env"],
      ["tracker", "provider", "env_file"],
      ["tracker", "provider", "workspace_slug"],
      ["tracker", "provider", "project_id"],
      ["tracker", "provider", "project_identifier"],
      ["tracker", "provider", "api_resource"],
      ["completion", "start_state"],
      ["completion", "complete_state"],
      ["completion", "incomplete_state"],
      ["workpad", "marker"]
    ]
    required.each do |keys|
      value = keys.reduce(@config) { |memo, key| memo.is_a?(Hash) ? memo[key] : nil }
      raise PlaneTrackerError, "missing YAML field: #{keys.join('.')}" if value.nil? || value.to_s.empty?
    end
    raise PlaneTrackerError, "tracker.kind must be plane" unless @config.dig("tracker", "kind") == "plane"
    unless @config.dig("tracker", "provider", "api_resource") == "work-items"
      raise PlaneTrackerError, "tracker.provider.api_resource must use the current work-items API"
    end
    true
  end

  def preflight(identifier)
    item = find_item(identifier)
    {
      ok: true,
      identifier: identifier,
      title: item.fetch("name"),
      state: state_name_for(item.fetch("state")),
      priority: item["priority"],
      updated_at: item["updated_at"],
      url: item_url(identifier)
    }
  end

  def start(identifier, apply: false)
    item = find_item(identifier)
    current = state_name_for(item.fetch("state"))
    target = @completion.fetch("start_state")
    active_states = Array(@tracker.fetch("active_states"))

    if current == target
      return {
        ok: true,
        applied: false,
        identifier: identifier,
        state: current,
        message: "already in #{target}",
        readback: "verified"
      }
    end
    unless active_states.include?(current) && current == "Todo"
      raise PlaneTrackerError, "cannot start #{identifier} from #{current}; expected Todo or #{target}"
    end

    unless apply
      return { ok: true, applied: false, dry_run: true, identifier: identifier, from: current, to: target }
    end

    update_item_state(item.fetch("id"), state_id_for(target))
    @all_items = nil
    readback = find_item(identifier)
    actual = state_name_for(readback.fetch("state"))
    raise PlaneTrackerError, "start readback mismatch: expected #{target}, got #{actual}" unless actual == target

    { ok: true, applied: true, identifier: identifier, from: current, to: actual, readback: "verified" }
  end

  def create(input_path, apply: false)
    payload = load_json_file(input_path)
    title = required_string(payload, "title")
    priority = payload.fetch("priority", "none").to_s
    allowed_priorities = %w[none urgent high medium low]
    raise PlaneTrackerError, "invalid priority #{priority}" unless allowed_priorities.include?(priority)
    target_state = payload.fetch("state", @completion.fetch("start_state")).to_s
    allowed_states = Array(@tracker.fetch("active_states"))
    unless allowed_states.include?(target_state)
      raise PlaneTrackerError, "new work item state must be one of #{allowed_states.join(', ')}"
    end

    exact = all_items.select { |item| item.fetch("name").strip.casecmp?(title.strip) }
    raise PlaneTrackerError, "duplicate title match: #{title}" if exact.length > 1
    unless exact.empty?
      existing = exact.first
      return {
        ok: true,
        applied: false,
        existing: true,
        identifier: identifier_for(existing),
        title: existing.fetch("name"),
        state: state_name_for(existing.fetch("state")),
        readback: "verified"
      }
    end

    request_body = {
      "name" => title,
      "description_html" => payload.fetch("description_html", ""),
      "priority" => priority,
      "state" => state_id_for(target_state)
    }
    unless apply
      return { ok: true, applied: false, dry_run: true, title: title, state: target_state, priority: priority }
    end

    created = request_json("post", work_items_path, body: request_body)
    identifier = identifier_for(created)
    @all_items = nil
    readback = find_item(identifier)
    unless readback.fetch("id") == created.fetch("id") && readback.fetch("name") == title
      raise PlaneTrackerError, "create readback mismatch for #{identifier}"
    end
    {
      ok: true,
      applied: true,
      identifier: identifier,
      title: title,
      state: state_name_for(readback.fetch("state")),
      url: item_url(identifier),
      readback: "verified"
    }
  end

  def closeout(identifier, input_path, apply: false)
    closeout = validated_closeout(identifier, input_path)
    item = find_item(identifier)
    current_state = state_name_for(item.fetch("state"))
    required_state = @completion.fetch("start_state")
    unless current_state == required_state
      raise PlaneTrackerError,
            "cannot close out #{identifier} from #{current_state}; expected #{required_state} after preflight/start"
    end
    target_state = closeout.fetch("target_state")
    closeout_id_value = closeout_id(closeout)
    html = render_workpad(closeout, closeout_id_value)
    existing_comment = workpad_comment(item.fetch("id"))

    unless apply
      return {
        ok: true,
        applied: false,
        dry_run: true,
        identifier: identifier,
        from: current_state,
        to: target_state,
        workpad_action: existing_comment ? "update" : "create",
        closeout_id: closeout_id_value
      }
    end

    upsert_workpad(item.fetch("id"), html, existing_comment)
    update_item_state(item.fetch("id"), state_id_for(target_state)) unless current_state == target_state
    @all_items = nil
    verify_result = verify(identifier, input_path)
    verify_result.merge(applied: true, workpad_action: existing_comment ? "updated" : "created")
  end

  def verify(identifier, input_path)
    closeout = validated_closeout(identifier, input_path)
    expected_state = closeout.fetch("target_state")
    expected_closeout = closeout_id(closeout)
    item = find_item(identifier)
    actual_state = state_name_for(item.fetch("state"))
    comment = workpad_comment(item.fetch("id"))
    raise PlaneTrackerError, "workpad readback missing for #{identifier}" unless comment

    comment_text = [comment["comment_stripped"], comment["comment_html"]].compact.join(" ")
    unless comment_text.include?(expected_closeout)
      raise PlaneTrackerError, "workpad readback mismatch for #{identifier}: closeout #{expected_closeout} not found"
    end
    unless actual_state == expected_state
      raise PlaneTrackerError, "state readback mismatch for #{identifier}: expected #{expected_state}, got #{actual_state}"
    end

    {
      ok: true,
      identifier: identifier,
      state: actual_state,
      closeout_id: expected_closeout,
      workpad: "verified",
      readback: "verified",
      url: item_url(identifier)
    }
  end

  private

  def validated_closeout(identifier, input_path)
    payload = load_json_file(input_path)
    payload_identifier = required_string(payload, "issue_identifier")
    raise PlaneTrackerError, "closeout issue does not match --issue" unless payload_identifier == identifier
    validate_identifier!(identifier)
    required_string(payload, "summary")

    validation = payload["validation"]
    raise PlaneTrackerError, "validation must be a non-empty array" unless validation.is_a?(Array) && !validation.empty?
    validation.each_with_index do |entry, index|
      raise PlaneTrackerError, "validation[#{index}] must be an object" unless entry.is_a?(Hash)
      required_string(entry, "command")
      result = required_string(entry, "result")
      required_string(entry, "evidence_class")
      raise PlaneTrackerError, "invalid validation result #{result}" unless ALLOWED_RESULTS.include?(result)
    end

    changed_files = payload["changed_files"]
    raise PlaneTrackerError, "changed_files must be an array" unless changed_files.is_a?(Array)
    validate_non_empty_string_array!(changed_files, "changed_files")

    open_gates = payload["open_gates"]
    raise PlaneTrackerError, "open_gates must be an array" unless open_gates.is_a?(Array)
    validate_non_empty_string_array!(open_gates, "open_gates")
    unless [true, false].include?(payload["acceptance_complete"])
      raise PlaneTrackerError, "acceptance_complete must be true or false"
    end
    target_state = required_string(payload, "target_state")
    allowed_targets = [@completion.fetch("complete_state"), @completion.fetch("incomplete_state")]
    raise PlaneTrackerError, "target_state must be one of #{allowed_targets.join(', ')}" unless allowed_targets.include?(target_state)

    if target_state == @completion.fetch("complete_state")
      failures = validation.reject { |entry| entry["result"] == "passed" }
      raise PlaneTrackerError, "Done requires every validation result to be passed" unless failures.empty?
      raise PlaneTrackerError, "Done requires open_gates to be empty" unless open_gates.empty?
      raise PlaneTrackerError, "Done requires acceptance_complete=true" unless payload["acceptance_complete"] == true
    else
      unless payload["acceptance_complete"] == false
        raise PlaneTrackerError, "In Progress requires acceptance_complete=false"
      end
      unresolved_validation = validation.any? { |entry| entry["result"] != "passed" }
      unless unresolved_validation || !open_gates.empty?
        raise PlaneTrackerError, "In Progress requires a named open gate or non-passing validation"
      end
    end

    payload
  end

  def validate_non_empty_string_array!(values, field)
    values.each_with_index do |value, index|
      unless value.is_a?(String) && !value.strip.empty?
        raise PlaneTrackerError, "#{field}[#{index}] must be a non-empty string"
      end
    end
  end

  def render_workpad(closeout, closeout_id_value)
    marker = escape(@workpad.fetch("marker"))
    summary = escape(closeout.fetch("summary"))
    changed_files = Array(closeout["changed_files"])
    validations = closeout.fetch("validation")
    open_gates = closeout.fetch("open_gates")
    repo = repo_snapshot

    files_html = if changed_files.empty?
                   "<li>None recorded</li>"
                 else
                   changed_files.map { |file| "<li><code>#{escape(file)}</code></li>" }.join
                 end
    validation_html = validations.map do |entry|
      "<li><code>#{escape(entry.fetch('command'))}</code> - #{escape(entry.fetch('result'))} (#{escape(entry.fetch('evidence_class'))})</li>"
    end.join
    gates_html = if open_gates.empty?
                   "<li>None</li>"
                 else
                   open_gates.map { |gate| "<li>#{escape(gate)}</li>" }.join
                 end

    <<~HTML
      <p>#{marker} | closeout #{escape(closeout_id_value)}</p>
      <h2>#{escape(@workpad.fetch('heading'))}</h2>
      <p><strong>Updated:</strong> #{escape(Time.now.utc.iso8601)}</p>
      <h3>Summary</h3>
      <p>#{summary}</p>
      <h3>Repository scope</h3>
      <p><strong>Branch:</strong> <code>#{escape(repo[:branch])}</code><br><strong>Commit:</strong> <code>#{escape(repo[:commit])}</code><br><strong>Worktree:</strong> #{escape(repo[:dirty])}</p>
      <ul>#{files_html}</ul>
      <h3>Validation</h3>
      <ul>#{validation_html}</ul>
      <h3>Open gates</h3>
      <ul>#{gates_html}</ul>
      <h3>Tracker outcome</h3>
      <p><strong>State:</strong> #{escape(closeout.fetch('target_state'))}<br><strong>Acceptance complete:</strong> #{closeout['acceptance_complete'] == true ? 'yes' : 'no'}</p>
    HTML
  end

  def repo_snapshot
    branch = git_output("rev-parse", "--abbrev-ref", "HEAD")
    commit = git_output("rev-parse", "--short", "HEAD")
    status = git_output("status", "--porcelain")
    { branch: branch, commit: commit, dirty: status.empty? ? "clean" : "dirty; closeout applies only to the files listed above" }
  end

  def git_output(*args)
    stdout, status = Open3.capture2("git", "-C", ROOT, *args)
    raise PlaneTrackerError, "git #{args.join(' ')} failed" unless status.success?
    stdout.strip
  end

  def upsert_workpad(item_id, html, existing)
    body = {
      "comment_html" => html,
      "comment_json" => {},
      "access" => "INTERNAL",
      "external_source" => "codex",
      "external_id" => "dosetap-agent-workpad:#{item_id}"
    }
    if existing
      request_json("patch", "#{work_items_path}#{item_id}/comments/#{existing.fetch('id')}/", body: body)
    else
      request_json("post", "#{work_items_path}#{item_id}/comments/", body: body)
    end
  end

  def workpad_comment(item_id)
    comments = paged_results("#{work_items_path}#{item_id}/comments/?limit=100")
    marker = @workpad.fetch("marker")
    matches = comments.select do |comment|
      [comment["comment_stripped"], comment["comment_html"]].compact.join(" ").include?(marker)
    end
    raise PlaneTrackerError, "multiple workpad comments found; refusing ambiguous update" if matches.length > 1
    matches.first
  end

  def update_item_state(item_id, state_id)
    request_json("patch", "#{work_items_path}#{item_id}/", body: { "state" => state_id })
  end

  def find_item(identifier)
    validate_identifier!(identifier)
    sequence = identifier.split("-", 2).last.to_i
    matches = all_items.select { |item| item["sequence_id"].to_i == sequence }
    raise PlaneTrackerError, "no exact Plane work item found for #{identifier}" if matches.empty?
    raise PlaneTrackerError, "multiple Plane work items found for #{identifier}" if matches.length > 1
    matches.first
  end

  def all_items
    @all_items ||= paged_results("#{work_items_path}?per_page=100")
  end

  def states
    @states ||= paged_results("/api/v1/workspaces/#{workspace_slug}/projects/#{project_id}/states/")
  end

  def state_name_for(state_id)
    state = states.find { |candidate| candidate["id"] == state_id }
    raise PlaneTrackerError, "unknown Plane state id #{state_id}" unless state
    state.fetch("name")
  end

  def state_id_for(name)
    matches = states.select { |state| state.fetch("name").casecmp?(name) }
    raise PlaneTrackerError, "no Plane state named #{name}" if matches.empty?
    raise PlaneTrackerError, "multiple Plane states named #{name}" if matches.length > 1
    matches.first.fetch("id")
  end

  def identifier_for(item)
    "#{@provider.fetch('project_identifier')}-#{item.fetch('sequence_id')}"
  end

  def validate_identifier!(identifier)
    pattern = Regexp.new(@config.fetch("identity").fetch("identifier_pattern"))
    raise PlaneTrackerError, "invalid work item identifier #{identifier}" unless pattern.match?(identifier)
  end

  def closeout_id(payload)
    Digest::SHA256.hexdigest(JSON.generate(deep_sort(payload)))[0, 16]
  end

  def deep_sort(value)
    case value
    when Hash
      value.keys.sort.each_with_object({}) { |key, result| result[key] = deep_sort(value[key]) }
    when Array
      value.map { |entry| deep_sort(entry) }
    else
      value
    end
  end

  def required_string(hash, key)
    value = hash[key]
    raise PlaneTrackerError, "#{key} must be a non-empty string" unless value.is_a?(String) && !value.strip.empty?
    value
  end

  def load_json_file(path)
    JSON.parse(File.read(File.expand_path(path, Dir.pwd)))
  rescue Errno::ENOENT => e
    raise PlaneTrackerError, "missing input file: #{e.message}"
  rescue JSON::ParserError => e
    raise PlaneTrackerError, "invalid closeout JSON: #{e.message}"
  end

  def paged_results(path)
    entries = []
    current_path = path
    seen_cursors = {}

    loop do
      payload = request_json("get", current_path)
      return payload if payload.is_a?(Array) && entries.empty?
      unless payload.is_a?(Hash) && payload["results"].is_a?(Array)
        raise PlaneTrackerError, "unexpected Plane list response"
      end

      entries.concat(payload.fetch("results"))
      break unless payload["next_page_results"] == true

      cursor = payload["next_cursor"].to_s
      raise PlaneTrackerError, "Plane pagination omitted next_cursor" if cursor.empty?
      raise PlaneTrackerError, "Plane pagination repeated cursor #{cursor}" if seen_cursors[cursor]
      seen_cursors[cursor] = true
      current_path = with_query_parameter(path, "cursor", cursor)
    end

    entries
  end

  def with_query_parameter(path, key, value)
    uri = URI.parse(path)
    query = URI.decode_www_form(uri.query.to_s)
    query.reject! { |candidate, _| candidate == key }
    query << [key, value]
    uri.query = URI.encode_www_form(query)
    uri.to_s
  end

  def request_json(method, path, body: nil)
    uri = URI.join(origin + "/", path.sub(%r{\A/}, ""))
    request_class = {
      "get" => Net::HTTP::Get,
      "post" => Net::HTTP::Post,
      "patch" => Net::HTTP::Patch
    }.fetch(method)
    request = request_class.new(uri)
    request["X-API-Key"] = api_key
    request["Accept"] = "application/json"
    if body
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(body)
    end

    response = Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: 5,
      read_timeout: 20
    ) { |http| http.request(request) }
    unless response.code.to_i.between?(200, 299)
      raise PlaneTrackerError, "Plane request failed: HTTP #{response.code} for #{method.upcase} #{uri.path}"
    end
    return {} if response.body.nil? || response.body.strip.empty?
    JSON.parse(response.body)
  rescue SocketError, SystemCallError, Timeout::Error, Net::OpenTimeout, Net::ReadTimeout => e
    raise PlaneTrackerError, "Plane request failed: #{e.class}: #{e.message}"
  rescue JSON::ParserError => e
    raise PlaneTrackerError, "Plane returned invalid JSON: #{e.message}"
  end

  def origin
    @origin ||= begin
      configured = ENV[@provider.fetch("base_url_env")]
      configured = env_file_url if configured.nil? || configured.strip.empty?
      if configured.nil? || configured.strip.empty?
        raise PlaneTrackerError, "missing Plane base URL in #{@provider.fetch('base_url_env')} or #{@provider.fetch('env_file')}"
      end
      uri = URI.parse(configured.strip)
      raise PlaneTrackerError, "Plane URL must use http or https" unless %w[http https].include?(uri.scheme)
      if @config.dig("security", "local_plane_only") == true && !local_plane_host?(uri.host)
        raise PlaneTrackerError, "Plane URL must resolve through localhost when security.local_plane_only is true"
      end
      default_port = (uri.scheme == "https" ? 443 : 80)
      port = uri.port == default_port ? "" : ":#{uri.port}"
      "#{uri.scheme}://#{uri.host}#{port}"
    rescue URI::InvalidURIError => e
      raise PlaneTrackerError, "invalid Plane URL: #{e.message}"
    end
  end

  def local_plane_host?(host)
    normalized = host.to_s.downcase
    return true if normalized == "localhost" || normalized.end_with?(".localhost")

    IPAddr.new(normalized).loopback?
  rescue IPAddr::InvalidAddressError
    false
  end

  def api_key
    @api_key ||= begin
      env_name = @provider.fetch("api_key_env")
      value = ENV[env_name]
      value = env_file_assignment(env_name) if value.nil? || value.strip.empty?
      if value.nil? || value.strip.empty?
        raise PlaneTrackerError, "missing Plane API key in #{env_name} or #{@provider.fetch('env_file')}"
      end
      value.strip
    end
  end

  def env_lines
    @env_lines ||= begin
      path = File.expand_path(@provider.fetch("env_file"), ROOT)
      File.readlines(path, chomp: true)
    rescue Errno::ENOENT
      []
    end
  end

  def env_file_url
    env_lines.map(&:strip).find { |line| line.start_with?("http://", "https://") }
  end

  def env_file_assignment(name)
    prefix = "#{name}="
    line = env_lines.find { |candidate| candidate.lstrip.start_with?(prefix) }
    return nil unless line
    line.lstrip.delete_prefix(prefix).strip.sub(/\A["']/, "").sub(/["']\z/, "")
  end

  def workspace_slug
    @provider.fetch("workspace_slug")
  end

  def project_id
    @provider.fetch("project_id")
  end

  def work_items_path
    "/api/v1/workspaces/#{workspace_slug}/projects/#{project_id}/work-items/"
  end

  def item_url(identifier)
    "#{origin}/#{workspace_slug}/browse/#{identifier}/"
  end

  def escape(value)
    CGI.escapeHTML(value.to_s)
  end
end

def parse_options(command, arguments)
  options = { apply: false, config: PlaneTracker::DEFAULT_CONFIG }
  parser = OptionParser.new do |opts|
    opts.banner = "Usage: plane_tracker.rb #{command} [options]"
    opts.on("--issue IDENTIFIER", "Exact Plane identifier, for example DOSETAP-34") { |value| options[:issue] = value }
    opts.on("--input PATH", "JSON input for create, closeout, or verify") { |value| options[:input] = value }
    opts.on("--config PATH", "Plane workflow YAML path") { |value| options[:config] = value }
    opts.on("--apply", "Perform the write; omitted means dry-run") { options[:apply] = true }
  end
  parser.parse!(arguments)
  [options, parser]
end

def plane_tracker_main(arguments)
  command = arguments.shift
  unless command
    raise PlaneTrackerError, "command required: validate-config, preflight, start, create, closeout, or verify"
  end
  options, parser = parse_options(command, arguments)
  tracker = PlaneTracker.new(config_path: options[:config])

  result = case command
           when "validate-config"
             { ok: true, config: options[:config], tracker: "plane", api_resource: "work-items" }
           when "preflight"
             raise PlaneTrackerError, parser.to_s unless options[:issue]
             tracker.preflight(options[:issue])
           when "start"
             raise PlaneTrackerError, parser.to_s unless options[:issue]
             tracker.start(options[:issue], apply: options[:apply])
           when "create"
             raise PlaneTrackerError, parser.to_s unless options[:input]
             tracker.create(options[:input], apply: options[:apply])
           when "closeout"
             raise PlaneTrackerError, parser.to_s unless options[:issue] && options[:input]
             tracker.closeout(options[:issue], options[:input], apply: options[:apply])
           when "verify"
             raise PlaneTrackerError, parser.to_s unless options[:issue] && options[:input]
             tracker.verify(options[:issue], options[:input])
           else
             raise PlaneTrackerError, "unknown command #{command}"
           end
  puts JSON.pretty_generate(result)
  0
rescue PlaneTrackerError, OptionParser::ParseError => e
  warn JSON.generate(ok: false, error: e.message)
  1
end

exit(plane_tracker_main(ARGV)) if __FILE__ == $PROGRAM_NAME
