# Etappe 4 – Weltenreise, Evolutionen, Musik

Ziel: Ein Lauf kann **gewonnen** werden. Der Weg führt durch drei Welten mit je einem Boss. Waffen wachsen über **Evolutionen** weiter, zwei neue Waffen erweitern das Arsenal, und Musik und Sounds tragen die Höhepunkte. Grundlage: `DESIGN_BRIEF.md`, Etappen 1–3. Der Nutzer hat die Entscheidungen an den Orchestrator übergeben (01.10.2026).

## Entscheidungen (Orchestrator)
- **Drei Welten je Lauf:** Verdant → Dürrschlund → Glutsumpf (Biome aus Mawlings).
  - Jede Welt hat ihre eigene Uhr: Boss bei 4:00 Weltzeit.
  - Gesamtlauf etwa 13–15 Minuten.
- **Portal (Wunsch des Nutzers aus Mawlings):**
  - Erscheint dort, wo der Boss der Welt stirbt.
  - Hineinlaufen → nächste Welt mit neuer Karte und neuem Seed. Der Build bleibt (Waffen, Werte, Relikte, LP); Gems, Gold und Kokons am Boden verfallen.
  - Wer nach dem Boss trödelt, bekommt nach 60 s die **Endwelle** dieser Welt.
- **Sieg:** Boss der dritten Welt besiegt → Siegesbildschirm (Ergebnis mit „SIEG“, Zeit, Kills, Build) statt Portal. Danach NOCHMAL oder MENÜ.
- **Schwierigkeit je Welt:** Gegner-LP und -Schaden ×1,0 / ×1,6 / ×2,4; Dichte +20 % je Welt.
  - Bosse bis zu echten Modellen: Moorkönig, in Welt 2 und 3 umgefärbt und stärker.
  - Wenn die Modelle aus Mawlings passen, nimmt Welt 2 den Sandwurm und Welt 3 die Aschenkröte als Vorlage (Ziel = Held). Der Agent entscheidet nach Aufwand.
- **Evolutionen (Vampire-Survivors-Prinzip):**
  - Bedingung: Waffe auf Stufe 6 **und** das passende Relikt im Besitz.
  - Dann bietet der nächste Kokon (Elite oder Boss, nicht Karten-Kokon) die Evolutions-Karte an. Sie verwandelt die Waffe in ihre stärkere Form.
  - Je Waffe eine Evolution mit eigenem Namen, Icon und deutlichem Effekt.
- **Zwei neue Waffen** für alle Helden, im Arsenal schaltbar, mit den gleichen Regeln (Stufe 1–6).
- **Audio:**
  - Musik aus Mawlings (`music.gd`, Menü-Thema, Lauf-Stems nach Intensität, Boss, Wüsten-Set).
  - Fehlende Sounds: Gem und Gold aufsammeln, Level-up, Kokon öffnen, Boss-Brüllen, Portal, Sieg-Fanfare, Evolution.
  - Lautstärke folgt den Bussen Master, Music und SFX des Menüs.

## Teil A – Weltenreise und Sieg
Besitzt:
- `scripts/enemies/pressure.gd`, `pressure_tuning.gd`, `boss_*.gd` und neue Boss-Skripte
- `scripts/enemies/director.gd`, `horde.gd` (nur Skalierung)
- neues `scripts/world/portal.gd` (+ Shader)
- `scripts/main.gd`, `scripts/core/run.gd`
- `scripts/ui/hud.gd` (Ergebnis „SIEG“, Weltbanner), `scripts/ui/hud_pressure.gd`
- Tests `worlds.gd`, `victory.gd`

Schnittstellen, die Teil C nutzt:
- In `battle.gd` die Signale `portal_opened(at: Vector3)`, `world_changed(index: int, biome: String)` und `run_won`.
- `battle.world_index` (0..2).

## Teil B – Evolutionen und neue Waffen
Besitzt:
- `scripts/progression/progress.gd` (Evolutionen, neue Waffen, Relikte als Partner)
- `scripts/progression/progression.gd`
- `scripts/progression/chests.gd`
- `scripts/weapons/*` (neue Waffen, evolvierte Formen)
- `scripts/ui/choice_screen.gd` (Evolutions-Karte)
- `scripts/ui/icons.gd`
- Tests `evolutions.gd`, `new_weapons2.gd`

