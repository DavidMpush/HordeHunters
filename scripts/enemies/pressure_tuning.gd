extends RefCounted

# Numbers of stage 2, Teil B (Druck): multi-side packs, announced waves,
# encircle rings, champion Brocken, the Moorkönig boss and the Endwelle
# (stages/02_run_loop.md); stage 4 Teil A: worlds, portal, bosses 2/3. Kept apart from tuning.gd so Teil A and Teil B can
# tune in parallel; everything here is (frei) and open for the hand test.

# ---------------------------------------------------------------- packs
## Packs spread over this many directions (2 -> 3 -> 4 over the run).
const PACK_SIDES := [[0.0, 2.0], [60.0, 2.0], [150.0, 3.0], [240.0, 4.0]]
## Share of packs that still come from where the hero runs to.
const PACK_HEADING_SHARE := 0.35
## The side set turns to new random angles this often (s).
const PACK_SIDES_SHUFFLE := 18.0
## From RENNER_FROM on, light packs are mixed: share of the other light kind.
const PACK_MIX := 0.3

# ---------------------------------------------------------------- waves
const WAVE_FIRST := 50.0                # first wave at 0:50
const WAVE_INTERVAL := [45.0, 60.0]     # random gap between waves
const WAVE_WARNING := 3.0               # "WELLE!" + edge arrow before the spawn
const WAVE_SIZE := 14                   # first wave, +WAVE_SIZE_STEP per wave
const WAVE_SIZE_STEP := 4
const WAVE_SIZE_MAX := 48
const WAVE_FRONT_SPREAD := 0.55         # rad: half width of the arc the wave comes in on
const WAVE_RENNER_SHARE := 0.35
const WAVE_BROCKEN_FROM := 120.0        # waves after 2:00 bring one Brocken
const WAVE_BOSS_GAP := 20.0             # no wave this close before the boss

# Encircle (from 2:00 every second wave): a ring of Wichtel with a bright gap
# closes slowly around the spot where the hero stood.
const ENCIRCLE_FROM := 120.0
const RING_RADIUS := 11.0               # start radius (m)
const RING_SPACING := 1.05              # metres between ring members
const RING_GAP := 4.0                   # width of the gap (m, kept while closing)
const RING_SPEED := 1.1                 # m/s the ring closes
const RING_END_RADIUS := 2.6            # ring dissolves into a normal chase here
const RING_MAX_SECONDS := 9.0
const RING_ESCAPE := 2.0                # hero this far outside the ring: it dissolves

# ---------------------------------------------------------------- elite
const ELITE_FROM := 90.0                # first champion at 1:30
const ELITE_INTERVAL := 75.0
const ELITE_HP_MULT := 2.0
const ELITE_SCALE := 1.3
const ELITE_SPEED := 2.2
const ELITE_REACH := 3.0                # stomp ring radius (from his centre to the hero's edge)
const ELITE_WINDUP := 1.0
const ELITE_DAMAGE := 26.0
const ELITE_RECOVER := 1.4
const ELITE_GOLD := 25

# ---------------------------------------------------------------- boss
const BOSS_AT := 240.0                  # Moorkönig at 4:00
const BOSS_WARNING := 3.0
const BOSS_HP := 1600.0
const BOSS_SPEED := 2.8
const BOSS_RADIUS := 1.5                # body circle (hits, hero push)
const BOSS_LENGTH := 4.6                # model fitted to this many metres
const BOSS_ARRIVE := 1.4                # emerging from the ground (not targetable)
const BOSS_SPAWN_DISTANCE := 9.0
# Stomp ring around the boss.
const STOMP_TRIGGER := 4.4
const STOMP_RADIUS := 4.6
const STOMP_WINDUP := 1.2
const STOMP_DAMAGE := 24.0
# Leap onto the hero (landing zone locked at the take-off decision, with a
# little lead so running straight on does not save you).
const LEAP_CROUCH := 0.55               # on the ground, zone already shown
const LEAP_AIR := 0.75                  # in the air (not targetable)
const LEAP_RADIUS := 3.4
const LEAP_DAMAGE := 28.0
const LEAP_LEAD := 0.6                  # s of hero motion added to the target ...
const LEAP_LEAD_MAX := 3.0              # ... at most this far
const LEAP_MAX := 18.0
const LEAP_HEIGHT := 4.5
const LEAP_FAR := 9.0                   # hero further than this: leap instead of walking
# Sweep: a wide arc in front of the boss.
const SWEEP_TRIGGER := 5.2
const SWEEP_REACH := 5.6
const SWEEP_HALF_DEG := 70.0
const SWEEP_WINDUP := 0.9
const SWEEP_DAMAGE := 22.0
const RECOVER := 1.1
const RECOVER_LEAP := 1.4
const CHASE_PATIENCE := 2.6             # s chasing for range before a leap is used instead
const BOSS_GOLD := 60
const BOSS_DENSITY := 0.5               # director density while the boss lives
const BREATHER := 12.0                  # no spawns after the boss falls

