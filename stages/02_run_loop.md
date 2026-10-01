# Etappe 2 – Run-Schleife

Ziel: Aus dem Kampf-Prototyp wird ein vollständiger Run mit Wachstum, Entscheidungen, Höhepunkten und Ende. Grundlage: `DESIGN_BRIEF.md`, Etappe 1 (`stages/01_feel_prototype.md`). Entscheidungen hat der Nutzer an den Orchestrator übergeben (01.10.2026).

## Entscheidungen (Orchestrator)
- **Brann bleibt der Starter.** Der Boxer (Branding, App-Icon) wird der erste Nahkampf-Held (Etappe 3).
- **Weglaufen soll nicht risikolos sein, aber Ausweichen bleibt die Kernfähigkeit:**
  - Rudel kommen öfter **von mehreren Seiten**.
  - Ab 2:00 gibt es **Einkesselungen**: Ein angekündigter Ring schließt sich, eine Lücke bleibt.
  - Renner sind schneller als Brann (5,5 m/s gegenüber 4,8), aber zerbrechlich.
  - XP-Gems, Kokons und Elite ziehen den Spieler in die Horde.

## Teil A – Fortschritt (XP, Level, Gold, Kokons, Ergebnis)
1. **XP-Gems:**
   - Getötete Gegner lassen Gems fallen (klein, mittel, groß nach Gegnertyp).
   - Magnet-Radius 2,5 m, Gems fliegen heran.
   - Gems bleiben liegen, bis sie eingesammelt werden.
   - Technik aus Mawlings `loot.gd` (Kristalle, MultiMesh, Bündelung).
2. **Level-up 1 aus 3** (Wahlbildschirm aus Mawlings `mutation_screen.gd`, Brawl-Stil, Seltenheitsfarben):
   - Levelkurve wie Mawlings (60 + 25 L + 6 L²), XP-Leiste oben.
   - **Werte** (Slots 6, je 5 Ränge): Schaden, Feuerrate/Nachladetempo, Reichweite, Tempo, Max-LP, Regeneration, Rüstung, Sammelradius, Krit-Chance, XP-Bonus, Glück.
   - **Shotgun-Upgrades** (eigene Spur, 5 Ränge): +1 Kugel, Durchschlag (Kugeln treffen 1 weiteren Gegner), stärkerer Rückstoß, +1 Schuss im Magazin, engerer Fächer mit mehr Reichweite.
   - Neu würfeln: 1 je Run.
3. **Gold** fällt von Elite, Kokon-Wächtern und selten von normalen Gegnern. **Karten-Kokons** (Kosten in Gold, 1 aus 3: Relikte und Werte; Logik aus Mawlings `chests.gd`/`arsenal.gd`, Relikt-Liste auf Held umgestellt, 8–10 Relikte für den Anfang).
4. **Tod → Ergebnis** mit Zeit, Kills, Level, gewählten Upgrades und Schaden je Quelle (Mawlings „DEIN BUILD“ als Vorlage). Dazu NOCHMAL.
5. Tests: XP und Level, Wahl und Wirkung, Slots, Kokon-Kauf, Ergebnis.

## Teil B – Druck (Elite, Wellen, Boss)
1. **Rudel von mehreren Seiten:** Der Direktor verteilt Rudel auf 2–4 Richtungen; Renner und Wichtel sind ab 0:40 gemischt.
2. **Wellen:** alle 45–60 s eine angekündigte Welle („WELLE!“, Richtungspfeil am Rand). Ab 2:00 kommt jede zweite als **Einkesselung**: ein Ring aus Wichteln mit einer hell markierten Lücke, der sich langsam schließt.
3. **Elite:** ab 1:30 alle ~75 s ein **Champion-Brocken** (größer, goldener Schimmer, doppelte LP, Stampf-Ring angekündigt). Er lässt einen **Gratis-Kokon** und Gold fallen.
4. **Erster Boss bei 4:00:** **Moorkönig** (Vorlage Mawlings `bog_king.gd`, Ziel = Held). Angriffe:
   - Stampf-Ring
   - Sprung auf die Heldenposition (Landezone angekündigt)
   - Rundumschlag (Bogen)

   Alle Angriffe sind magenta angekündigt. Bosse sind immun gegen Rückstoß. Die Bossleiste nutzt das Mawlings-HUD. Der Sieg gibt einen Boss-Kokon (1 aus 3, mindestens episch) und eine kurze Atempause.
