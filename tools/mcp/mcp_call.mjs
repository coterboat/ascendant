#!/usr/bin/env node
// A small MCP client over stdio: a reusable smoke tool for the Godot MCP toolkit bridge.
//
// It starts the bridge EXACTLY the way .mcp.json says (same command, args, env; cwd = the project
// folder), then speaks JSON-RPC to it: initialize, tools/list, tools/call. Use it to prove the real
// bridge path works without loading a new MCP server into an agent session, and to script a walk.
//
//   node tools/mcp/mcp_call.mjs list                              startup tool list (count + names)
//   node tools/mcp/mcp_call.mjs counts [--activate g1,g2|all]     tool counts at startup and after discover_tools
//   node tools/mcp/mcp_call.mjs call <tool> ['<json args>']       one tools/call
//   node tools/mcp/mcp_call.mjs run <steps.json>                  a recipe: [{"tool": "...", "args": {...}}, {"sleep_ms": 500}, ...]
//                                                                 a step may also carry "capture": "name" (keep execute_code's result for
//                                                                 a later ${name} in args), "expect": "text", "until": "text" (call again
//                                                                 until the output has it), "continue_on_error", "note". See walk_turn1.json.
//
// Options (any position):
//   --project <dir>   project folder holding .mcp.json (default: the current directory). The bridge is
//                     started with this as its cwd, which is how it finds that project's own editor.
//   --env KEY=VALUE   extra environment for the bridge (repeatable), e.g. GODOT_MCP_READ_ONLY=1
//   --out <dir>       save image results here as PNG files (default: <tmp dir>/ascendant-mcp); text is printed
//   --timeout <ms>    per-request timeout (default 120000)
//   --full            print whole text results instead of cutting them at 1500 characters
//
// Nothing secret is printed: any 64-character hex string in output is replaced with <redacted-64hex>,
// because that is the shape of the toolkit's per-start auth token.
// Exit code: 0 ok, 1 a tool call returned isError (or a step failed), 2 usage / transport failure.

import { spawn } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const SERVER_KEY = "godot-mcp-toolkit";

export function redact(text) {
	return String(text).replace(/\b[0-9a-f]{64}\b/gi, "<redacted-64hex>");
}

/** Reads .mcp.json and returns the spawn spec for the toolkit server (nothing is hardcoded here). */
export function serverSpec(projectDir, extraEnv = {}) {
	const cfg = JSON.parse(readFileSync(join(projectDir, ".mcp.json"), "utf8"));
	const entry = cfg.mcpServers?.[SERVER_KEY];
	if (!entry) throw new Error(`.mcp.json has no "${SERVER_KEY}" server`);
	return {
		command: entry.command,
		args: entry.args ?? [],
		env: { ...process.env, ...(entry.env ?? {}), ...extraEnv },
		cwd: projectDir,
	};
}

/** A tiny JSON-RPC-over-stdio MCP client. Messages are newline-delimited JSON, as MCP's stdio transport defines. */
export class McpClient {
	constructor(spec, { timeoutMs = 120000, log = () => {} } = {}) {
		this.timeoutMs = timeoutMs;
		this.log = log;
		this.nextId = 1;
		this.pending = new Map();
		this.notifications = [];
		this.stderrTail = [];
		this.child = spawn(spec.command, spec.args, { cwd: spec.cwd, env: spec.env, stdio: ["pipe", "pipe", "pipe"] });
		this.exited = new Promise((res) => this.child.on("exit", (code, sig) => { this.exitInfo = { code, sig }; this._failAll(new Error(`bridge exited (${code ?? sig})`)); res(); }));
		this.child.on("error", (e) => this._failAll(e));
		let buf = "";
		this.child.stdout.setEncoding("utf8");
		this.child.stdout.on("data", (chunk) => {
			buf += chunk;
			let nl;
			while ((nl = buf.indexOf("\n")) >= 0) {
				const line = buf.slice(0, nl).trim();
				buf = buf.slice(nl + 1);
				if (line) this._onMessage(line);
			}
		});
		this.child.stderr.setEncoding("utf8");
		this.child.stderr.on("data", (chunk) => {
			for (const l of chunk.split("\n")) {
				if (!l.trim()) continue;
				this.stderrTail.push(l);
				if (this.stderrTail.length > 200) this.stderrTail.shift();
				this.log(`[bridge] ${l}`);
			}
		});
	}

	_failAll(err) {
		for (const { reject, timer } of this.pending.values()) { clearTimeout(timer); reject(err); }
		this.pending.clear();
	}

	_onMessage(line) {
		let msg;
		try { msg = JSON.parse(line); } catch { this.log(`[bridge stdout, not JSON] ${redact(line).slice(0, 200)}`); return; }
		if (msg.id !== undefined && (msg.result !== undefined || msg.error !== undefined) && this.pending.has(msg.id)) {
			const { resolve: ok, reject, timer } = this.pending.get(msg.id);
			clearTimeout(timer);
			this.pending.delete(msg.id);
			if (msg.error) reject(Object.assign(new Error(`${msg.error.message} (code ${msg.error.code})`), { rpc: msg.error }));
			else ok(msg.result);
		} else if (msg.method) {
			this.notifications.push(msg.method);
			if (msg.id !== undefined) this._send({ jsonrpc: "2.0", id: msg.id, result: {} }); // answer server->client requests (ping, ...) with an empty result
		}
	}

