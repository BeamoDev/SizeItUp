--!strict
local ScaleMath = {}
function ScaleMath.IsFinite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
function ScaleMath.IsGuess(value: any, minimum: number, maximum: number): boolean
	return ScaleMath.IsFinite(value) and value >= minimum and value <= maximum
end
function ScaleMath.FromAlpha(alpha: number, minimum: number, maximum: number): number
	return minimum * (maximum / minimum) ^ math.clamp(alpha, 0, 1)
end
function ScaleMath.ToAlpha(value: number, minimum: number, maximum: number): number
	return math.clamp(math.log(value / minimum) / math.log(maximum / minimum), 0, 1)
end
function ScaleMath.Error(guess: number, actual: number): number
	return math.abs(guess - actual) / actual
end
function ScaleMath.Accuracy(errorValue: number): number
	return math.clamp(1 - errorValue, 0, 1) * 100
end
-- "Snap and juice" feedback only: round-number sizes (1, 2 and 5 times each power of ten) within [minimum,maximum], plus
-- the reference height when it also falls in range. Sorted ascending and de-duplicated. Crossing one of these while
-- dragging plays a distinct cue -- it never snaps or changes the dragged Value itself.
function ScaleMath.Landmarks(minimum: number, maximum: number, referenceMeters: number?): {number}
	local seen, list = {}, {}
	local function add(value: number)
		if value < minimum or value > maximum then return end
		local key = math.floor(value * 1000 + 0.5)
		if seen[key] then return end
		seen[key] = true
		table.insert(list, value)
	end
	if referenceMeters and ScaleMath.IsFinite(referenceMeters) and referenceMeters > 0 then add(referenceMeters) end
	local exponent = math.floor(math.log(minimum, 10)) - 1
	while 10 ^ exponent <= maximum do
		for _, step in { 1, 2, 5 } do add(step * 10 ^ exponent) end
		exponent += 1
	end
	table.sort(list)
	return list
end
-- Critically damped motion in log space: ease velocity as well as size. Bounded
-- substeps make sparse input/render updates behave like high-refresh dragging.
function ScaleMath.SmoothApproach(current: number,target: number,velocity: number?,dt: number,config: any): (number,number)
	local speed=velocity or 0
	if not ScaleMath.IsFinite(dt) or dt<=0 then return current,speed end
	if current==target then return target,0 end
	local elapsed=math.min(dt,config.ScaleMaximumFrameSeconds)
	local steps=math.max(1,math.ceil(elapsed*240));local h=elapsed/steps
	local omega=config.ScaleSmoothSpeed
	local limit=math.log(2)*config.ScaleMaxOctavesPerSecond
	local decay=math.exp(-omega*h)
	local value=current
	for _=1,steps do
		local delta=math.log(target/value)
		if math.abs(delta)<=math.min(0.00001,limit*h) then return target,0 end
		-- A reversal must not keep moving in the old direction.
		if speed*delta<0 then speed=0 end
		local change=math.clamp(-delta,-2*limit/omega,2*limit/omega)
		local temp=(speed+omega*change)*h
		local step=math.clamp(-change+(change+temp)*decay,-limit*h,limit*h)
		speed=math.clamp((speed-omega*temp)*decay,-limit,limit)
		local nextValue=math.clamp(value*math.exp(step),math.min(value,target),math.max(value,target))
		if nextValue==target then return target,0 end
		value=nextValue
	end
	return value,speed
end
return table.freeze(ScaleMath)
