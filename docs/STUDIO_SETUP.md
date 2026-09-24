# Studio setup and validation

The JSON mappings describe intended Script Sync connections; they do not connect Studio or publish places. The map, UI, templates and model assets live in Studio.

## Source mappings

| Place | Source | Studio destination |
| --- | --- | --- |
| Main: 97619904048927 | `src/Client` | `StarterPlayer.StarterPlayerScripts.Client` |
| Main | `src/Server` | `ServerScriptService.Server` |
| Main | `src/Shared` | `ReplicatedStorage.Shared` |
| AFK: 95238940314216 | `src/AFKClient` | `StarterPlayer.StarterPlayerScripts.AFKClient` |
| AFK | `src/AFKServer` | `ServerScriptService.AFKServer` |
| AFK | `src/AFKShared` | `ReplicatedStorage.AFKShared` |

Use `project.sources.json` for main and `project.afk.sources.json` for AFK. Both server Bootstrap files are Scripts; both client Bootstrap files and the main `ProximityPromptScript.local.luau` are LocalScripts. Other Luau files are ModuleScripts. The custom prompt script expects its authored Default/Theme template children.

Connect only the roots for that place, sync, then restart Play. Cross-place profile sharing requires both places in the same experience. Confirm configured IDs and actual Studio connections before publishing.

## Main-place assets

| Authored location | Purpose |
| --- | --- |
| `StarterGui.HUD` | Game, Lobby, Frames and BlackWipe; see [UI authoring](UI_AUTHORING.md) |
| `Workspace.Game.Zones.2v2/2v2Tables`, `3v3/3v3Tables` | Existing table assemblies; duplicate model names are allowed |
| Each table's numbered seat assemblies | Existing nested Seat instances, stable seat order, exact matching capacity |
| Each table's `Table.Top` | Preferred upper surface for cash/countdown and display placement |
| `Workspace.Game.Zones.ObjectArena` | Authored comparison arena, or an ArenaName under Workspace.ScaleArenas |
| `ServerStorage.Objects` | Supported comparison Models/MeshParts/BaseParts; private HeightMeters overrides. Import scale is arbitrary: runtime previews discard fully transparent helper bounds and normalize visible geometry to one stud before applying real-life metres. |
| `ServerStorage.Pets.Active` | Flat folder containing every playable pet Model directly; spacing differences in model names are normalized and `ServerStorage.Pets.InActive` is ignored |
| `ServerStorage.Characters.NPC` | Direct child NPC Models with Humanoid and HumanoidRootPart; appearance templates for the fake lobby population only |
| `ServerStorage.Characters.Bot` | Model with Humanoid and HumanoidRootPart; the exclusive character template used by the Play Bot button |
| `ReplicatedStorage.Assets.Chairs`, `.LuckyBlocks`, `.Eggs` | Catalog-mapped viewport/equipment assets |
| `ReplicatedStorage.Assets.UI` | Authored cards, vote portraits, world tags, PlayerDetails and a BotTag BillboardGui; BotTag is cloned disabled into every bot and enabled locally only for allowlisted users 1790165114 and 2044711693 |
| `Workspace.Game.Interactables.Chairs.Chairs`, `.Eggs` | Authored chair shop and Common/Uncommon/Exquisite egg stands |
| `Workspace.Game.Triggers.AFK.Hitbox` | Touch portal to AFK |
| `Workspace.Map` | Water BaseParts and authored RespawnPoint markers |
| `Workspace.Runtime.Models`, `.Pets`, `.NPC`, `.Other` | Runtime preview, follower, NPC and miscellaneous display containers |
| `SoundService.SFX` | Named authored sounds used by SfxController and AFKController |

