# Menschliche Helden · Richtungsentwurf

**Status: V1 verworfen.** Nutzerfeedback am 01.10.2026: Diese ersten Entwürfe sind zu realistisch und passen nicht zur bestehenden Linie. Die [korrigierte Richtung](V2_Stylized_Heroes/README.md) zeigt stark vereinfachte kompakte Supercell-nahe 3D-Formen, erwachsene menschliche Charaktere und eine verbundene Fantasy-Lore.

Stand: 01.10.2026. Auf Wunsch des Nutzers wird die Mawlings-Richtung vorerst stehen gelassen. Diese vier Bildkonzepte erkunden einen Survival-Roguelite mit einem menschlichen Einzelhelden, vertrauten Schusswaffen und normalen Nahkampfwaffen. Es wurde dafür kein Godot-Spielcode umgebaut. Die vorhandenen Quellen und Assets bleiben als bisheriger Stand erhalten.

## Drei visuelle Richtungen

| Entwurf | Bild | Schwerpunkt | Einschätzung |
|---|---|---|---|
| A · Rift Frontier | `01_frontier_gameplay.png` | Farbige Expedition, Rifles und Stahlklingen, Ruinen und fremde Biome | Empfehlung: passt zu den vorhandenen Welten und verbindet klare Helden mit einer eigenen Abenteuerwelt. |
| B · Dusk Hunters | `02_dusk_hunters_gameplay.png` | Menschliche Monsterjäger, Schwerter und Pistolen, verfallene Dörfer | Sofort verständliches Genre, aber stärkere Nähe zu bekannten Dark-Fantasy-Spielen. |
| C · Salvage Crew | `03_salvage_crew_gameplay.png` | Menschliche Bergungstruppe, Shotguns und Macheten, überwucherte Forschungsanlagen | Klare Identität und Waffenfantasie, verlangt mehr neue Umgebungsgrafiken. |
| A · Heldenauswahl | `04_hero_selection.png` | Mara Voss und fünf weitere menschliche Helden | Zeigt den Freischaltanreiz über Gesichter, Waffen, Fähigkeit und kurze Geschichte. |

Diese Namen bezeichnen Arbeitshypothesen, keine endgültige Marke. Beschriftungen sind Englisch. Die Bilder sind generierte Mockups, keine gerenderten Screenshots oder fertigen Spielassets. Ihre Umwelt-Details sind teils aufwendiger als unser späteres mobiles 3D-Modulset. Sie legen weder Angriffsradien noch Gegnerzahlen oder endgültige HUD-Maße fest.

## Warum der Wechsel sinnvoll sein kann

Ein menschlicher Held bietet sofort erkennbare Eigenschaften: Gesicht, Kleidung, Haltung und eine vertraute Waffe. Das erleichtert dem Spieler die Vorstellung, wen er spielt. Freischaltungen werden attraktiver, wenn ein Held nicht nur anders aussieht, sondern eine andere Art zu kämpfen anbietet. Das bleibt eine Designhypothese; die Mockups und ein späterer kleiner Spieltest sollen sie prüfen.

Die Schwarm-Population und das Wachstum durch Biomasse waren ein eigener mechanischer Schwerpunkt. Beim Wechsel zum Einzelhelden entfällt dieser Schwerpunkt. Die neue Identität sollte deshalb aus einer zusammenhängenden Besetzung, einer erkennbaren Welt und der Reise zwischen Biomen entstehen. Mehr Hintergrundtext allein trägt das Spiel nicht.

## Vorschlag für den bestehenden Spielkern

- Ein menschlicher Held mit LP, automatischen Waffenangriffen, Bewegung und einer aktiv ausgelösten Ausweich- oder Signaturfähigkeit. Die Mockups zeigen rechts Bewegung und links Ausweichen; die genaue Bedienung wird später geprüft.
- Waffen-Builds verbinden Rifles, Pistolen, Shotguns und Bögen mit Schwertern, Großschwertern oder Speeren. Eine Startwaffe gibt dem Helden Identität; weitere gefundene Waffen erlauben gemischte Builds.
- XP führt zu Werte- und Talententscheidungen. Kisten und Bosse geben Waffen und Ausrüstung. Ob wir die bestehende duale Progression exakt behalten, wird nach dem Richtungsentscheid geklärt.
- Münzen kaufen Ausrüstung im Run. Biomasse/Population wird nicht einfach in eine neue gleichartige Ressource umbenannt; Heilung oder andere Drops müssen zum Einzelhelden passen.
- Die begrenzte Erkundungskarte, mehrere Laufwege, entdeckbare Orte, Magenta-Warnflächen, zunehmender Druck, Horden und Bossmuster bleiben brauchbare Grundlagen.
- Nach einem Biom-Boss führt ein Riss mit dem bestehenden Build in die nächste Welt. Dschungelruinen, Wüste und Glutsumpf können als Expeditionsgebiete weiterleben; Welt- und Bossnamen sind noch offen.

