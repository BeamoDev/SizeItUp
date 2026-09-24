--!strict
-- Server-owned motion for chairs with a Float mesh (the Void): the authored Float turns and bobs. The chair's
-- authored colours, materials, transparency, textures, lights and particles are never changed or supplemented here.
local ChairFx = {}
ChairFx.__index = ChairFx

local TURN_SECONDS = 14
local BOB_STUDS, BOB_SECONDS = 0.35, 3.2

local function firstPart(item: Instance): BasePart?
	if item:IsA("BasePart") then return item end
	if item:IsA("Model") and item.PrimaryPart then return item.PrimaryPart end
	return item:FindFirstChildWhichIsA("BasePart", true)
end

function ChairFx.new()
	return setmetatable({ Entries = {}, Clock = 0, Count = 0 }, ChairFx)
end

-- Starts animating a chair model (its Float mesh must be anchored, as chair models are).
function ChairFx.Add(self: any, model: Instance)
	if self.Entries[model] then return end
	local float = model:FindFirstChild("Float", true)
	local floatPart = if float then firstPart(float) else nil
	self.Count += 1
	self.Entries[model] = { Float = floatPart, Base = if floatPart then floatPart.CFrame else nil, Phase = self.Count * 0.7 }
end

function ChairFx.Remove(self: any, model: Instance)
	local entry = self.Entries[model]
	if not entry then return end
	self.Entries[model] = nil
	if entry.Float and entry.Float.Parent and entry.Base then entry.Float.CFrame = entry.Base end
end

-- Turns and bobs every Float mesh, every single Heartbeat: an anchored part's CFrame never interpolates on the
-- client, so throttling this (like the rest of the server's batched tick) would show up as visible stepping.
function ChairFx.Step(self: any, dt: number)
	self.Clock += dt
	for model, entry in self.Entries do
		local float = entry.Float
		if not model.Parent then self:Remove(model);continue end
		if not float or not float.Parent or not entry.Base then continue end
		local turn = (self.Clock / TURN_SECONDS) * math.pi * 2
		local bob = math.sin((self.Clock + entry.Phase) / BOB_SECONDS * math.pi * 2) * BOB_STUDS
		float.CFrame = CFrame.new(0, bob, 0) * entry.Base * CFrame.Angles(0, turn, 0)
	end
end

function ChairFx.Destroy(self: any)
	for model in table.clone(self.Entries) do self:Remove(model) end
end

return ChairFx
