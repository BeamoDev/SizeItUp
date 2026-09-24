--!strict
-- Normalize only the local display clone; keep authored colours, meshes and textures.
local BlockVisual={}
function BlockVisual.Create(source: Instance, parent: Instance): Model?
	if not source:IsA("Model") and not source:IsA("BasePart") then return nil end
	local copy=source:Clone()
	if not copy then return nil end
	local model=Instance.new("Model");model.Name="SelectedBlock"
	copy.Parent=model
	local low,high=Vector3.new(math.huge,math.huge,math.huge),Vector3.new(-math.huge,-math.huge,-math.huge)
	local count=0
	for _,node in model:GetDescendants() do
		if node:IsA("LuaSourceContainer") then node:Destroy()
		elseif node:IsA("BasePart") then
			node.Anchored,node.CanCollide,node.CanTouch,node.CanQuery=true,false,false,false
			local visible=node.Transparency<1
			for _,child in node:GetChildren() do
				if (child:IsA("Decal") or child:IsA("Texture")) and child.Transparency<1 then visible=true end
			end
			if visible then
				count+=1
				for _,x in {-0.5,0.5} do for _,y in {-0.5,0.5} do for _,z in {-0.5,0.5} do
					local point=node.CFrame:PointToWorldSpace(node.Size*Vector3.new(x,y,z))
					low=Vector3.new(math.min(low.X,point.X),math.min(low.Y,point.Y),math.min(low.Z,point.Z))
					high=Vector3.new(math.max(high.X,point.X),math.max(high.Y,point.Y),math.max(high.Z,point.Z))
				end end end
			end
		end
	end
	if count==0 then model:Destroy();return nil end
	local size=high-low
	model.WorldPivot=CFrame.new((low+high)*0.5)
	model:PivotTo(CFrame.new())
	model:ScaleTo(3/math.max(size.X,size.Y,size.Z,0.001))
	model:SetAttribute("LuckyBlockAsset",source.Name)
	model.Parent=parent
	return model
end
return BlockVisual
