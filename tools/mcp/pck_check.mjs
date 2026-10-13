#!/usr/bin/env node
// Lists what a Godot .pck holds and fails if anything of the MCP toolkit shipped.
//
//   node tools/mcp/pck_check.mjs <file.pck> [--addon-dir addons/godot_mcp_toolkit]
//
// The addon folder is found from the plugin.cfg named "MCP Toolkit" under addons/ (tools/mcp/project_plugin.mjs), so
// nothing here hardcodes the toolkit. Exits 1 when the pack holds a path under that
// folder, a `.mcp.json`, or an autoload entry that points into it (read out of res://project.binary).
// Reads PCK format versions 2 and 3 (Godot 4.0 to 4.5+); it never runs Godot and needs no templates.
// See tools/mcp/README.md ("Exports") for how to make a pack without export templates.

import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { toolkitDir } from "./project_plugin.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const projectRoot = resolve(here, "..", "..");

/** The toolkit's folder, found by the name in its plugin.cfg (the plugin is not enabled in the committed project.godot). */
export function addonDirs(root = projectRoot) {
	return [toolkitDir(root)];
}

/** Parses the file table of a .pck. Returns [{ path, offset, size }]. */
export function readPck(buf) {
	if (buf.toString("latin1", 0, 4) !== "GDPC") throw new Error("not a Godot .pck (no GDPC magic)");
	let p = 4;
	const u32 = () => { const v = buf.readUInt32LE(p); p += 4; return v; };
	const u64 = () => { const v = Number(buf.readBigUInt64LE(p)); p += 8; return v; };
	const version = u32();
	p += 12; // engine major, minor, patch
	let flags = 0;
	let fileBase = 0;
	if (version >= 2) { flags = u32(); fileBase = u64(); }
	if (version >= 3) { p = u64(); } else { p += 64; } // v3 stores the directory offset; v2 has 16 reserved words
	const count = u32();
	const files = [];
	for (let i = 0; i < count; i++) {
		const len = u32();
		const path = buf.toString("utf8", p, p + len).replace(/\0+$/, "");
		p += len;
		const offset = u64() + ((flags & 2) !== 0 ? fileBase : 0);
		const size = u64();
		p += 16; // md5
		if (version >= 2) p += 4; // per-file flags
		files.push({ path, offset, size });
	}
	return files;
}

/**
 * Autoload entries recorded in res://project.binary, found by key name rather than by parsing variants.
 * Each is `{ name, intoDir }`, where `intoDir` says whether the value that follows the key points into
 * one of `dirs` (the value is the next few dozen bytes: a short string like "*res://addons/x/y.gd").
 */
export function autoloadsIn(binary, dirs = []) {
	const text = binary.toString("latin1");
	const out = [];
	for (const m of text.matchAll(/autoload\/([A-Za-z0-9_]+)/g)) {
		const after = text.slice(m.index + m[0].length, m.index + m[0].length + 160);
		out.push({ name: m[1], intoDir: dirs.some((d) => after.includes(d + "/")) });
	}
	return out;
}

function main() {
	const args = process.argv.slice(2);
	const pckPath = args.find((a) => !a.startsWith("--"));
	if (!pckPath) { console.error("usage: node tools/mcp/pck_check.mjs <file.pck> [--addon-dir <res-relative dir>]"); process.exit(2); }
	const flag = args.indexOf("--addon-dir");
	const dirs = flag >= 0 ? [args[flag + 1]] : addonDirs();
	if (dirs.length === 0) { console.error("no MCP Toolkit addon under addons/ and no --addon-dir given"); process.exit(2); }

	const buf = readFileSync(pckPath);
	const files = readPck(buf);
	const problems = [];
	for (const dir of dirs) {
		const hits = files.filter((f) => f.path.replace(/^res:\/\//, "").startsWith(dir + "/"));
		console.log(`paths under ${dir}/: ${hits.length}`);
		for (const h of hits.slice(0, 10)) problems.push(`packed path under the addon folder: ${h.path}`);
	}
	const dotMcp = files.filter((f) => /(^|\/)\.mcp\.json$/.test(f.path));
	console.log(`.mcp.json entries: ${dotMcp.length}`);
	for (const f of dotMcp) problems.push(`packed ${f.path}`);

	const pb = files.find((f) => f.path.replace(/^res:\/\//, "") === "project.binary");
	if (!pb) {
		problems.push("no project.binary in the pack, so the autoload list could not be checked");
	} else {
		const autoloads = autoloadsIn(buf.subarray(pb.offset, pb.offset + pb.size), dirs);
		console.log(`autoloads in project.binary: ${autoloads.length ? autoloads.map((a) => a.name).join(", ") : "(none)"}`);
		for (const a of autoloads) {
			if (a.intoDir) problems.push(`autoload ${a.name} points into the addon folder`);
		}
	}
	console.log(`${files.length} files in the pack`);
	if (problems.length) {
		console.error("\nFAIL: the pack holds MCP toolkit content:");
		for (const p of problems) console.error("  " + p);
		process.exit(1);
	}
	console.log("OK: nothing of the MCP toolkit is in the pack, and no toolkit autoload");
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
