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
