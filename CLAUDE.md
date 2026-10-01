# Horde Hunters – Projektkontext für Claude Code

Arbeite im **Godot-Projekt dieses Verzeichnisses** (`C:\Users\vrxby\Documents\Codex\HordeHunters`). Antworte dem Nutzer auf Deutsch. Verbindliche Richtung: `DESIGN_BRIEF.md`, Gesamtplan: `stages/00_plan.md`.

**Mawlings** (`C:\Users\vrxby\Documents\Codex\Godot\Mawlings`, GitHub `DavidMpush/Mawlings`) ist das Vorgängerprojekt (Schwarm). Es dient als **Quelle für Module**, die gezielt kopiert und angepasst werden. Dort nichts ändern. Die neuesten Wände und Böden liegen auf dem Mawlings-Branch `wip/etappe-34-37` (lesen über `git -c safe.directory=... show wip/etappe-34-37:<pfad>`).

Konzeptbilder der Helden: `C:\Users\vrxby\Documents\Codex\Swarm\Design\Human_Hero_Pivot_2026-10-01` (V2-Roster ist der gewählte Stil, nur lesen).

## Arbeitsweise
- Der Nutzer möchte größere, zusammenhängende, spielbare Etappen. Er übergibt Entscheidungen oft an Claude; dann selbst entscheiden und begründen.
- Fortschritt knapp und regelmäßig melden. Spielgefühl ehrlich anhand gerenderter Bilder beurteilen, nicht nur anhand bestandener Tests.
- Etappen stehen in `stages/NN_name.md` mit Abnahmekriterien; nach der Arbeit: Tests, Prüfbilder, README/Stage-Ergebnis aktualisieren, Commit auf `main` (erlaubt nach bestandener Prüfung), **kein Push ohne Auftrag**.
- Unabhängige Teile parallel an Subagenten mit getrenntem Dateibesitz verteilen. Subagenten machen **kein** `git stash/checkout/reset/clean` und keinen Commit.

## Technik
- Godot 4.7.2, GL Compatibility, Hochformat 900 × 1600 (`canvas_items`, `keep`). Ziel: Samsung S25.
- Godot-Konsole: `C:\Users\vrxby\Documents\Codex\Godot\Godot_v4.7.2-stable_win64_console.exe`.
- Automatische Läufe **immer** mit `--audio-driver Dummy`. Fenster-Läufe (Captures, Bench) mit `--screen 1` und **ohne** `--headless`.
- Tests: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/test.ps1 [-Only a,b]`. Neue Tests in die `$tests`-Liste aufnehmen.
- Hook `tools/hooks/check_gdscript.js` parst jede geänderte `.gd`-Datei.
- Dateien als UTF-8 ohne BOM schreiben (Umlaute prüfen).

## Konten (wichtig)
Claude läuft als Windows-Benutzer `arufa`, das Projekt gehört `vrxby`:
- Git braucht `-c safe.directory=C:/Users/vrxby/Documents/Codex/HordeHunters`; Commits mit `-c user.name="JAY Solution" -c user.email=david@jay-solution.com`.
- APK-Export und adb laufen nur unter `vrxby` (`tools/export_android.ps1`, vom Nutzer ausgeführt).

## Struktur (Ziel)
- `scripts/core/`: Run-Zustand.
- `scripts/hero/`: Held.
- `scripts/weapons/`: Waffen.
- `scripts/enemies/`: Gegner und Direktor.
- `scripts/combat/`: Treffer und Rückstoß.
- `scripts/world/`: Karte aus Mawlings.
- `scripts/progression/`, `scripts/ui/`: aus Mawlings, angepasst.
- `tests/`: Tests und Captures.
- `stages/`: Etappen.
