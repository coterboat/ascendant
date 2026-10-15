class_name SpellIcons
## UI-ICONS (#233): the magic art on screen. Every place that names a spell puts its icon (Art.spell_icon, #225: one painted cel
## icon per data/magic.gd SPELLS id, and Tithe of Blood's for the blood mandate) beside the name. A spell whose file has not landed
## gets no icon and the place keeps the look it had. Static helpers only; the panels and cards build the nodes.
##
##   SpellIcons.keys()               every key an icon can exist for: MagicData.SPELLS' ids, then the blood mandate's
##   SpellIcons.texture(key)         the icon, or null (no art yet, or no such key)
##   SpellIcons.rect(key, px)        a TextureRect of px x px that takes no mouse, or null when there is no icon
##   SpellIcons.of_codex(codex_key)  the icon key a codex entry is about ("spell_sunlance" -> "sunlance"), or ""
##   SpellIcons.source               where the art comes from (Art.spell_icon); tests point it elsewhere to see the old look

## The blood mandate whose icon is in the set (it pays for rituals in blood).
const BLOOD_MANDATE := "tithe_of_blood"

static var source: Callable = func(key: String) -> Texture2D: return Art.spell_icon(key)


static func keys() -> Array:
	var out := MagicData.SPELLS.keys()
	out.append(BLOOD_MANDATE)
	return out


static func texture(key: String) -> Texture2D:
	if key.is_empty() or not keys().has(key):
		return null
	return source.call(key)


static func rect(key: String, px: int) -> TextureRect:
	var tex := texture(key)
	if tex == null:
		return null
	var r := TextureRect.new()
	r.name = "SpellIcon_%s" % key.validate_node_name()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(px, px)
	r.size = Vector2(px, px)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_meta("spell_icon", key)
	return r


static func of_codex(codex_key: String) -> String:
	for id in MagicData.SPELLS:
		if String(MagicData.SPELLS[id].get("codex", "")) == codex_key:
			return String(id)
	if codex_key == "mandate_%s" % BLOOD_MANDATE:
		return BLOOD_MANDATE
	return ""


## The icon keys shown under `root` (every SpellIcons.rect inside it), in tree order: for tests.
static func shown_under(root: Node) -> Array:
	var out := []
	for n in root.find_children("SpellIcon_*", "TextureRect", true, false):
		out.append(String(n.get_meta("spell_icon", "")))
	return out
