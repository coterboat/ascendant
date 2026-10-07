#!/bin/sh
# Double-click in Finder to open the review table (accept or reject generated voices, pictures
# and films) in your browser. Keep this window open while you review; close it to stop the table.
# The same thing from a terminal: ./scripts/review.sh
cd "$(dirname "$0")" && exec ./scripts/review.sh