Schnittstelle: Signal `evolved(weapon_id: String)` an `progression.gd`.

## Teil C – Musik und Sounds
Besitzt:
- `scripts/core/sfx.gd`, neues `scripts/core/music.gd`
- `assets/audio/`, `assets/music/`, `LICENSES_mawlings.md`
- Menü-Musik in `scripts/menu/menu.gd` (nur Musikstart)
- in `battle.gd` eine eigene Funktion `_connect_audio()`
- Test `audio.gd`

Verbindet sich null-sicher (`has_signal`) mit den Signalen von A und B.

`battle.gd` ändern alle nur mit kleinen, lokalen Einträgen.

## Abnahme
- Suite grün.
- Prüfbilder: Portal nach dem Boss, Weltwechsel (Wüste), Boss in Welt 2/3, Siegesbildschirm, Evolutions-Karte, beide neuen Waffen im Kampf.
- Ein Bot-Lauf mit Upgrades erreicht Welt 2; der Sieg ist per Test erzwingbar.
- Danach folgt der **Handtest** durch den Nutzer.

## Teil D – Performance auf dem S25 und FPS-Anzeige (Vorrang)
Rückmeldung des Nutzers vom 01.10.: Auf dem S25 gibt es viele Lags und starke Ruckler.

1. **FPS-Anzeige:**
   - Kleine Einblendung oben links: FPS, Frame-Zeit in ms, Mini-Graph der letzten ~2 s, Draw Calls und Gegnerzahl.
   - Schalter „FPS-ANZEIGE“ in den Einstellungen (Profil-Setting `show_fps`, Standard: an, solange wir testen).
2. **Messen:**
   - Bench-Szene oder Skript mit festem Stresslauf (viele Gegner, alle Waffen, Effekte).
   - Erfasst Frame-Zeit, Prozesszeit, Draw Calls und Objekte, Ausgabe in `previews/perf_*.txt`.
   - Die größten Kosten werden gesucht und beseitigt.
   - Verdächtig:
     - Platzhalter-Held aus vielen Einzel-Meshes
     - Schatten
     - Schadenszahlen und Effekte ohne Pooling
     - Instanz-Uniforms
     - Wand- und Boden-Shader
     - Partikel
     - Ruckler durch Shader-Kompilierung beim ersten Auftreten (Warm-up beim Laden)
     - GC- bzw. `new()`-Spitzen je Frame
3. **Ruckler:**
   - Erste Effekte, Bosse und Waffen vorab laden bzw. warm rendern (Shader-Cache).
   - Allokationen im Frame vermeiden.
4. **Qualitätsstufen** (`scripts/world/quality.gd`), automatisch nach gemessener Frame-Zeit.

Besitzt:
- neues `scripts/ui/fps_overlay.gd`
- `scripts/menu/settings_sheet.gd`, Setting in `scripts/core/profile.gd`
- `scripts/world/*` außer `portal.gd`
- `shaders/*` außer neuen Portal- und Waffen-Shadern
- `scripts/combat/effects.gd`, `scripts/hero/*`, `project.godot`
- `tests/perf_*.gd`, `tools/perf.ps1`

Änderungen an Dateien anderer Teile (`horde.gd`, `hud.gd`, Waffen) meldet D dem Orchestrator mit Messwert, statt sie selbst zu machen.

