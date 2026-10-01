# Horde Hunters – Design-Brief (Arbeitstitel)

Stand 01.10.2026. Bestätigte Richtung nach dem Wechsel weg von Mawlings (Schwarm). Mawlings bleibt als Archiv unter `Codex\Godot\Mawlings` und auf GitHub (`DavidMpush/Mawlings`).

## Kern
- **Ein Held gegen Horden.** Mobile-Survivor im Hochformat (Vampire Survivors / Survivor.io), schöner verpackt: Supercell-naher, stark vereinfachter 3D-Stil (V2-Roster unter `Codex\Swarm\Design\Human_Hero_Pivot_2026-10-01\V2_Stylized_Heroes`), farbige Fantasy-Welten aus Mawlings.
- **Steuerung:** schwebender Joystick rechts (bewegen); Ausweichen (Dash) als Knopf links. **Waffen zielen automatisch** auf den nächsten Gegner.
- **Gegner greifen primär im Nahkampf an:** Sie laufen heran, holen in Schlagreichweite sichtbar aus (kurze Ankündigung) und schlagen zu. Weglaufen und Ausweichen im richtigen Moment lohnen sich. Fernkämpfer und Flächenangriffe kommen erst später und sparsam, immer angekündigt.
- **Waffen:** Schusswaffen (Shotgun, Pistolen, Gewehr, Bogen …) und Nahkampfwaffen (Schwert, Axt, Speer …) mit kurzer Reichweite. Gemischte Builds sind erwünscht.
- **Rückstoß nach Masse:** Leichte Gegner werden zurückgestoßen, mittlere wenig, Bosse gar nicht. Rückstoß ist Verteidigung.
- **Nur der Tod beendet den Run.** Der Druck steigt über die Zeit; Wellen, Elite, Bosse; nach dem Endboss einer Welt führt ein Portal in die nächste Welt (aus Mawlings übernommen).

## Erster Held: Brann (Shotgun, Graves-Fantasie)
- **Schrotflinte, 2 Schuss, dann kurzes Nachladen** (~0,7 s, gut lesbar: Lauf kippt auf, Hülsen fliegen, Patronen rein, Lauf schnappt zu).
- **Fächer aus 6–8 Kugeln**, hoher Schaden aus der Nähe, Abfall mit der Entfernung; kurze Reichweite (~7–8 m).
- **Rückstoß** auf leichte Gegner, eigenes kleines Rückstoß-Feedback am Helden (Kamera-Ruck, Mündungsfeuer).
- **Signatur (später):** z. B. „Rauchgranate“ (Ausweichen durch eine Rauchwolke, Gegner verlieren das Ziel) – erst nach dem Prototyp entscheiden.

## Übernahme aus Mawlings (gezielt kopieren und anpassen)
Siehe `stages/00_plan.md` – Kartengenerator, Wände/Wasser/Boden-Shader, Minimap, UI-Kit „brawl“, HUD-Bausteine, Schadenszahlen, Level-up/Seltenheit/Slots/Kokons/Evolutionen/Siegel/Arkana, Beute und Magnet (als XP-Gems), Bosse als Vorlage, Sound und Musik, Profil/Meta, Test- und Capture-Werkzeuge, Balance-Bot als Vorlage.

## Begriffe (Genre-Sprache)
XP, Level-up, Gold, Welle, Endwelle, Portal/Nächste Welt, Welt, Held, Waffe, Upgrade, Relikt, Kokon (Truhe), Arkana, Limit Break. Eigene Begriffe höchstens ein bis zwei.

## Onboarding
Erste 60 s: bewegen, schießen, erstes Level-up. Pro Minute höchstens ein neues Konzept, Meta-Systeme erst nach dem ersten Run.

## USP-Test
Ein Merkmal zählt nur, wenn man es in einem 5-Sekunden-Clip sieht und es sich besser anfühlt. Für Horde Hunters heißt das: **Treffer-Gefühl** (Shotgun-Knall, Rückstoß, Gegner fliegen) und **Heldenpersönlichkeit** müssen im Clip sofort wirken.
