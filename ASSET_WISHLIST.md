# Horde Hunters – Asset-Wunschliste

Stand: 01.10.2026. Eine Liste für alles, was parallel erzeugt werden kann: Figuren und Waffen (Tencent 3D Studio / Hunyuan3D), 2D-Bilder (Konzepte, Icons, UI, Branding) und Audio. Grundlage sind `DESIGN_BRIEF.md`, `ASSET_PIPELINE.md`, `stages/00–03` und der aktuelle Code. Fast alles, was heute im Spiel steht, ist Platzhalter: Grundformen, Mawlings-Kreaturen, im Code gezeichnete Vektor-Icons und synthetische Töne.

## 1. Lieferregeln

### Formate (nach `ASSET_PIPELINE.md`)
| Art | Format | Hinweis |
|---|---|---|
| Held, Boss, Elite mit Gliedmaßen | **Rig-FBX** in T-Pose ohne Animation + **eine FBX je Clip** | Gleiche Figur, gleiches Rig. Dateiname `<Name> Rig.fbx`, `<Name> <Clip>.fbx` (z. B. `Brine Left Hook.fbx`). |
| Horden-Gegner | **statisches GLB**, kein Rig | Hunderte gleichzeitig, Animation im Shader. Neutrale Pose, Kopf nach vorn, Beine leicht gespreizt, Arme frei vom Körper. |
| Waffen, Projektile, Pickups, Props, Gelände | **statisches GLB** | Waffe immer **getrennt** von der Figur. Griff/Ursprung dort, wo die Hand greift. |
| Icons, UI, VFX-Texturen | **PNG mit Alpha**, sRGB | Icons 512 × 512 (wir verkleinern), VFX als einzelnes Bild oder Flipbook-Raster (z. B. 4 × 4 Bilder à 256 px). |
| Konzeptbilder, Splash, Hintergründe | PNG, Hochformat 1080 × 1920 oder größer | Ohne Text, Text setzen wir in Godot. |
| Soundeffekte | WAV 44,1 kHz 16 bit (oder OGG), **mono** | Kurz geschnitten, kein Stille-Anfang, Spitze ≤ −1 dBFS, 2–4 Varianten je Ereignis. |
| Musik | OGG Vorbis, **stereo**, nahtlos loopbar | Ziel um −14 LUFS integriert; Ambience leiser (≈ −20 LUFS). |

### Ablage
- Alles nach `Konzepte und Ideen/<Kategorie>/`, Kategorien: `Helden/`, `Waffen/`, `Gegner/`, `Bosse/`, `Props/`, `Pickups/`, `VFX/`, `UI/`, `Icons/`, `Audio/SFX/`, `Audio/Musik/`, `Store/`. Der Ordner ist nicht im Repo; die Werkzeuge erzeugen daraus leichte Spielversionen unter `assets/`.
- Vorhandenes bleibt, neue Varianten bekommen eigene Namen oder `_v2`. Prompt kurz in eine `PROMPTS.md` des Ordners schreiben (hilft bei Nachlieferungen).

### Prioritäten
- **P1** = als Nächstes gebraucht (ersetzt sichtbare Platzhalter im aktuellen Prototyp).
- **P2** = bald (Etappen 3–4: weitere Waffen, Welten, Menü-Politur).
- **P3** = später (weitere Helden, Store, Feinschliff).

### Dreiecke und Texturen
- Hunyuan-Ausgabe mit ~50k Dreiecken ist in Ordnung; `tools/build_rigged_hero.gd` und `tools/optimize_hero_model.gd` reduzieren (Held ≈ 6–9k, Boss ≈ 8–12k, Horden-Gegner ≈ 1,5–3k, Props ≈ 1–4k) und verkleinern die Textur auf 1024 (Gegner/Props 512).
- **Eine** Albedo-Textur je Modell genügt; Licht, Glanz, Konturen und Glühen macht der Toon-Shader. Bitte **keine eingebackenen harten Schatten oder Glanzlichter** in der Textur.
- Farbe in großen flachen Flächen, wenige Details: Was kleiner als ein Daumennagel auf dem Handy ist, verschwindet.

### Stil (verbindlich: V2-Roster)
- Supercell-nah (Brawl Stars / Clash Royale): kompakte Körper mit etwa 4 Kopf-Höhen, große Hände, Füße und Waffen, glatte matte Flächen, kräftige klare Farben, Haare als wenige skulptierte Formen.
- **Lesbar aus der schrägen Draufsicht** (Kamera von oben, Figur ca. 1/12 der Bildhöhe): starke Silhouette, eine dominante Farbe je Figur, ein großes Erkennungsmerkmal (Schulterplatte, Schürze, Kapuze), Waffe deutlich größer als real.
- Gegner: Farbe pro Typ eindeutig, Augen/Maul groß, Rücken-Silhouette (Panzer, Stacheln, Buckel) wichtiger als das Gesicht. **Magenta ist für Gefahr reserviert** (Ankündigungen) – nicht als Grundfarbe verwenden.
- Prompt-Bausteine, die sich bewährt haben: `stylized 3D mobile game character, Supercell style, chunky proportions, big hands and feet, smooth matte surfaces, flat bold colors, clean simple shapes, neutral T-pose, front view, full body, plain grey background, no base, no text`.

## 2. Helden

Hinweis zur Benennung: Im Code ist **Brine = der Boxer** (`hero_id "boxer"`, V5-Faustkämpfer, `Brine Rig.fbx` vorhanden). Der amphibische Fährmann aus `V6_Brine_Shotgun_3D` ist eine andere Figur; falls er gebaut wird, braucht er einen eigenen Namen (Vorschlag: „Fährmann“ als Arbeitsname).

