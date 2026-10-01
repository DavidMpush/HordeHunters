extends RefCounted

# Biome data (ported from Mawlings scripts/biomes.gd). Pure data: arena.gd,
# arena_border.gd and the ground / wall / water shaders read their colours from
# here; main.gd reads `light` (sun colour and energy).
#
# verdant_maw is the default meadow world. Glutsumpf (`ember` block): peat
# shader ground with glowing cracks, lava lakes with a walkable crust ring,
# basalt walls and charred landmarks. Dürrschlund (`desert` block): dune sand,
# sandstone walls, bones, cacti and walkable quicksand patches (they slow).
# Flat ground decoration (pools, quicksand) never hurts; danger always comes
# with a telegraph.

const DEFAULT := "verdant_maw"
# World order of a run (stage 4: a portal after the end boss leads to the next).
const ORDER := ["verdant_maw", "duerrschlund", "glutsumpf"]

const DATA := {
	"verdant_maw": {
		"name": "Verdant Maw",
		"title": "VERDANT MAW",
		"description": "Offene, grüne Jagdgründe.",
		"ground": Color("80a04c"),
		"path": Color("d4b377"),
		"path_edge": Color("aeaa62"),
		# Glow of trail and edge (0 = plain, matte ground like the classic map).
		"path_emission": Color(0, 0, 0),
		"path_edge_emission": Color(0, 0, 0),
		"moss": [Color("88a852"), Color("718f40"), Color("7a9844")],
		"sand": Color("c8ab6e"),
		"earth": Color("b39862"),
		"plinth": Color("62883a"),
		"pool": Color("3fc0c4"),
		"pool_roughness": 0.35,
		"pool_emission": Color(0, 0, 0),
		"shore": Color("dcd296"),
		"flower_dark": Color("6a5a8e"),
		"flower_light": Color("c3b3de"),
		"prop_rim": Color("f2f0c8"),
		# body_tint of the prop shader per prop group (alpha = amount, 0 = original colours).
		"rock_tint": Color(1, 1, 1, 0),
		"leaf_tint": Color(1, 1, 1, 0),
		"wood_tint": Color(1, 1, 1, 0),
		"reed_tint": Color(1, 1, 1, 0),
		# Stage 34: shader ground (shaders/verdant_ground.gdshader, uniform name ->
		# value): three grass tones, clover and dirt fields, trodden clearings.
		# Paths use "path" / "path_edge" above.
		"meadow": {
			"grass_dark": Color("6d8f40"),
			"grass_mid": Color("80a04c"),
			"grass_light": Color("93b153"),
			"clover": Color("64904a"),
			"clover_light": Color("7aa558"),
			"dirt": Color("917c55"),
			"trodden": Color("a5ad62"),
			"clover_amount": 1.0,
			"dirt_amount": 1.0,
		},
		# Decoration counts per chunk (classic layout).
		"pond_one_in": 5,
		"eruptions": false,
		# Map edge (stage 18, arena_border.gd): forest floor under the wall, fog it
		# fades into (= the project clear colour), swamp water of the edge.
		"border": {"floor": Color("4a6a34"), "fog": Color(0.16, 0.23, 0.18), "water": Color("2b8a86"), "shore": Color("6f8a44")},
		# Stage 29: lakes and moors (shaders/water.gdshader via arena_border.gd):
		# muddy rim, light sandy shallows, a clear darker teal where it gets deep.
		"water": {
			"rim": Color("a39a62"), "shallow_light": Color("9edcc2"), "shallow": Color("4cbfb6"),
			"deep": Color("1f8993"), "abyss": Color("17687a"), "foam": Color("f0fff6"),
			"glint": Color("d8fff4"), "pad": Color("5f9e3a"), "pads": 1.0,
		},
		# Stage 34: continuous walls (shaders/wall.gdshader via arena_border.gd):
		# grey rock plates with moss, dark green domed hedges, pale ruin masonry
		# with a moss crown; a warm rim light on every top edge.
		"walls": {
			"rock_top": Color("a39f90"), "rock_side": Color("7a766b"), "rock_dark": Color("45423c"),
			"moss": Color("7a9a38"), "moss_amount": 0.55, "band_amount": 0.2,
			"hedge_top": Color("3e7a2a"), "hedge_light": Color("86bd42"), "hedge_side": Color("2c5c21"),
			"hedge_dark": Color("143413"), "stone": Color("cbbf9f"), "stone_top": Color("b9ad8c"),
			"mortar": Color("6b6252"), "rim_color": Color("fff4c8"), "rim_strength": 0.5,
			"glow": 0.0, "shadow": Color(0.04, 0.07, 0.03),
		},
		"light": {"color": Color(1, 1, 1), "energy": 1.15},
	},
	"glutsumpf": {
		"name": "Glutsumpf",
		"title": "GLUTSUMPF",
		"description": "Glühender Sumpf voller Gase.",
		"ground": Color("5e4f55"),
		"path": Color("3c2c2c"),
		"path_edge": Color("b8622c"),
		"path_emission": Color(0, 0, 0),
		"path_edge_emission": Color("5a2408"),
		"moss": [Color("6a5e62"), Color("4a3f45"), Color("76665f")],
		"sand": Color("5a4c4c"),
		"earth": Color("3e3337"),
		"plinth": Color("3e3438"),
		"pool": Color("ffc24a"),
		"pool_roughness": 0.6,
		"pool_emission": Color("ff9a2a"),
		"shore": Color("2a2124"),
		"flower_dark": Color("1f6a70"),
		"flower_light": Color("9fe6e0"),
		"prop_rim": Color("ffc07a"),
		"rock_tint": Color(0.42, 0.38, 0.42, 0.85),
		"leaf_tint": Color(0.34, 0.28, 0.24, 0.9),
		"wood_tint": Color(0.3, 0.24, 0.24, 0.85),
		"reed_tint": Color(0.5, 0.42, 0.34, 0.75),
		"pond_one_in": 3,
		"eruptions": true,
		"border": {"floor": Color("3a2e33"), "fog": Color("1d1417"), "water": Color("ffb040"), "shore": Color("2a2124"), "crust": Color("2e2327"), "crust_glow": Color("1a0802")},
		# Stage 29: the swamp lakes are lava - a walkable ring of cooled crust
		# with glowing cracks (slows), molten lava with drifting plates inside.
		"water": {
			"lava": true, "rim": Color("3c3033"), "crust": Color("2e2327"), "crack": Color("ff8a2c"),
			"lava_core": Color("fff2a0"), "lava_mid": Color("ff7a1c"), "lava_crust": Color("2a0c0a"),
			"plates": 0.78, "pads": 0.0,
		},
		# Stage 34 walls: basalt with glowing cracks, a charred thicket, dark
		# basalt masonry; ember rim light (never large orange areas).
		"walls": {
			"rock_top": Color("574a52"), "rock_side": Color("3d3339"), "rock_dark": Color("1b1418"),
			"moss": Color("75696b"), "moss_amount": 0.3, "band_amount": 0.15,
			"hedge_top": Color("463a3a"), "hedge_light": Color("6e5a50"), "hedge_side": Color("302628"),
			"hedge_dark": Color("150f10"), "stone": Color("5d4f56"), "stone_top": Color("524549"),
			"mortar": Color("221a1d"), "rim_color": Color("ffb27a"), "rim_strength": 0.42,
			"glow_color": Color("ff7a24"), "glow": 0.9, "shadow": Color(0.05, 0.02, 0.02),
		},
		"light": {"color": Color(1.0, 0.86, 0.74), "energy": 1.2},
		# Shader look of arena.gd (only biomes with this block use it).
		"ember": {
			"ground_dark": Color("463a42"),
			"ground_light": Color("6c5a5c"),
			"ash": Color("8a8184"),
			"vein": Color("ff8a2c"),
			"vein_amount": 0.55,
			"crust": Color("33272a"),
			"crust_rim": Color("54433f"),
			"core": Color("ffb03c"),
			"core_hot": Color("fff0a0"),
			"lava_core": Color("ffe27a"),
			"lava_mid": Color("ff9a2e"),
			"lava_crust": Color("5a2014"),
			"basalt_tint": Color(0.24, 0.2, 0.22, 0.95),
			"char_rim": Color("ff9a4a"),
			"mushroom_dark": Color("0f4a58"),
			"mushroom_light": Color("8ff4ff"),
			"mushroom_rim": Color("b8fbff"),
		},
	},
	# The desert "Dürrschlund" between Verdant Maw and Glutsumpf.
	# Readability: the sand is pale ochre/beige with
	# cool (blue-grey) shadows instead of orange; paths are packed, greyer sand;
	# oases are turquoise with a green rim; cactus flowers pink (never orange).
	"duerrschlund": {
		"name": "Dürrschlund",
		"title": "DÜRRSCHLUND",
		"description": "Dünen, Knochenfelder und der Sandwurm.",
		"ground": Color("dcc89e"),
		"path": Color("bcac8a"),
		"path_edge": Color("9f8f6e"),
		"path_emission": Color(0, 0, 0),
		"path_edge_emission": Color(0, 0, 0),
		"moss": [Color("d4bf92"), Color("c9b489"), Color("e3d1a8")],
		"sand": Color("e9d9b2"),
		"earth": Color("b5a07a"),
		"plinth": Color("a8936e"),
		"pool": Color("35c4bd"),
		"pool_roughness": 0.3,
		"pool_emission": Color(0, 0, 0),
		"shore": Color("86b25e"),
		"flower_dark": Color("b04c78"),
		"flower_light": Color("f3a8c6"),
		"prop_rim": Color("fff2d2"),
		"rock_tint": Color(0.9, 0.72, 0.52, 0.5),
		"leaf_tint": Color(0.62, 0.66, 0.42, 0.45),
		"wood_tint": Color(0.86, 0.8, 0.68, 0.65),
		"reed_tint": Color(0.84, 0.76, 0.54, 0.6),
		# Desert props (phase 2): walls a muted rust-brown so they stay darker than
		# the pale sand (rule "klare, dunkle Wände"), bones only slightly warmed.
		"wall_tint": Color(0.56, 0.42, 0.34, 0.68),
		"bone_tint": Color(1.0, 0.95, 0.85, 0.15),
		"pond_one_in": 7,
		"eruptions": false,
		# Quicksand patches slow every body (walkable, announced by their look).
		"quicksand": true,
		# Map edge (arena_border.gd): high dune ridges and sandstone, fading into a
		# dusty haze; "water" is the dune sea / quicksand ring of the edge.
		"border": {"floor": Color("bda77e"), "fog": Color(0.6, 0.55, 0.47), "water": Color("cfb07a"), "shore": Color("a78f66")},
		# Stage 29: the oasis pond - pale sand rim, turquoise shallows, deep teal.
		"water": {
			"rim": Color("e9d8a6"), "shallow_light": Color("9fe8d6"), "shallow": Color("5fd3c6"),
			"deep": Color("1f98a2"), "abyss": Color("17778a"), "foam": Color("fffbef"),
			"glint": Color("e8fffa"), "pads": 0.0,
		},
		# Stage 34 walls: rust sandstone with pale bands (darker than the sand,
		# "klare Wände"), dry olive scrub in the cactus groves, sandstone blocks.
		"walls": {
			"rock_top": Color("b8875a"), "rock_side": Color("94603f"), "rock_dark": Color("5a3524"),
			"moss": Color("c9a36f"), "moss_amount": 0.2, "band_amount": 0.55,
			"hedge_top": Color("848a4a"), "hedge_light": Color("b3b064"), "hedge_side": Color("666939"),
			"hedge_dark": Color("3a3a20"), "stone": Color("c9a77a"), "stone_top": Color("b89468"),
			"mortar": Color("7a5a40"), "rim_color": Color("fff0cc"), "rim_strength": 0.45,
			"glow": 0.0, "shadow": Color(0.3, 0.2, 0.12),
		},
		"light": {"color": Color(1.0, 0.96, 0.88), "energy": 1.15},
		# Shader look for the phase-2 ground (like the Glutsumpf "ember" block):
		# dune ripples, cool shadow side, bone-white flecks, turquoise oasis water.
		"desert": {
			"dune_light": Color("e6d4aa"),
			"dune_shadow": Color("b3a590"),
			"shadow_cool": Color("8e93a6"),
			"ripple": Color("cdb68a"),
			"ripple_amount": 0.4,
			"bone_fleck": Color("f4ecd8"),
			"quicksand": Color("b89a64"),
			"quicksand_swirl": Color("8f7446"),
			"oasis_core": Color("2fb8b8"),
			"oasis_shallow": Color("7fe0d0"),
			"oasis_rim": Color("6aa04a"),
		},
	},
}


static func has(id: String) -> bool:
	return DATA.has(id)


# Full data set; unknown ids fall back to the default biome.
static func get_data(id: String) -> Dictionary:
	return DATA.get(id, DATA[DEFAULT])


static func display_name(id: String) -> String:
	return String(get_data(id).name)


# Biome after `id` in the migration order (wraps around, the run stays endless).
static func next_biome(id: String) -> String:
	var index := ORDER.find(id)
	return ORDER[(index + 1) % ORDER.size()]
