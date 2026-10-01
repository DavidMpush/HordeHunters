# Etappe 3 – Menü und Pause, Nahkampf, zweiter Held (Boxer)

Quelle: Nutzer 01.10.2026 („mach gerne weiter, auch mal mit Pause und Menü“). Entscheidungen trifft der Orchestrator.

## Teil A – Menü, Pause, Profil
1. **Startszene `scenes/menu.tscn`** (wird `run/main_scene`):
   - **Titel:** Logo aus `Konzepte und Ideen/Branding/horde-hunters-logo.png` (als Kopie unter `assets/branding/`, verkleinert auf ~900 px Breite). Dahinter eine ruhige, bewegte Szene (Held auf der Karte, langsam schwenkende Kamera) oder die Key Art als Hintergrund, abgedunkelt.
   - **SPIELEN** (großer Brawl-Knopf), darüber die **Heldenkarte** (aktueller Held mit Porträt, Name, Waffe, Kurztext). Antippen öffnet die Heldenwahl.
   - **Heldenwahl:** Brann (frei) und Boxer, vorerst frei, die Freischaltung kommt später. Weitere Helden als Silhouetten mit „BALD“.
   - **Einstellungen:** Lautstärke (Gesamt, Musik, Effekte), Vibration an/aus, Schadenszahlen an/aus.
   - **Statistik:** bester Run je Held (Zeit, Kills, Level), Runs gesamt.
2. **Pause im Run:**
   - Knopf oben rechts (Brawl-Stil), Esc/P, automatisch bei Fokusverlust.
   - Pause-Overlay: WEITER, NEUSTART, MENÜ, Lautstärke-Regler und eine Übersicht des aktuellen Builds (Upgrades und Relikte als Icons).
3. **Ergebnis** bekommt zusätzlich einen Knopf MENÜ.
4. **Profil** `user://profile.json`: gewählter Held, Einstellungen, Bestwerte. Robuste Ladefunktion (kaputte Datei → Standardwerte).
5. **Run-Konfiguration:** Das Menü übergibt `hero_id` an `main.tscn`; der Run baut den passenden Helden und seine Startwaffe.
6. Optik: UI-Kit `brawl`, Farbwelt aus dem Logo (Creme, Gold, Orange, Dunkelblau mit Türkis-Akzent).
7. Tests: Menü lädt, SPIELEN startet einen Run mit dem gewählten Helden, Pause friert alles ein (Gegner, Waffen, Zeit), WEITER, NEUSTART, MENÜ, Profil speichern/laden/kaputt.

## Teil B – Waffensystem, Nahkampf, Boxer
1. **Waffen-Grundlage** `scripts/weapons/weapon.gd`: gemeinsame Basis (Abklingzeit, Zielwahl, Schaden über `hero.stat`, Upgrade-Rang 0–5, Schadensquelle für die Auswertung). Die Shotgun wird darauf umgestellt, ohne ihr Verhalten zu ändern.
2. **Bis zu 4 Waffen gleichzeitig.** Neue Waffen kommen als Level-up-Karte „NEUE WAFFE“, solange Plätze frei sind; danach nur Rang-ups vorhandener Waffen. So steht es schon im Slot-System.
3. **Boxer** (`hero_id = "boxer"`, Name offen; Arbeitsname **„Rocco“**):
   - **Look:** Platzhalter aus Grundformen nach V5-Konzept (`Konzepte und Ideen/Charakterkonzepte/V5_Combat_Archetypes/01_unarmed_boxer.png`): breiter Körper, rote ärmellose Kapuzenjacke, grüne Shorts, große bandagierte Fäuste, graue Strähne.
   - **Startwaffe Fäuste (Nahkampf):**
     - Auto-Ziel auf den nächsten Gegner in 2,2 m; der Boxer dreht sich zum Ziel.
     - **3er-Kombo:** links, rechts, Aufwärtshaken. Schläge 1 und 2 treffen in einem kurzen Bogen (±50°), der Haken in einem größeren Bogen mit **starkem Rückstoß** (auch mittlere Gegner, Bosse nicht) und Mini-Kamera-Ruck.
     - Hoher Einzelschaden, kurze Reichweite: Er muss nah ran. Dafür bekommt er mehr LP (130) und 10 % Rüstung.
     - Feedback: Schlagbögen als weiße Wisch-Effekte, Treffer-Stopp (2–3 Frames Hitstop beim Haken), Staubwolke.
   - **Fäuste-Spur** im Level-up (5 Ränge): größerer Bogen, schnellere Kombo, Haken mit Schockwelle, Lebensraub pro Schlag, vierter Schlag.
   - **Dash** wie Brann. Später bekommt der Boxer eine eigene Signatur.