| Priorität | Asset | Format | Details/Prompt-Hinweise | Wofür im Spiel |
|---|---|---|---|---|
| P1 | Brine – Idle/Kampfhaltung (Schleife) | `Brine Idle.fbx` | Boxer-Deckung, leichtes Wippen auf den Fußballen, Fäuste vor dem Kinn; 1–2 s, Anfang = Ende | Stand, Menü-Held, ersetzt den Clip-Standbildtrick |
| P1 | Brine – Laufen (Schleife) | `Brine Run.fbx` | Lockerer Lauf mit Deckung oben, Template „Run“/„Jog“; am Platz laufen (kein Vorwärtsweg im Clip) | Bewegung, ersetzt prozedurale Beine |
| P1 | Brine – Treffer | `Brine Hit.fbx` | Template „Hit“, kurzer Kopf-/Oberkörper-Ruck nach hinten, 0,3–0,4 s | Schaden am Helden |
| P1 | Brine – Tod | `Brine Death.fbx` | Rückwärts umfallen, liegen bleiben (letztes Bild ruhig) | GEFALLEN-Bildschirm |
| P1 | Brine – Left Hook | `Brine Left Hook.fbx` | Template „Left Hook“, kurz und schnappig | Kombo-Schlag 1/2 |
| P1 | Brine – Uppercut/Charged Punch | `Brine Uppercut.fbx` | Template „Charged Punch“ oder Uppercut: tief abtauchen, explosiv nach oben | Haken mit Rückstoß + Hitstop |
| P2 | Brine – Backstep/Dash | `Brine Dash.fbx` | Template „Backstep“ oder Ausfallschritt seitlich, 0,25 s | Dash-Knopf |
| P2 | Brine – Hammerfaust/Roundhouse | `Brine Roundhouse Kick.fbx` | Template „Roundhouse Kick“ oder beidhändiger Hammerschlag nach unten | 4. Kombo-Schlag (Rang 5) |
| P2 | Brine – Sieg/Jubel | `Brine Victory.fbx` | Faust in die Luft, Schulterrollen, Schleife möglich | Menü, Ergebnis nach Boss |
| P1 | Brann – 3D-Modell + Rig | `Brann Rig.fbx` | Nach V2-Roster: sehr breit, Glatze, kurzer quadratischer schwarzer Bart, große orange Schmiedeschürze, dunkle Kleidung, große Handschuhe; **ohne Waffe**, Hände offen in T-Pose | Erster Held, ersetzt die Grundformen-Figur |
| P1 | Brann – Idle | `Brann Idle.fbx` | Flinte in beiden Händen vor der Hüfte (Pose so, dass die rechte Hand die Waffe halten kann), ruhiges Atmen | Stand, Menü |
| P1 | Brann – Laufen | `Brann Run.fbx` | Schwerer Trab, Oberkörper ruhig (Waffe zielt beim Laufen) | Bewegung |
| P1 | Brann – Schießen | `Brann Shoot.fbx` | Kurzer Rückstoß aus der Hüfte, Schultern zucken zurück, 0,25 s | Jeder Schuss |
| P1 | Brann – Nachladen | `Brann Reload.fbx` | Lauf kippt auf, Hülsen raus, zwei Patronen rein, Lauf schnappt zu; ~0,7 s | 2 Schuss, dann Nachladen (Kernmoment) |
| P1 | Brann – Treffer | `Brann Hit.fbx` | Template „Hit“ | Schaden |
| P1 | Brann – Tod | `Brann Death.fbx` | Auf die Knie, dann zur Seite | GEFALLEN |
| P2 | Brann – Dash | `Brann Dash.fbx` | Schulterrolle oder Hechtsprung seitwärts | Dash |
| P2 | Brann – Sieg | `Brann Victory.fbx` | Flinte auf die Schulter legen, Nicken | Menü, Ergebnis |
| P1 | Brann – Doppelflinte | GLB (siehe Waffen) | Getrennt modelliert | Wird an die Hand gehängt |
| P1 | Porträt-Renders Brann/Brine | PNG 1024² | Schulterporträt im Spielstil, neutraler Verlauf, Blick leicht seitlich | Heldenkarte, Heldenwahl (ersetzt Bildausschnitte) |
| P2 | Rook – Konzept + Rig + Clips | Rig-FBX + Idle, Run, Swing, Hit, Death, Dash, Victory | Breit, eckiger Bart, große elfenbeinfarbene Schulterplatte, dunkelblau mit roter Schärpe; Waffe: breites Stahl-Großschwert (getrennt) | Held 3: Großschwert, breiter Frontalhieb, Block mit Konter |
| P2 | Vexa – Konzept + Rig + Clips | Rig-FBX + Idle, Run, Shoot L, Shoot R, Reload, Hit, Death, Dash, Victory | Asymmetrischer violetter Haarschnitt, einseitiger Amber-Mantel; zwei große Revolver (getrennt) | Held 4: schnelle Salven, Abpraller |
| P3 | Sable – Konzept + Rig + Clips | Rig-FBX + Idle, Run, Draw/Shoot, Hit, Death, Dash, Victory | Lange dicke Flechtsträhne, grüner Mantel, helle Ärmel; großer Holzbogen (getrennt) | Held 5: Bogen, Durchschlag, Markieren |
| P3 | Kael – Konzept + Rig + Clips | Rig-FBX + Idle, Run, Slash Combo, Lunge, Hit, Death, Dash, Victory | Haarknoten, schwarzer Oberkörper, breite glutrote Schärpe, helle Hose; breiter Säbel (getrennt) | Held 6: Säbel-Kombo mit Vorstoß |
| P3 | Optional: Nyra, Sera, Jett, Fährmann | wie oben | Nyra (Gewehr, türkiser Schultermantel), Sera (Lichtklinge), Jett (Energiefäuste), Fährmann (Amphibie, Harpune/Flinte) | Spätere Freischaltungen |
| P2 | Silhouetten der kommenden Helden | PNG 512², schwarz mit Alpha | Aus den finalen Konzepten abgeleitet (Vexa, Rook, Sable, Kael), Kopf + Schultern + Waffe erkennbar | „BALD“-Karten in der Heldenwahl |

Clip-Hinweise für alle Helden: am Platz animieren (Root bleibt stehen), 30 fps, Schleifen mit identischem Anfang/Ende, Waffenhand-Pose in allen Clips gleich (sonst springt die Waffe).

## 3. Waffen, Projektile, Einschläge

Alle als statisches GLB, Ursprung am Griff, Lauf/Klinge entlang +Z. Deutlich überdimensioniert (≈ 1,5 × real), wenige große Formen, klare Zweifarbigkeit (Metall + Holz/Leder + ein Akzent).

### Vorhandene Waffen (Platzhalter ersetzen)
| Priorität | Asset | Format | Details/Prompt-Hinweise | Wofür im Spiel |
|---|---|---|---|---|
| P1 | Doppelflinte (Brann) | GLB | Doppellauf nebeneinander, dicker Holzschaft mit Messingbeschlägen, Kipplauf-Scharnier sichtbar; Vorlage `V6_Brine_Shotgun_3D/02_brine_shotgun_separat.png` als Form-Hilfe | Startwaffe, Nachlade-Animation |
| P1 | Schrothülse | GLB, sehr klein | Rote Papphülse mit Messingboden, übertrieben groß | Fliegt beim Nachladen heraus |
| P2 | Boxbandagen/Handschuh-Variante | GLB oder Teil von Brine | Nur falls Brine später Handschuhe als Upgrade bekommt | Fäuste-Skin |
| P1 | Wurfaxt | GLB | Kurzer Holzstiel, breites Blatt mit heller Schneide, rotes Lederband; liest sich auch als Drehscheibe | Zusatzwaffe Wurfaxt |
| P1 | Schwert (Wirbel) | GLB | Breites gerades Schwert, Parierstange mit blauem Stein | Kreisende Klinge beim Schwert-Wirbel |
| P1 | Granate | GLB | Runde gusseiserne Kugel mit Lunte oder Stielgranate mit Holzgriff, gelbes Band | Zusatzwaffe Granate (Flug) |

