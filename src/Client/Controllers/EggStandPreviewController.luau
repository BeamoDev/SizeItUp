--!strict
-- Each egg stand's CyclePets (a Gui on the stand, anywhere under it) shows a live preview: CyclePets.Frame.RewardViewport
-- holds one pet from that egg's own loot pool at a time -- always a real member of it, in order -- spinning continuously
-- and cycling to the next pet every few seconds; CyclePets.Frame.sunburst (if present) turns slowly behind it. Purely
-- visual and entirely client-local: nothing here is sent to the server or changes which pets exist or their odds.
local Style = require(script.Parent.UIStyle)
local Cycle = {}
Cycle.__index = Cycle

local CYCLE_SECONDS = 4 -- how long each pet stays before the next one in the pool shows
local SUNBURST_DEGREES_PER_SECOND = 4
local RESCAN_SECONDS = 2 -- how often newly streamed-in stands are picked up

-- Model name -> CosmeticCatalog.PetShopOrder id, mirroring EggShops.luau's own fallback (an authored PetShopId wins).
local SHOP_BY_NAME = { Common = "Starter", Uncommon = "Lucky", Exquisite = "Secret", Equisite = "Secret" }

local function shopIdFor(model: Instance, catalog: any): string?
	local id = model:GetAttribute("PetShopId")
	if type(id) == "string" and catalog.PetShops[id] then
		return id
	end
	return SHOP_BY_NAME[model.Name]
end

local function setupViewport(viewport: ViewportFrame)
	local camera = viewport:FindFirstChild("PreviewCamera")
	if not camera then
		camera = Instance.new("Camera")
		camera.Name, camera.FieldOfView = "PreviewCamera", 38
		camera.CFrame = CFrame.lookAt(Vector3.new(3, 2, 5), Vector3.zero)
		camera.Parent = viewport
	end
	(viewport :: any).CurrentCamera = camera
	viewport.Ambient, viewport.LightColor = Color3.new(0.7, 0.7, 0.7), Color3.new(1, 1, 1)
end

local function registerHover(model: Instance, age: number, phase: number)
	local body = model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		-- Anchored so this script's per-frame CFrame set is the only thing moving the part: on an unanchored part
		-- gravity/physics fights a scripted CFrame every step, which is what made the hover/turn look jittery.
		if not body.Anchored then body.Anchored = true end
		local origin = model:GetAttribute("_HoverBodyCFrame")
		if origin == nil then
			model:SetAttribute("_HoverBodyCFrame", body.CFrame)
			origin = body.CFrame
		end
		body.CFrame = CFrame.new(
			origin.Position.X,
			origin.Position.Y + math.sin(age * 1.2 + phase) * 0.15,
			origin.Position.Z
		) * CFrame.Angles(0, age * 0.28 + phase, 0)
	end
	local object = model:FindFirstChild("Object_0.001")
	if object and object:IsA("BasePart") then
		if not object.Anchored then object.Anchored = true end
		local origin = model:GetAttribute("_HoverObjectCFrame")
		if origin == nil then
			model:SetAttribute("_HoverObjectCFrame", object.CFrame)
			origin = object.CFrame
		end
		object.CFrame = CFrame.new(
			origin.Position.X,
			origin.Position.Y + math.sin(age * 1.1 + phase + 0.7) * 0.12,
			origin.Position.Z
		) * CFrame.Angles(0, age * 0.22 + phase + 0.5, 0)
	end
end

local function resolvePetAssetId(pet: any): string?
	if not pet then
		return nil
	end
	if type(pet) == "string" then
		return pet
	end
	if type(pet.AssetId) == "string" and pet.AssetId ~= "" then
		return pet.AssetId
	end
	if type(pet.Id) == "string" and pet.Id ~= "" then
		return pet.Id
	end
	if type(pet.Name) == "string" and pet.Name ~= "" then
		return pet.Name
	end
	return nil
end

local function showPet(viewport: ViewportFrame, pet: any)
	for _, child in viewport:GetChildren() do
		if child.Name == "PetModel" or child:IsA("Model") then
			child:Destroy()
		end
	end
	if not pet then
		return
	end
	local assetId = resolvePetAssetId(pet)
	if assetId and Style.PetVisual and Style.PetModels and Style.PetModels:FindFirstChild(assetId) then
		Style.PetVisual.Create(Style.PetModels, assetId, viewport, 2.3, pet)
		return
	end
	if assetId then
		warn(
			"[EggStandPreview] missing pet model for asset "
				.. tostring(assetId)
				.. " in viewport "
				.. tostring(viewport.Name)
		)
	else
		warn("[EggStandPreview] no valid pet asset id for viewport " .. tostring(viewport.Name))
	end
