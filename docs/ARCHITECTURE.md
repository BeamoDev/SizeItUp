# Architecture

This describes the checked-in source, not a verified published place. Some supplied owner requirements differ from that source; the final section records the differences without changing gameplay.

## Startup and ownership

| Area | Entry point / owner | Responsibility |
| --- | --- | --- |
| Main server | `src/Server/Startup/Bootstrap.server.luau` | Builds services/assets/remotes, binds world objects, routes requests and advances server ticks |
| Main client | `src/Client/Startup/Bootstrap.local.luau` | Attaches AuthoredUI first, then loading, inventory, match, sound, followers and world-label controllers |
| Custom prompts | `src/Client/ProximityPromptScript.local.luau` | Authored custom prompt presentation |
| AFK server | `src/AFKServer/Startup/Bootstrap.server.luau` | Builds reward previews and AFKRuntime; anchors players and ticks rewards/saves |
| AFK client | `src/AFKClient/Startup/Bootstrap.local.luau` | Starts AFKController and the authored AFKView |

`Shared/Network/MatchRemotes` names the match remotes. Cosmetics use `CosmeticCatalog.RemoteName`; AFK uses `AFKConfig.RemoteName`. Bootstrap validates/routes requests into services; clients do not create matches or choose rewards.

## Matches and world

- `LobbySetup`, `WorldBindings`, `TableService`: discover authored assemblies, validate seats/arenas, observe occupants, vote, count down, roll prizes and clean up. `TableDisplay` supplies tabletop status/miniatures; `SpectatorDisplayController` controls participant visibility.
- `MatchService`: authoritative mode, roster, turn order, deadlines, snapshots, hints/sabotage, departures and exactly-once settlement. `RoundService` chooses compatible pairs and scores guesses; `ChainProgress` supports Endless. `BotPlayer` plans human-like guess movement. `NPCPopulationService` supplies variable-count lobby NPCs, while `PracticeBotService` creates the separate legacy Bot used by Play Bot.
- `ChairTagController` disables distant chair-shop Highlights and BillboardGui tags during a match, preserving and restoring their authored Enabled values. MatchController leaves world instances under their authored parents.
- Flow: waiting -> voting for capacities >=3 -> countdown -> prize roll -> guessing/locked turns -> reveal -> table return -> reaction -> next round or match end -> ejection/IDLE. GO and intro states remain supported but have zero configured duration.
- Classic loses one life for a unique lowest score; tied lowest scores keep lives. Endless uses a rising accuracy target and chains the last target into the next reference. Best of Five totals raw accuracy across five rounds without normal round heart losses. Sudden Death starts with one life.
- Pair history is per match: unordered pair uses, object uses and recent appearances guide selection within direction bags. Eligibility uses private heights, excludes self-pairs and caps their ratio at 4:1. `RoundService` sends a power-of-two guess band and a shared randomized starting guess.
- `ObjectLibrary` imports supported Models/BaseParts from `ServerStorage.Objects`; `ObjectVisual` removes fully transparent import helpers before measuring visible bounds, normalizes every cloned preview to exactly one visible stud, and records non-secret source/normalized bound diagnostics as attributes. The client multiplies that neutral template by the public reference metres or the current private guess, so arbitrary import scale cannot affect displayed size. `ObjectData` holds public identities, `ObjectMeasurements` private defaults, and a source `HeightMeters` attribute can override a height.
- `WaterRespawn`, `AFKPortal`, `ChairShop`, `EggShops`, `LuckyBlocksTrigger` own their respective world interactions. WaterRespawn safely returns living players and tagged bots that touch authored water, with only each bot's root kept touch-enabled. `CosmeticDisplay` and `ChairFx` own server-visible tags/chair effects and equipped-chair presentation.