### Neue Waffenideen (je eine GLB-Waffe + ggf. Projektil)
| Priorität | Asset | Format | Details/Prompt-Hinweise | Wofür im Spiel |
|---|---|---|---|---|
| P2 | Revolver-Paar | GLB (1 Revolver, wird gespiegelt) + Kugel | Langer Lauf, große Trommel, Perlmuttgriff | Schnelle Doppelsalve, Kugeln prallen 1× auf den nächsten Gegner ab (Vexa-Start) |
| P2 | Jagdbogen + Pfeil | GLB Bogen, GLB Pfeil | Großer Holzbogen mit Lederwicklung, Pfeil mit roten Federn | Langsamer, durchschlagender Schuss in Linie, markiert getroffene Elite (+Schaden) |
| P2 | Großschwert | GLB | Breite Klinge, lange Griffwicklung, Schulterlänge | Breiter Frontalhieb (±70°) mit starkem Rückstoß, langsam (Rook-Start) |
| P2 | Speer | GLB | Langer Schaft, breite Blattspitze, Fellquaste | Stoß in Linie, spießt bis zu 3 Gegner auf und schiebt sie weit zurück |
| P2 | Kriegshammer | GLB | Riesiger Steinkopf auf Holzstiel, Eisenringe | Bodenstampfer: Schockwelle rundum, wirft leichte Gegner um und betäubt kurz |
| P2 | Kettenmorgenstern | GLB Kopf + GLB Kettenglied | Stachelkugel, grobe Kettenglieder | Kreist dauerhaft um den Helden, Rückstoß nach außen (Orbit-Waffe) |
| P2 | Brandflasche (Molotow) | GLB | Bauchige Flasche, Stofflappen als Docht, orange Flüssigkeit | Wurf auf Gruppe, hinterlässt brennende Fläche (Schaden über Zeit) |
| P2 | Bumerang-Schild | GLB | Runder Holzschild mit Metallrand und Wappen | Prallt zwischen 3–5 Gegnern hin und her, kehrt zurück |
| P3 | Harpune | GLB Waffe + GLB Harpunenspitze mit Seil | Dicke Harpunenflinte, Widerhaken | Spießt ein Ziel auf und zieht es heran (oder Held zum Boss) |
| P3 | Bärenfalle / Mine | GLB | Eiserne Zackenfalle, offen | Wird hinter dem Helden gelegt, schnappt zu und hält schwere Gegner fest |
| P3 | Säbel | GLB | Breiter gebogener Säbel, Korbgriff in Glutrot | Kael: schnelle 3er-Kombo mit kurzem Vorstoß |
| P3 | Glockenhammer / Streitaxt | GLB | Juno-Idee: Axt mit gesprungener Glocke als Gegengewicht | Schwerer Rundumhieb, Glockenschall betäubt |

### Projektil- und Einschlag-Modelle
| Priorität | Asset | Format | Details/Prompt-Hinweise | Wofür im Spiel |
|---|---|---|---|---|
| P2 | Pfeil, Speer-Splitter, Kugel | GLB je ≤ 300 Dreiecke | Stark vereinfacht, kräftige Farbe | Fliegende Projektile |
| P2 | Brandfleck, Krater | GLB flach oder PNG-Decal | Dunkler Ruß mit Glutrand | Bleibt nach Granate/Molotow kurz liegen |
| P3 | Steckende Pfeile/Äxte im Boden | GLB | Gleiche Modelle, leicht schräg | Fehlschüsse bleiben kurz sichtbar |

## 4. Gegner der Horde (statisches GLB, kein Rig)

Für alle: neutrale Pose, **Kopf zeigt nach vorn (+Z)**, Beine leicht gespreizt und Arme leicht vom Körper (der Shader wippt, schwingt und neigt), eine Albedo-Textur, keine dünnen Teile (Fühler, Schwänze dick halten). Größen: Wichtel ≈ 1,25 m, Renner ≈ 1,5 m, Brocken ≈ 2,7 m. Prompt-Baustein: `stylized cute-menacing creature, Supercell style, chunky silhouette, big eyes, simple shapes, flat bold colors, neutral standing pose, three-quarter top view readable, no base`.

### Verdant Maw (grüne Jagdgründe, Welt 1)
| Priorität | Asset | Format | Details/Prompt-Hinweise | Wofür im Spiel |
|---|---|---|---|---|
| P1 | Wichtel | GLB | Kleiner kugeliger Moos-Kobold, blau-violette Haut, großer Kopf, kurze Krallenarme, Blätterbüschel auf dem Kopf | Masse ab 0:00, leicht, fliegt weit (ersetzt Moorbrut) |
| P1 | Renner | GLB | Flaches schnelles Dornenwiesel, rote Grundfarbe, lange Schnauze, nach hinten gelegte Stacheln | Schnell, wenig LP, ab 0:40 (ersetzt Skitter) |
| P1 | Brocken | GLB | Breiter Borkenkäfer-Troll, grau-brauner Rindenpanzer, riesige Vorderarme zum Ausholen | Schwer, kaum Rückstoß, großer angekündigter Hieb ab 1:30 (ersetzt Jägerkäfer) |
| P1 | Champion-Brocken | GLB oder Textur-Variante | Gleiche Form + goldene Rüstungsplatten, Krone/Hörner, Moosmantel | Elite mit Stampfring, droppt Gratis-Kokon |
| P2 | Sporenspucker | GLB | Pilz mit Maul im Hut, kurzer Stiel, Sporen-Beutel | Fernkämpfer (später, sparsam, angekündigt) |
| P2 | Blähfrosch | GLB | Aufgeblasener runder Frosch mit Giftblasen | Platzer: läuft heran, bläht sich auf, explodiert |
| P2 | Rindenschildträger | GLB | Wichtel-Verwandter hinter großem Rindenschild | Blockt frontal, muss umlaufen oder per Rückstoß gedreht werden |
| P3 | Wurzelrufer | GLB | Dürrer Baumschamane mit Laternenstab | Unterstützer: heilt oder schirmt Nachbarn |

