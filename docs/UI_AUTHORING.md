# UI authoring

The main client binds the authored `StarterGui.HUD` through AuthoredUI before starting controllers. Keep `HUD.Game`, `HUD.Lobby`, `HUD.Frames` and `HUD.BlackWipe`. The old singular Frame name is accepted for compatibility. Never build a replacement screen to hide a missing-control error.

This is a navigation guide to the binders, not a second copy of every node definition. For exact required descendants, read the owning view's constructor and its reported `Missing authored UI` path. Preserve authored positions, sizes, gradients and resting-pose attributes.

## Gameplay layouts

AuthoredUI selects these layouts in order:

| Detection | Owner | Main controls |
| --- | --- | --- |
| Game.AdjustingSize exists | GameStatesUI | AdjustingSize.Left/Lower/Right/Upper, OtherPlayerGuessing, DamageFlash; optional reveal/end panels |
| Game.Profile or Header.Title/Paragraph exists | GameFrameUI | Header.Title/Paragraph, ScaleSlider.Plus/Minus/Track.Knob, Submit, Hint, View, Reset, InkSplat or LightsOut, DamageFlash |
| Otherwise | AuthoredUI legacy binding + UIController | Existing expanded Game controls; this is not permission to regenerate them |

In the state layout, `AdjustingSize.Upper.Header.Title/Sub` carries messages, Lower owns Submit/TimeLeft and `AdjustingSize.Right.Container` owns `Track`, `Minus` and `Plus`. Track accepts the original held mouse/touch drag and may contain a visual `Knob`; Minus/Plus use the existing smooth, bounded 10% nudges. These controls are enabled only for the local active guesser. OtherPlayerGuessing owns watched-player labels/time and sabotage buttons. `AdjustingSize.Left.Players.P1-P4` owns every live player stat: P1 is always the local client and P2-P4 are the other seated players in local-first order. Each card supplies its own mugshot, username, Hearts.1-3 and points TextLabel; legacy `Left.Hearts` and `Left.Points` are ignored. P1 Hearts.1/2/3 TextLabels are clickable refill controls, with only the next missing heart shown and a newly lost heart delayed until its reaction animation completes. Points and hearts switch by mode. The result reveal also creates a short `ScorePraiseEffect` overlay for scores of 75 or better and removes it with the HUD.

In compact layout, TimeLeft and Profile are optional; Profile stays hidden and Header.Paragraph owns the countdown. Match start hides lobby menus; simply sitting at a table must retain lobby currency/navigation. InventoryController keeps presentation separate from Busy action restrictions.

Paid, saved-credit and pet hints all show the same local exact-size yellow highlighted mystery clone. Existing hint/header labels explain the yellow highlight; do not show Bigger/Smaller/Close advice. The clone uses the shared display scale and mystery floor/left edge, participates in camera framing, and disappears on expiry or leaving the guessing turn. The mystery ruler remains ???m while guessing.

## New-player seat guide

The tutorial seat guide, beam and red arrow are removed. Existing tutorial asset templates are unused; the client does not clone them or run a first-match guidance controller.

Rulers bind under Game.ReferenceSizes when present, otherwise Game. MeasurementUI owns the narrow ruler-repair exception: reuse/repair ReferenceMeasurement and MysteryMeasurement, ObjectName, RealHeight/UnknownHeight/EstimatedHeight, TopCap/BottomCap and HeightDot1-64. The dots render as bold white rounded vertical segments with black outlines; wider outlined caps mark the projected top and floor. ObjectName sits above the measurement, and a result PlayerMugshot sits below that text before the top cap. The entire ruler layer uses ZIndex 0 so authored HUD panels always cover it; it does not move to avoid those panels. Caption and marker sizes scale down from the live viewport on phones, stay clamped inside the screen top/side edges, and only the two ruler caption stacks attempt to separate from each other. Use public names and post-camera projection; follow phase privacy rules in AGENTS. Do not rebuild other deleted gameplay panels.

## Menus and templates

Paths below start at HUD unless stated otherwise.