NPCPopulationService chooses a 12–15 visible-population target per server, subtracts real Players and caps the result at fourteen ambient NPCs. It builds unique Roblox-valid usernames from ten weighted styles, independently varies DisplayNames, and assigns randomized public avatar IDs. Five progression tiers keep each NPC's wins, matches, streaks, playtime, level, hatches, earnings and Cash proportional to its VIP status and pet/chair/title collection. Nearby-player billboards discover tagged ambient NPC characters as well as Players; their profile and Cash-steal requests resolve the server's temporary negative bot ID. The server repeats the normal range, living-character, seating, match, cooldown, credit and purchase checks before atomically moving an NPC's current Cash into the real player's saved profile. Practice bots are excluded. Each NPC has its own speed, pause, detour, social and restlessness biases. WalkSpeed eases toward a per-leg target; final approaches, planned pauses and jumps slow first. Longer walks use randomized intermediate goals and small lateral waypoint variation. Paths retain server network ownership and recompute at most three times after failure or `Path.Blocked`; stationary look turns ease over a few low-frequency steps. Roaming mixes short local strolls, attraction visits and movement near real players or other NPCs. Ground misses become stay-put destinations rather than walks into empty space. Imported movement scripts and force actuators are disabled, and a low-cost speed/fall/radius guard returns an unmatched runaway NPC to spawn with cleared velocity. NPCs spawn at authored lobby SpawnLocations, periodically change equipped cosmetics, then walk back toward a spawn before being replaced. A minimum roaming quota keeps two NPCs moving while the others approach tables. Seating uses a dedicated state, a sit animation and verified `Seat.Occupant`/`Humanoid.SeatPart` retries. Real players waiting at two-, three- or four-seat tables receive priority, and the population reserves enough NPCs to fill every remaining seat even while other bots are already playing. Ambient NPCs can also fill and complete NPC-only matches. Play Bot requests bypass this population and exclusively clone `ServerStorage.Characters.Bot` through PracticeBotService, creating a plain `Bot` with a negative portrait ID that selects the legacy bot mugshot and no fake player profile. `Workspace.NPCCount` and `DisplayedPopulation` expose only the ambient display values; neither type can change Roblox's platform server count.

When a real watcher lacks a Sabotage credit, a valid troll-button click opens the developer-product prompt during either a real player's or bot's GUESSING turn. Bot turns additionally freeze the bot's slider plan and server deadline with a full configured turn remaining. `MarketplaceService.PromptProductPurchaseFinished` releases that hold on purchase or cancellation, then the bot replans from its currently visible guess. Concurrent watcher prompts share the hold; player departure, stale turn IDs and a 120-second missing-event cap release it. Receipt processing remains the only authority that grants and spends the product.

Each server chooses one stable visible-population target from 12–15, so one real player produces 11–14 NPCs and every additional real player removes one NPC until none are needed. The population reserves two managed NPCs as roamers while available extras seek tables, waits 40–90 seconds and completes NPC-only tables more often. NPC activity messages share one global ChatNews schedule with 75–160 second base spacing, silent due slots and occasional extra two-to-five-minute quiet periods; pet/chair messages avoid immediate type repetition. Catalog-backed pet rolls and chair purchases update that NPC's runtime cosmetics, while BotWin is emitted only for an actual completed win and includes a streak once it reaches three. Bot matches freeze a difficulty strategy from the real participants' saved Matches, Wins and BestChainRound. New profiles get a close contest whose decisive rounds favor the human; skilled profiles get a 50/50 match-level human-win roll; intermediate profiles use a 72% human-win blend. Early rounds can swing either way, while final-heart/final-round targets land narrowly above or below the humans' demonstrated accuracy. The ordinary scorer still determines every heart and winner.

## Client presentation

`MatchController` coordinates ScaleController, PreviewController, CameraController, UIController, TransitionController and ReactionController. ScaleMath owns bounded logarithmic scaling/scoring helpers. Direct picking targets only visible local mystery geometry. Camera changes and smoothing never change accepted server scores.

MatchController leaves authored world instances under their existing parents when match state changes.

The comparison camera starts from ObjectArena.CameraPart and uses the original adaptive framing path. Each render step fits the current reference and mystery bounds using viewport aspect, smooth distance following and bounded FOV, so resizing and large pairs remain visible. WorldBindings validates and reads the authored anchored ReferenceSpawn/TargetSpawn BaseParts without creating or repositioning them. The state HUD binds `AdjustingSize.Right.Container.Track/Minus/Plus`; ObjectArena.ButtonModel is not used by gameplay. The separate table-reaction camera retains its own framing.

