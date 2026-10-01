# Audio-Herkunft und Lizenzen

Alle Dateien in `assets/audio/` sind entweder **prozedural** erzeugt (`tools/gen_sfx.py`, eigene Synthese, keine Fremdrechte), aus dem **Audio-Paket V1** des Nutzers (selbst synthetisiert, lizenzfrei) oder aus **vom Nutzer gelieferten Aufnahmen** abgeleitet (`tools/import_user_sfx.py`). Die Originale liegen unverändert in `C:\Users\vrxby\Documents\Codex\Swarm\Design\Sounds\` und werden **nicht** ins Repository oder den Export kopiert; im Spiel liegen nur gekürzte, gefilterte, in Mono umgewandelte Varianten.

## Mixkit-Dateien (Mixkit Sound Effects Free License)

Quelle: https://mixkit.co/free-sound-effects/ – Mixkit-Lizenz: kostenlos in kommerziellen und nicht-kommerziellen Projekten (auch Spielen) nutzbar, ohne Namensnennung; **nicht** als eigenständige Sound-Dateien oder in einer Sound-Bibliothek weitergeben oder verkaufen. Im Spiel eingebettet (Export komprimiert QOA) ist erlaubt; die Dateien in diesem Repo daher nicht separat veröffentlichen.

| Quelldatei | Spiel-IDs |
|---|---|
| `mixkit-aggressive-beast-roar-13.wav` | `boss_roar_1..2` |
| `mixkit-alien-technology-hum-2134.wav` | `portal_open_1..2` |
| `mixkit-completion-of-a-level-2063.wav` | `milestone_1..2` |
| `mixkit-epic-orchestra-transition-2290.wav` | `migration_whoosh_1` |
| `mixkit-game-blood-pop-slide-2363.wav` | `kill_1..4`, `death_1..3` |
| `mixkit-mechanical-crate-pick-up-3154.wav` | `alpha_core_1..2` |
| `mixkit-mystwrious-bass-pulse-2298.wav` | `quake_1..2` |
| `mixkit-ominous-drums-227.wav` | `flood_warn_1..2` |
| `mixkit-sci-fi-positive-notification-266.wav` | `mutate_1..3` |
| `mixkit-sword-magic-drag-3009.wav` | `evolve_1..2` |
| `mixkit-technological-futuristic-hum-2133.wav` | `portal_hum_1` (Loop) |
| `mixkit-trumpet-fanfare-2293.wav` | `fanfare_1` |
| `mixkit-video-game-health-recharge-2837.wav` | `regen_1..2` |
| `mixkit-retro-game-emergency-alarm-1000.wav` | nicht verwendet (sehr schrill, Energie um 17 kHz) |

## Weitere Stock-Sounds (vom Nutzer bestätigt am 27.09.2026)

Der Nutzer hat bestätigt, dass alle gelieferten Sounds lizenzfreie Stock-Sounds sind. Bei einer Veröffentlichung die genaue Quelle je Datei nachtragen.

| Quelldatei | Spiel-IDs | Status |
|---|---|---|
| `soft-quick-sound-of-slime-sk5tldnt.wav` | `split_1..4` | Stock, lizenzfrei (Nutzerangabe) |
| `merge-3-mobile-game-short-7ir6tzte.wav` | `grow_1..3` | Stock, lizenzfrei (Nutzerangabe) |
| `sling-streching-sfx-for-m-vpiblugt.wav` | `leaper_windup_1..2` | Stock, lizenzfrei (Nutzerangabe) |

## Audio-Paket V1 (vom Nutzer selbst synthetisiert, lizenzfrei, 27.09.2026)

Quelle: `C:\Users\vrxby\Documents\Codex\Swarm\Design\Audio\` (`build_audio.py`, eigene Oszillatoren und generiertes Rauschen, keine Fremd-Samples). Keine Fremdrechte, keine Namensnennung nötig. Verarbeitung reproduzierbar in `tools/import_user_sfx.py` (Rezepte mit `"dir": "v1"`, Musik in `MUSIC_RECIPES`).

| Quelldatei | Spiel-IDs |
|---|---|
| `SFX/bite_01..03.wav` | `bite_1..4` (ersetzt prozedurales `bite`) |
| `SFX/enemy_telegraph.wav` | `warn_1..3` (ersetzt prozedurales `warn`) |
| `SFX/ui_tap.wav` | `ui_1..3` (ersetzt prozedurales `ui`) |
| `SFX/run_end.wav` | `extinct_1..2` (ersetzt prozedurales `extinct`) |
| `SFX/rally.wav` | `rally_1..2` |
| `SFX/corpse_harvest.wav` | `harvest_1..3` |
| `SFX/dna_gain.wav` | `dna_1..2` |
| `SFX/threat_rise.wav` | `threat_1..2` |
| `SFX/population_loss.wav` | `loss_1..2` |
| `SFX/swarm_feeding_cluster.wav` | `feed_1` (Loop) |
| `SFX/swarm_rustle_01..02.wav` | `rustle_1` (Loop, beide Dateien verbunden) |
| `Music/mawlings_arena_loop_96bpm.wav` | `assets/music/v1_arena.wav` (Musikstil „v1“) |
| `Music/mawlings_boss_loop_128bpm.wav` | `assets/music/v1_boss.wav` (Musikstil „v1“) |

Nicht übernommen (Ereignis bereits besetzt): `mutation_select` (`mutate`), `boss_entrance` (`boss_roar` + Stinger `boss`).

## Prozedural (eigene Synthese)

`hit`, `stomp`, `pickup`, `leader_hit`, `leader_swap`, `heartbeat`, `ambience_jungle` sowie die klassische Musik unter `assets/music/` (`tools/gen_music.py`).

Etappe 23 (Audio-Durchgang, 28.09.2026), alles eigene Synthese in `tools/gen_sfx.py` (`SOUNDS_23`) bzw. `tools/gen_music.py`, keine Fremdrechte:
`collect_coin`, `cocoon_open`, `cocoon_common`, `cocoon_rare`, `cocoon_epic`, `cocoon_legendary`, `cocoon_denied`, `powerup_take`, `powerup_end`, `shrine_tick`, `shrine_done`, `ability_glutsprung`, `ability_land`, `ability_sporenbombe`, `ability_panzerstoss`, `ability_hetzjagd`, `ability_saeureschwall`, `ability_schattenschleier`, `ability_ready`, `leader_hit_heavy`, `sandworm_breach`, `sandworm_sweep`, `sandgrub_burst`, die Loops `sandworm_dig`, `sandstorm`, `quicksand`, `ambience_desert` sowie die Wüsten-Musik `assets/music/desert_base/tension/flood/boss.wav`. `leader_critical` nutzt die `heartbeat`-Dateien. Etappe 24: `ambience_glutsumpf` (Loop), `lava_warn`, `lava_burst` (`SOUNDS_24`), ebenfalls eigene Synthese. Die Stock-Sounds des Nutzers waren bereits alle vergeben; neue Aufnahmen wurden nicht importiert. Die prozeduralen Fassungen von `bite`, `warn`, `ui`, `extinct` erzeugt `tools/gen_sfx.py` nur noch, wenn die V1-Quellen fehlen.
