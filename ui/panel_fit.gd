class_name PanelFit
extends RefCounted
## MVP-3 (#177), items 5 and 6: the big centred panels (the research panel with its Magic tab, the lock-in preview, the ruler
## panel, the sacrifice dialog, the turn report's box) are built at a fixed size (1040 to 1560 wide, up to 860 tall) that fits
## the 1600x900 window and not the 1280x720 one Settings' 125% interface size makes of it: their right edge and bottom were cut
## off. attach() shrinks such a panel to fit the viewport it is in, about the centre, and leaves it exactly as it was (scale 1)
## wherever it fits. Everything on it stays reachable and keeps its tooltips; only the size changes, and at 125% a panel scaled
## by 0.8 reads like the same panel at 100%.
## A Container resets its children's scale, so the scale goes on the CenterContainer that centres the panel (whose parent is a
## plain Control): the whole centred layer shrinks, about the point that leaves the panel's middle on the window's middle. (A
## container is never smaller than its content, so the CenterContainer is as big as the panel, and the panel sits at its
## top-left corner while the window is the smaller one: the pivot is worked out from where the panel really is.)

## The panel keeps at least this much of the viewport free all round.
const MARGIN := 20.0
## It never shrinks below this (below it the text is too small to read, and the window is not one the game supports).
const MIN_SCALE := 0.5


## The scale that fits a panel of `need` pixels in a viewport of `viewport`: 1.0 when it fits with the margin all round.
static func scale_for(need: Vector2, viewport: Vector2) -> float:
	if need.x <= 0.0 or need.y <= 0.0 or viewport.x <= 0.0 or viewport.y <= 0.0:
		return 1.0
	return clampf(minf((viewport.x - 2.0 * MARGIN) / need.x, (viewport.y - 2.0 * MARGIN) / need.y), MIN_SCALE, 1.0)


## The pivot (in the holder's own coordinates) that scaling the holder by `s` about puts a panel whose middle is at `panel_middle`
## (in the holder's parent's coordinates, unscaled) on `window_middle`: P + s (m - P) = w, so P = (w - s m) / (1 - s).
static func pivot_for(s: float, panel_middle: Vector2, window_middle: Vector2, holder_position: Vector2) -> Vector2:
	if s >= 1.0:
		return Vector2.ZERO
	return (window_middle - panel_middle * s) / (1.0 - s) - holder_position


## Keeps `panel` (a Control of a fixed minimum size, centred by `holder`, a full-window CenterContainer under a plain Control)
## inside its viewport from now on: whenever it is shown or moved or resized, and whenever the viewport changes size (a window
## drag, Settings' interface size) while the holder is in the tree.
## #330: the viewport outlives the panel (the window outlives every game screen), so the fit is hooked to its size_changed as the
## holder enters the tree and unhooked as it leaves. It was never unhooked: after a game was left, every resize called the fits of
## that game's freed panels (three errors each, and more with every game left). The fit holds the two by weak reference, so a call
## that comes after they are freed (one deferred as the holder entered the tree) does nothing.
static func attach(panel: Control, holder: Control) -> void:
	var panel_ref: WeakRef = weakref(panel)
	var holder_ref: WeakRef = weakref(holder)
	var fit := func() -> void:
		var centre := holder_ref.get_ref() as Control
		var fitted := panel_ref.get_ref() as Control
		if centre == null or fitted == null or not centre.is_inside_tree():
			return
		var window := centre.get_viewport_rect().size
		var s := scale_for(fitted.get_combined_minimum_size(), window)
		centre.scale = Vector2(s, s)
		centre.pivot_offset = pivot_for(s, centre.position + fitted.position + fitted.size * 0.5, window * 0.5, centre.position)
	holder.resized.connect(fit)
	holder.visibility_changed.connect(fit)
	panel.item_rect_changed.connect(fit)
	holder.tree_entered.connect(func() -> void:
		var vp := holder.get_viewport()
		if vp != null and not vp.size_changed.is_connected(fit):
			vp.size_changed.connect(fit)
		fit.call_deferred())
	holder.tree_exiting.connect(func() -> void:
		var vp := holder.get_viewport()
		if vp != null and vp.size_changed.is_connected(fit):
			vp.size_changed.disconnect(fit))