4. **Erste Zusatzwaffen** (für beide Helden über Level-up):
   - **Wurfaxt:** Fernkampf im Bogen, durchschlägt, kommt zurück.
   - **Schwert-Wirbel:** Nahkampf, Rundumhieb alle 2,5 s mit Rückstoß.
   - **Granate:** Wurf auf eine Gegnergruppe, Explosion mit Fläche und Rückstoß.

   Je 5 Ränge, Seltenheit wie bei den Werten.
5. Tests:
   - Basis (Shotgun unverändert)
   - Fäuste: Kombo-Zyklus, Bogen, Rückstoß nach Masse, Hitstop
   - neue Waffen erscheinen nur bei freien Plätzen
   - jede Zusatzwaffe trifft und skaliert mit dem Rang
   - Boxer-Run startet

   Prüfbilder: Boxer-Kombo mit Haken, die drei Zusatzwaffen, die Heldenwahl.

## Schnittstellen
- **Run-Konfiguration:** `main.gd` liest `Session.config` (Autoload oder statische Klasse `scripts/core/session.gd`) mit `hero_id`, `seed`, `biome`; ohne Konfiguration gilt Brann.
- **Heldenkatalog:** `scripts/hero/heroes.gd` mit `HEROES := {id: {name, title, weapon, hp, armor, model_script, portrait}}`. Teil B füllt ihn, Teil A liest ihn für Menü und Heldenwahl.
- **Pause:** `battle.set_paused(bool)` friert alles ein. Die Level-up-Wahl nutzt denselben Mechanismus.
- **Dateibesitz:**
  - Teil A: `scenes/menu.tscn`, `scripts/menu/*`, `scripts/core/session.gd`, `scripts/core/profile.gd`, Pause und Ergebnis in `scripts/ui/*`.
  - Teil B: `scripts/weapons/*`, `scripts/hero/*`, `scripts/progression/progress.gd` (neue Karten).
  - `battle.gd` und `main.gd` ändern beide nur mit kleinen, lokalen Einträgen.

