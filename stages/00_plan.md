# Horde Hunters – Gesamtplan

Entscheidungen des Nutzers (01.10.2026): neues Projekt und neues Repo; Auto-Aim auf den nächsten Gegner; erster Held **Brann** (V2-Roster) mit Shotgun; erst Platzhalter-Figur, echte Modelle parallel.

## Projektaufbau
- Ordner `C:\Users\vrxby\Documents\Codex\Godot\HordeHunters`, Godot 4.7.2, GL Compatibility, Hochformat 900 × 1600 (wie Mawlings), eigenes Git-Repo, später GitHub `DavidMpush/HordeHunters`.
- Saubere Struktur statt eines Gott-Objekts:
  - `scripts/core/run.gd`: Run-Zustand, Zeit, Druck, Tod
  - `scripts/hero/`: Held, Steuerung, LP, Dash, Animation
  - `scripts/weapons/`: Waffen-Basis, Projektile, Nahkampf-Bögen, Nachladen
  - `scripts/enemies/`: Massen-Gegner (MultiMesh), Elite, Bosse, Direktor
  - `scripts/combat/`: Treffer, Rückstoß, Schaden, Effekte
  - `scripts/world/`: Karte aus Mawlings (Arena, Layout, Wände, Wasser, Boden)
  - `scripts/progression/`: aus Mawlings (Werte, Arsenal, Seltenheit, Kokons)
  - `scripts/ui/`: UI-Kit und HUD aus Mawlings, angepasst
  - `tests/`: Testlauf-Skripte und Captures wie in Mawlings
- Werkzeuge aus Mawlings übernehmen (`tools/test.ps1`, `capture.ps1`, `perf.ps1`, Hook für GDScript-Parse-Check).

## Etappe 1 – Spielgefühl-Prototyp (zuerst, bis es Spaß macht)
1. Projekt-Skelett, Kamera wie Mawlings (schräg von oben), eine Verdant-Karte aus dem Mawlings-Generator (Wände, Wasser, Boden), Minimap optional.
2. **Held Brann als Platzhalter:** stimmige vereinfachte Figur aus Grundformen im V2-Look (Körper, Kopf mit Bart, Schürze, Flinte als eigenes Teil). Prozedurale Animation: Laufen (Wippen, Beine), Schuss-Rückstoß, Nachlade-Pose. LP-Leiste, Treffer-Blitz, kurze Unverwundbarkeit.
3. **Steuerung:** schwebender Joystick rechts (aus Mawlings), Dash-Knopf links (kurzer Sprint mit Unverwundbarkeit, Abklingzeit).
4. **Shotgun:**
   - Auto-Aim auf den nächsten Gegner in Reichweite.
   - 2 Schuss, dann Nachladen ~0,7 s.
   - Fächer aus 7 Kugeln (sichtbare Leuchtspuren), Schaden fällt mit der Entfernung ab, Rückstoß nach Masse.
   - Mündungsfeuer, Hülsen, Kamera-Ruck, Treffer-Funken, Schadenszahlen.
5. **Gegner (Nahkampf):**
   - **Wichtel:** viele, leicht, starker Rückstoß.
   - **Renner:** schnell, wenig LP.
   - **Brocken:** zäh, kaum Rückstoß, großer angekündigter Hieb.
   - Annähern → in Reichweite kurz ausholen (Ankündigung am Gegner) → Treffer, wenn der Held noch in Reichweite ist. Abstand halten über Trennungskräfte, MultiMesh für Masse.
6. **Direktor:** steigende Dichte über 3–5 Minuten, Spawns außerhalb des Bildes.
7. Tod → einfacher Ergebnisbildschirm → Neustart.
8. **Abnahme:**
   - Tests: Bewegung, Dash, Nachladen, Rückstoß nach Masse, Ausholen/Treffer, Direktor.
   - Prüfbilder aus der Spielkamera.
   - Kurzes Video oder GIF vom Kampf.
   - **Handtest durch den Nutzer** (PC, dann S25).

