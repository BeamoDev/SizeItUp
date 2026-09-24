--!strict
-- Pure display timing, always derived from the server's scored round.
local Reveal = {}
function Reveal.SizeCaption(name: string, meters: number?): string
	if not meters then return name end
	return name..": "..string.format("%.2f",meters).."m"
end
function Reveal.Order(results: any,ownId: number?)
	local ordered=table.clone(results or {})
	for index,entry in ordered do if entry.UserId==ownId then table.remove(ordered,index);table.insert(ordered,1,entry);break end end
	return ordered
end
function Reveal.Sequence(age: number,config: any,count: number)
	local appear=math.clamp((age-config.ResultReferenceSeconds)/config.ResultActualAppearSeconds,0,1)
	-- The real-size object grows up from the ground over its appearance and hold, like the guesses do.
	local grow=math.clamp((age-config.ResultReferenceSeconds)/(config.ResultActualAppearSeconds+config.ResultActualHoldSeconds),0,1)
	local greyAt=config.ResultReferenceSeconds+config.ResultActualAppearSeconds+config.ResultActualHoldSeconds
	local grey=math.clamp((age-greyAt)/config.ResultGreyFadeSeconds,0,1)
	local intro=config.RevealIntroSeconds()
	local rawIndex=math.floor(math.max(0,age-intro)/config.RevealSlotSeconds())+1
	local index=math.min(math.max(1,count),rawIndex)
	local slotAge=age-intro-(index-1)*config.RevealSlotSeconds()
	local growth=math.clamp((slotAge-config.ResultAnnounceSeconds)/config.ResultGrowSeconds,0,1)
	local fadeAt=config.ResultAnnounceSeconds+config.ResultGrowSeconds+config.ResultGuessHoldSeconds
	-- Every guess (the last too) fades out completely after its hold, leaving only its outline.
	local opacity=1-math.clamp((slotAge-fadeAt)/config.ResultGuessFadeSeconds,0,1)
	return {Phase=if age<config.ResultReferenceSeconds then "REFERENCE" elseif age<intro then "ACTUAL" else "GUESS",
		ActualAlpha=appear,ActualGrow=grow,Grey=grey,Index=if age>=intro and count>0 then index else nil,Growth=growth,Opacity=opacity,SlotAge=slotAge}
end
function Reveal.Evaluate(snapshot: any, now: number, config: any)
	local scored=snapshot.Reveal
	if not scored then return nil end
	local ordered=Reveal.Order(scored.Results,snapshot.YourUserId)
	local start=scored.StartedAt or ((snapshot.Deadline or now)-config.RevealDuration(if #ordered>0 then #ordered else 2))
	local age=math.max(0,now-start)
	local progress=math.clamp(age/config.AccuracyCountSeconds,0,1)
	local accuracy=math.clamp(math.floor((scored.YourAccuracy or 0)+(if scored.Mode=="Endless" then 1e-7 else 0.5)),0,100)
	local percent=if progress>=1 then accuracy else math.min(math.max(0,accuracy-1),math.floor(accuracy*(1-(1-progress)^2)))
	local phase=if snapshot.State=="ROUND_REVEAL" and age<config.AccuracyCountSeconds+config.AccuracySettleSeconds then "COUNT" elseif snapshot.State=="ROUND_REVEAL" and age>=config.AccuracyCountSeconds+config.AccuracySettleSeconds+config.ResultHoldSeconds then "SIZE" else "RESULT"
	local lost=scored.Result=="ROUND LOST!"
	local hearts=scored.YourHeartsAfter
	if hearts==nil then hearts=math.max(0,(snapshot.YourHearts or 0)-(if lost and not snapshot.HeartAppliedAt then 1 else 0)) end
	local outcome=if lost then "LOST" elseif scored.Result=="TIE!" then "TIE" elseif snapshot.Eliminated then "SPECTATING" else "WON"
	local message=if outcome=="WON" then "YOU WON" elseif outcome=="LOST" then "YOU LOST\n("..hearts.." HEARTS REMAINING)" elseif outcome=="TIE" then "TIE — NO HEARTS LOST" else "SPECTATING"
	if not snapshot.HeartAppliedAt then
		hearts=snapshot.YourHearts or hearts
		if outcome=="LOST" then message="YOU LOST" end
	end
	if scored.Mode == "Endless" then
		local own = scored.YourOutcome
		outcome = if not own then "SPECTATING" elseif not own.Passed then "LOST" elseif own.HeartDelta > 0 then "HEALED" else "SAFE"
		message = if outcome == "SPECTATING" then "SPECTATING" elseif outcome == "LOST" then "-1 HEART / "..hearts.." LEFT" elseif outcome == "HEALED" then "+1 HEART / THREE GREAT GUESSES!" else "SAFE / NO HEART LOST"
		if not snapshot.HeartAppliedAt then
			message=if outcome=="SPECTATING" then "SPECTATING" elseif outcome=="LOST" then "BELOW TARGET" elseif outcome=="HEALED" then "GREAT GUESS STREAK!" else "TARGET REACHED!"
		end
		message ..= "\nTARGET: "..scored.RequiredAccuracy.."%"
	end
	if scored.Mode=="BestOfFive" then message="TOTAL: "..string.format("%.1f",snapshot.TotalAccuracy or 0).." POINTS";outcome="SAFE" end
	local sequence=Reveal.Sequence(age,config,#ordered)
	local entry=sequence.Index and ordered[sequence.Index]
	sequence.Caption=if entry then (if entry.UserId==snapshot.YourUserId then "YOUR GUESS" else string.upper(entry.Name or "PLAYER "..sequence.Index).."'S GUESS") elseif sequence.Phase=="REFERENCE" then "Compare with this!" else Reveal.SizeCaption(if snapshot.Target then snapshot.Target.DisplayName else "Mystery object",scored.Actual)
	return {RequiredAccuracy=scored.RequiredAccuracy,Sequence=sequence,Phase=phase,Percent=percent,Accuracy=accuracy,Progress=progress,Age=age,Outcome=outcome,Hearts=hearts,Text=if phase=="COUNT" then "Accuracy: "..percent.." / 100" else message}
end
return Reveal
