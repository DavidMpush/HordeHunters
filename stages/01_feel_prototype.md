# Etappe 1 – Spielgefühl-Prototyp

Ziel: Der Nutzer spielt 3 Minuten Brann mit der Schrotflinte gegen Nahkampf-Horden auf einer Verdant-Karte, und es macht Spaß. Erst danach folgt die Run-Schleife (Etappe 2). Grundlage: `DESIGN_BRIEF.md`, `stages/00_plan.md`.

## Teil A – Welt (Port aus Mawlings)
1. Kartengenerator und Darstellung aus Mawlings übernehmen:
   - `arena.gd`, `map_explore.gd`, `map_layout.gd`, `arena_border.gd`, `wall_mesh.gd`, `flow_field.gd`, `biomes.gd`, `region_names.gd` und die Shader (`wall`, `water`, `verdant_ground`, `ground_field.gdshaderinc`, `prop_fade`, `ember_*`, `desert_ground`, `lava`, `ember_noise`).
   - Wände und Boden vom Mawlings-Branch `wip/etappe-34-37` nehmen (Etappe 34).
   - Nötige Assets (Requisiten, Texturen) mitkopieren.
2. Alles Schwarm-Spezifische entfernen (Population, Treffer pro Tier, Schwarm-Radius-Sonderfälle). Der Fokus der Karte ist ein **Ziel-Node** (der Held).
3. `scenes/main.tscn`:
   - Wurzel `Main` (`scripts/main.gd`) mit `Arena`, `Camera3D` (Offset wie Mawlings `CAMERA_OFFSET` (0, 23, 15), folgt weich dem Helden), Sonne und Umgebung wie in Mawlings.
   - Platzhalter-Knoten `Hero` (Node3D), den Teil B ersetzt.
4. Schnittstelle der Arena (für Held und Gegner):
   - `sync(focus: Vector3)`
   - `resolve_motion(start, motion, radius) -> Vector3`
   - `is_open(point, radius) -> bool`
   - `safe_spawn(point, radius) -> Vector3`
   - `spawn_point_near(center, radius, angle, clearance) -> Vector3`
   - `playable_rect() -> Rect2`, `map_center() -> Vector3`
   - `set_seed(seed: int)`, `has_layout() -> bool`
   - Flow-Field-Richtung zum Ziel für Gegner, z. B. `flow_direction(from: Vector3) -> Vector3` (aus Mawlings `flow_field`/`steer_direction`).
5. Tests: Karte baut deterministisch, Bewegung gleitet an Wänden, Spawns auf offenem Boden; dazu ein Prüfbild aus der Spielkamera.

## Teil B – Held, Shotgun, Gegner
1. **Held Brann** (`scripts/hero/hero.gd`, Platzhalter-Modell aus Grundformen im V2-Look):
   - stämmiger Körper, Kopf mit Bart, orange Schürze, dunkles Hemd, doppelläufige Flinte als eigenes Teil
   - prozedurale Animation: Laufen (Wippen, Beinpendel), Zielen (Oberkörper und Flinte drehen zum Ziel), Schuss-Rückstoß, Nachladen (Flinte kippt auf, Hülsen fliegen, schnappt zu), Treffer-Blitz
   - 100 LP, kurze Unverwundbarkeit nach Treffer
2. **Steuerung:**
   - schwebender Joystick rechts (aus Mawlings `touch_controls.gd` übernehmen) und WASD
   - **Dash** links (Knopf im Brawl-Stil, Leertaste): 5 m in 0,18 s, unverwundbar währenddessen, 2,5 s Abklingzeit
3. **Shotgun** (`scripts/weapons/shotgun.gd`):
   - Auto-Aim auf den nächsten Gegner in 8 m, 2 Schuss, dann Nachladen 0,7 s; 0,35 s zwischen den beiden Schüssen
   - 7 Kugeln im 34°-Fächer als sichtbare Leuchtspuren
   - Schaden je Kugel fällt ab 3 m linear auf 40 % bei 8 m; die erste getroffene Kugel stoppt (kein Durchschlag)
   - Rückstoß nach Masse: leicht 4 m/s, mittel 1,5 m/s, schwer bzw. Boss 0
   - Feedback: Mündungsfeuer, Hülsen, Kamera-Ruck, Funken am Treffer, Schadenszahlen (aus Mawlings `hud_damage.gd`)