## Umsetzung Teil C – Musik und Sounds
- **`scripts/core/music.gd`** (nach Mawlings): ein Knoten `Music` unter der Wurzel, überlebt den Szenenwechsel. Menü-Thema im Menü (`menu.gd`), im Lauf vier synchrone Stems (Basis, Spannung nach lebenden Gegnern 25→110, Flut bei Endwelle oder ≥170 Gegnern, Boss solange er lebt). Sets je Biom: Verdant `run_*`, Dürrschlund `desert_*`, Glutsumpf `run_*` tiefer (Pitch 0,92). Stinger: Boss-Ankündigung, Level-up (nur kurzes Ducking), neue Welt, Sieg (Fanfare), Niederlage; danach blenden die Loops aus. Alles auf dem Music-Bus, Überblendungen 1,2–2 s. Zustand wird mitgeführt, damit Tests mit Dummy-Treiber prüfen können.
- **`scripts/core/sfx.gd`**: alle Sounds beim Start geladen, keine Allokation je Abspielen, Pool 16. Neu: Gem-Tick (synthetisiert, Pentatonik-Leiter bei schnellem Aufsammeln, max. 2 Stimmen, ≥55 ms Abstand), Gold, Level-up, Kartenwahl, Kokon, Boss-Brüllen, Portal + Summen (lauter in Portalnähe), Welt-Whoosh, Fanfare, Evolution, Herzschlag unter 30 % LP. Aufsammeln, Kartenwahl, Summen und Herzschlag werden günstig abgefragt (Zähler von `run`/`progression`), weil `loot.gd` kein Signal hat.
- **`battle.gd`**: nur `_connect_audio()` + `_audio()`; Signale von A (`portal_opened`, `world_changed`, `run_won`) und B (`evolved` an `progression` oder `progress`) werden per `has_signal` verbunden. Das Biom liest die Musik zusätzlich aus `main.biome_id`.
- Dateien aus Mawlings: siehe `assets/audio/LICENSES_mawlings.md` (Abschnitt Etappe 4). WAV bleibt (kein OGG-Konverter vorhanden; 22 kHz mono, QOA-Import).
- Test `tests/audio.gd` (in `tools/test.ps1`).

## Umsetzung Teil B – Evolutionen und neue Waffen
- **Evolutionen** (`progress.gd` EVOLUTIONS): Bedingung Stufe 6 + Partner-Relikt. Der nächste Elite- oder Boss-Kokon legt die Karte sicher als erste von drei (eigene Kartenform: violett, Goldrand, Reiter „EVOLUTION“, Band „EVOLUTION!“). Karten- und Level-up-Wahl bieten sie nie an.
  - Schrotflinte → **Drachenatem** (Pulverhorn): Feuerkegel über den Fächer, die ersten 3 getroffenen Gegner explodieren, +2 Kugeln.
  - Fäuste → **Titanenfäuste** (neues Relikt Eisenbandagen, nur mit Fäusten): jeder Schlag löst eine goldene Schockwelle aus, +40 % Schaden.
  - Wurfaxt → **Blutmond-Axt** (Jagdtrophäe): 4 rote Riesenäxte, +50 % Schaden, Treffer heilen.
  - Schwert-Wirbel → **Klingenorkan** (Siebenmeilenstiefel): zwei Klingen kreisen ständig, Wirbel +20 %.
  - Granate → **Napalm** (neues Relikt Brandsatz, nur mit Granate): größere Explosion, brennende Fläche für 3 s.
  - Doppelpistolen → **Kugelhagel** (Kriegstrommel): 3 Kugeln je Schuss, Tempo ×1,8, +2 Durchschlag.
  - Blitzkette → **Gewittersturm** (Lockstein): Blitzeinschlag vom Himmel am ersten Ziel, +3 Sprünge.
- Partner-Relikte einer Waffe ab Stufe 4 kommen im Kokon mit 50 % zuerst; die Reliktkarte nennt die Evolution. Signal `progression.evolved(weapon_id)`, Helfer `weapon.evolved()`, `progress.is_evolved/weapon_name/weapon_icon`. Das Build im Ergebnis zeigt Name und Icon der Evolution (legendär, `evolved: true`).
- **Neue Waffen** (für alle Helden, im Arsenal schaltbar):
  - **Doppelpistolen:** abwechselnd auf die zwei nächsten Gegner bis 10 m, Treffer per Strahl, Durchschlag ab Stufe 3. Ergänzt die kurze Flinte um Fernkampf gegen Renner und Nachzügler.
  - **Blitzkette:** springt von Gegner zu Gegner, jeder Treffer unterbricht ein Ausholen. Defensives Werkzeug für dichte Horden, gut lesbar als heller Zickzack.
