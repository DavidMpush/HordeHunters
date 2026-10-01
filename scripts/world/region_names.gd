extends RefCounted

# Region names (minimap stage). Every arena region (arena.gd REGION x REGION
# chunks) gets a German name that fits its biome, built from a syllable kit:
# prefix + suffix ("Moos" + "grund" = "Moosgrund"). The choice depends only on
# the world seed, the region and the biome, so the same seed always names the
# same land the same way; after a migration the land is renamed in the new
# biome's words. An optional landmark phrase ("am Wurzelbogen") refers to a
# landmark standing in the region (banner and big map only; the label under
# the minimap stays short).

const MAX_LENGTH := 14

const KITS := {
	"verdant_maw": {
		"prefix": ["Moos", "Wurzel", "Dornen", "Tümpel", "Farn", "Moor", "Ranken", "Laub", "Pilz", "Schilf", "Nebel", "Efeu", "Kraut", "Borken", "Sporen", "Wisper", "Grün", "Blatt", "Distel", "Kolben"],
		"suffix": ["grund", "hain", "senke", "tal", "mulde", "wiese", "au", "bruch", "winkel", "furt", "hang", "pfad", "weiher", "dickicht", "lichtung", "flur"],
	},
	"duerrschlund": {
		"prefix": ["Sand", "Dünen", "Knochen", "Staub", "Rippen", "Kaktus", "Dorn", "Ocker", "Glut", "Wind", "Schädel", "Salz", "Stein", "Durst", "Geier", "Bogen"],
		"suffix": ["feld", "senke", "grat", "mulde", "rinne", "tal", "kamm", "becken", "hang", "furt", "grund", "kessel", "wall", "pfad", "schlucht"],
	},
	"glutsumpf": {
		"prefix": ["Asche", "Glut", "Schlacken", "Rauch", "Funken", "Ruß", "Kohle", "Brand", "Schwefel", "Qualm", "Zunder", "Lava", "Essen", "Sud", "Glimm", "Dampf"],
		"suffix": ["kessel", "furt", "grube", "feld", "senke", "pfuhl", "mulde", "rinne", "schlund", "becken", "tiegel", "grund", "hang", "moor", "bruch"],
	},
}

# Landmark phrases per arena Landmark type (ROOT_ARCH, FALLEN_LOG, POND, MEADOW).
const PHRASES := {
	"verdant_maw": [["am Wurzelbogen", "unterm Wurzeltor"], ["am Moderstamm", "beim Faulholz"], ["am Weiher", "am Grünen Auge"], ["an der Blütenwiese", "im Blumenkreis"]],
	"duerrschlund": [["am Felsbogen", "unterm Sandtor"], ["bei den Rippen", "am Knochenkamm"], ["an der Oase", "am Blauen Auge"], ["im Kaktushain", "am Dornkreis"]],
	"glutsumpf": [["am Kohlebogen", "unterm Rußtor"], ["bei den Glutstümpfen", "am Stumpfkreis"], ["am Lavaauge", "am Glutbecken"], ["am Pilzfeuer", "im Glimmkreis"]],
}


static func _kit(biome_id: String) -> Dictionary:
	return KITS.get(biome_id, KITS["verdant_maw"])


static func _mix(seed_value: int, region: Vector2i, salt: int) -> int:
	var n := seed_value * 0x2545F491 + region.x * 374761393 + region.y * 668265263 + salt * 144269
	n = (n ^ (n >> 15)) * 2246822519
	n = (n ^ (n >> 13)) * 3266489917
	n = n ^ (n >> 16)
	return n & 0x7FFFFFFFFFFFFFFF


## Short region name ("Moosgrund"); deterministic per seed, region and biome.
static func name_for(seed_value: int, region: Vector2i, biome_id: String) -> String:
	for attempt in 8:
		var result := _candidate(seed_value, region, biome_id, attempt)
		if result != "":
			return result
	var kit := _kit(biome_id)
	var prefixes: Array = kit.prefix
	var salt := 17 if biome_id == "glutsumpf" else (29 if biome_id == "duerrschlund" else 3)
	return String(prefixes[_mix(seed_value, region, salt) % prefixes.size()]) + String(kit.suffix[0])


# Name of one attempt, or "" if it reads badly.
static func _candidate(seed_value: int, region: Vector2i, biome_id: String, attempt: int) -> String:
	var kit := _kit(biome_id)
	var prefixes: Array = kit.prefix
	var suffixes: Array = kit.suffix
	var salt := 17 if biome_id == "glutsumpf" else (29 if biome_id == "duerrschlund" else 3)
	var roll := _mix(seed_value, region, salt + attempt * 31)
	var prefix: String = prefixes[roll % prefixes.size()]
	var suffix: String = suffixes[(roll / prefixes.size()) % suffixes.size()]
	# Avoid doubled letters at the seam that read badly ("Moorrinne" is fine,
	# "Auau" is not) and names too long for the minimap label.
	if prefix.to_lower().ends_with(suffix.substr(0, 2)):
		return ""
	var result := prefix + suffix
	return result if result.length() <= MAX_LENGTH else ""


## Unique names for every region of a bounded map (stage 18): each region keeps
## its own name_for() unless an earlier region (in the given order) already has
## it; then further attempts are tried. Prefixes are also kept apart where the
## kit allows, so neighbours never read alike ("Moosgrund" / "Moostal").
static func map_names(seed_value: int, regions: Array, biome_id: String) -> Dictionary:
	var result := {}
	var used := {}
	var prefixes_used := {}
	var prefix_count := (_kit(biome_id).prefix as Array).size()
	for region in regions:
		var chosen := ""
		for pass_index in 2:
			for attempt in 64:
				var name := _candidate(seed_value, region, biome_id, attempt)
				if name == "" or used.has(name):
					continue
				var prefix := _prefix_of(name, biome_id)
				# First pass: a fresh prefix while there are enough of them.
				if pass_index == 0 and prefixes_used.has(prefix) and prefixes_used.size() < prefix_count:
					continue
				chosen = name
				break
			if chosen != "":
				break
		if chosen == "":
			chosen = "%s %d" % [name_for(seed_value, region, biome_id), used.size() + 1]
		used[chosen] = true
		prefixes_used[_prefix_of(chosen, biome_id)] = true
		result[region] = chosen
	return result


static func _prefix_of(name: String, biome_id: String) -> String:
	for prefix in _kit(biome_id).prefix:
		if name.begins_with(String(prefix)):
			return String(prefix)
	return name


## Landmark phrase for the region ("am Wurzelbogen") or "" (no landmark, or the
## seed decided to keep the name plain). `landmark_types` = arena Landmark ids.
static func phrase_for(seed_value: int, region: Vector2i, biome_id: String, landmark_types: Array) -> String:
	if landmark_types.is_empty():
		return ""
	var roll := _mix(seed_value, region, 211)
	if roll % 3 == 0:
		return ""
	var table: Array = PHRASES.get(biome_id, PHRASES["verdant_maw"])
	var type := int(landmark_types[roll % landmark_types.size()])
	if type < 0 or type >= table.size():
		return ""
	var options: Array = table[type]
	return String(options[(roll / 7) % options.size()])


## Name plus phrase ("Moosgrund am Wurzelbogen").
static func full_name(seed_value: int, region: Vector2i, biome_id: String, landmark_types: Array) -> String:
	var phrase := phrase_for(seed_value, region, biome_id, landmark_types)
	var base := name_for(seed_value, region, biome_id)
	return base if phrase == "" else "%s %s" % [base, phrase]