5. **Endwelle** ab 6:00: exponentiell wachsende Rudel wie die Flut in Mawlings. Nur der Tod beendet den Run.
6. Tests: Rudelrichtungen, Wellen- und Einkesselungs-Ankündigung, Elite-Drop, Boss-Muster (Ankündigung vor Schaden, Rückstoß-Immunität), Endwelle.

## Schnittstellen
- `run.gd`: `xp`, `level`, `gold`, Signale `leveled_up`, `died`.
- `stats` des Helden: `hero.stat(id) -> float`, Multiplikatoren, die die Shotgun liest (`damage_mult`, `fire_rate_mult`, `range_mult`, `pellets_bonus`, `pierce`, `knockback_mult`, `mag_bonus`).
- Drops: `Battle.drop_xp(at, amount)`, `drop_gold(at, amount)`, `drop_chest(at, kind)`.
- Teil A besitzt `scripts/progression/*`, `scripts/ui/*` (Wahl, Ergebnis, XP-Leiste), `run.gd`.
- Teil B besitzt `scripts/enemies/*` (Direktor, Wellen, Elite, Boss) und neue Telegraph-Shader.
- `battle.gd` ändern beide nur mit kleinen, lokalen Einträgen.
- **Stand Teil A (Drops, ab sofort aufrufbar):** `battle.drop_xp(at: Vector3, amount: float)`, `battle.drop_gold(at: Vector3, amount: int)`, `battle.drop_chest(at: Vector3, kind := "free")` mit `kind` = `"free"` (Elite-Gratis-Kokon, mind. selten), `"boss"` (mind. episch), `"map"` (kostet Gold). Gegner-Tode geben XP automatisch über `horde.enemy_killed` (Teil A hört darauf); Teil B ruft nur für Elite/Boss zusätzlich `drop_chest`/`drop_gold`. Solange der Run pausiert (Level-up-/Kokon-Wahl), ruft `battle.tick` Gegner und Direktor nicht auf (`battle.paused()`). Lange Tests/Bots: `battle.progression.auto_pick = true` (jede Wahl nimmt sofort die erste Karte) oder `if battle.paused(): battle.progression.choose(0)`. XP je Tod: Wichtel/Renner 4, Brocken 20, unbekannte Arten (Elite/Boss) 15 – über `progression.XP_BY_KIND`.

## Abnahme
- Suite grün.
- Prüfbilder: Level-up-Wahl, Kokon, Welle mit Pfeil, Einkesselung mit Lücke, Elite, Boss-Angriffe, Ergebnis.
- Ein 6-Minuten-Bot-Lauf (der einfache Bot aus Etappe 1, erweitert: nimmt Gems mit, wählt Upgrades) stirbt nicht vor 3:00 und überlebt nicht endlos. Danach folgt der **Handtest** durch den Nutzer.

## Umsetzung Teil A – Fortschritt (Stand 01.10.)
Dateien: `scripts/progression/` (`progress.gd` Build: Werte/Shotgun-Spur/Relikte, Seltenheit, Angebote, Preis; `loot.gd` XP-Gems und Gold-Münzen mit Magnet, MultiMesh; `chests.gd` Kokons in der Welt; `progression.gd` verdrahtet alles), `scripts/ui/` (`choice_screen.gd` 1-aus-3-Wahl, `icons.gd` Vektor-Icons, `hud.gd` XP-Leiste/Level/Gold, Preis-Pillen, Ergebnis „DEIN BUILD“), `scripts/core/run.gd` (XP, Level, Gold, Schaden je Quelle). Kleine Einträge in `battle.gd` (Progression anlegen, `paused()`, `progression.step`, Reset, Drop-API), `hero.gd` (`build`, `stat(id)`, Tempo, Regeneration, Rüstung, Dash-Abklingzeit), `shotgun.gd` (liest alle Multiplikatoren, Durchschlag), `touch_controls.gd` (`blocked` während der Wahl).