- Leistung: neue Effekte über `scripts/weapons/streaks.gd` (3 MultiMeshes je Waffe mit fester Kapazität, keine Allokation pro Frame). Die Klingen-Kreisbahn prüft Treffer ohne Allokation.
- Arsenal-Zeilen passen sich der Waffenzahl an (7 Zeilen über FERTIG).
- Tests: `evolutions`, `new_weapons2` neu; `upgrades`, `new_weapons`, `arsenal` auf 7 Waffen angepasst. Prüfbilder: `tests/capture_evolution.gd` → `preview_evolution_card`, `preview_weapon_pistols/lightning`, `preview_evolved_shotgun/sword/grenade/lightning`.
- Offen: Die Blitzkette auf Stufe 1 wirkt in dichten Pulks noch zart (Handtest). Der Schaden evolvierter Waffen läuft weiter unter dem alten Quellnamen (z. B. „Schrotflinte“).
## Umsetzung Teil A – Weltenreise und Sieg
- **Drei Welten** (`scripts/core/worlds.gd`, neu): Verdant Maw → Dürrschlund → Glutsumpf. Jede Welt hat ihre eigene Uhr (`pressure.world_start`): Wellen ab 0:50, Einkesselung ab 2:00, Champion ab 1:30, Boss bei 4:00 Weltzeit. Der Direktor läuft ab Welt 2 mit 90 s Vorsprung (Renner und Brocken von Anfang an). Die Laufzeit läuft weiter. `battle.world_index` 0..2; Signale `portal_opened(at)`, `world_changed(index, biome)` und `run_won` in `battle.gd`.
- **Portal** (`scripts/world/portal.gd` + `shaders/portal_vortex.gdshader`, nach Mawlings `migration_maw.gd`):
  - Aussehen: SandPortal-Maul als Rand, Wirbel in den Farben des Ziel-Bioms, Lichtsäule, Bodenring.
  - Lage: 6 m hinter dem Todesort des Bosses (vom Helden aus), auf freiem Boden und mindestens 5,6 m vom Boss-Kokon entfernt. So bleiben Kokon und Gems außerhalb.
  - Hinweise: Band „SIEG!“, nach 1,4 s „PORTAL OFFEN“. Ist es außer Sicht, zeigt der Randpfeil „PORTAL“ (Ton info) dorthin.
  - Wer 0,6 s darin steht, löst den Wechsel aus: Abblende 0,35 s, neue Karte (neuer Seed, nächstes Biom, Held auf dem Startpunkt), Aufblende 0,45 s, Band „WELT 2 · DÜRRSCHLUND“.
  - Gegner, Gems, Gold und Kokons am Boden verfallen. Build, LP, Level und Gold bleiben.
  - Wer trödelt, bekommt 60 s nach dem Boss die Endwelle (`pressure.end_at`).
- **Schwierigkeit je Welt** (`pressure_tuning.gd`): Gegner-LP und -Schaden ×1,0 / ×1,6 / ×2,4 (`director.world_hp`, `horde.damage_mult`), Dichte und Wellengröße ×1,0 / ×1,2 / ×1,4. Gegner-Tönung komplementär zum Boden: Wüste violett, Glutsumpf cyan (`horde.set_world_tint`). Die erste Variante (Sandfarbe) machte die Gegner auf Sand grau und schlecht lesbar und wurde verworfen.
- **Bosse – Entscheidung:** Die Modelle aus Mawlings werden übernommen, das Verhalten nicht. Sandwurm und Aschenkröte sind dort ~80 KB Schwarm-Logik (Eingraben, Orbits, Schwarm-Anteile). Die Moorkönig-Zustandsmaschine erfüllt die Regeln schon (magenta angekündigt, kein Rückstoß, Schaden nur in der gezeigten Form). Deshalb nimmt `boss_king.gd configure()` Modell, Größe, LP, Schaden und **einen Extra-Angriff**:
  - Welt 2 **Sandwurm**: 4.200 LP, Schaden ×1,3, zusätzlich **Sandsturz**. Eine Bahn von 14 × 3,2 m wird 1,1 s gezeigt, dann schießt der Wurm hindurch (`shaders/boss_lane.gdshader`).
  - Welt 3 **Aschenkröte**: 7.800 LP, Schaden ×1,6, zusätzlich **Glutregen**. Vier Landekreise (r 2,4 m), einer davon auf dem Helden, werden 1,4 s gezeigt und brechen dann aus.
  - Moorkönig in Welt 1 unverändert (1.600 LP).
