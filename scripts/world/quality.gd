extends RefCounted

# Quality tiers (ported from Mawlings scripts/quality.gd, swarm switches removed).
# Static data and selection API:
#
#   const Quality := preload("res://scripts/world/quality.gd")
#   var tier: int = Quality.current_tier()        # override or heuristic
#   var s: Dictionary = Quality.settings(tier)     # copy of the switches
#   Quality.apply_viewport(get_viewport(), s)      # MSAA + 3D scale
#
# Every switch is purely visual: none may change game state, collision, seed
# determinism or hit resolution.

enum Tier { LOW, MEDIUM, HIGH }

const TIER_IDS := ["low", "medium", "high"]
const TIER_NAMES := ["NIEDRIG", "MITTEL", "HOCH"]

## Switches per tier:
## wall_detail        float density of wall accents deep inside walls and at the map
##                          edge (1 = all). Wall edges (collision = look) always stay.
## decor_density      float fine detail of the ground shaders (grass grain, blossoms).
## effect_density     float share of decorative effect parts (never telegraphs).
## minimap_bake_us    int   minimap bake time per frame (us).
## hud_redraw_hz      int   HUD redraw cap when nothing animates (0 = every frame).
## msaa_3d            int   MSAA of the game viewport (Viewport.MSAA_*).
## scaling_3d_scale   float 3D render scale of the game viewport (HUD stays sharp).
## max_fps            int   frame rate cap (0 = unlimited / vsync).
const PRESETS := {
	Tier.LOW: {
		"wall_detail": 0.55,
		"decor_density": 0.5,
		"effect_density": 0.5,
		"minimap_bake_us": 300,
		"hud_redraw_hz": 20,
		"msaa_3d": Viewport.MSAA_DISABLED,
		"scaling_3d_scale": 0.7,
		"max_fps": 60,
	},
	Tier.MEDIUM: {
		"wall_detail": 0.8,
		"decor_density": 0.8,
		"effect_density": 0.75,
		"minimap_bake_us": 450,
		"hud_redraw_hz": 30,
		"msaa_3d": Viewport.MSAA_DISABLED,
		"scaling_3d_scale": 0.85,
		"max_fps": 60,
	},
	Tier.HIGH: {
		"wall_detail": 1.0,
		"decor_density": 1.0,
		"effect_density": 1.0,
		"minimap_bake_us": 600,
		"hud_redraw_hz": 0,
		"msaa_3d": Viewport.MSAA_2X,
		"scaling_3d_scale": 1.0,
		"max_fps": 60,
	},
}

## Profile / settings value overriding the heuristic (-1 = automatic).
static var override_tier := -1
static var _detected := -1


## Tier the game should use: override, else the (once detected) heuristic.
static func current_tier() -> int:
	if override_tier >= 0:
		return clampi(override_tier, Tier.LOW, Tier.HIGH)
	if _detected < 0:
		_detected = choose_tier(device_info())
	return _detected


## Copy of the switches of a tier (callers may change it).
static func settings(tier: int = -1) -> Dictionary:
	if tier < 0:
		tier = current_tier()
	return (PRESETS[clampi(tier, Tier.LOW, Tier.HIGH)] as Dictionary).duplicate()


## One switch of the current tier with a fallback.
static func value(key: String, fallback: Variant = null) -> Variant:
	return settings().get(key, fallback)


static func set_override(tier: int) -> void:
	override_tier = tier if tier >= Tier.LOW and tier <= Tier.HIGH else -1


static func tier_id(tier: int) -> String:
	return TIER_IDS[clampi(tier, Tier.LOW, Tier.HIGH)]


static func tier_name(tier: int) -> String:
	return TIER_NAMES[clampi(tier, Tier.LOW, Tier.HIGH)]


## "low"/"medium"/"high" (or the German names) -> Tier; unknown -> -1.
static func parse(text: String) -> int:
	var key := text.strip_edges().to_lower()
	for index in TIER_IDS.size():
		if key == TIER_IDS[index] or key == String(TIER_NAMES[index]).to_lower():
			return index
	return -1


## Device data for the heuristic (separate so choose_tier() stays testable).
static func device_info() -> Dictionary:
	var screen := DisplayServer.screen_get_size() if DisplayServer.get_name() != "headless" else Vector2i(1080, 2340)
	var memory := OS.get_memory_info()
	return {
		"os": OS.get_name(),
		"cores": OS.get_processor_count(),
		"cpu": OS.get_processor_name(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"vendor": RenderingServer.get_video_adapter_vendor(),
		"screen": screen,
		"memory_mb": int(memory.get("physical", 0)) / 1048576,
	}


## Conservative heuristic: desktop HIGH; mobile scores GPU family, cores and
## memory (Adreno 7xx/8xx, Mali-G7xx/Immortalis and >= 8 GB -> HIGH, e.g.
## Galaxy S25). Very many pixels (> 3.2 MP) lower a non-HIGH tier once more.
static func choose_tier(info: Dictionary) -> int:
	var os_name := String(info.get("os", ""))
	if os_name in ["Windows", "macOS", "Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD"]:
		return Tier.HIGH
	var score := 0
	var adapter := String(info.get("adapter", "")).to_lower()
	score += _gpu_class(adapter)
	if int(info.get("cores", 4)) >= 8:
		score += 1
	var memory_mb := int(info.get("memory_mb", 0))
	if memory_mb >= 7500:
		score += 2
	elif memory_mb >= 5500:
		score += 1
	var tier := Tier.LOW
	if score >= 5:
		tier = Tier.HIGH
	elif score >= 3:
		tier = Tier.MEDIUM
	var screen: Vector2i = info.get("screen", Vector2i(1080, 2340))
	if tier != Tier.HIGH and screen.x * screen.y > 3_200_000:
		tier = maxi(Tier.LOW, tier - 1)
	return tier


## 0 = unknown/weak, 1 = mid range, 2 = current high end.
static func _gpu_class(adapter: String) -> int:
	var digits := _first_number(adapter)
	if adapter.contains("adreno"):
		if digits >= 730:
			return 2
		if digits >= 610:
			return 1
		return 0
	if adapter.contains("immortalis"):
		return 2
	if adapter.contains("mali-g"):
		if digits >= 710:
			return 2
		if digits >= 57:
			return 1
		return 0
	if adapter.contains("xclipse") or adapter.contains("apple"):
		return 2
	if adapter.contains("powervr"):
		return 0
	return 1 if adapter != "" else 0


static func _first_number(text: String) -> int:
	var digits := ""
	for character in text:
		if character >= "0" and character <= "9":
			digits += character
		elif digits != "":
			break
	return int(digits) if digits != "" else 0


## Applies the viewport switches (MSAA, 3D scale, FPS cap). The compatibility
## renderer only supports bilinear 3D scaling.
static func apply_viewport(viewport: Viewport, values: Dictionary) -> void:
	if viewport == null:
		return
	viewport.msaa_3d = int(values.get("msaa_3d", Viewport.MSAA_DISABLED))
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = clampf(float(values.get("scaling_3d_scale", 1.0)), 0.5, 1.0)
	Engine.max_fps = int(values.get("max_fps", 0))


## Number of decorative parts for a density (deterministic: takes the first n).
static func scaled_count(full: int, density: float) -> int:
	return clampi(int(round(float(full) * clampf(density, 0.0, 1.0))), 0, full)
