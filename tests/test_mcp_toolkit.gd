extends "res://tests/test_case.gd"
## TOOL-3 (#210): the godot-mcp-toolkit editor plugin and its npm bridge are installed so agents can drive the
## running game, and none of it reaches the game, the tests or a shipped build.
##
## Every path here comes from the addon's own plugin.cfg (found by its name), from project.godot, from
## export_presets.cfg or from .mcp.json: no folder name, autoload name or version is written into this file, so an
## upgrade of the addon changes no test.
##
## The committed project.godot leaves the plugin OFF (tools/mcp/editor.sh switches it on for a session): the plugin
## writes a runtime autoload into project.godot whenever the editor loads it, and with that line present every plain
## `godot --path .` run would open a listener on 127.0.0.1:6570-6585. If a test here fails because project.godot
## holds the plugin or its autoload, an editor session left them behind: run `tools/mcp/editor.sh --strip`.
## (If the team decides to enable the plugin for everyone, change test_project_godot_leaves_the_toolkit_out and
## tools/mcp/README.md together.)

const ADDONS := "res://addons"
const PROJECT := "res://project.godot"
const EXPORT_PRESETS := "res://export_presets.cfg"
const MCP_JSON := "res://.mcp.json"
const README := "res://tools/mcp/README.md"
const WALK := "res://tools/mcp/walk_turn1.json"
## What plugin.cfg's `name` holds for this addon (a name, not a path).
const TOOLKIT_NAME := "MCP Toolkit"
## The desktop platforms a shipped build can target; each preset for one of them must leave the addon out.
const DESKTOP_PLATFORMS := ["macOS", "Windows Desktop", "Linux", "Linux/X11"]
const FIX := " (an editor session left it behind: run tools/mcp/editor.sh --strip)"


## "res://addons/<folder>" of the toolkit, found by the name in its plugin.cfg; "" when it is not installed.
func _toolkit_dir() -> String:
	for folder in DirAccess.get_directories_at(ADDONS):
		var cfg := ConfigFile.new()
		if cfg.load("%s/%s/plugin.cfg" % [ADDONS, folder]) == OK and String(cfg.get_value("plugin", "name", "")).contains(TOOLKIT_NAME):
			return "%s/%s" % [ADDONS, folder]
	return ""


func _plugin_cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(_toolkit_dir() + "/plugin.cfg")
	return cfg