	_send(obj) { this.child.stdin.write(JSON.stringify(obj) + "\n"); }

	request(method, params = {}, timeoutMs = this.timeoutMs) {
		const id = this.nextId++;
		return new Promise((resolve, reject) => {
			const timer = setTimeout(() => { this.pending.delete(id); reject(new Error(`timeout after ${timeoutMs} ms waiting for ${method}`)); }, timeoutMs);
			this.pending.set(id, { resolve, reject, timer });
			this._send({ jsonrpc: "2.0", id, method, params });
		});
	}

	notify(method, params = {}) { this._send({ jsonrpc: "2.0", method, params }); }

	async initialize() {
		const result = await this.request("initialize", {
			protocolVersion: "2025-06-18",
			capabilities: {},
			clientInfo: { name: "ascendant-mcp-call", version: "1" },
		});
		this.notify("notifications/initialized");
		return result;
	}

	async listTools() {
		const tools = [];
		let cursor;
		do {
			const r = await this.request("tools/list", cursor ? { cursor } : {});
			tools.push(...r.tools);
			cursor = r.nextCursor;
		} while (cursor);
		return tools;
	}

	callTool(name, args = {}, timeoutMs) { return this.request("tools/call", { name, arguments: args }, timeoutMs); }

	async close() {
		try { this.child.stdin.end(); } catch { /* already closed */ }
		const t = setTimeout(() => this.child.kill("SIGTERM"), 2000);
		await this.exited;
		clearTimeout(t);
	}
}

/** Prints a tools/call result; saves image blocks as PNG files under outDir. Returns true when it was an error. */
export function showResult(name, result, { outDir, full = false, out = console.log } = {}) {
	let n = 0;
	for (const block of result.content ?? []) {
		if (block.type === "text") {
			const text = redact(block.text);
			out(full || text.length <= 1500 ? text : text.slice(0, 1500) + `\n... (${text.length - 1500} more characters; pass --full)`);
		} else if (block.type === "image") {
			mkdirSync(outDir, { recursive: true });
			const file = join(outDir, `${name}_${Date.now()}_${n++}.${block.mimeType?.split("/")[1] ?? "png"}`);
			writeFileSync(file, Buffer.from(block.data, "base64"));
			out(`[image saved] ${resolve(file)} (${block.mimeType}, ${Buffer.byteLength(block.data, "base64")} bytes)`);
		} else {
			out(`[${block.type} block]`);
		}
	}
	return result.isError === true;
}

/** The text of a tools/call result, redacted, with image blocks left out. */
export function textOf(result) {
	return (result.content ?? []).filter((b) => b.type === "text").map((b) => redact(b.text)).join("\n");
}

/** `${name}` in a step's args becomes a value captured by an earlier step (a whole-string `${n}` of a number stays a number). */
export function substitute(value, vars) {
	if (typeof value === "string") {
		const whole = /^\$\{(\w+)\}$/.exec(value);
		if (whole && whole[1] in vars) { const v = vars[whole[1]]; return /^-?\d+(\.\d+)?$/.test(v) ? Number(v) : v; }
		return value.replace(/\$\{(\w+)\}/g, (_, k) => vars[k] ?? "");
	}
	if (Array.isArray(value)) return value.map((v) => substitute(v, vars));
	if (value && typeof value === "object") return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, substitute(v, vars)]));
	return value;
}

/**
 * Runs a recipe. A step is {"sleep_ms": n}, or {"tool", "args"} with optional:
 *   "capture": "name"       keep the call's value (execute_code's "result") for later `${name}` in args
 *   "expect": "text"        the step fails unless the output contains this text
 *   "until": "text"         call again every "every_ms" (default 1000) until the output contains this text, up to "timeout_ms" (default 60000)
 *   "continue_on_error"     go on after a failed step (the run still exits 1)
 *   "note": "..."           printed before the step
 * Returns true when every step passed.
 */