end

local function nextPetId(stand: any): any
	local shop = stand.Shop
	if not shop or #shop.Pets == 0 then
		return nil
	end
	for index = 1, #shop.Pets do
		local candidateIndex = ((stand.Index + index - 1) % #shop.Pets) + 1
		local candidate = shop.Pets[candidateIndex]
		local pet = stand.Catalog.Items.Pets[candidate]
		local assetId = resolvePetAssetId(pet)
		-- PetLibrary publishes only assets that exist and normalize successfully. Missing release pets are disabled on
		-- the server, so the decorative stand must skip them instead of repeatedly selecting an impossible preview.
		if pet and assetId and Style.PetModels and Style.PetModels:FindFirstChild(assetId) then
			stand.Index = candidateIndex
			return pet
		end
	end
	return nil
end

function Cycle.new(world: Instance, runService: any, catalog: any)
	-- Stands is a plain array (not a dict keyed by Instance): Lune's Roblox polyfill can hand back a freshly
	-- wrapped reference to the same instance from a later GetChildren() call, which does not reliably match an
	-- Instance used earlier as a table key even though == says they're equal. An array checked with == is safe
	-- in both Lune and real Roblox and avoids re-adding (and thereby resetting) an already-tracked stand.
	local self: any = setmetatable({ World = world, Catalog = catalog, Stands = {}, Rescan = 0, Age = 0 }, Cycle)
	self.Connection = runService.RenderStepped:Connect(function(dt: number)
		self:Step(dt)
	end)
	return self
end

function Cycle.Tracking(self: any, model: Instance): boolean
	for _, stand in self.Stands do
		if stand.Model == model then
			return true
		end
	end
	return false
end

-- (Re)scans Workspace.Game.Interactables.Eggs for stands with a usable CyclePets.Frame.RewardViewport; already-found stands are skipped.
function Cycle.Find(self: any)
	local game = self.World:FindFirstChild("Game")
	local interactables = game and game:FindFirstChild("Interactables")
	local eggs = (interactables and interactables:FindFirstChild("Eggs")) or (game and game:FindFirstChild("Eggs"))
	if not eggs then
		return
	end
	for _, model in eggs:GetChildren() do
		if model:IsA("Model") and not self:Tracking(model) then
			local shopId = shopIdFor(model, self.Catalog)
			local shop = shopId and self.Catalog.PetShops[shopId]
			local cyclePets = model:FindFirstChild("CyclePets", true)
			local frame = cyclePets and cyclePets:FindFirstChild("Frame")
			local viewport = frame and frame:FindFirstChild("RewardViewport")
			if shop and #shop.Pets > 0 and viewport and viewport:IsA("ViewportFrame") then
				setupViewport(viewport)
				local stand = {
					Model = model,
					Shop = shop,
					Catalog = self.Catalog,
					Viewport = viewport,
					Sunburst = frame:FindFirstChild("sunburst"),
					Index = 0,
					Timer = 0,
				}
				local pet = nextPetId(stand)
				if pet then
					showPet(stand.Viewport, pet)
				else
					warn(
						"[EggStandPreview] no workbench pets found for stand "
							.. tostring(model:GetFullName())
							.. " shop "
							.. tostring(shopId)
					)
				end
				table.insert(self.Stands, stand)
			end
		end
	end
end

function Cycle.Step(self: any, dt: number)
	dt = math.max(0, dt)
	self.Age += dt
	self.Rescan -= dt
	if self.Rescan <= 0 then
		self.Rescan = RESCAN_SECONDS
		self:Find()
	end
	for i = #self.Stands, 1, -1 do
		local stand = self.Stands[i]
		if not stand.Model.Parent or not stand.Viewport.Parent then
			table.remove(self.Stands, i)
			continue
		end
		stand.Timer -= dt
		if stand.Timer <= 0 then
			stand.Timer = CYCLE_SECONDS
			local pet = nextPetId(stand)
			if pet then
				showPet(stand.Viewport, pet)
			end
		end
		Style.RotatePetPreview(stand.Viewport, self.Age)
		registerHover(stand.Model, self.Age, (stand.Index or 0) * 0.75)
		if stand.Sunburst and stand.Sunburst:IsA("ImageLabel") then
			stand.Sunburst.Rotation = (self.Age * SUNBURST_DEGREES_PER_SECOND) % 360
		end
	end
end

function Cycle.Destroy(self: any)
	self.Connection:Disconnect()
	table.clear(self.Stands)
end

return Cycle