### Dürrschlund (Wüste, Welt 2)
| Priorität | Asset | Format | Details/Prompt-Hinweise | Wofür im Spiel |
|---|---|---|---|---|
| P2 | Sandwichtel (Skarabäus) | GLB | Kleiner Mistkäfer mit Türkis-Panzer, große Kiefer | Masse |
| P2 | Knochenschakal | GLB | Hagerer Schakal mit Knochenmaske, sandgelb | Renner |
| P2 | Panzerechse | GLB | Breite Krustenechse, Sandsteinplatten auf dem Rücken | Brocken |
| P2 | Champion-Panzerechse | GLB-Variante | Goldene Kopfplatte, rote Stoffbänder | Elite |
| P2 | Säureskorpion | GLB | Großer Schwanz mit grüner Blase (dick modellieren) | Fernkämpfer, Säurepfütze |
| P2 | Grabwühler | GLB | Maulwurfwurm mit Bohrkopf | Taucht unter, erscheint mit Staubring neben dem Helden |
| P3 | Knochenschildkrieger | GLB | Skelettiger Echsenkrieger mit Schulterschild aus Rippen | Schildträger |
| P3 | Mumienbläher | GLB | Bandagierte Kugel mit Gas | Platzer |

### Glutsumpf (glühender Sumpf, Welt 3)
| Priorität | Asset | Format | Details/Prompt-Hinweise | Wofür im Spiel |
|---|---|---|---|---|
| P2 | Glutmolch | GLB | Kleiner schwarzer Molch mit orange glühenden Flecken | Masse |
| P2 | Aschflitzer | GLB | Magerer Echsenläufer, Rauchfedern am Rücken | Renner |
| P2 | Schlackegolem | GLB | Basaltblock-Körper, Lavarisse (in der Textur orange, Glühen macht der Shader) | Brocken |
| P2 | Champion-Schlackegolem | GLB-Variante | Obsidian-Krone, mehr Risse | Elite |
| P2 | Gasblase | GLB | Schwebende Sumpfblase mit Augen | Platzer, giftige Wolke |
| P2 | Funkenspucker | GLB | Kröte mit Glutsack am Hals | Fernkämpfer, Funkenbogen |
| P3 | Moorhexe | GLB | Gebeugte Torfgestalt mit Laterne | Unterstützer, beschwört Molche |

## 5. Bosse (Rig-FBX + Clips)

Clips je Boss: **Idle, Walk, Slam/Stampfer, Leap/Sprung (Absprung–Flug–Landung), Sweep/Rundumschlag, Hit, Death**, schön: Roar/Auftritt, Enrage. Am Platz animieren, Ankündigungen (Ausholen) deutlich und lang (0,6–1,0 s). Höhe im Spiel 4–6 m, also **sehr** klare Silhouette.

| Priorität | Asset | Format | Details/Prompt-Hinweise | Wofür im Spiel |
|---|---|---|---|---|
| P1 | Moorkönig | Rig-FBX + 7–9 Clip-FBX | Riesige Sumpfkröte/Morastkönig, Moosmantel, Wurzelkrone, breites Maul, kräftige Arme für Stampfer und Rundumschlag | Boss bei 4:00 (Verdant), ersetzt BogKing-/Moorbrut-Platzhalter |
| P1 | Moorkönig – Auftritt | `Moorkönig Rise.fbx` | Steigt aus dem Boden, brüllt | ARRIVING-Phase |
| P2 | Sandkoloss (Dürrschlund) | Rig-FBX + Clips | Riesenskarabäus oder Knochenkoloss mit Sandstein-Rückenplatte, Kiefer-Rundumschlag, Eingraben statt Sprung | Endboss Welt 2 |
| P2 | Glutkröte (Glutsumpf) | Rig-FBX + Clips | Riesige Basaltkröte mit Lavasack, Zunge als Sweep, Sprung mit Lava-Landung | Endboss Welt 3 |
| P3 | Schutzfeuer-Wächter | Rig-FBX + Clips | Verfallener Feuerturm-Golem (Beaconfall-Lore), Laterne als Kopf | Finaler Boss / Weltenkern |
| P3 | Elite mit Gliedmaßen (je Welt 1) | Rig-FBX + Idle, Walk, Attack, Death | Mini-Boss: z. B. Dornenritter, Wüstenhäuptling, Schlackenschmied | Zwischenboss zwischen Wellen |
| P2 | Boss-Porträts | PNG 512², rund freigestellt | Kopf frontal, wütend, gleiche Kontur wie Heldenporträts | Boss-Leiste, Auftrittsbanner |

## 6. Map-Props und Gelände (statisches GLB)

Vorhanden aus Mawlings: Rock, Leaf, RootArch, FallenLog, PondSeeds, Flower, SandstoneCliff, RibBones, Cactus, GiantSkull, RockArch. Wände entstehen prozedural (`wall_mesh.gd`) – Module unten sind Ergänzungen für Ränder und Landmarken. Props sind halbtransparent zwischen Kamera und Held: daher **geschlossene, kompakte Formen**, Unterseite flach, Ursprung am Boden.

### Allgemein (alle Welten, mit Biom-Tönung)
| Priorität | Asset | Format | Details/Prompt-Hinweise | Wofür im Spiel |
|---|---|---|---|---|
| P1 | Holzkiste (zerbrechlich) | GLB | Grobe Bretter, Eisenecken | Breakable, droppt Gold/Heilung |
| P1 | Fass (zerbrechlich) | GLB | Dicke Dauben, rote Bänder | Breakable, droppt Gold |
| P2 | Pulverfass | GLB | Fass mit Totenkopf-freiem Warnzeichen, Lunte | Explodiert bei Treffer, schadet Gegnern |
| P1 | Portal zur nächsten Welt | GLB | Steinbogen mit Runen/Leuchtfeuer-Schale, innen leer (Wirbel = Shader) | Nach dem Endboss in die nächste Welt |
| P2 | Leuchtfeuer-Station (Beacon) | GLB | Turm mit Feuerschale, teils zerfallen (Beaconfall) | Landmarke, später Aktivierungs-Ziel |
| P2 | Schrein | GLB | Kleiner Steinaltar mit Kristall | POI: Segen gegen Gold/Zeit |
| P2 | Händlerkarren | GLB | Karawanenwagen mit Plane (Free Caravans) | POI Händler |
| P2 | Wegweiser/Banner | GLB | Holzpfahl mit Stoffbanner | Kleine POI-Markierung |
| P3 | Lagerfeuer | GLB | Steinring, Holzscheite (Flamme = VFX) | Ruhepunkt, Menü-Szene |