export async function runSteps(client, steps, { outDir, full }) {
	const vars = {};
	const started = Date.now();
	let ok = true;
	for (const [i, step] of steps.entries()) {
		if (step.sleep_ms) { await new Promise((r) => setTimeout(r, step.sleep_ms)); continue; }
		const args = substitute(step.args ?? {}, vars);
		console.log(`\n--- step ${i + 1}: ${step.tool} ${redact(JSON.stringify(args)).slice(0, 300)}${step.note ? "   # " + step.note : ""}`);
		try {
			const deadline = Date.now() + (step.until ? step.timeout_ms ?? 60000 : 0);
			let result;
			for (;;) {
				result = await client.callTool(step.tool, args, step.until ? undefined : step.timeout_ms);
				if (!step.until || textOf(result).includes(step.until)) break;
				if (Date.now() > deadline) throw new Error(`gave up waiting for "${step.until}" (last output: ${textOf(result).slice(0, 200)})`);
				await new Promise((r) => setTimeout(r, step.every_ms ?? 1000));
			}
			const failed = showResult(step.tool, result, { outDir, full });
			const text = textOf(result);
			if (step.capture) {
				let v = text;
				try { const j = JSON.parse(text); v = typeof j === "object" && j !== null && "result" in j ? (typeof j.result === "string" ? j.result : JSON.stringify(j.result)) : text; } catch { /* not JSON: keep the text */ }
				vars[step.capture] = String(v);
			}
			if (failed) throw new Error("the tool reported an error");
			if (step.expect && !text.includes(step.expect)) throw new Error(`expected the output to contain "${step.expect}"`);
		} catch (e) {
			console.log(`STEP FAILED: ${redact(e.message)}`);
			ok = false;
			if (!step.continue_on_error) break;
		}
	}
	console.log(`\nrecipe ${ok ? "passed" : "FAILED"}: ${steps.length} steps in ${((Date.now() - started) / 1000).toFixed(1)} s`);
	return ok;
}

function parseArgs(argv) {
	const opts = { env: {}, project: process.cwd(), out: join(tmpdir(), "ascendant-mcp"), timeout: 120000, full: false, rest: [] };
	for (let i = 0; i < argv.length; i++) {
		const a = argv[i];
		if (a === "--project") opts.project = resolve(argv[++i]);
		else if (a === "--env") { const [k, ...v] = argv[++i].split("="); opts.env[k] = v.join("="); }
		else if (a === "--out") opts.out = argv[++i];
		else if (a === "--timeout") opts.timeout = Number(argv[++i]);
		else if (a === "--activate") opts.activate = argv[++i];
		else if (a === "--full") opts.full = true;
		else opts.rest.push(a);
	}
	return opts;
}

async function main() {
	const opts = parseArgs(process.argv.slice(2));
	const [cmd, ...args] = opts.rest;
	if (!["list", "counts", "call", "run"].includes(cmd)) {
		console.error("usage: node tools/mcp/mcp_call.mjs list|counts|call <tool> [json]|run <steps.json> [--project dir] [--env K=V] [--out dir] [--timeout ms] [--full]");
		process.exit(2);
	}
	const spec = serverSpec(opts.project, opts.env);
	console.log(`bridge: ${spec.command} ${spec.args.join(" ")}   (cwd ${spec.cwd})`);
	const client = new McpClient(spec, { timeoutMs: opts.timeout, log: (l) => console.error(redact(l)) });
	let exit = 0;
	try {
		const init = await client.initialize();
		console.log(`server: ${init.serverInfo?.name} ${init.serverInfo?.version}  protocol ${init.protocolVersion}`);
		let tools = await client.listTools();
		console.log(`tools/list: ${tools.length} tools at startup`);
		const show = (name, r) => { if (showResult(name, r, { outDir: opts.out, full: opts.full })) exit = 1; };

		if (cmd === "list") {
			console.log(tools.map((t) => t.name).join(", "));
		} else if (cmd === "counts") {
			const start = tools.length;
			const wanted = opts.activate ?? "";
			if (wanted) {
				const groups = wanted === "all" ? groupNames(tools) : wanted.split(",");
				const r = await client.callTool("discover_tools", { request: groups });
				if (r.isError) { console.log(`discover_tools: ERROR ${redact(r.content?.[0]?.text ?? "").slice(0, 300)}`); exit = 1; }
				tools = await client.listTools();
				console.log(`after discover_tools(${groups.length} groups): ${tools.length} tools (startup ${start}, +${tools.length - start})`);
			}
		} else if (cmd === "call") {
			const toolArgs = args[1] ? JSON.parse(args[1]) : {};
			show(args[0], await client.callTool(args[0], toolArgs));
		} else if (cmd === "run") {
			const steps = JSON.parse(readFileSync(args[0], "utf8"));
			if (!(await runSteps(client, steps, { outDir: opts.out, full: opts.full }))) exit = 1;
		}
	} catch (e) {
		console.error(`FAILED: ${redact(e.message)}`);
		exit = 2;
	} finally {
		await client.close();
	}
	process.exit(exit);
}

/** The built-in group names, read from discover_tools' own schema ("Built-in: a, b, c (plus extension groups)"). */
export function groupNames(tools) {
	const d = tools.find((t) => t.name === "discover_tools")?.inputSchema?.properties?.request?.description ?? "";
	const m = /Built-in:\s*([^()]+?)\s*\(plus/.exec(d);
	return m ? m[1].split(",").map((g) => g.trim()).filter(Boolean) : [];
}

if (process.argv[1] && resolve(process.argv[1]) === new URL(import.meta.url).pathname) main();