# ---------------------------------------------------------------- Endwelle
const END_AT := 360.0                   # 6:00
const END_DOUBLING := 45.0              # pack size doubles every 45 s
const END_INTERVAL_HALF := 60.0         # pack interval halves every 60 s
const END_INTERVAL_MIN := 0.2
const END_HP_GROWTH := 1.2              # enemy health x1.2 every END_HP_STEP s
const END_HP_STEP := 30.0
const END_SPEED_MAX := 0.25             # up to +25 % speed
const END_WAVE_INTERVAL := 22.0
const END_RECYCLE := 36.0               # far enemies come back sooner

# ---------------------------------------------------------------- worlds (stage 4 Teil A)
# A run crosses three worlds (biomes.gd ORDER); every world has its own clock
# (boss at BOSS_AT world time). Enemy health and damage per world, density
# (wanted living count and wave size) +20 % per world.
const WORLD_COUNT := 3
const WORLD_HP := [1.0, 1.6, 2.4]
const WORLD_DAMAGE := [1.0, 1.6, 2.4]
const WORLD_DENSITY := [1.0, 1.2, 1.4]
## The director's curves start this far in from world 2 on (Renner and Brocken
## from the first minute instead of a calm Wichtel start).
const WORLD_HEAD_START := 90.0
## Body tint of the mass enemies per world (alpha = amount mixed in).
## Complementary to the ground (violet on sand, cyan on peat) so they keep reading.
const WORLD_TINT := [Color(1, 1, 1, 0.0), Color(0.5, 0.22, 0.72, 0.3), Color(0.2, 0.7, 0.78, 0.25)]
## Portal: the hero stands this long inside it, then the next world loads.
const PORTAL_RADIUS := 2.2
const PORTAL_HOLD := 0.6
## The boss fell and the hero did not take the portal: Endwelle after this long.
const PORTAL_GRACE := 60.0
const FADE_OUT := 0.35
const FADE_IN := 0.45

# Bosses per world: the Moorkönig state machine with a model, health, damage
# and one extra attack per world (boss_king.gd configure()).
const BOSSES := [
	{"id": "moorkoenig", "title": "MOORKÖNIG", "model": "res://assets/enemies/BogKing_game.glb",
		"length": 4.6, "radius": 1.5, "hp": 1600.0, "damage": 1.0, "extra": "", "crown": true,
		"tint": Color(0.45, 0.66, 0.32, 0.0), "rim": Color("d8b8ff"), "ring": Color(0.48, 0.34, 0.2, 0.85)},
	{"id": "sandwurm", "title": "SANDWURM", "model": "res://assets/enemies/Sandwurm_game.glb",
		"length": 6.4, "radius": 1.7, "hp": 4200.0, "damage": 1.3, "extra": "charge", "crown": false,
		"tint": Color(1.0, 0.8, 0.5, 0.15), "rim": Color("ffe0a8"), "ring": Color(0.85, 0.66, 0.38, 0.85)},
	{"id": "aschenkroete", "title": "ASCHENKRÖTE", "model": "res://assets/enemies/AshToad_game.glb",
		"length": 5.4, "radius": 1.8, "hp": 7800.0, "damage": 1.6, "extra": "erupt", "crown": false,
		"tint": Color(1.0, 0.45, 0.25, 0.12), "rim": Color("ffb070"), "ring": Color(0.95, 0.4, 0.15, 0.85)},
]
# Sandwurm "Sandsturz": a straight lane from the worm through the hero's spot;
# after the wind-up the worm shoots along it.
const CHARGE_WINDUP := 1.1
const CHARGE_LENGTH := 14.0
const CHARGE_WIDTH := 3.2
const CHARGE_DASH := 0.4
const CHARGE_DAMAGE := 26.0
const CHARGE_TRIGGER := 11.0
# Aschenkröte "Glutregen": four glowing landing spots, one on the hero.
const ERUPT_WINDUP := 1.4
const ERUPT_COUNT := 4
const ERUPT_RADIUS := 2.4
const ERUPT_SPREAD := 4.8
const ERUPT_DAMAGE := 24.0
const ERUPT_TRIGGER := 12.0
