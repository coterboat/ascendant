#!/usr/bin/env node
// Switches the toolkit's editor plugin on or off in project.godot, as plain text edits, so an MCP session
// can open the editor with the plugin and leave project.godot exactly as it found it.
//
//   node tools/mcp/project_plugin.mjs enable    add the plugin to [editor_plugins] (the editor then loads it)
//   node tools/mcp/project_plugin.mjs strip     remove everything the toolkit put in project.godot: the plugin entry,
//                                               its runtime autoload, and its [mcp_toolkit] settings
//   node tools/mcp/project_plugin.mjs status    say what project.godot holds (exit 1 when it holds the autoload)
//   node tools/mcp/project_plugin.mjs --selftest
//
// Why this exists: the toolkit's plugin writes `MCPRuntimeServer="*res://addons/..."` into [autoload] every time
// the editor loads it (an upstream design choice, ADR 0013 in its repo), because the game reads project.godot at F5.
// With that line in project.godot, every plain `godot --path .` run (tests, boot checks, autoplay workers) opens a
// listener on 127.0.0.1:6570-6585 and writes the shared registry. So the committed project.godot leaves the plugin
// off, tools/mcp/editor.sh switches it on for a session, and `strip` puts project.godot back when the session ends.
// Other changes made to project.godot meanwhile (a setting an agent changed on purpose) are kept.

import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");

/** The toolkit's folder under addons/ (found by its plugin.cfg name, not hardcoded), e.g. "addons/godot_mcp_toolkit". */
export function toolkitDir(root = projectRoot) {
	const base = join(root, "addons");
	for (const d of readdirSync(base, { withFileTypes: true })) {
		if (!d.isDirectory()) continue;
		try {
			const cfg = readFileSync(join(base, d.name, "plugin.cfg"), "utf8");
			if (/^name="[^"]*MCP Toolkit[^"]*"/m.test(cfg)) return `addons/${d.name}`;
		} catch { /* no plugin.cfg in this folder */ }
	}
	throw new Error("no addon whose plugin.cfg is named MCP Toolkit under addons/");
}

const header = (l) => /^\[[^\]]+\]\s*$/.test(l);
const items = (line) => [...line.matchAll(/"([^"]*)"/g)].map((m) => m[1]);
const arrayLine = (list) => `enabled=PackedStringArray(${list.map((i) => `"${i}"`).join(", ")})`;

/** text with the plugin added to [editor_plugins] (the section is created when absent). */
export function enablePlugin(text, dir) {
	const cfg = `res://${dir}/plugin.cfg`;
	const lines = text.split("\n");
	const at = lines.findIndex((l) => l.trim() === "[editor_plugins]");
	if (at < 0) return text.replace(/\n*$/, "\n") + `\n[editor_plugins]\n\n${arrayLine([cfg])}\n`;
	let end = lines.findIndex((l, i) => i > at && header(l));
	if (end < 0) end = lines.length;
	const e = lines.findIndex((l, i) => i > at && i < end && /^enabled\s*=/.test(l));
	if (e < 0) lines.splice(at + 1, 0, "", arrayLine([cfg]));
	else {
		const list = items(lines[e]);
		if (!list.includes(cfg)) lines[e] = arrayLine([...list, cfg]);
	}
	return lines.join("\n");
}

/** text with everything the toolkit wrote taken out: its autoload, its plugin entry and its [mcp_toolkit] section. */
export function stripToolkit(text, dir) {
	const cfg = `res://${dir}/plugin.cfg`;
	const lines = text.split("\n");
	const out = [];
	let section = "";
	for (const l of lines) {
		if (header(l)) section = l.trim();
		if (section === "[mcp_toolkit]") continue;
		if (section === "[autoload]" && l.includes(`res://${dir}/`)) continue;
		if (section === "[editor_plugins]" && /^enabled\s*=/.test(l)) {
			const rest = items(l).filter((i) => i !== cfg);
			if (rest.length === 0) continue;
			out.push(arrayLine(rest));
			continue;
		}
		out.push(l);
	}
	// Drop an [editor_plugins] section that ended up empty (its header and the blank lines after it; the blank line
	// before it stays, so the neighbouring sections keep their spacing).
	const kept = [];
	for (let i = 0; i < out.length; i++) {
		if (out[i].trim() === "[editor_plugins]") {
			let j = i + 1;
			while (j < out.length && !header(out[j]) && out[j].trim() === "") j++;
			if (j >= out.length || header(out[j])) {
				i = j - 1;
				continue;
			}
		}
		kept.push(out[i]);
	}
	// A section dropped at the very end leaves the file ending in one newline, as before.
	return kept.join("\n").replace(/\n*$/, "\n");
}

