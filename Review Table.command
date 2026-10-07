#!/bin/sh
# Double-click in Finder to open the Review Table (accept or reject generated concept art, 3D models, voices,
# pictures and films) in your browser. Keep this window open while you review; close it to stop the table.
# The same thing from a terminal: ./scripts/review.sh   (it serves on http://127.0.0.1:8766/)
cd "$(dirname "$0")" && exec ./scripts/review.sh
