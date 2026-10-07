#!/bin/sh
# The Review Table: accept or reject what was generated (concept art, 3D models, voices, pictures, films),
# and install or redo from its buttons. Opens in your browser at http://127.0.0.1:8766/ (Concurrent's is 8765).
#   ./scripts/review.sh          start it and open it (if it's already running, just open it)
#   ./scripts/review.sh 8770     on another port
# Or double-click "Review Table.command" in the repo folder. Ctrl+C, or closing that window, stops it.
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
PATH="/opt/homebrew/bin:/usr/local/bin:$PATH" ## Finder starts .command files with a bare PATH
PORT="${1:-8766}"
URL="http://127.0.0.1:$PORT/"
if curl -s -o /dev/null --max-time 2 "$URL"; then
	echo "review: already running at $URL (opening it)"
	open "$URL" 2>/dev/null || xdg-open "$URL" 2>/dev/null
	exit 0
fi
exec python3 tools/review/review.py serve --port "$PORT" --open