### Verdant Maw
| Priorität | Asset | Format | Details/Prompt-Hinweise | Wofür im Spiel |
|---|---|---|---|---|
| P2 | Klippen-/Felswand-Modul (gerade, Ecke, Ende) | GLB je ~4 m | Moosbedeckte runde Felsstufen, oben grün | Kartenrand, Engstellen |
| P2 | Laubbaum groß / klein | GLB | Dicker Stamm, Krone aus 3–5 runden Blattballen | Wald-Gruppen, Landmarken |
| P2 | Busch, Farn, Pilzgruppe | GLB | Gebündelt, wenige große Formen | Füllmaterial |
| P2 | Ruinen-Säule, Mauerstück, Torbogen | GLB | Heller Stein mit Moos, Beacon-Guard-Symbol | Ruinen-POI |
| P2 | Holzbrücke | GLB 6 m | Breite Planken, Seilgeländer | Über Wasserläufe |
| P3 | Riesenbaum-Landmarke | GLB | Weithin sichtbar, Wurzeltor am Fuß | Ersetzt gebaute Beacon-Landmarke |

### Dürrschlund
| Priorität | Asset | Format | Details/Prompt-Hinweise | Wofür im Spiel |
|---|---|---|---|---|
| P2 | Sandstein-Klippenmodule | GLB | Rot-ocker Schichten, abgerundete Kanten | Kartenrand |
| P2 | Dornbusch, Kaktusgruppe, toter Baum | GLB | Flache dicke Formen | Füllmaterial |
| P2 | Wüstenruine, Obelisk | GLB | Zerbrochene Säulen, Stoffreste | Ruinen-POI |
| P2 | Riesen-Wirbelsäule, Hörner | GLB | Ergänzung zu RibBones/GiantSkull | Landmarke |
| P3 | Zeltlager der Karawane | GLB | Bunte Planen, Kisten | POI |

### Glutsumpf
| Priorität | Asset | Format | Details/Prompt-Hinweise | Wofür im Spiel |
|---|---|---|---|---|
| P2 | Basalt-Säulen und -Klippen | GLB | Sechseckige Säulen, dunkel mit warmen Kanten | Kartenrand, Engstellen |
| P2 | Verkohlter Baum, Baumstumpf | GLB | Schwarz, abgebrochene Äste | Füllmaterial |
| P2 | Glühpilz-Gruppe | GLB | Türkise Pilzhüte (Kontrast zum Orange) | Füllmaterial, Landmarke |
| P2 | Steg/Brücke aus Basalt | GLB | Flache Platten über Lava | Übergänge |
| P3 | Schlot/Geysir | GLB | Kegel mit Öffnung (Ausbruch = VFX) | Gelände-Gefahr („eruptions“) |

## 7. Pickups

Klein, sehr kräftig, drehen sich im Shader. Ursprung in der Mitte.

| Priorität | Asset | Format | Details/Prompt-Hinweise | Wofür im Spiel |
|---|---|---|---|---|
| P1 | XP-Gem klein / mittel / groß | GLB (eine Form, 3 Größen) oder 3 Formen | Facettierter Kristall; Farben im Spiel: Blau, Grün, Violett (Textur hell/neutral, Färbung macht der Code) | XP nach Kills |
| P1 | Goldmünze | GLB | Dicke Münze mit geprägtem Stern, Rand deutlich | Gold |
| P2 | Goldbeutel | GLB | Lederbeutel mit Münzen oben | Viel Gold (Elite, Fass) |
| P2 | Heil-Bernstein | GLB | Amber-Kristall mit Blatt eingeschlossen | Heilung |
| P2 | Magnet | GLB | Hufeisen-Magnet rot/silber | Sammelt alle Gems ein |
| P2 | Bombe | GLB | Runde schwarze Bombe mit Funken-Lunte | Räumt den Bildschirm |
| P1 | Kokon Karte | GLB | Seidenkokon creme mit Fäden, an Wurzel/Stein gesponnen | Kauf-Kokon (Gold) |
| P1 | Kokon Elite (gratis) | GLB | Kleiner, mit blauen Fäden | Elite-Drop |
| P1 | Kokon Boss | GLB | Groß, goldene Fäden, Krone aus Kristallen | Boss-Belohnung |
| P3 | Schatztruhe (Alternative) | GLB + Deckel getrennt | Falls „Kokon“ durch Truhe ergänzt wird | Spätere Meta-Belohnung |

## 8. VFX-Texturen (PNG mit Alpha)

Toon-Stil: harte Kanten, 2–3 Farbstufen, weiß oder hell (Färbung im Shader), keine fotorealistischen Rauchtexturen. Flipbooks als Raster mit gleich großen Zellen, 8–16 Bilder.

| Priorität | Asset | Format | Details/Prompt-Hinweise | Wofür im Spiel |
|---|---|---|---|---|
| P1 | Mündungsfeuer | 3–4 Einzelbilder 512² | Sternförmig, gelb-weißer Kern | Shotgun, Revolver |
| P1 | Treffer-Funken | Flipbook 4×4, 256er Zellen | Kurze Strahlen, comicartig | Jeder Treffer |
| P1 | Staubwolke | Flipbook 4×4 | Runde Wolkenballen, beige | Dash, Landung, Haken, Brocken-Hieb |
| P1 | Wisch-Sichel (Slash) | 2–3 Bilder 1024×512 | Breiter Bogen, Kante scharf, Ende ausfransend | Fäuste, Schwert, Großschwert |
| P1 | Explosion | Flipbook 4×4 oder 5×5 | Feuerball → Rauch, Toon-Stufen | Granate, Pulverfass, Platzer |
| P1 | Schockwellen-Ring | Einzelbild 1024² | Dünner heller Ring mit weicher Innenseite | Haken-Schockwelle, Hammer, Boss-Landung |
| P1 | Level-up-Ausbruch | Strahlenkranz + Funken | Gold/Weiß, sternförmig | Level-up am Helden |
| P1 | Ankündigungs-Muster | 3 Kacheln 512² | Kreis, Kegel, Streifen mit Schraffur/Pfeilen (weiß, Spiel färbt magenta) | Gegner- und Boss-Telegraphs |
| P2 | Splatter Gegner | 6–8 Varianten 512² | Toon-Klecks (Schleim, nicht Blut), weiß zum Einfärben | Bleibt kurz am Boden nach Kills |
| P2 | Rauchwolke | Flipbook | Dicke graue Ballen | Rauchgranate (Brann-Signatur) |
| P2 | Feuerfläche | Kachel + Flammen-Flipbook | Bodenflamme, loopbar | Molotow, Glutsumpf |
| P2 | Lichtstrahl | Einzelbild 256×1024 | Vertikaler Strahl, oben ausblendend | Kokon öffnen (Seltenheitsfarbe) |
| P2 | Portal-Wirbel | Einzelbild 1024² | Spirale, nahtlos drehbar | Portal |
| P2 | Heil-Plus, Magnet-Funken | Kleine Partikel 128² | Plus-Zeichen, Funkenstern | Pickups |
| P3 | Schadenszahlen-Schrift | Bitmap-Font oder Font-Empfehlung | Dicke Ziffern mit Kontur, Krit-Variante | Schadenszahlen (heute Baloo 2) |