- **Sieg:** Fällt der Boss von Welt 3, öffnet sich kein Portal und es fallen kein Kokon und keine Gems. Alle Gegner verschwinden, `run.win()` setzt `won` und `dead` (alles, was beim Tod anhält, hält an; der Held lebt).
  - Nach 1,8 s erscheint das Ergebnis mit „SIEG!“ (Goldband), „ALLE 3 WELTEN BEZWUNGEN“, Zeit, Kills, Level, DEIN BUILD, Schaden, MENÜ und NOCHMAL.
  - Das Ergebnis nach dem Tod zeigt jetzt „WELT n/3 · BIOM“.
  - NOCHMAL baut Welt 1 mit dem ersten Seed neu auf.
  - Der Sieg wird über `Session.record_run` gebucht (Zeit, Kills, Level).
- **HUD:** Bossleiste und Ankündigung mit dem Namen des Bosses. Das Band „EVOLUTION: <NAME>“ erscheint beim Signal `evolved` von Teil B, im Build steht dann eine EVO-Marke. Pressure-Bänder blenden beim Ergebnis aus (kein doppeltes „SIEG!“).
- **Tests:** `worlds` (Portal nach dem Boss, Randpfeil, Eintritt nach 0,60 s, Dürrschlund mit neuem Seed, Build/Level/LP/Gold bleiben, Boden leer, Weltuhr neu, ×1,6 LP/Schaden, Dichte +20 %, Tönung, Sandwurm-Bahn vor dem Treffer, Endwelle nach 60,0 s) und `victory` (Glutsumpf ×2,4, Glutregen 4 Kreise vor dem Treffer, `run_won`, kein Portal, Siegesbildschirm, NOCHMAL → Welt 1). Suite (`-SkipPlaythrough`) grün, 28/28.
- **Prüfbilder** (`tests/capture_worlds.gd`): `preview_portal`, `preview_world2`, `preview_world2_boss`, `preview_world3_boss`, `preview_victory`.
- **Offen:**
  - Eine Minimap gibt es in Horde Hunters noch nicht, daher auch keine Portal-Markierung.
  - Kein Feld `wins` im Profil (würde `profile.gd` von Teil D betreffen).
  - Der Sandwurm wirkt von oben eher wie ein Sandhaufen mit Körper. Er bewegt sich nur am Stück (keine Animation) – Handtest.
  - Die Balance der Boss-LP gegen echte Builds aus Welt 2/3 ist noch offen (Bot-Lauf).
## Umsetzung Teil D (01.10.)
**FPS-Anzeige** (`scripts/ui/fps_overlay.gd`, Schalter „FPS-ANZEIGE“, Profil `show_fps`, Standard an):
- Unten links über dem DASH-Knopf, damit sie Kopfleiste, Boss-Leiste und Banner nicht verdeckt.
- Zeigt FPS, Frame-Zeit (Mittel und Max der letzten Sekunde) und einen 2-s-Graphen mit 16,7/33-ms-Linie.
- Dazu „Skript“ (gesamte `_process`-Arbeit) gegen „Rest“ (Rendern, GPU, Warten), Draw Calls, Objekte, Gegner und Qualitätsstufe.
- Daran erkennt man auf dem S25 sofort, ob CPU (GDScript) oder GPU bremst.

**Bench** (`tests/perf_bench.gd`, `tools/perf.ps1`, Ausgabe `previews/perf_<held>.txt`):
- Echte Hauptszene, 200 Gegner, alle Waffen, Schadenszahlen an, Boss bei halber Zeit.
- Erfasst Perzentile, Spitzen mit Ereignissen, erstes Auftreten und Ablationen (`off=hud,fx,horde,world`, `hudprof=on`, `mobile=on`, `cache=clear`).

