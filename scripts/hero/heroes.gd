extends RefCounted

# Hero catalogue (stage 3, Teil B §3). One entry per playable hero:
#   name, title      shown in the menu / hero choice (Teil A reads them)
#   weapon           id of the starting weapon (scripts/weapons/*, see WEAPONS)
#   weapon_name      German name of that weapon (menu text)
#   hp, armor        base health and base armor share (0.1 = 10 % less damage)
#   speed            base run speed (m/s)
#   model_script     placeholder model built from primitives
#   portrait         hint for the menu portrait: colours + a short look text
#   text             one line for the hero card
# current_id() reads the run configuration of the menu (Session.config.hero_id,
# scripts/core/session.gd of Teil A) with fallbacks; unknown ids fall back to
# DEFAULT ("brann").

const DEFAULT := "brann"
const SESSION_PATH := "res://scripts/core/session.gd"

const HEROES := {
	"brann": {
		"name": "Brann",
		"title": "Der Schrotflinten-Koch",
		"weapon": "shotgun",
		"weapon_name": "Schrotflinte",
		"hp": 100.0,
		"armor": 0.0,
		"speed": 4.8,
		"model_script": "res://scripts/hero/brann_model.gd",
		"portrait": {"main": Color("ef6a22"), "accent": Color("4a4558"), "skin": Color("8a5636"),
			"hint": "Glatze, schwarzer Bart, orange Schürze, Doppelflinte"},
		"text": "Zwei Schuss, dann Nachladen. Ein Fächer aus Schrot wirft leichte Gegner um.",
	},
	"boxer": {
		"name": "Brine",
		"title": "Der Straßenboxer",
		"weapon": "fists",
		"weapon_name": "Fäuste",
		"hp": 130.0,
		"armor": 0.1,
		"speed": 4.4,
		"model_script": "res://scripts/hero/boxer_model.gd",
		"portrait": {"main": Color("d8382e"), "accent": Color("2f6b3a"), "skin": Color("c27a48"),
			"hint": "rote ärmellose Kapuzenjacke, grüne Shorts, bandagierte Fäuste, graue Strähne"},
		"text": "Links, rechts, Aufwärtshaken. Muss nah ran, hält dafür mehr aus.",
	},
}

## Hero ids in menu order.
const ORDER := ["brann", "boxer"]


static func has(id: String) -> bool:
	return HEROES.has(id)


## Catalogue entry of `id` (Brann for unknown ids).
static func get_hero(id: String) -> Dictionary:
	return HEROES.get(id, HEROES[DEFAULT])


static func ids() -> Array:
	return ORDER.duplicate()


## Hero chosen in the menu for this run (Session.config.hero_id), else Brann.
static func current_id() -> String:
	var config := session_config()
	var id := String(config.get("hero_id", DEFAULT))
	return id if HEROES.has(id) else DEFAULT


## The menu's run configuration ({} when there is none): an autoload node
## "Session" first, then the static `config` of scripts/core/session.gd.
static func session_config() -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		var node := tree.root.get_node_or_null("Session")
		if node != null:
			var value: Variant = node.get("config")
			if value is Dictionary:
				return value
	if ResourceLoader.exists(SESSION_PATH):
		var script: Variant = load(SESSION_PATH)
		if script is Script:
			var value: Variant = (script as Script).get("config")
			if value is Dictionary:
				return value
	return {}
