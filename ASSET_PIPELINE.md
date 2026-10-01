# 3D-Asset-Pipeline (Tencent 3D Studio / Hunyuan3D → Godot)

Originale liegen in `Konzepte und Ideen/` (nicht im Repo, `.gdignore`). Die Werkzeuge erzeugen daraus leichte Spielversionen unter `assets/`.

## Was wir je Modell brauchen

**Helden** (und später Bosse oder Elite mit Gliedmaßen):
1. **Rig-FBX**: Bone Binding in T-Pose, *ohne* Animation, z. B. `Brine Rig.fbx`.
2. **Eine FBX je Animation**, gleiche Figur, gleiches Rig, z. B. `Brine Double Punch.fbx`. Gewünschte Clips:
   - **Pflicht:** Idle bzw. Kampfhaltung (Schleife), Laufen (Schleife), Angriff(e), Treffer, Tod.
   - **Schön:** Dash/Ausweichen, Sieg/Jubel fürs Menü.
3. Dateiname = Figur + Clip; das Tool vergibt die Clipnamen.
4. **Format FBX**: Godot liest es direkt. GLB/USDZ/MP4/GIF sind für das Spiel nicht nötig.
5. Ein **Standbild-GLB** (wie `Brine.glb`) ist nur ohne Rig nötig. Eine Figur mit Rig braucht es nicht.

**Gegner der Horde** (Hunderte gleichzeitig, MultiMesh): kein Rig. Ein statisches GLB in neutraler Pose reicht; sie werden im Shader animiert.

**Props und Gelände**: statisches GLB.

## Werkzeuge
- `tools/build_rigged_hero.gd`: Rig plus Clips → `<name>_rig.scn` und `<name>_albedo.png` (Dreiecke reduziert, Skin-Gewichte bleiben, Textur 1024).
  ```
  Godot_console.exe --headless --audio-driver Dummy --path . --script tools/build_rigged_hero.gd -- res://assets/heroes/brine brine 9000 1024 "<Konzepte>/Brine Rig.fbx" "double_punch=<Konzepte>/Brine Double Punch.fbx"
  ```
- `tools/optimize_hero_model.gd`: statisches GLB → `<name>_mesh.res` und `<name>_albedo.png` (Füße auf y = 0, Höhe 1).

## Stand Brine (01.10.2026)
- 50k → 6,25k Dreiecke, 28 Knochen (Mixamo-Namen), Textur 1024.
- `boxer_model.gd` setzt die Pose Knochen für Knochen:
  - **Aus dem Clip:** Deckung (Clip bei 0 s), linke Schläge (0,15–0,35 s), rechte Schläge (0,42–0,6 s).
  - **Prozedural:** Laufbeine, Drehung zum Ziel, Vorlage, Kopf-Treffer.
- Sobald Idle-, Lauf-, Treffer- und Tod-Clips da sind, ersetzen sie die prozeduralen Teile.