**Messung PC** (RTX 5070, 900×1600, 200 Gegner, Shader-Cache gelöscht; Werte schwanken ±15 %, weil parallel andere Godot-Läufe liefen):

| | vorher | nachher |
|---|---|---|
| Frame Ø / p95 | 12,0 / 18,4 ms | 11,6–13,7 / 17–20 ms |
| Draw Calls Ø | 276 | 252 (Brann) / 233 (Brine) |
| Brann-Meshes | ~45 | 8 |
| Boss-Spawn (erstes Mal) | 57 ms | 18–20 ms |
| Erster Kill | 30 ms | 9–14 ms |
| Erster Schuss | 52 ms | im Warm-up der ersten 0,1 s |
- `battle.tick` 5,6 ms, davon `horde.step` 3,8 ms. HUD-`_draw` ≈ 1,1 ms und ≈ 140 der 250 Draw Calls.

**Umgesetzt:**
- Brann besteht aus einem vertexgefärbten Mesh je Gelenk (`shaders/toon_merged.gdshader`); der Blitz ist ein Material-Uniform und wird nur bei Änderung geschrieben. Bei Brine gilt dasselbe für den Blitz.
- Shader-Warm-up (`scripts/world/shader_warmup.gd`):
  - Zeichnet alle Spatial-Shader (Mesh und MultiMesh), die Effekt-Batches und die Boss-/Portal-Modelle einmal verdeckt unter dem Boden.
  - Lädt diese Modelle im Hintergrund-Thread und hält sie im Speicher.
  - Versteckt erzeugte Meshes bekommen einen Zwilling.
  - Zusätzlich werden die Ziffern-Glyphen der Schadenszahlen vorab gerastert.
- Qualitätsstufen (`quality.gd`, `quality_governor.gd`):
  - Auf dem Handy wird 3D mit 80/70/60 % Auflösung gerendert, das HUD bleibt scharf. Am PC ändert sich nichts.
  - Adaptiv: Ø > 20 ms über 3 s bei einem Render-Anteil > 8 ms → eine Stufe tiefer (MSAA aus, kleinere Skala; Wanddetail und Deko ab der nächsten Welt).

**Offen, betrifft andere Teile:**
- `hud.gd`:
  - `_draw_brocken_bars` läuft jeden Frame über alle 200 Gegner (0,45 ms).
  - Schadenszahlen zeichnen je drei Textpässe.
  - Die Patronen-Pips bestehen aus 5 Rundrechtecken je Pip.
- `horde.step` (~3,8 ms PC, auf dem S25 geschätzt 6–9 ms): Gegner außerhalb des Bildes nur jeden 2. Frame steuern.
- Auf dem S25 prüfen:
  - FPS-Anzeige ablesen.
  - Wechselt „HOCH“ zu „MITTEL auto“?
  - Bleibt „Rest“ hoch, obwohl „Skript“ niedrig ist?

## Umsetzung Teil E – CPU (02.10.)
Ziel: GDScript-Zeit pro Frame senken, ohne Regeln oder Optik zu ändern. Gemessen mit `tools/perf.ps1` (PC, RTX 5070, 900×1600, 200 Gegner, je Held 2 Läufe à 20 s, Mittelwert; Rauschen ±10 %).

| | vorher Brann / Brine | nachher Brann / Brine |
|---|---|---|
| Frame Ø | 13,4 / 12,6 ms | 8,3 / 8,3 ms |
| Frame p95 / p99 | 20,6 / 24,3 ms – 19,5 / 22,0 ms | 12,8 / 14,6 ms – 12,5 / 14,8 ms |
| Skript gesamt (`_process`) | 6,6 / 6,6 ms | 4,5 / 4,7 ms |
| `battle.tick` | 6,1 / 6,1 ms | 4,0 / 4,2 ms |
| `horde.step` (davon Zeichnen) | 4,2 (0,88) / 4,0 (0,84) ms | 2,8 (0,41) / 2,7 (0,41) ms |
| Loot (`progression.step`) | 0,6 ms | 0,2 ms |
| HUD: Brocken-Leisten / Schadenszahlen | 0,73 / 0,29 ms | 0,03 / 0,13 ms |
| Draw Calls Ø | 252 / 233 | 240 / 224 |