func _text(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _json(path: String) -> Variant:
	return JSON.parse_string(_text(path))


## Every file under `dir`, as res:// paths.
func _files_under(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_files_under(dir.path_join(d)))
	return out


## Whether a preset's exclude_filter drops `path` (a res:// path). Godot reads the filter as comma-separated globs and
## accepts them with or without the res:// prefix.
func _excluded(exclude_filter: String, path: String) -> bool:
	for raw in exclude_filter.split(","):
		var f := raw.strip_edges()
		if f.is_empty():
			continue
		if path.matchn(f) or path.matchn("res://" + f):
			return true
	return false


## The section ids of export_presets.cfg's presets (preset.0, preset.1, ...), not their .options.
func _preset_sections(cfg: ConfigFile) -> PackedStringArray:
	var out := PackedStringArray()
	for s in cfg.get_sections():
		if s.begins_with("preset.") and not s.ends_with(".options"):
			out.append(s)
	return out


# --- the addon ---------------------------------------------------------------------------------------------------


func test_the_addon_is_installed_with_its_plugin_cfg() -> void:
	var dir := _toolkit_dir()
	assert_false(dir.is_empty(), "an addon whose plugin.cfg is named '%s' is under res://addons" % TOOLKIT_NAME)
	var cfg := _plugin_cfg()
	assert_false(String(cfg.get_value("plugin", "version", "")).is_empty(), "plugin.cfg carries a version")
	var script := String(cfg.get_value("plugin", "script", ""))
	assert_true(FileAccess.file_exists(dir.path_join(script)), "the plugin script %s exists" % script)
	assert_true(FileAccess.file_exists(dir.path_join("LICENSE")), "the addon's MIT license travels with it")


func test_the_readme_records_the_release_and_the_bridge_pin() -> void:
	assert_true(FileAccess.file_exists(README), "tools/mcp/README.md exists")
	var readme := _text(README)
	var version := String(_plugin_cfg().get_value("plugin", "version", ""))
	assert_true(readme.contains("v" + version), "the README names the release tag v%s" % version)
	var sha := RegEx.create_from_string("\\b[0-9a-f]{40}\\b")
	assert_true(sha.search(readme) != null, "the README records the release's full commit SHA")
	var pinned := _bridge_spec()
	assert_true(not pinned.is_empty() and readme.contains(pinned), "the README names the pinned bridge %s" % pinned)


# --- the bridge in .mcp.json -------------------------------------------------------------------------------------


## The "<package>@<version>" argument of the one MCP server in .mcp.json ("" when there is none).
func _bridge_spec() -> String:
	var cfg: Variant = _json(MCP_JSON)
	if not (cfg is Dictionary) or not (cfg.get("mcpServers") is Dictionary):
		return ""
	for name in cfg.mcpServers:
		for arg in cfg.mcpServers[name].get("args", []):
			if String(arg).begins_with("@") or String(arg).contains("@"):
				return String(arg)
	return ""


func test_mcp_json_pins_the_bridge_to_an_exact_version() -> void:
	var cfg: Variant = _json(MCP_JSON)
	assert_true(cfg is Dictionary and cfg.get("mcpServers") is Dictionary, ".mcp.json parses and has mcpServers")
	if not (cfg is Dictionary):
		return
	assert_eq(cfg.mcpServers.size(), 1, "one MCP server: the toolkit's bridge")
	var exact := RegEx.create_from_string("^@?[a-z0-9][a-z0-9._/-]*@\\d+\\.\\d+\\.\\d+$")
	var spec := _bridge_spec()
	assert_true(exact.search(spec) != null, "the bridge argument '%s' is <package>@<major.minor.patch>, never a range or 'latest'" % spec)
	for name in cfg.mcpServers:
		var args: Array = cfg.mcpServers[name].get("args", [])
		assert_eq(String(cfg.mcpServers[name].get("command", "")), "npx", "%s starts through npx" % name)
		assert_true(args.has(spec), "%s's arguments hold the pinned package" % name)


func test_mcp_json_holds_no_secret() -> void:
	var text := _text(MCP_JSON)
	var token := RegEx.create_from_string("\\b[0-9a-fA-F]{64}\\b")
	assert_true(token.search(text) == null, "no 64-hex token in .mcp.json (the session token lives in user://, never in a file)")
	var cfg: Variant = _json(MCP_JSON)
	if not (cfg is Dictionary):
		return
	for name in cfg.mcpServers:
		for key in cfg.mcpServers[name].get("env", {}):
			var upper := String(key).to_upper()
			for word in ["TOKEN", "SECRET", "PASSWORD", "API_KEY", "APIKEY"]:
				assert_false(upper.contains(word), "%s's env has no %s-like key (%s)" % [name, word, key])


# --- project.godot -----------------------------------------------------------------------------------------------


func test_project_godot_leaves_the_toolkit_out() -> void:
	var dir := _toolkit_dir()
	var project := ConfigFile.new()
	assert_eq(project.load(PROJECT), OK, "project.godot parses")
	for key in project.get_section_keys("autoload"):
		var value := String(project.get_value("autoload", key, "")).trim_prefix("*")
		assert_false(value.begins_with(dir + "/"),
			"the toolkit's runtime autoload is not a permanent autoload: [autoload] %s=%s is in project.godot%s" % [key, value, FIX])
	var enabled: Variant = project.get_value("editor_plugins", "enabled", PackedStringArray())
	assert_false(enabled.has(dir + "/plugin.cfg"),
		"the committed project.godot leaves the plugin off; tools/mcp/editor.sh switches it on for a session%s" % FIX)
	assert_false(project.has_section("mcp_toolkit"), "no [mcp_toolkit] settings in project.godot%s" % FIX)


func test_no_toolkit_node_is_loaded_in_this_run() -> void:
	# A plain run of the game (this runner included) must not carry the toolkit's runtime autoload.
	var dir := _toolkit_dir()
	var root := (Engine.get_main_loop() as SceneTree).root
	for child in root.get_children():
		var script: Script = child.get_script()
		assert_false(script != null and script.resource_path.begins_with(dir + "/"),
			"%s at the root of this run is the toolkit's: its autoload must not be on%s" % [child.name, FIX])


# --- exports -----------------------------------------------------------------------------------------------------


func test_every_export_preset_excludes_the_whole_addon() -> void:
	var dir := _toolkit_dir()
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(EXPORT_PRESETS), OK, "export_presets.cfg parses")
	var presets := _preset_sections(cfg)
	assert_false(presets.is_empty(), "there is an export preset")
	var desktop := 0
	var files := _files_under(dir)
	assert_false(files.is_empty(), "the addon has files to leave out")
	for section in presets:
		var platform := String(cfg.get_value(section, "platform", ""))
		if DESKTOP_PLATFORMS.has(platform):
			desktop += 1
		var filter := String(cfg.get_value(section, "exclude_filter", ""))
		var kept := PackedStringArray()
		for f in files:
			if not _excluded(filter, f):
				kept.append(f)
		assert_true(kept.is_empty(), "%s (%s) excludes every file under %s; still shipped: %s" % [
			cfg.get_value(section, "name", section), platform, dir, ", ".join(kept.slice(0, 3))])
	assert_true(desktop >= 1, "at least one desktop preset (%s)" % ", ".join(DESKTOP_PLATFORMS))


func test_the_exclude_check_notices_a_filter_that_misses_the_addon() -> void:
	# The check above is only worth something if a wrong filter fails it.
	var dir := _toolkit_dir()
	var some_file := dir + "/plugin.cfg"
	assert_true(_excluded(dir.trim_prefix("res://") + "/*", some_file), "the relative folder glob drops the addon")
	assert_true(_excluded("*.tmp, " + dir + "/*", some_file), "a glob in a list drops the addon")
	assert_false(_excluded("", some_file), "no filter drops nothing")
	assert_false(_excluded("addons/some_other_addon/*", some_file), "another folder's glob drops nothing here")
	assert_false(_excluded(dir.trim_prefix("res://"), some_file), "a bare folder name matches no file")


# --- the recorded walk ---------------------------------------------------------------------------------------------


func test_the_recorded_walk_is_a_list_of_tool_calls() -> void:
	var steps: Variant = _json(WALK)
	assert_true(steps is Array and not (steps as Array).is_empty(), "tools/mcp/walk_turn1.json parses to a list of steps")
	if not (steps is Array):
		return
	for i in steps.size():
		var step: Dictionary = steps[i]
		assert_true(step.has("tool") or step.has("sleep_ms"), "step %d is a tool call or a sleep" % (i + 1))
		if step.has("tool"):
			assert_true(step.get("args", {}) is Dictionary, "step %d's args are an object" % (i + 1))
