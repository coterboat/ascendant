class_name SceneFlow
## How the game moves between its screens (#7, #8):
##   title --New game--> new game screen (over the title) --Start--> game screen
##                       new game screen --Back--> title
##   title --Quick start--> game screen (default setup)
##   game screen --victory "New game"--> title with the new game screen open
##   game screen --"Back to title" / "Quit to title"--> title
##
## The one rule: the next screen is instantiated and fully set up while it is still OUT of the tree
## (GameScreen.start_game(config), TitleScreen.open_new_game()), then switch() makes it the current
## scene and frees the old one at the end of the frame. A screen never shows a half-built state, and
## the same calls work headless, where nothing is in the tree: switch() then does nothing and the
## caller (and its tests) keep the new screen.

const TITLE_SCENE := "res://ui/title_screen.tscn"
const GAME_SCENE := "res://ui/game_screen.tscn"


## A game screen already running a new game with `config` ({"players", "seed"}, see
## GameScreen.start_game). It enters the tree with its session in place, so it never starts a default.
static func make_game(config: Dictionary) -> GameScreen:
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.start_game(config)
	return game


## The title screen; with `with_new_game`, its new game screen is already open.
static func make_title(with_new_game: bool = false) -> TitleScreen:
	var title := load(TITLE_SCENE).instantiate() as TitleScreen
	if with_new_game:
		title.open_new_game()
	return title


## Makes `next` the current scene instead of the scene `from` belongs to, which is freed at the end
## of the frame. Outside the tree (headless tests) it does nothing.
static func switch(from: Node, next: Node) -> void:
	if from == null or next == null or not from.is_inside_tree():
		return
	var tree := from.get_tree()
	var old := tree.current_scene
	tree.root.add_child(next)
	tree.current_scene = next
	if old != null and old != next:
		old.queue_free()
