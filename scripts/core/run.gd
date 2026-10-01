extends RefCounted

# Run state of stage 1: time, kills, death. Only death ends a run.

var elapsed := 0.0
var kills := 0
var kills_by_kind := PackedInt32Array([0, 0, 0])
var shots := 0
var damage_dealt := 0.0
var damage_taken := 0.0
var dead := false
## Seconds since death (the result screen appears after a short beat).
var since_death := 0.0
var runs := 1


func reset() -> void:
	elapsed = 0.0
	kills = 0
	kills_by_kind = PackedInt32Array([0, 0, 0])
	shots = 0
	damage_dealt = 0.0
	damage_taken = 0.0
	dead = false
	since_death = 0.0


func step(delta: float) -> void:
	if dead:
		since_death += delta
	else:
		elapsed += delta


func add_kill(kind: int) -> void:
	kills += 1
	if kind >= 0 and kind < kills_by_kind.size():
		kills_by_kind[kind] += 1


func die() -> void:
	if dead:
		return
	dead = true
	since_death = 0.0


## "2:05"
static func clock(seconds: float) -> String:
	var whole := int(floor(seconds))
	return "%d:%02d" % [whole / 60, whole % 60]
