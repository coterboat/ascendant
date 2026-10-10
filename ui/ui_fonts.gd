class_name UiFonts
## The War Table's type tokens (design/UX_WAR_TABLE.md section 7, UX-0a): four fonts by job. New HUD
## pieces ask for a font by what the text IS and a size from the type scale in UiPalette:
##
##   label.add_theme_font_override("font", UiFonts.name())
##   label.add_theme_font_size_override("font_size", UiPalette.TYPE_NAME)
##
##   title()   headings: the Chronicle, a panel's title
##   name()    names of places, armies, rulers and rivals (a plaque's first line)
##   body()    everything that is read: tooltips, card text, report lines
##   number()  counts and amounts (gold, strength, garrison): figures that must not jump as they change
##
## TODAY all four are the project's default font, so nothing looks different yet. UX-0b swaps the
## real fonts in here (Spectral SC for title() and name(), Alegreya Sans for body() and number()) and no
## caller changes, because callers only ever name the job.
##
## TABULAR FIGURES. number() is a FontVariation of the default font with the OpenType feature "tnum"
## (every digit the same width, so a column of numbers lines up and a counter does not shimmer as it
## ticks). The default font supports it (tests/test_ui_icons.gd measures that "1111" and "0000" are the
## same width). If UX-0b's body font lacks "tnum", that is UX-0b's to fix; the test will say so.

static var _number: Font = null


static func title() -> Font:
	return _base()


static func name() -> Font:
	return _base()


static func body() -> Font:
	return _base()


## The font for figures: the default font with tabular figures turned on.
static func number() -> Font:
	if _number == null:
		var variation := FontVariation.new()
		variation.base_font = _base()
		variation.opentype_features = {"tnum": 1}
		_number = variation
	return _number


## The project's default font, which is what every Control without its own font draws with: the font of
## the project theme if it names one, else the engine's built-in font.
static func _base() -> Font:
	var theme := ThemeDB.get_project_theme()
	if theme != null and theme.has_default_font():
		return theme.default_font
	return ThemeDB.fallback_font