## 9. UI/UX

Richtung: UI-Kit „brawl“ – blau-violette Flächen, kräftige dunkle Konturen, weiße Blockschrift, Türkis für Auswahl, großer grüner Spielknopf, Magenta = Gefahr. Farbwelt des Logos: Creme, Gold, Orange, Dunkelblau. 9-Slice-Elemente mit gleich breiten Rändern (Angabe der Randbreite in Pixeln mitliefern).

### Branding und Bildschirme
| Priorität | Asset | Format | Details/Prompt-Hinweise | Wofür im Spiel |
|---|---|---|---|---|
| — | Logo, App-Icon Boxer/HH, Key Art | vorhanden | `Konzepte und Ideen/Branding/` | Titel, Icon |
| P2 | App-Icon Brann-Variante | PNG 1024² | Brann mit Flinte, Mündungsblitz, gleicher Rahmen | A/B-Test Icon |
| P2 | Adaptive-Icon-Ebenen | PNG 432² (Vordergrund mit Alpha + Hintergrund) | Motiv im inneren 66-%-Kreis | Android-Startbildschirm (heute nur abgeleitet) |
| P1 | Menü-Hintergrund Hochformat | PNG 1080×1920 | Verdant-Lichtung von schräg oben, ruhige Mitte für Held und Knöpfe, ohne Text | Titelbildschirm (heute Key Art abgedunkelt) |
| P2 | Ladebildschirm | PNG 1080×1920 | Held vor Horde-Silhouette, Platz für Logo oben | Start, Weltenwechsel |
| P2 | Ergebnis-Kunst GEFALLEN / SIEG | PNG 1080×800 je | Gefallener Held mit Staub / Held auf Boss-Kokon | Ergebnisbildschirm |
| P2 | Welt-Titelkarten | PNG 1080×600 je Welt | Verdant Maw, Dürrschlund, Glutsumpf als Panorama | Weltenwechsel, Weltauswahl |

### Knöpfe, Rahmen, Karten
| Priorität | Asset | Format | Details/Prompt-Hinweise | Wofür im Spiel |
|---|---|---|---|---|
| P1 | Knopf groß grün / blau / grau / rot | PNG 9-Slice je | Dicke Kontur, unten dunkle Lippe (gedrückt-Variante extra) | SPIELEN, WEITER, NOCHMAL, MENÜ |
| P1 | Panel / Bogen-Hintergrund | PNG 9-Slice | Blau-violett mit leichtem Verlauf, runde Ecken | Pause, Einstellungen, Statistik |
| P1 | Kartenrahmen je Seltenheit | 5 × PNG 9-Slice | Gewöhnlich (grau), Ungewöhnlich (grün), Selten (blau), Episch (violett), Legendär (gold, mit Glanz) | Level-up- und Kokon-Karten |
| P2 | Band/Ribbon | PNG 9-Slice | Für Überschriften („LEVEL UP“, „GEFALLEN“) | Titel-Banner |
| P2 | Etikett „NEUE WAFFE“, „BALD“, „GRATIS“ | PNG | Kleine Stempel-Pillen | Karten, Heldenwahl, Kokon-Preis |
| P2 | Schalter, Regler, Checkbox | PNG | Brawl-Stil, an/aus | Einstellungen, Lautstärke |
| P2 | Arsenal-Elemente | PNG | Waffen-Kachel aktiv/inaktiv, Schloss, Haken | Arsenal-Bildschirm (Waffenpool an/aus) |

### Icons (PNG 512², gemalter Stil wie `V2_Stylized_Heroes/04_vexa_selection.png`, dunkle Kontur, kein Hintergrund)
| Priorität | Asset | Format | Details/Prompt-Hinweise | Wofür im Spiel |
|---|---|---|---|---|
| P1 | Waffen-Icons: Schrotflinte, Fäuste, Wurfaxt, Schwert-Wirbel, Granate | 5 × PNG | Waffe schräg 45°, groß, kräftige Lichtkante | Level-up-Karten, Build-Übersicht (ersetzt Vektor-Icons) |
| P2 | Waffen-Icons neue Waffen | 1 je Waffe aus Abschnitt 3 | gleicher Aufbau | Karten, Arsenal |
| P1 | Werte-Icons (11): Schaden, Feuerrate, Reichweite, Tempo, Max-LP, Regeneration, Rüstung, Sammelradius, Krit-Chance, XP-Bonus, Glück | 11 × PNG | Motive wie heute im Code: Explosion, Uhr, Fadenkreuz, Stiefel, Herz, Herz mit Pfeil, Schild, Magnet, Krit-Stern, Gem, Kleeblatt | Werte-Karten, Pause-Build |
| P1 | Relikt-Icons (10): Pulverhorn, Feldflasche, Lockstein, Dornenweste, Glücksmünze, Siebenmeilenstiefel, Jagdtrophäe, Bleihagel, Patronengurt, Ahnenamulett | 10 × PNG | Gegenstand im Fokus, Rahmenfarbe nach Seltenheit macht der Code | Kokon-Karten, Build-Übersicht |
| P2 | Waffen-Spur-Icons | 10 × PNG | Shotgun: +1 Kugel, Durchschlag, Wucht, Großes Magazin, Würgebohrung; Fäuste: Weiter Bogen, Schnelle Kombo, Schockwelle, Lebensraub, Hammerfaust | Rang-Karten |
| P2 | Ressourcen-Icons | PNG 256² | Gold, XP-Gem, Kill-Schädel (freundlich), Uhr, Krone (Bestwert) | HUD, Statistik, Ergebnis |
| P2 | System-Icons | PNG 256² | Pause, Einstellungen, Statistik, Zurück, Neustart, Lautsprecher, Musik, Vibration, Würfel (Neu würfeln) | Menüs, Pause |

### Helden- und Boss-Bilder
| Priorität | Asset | Format | Details/Prompt-Hinweise | Wofür im Spiel |
|---|---|---|---|---|
| P1 | Rundes Porträt je Held | PNG 512² | Kopf/Schultern, leicht seitlich, Hintergrund transparent | HUD, Heldenkarte, Ergebnis |
| P2 | Ganzkörper-Splash je Held | PNG 1080×1600 | Dynamische Pose mit Waffe, transparenter Hintergrund | Heldenwahl, Freischaltung |
| P2 | Gesperrte Silhouetten | PNG 512² | Siehe Abschnitt 2 | „BALD“-Karten |
| P2 | Boss-Porträt | PNG 512² | Siehe Abschnitt 5 | Boss-Leiste, Banner |