Do not generate replacement lobby furniture or delete the authored 4v4 area. Existing code still registers it; the requested inactive behavior is recorded in [architecture](ARCHITECTURE.md#owner-requirements-versus-existing-code).

Arena `CameraPart`, `ReferenceSpawn` and `TargetSpawn` must be anchored BaseParts. Author the two spawn markers at the same Y and viewing depth, with ReferenceSpawn left of TargetSpawn from CameraPart. The server reads these exact CFrames and never creates or repositions the markers. The comparison camera begins at CameraPart and adaptively fits both rendered objects for the current viewport. The authored HUD must contain `Game.AdjustingSize.Right.Container.Track`, `Minus` and `Plus`; Track may contain a `Knob`, and each button may itself be a GuiButton or contain one. `ObjectArena.ButtonModel` is not required. Streaming requires a Persistent arena Model. Missing ArenaName may use LobbySetup's comparison-arena fallback; this does not authorize generating a lobby.

At least two valid objects within the private ratio limit are needed. ObjectLibrary and PetLibrary create sanitized replicated previews; preserve original assets. Keep asset IDs/names aligned with catalogs rather than adding undocumented replacements.

NPC templates are cloned without modifying their sources. Their parts are unanchored and server-owned at runtime. An authored server `Animate` Script is retained; otherwise the population service drives standard R6 idle, walk and sit tracks. A template `Move` Script is disabled on the clone because NPCPopulationService is the single movement owner. Each ambient NPC receives a randomized valid Roblox headshot; set a positive `AvatarUserId` attribute on a template to choose its portrait. The Play Bot button exclusively clones `ServerStorage.Characters.Bot` through PracticeBotService, presents it as the plain `Bot`, uses the legacy bot portrait, and never registers it as part of the ambient population. Add an enabled lobby `SpawnLocation` named `SpawnLocation`, `Spawn`, or containing `Lobby`; NPC arrivals and departures prefer it and ignore arena spawns. `MinimumWalkers` keeps part of the crowd roaming while other NPCs use verified Seat welds and real table matches. The remaining `NPCPopulation` values tune speed/acceleration, waypoint imperfections, bounded path retries, routes, pauses, table response, bot-only matches, lifetimes and cosmetic changes.

## AFK-place assets

Provide authored `StarterGui.HUD.AFK`, the ordinary map, and optional `AFKSpawn`. An optional anchored BasePart named `Camera` defines the orbit view; AFKController supports map-based fallback framing. Entry requires five saved Wins in both the main place and AFK runtime. No ScaleAFKWorld wrapper or scenery generator is required.

Include `ServerStorage.Pets.Active` for AFK reward pets and the catalog-mapped replicated chair/block/egg assets. `InActive` is never scanned. AFKPreviews generates only sanitized reward preview models. The HUD has fifteen history slots and five offer slots; see the UI guide.

## Saving and travel

Both save configs use `ScaleItUp_Profiles_v1`, a 180s lease and 45s autosave. Saving is enabled by default. For intentional unsaved Studio play, set that place's `MemoryOnlyInStudio = true`; published servers still save. Use a test experience for persistence validation. Keep the seven duplicated module pairs listed in AGENTS byte-identical.

Travel saves/releases the profile and recovers if teleport fails. Test actual travel, purchases, badges, referrals and DataStore behavior in published test clients; local syntax checks cannot validate Roblox services. Keep live prices/IDs in the catalogs and preserve receipt/pass validation.

## Focused playtest checklist

Run the rows relevant to the change. The removed test suite is not a prerequisite and should not be recreated just to follow these docs.

| Change | Check |
| --- | --- |
| Startup/assets | Main and AFK load independently; Output identifies missing paths; authored geometry remains intact |
| Tables/modes | Two and three clients seat, leave, die and refill during voting/countdown/roll; stale votes fail and roster changes restart correctly |
| No tutorial guide | Join with zero completed matches, walk near empty/occupied tables, sit, stand and respawn: no tutorial beam or red arrow appears. Ordinary Play Bot still works. |
| NPC population | Add several NPC templates; with one real player confirm a stable 11–14 NPC target, two roamers, table waiting/playing, rate-limited pet/chair/win chat news, then add players and confirm one-for-one departures, unique identities, real-player priority, post-match reuse and clean shutdown |
| Turns/input | One active owner, live watching, early lock and deadline lock; drag release stops, UI blocks picking, lock uses the visible value |
| NPC roaming | Watch every NPC template walk, pause, turn and jump. Interrupt a walk with table dispatch, seating and removal; the old route must not resume. On a roaming runtime clone, temporarily set PlatformStand or disable EvaluateStateMachine and confirm recovery restores walking. Check sustained sliding recovery through the clone's ScaleNPCRecoveryReason attribute, while brief bumps, ordinary jumps and seated matches remain unaffected. |
| Bot seating | Record authored seat CFrames, then repeatedly seat/release ambient NPCs and use Play Bot, including table dispatch during a roaming turn and a human taking the reserved seat. Chairs must retain the same position/rotation, bots must use the normal seated pose, and another occupant's weld must survive. Check failed seating retries and post-match exits: retries never pivot an attached rig and exit movement removes only that bot's SeatWeld first. |
| Privacy/results | Inspect owner versus watcher packets; reveal order/timing survives repeated snapshots; guesses remain bounded and floor-aligned |
| Hints | Use a pet hint, a saved credit and a new paid purchase: each shows the same exact-size yellow clone only to the guesser, with no directional advice. Resize both above and below it, including capped large objects and narrow screens; the clone shares the scale/floor/left edge and stays in frame. Repeated snapshots must reuse it; expiry permits another hint and lock/turn change/teardown removes it. Watcher packets contain no Hint.Actual and mystery rulers remain ???m. |
| Hearts/completion | Ties, healing, elimination and Best of Five settle once; depart during final review/reaction; no duplicate prize or reversed winner |
| Bot reaction camera | Open several mugshots for the same bot, then play through table reactions: the camera and heart highlight must follow the seated Workspace rig. PortraitWorld clones must have no runtime bot tags or ScaleBotUserId. Repeat after rebuilding portraits and with a late-replicating bot; cached targets must reject viewport clones and reaction effects must attach without restarting the slot. |
| Map interactions | Water preserves health/releases seats; prompts validate distance/state; furniture restores after equipment or departure |
| Bot water recovery | Walk every bot rig onto thin/shallow Water parts and drop one through a thin surface between polling ticks. Confirm a return to the nearest authored RespawnPoint, upright feet above its surface, unchanged health, zero residual velocity and ScaleNPCRecoveryReason = Water. Trigger recovery while pathfinding, turning and approaching a reserved seat: no old waypoint or seating callback may resume. Verify the brief pause and fresh roaming, dry bridges above water, rotated Water parts, dead/untagged rigs being ignored, and assigned/default spawn fallback without markers. At the lucky-block return area, test a marker below the platform floor and one overlapping water: the bot must land above dry support or choose the next safe marker/spawn. Leave the bot standing there beyond the debounce; its water return count must stop increasing. An immediate genuine re-entry near a failed landing must not reuse it, and delayed touches from the previous location must be ignored. If all candidates are unsafe, expect a single diagnostic rather than a teleport loop. Remove the service and check authored CanTouch is restored. |
| Spectator exit | In a three-player Sudden Death/Classic/Endless match, lose all hearts and keep watching. Jump or use the authored Exit/Leave control during guessing and reactions: the camera/HUD must return immediately, table and match ownership must clear, and survivors must continue unchanged. Join another table before the old match ends; its later snapshots/cleanup must not reclaim your UI or seat. Repeat by naturally unseating/resetting. Living players must retain their jump lock, while eliminated seated spectators can still buy a valid heart refill before leaving. Preserve existing four-seat rejection. |
| Sabotage presentation | On desktop and phone, watch another player's turn: one random available sabotage button shakes at a time; no immediate repeated choice when multiple are shown. Buy Wobble and Ink separately and together: check stronger spins/rings/sparks, Ink fading/sliding offscreen, early lock, expiry, repeated snapshots, new turns and leaving. Controls stay usable, rulers retain their steady projection, authored button poses restore and all owned effects disappear on teardown. |
| UI | Desktop and narrow touch screens; menus, voting, transitions, hatch and respawn restore input/camera/visibility without duplicate handlers; chair-shop outlines/tags hide during a match and return in the lobby |
| Economy/pets | Buy/equip/unequip, single/bulk hatch, saved block stock, XP/ability progress and legacy ownership across rejoin |
| Saves/products | Failed load/save, repeated receipts/claims and late hint/heart grants preserve credits and never overwrite or double-grant |
| AFK/travel | Offer odds total 100%, displayed offer supplies the reward; main -> AFK -> main preserves profile; failed travel restores HUD/control |

For a source-only cleanup, validate source-map paths, remaining Luau syntax, documentation links, duplicate-copy parity and unchanged retained runtime files. State explicitly when Studio or published-client checks were not run.
