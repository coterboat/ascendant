#!/usr/bin/env bash
# Opens THIS checkout's Godot editor for an MCP session, with the toolkit's plugin switched on, and puts
# project.godot back the way it was when the editor closes.
#
#   tools/mcp/editor.sh                 windowed editor, always on top (an occluded window never draws)
#   tools/mcp/editor.sh --headless      headless editor: file, scene, node and script tools only; no game, no screenshots
#   tools/mcp/editor.sh --strip         only clean project.godot (after an editor you opened some other way, or a killed session)
#   tools/mcp/editor.sh --status        what project.godot holds of the toolkit right now
#   tools/mcp/editor.sh -- <godot args> anything after `--` goes to Godot as it is
#
# Why a launcher: the committed project.godot leaves the plugin OFF on purpose. The plugin writes its runtime
# autoload (MCPRuntimeServer) into project.godot's [autoload] section every time the editor loads it, because the
# game reads project.godot at F5. With that line in place, every plain `godot --path .` run (tests, boot checks,
# autoplay workers) opens a listener on 127.0.0.1:6570-6585 and writes a machine-wide registry; and with the
# plugin enabled in the committed file, even `godot --import` would write the line into every fresh worktree.
# This script switches the plugin on for the session (tools/mcp/project_plugin.mjs enable) and, when the editor
# exits, takes out the plugin entry, the autoload and the toolkit's settings (strip). tests/test_mcp_toolkit.gd
# fails while any of them is left in project.godot.
#
# The editor's pid is printed; stop it with `kill <pid>` (a trap strips on TERM and INT; after a SIGKILL or a
# crash run `tools/mcp/editor.sh --strip`). Stop only the editor you started: other sessions run Godot here too.
set -u
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root" || exit 1

command -v node >/dev/null 2>&1 || { echo "Node.js 22 or newer is needed (the MCP bridge is an npm package)."; exit 2; }
plugin() { node tools/mcp/project_plugin.mjs "$@"; }

godot="${GODOT:-}"
if [ -z "$godot" ]; then
	for c in "$(command -v godot 2>/dev/null)" /Applications/Godot.app/Contents/MacOS/Godot "$HOME/Downloads/Godot.app/Contents/MacOS/Godot" /home/box/playtester/godot/godot; do
		if [ -n "$c" ] && [ -x "$c" ]; then godot="$c"; break; fi
	done
fi

mode="windowed"
extra=()
while [ $# -gt 0 ]; do
	case "$1" in
		--headless) mode="headless" ;;
		--strip) plugin strip; exit 0 ;;
		--status) plugin status; exit $? ;;
		--) shift; extra=("$@"); break ;;
		*) echo "unknown option $1 (see the header of $0)"; exit 2 ;;
	esac
	shift
done

[ -n "$godot" ] || { echo "No Godot binary found: set GODOT=/path/to/godot"; exit 2; }

plugin enable || exit 1

args=(--path . --editor)
if [ "$mode" = "headless" ]; then args=(--headless "${args[@]}"); else args=("${args[@]}" --always-on-top); fi

"$godot" "${args[@]}" ${extra[@]+"${extra[@]}"} &
pid=$!
echo "editor pid $pid ($mode). Close it, or kill $pid, when the session is over; project.godot is cleaned on exit."
trap 'kill "$pid" 2>/dev/null' INT TERM
wait "$pid"
# A trapped signal ends the first wait at once; keep waiting until the editor has really exited and saved.
while kill -0 "$pid" 2>/dev/null; do wait "$pid"; done
trap - INT TERM
plugin strip
if ! git diff --quiet -- project.godot 2>/dev/null; then
	echo "NOTE: project.godot still differs from the index. Review it before committing:"
	git --no-pager diff --stat -- project.godot
fi