## Etappe 2 – Run-Schleife
XP-Gems (Kristalle und Magnet aus Mawlings), Level-up 1 aus 3 (Werte und Waffen), Slots (4 Waffen / 6 Werte / 6 Relikte), Gold, Kokons (1 aus 3), Elite mit Kokon, erster Boss (Vorlage Bog King, Nahkampf-Muster mit Ankündigung), Wellen und Endwelle, Ergebnis mit „DEIN BUILD“.

## Etappe 3 – Nahkampfwaffen und Builds
Schwert/Axt (Bogenhieb auf kurze Distanz), zweite Fernwaffe (Pistolen oder Bogen), Evolutionen (Waffe + Relikt), Seltenheiten, Arkana und Limit Break aus Mawlings.

## Etappe 4 – Welten und Meta
Weltenreise (Portal nach dem Endboss: Verdant → Wüste → Glutsumpf), Endbosse aus Mawlings umgebaut, Menü/Profil/Freischaltungen (Helden über Welten oder Aufgaben), Siegel, Statistik, Tages-Run, Balance-Bot für den Helden.

## Etappe 5 – weitere Helden
Zweiter und dritter Held aus dem V2-Roster (z. B. Rook mit Großschwert, Vexa mit Pistolen) mit eigener Startwaffe und Signatur.

## Parallel: Kunst-Pipeline (Nutzer)
- **Modell Brann:** aus dem V2-Konzept ein 3D-Modell erzeugen (z. B. Hunyuan3D wie bei den Mawlings-Kreaturen). Möglichst A-/T-Pose, Waffe als eigenes Teil.
- **Rig und Animationen:** z. B. über Mixamo: Idle, Laufen, Schießen, Nachladen, Ausweichen, Treffer, Tod. Export als GLB/FBX.
- **Gegner-Modelle:** zunächst aus Mawlings (Moorbrut, Jäger, Skitter …) als Platzhalter-Horden; später eigene Gegner im V2-Stil.
- Der Prototyp funktioniert vollständig ohne diese Modelle; sie werden eingesetzt, sobald sie da sind.

## Was aus Mawlings übernommen wird (Prüfliste für Etappe 1–2)

| Modul | Mawlings-Datei(en) | Anpassung |
|---|---|---|
| Karte | `arena.gd`, `map_explore.gd`, `map_layout.gd`, `arena_border.gd`, `wall_mesh.gd`, `flow_field.gd`, `region_names.gd`, `biomes.gd` + Shader (`water`, `wall`, `verdant_ground`, `ground_field`, `ember_ground`, `desert_ground`, `prop_fade`, `lava`) | Wände und Boden vom WIP-Branch `wip/etappe-34-37` (Etappe 34) nehmen; Schwarm-Bezüge entfernen |
| UI | `ui_style.gd`, `ui_kit_brawl.gd`, `ui_layer.gd`, `ui_frames.gd`, `ui_icons.gd`, `hud_damage.gd`, Teile von `hud_top.gd`, `hud_minimap.gd`, `map_fog.gdshader`, `touch_controls.gd` (Joystick) | HUD für Helden-LP, XP, Gold, Zeit |
| Progression | `progression/stats.gd`, `arsenal.gd`, `cores.gd`, `evolution.gd`, `mutation_screen.gd`, `chests.gd`, `loot.gd` | Werte auf Helden umstellen, Waffenliste neu |
| Gegner-Technik | `horde.gd` (MultiMesh, Trennung, Flow-Field) | Nahkampf-Ausholen, Rückstoß nach Masse |
| Bosse | `bog_king.gd`, `apex_*.gd`, `telegraph_style.gd`, `attack_forms.gd` (Teile) | Ziel = Held statt Schwarm |
| Audio | `sfx.gd`, `music.gd`, `audio_settings.gd`, Assets | Shotgun-Sounds neu |
| Meta | `meta/profile.gd`, `chronicle.gd`, `codex.gd`, Menü | später (Etappe 4) |
| Werkzeuge | `tools/*.ps1`, `tools/hooks/check_gdscript.js`, `.claude/agents/*` | Pfade anpassen |
