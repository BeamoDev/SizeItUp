# Scale It Up!

A Roblox size-estimation game. Players sit at authored tables, take turns resizing an object against a reference, then compare guesses with its real size. Classic, Endless, Best of Five and Sudden Death control scoring and elimination. Pets, chairs, titles, rewards and purchases share saved profiles with a separate AFK place.

The lobby is populated by variable-count NPC players from `ServerStorage.Characters.NPC`. They arrive and leave through normal spawn locations, roam with varied routes, change cosmetics, respond to lone players and can play complete NPC-only matches using the normal table and bot-turn systems. Names, mugshots, streaks, VIP status, titles, chairs and pets are randomized.

## Start here

- [AGENTS.md](AGENTS.md): short instructions for future agents.
- [Architecture](docs/ARCHITECTURE.md): systems, configuration and known differences between requested rules and implementation.
- [Studio setup](docs/STUDIO_SETUP.md): source mappings, required assets and playtesting.
- [UI authoring](docs/UI_AUTHORING.md): authored HUD bindings and allowed runtime content.

## Repository

| Folder | Purpose |
| --- | --- |
| `src/Client` | Main-place input, camera, models, HUD and menus |
| `src/Server` | Main-place matches, economy, persistence and world bindings |
| `src/Shared` | Main-place public catalogs, configuration and utilities |
| `src/AFKClient` | AFK HUD and camera |
| `src/AFKServer` | AFK rewards, persistence and travel |
| `src/AFKShared` | AFK configuration and shared copies |

The source maps are [project.sources.json](project.sources.json) and [project.afk.sources.json](project.afk.sources.json). Studio owns the map, models and authored UI; those assets are not included in this repository.

The test suite was removed at the owner's request. Use the focused Studio checklist in the setup guide. A source review or local syntax check does not verify the published game.