## Umsetzung Teil A – Menü, Pause, Profil (Stand 01.10.)
- **Menü** `scenes/menu.tscn` (jetzt `run/main_scene`), `scripts/menu/`: `menu.gd` (Titel: Key Art als abgedunkelter, langsam schwenkender Hintergrund, Logo, Heldenkarte, SPIELEN, STATISTIK, EINSTELLUNGEN), `hero_select.gd` (Brann, Rocco, vier „BALD“-Silhouetten; Antippen wählt sofort), `settings_sheet.gd`, `stats_sheet.gd`, `hero_catalog.gd` (liest `heroes.gd` defensiv, Porträts, Silhouette), `menu_parts.gd` (Ribbon, Schalter, Glyphen). Tasten: Enter = SPIELEN, H = Helden, Esc = zurück.
- **Bilder:** `assets/branding/logo_900.png`, `key_art_1200.png` (verkleinerte Kopien), Porträts `assets/heroes/portrait_brann.png` (V2-Roster-Ausschnitt), `portrait_boxer.png` (Boxer-App-Icon-Ausschnitt).
- **Session** `scripts/core/session.gd` (statische Klasse, kein Autoload): `config = {hero_id, seed, biome}`, SPIELEN setzt sie mit Zufalls-Seed; `main.gd` liest Seed/Biom, `heroes.current_id()` den Helden. Profil lazy, Tests/Captures (eigener SceneTree) bekommen ein Profil im Speicher und schreiben nie in die echte Datei.
- **Profil** `scripts/core/profile.gd` → `user://profile.json`: Held, Einstellungen, Bestwerte je Held, Runs gesamt; kaputte Datei/falsche Typen → Standardwerte je Feld. Ein Run zählt beim Tod (`battle.run_ended`).
- **Audio:** `default_bus_layout.tres` mit Music und SFX; `scripts/core/audio_settings.gd` (Hörkurve wie Mawlings); `sfx.gd` spielt auf SFX. Schadenszahlen-Schalter wirkt in `hud.add_damage`, Vibration (nur Handy) bei Treffern am Helden.
- **Pause** `scripts/ui/pause_screen.gd` (von `main.gd` in den HUD-Layer gehängt): Knopf oben rechts (Kill-Zähler rückt nach links), Esc/P, Fokusverlust; PAUSE mit Zeit/Kills/Level, aktuellem Build als Icons, drei Lautstärke-Reglern (`scripts/ui/volume_sliders.gd`, auch im Menü), WEITER, NEUSTART, MENÜ. `battle.set_paused(bool)`/`user_paused`, `battle.paused()` = Pause oder Wahl offen; `restart()` hebt die Pause auf.
- **Ergebnis:** MENÜ links neben NOCHMAL (`hud.result_menu_rect()`, `controls.menu_requested`, Taste M/Esc).
- **Tests:** `profile`, `menu`, `pause`. Prüfbilder: `tests/capture_menu.gd` → `previews/preview_menu_title|title_boxer|heroes|settings|stats|hud|pause|result.png` (`-- menu` nur Menü).