### HUD und Steuerung
| Priorität | Asset | Format | Details/Prompt-Hinweise | Wofür im Spiel |
|---|---|---|---|---|
| P1 | LP-Leiste Rahmen + Füllung | PNG 9-Slice | Dicke Kontur, Füllung weiß (Färbung im Code) | Helden-LP |
| P1 | XP-Leiste mit Level-Plakette | PNG 9-Slice + Plakette 128² | Sechseckige Plakette für die Level-Zahl | XP-Zeile oben |
| P1 | Zeit-Pille, Kill-Zähler, Gold-Zähler | PNG 9-Slice | Dunkle Pille mit Icon-Platz | HUD oben |
| P1 | Pause-Knopf | PNG 256² normal/gedrückt | Runder Brawl-Knopf | Oben rechts |
| P1 | Joystick-Ring + Knauf | PNG 512² / 256² | Halbtransparent, Kontur deutlich | Schwebender Joystick rechts |
| P1 | Dash-Knopf + Abklingring | PNG 256² + Ring 256² | Stiefel- oder Pfeil-Motiv, Ring als radiale Füllung | Dash links |
| P2 | Boss-Leiste | PNG 9-Slice + Schädel-Endstück | Breit, rot-violett, Platz für Namen | Moorkönig-LP |
| P2 | Wellen-Banner, Richtungspfeil | PNG | „WELLE!“-Banner, dicker Randpfeil | Ankündigungen (Welle, Einkesselung) |

### Schrift
| Priorität | Asset | Format | Details/Prompt-Hinweise | Wofür im Spiel |
|---|---|---|---|---|
| — | Baloo 2 (Display) + Figtree (Text) | vorhanden, SIL OFL | Lizenz liegt bei (`assets/ui/fonts/OFL_*.txt`) | Alle Texte |
| P3 | Optional: Lilita One oder Luckiest Guy für Titel | TTF, SIL OFL / Apache | Nur Fonts mit OFL/Apache, Lizenzdatei mitliefern; keine Supercell-Schrift (proprietär) | Große Titel, Schadenszahlen |

## 10. Audio – Soundeffekte

Heute: Schuss, Klick, Hülse, Dash sind **im Code synthetisiert**; Treffer, Kill, Held-Treffer, Warnung, Stampfer, Tod, UI kommen aus Mawlings. Alles wird ersetzt. Je Ereignis **2–4 Varianten** (`<ereignis>_1.wav` …), mono, 44,1 kHz, kurz, Spitze ≤ −1 dBFS. Häufige Töne (Treffer, Gem) sehr kurz (< 150 ms) und eher leise gemischt.

### Waffen
| Priorität | Asset | Format | Details/Prompt-Hinweise | Wofür im Spiel |
|---|---|---|---|---|
| P1 | Shotgun Schuss | WAV mono ×3 | Tiefer Knall mit Bass-Punch, kurzer Hall, < 500 ms | Kern des Treffer-Gefühls |
| P1 | Shotgun Lauf öffnen / Hülsen raus / Patronen rein / Lauf zu | WAV je ×2 | Metallisches Klacken, Hülsen-Klingeln | Nachladen (0,7 s) |
| P1 | Faust Jab / Cross / Haken | WAV je ×3 | Dumpfer Schlag, Haken mit Bass und kurzem „Whoomp“ | Fäuste-Kombo |
| P1 | Wurfaxt Wurf (Surren) / Treffer / Fang | WAV je ×2 | Rotierendes Surren loopbar | Wurfaxt |
| P1 | Schwert-Wirbel Whoosh / Klingentreffer | WAV je ×2 | Breites Zischen, metallisch | Schwert-Wirbel |
| P1 | Granate Wurf / Aufprall / Explosion | WAV je ×2 | Explosion dumpf mit Nachrollen | Granate |
| P2 | Neue Waffen: Revolver, Bogen, Speer, Hammer, Morgenstern, Molotow, Bumerang | WAV je Abschuss + Treffer | Gleicher Stil wie oben | Neue Waffen |
| P2 | Krit-Treffer | WAV ×2 | Heller „Ping“ über dem Treffer | Krit |

### Gegner und Bosse
| Priorität | Asset | Format | Details/Prompt-Hinweise | Wofür im Spiel |
|---|---|---|---|---|
| P1 | Treffer weich (Wichtel/Renner) | WAV ×3 | Kurzes nasses „Plopp“ | Treffer an leichten Gegnern |
| P1 | Treffer hart (Brocken/Boss) | WAV ×3 | Panzer-Klonk | Treffer an schweren Gegnern |
| P1 | Kill klein / Kill groß | WAV ×4 / ×2 | Klein: Quieken + Puff; groß: Krachen + Staub | Kill |
| P1 | Ausholen-Warnung Brocken | WAV ×2 | Knurren mit ansteigendem Ton (0,6 s) | Ankündigung Hieb |
| P2 | Gegner-Geräusche je Typ | WAV ×2 je | Wichtel kichern, Renner fauchen, Brocken grunzen (selten abspielen) | Atmosphäre, Erkennung |
| P1 | Champion erscheint / Stampfer | WAV ×1 / ×2 | Fanfare-artiges Brüllen; tiefer Bodenschlag | Elite |
| P1 | Moorkönig: Brüllen, Stampfer, Absprung, Landung, Rundumschlag, Treffer, Tod | WAV je ×1–2 | Tief, feucht, groß; Landung mit Sub-Bass | Boss |
| P2 | Platzer-Zischen + Explosion, Spucker-Schuss + Aufprall | WAV je ×2 | — | Neue Gegnertypen |

### Held
| Priorität | Asset | Format | Details/Prompt-Hinweise | Wofür im Spiel |
|---|---|---|---|---|
| P1 | Held getroffen (Brann, Brine) | WAV je ×3 | Kurzer Stöhner, stimmlich passend | Schaden |
| P1 | Held Tod | WAV je ×1 | Längerer Aufschrei/Seufzer + Fall | GEFALLEN |
| P1 | Dash | WAV ×2 | Luftstoß + Stoff-Rascheln | Dash |
| P2 | Schritte je Boden (Gras, Sand, Asche) | WAV ×4 je | Sehr leise | Laufen |
| P3 | Sprachfetzen je Held | WAV ×5 je | Kurze Rufe („Nachladen!“, Lachen, Siegesspruch) – Deutsch oder ohne Worte | Persönlichkeit |

