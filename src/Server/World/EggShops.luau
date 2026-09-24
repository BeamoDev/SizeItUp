--!strict
-- Binds the authored egg stands in Workspace.Game.Interactables.Eggs; nothing is generated. Each stand is a Model named after its egg
-- (Common, Uncommon, Exquisite) with a Body part and a Tag BillboardGui:
--   Body            gets the E ProximityPrompt (Custom style) that opens that egg's pet shop, and the PetShopId attribute
--   Tag.EggName     the egg's name ("Common Egg"); the client styles it (plain, green shine, cool effects)
--   Tag.MinPrice    the cheapest pet in that egg ("$100", "$1,000"), or only the numeric amount for a shop whose
--                   CosmeticCatalog.PetShops[id].Currency is "Keys" (the Exquisite egg)
-- The model also gets a PetShopId attribute so the client can tell which egg it is.
local EggShops = {}

-- Model name -> CosmeticCatalog.PetShopOrder id. "Equisite" is accepted because that is how the stand may be spelled.
local SHOP_BY_NAME = { Common = "Starter", Uncommon = "Lucky", Exquisite = "Secret", Equisite = "Secret" }

local function money(amount: number): string
	local reversed = string.reverse(tostring(math.floor(amount)))
	local grouped = string.gsub(reversed, "(%d%d%d)", "%1,")
	return "$" .. string.gsub(string.reverse(grouped), "^,", "")
end

-- Cheapest pet price in an egg.
function EggShops.MinPrice(catalog: any, shopId: string): number
	local lowest = math.huge
	for _, id in catalog.PetShops[shopId].Pets do
		local price = catalog.Items.Pets[id].Price
		if price and price < lowest then
			lowest = price
		end
	end
	return lowest
end

-- The MinPrice label text: "$X" for a Cash shop, or just the numeric Gems count for a Keys shop.
function EggShops.MinPriceText(catalog: any, shopId: string): string
	local amount = EggShops.MinPrice(catalog, shopId)
	if catalog.PetShops[shopId].Currency == "Keys" then
		return tostring(math.floor(amount))
	end
	return money(amount)
end

function EggShops.Bind(root: Instance, catalog: any, warn: (string) -> ()): { any }
	local bound, seen = {}, {}
	for _, model in root:GetChildren() do
		if not model:IsA("Model") then
			continue
		end
		local shopId = model:GetAttribute("PetShopId") or SHOP_BY_NAME[model.Name]
		if type(shopId) ~= "string" or not catalog.PetShops[shopId] then
			warn("Egg stand '" .. model.Name .. "' is not one of the egg shops and was ignored.")
		elseif seen[shopId] then
			warn("Egg '" .. shopId .. "' appears twice; ignoring " .. model.Name .. ".")
		else
			local body = model:FindFirstChild("Body")
			if not body or not body:IsA("BasePart") then
				warn("Egg stand '" .. model.Name .. "' needs a Body part for its prompt.")
				continue
			end
			seen[shopId] = true
			local shop = catalog.PetShops[shopId]
			model:SetAttribute("PetShopId", shopId)
			body:SetAttribute("PetShopId", shopId)
			local prompt = body:FindFirstChildWhichIsA("ProximityPrompt")
			if not prompt then
				prompt = Instance.new("ProximityPrompt")
				prompt.Name = "OpenPetShop"
				prompt.Parent = body
			end
			prompt.Style = Enum.ProximityPromptStyle.Custom
			prompt.KeyboardKeyCode, prompt.GamepadKeyCode = Enum.KeyCode.E, Enum.KeyCode.ButtonX
			prompt.HoldDuration, prompt.MaxActivationDistance, prompt.RequiresLineOfSight = 0, 12, false
			prompt.ActionText, prompt.ObjectText = "View", shop.Name
			local tag = model:FindFirstChild("Tag")
			local nameLabel = tag and tag:FindFirstChild("EggName", true)
			local priceLabel = tag and tag:FindFirstChild("MinPrice", true)
			if nameLabel and nameLabel:IsA("TextLabel") then
				nameLabel.Text = shop.Name
			end
			if priceLabel and priceLabel:IsA("TextLabel") then
				priceLabel.Text = EggShops.MinPriceText(catalog, shopId)
			end
			table.insert(bound, { Model = model, Body = body, Prompt = prompt, ShopId = shopId })
		end
	end
	for shopId in catalog.PetShops do
		if not seen[shopId] then
			warn("No authored egg stand found for '" .. shopId .. "'.")
		end
	end
	return bound
end

return EggShops
