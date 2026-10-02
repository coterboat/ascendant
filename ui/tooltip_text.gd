class_name TooltipText
## Turns a Breakdown dictionary (rules/breakdown.gd) into multi-line tooltip text:
##   Income of Crownkeep
##     Base income of Crownkeep: 12  (set by the map)
##     Modifiers: +0  (none yet: ...)
##     = Income per turn: 12
##   <plain-language description, wrapped>
## Plain Control.tooltip_text is used everywhere, so lines are wrapped here to keep tooltips narrow.

const WRAP := 64


static func from_breakdown(b: Dictionary) -> String:
	var out := PackedStringArray()
	out.append(String(b.get("title", "")))
	var first := true
	for l in b.get("lines", []):
		var value: int = int(l.value)
		var shown := str(value) if first else ("%+d" % value)
		var note: String = l.get("note", "")
		out.append("  %s: %s%s" % [l.label, shown, "" if note.is_empty() else "  (%s)" % note])
		first = false
	out.append("  = %s: %d" % [b.get("total_label", "Total"), int(b.get("total", 0))])
	var desc: String = b.get("description", "")
	if not desc.is_empty():
		out.append("")
		out.append(wrap_text(desc))
	return "\n".join(out)


## Word-wraps plain text to at most `width` characters per line (longer single words stay whole).
static func wrap_text(text: String, width: int = WRAP) -> String:
	var lines := PackedStringArray()
	var current := ""
	for word in text.split(" ", false):
		if current.is_empty():
			current = word
		elif current.length() + 1 + word.length() <= width:
			current += " " + word
		else:
			lines.append(current)
			current = word
	if not current.is_empty():
		lines.append(current)
	return "\n".join(lines)


## Title plus wrapped description, for labels that explain a fact rather than a number.
static func plain(title: String, description: String) -> String:
	return "%s\n\n%s" % [title, wrap_text(description)]