4. **Gegner** (`scripts/enemies/`), Massen-Darstellung per MultiMesh (Technik aus Mawlings `horde.gd`), Trennungskräfte, Flow-Field-Verfolgung:

   | Typ | LP | Tempo | Masse | Hieb |
   |---|---|---|---|---|
   | Wichtel | 12 | 3,2 | leicht | 8 Schaden, 0,35 s Ausholen, Reichweite 1,1 m |
   | Renner | 8 | 5,5 | leicht | 6 Schaden, 0,25 s Ausholen |
   | Brocken | 120 | 2,0 | schwer | 22 Schaden, 0,8 s Ausholen mit Bogen-Markierung am Boden, Reichweite 2,2 m |

   - **Ablauf:** Annähern → in Reichweite stoppen und sichtbar ausholen (Körper lehnt zurück, Farb-Blitz; beim Brocken eine Magenta-Bogenfläche) → Treffer nur, wenn der Held am Ende des Ausholens noch in Reichweite ist → kurze Erholung.
   - **Modelle:** vorerst Mawlings-Kreaturen als Platzhalter (Moorbrut für Wichtel, Skitter für Renner, Jäger für Brocken), umgefärbt.
5. **Direktor** (`scripts/enemies/director.gd`):
   - Spawns außerhalb des Bildes, Dichte steigt über 5 Minuten (Wichtel ab 0 s, Renner ab 40 s, Brocken ab 90 s)
   - kleine Rudel; Deckel 250 lebende Gegner
6. **Run und HUD:**
   - Zeit, LP-Leiste über dem Helden und oben, Kill-Zähler
   - Tod → Ergebnisbildschirm (Zeit, Kills) → NOCHMAL
   - UI-Kit `brawl` aus Mawlings (`ui_style.gd`, `ui_kit_brawl.gd`, Schriften)
7. **Tests:**
   - Dash (Strecke, Unverwundbarkeit, Abklingzeit)
   - Shotgun (2 Schuss, Nachladen, Fächer, Abfall, Rückstoß nach Masse)
   - Gegner (Ausholen, Treffer nur in Reichweite, Weglaufen rettet)
   - Direktor (Dichte steigt, Spawns außerhalb des Bildes, Deckel)
   - Tod und Neustart
   - Prüfbilder: Kampf mit Schuss und fliegenden Wichteln; Brocken holt aus; Nachladen

## Abnahme
- Suite grün; Prüfbilder gesichtet.
- Leistung: 250 Gegner bei stabilen Frames (Desktop-Bench als Näherung).
- **Handtest durch den Nutzer** (PC: F5; danach APK).

## Schnittstellen (Teil A – Welt, umgesetzt)
Dateien: `scripts/world/` (`arena.gd`, `map_explore.gd`, `map_layout.gd`, `arena_border.gd`, `wall_mesh.gd`, `flow_field.gd`, `biomes.gd`, `region_names.gd`, `map_beacons.gd`, `quality.gd`, `world_tuning.gd`), Shader unter `shaders/`, Requisiten unter `assets/gameplay/props/`. Stand der Optik = Mawlings `wip/etappe-34-37` (Prüfbilder farbgleich mit Mawlings `preview_walls_*`).

**Szene `scenes/main.tscn`:** `Main` (`scripts/main.gd`) mit `Arena`, `Hero` (Node3D, Platzhalter-Kapsel als Kind `Placeholder`), `Camera3D`, `Sun`, `WorldEnvironment`.
- `main.hero: Node3D`, `main.arena`, `main.camera`, `main.camera_jitter: Vector3` (Kamera-Ruck, ungeglättet), `main.start_world(seed: int, biome := "verdant_maw")` (Karte neu, Held auf Startpunkt, Kamera einrasten), `main.snap_camera()`.
- `Main` läuft nach seinen Kindern (`process_priority = 100`): Held bewegt sich in seinem eigenen `_process`/`_physics_process`, `Main` ruft danach `arena.sync(hero.position)` und führt die Kamera nach.
- WASD bewegt nur, solange `Hero` **kein Skript** hat. Teil B hängt `scripts/hero/hero.gd` an den Knoten `Hero` (oder ersetzt ihn durch eine gleichnamige Node3D) und löscht `Hero/Placeholder`; Gegner, Direktor, HUD kommen als weitere Kinder von `Main`.