**Zahlen** (frei gewählt, für den Handtest offen):
- Levelkurve 60 + 25 L + 6 L² (L = bisherige Level-ups; erstes Level-up 60 XP). Gems: Wichtel/Renner 4 XP (klein, blau), Brocken 20 (groß, violett), Stufen < 5 / < 14 / größer. Magnet 2,5 m, Gems bleiben liegen; über 240 liegenden Gems wird gebündelt.
- Werte (6 Plätze, 5 Ränge, Wirkung = Basis × Summe der Seltenheitsfaktoren 1 / 1,25 / 1,5 / 2 / 3): Schaden 8 %, Feuerrate 7 % (Schussabstand und Nachladen), Reichweite 6 %, Tempo 5 %, Max-LP +15, Regeneration 0,4 LP/s, Rüstung 6 % (max. 60 %), Sammelradius 20 %, Krit-Chance 5 % (doppelter Kugelschaden), XP-Bonus 8 %, Glück +1 (+10 % relativ auf die höheren Stufen, Kokon −3 %).
- Shotgun-Spur in fester Reihenfolge: +1 Kugel → Durchschlag (1 weiterer Gegner je Kugel) → Rückstoß ×1,5 → +1 Schuss → Fächer ×0,7 und Reichweite +25 %. Seltenheit = Rang-Sprung (episch +2, legendär +3). Die Spur liegt in jeder zweiten Level-up-Wahl.
- Neu würfeln: 1 je Run (Level-up und Kokon).
- Gold: Wichtel/Renner 6 % (1), Brocken 60 % (3), Elite/Boss über `drop_gold`. Karten-Kokons auf `arena.poi_slots("cocoon")`, Preis 20 × 1,6ⁿ Gold, mind. ungewöhnlich; Elite-Kokon gratis, mind. selten; Boss-Kokon gratis, mind. episch. Öffnen: 0,5 s im Ring stehen; zu wenig Gold → Ring grau, Preis-Pille rot, raus und wieder rein.
- Relikte (Kokon, 6 Plätze, Stapel): Pulverhorn (Nachladen +15 %, gewöhnlich), Feldflasche (+0,5 LP/s), Lockstein (+40 % Sammelradius), Dornenweste (Angreifer erleidet 20, ungewöhnlich), Glücksmünze (+50 % Gold, +1 Glück), Siebenmeilenstiefel (Dash −20 % Abklingzeit, selten), Jagdtrophäe (jeder 25. Kill heilt 8), Bleihagel (+2 Kugeln, episch, 2×), Patronengurt (+1 Schuss, episch, 2×), Ahnenamulett (+25 % Schaden, +25 Max-LP, legendär, 1×).
- Ergebnis: Zeit, Kills, Level, DEIN BUILD (Werte mit Rang, Shotgun-Rang, Relikte, Rahmen in bester Seltenheit), Schaden je Quelle (Schrotflinte, Dornenweste …), NOCHMAL unter dem Panel.

**Tests** (`tools/test.ps1`): `xp_level`, `upgrades`, `chests`, `result`. Prüfbilder: `tests/capture_progress.gd` → `previews/preview_progress_xpbar|levelup|cocoon|result.png`. Bot: `tests/balance_probe.gd -- kite` sammelt Gems und nimmt die erste Karte (Lauf 01.10.: Level 2/3/4 bei 0:35/0:57/1:26).
- Offen: eigene Sounds für Pickup, Level-up und Kokon (derzeit `ui`/`slam`), Randpfeil zum nächsten Kokon.