## Umsetzung Teil B – Waffensystem, Nahkampf, Boxer (Stand 01.10.)
- **Waffen-Basis** `scripts/weapons/weapon.gd`: `id`/`source` (Schadensquelle fürs Ergebnis), Abklingzeit über `fire_rate_mult`, `rank()`/`power()` aus dem Build (`weapon_rank`, `weapon_power`; `rank_override` für Tests), Schaden × `damage_mult` + Krit, Abfragen `enemies_in_arc`/`enemies_in_circle` (Boss eingeschlossen), `knock_by_mass(index, [leicht, mittel, schwer])` (Champion = schwer, Boss immer 0), `apply(hits)` bucht auf `source`, Signal `hitstop_requested(frames)`. Die Shotgun erbt davon, Verhalten unverändert (`shotgun`-Test grün).
- **Bis zu 4 Waffen** (`progress.gd`): `start_weapon` (Shotgun/Fäuste, Spur 0–5, Seltenheit = Rang-Sprung wie bisher) + Zusatzwaffen `axe`/`sword`/`grenade` als Karte **NEUE WAFFE** (`type "new_weapon"`, Rang 0 → 1), solange ein Platz frei ist; danach nur Rang-ups (`type "weapon"`, Rang +1, Kraft + Seltenheitsfaktor wie bei Werten, Schaden × (0,75 + 0,25 × Kraft)). Level-up: 50 % eigene Spur, 45 % Zusatzwaffe, Rest Werte. `battle.gd` hält `weapons` (eigene zuerst, `battle.shotgun` = eigene Waffe), gleicht sie mit `progress.weapons` ab (`sync_weapons()`), NOCHMAL wirft Zusatzwaffen ab; `battle.set_hero(id)`; Hitstop in `tick()` (`hitstop_frames`).
- **Heldenkatalog** `scripts/hero/heroes.gd` (`HEROES`, `ORDER`, `get_hero`, `current_id()` liest `Session.config.hero_id` dynamisch, Fallback Brann). `hero.gd`: `apply_hero(id)` setzt LP, Grund-Rüstung (`armor()` = Grund + Build, max. 70 %), Tempo und Modell; `progression.gd` nimmt `hero.base_health`.
- **Rocco** (`boxer_model.gd`, 80 Teile, V5-Look): rote ärmellose Kapuzenjacke über schwarzem Tanktop, grüne Shorts mit Cremekante, schwarz-creme Stiefel, große bandagierte Fäuste, Bart, Pflaster, graue Strähne. Animation: Laufen, Boxer-Wippen mit Deckung, Ausholen (`wind_punch`), Jab/Cross mit Rumpfdrehung, Aufwärtshaken (tief, dann hoch, Körper hebt sich), Hammerfaust, Dash, Treffer-Blitz, Umfallen. 130 LP, 10 % Rüstung, **4,4 m/s** (frei: schwerer als Brann, Balance).
- **Fäuste** (`fists.gd`): Ziel = nächster Gegner mit Körperrand ≤ 2,2 m; Kombo Jab → Cross → Haken (Ausholen 0,07 s, Abstände 0,24/0,28 s, Erholung 0,9 s; Zyklus ≈ 1,6 s). Jab/Cross 10 Schaden, ±50°, treffen nur die **2 nächsten** Körper, leichter Rückstoß 0,8; Haken 18 Schaden, ±75°, 15 % weiter, alle im Bogen, Rückstoß leicht 7 / mittel 4 / schwer 1 / Boss 0, Kamera-Ruck, **3 Frames Hitstop** nur bei Treffer. Weiße/goldene Wisch-Sicheln (`shaders/swipe.gdshader`, `weapon_fx.gd`), Funken, weißer Aufprall-Puff, Staub. Spur: Weiter Bogen (±65/±100, +1 Ziel) → Schnelle Kombo (+25 %) → Schockwelle (2,9 m, 10 Schaden) → Lebensraub (1,5 LP je Treffer-Schlag) → Hammerfaust (4. Schlag rundum, 18).
- **Zusatzwaffen** (je 5 Ränge): **Wurfaxt** (`throwing_axe.gd`) alle 1,8 s auf das nächste Ziel ≤ 9 m, Schleife 6,5 m hinaus und zurück, durchschlägt (ein Treffer je Gegner und Durchgang), 14 Schaden, Drehscheibe als Bewegungsunschärfe; R2 weiter, R3 2 Äxte, R4 schneller, R5 3 Äxte. **Schwert-Wirbel** (`sword_whirl.gd`) alle 2,5 s, sobald ein Gegner im Kreis ist: 2,7 m rundum, 18 Schaden, Rückstoß 7/3/0, kreisende Klinge + blaue Vollkreis-Sichel; R2/R4 schneller, R3 Radius +25 %, R5 Doppelwirbel. **Granate** (`grenade.gd`) alle 3,2 s auf die dichteste Gruppe ≤ 9 m, 0,6 s Flug mit gelbem Landering (bewusst nicht magenta), Explosion 2,6 m, 30 Schaden (Rand 60 %), Rückstoß 8/4/0, Feuerball, Ringe, Rauch, Brandfleck; R2/R4 schneller, R3 Radius +25 %, R5 zwei Granaten. Schaden je Quelle: „Schrotflinte“, „Fäuste“, „Wurfaxt“, „Schwert-Wirbel“, „Granate“. Icons `fists/axe/sword/grenade` in `icons.gd`, Karte „NEUE WAFFE“ in `choice_screen.gd`.
- **Tests:** `weapon_base`, `fists`, `new_weapons`, `boxer_run`. Prüfbilder: `tests/capture_boxer.gd` (`preview_heroes_lineup`, `preview_boxer_poses`, `preview_boxer_jab|uppercut|after|close`), `tests/capture_weapons.gd` (`preview_weapon_axe|sword|grenade_fly|grenade_boom|choice`). Hinweis: Toon-Teile nutzen Instanz-Uniforms (GLES3-Puffer reicht für ca. 330 Teile gleichzeitig) – keine Menge von Heldenmodellen in einer Szene.
- **Balance** (`tests/balance_probe.gd -- smart hero=boxer|brann seed=N`, Seeds 1–12): Brann im Mittel 188 s (Median 150), 170 Kills, Level 2,3. Rocco 229 s (Median 209, **+22 %** im Mittel), 268 Kills, Level 4,8. Die Überlebenszeit hängt beim Bot vor allem an Ereignissen (Einkesselung ~2:30, Boss 4:00) und kaum an LP (115 statt 130 LP änderten fast nichts); Rocco hat mehr Kills/Level, weil Gems direkt vor seinen Füßen fallen. Für den Handtest offen.