**Arena** (`scripts/world/arena.gd`, Kopfkommentar):
- `sync(focus: Vector3) -> void` – Chunks, Flow-Field-Quelle, Durchsicht-Fenster folgen dem Fokus; `arena.focus` = letzter Fokus.
- `resolve_motion(start: Vector3, motion: Vector3, radius: float) -> Vector3` – Kollision, gleitet an Wänden/Steinen, bleibt im Spielfeld; Treibsand und Flachufer bremsen.
- `is_open(point: Vector3, radius: float) -> bool`
- `safe_spawn(point: Vector3, radius: float) -> Vector3`
- `spawn_point_near(center: Vector3, distance: float, angle: float, clearance: float) -> Vector3` – `Vector3.INF`, wenn nichts passt (oder Seed 0).
- `spawn_points(count: int) -> Array[Vector3]` – Startpunkt(e).
- `playable_rect() -> Rect2`, `map_center() -> Vector3`, `wall_distance(point) -> float`
- `set_seed(seed: int)` (0 = klassische offene Karte), `has_layout() -> bool`, `set_biome(id: String, staggered := false)` (`verdant_maw`, `glutsumpf`, `duerrschlund`)
- `flow_direction(from: Vector3, radius := 0.6) -> Vector3` – Einheitsrichtung zum aktuellen Fokus: gerade bei freier Sicht (≤ 14 m), sonst über das gemeinsame Flow-Field um Wände herum; Steine werden umgangen. `ZERO` am Fokus.
- `flow_distance(from: Vector3) -> float` (Laufweg, `INF` unbekannt), `steer_direction(from, target, radius)` für beliebige Ziele.
- Für Tests/Ladebild: `finish_rebuild()`, `finish_flow(point)`; `chunk_budget` (Main: 1 Chunk pro Frame).

**Tests:** `tests/world.gd` (in `tools/test.ps1`): Seed deterministisch, Gleiten an Wänden, `safe_spawn`/`spawn_point_near` offen, `flow_direction` führt um Wände zum Ziel, alle drei Biome bauen. Prüfbilder: `tests/capture_world.gd` → `previews/preview_world_*.png` (Start, Felsrücken, Dickicht, Wald, See, Kartenrand, Glutsumpf-Rücken und Lavasee, Wüsten-Klippen und Kakteen).

## Umsetzung Teil B – Held, Shotgun, Gegner (Stand 01.10.)
Dateien: `scripts/core/` (`battle.gd` verdrahtet alles, `tuning.gd` alle Zahlen, `run.gd`, `sfx.gd`, `flat_arena.gd` + `combat_lab.gd` für `scenes/combat_lab.tscn`), `scripts/hero/` (`hero.gd`, `brann_model.gd`), `scripts/weapons/shotgun.gd`, `scripts/enemies/` (`horde.gd`, `director.gd`), `scripts/combat/` (`effects.gd`, `fx_batch.gd`, `camera_shake.gd`), `scripts/ui/` (`hud.gd`, `touch_controls.gd`, `ui_style.gd`, `ui_kit_brawl.gd`), Shader `toon_part`, `enemy`, `telegraph_arc`. Assets: `assets/enemies/` (Moorbrut/Skitter/HunterBeetle als Platzhalter), `assets/ui/fonts/`, `assets/audio/` (Mawlings-Sounds; Schuss, Klicks, Hülsen und Dash synthetisch).

**Einbindung:** `main.tscn` – `Hero` trägt `hero.gd` (Platzhalter-Kapsel entfernt), neuer Knoten `Battle` (`battle.gd`). Reihenfolge je Frame: Eingabe → Held → Shotgun → Gegner → Direktor → Effekte → Run; danach synct `Main` die Arena und führt die Kamera. Kamera-Ruck und Schütteln über `Camera3D.h_offset/v_offset` (kein Eingriff in `main.gd`). NOCHMAL setzt den Helden auf `arena.spawn_points(1)[0]`, gleiche Karte.

**Zahlen** (`tuning.gd`; Spezifikation unverändert, frei gewählt): Held 4,8 m/s, Radius 0,45, 0,6 s Unverwundbarkeit nach Treffer; Kugel 8 Schaden bis 3 m, linear auf 40 % bei 8 m; Rückstoß klingt mit 4/s ab (leicht 4 m/s ≈ 1 m Rutschen); Reichweite = Gegnermitte bis Heldenrand, Ausholen beginnt bei 75 % der Reichweite; Erholung Wichtel 0,75 s, Renner 0,6 s, Brocken 1,1 s; Brocken-Bogen ±60°; leichte Gegner taumeln 0,25 s, wenn sie beim Ausholen getroffen werden; anlaufende Gegner zielen etwas vor den laufenden Helden (Wichtel 0,3 s, Renner 0,7 s). Direktor: gewünschte Dichte 10 → 40 (1 min) → 130 (3 min) → 250 (5 min), Rudel 4–12, jede neue Art hat ihr eigenes erstes Rudel, die Hälfte der Rudel kommt aus der Laufrichtung, Gegner über 42 m werden nach vorn versetzt.

**Tests** (`tools/test.ps1`): `dash`, `shotgun`, `enemy_melee`, `director`, `death_restart`. Prüfbilder: `tests/capture_fight.gd` (`preview_fight_shot/after/reload/brocken/hit/horde/result`), `tests/capture_models.gd` (Nahaufnahmen, Nachlade-Folge). Leistung: `tests/perf_bench.gd` (`tools/perf.ps1 -Only worst`; `-- steps=600` headless, `vsync=off`, `off=hud|horde|battle`). Balance-Sonde: `tests/balance_probe.gd -- idle|kite`.