Preview clones use `Workspace.Runtime.Models`; followers use `Workspace.Runtime.Pets`. Bounds exclude invisible helpers, effects and contact shadows. The projected reference/mystery rulers use a viewport-responsive ZIndex 0 layer with white, black-outlined vertical segments and wider top/bottom caps. Each caption stacks object name, measurement and optional reveal mugshot above the ruler; mobile elements shrink, top/side positions clamp on-screen, and authored HUD panels naturally draw over them instead of displacing them. Reveals are driven by server timestamps and `RevealPresentation`, with local-first slots and per-viewer colors. Answer/guesses share a left edge and floor. `ReactionCycle` coordinates avatar/camera/HUD reaction beats.

`AuthoredUI.Match` selects GameStatesUI when `Game.AdjustingSize` exists, otherwise GameFrameUI for compact controls, otherwise the authored legacy binding. InventoryController manages menu requests and availability; InventoryView routes the authored views. See [UI authoring](UI_AUTHORING.md).

`NewPlayerSeatGuide` is the only first-match guidance. Profiles with zero completed matches receive a local beam to the nearest free Seat on an available capacity-two table. Its arrow BillboardGui is attached to the authored table surface with a three-stud world offset. It also accepts a table with one waiting opponent, retargets when a seat becomes unavailable, and removes all local guide objects as soon as the player sits. There is no tutorial UI, tutorial remote, forced bot match or saved tutorial state.

## Economy, progression and assets

| Owner | Responsibility |
| --- | --- |
| `EconomyRuntime` | Profile lifecycle, economy remote, receipts/pass grants, state replication and settlement |
| `ProfileService` / `ProfileSchema` | Leased DataStore document, reconciliation, autosaves and failed-load protection |
| `CurrencyService` / `InventoryService` | Wallet changes, ownership, equipment, chairs, pet buying and hatching |
| `TransferService` / `ReferralService` | Durable stealing transfers and verified invite payouts/mailboxes |
| `EngagementService` / `PotionService` | Daily/group/lifetime playtime claims and expiring boosts |
| `PetProgressionService` / `PetAbilityService` | Equipped-time XP versus saved match-turn ability progress |
| `PlayerLevelService` / `LeaderboardService` | Player XP/title unlocks and rankings |
| `BadgeRules` / `AnalyticsFunnel` | Badge eligibility and deduplicated onboarding steps |

Profiles include Cash, Keys (displayed as Gems), ownership/equipment, pet XP/ability progress, player progression, statistics, rewards, boosts, credits, receipts, passes, badges and transaction journals. Both places use `ScaleItUp_Profiles_v1`. Never send balances in teleport data: TravelService saves/releases the lease before travel and recovers after failure.

`PetDatabase` is an identity/asset index, not a gameplay catalog. PetLibrary scans only direct pet Models under the flat `ServerStorage.Pets.Active` folder, ignores `InActive`, preserves originals, writes `ServerStorage.ScalePetDatabase`, and publishes usable previews in `ReplicatedStorage.ScalePetPreviews`. It resolves the authored model name, display name or stable pet ID with normalized spacing. Missing outcomes block relevant purchases. CosmeticCatalog owns pets, direct egg shops, abilities, rarity/presentation, chairs, titles and level formulas.

ShopCatalog owns products, passes, blocks, odds, currencies and bulk opening. Paid receipt grants persist before acknowledgement; late hint/heart receipts retain a saved credit when a request is no longer valid. OwnedBlocks opens saved stock before charging for a new block. Current blocks each have four 60/28/10/2 outcomes; catalog values are authoritative. Pet XP is shared by type; match abilities use a captured unique roster and strongest applicable passive effects.

The local lost-heart refill binds Hearts.1/2/3 and shows only the next missing heart. When the current round removes that heart, its TextLabel stays hidden until the local player's heart-loss tween completes in their TABLE_REACTION slot; earlier losses remain purchasable normally. MatchService accepts a refill during another player's turn, lock/reveal, table return or reaction, and can recover a zero-heart player before the match finishes. The server binds it to the purchaser's authoritative live MatchId, membership and mode cap; Best of Five has no heart refills. Round/turn changes do not invalidate a delayed receipt. Bootstrap suppresses overlapping prompts and clears cancellation state through `PromptProductPurchaseFinished`.

## AFK place