## Richtung A: sechs Helden als erste Besetzung

Die Figuren sind bewusst unterschiedlich in Gesicht, Körperbau, Outfit, Startwaffe und Bewegungsfantasie. Name, Lore, Fähigkeit und Unlock sind Vorschläge, keine bestätigten Spielregeln.

| Held | Identität und Motivation | Startwaffe / Spielstil | Signatur-Idee | Freischaltgeschichte |
|---|---|---|---|---|
| Mara Voss | Expeditionskapitänin. Sie sucht ihre hinter dem Riss verschwundene Crew. Orange Jacke, türkiser Schal, weiße Haarsträhne. | Arc Rifle; präzise mittlere Reichweite | Rally Shot: durchschlagender Schuss nach einem kurzen Ausweichschritt | Starterin; führt in die Reise und in den zentralen Konflikt ein. |
| Gideon Ash | Älterer ehemaliger Wachtkommandant. Er will Menschen retten, nachdem er einst einen Außenposten aufgab. Breite Gestalt, dunkle Haare, helle Plattenrüstung. | Großschwert; Nahkampf und Flächenschaden | Last Stand: kurz blocken und einen schweren Gegenschlag ausführen | Überlebende in einer belagerten Ruine finden. |
| Inez Vale | Gesetzlose Kurierin. Sie besitzt eine gestohlene Karte und sucht ihren verschollenen Partner. Rotes Haar, burgunderfarbener Mantel. | Zwei Pistolen; Bewegung, schnelle Treffer, Abpraller | Crossfire: kurze Salve mit verbesserten Abprallern | Einen Kurier-Auftrag durch mehrere Orte abschließen. |
| Oren Pike | Veteran und Mechaniker. Seine Werkzeuge sollen diesmal Leben retten. Stämmig, Bart, blaue Arbeitsjacke, Schutzbrille auf der Stirn. | Shotgun; kurzer breiter Schadenskegel | Field Rig: eine zeitlich begrenzte improvisierte Geschützstellung | Eine verlassene Signalstation reparieren. |
| Sera Reed | Kundschafterin und Heilerin. Sie sucht ein Heilmittel für die Risskrankheit ihrer Schwester. Dunkle Haut, Zöpfe, grüne Reisekleidung. | Langbogen; gezielte Treffer und markierte Ziele | Hunter's Mark: ein starkes Ziel markieren und Schwachstellen ausnutzen | Pflanzenproben aus unterschiedlichen Biomen sichern. |
| Kade Wynn | Entkommener Rissläufer. Er will die Menschen finden, die an ihm experimentiert haben. Schlanke Gestalt, blass-türkises Haar, violetter Schal. | Stahlschwert; riskantes Hineingehen und Rückzug | Rift Step: kurze Versetzung mit anschließendem Schwertschlag | Einen versteckten Laborzugang entdecken. |

Ein Unlock soll neue Entscheidungen geben und gleichzeitig ein kleines Stück der Welt erklären. Jede Figur braucht dafür nur eine klare persönliche Frage und wenige gut platzierte Story-Momente; lange Lore-Blöcke im Auswahlmenü sind nicht nötig.

## Nächster sinnvoller Schritt

Zuerst eine visuelle Richtung wählen und den Stil der menschlichen Helden festlegen. Danach einen kleinen reversiblen Godot-Prototyp mit einem Helden, einer Schusswaffe, einem Schwert, Ausweichen und einem vorhandenen Biom bauen. Erst wenn dieser Ablauf funktioniert, die komplette Progression und die übrigen Helden umbauen.

## Dateien und Erzeugung

Vier PNG-Mockups in diesem Ordner. Erzeugt mit dem eingebauten Imagegen-Werkzeug; vollständige Prompts stehen in `PROMPTS.md`. Die Heldenauswahl nutzt das A-Spielbild als Stil- und Mara-Referenz. Die bisherigen Mawlings-Assets wurden nicht ersetzt.
