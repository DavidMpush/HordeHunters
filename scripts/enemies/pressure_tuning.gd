extends RefCounted

# Numbers of stage 2, Teil B (Druck): multi-side packs, announced waves,
# encircle rings, champion Brocken, the Moorkönig boss and the Endwelle
# (stages/02_run_loop.md). Kept apart from tuning.gd so Teil A and Teil B can
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