**Umgesetzt:**
- `horde.gd`:
  - Wandkollision mit Freiraum-Cache: Bei einer Probe wird der freie Abstand zu Wänden (Distanzfeld), Steinen und Kartenrand gemessen. Solange der Gegner in diesem Kreis bleibt, entfällt `resolve_motion()` (vorher ~60 Aufrufe/Frame, jetzt ~20; Wandanteil 1,3 → 0,3 ms). Treibsand/Flachwasser bremsen nahe Gegner weiter wie bisher.
  - Gegner außerhalb des Bildes (Kamerablick + 4 m), weiter als 9 m und im Anlauf laufen jeden 2. Frame mit der gesammelten Zeit. Gleiche Bewegung, halbe Kosten; im Bench wirkt das kaum, weil dort alle 200 Gegner im Bild stehen. Weit entfernte Gegner (> 16 m) fragen das Flussfeld halb so oft ab.
  - Zeichnen in einem Durchlauf statt einem pro Art; Pose-Mathematik inline (numerisch gleich `_pose()`); Gegner außerhalb des Bildes bekommen keine Instanz; Instanzfarbe nur einmal gesetzt.
  - Der Held-lebt-Check wird einmal pro Frame statt pro Gegner gemacht. Ruhende Leichen prüfen keine Wände mehr.
  - `brocken_list` / `elite_list` für die HUD-Leisten.
- `loot.gd`: Jedes Item hat feste Slots (Glühen = id, Edelstein/Münze eigener Bereich); pro Frame werden nur bewegte Items neu geschrieben, ohne neue Arrays.
- HUD:
  - Brocken-Leisten sind gepoolte Elemente, die nur verschoben und bei geänderter LP neu gezeichnet werden. Für die Overhead-Leiste über dem Helden gilt dasselbe: Sie wird nur bei geänderter LP, Patronenzahl oder Nachladen neu gezeichnet.
  - Schadenszahlen: höchstens 24 (Handy 16), Treffer auf dieselbe Stelle innerhalb von 0,12 s werden zusammengezählt. Je Zahl ein Konturpass statt Schatten plus Kontur; der Schatten entsteht durch eine leicht nach unten versetzte Kontur.
  - `ui_kit_brawl.gd`: StyleBoxen je Farbe/Radius/Rand gecacht (vorher 5 Setter mit `changed`-Signal pro Aufruf), Verlaufspolygone von `fade_rrect` gecacht und nur verschoben.
- Getestet und verworfen: `fx_batch.gd` über einen Puffer statt `set_instance_*`. Das war langsamer (0,49 statt 0,42 ms), weil 16 GDScript-Schreibzugriffe mehr kosten als 2 native Aufrufe. Aus demselben Grund setzt `horde.gd` die Instanzen jetzt über native Aufrufe statt über den Puffer (0,47 → 0,40 ms).

**Optik:** In den Captures (`fight`, `boxer`, `pressure`, `worlds`, `progress_xpbar`) ist das Bild gleich. Die Schadenszahlen haben einen etwas schwächeren Schlagschatten. Bei mehreren Waffen auf denselben Gegner erscheint eine zusammengezählte Zahl statt mehrerer.

**Offen:**
- `horde.step` liegt im Bench bei −33 %, nicht −50 %. Der Rest verteilt sich auf Zustandslogik inkl. Flussfeld (~0,5 ms; `arena.flow_direction` kostet ~14 µs pro Aufruf), Trennung (~0,4 ms), Bewegung/Wände (~0,4 ms), Animation (~0,2 ms), Leichen (~0,15 ms) und Zeichnen (0,4 ms).
- Nächste Hebel liegen in `arena.gd` (Flussfeld-Abfrage, `_push_out` über 9 Chunks).
- `tests/capture_progress.gd` bricht beim Level-up-Bild ab (`progress._shotgun_entry` fehlt). Das war schon vorher kaputt und hat mit Teil E nichts zu tun.