/** What project.godot holds of the toolkit. */
export function statusOf(text, dir) {
	const lines = text.split("\n");
	let section = "";
	const found = { enabled: false, autoload: false, settings: false };
	for (const l of lines) {
		if (header(l)) { section = l.trim(); if (section === "[mcp_toolkit]") found.settings = true; }
		if (section === "[editor_plugins]" && /^enabled\s*=/.test(l) && l.includes(`res://${dir}/plugin.cfg`)) found.enabled = true;
		if (section === "[autoload]" && l.includes(`res://${dir}/`)) found.autoload = true;
	}
	return found;
}

function selftest() {
	const dir = "addons/godot_mcp_toolkit";
	const base = '; header\n\nconfig_version=5\n\n[autoload]\n\nAudio="*res://ui/audio.gd"\n\n[display]\n\nwindow/size/viewport_width=1600\n';
	const assert = (c, m) => { if (!c) { console.error("selftest FAILED: " + m); process.exit(1); } };
	const on = enablePlugin(base, dir);
	assert(statusOf(on, dir).enabled, "enable adds the plugin");
	assert(enablePlugin(on, dir) === on, "enable twice changes nothing");
	const session = on.replace('Audio="*res://ui/audio.gd"\n', `Audio="*res://ui/audio.gd"\nMCPRuntimeServer="*res://${dir}/runtime/mcp_runtime_server.gd"\n`) + "\n[mcp_toolkit]\n\ninternal/bootstrap_complete=true\n";
	assert(statusOf(session, dir).autoload && statusOf(session, dir).settings, "status sees the autoload and the settings");
	assert(stripToolkit(session, dir) === base, "strip returns the file to what it was");
	assert(stripToolkit(base, dir) === base, "strip of a clean file changes nothing");
	const others = base + '\n[editor_plugins]\n\nenabled=PackedStringArray("res://addons/other/plugin.cfg")\n';
	const both = enablePlugin(others, dir);
	assert(both.includes('"res://addons/other/plugin.cfg", "res://addons/godot_mcp_toolkit/plugin.cfg"'), "enable appends to another plugin's list");
	assert(stripToolkit(both, dir) === others, "strip leaves another plugin's entry alone");
	const kept = stripToolkit(session.replace("viewport_width=1600", "viewport_width=1280"), dir);
	assert(kept.includes("viewport_width=1280") && !statusOf(kept, dir).autoload, "strip keeps unrelated edits");
	console.log("selftest ok");
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
	const cmd = process.argv[2];
	if (cmd === "--selftest") selftest();
	else if (["enable", "strip", "status"].includes(cmd)) {
		const file = join(projectRoot, "project.godot");
		const dir = toolkitDir();
		const text = readFileSync(file, "utf8");
		if (cmd === "status") {
			const s = statusOf(text, dir);
			console.log(`project.godot: plugin ${s.enabled ? "enabled" : "not enabled"}, runtime autoload ${s.autoload ? "PRESENT" : "absent"}, [mcp_toolkit] settings ${s.settings ? "present" : "absent"}`);
			process.exit(s.autoload ? 1 : 0);
		}
		const next = cmd === "enable" ? enablePlugin(text, dir) : stripToolkit(text, dir);
		if (next === text) console.log(`project.godot: nothing to ${cmd}`);
		else { writeFileSync(file, next); console.log(`project.godot: ${cmd} done`); }
	} else {
		console.error("usage: node tools/mcp/project_plugin.mjs enable|strip|status|--selftest");
		process.exit(2);
	}
}
