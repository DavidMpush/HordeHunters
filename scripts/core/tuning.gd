extends RefCounted

# Combat numbers of stage 1, Teil B (stages/01_feel_prototype.md). The spec
# values are binding starting values; everything marked (frei) was chosen here
# and is open for the hand test.

# ---------------------------------------------------------------- hero
const HERO_HP := 100.0
const HERO_SPEED := 4.8                 # (frei) m/s: faster than Wichtel, slower than Renner
const HERO_RADIUS := 0.45               # (frei) body circle for walls and enemy reach
const HERO_HURT_INVULN := 0.6           # (frei) "kurze Unverwundbarkeit" after a hit
const HERO_ACCEL := 40.0                # (frei) m/s^2 towards the stick velocity

# Dash: 5 m in 0.18 s, invulnerable, 2.5 s cooldown.
const DASH_DISTANCE := 5.0
const DASH_SECONDS := 0.18
const DASH_COOLDOWN := 2.5

# ---------------------------------------------------------------- shotgun
const GUN_RANGE := 8.0                  # auto-aim radius and pellet reach
const GUN_SHELLS := 2
const GUN_SHOT_GAP := 0.35              # between the two shots
const GUN_RELOAD := 0.7
const GUN_PELLETS := 7
const GUN_FAN_DEG := 34.0
const GUN_PELLET_DAMAGE := 8.0          # (frei) per pellet at <= 3 m
const GUN_FALLOFF_START := 3.0          # damage falls linearly from here ...
const GUN_FALLOFF_MIN := 0.4            # ... to 40 % at GUN_RANGE
const GUN_TOPUP_IDLE := 1.0             # (frei) half-empty gun reloads after this long without target
const GUN_PELLET_JITTER_DEG := 1.2      # (frei) small random spread per pellet

# Knockback by mass (m/s at the hit, per shot - not per pellet).
const KNOCK_LIGHT := 4.0
const KNOCK_MEDIUM := 1.5
const KNOCK_HEAVY := 0.0
const KNOCK_FRICTION := 4.0             # (frei) 1/s decay of the knock velocity

# ---------------------------------------------------------------- enemies
enum Kind { WICHTEL, RENNER, BROCKEN }
enum Mass { LIGHT, MEDIUM, HEAVY }

# hp, speed (m/s), mass, damage, windup (s), reach (m, from the hero's body
# edge), recover (s, frei), radius (body, frei), arc (half angle of the
# Brocken swing in degrees; 0 = any direction within reach), lead (s, frei:
# approaching enemies aim where the hero will be, cutting off pure running).
const ENEMIES := {
	Kind.WICHTEL: {"name": "Wichtel", "hp": 12.0, "speed": 3.2, "mass": Mass.LIGHT, "damage": 8.0,
		"windup": 0.35, "reach": 1.1, "recover": 0.75, "radius": 0.45, "arc": 0.0, "lead": 0.3},
	Kind.RENNER: {"name": "Renner", "hp": 8.0, "speed": 5.5, "mass": Mass.LIGHT, "damage": 6.0,
		"windup": 0.25, "reach": 1.0, "recover": 0.6, "radius": 0.42, "arc": 0.0, "lead": 0.7},
	Kind.BROCKEN: {"name": "Brocken", "hp": 120.0, "speed": 2.0, "mass": Mass.HEAVY, "damage": 22.0,
		"windup": 0.8, "reach": 2.2, "recover": 1.1, "radius": 0.95, "arc": 60.0},
}
## Wind-up starts when the hero is closer than this share of the reach.
const ENGAGE_SHARE := 0.75
## A light enemy hit during its wind-up is interrupted (s of stagger).
const STAGGER_SECONDS := 0.25

# ---------------------------------------------------------------- director
const ENEMY_CAP := 250
const RENNER_FROM := 40.0
const BROCKEN_FROM := 90.0
const RAMP_SECONDS := 300.0             # density ramp over 5 minutes
# Wanted living enemies over time (linear between the points, frei).
const DENSITY := [[0.0, 10.0], [60.0, 40.0], [120.0, 80.0], [180.0, 130.0], [240.0, 190.0], [300.0, 250.0]]
const PACK_INTERVAL := [[0.0, 2.2], [120.0, 1.4], [300.0, 0.8]]
const PACK_SIZE := [[0.0, 4.0], [120.0, 7.0], [300.0, 12.0]]
const SPAWN_MIN_DISTANCE := 14.0        # never closer to the hero than this


static func enemy(kind: int) -> Dictionary:
	return ENEMIES[kind]


static func knock_for(mass: int) -> float:
	match mass:
		Mass.LIGHT:
			return KNOCK_LIGHT
		Mass.MEDIUM:
			return KNOCK_MEDIUM
	return KNOCK_HEAVY


## Damage of one pellet hitting at `distance` metres.
static func pellet_damage(distance: float) -> float:
	if distance <= GUN_FALLOFF_START:
		return GUN_PELLET_DAMAGE
	var t := clampf((distance - GUN_FALLOFF_START) / (GUN_RANGE - GUN_FALLOFF_START), 0.0, 1.0)
	return GUN_PELLET_DAMAGE * lerpf(1.0, GUN_FALLOFF_MIN, t)


## Piecewise linear lookup in [[x, y], ...].
static func curve(table: Array, x: float) -> float:
	if x <= float(table[0][0]):
		return float(table[0][1])
	for i in range(1, table.size()):
		var a: Array = table[i - 1]
		var b: Array = table[i]
		if x <= float(b[0]):
			return lerpf(float(a[1]), float(b[1]), (x - float(a[0])) / (float(b[0]) - float(a[0])))
	return float(table[table.size() - 1][1])