AFK entry requires five saved Wins. The main portal and AFK inventory action reject lower totals with an alert, while AFKRuntime checks again before creating a reward session. AFKRuntime otherwise uses the same saved profile through independent copied services. RewardService draws five offers, one per rarity tier in `AFKConfig.Offer`, with amounts/items and displayed chances summing to 100%. It rolls the offer already shown, grants once, then draws the next offer and a fresh 30-60s interval. There is no offline accrual; old clock boosts no longer shorten the interval.

Offers include Cash, Gems, pets, chairs, unopened blocks and eggs. Already-owned chairs convert to configured Cash compensation; eggs grant a weighted pet. WealthScale adjusts AFK Cash/Gems and Cash-only invite payouts. AFKPreviews publishes pool/egg pet models for the authored reward viewports. Session history is separate from the persistent wallet. AFKController orbits the authored map; no scenery generator is active.

## Where to tune

Paths below are relative to `src/`.

| Source | Owns |
| --- | --- |
| `Shared/Config/GameConfig.luau` | Modes, timing, scale limits, camera, match rewards and round-selection exclusions |
| `Server/Config/EconomyConfig.luau` | DataStore, prize roll/prize pool and player XP |
| `Shared/Config/CosmeticCatalog.luau` | Cosmetics, pet levels/abilities, direct egg shops and presentation |
| `Shared/Config/ShopCatalog.luau` | Product/pass IDs, free-mode flags, block prices/odds/designs and potions |
| `Shared/Config/RewardCatalog.luau` | Group, daily/playtime claims and base invitation reward |
| `Shared/Config/ObjectData.luau` + `Server/Config/ObjectMeasurements.luau` | Public object identities + private heights |
| `Client/Controllers/UIStyle.luau` + `ReactionCycle.luau` | Shared UI styling/motion and reaction beats |
| `AFKShared/Config/AFKConfig.luau` + `AFKServer/Config/DataConfig.luau` | AFK offers/assets/timing/place IDs + save settings |
| `Shared/Util/WealthScale.luau` | Reward scaling curves; identical AFKShared copy |

## Owner requirements versus existing code

The cleanup preserved behavior. These are observed discrepancies, not approved replacements for the supplied requirements. Address them only in a gameplay task; read both the current user request and the owning implementation.

| Area | Supplied requirement | Existing source |
| --- | --- | --- |
| Tables | Only 2v2/3v3; reject stale four-seat bindings | LobbySetup registers 4v4 and WorldBindings accepts capacity 4 |
| Voting | End when all have voted; zero votes use Endless | TableService ends early only on unanimity; DefaultMode is Classic |
| Pacing | 35s turns, 6s roll, 3s guess growth, 3s reaction, 1.5s cleanup | Config uses 35s base turns, 7.5s roll, 2s growth, 5s per reaction slot and a 5.2s end sequence; ExtraTime pets add time at turn start |
| Hints | $100 frozen directional clue, broad 20% Close band, <=10s, no answer or overlap charge | MatchService uses free pet/saved Robux credits, sends owner-only Actual and a yellow true-size clone, allows up to four hints, and expires them at the turn deadline |
| Water | Nearest authored RespawnPoint | WaterRespawn searches ancestors for the first matching marker, then spawn fallbacks |
| Followers | One rear arc, up to six pets | PetFollowerController uses up to two rows; VIP supports eight equipped slots |
| Blocks | LuckyBlock1/5/10 designs | ShopCatalog/AFKConfig use Purple/Red/Gold/Grey |
| Watcher effect | Free seven-second Lights Out, one use, no overlap | Ink/Lag/Fog/Wobble paths exist; GameConfig sets three uses and 12-18s base duration, with pet modifiers and turn clamp |
| Voting UI | HUD.Frames.ModeVote with named cards | ModeVoteView requires HUD.Frames.Voting with numbered cards |
| Completion | Completion only after ejection | GameStatesUI also shows an end banner/points before TableService ejects; IDLE carries the finite completion notice |

Other catalog prices, products and perks have evolved: FreeShop/FreeSteal are currently false and product/pass IDs are populated. Do not restore old "free shop" documentation as behavior. The workspace's actual Studio hierarchy and published version still require inspection when a task depends on them.