### Pickups und UI
| Priorität | Asset | Format | Details/Prompt-Hinweise | Wofür im Spiel |
|---|---|---|---|---|
| P1 | Gem aufsammeln | WAV ×3 | Heller Glöckchen-Ton, leicht steigende Tonhöhe möglich | XP |
| P1 | Gold aufsammeln | WAV ×3 | Münz-Klimpern | Gold |
| P2 | Heilung, Magnet, Bombe | WAV je ×1 | Warmes Aufleuchten / Saugen / großer Knall | Pickups |
| P1 | Kokon: Halten, Aufblähen, Platzen | WAV je ×1 | Seide spannt sich, dann glitzerndes Platzen | Kokon öffnen |
| P1 | Knopf-Tipp | WAV ×2 | Kurz, weich, nicht nervig | Alle Knöpfe |
| P1 | Karte erscheint / Karte gewählt | WAV je ×1 | Kartenwisch / bestätigendes „Thunk“ | Level-up, Kokon |
| P2 | Karte gewählt je Seltenheit | 5 × WAV | Steigend: Gewöhnlich schlicht … Legendär mit Chor/Glanz | Seltenheits-Gefühl |
| P1 | Level-up | WAV ×1 | Kurzer Aufstieg mit Glanz | Level-up |
| P2 | Neu würfeln, Pause an/aus, Kauf nicht möglich | WAV je ×1 | — | Reroll, Pause, zu wenig Gold |

### Wellen, Alarme, Ambience
| Priorität | Asset | Format | Details/Prompt-Hinweise | Wofür im Spiel |
|---|---|---|---|---|
| P1 | Wellen-Horn | WAV ×1 | Tiefes Kriegshorn, 1,5 s | „WELLE!“ |
| P1 | Einkesselungs-Warnung | WAV ×1 | Unheilvolles Anschwellen | Einkesselung ab 2:00 |
| P1 | Boss-Auftritt | WAV ×1 | Trommelschlag + Brüllen, 2–3 s | Moorkönig bei 4:00 |
| P2 | Endwelle startet | WAV ×1 | Glocke + Horn | Endwelle ab 6:00 |
| P2 | Portal öffnet | WAV ×1 | Magisches Anschwellen | Weltenwechsel |
| P2 | Ambience Verdant / Dürrschlund / Glutsumpf | OGG stereo loop 60–90 s | Vögel+Wind / Wüstenwind+Sandrieseln / Blubbern+Glutknistern | Hintergrund je Welt |

## 11. Musik

Heute gibt es **keine Musik** (Bus „Music“ ist vorbereitet). OGG stereo, nahtlos loopbar (Loop-Punkt angeben), um −14 LUFS. Ideal: **Stems/Intensitätsebenen** (Basis, + Percussion, + Melodie), die wir je nach Druck einblenden.

| Priorität | Asset | Format | Details/Prompt-Hinweise | Wofür im Spiel |
|---|---|---|---|---|
| P1 | Menü-Thema | OGG loop 1:30–2:00 | Abenteuerlich, warm, einprägsames Motiv, 100–110 BPM | Titel, Heldenwahl |
| P1 | Run Verdant Maw | OGG loop 2–3 min, 3 Ebenen | Treibend, Folk-Percussion, Streicher/Flöte, 128–135 BPM | Run Welt 1 |
| P2 | Run Dürrschlund | OGG loop, 3 Ebenen | Wüstenskalen, Handtrommeln, Oud-artig, 130 BPM | Run Welt 2 |
| P2 | Run Glutsumpf | OGG loop, 3 Ebenen | Dunkler, tiefe Trommeln, verzerrte Bässe, 135–140 BPM | Run Welt 3 |
| P1 | Boss-Thema | OGG loop 1:30 | Schwere Trommeln, Bläser, 140 BPM | Moorkönig, weitere Bosse |
| P2 | Endwelle | OGG loop 1:00 | Hektisch, ansteigend, 150 BPM | Endwelle ab 6:00 |
| P1 | Sieg-Sting | OGG 3–5 s, kein Loop | Fanfare, Dur | Boss besiegt, Portal |
| P1 | Niederlage-Sting | OGG 3–5 s, kein Loop | Abfallend, nicht deprimierend („nochmal!“-Gefühl) | GEFALLEN |
| P2 | Level-up-Pausen-Bett | OGG loop 20–30 s | Sehr leise, schwebend | Während der Kartenwahl |

## 12. Store und Marketing (P3)

| Priorität | Asset | Format | Details/Prompt-Hinweise | Wofür im Spiel |
|---|---|---|---|---|
| P3 | Feature-Grafik Google Play | PNG 1024×500 | Held vs. Horde, Logo links, keine kleinen Texte | Store-Eintrag |
| P3 | Screenshot-Rahmen | PNG 1080×1920, 5–8 Stück | Rahmen + kurze Werbezeile (Text in Godot/Figma setzen) um echte Spielbilder | Store-Screenshots |
| P3 | Trailer-Keyframes | PNG 1080×1920 | Shotgun-Schuss mit fliegenden Wichteln, Boss-Sprung, Level-up-Karten, Portal | 15–30-s-Trailer, USP-Clip |
| P3 | Promo-Icon-Varianten | PNG 1024² | Saisonal / pro Held | Store-Tests |
| P3 | Social-Banner | PNG 1500×500, 1080² | Key Art angepasst | Social Media |

## 13. Reihenfolge-Empfehlung (zuerst liefern)

1. **Brine: Idle, Laufen, Treffer, Tod** (Rig ist da – größter sichtbarer Gewinn sofort).
2. **Brine: Left Hook + Uppercut/Charged Punch** (Kombo komplett aus Clips).
3. **Brann: Rig + Idle, Laufen, Schießen, Nachladen, Treffer, Tod** und die **Doppelflinte** als GLB.
4. **Horden-Gegner Verdant: Wichtel, Renner, Brocken** (+ Champion-Variante) als statische GLB.
5. **Moorkönig** als Rig + Clips (Rise, Idle, Walk, Stampfer, Sprung, Rundumschlag, Treffer, Tod).
6. **SFX-Kernpaket:** Shotgun-Schuss + Nachladen, Faustschläge, Treffer weich/hart, Kill, Gem, Gold, Level-up, Knopf.
7. **Musik:** Run Verdant (mit Ebenen), Boss-Thema, Menü-Thema, Sieg/Niederlage-Sting.
8. **Icons:** 5 Waffen, 11 Werte, 10 Relikte (ersetzen die Code-Vektoren auf den Karten).
9. **UI-Grundkit:** Kartenrahmen je Seltenheit, Knöpfe, LP/XP-Leisten, Joystick, Dash-Knopf, Pause-Knopf.
10. **Pickups + Kokons + VFX-Kern:** XP-Gems, Münze, 3 Kokons, Mündungsfeuer, Funken, Staub, Explosion, Schockwelle.

Danach: Zusatzwaffen-Modelle (Axt, Schwert, Granate), Breakables und Portal, dann die Welten Dürrschlund und Glutsumpf mit Gegnern, Bossen und Props, danach Held 3 (Rook) und 4 (Vexa).