| Feature | Authored root / assets | Binder |
| --- | --- | --- |
| Lobby navigation/currency | Lobby.left/right/Lower/Upper/CurrencyDisplay | LobbyHUDView |
| Inventory | Frames.Inventory; ReplicatedStorage.Assets.UI.PetChairTemplate and TitleTemplate | InventoryFrameView |
| Profile / rewards / store | Frames.Profile, Rewards, Store | ProfileFrameView, RewardsFrameView, StoreFrameView |
| Egg shops | Frames.Eggs.Frame.Body.Selected and Slot1-6; Frame.Header | EggShopView |
| Lucky blocks | Frames.LuckyBlocks.Arrows/Lower/Upper; Assets.UI.PetLuckyBlockTemp | LuckyBlockView |
| Older block showroom | Frames.BlockPreview.Showroom (or BlockPreview itself) | BlockPreviewView / AuthoredBlockCards |
| Hatch | Frames.HatchReveal; HatchContainer selects the grid variant | HatchController / HatchGridController |
| Voting in current code | Frames.Voting.Frame.Header.TextLabel; Container.1-4 with ModeName/ModeInfo/VotingList; Assets.UI.VoteTemplate | ModeVoteView |
| Friend invite | Lobby.Upper.InviteFrame with OnlineMessage, portrait, reward, InviteButton, Close | FriendInviteView |
| Active potions | Lobby.Potions.Template | PotionHUDView |
| Nearby player | ReplicatedStorage.Assets.UI.PlayerDetails, with Details/Steal buttons | PlayerDetailsController |
| World tags | ReplicatedStorage.Assets.UI.HeadTag and CashTag | CosmeticDisplay |
| Owner bot marker | ReplicatedStorage.Assets.UI.BotTag | Server bot spawners + BotTagController; disabled by default, visible only to user 1790165114 |

InventoryView chooses LuckyBlockView when LuckyBlocks exists, otherwise the older showroom. Preserve that fallback until actual Studio usage is checked. Missing optional menus are unavailable; don't recreate the removed Lobby.Panel screen system.

Egg slots retain their authored appearance and viewports. Selected owns Level, ItemName (ability), Icon, Buy, Equip, Unequip and rarity strokes. Bind existing slots; purchases/equipment come from the server.

Repeated cards may reuse existing cards or clone authored templates. The older binder accepts a Templates folder, a UITemplate attribute or a named sibling template. Approved content filling is limited to existing Lobby.Panel.Body/Tabs/InventoryTools and BlockPreview.Showroom.PetOdds: generated children use FilledUI and are reused. This exception does not authorize a new shell. Four block odds slots remain stable while browsing.

Viewport cameras, WorldModels, preview stages and selected/reward clones are runtime dependencies, not mandatory authored screen controls. Reuse them idempotently, preserve unrelated viewport scenery, strip cloned scripts and destroy only owned geometry. Blocks use ShopCatalog.BlockPreviewModels; pet labels use CosmeticCatalog.PetDisplayName.

## Motion and cleanup

GameHUDMotion owns gameplay panel entrances/exits; LobbyHUDView owns lobby motion; FrameSlide handles menu roots; TransitionController owns BlackWipe. Respect motion ownership attributes to avoid competing animations. Disable input immediately on exit, hide roots when exits finish, and restore resting poses on teardown. Repeated snapshots use server-relative ages and must not restart reveals/reactions/effects.

OtherPlayerGuessing's authored sabotage buttons reuse HintWobble for one random shake/pop at a time while purchasing is available. MatchController owns this selection in its existing render loop and resets each button on disable/teardown. Existing gameplay controls named Exit/ExitButton/Leave/LeaveButton can request the same eliminated-spectator departure as Jump; no exit control is generated. The server confirms departure before the client clears the match presentation.

Keep short player-facing messages, existing gradients, rarity colors and template labels. Level-only updates change labels/XP fills without rebuilding viewports. Clear hover/drag/effects on lock, deadline, focus loss, menu opening, respawn and teardown. World billboards and local models are separate from the authored screen hierarchy; preserve source templates and destroy only controller-owned copies.

## AFK HUD

AFKView binds StarterGui.HUD.AFK independently of AuthoredUI:

- Left.RewardsEarnt.1-15: newest-first history cards with ImageLabel/TextLabel and optional authored viewports.
- Right.Container.Reward1-5: the five server-drawn offers, each with ImageLabel/TextLabel/Chance and optional viewports.
- Lower.Frame.ProgressBar, Lower.RewardNext and Lower.Return: server countdown and return action.
- Upper.UpperTitle.LowerTitle: the nested title labels animated by the view.

Reward previews reuse authored viewports and retry missing replicated assets. AFKView owns its travel overlay; the main place uses LoadingController while Traveling. Failures must restore the HUD, camera and controls.
