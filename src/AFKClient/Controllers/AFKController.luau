--!strict
-- Drives the AFK screen: forwards server packets to the authored HUD.AFK view, sends the Return request and slowly
-- orbits the camera around the normal authored map (no special wrapper model). An optional BasePart named Camera,
-- anywhere in the map, sets where the orbit starts and which way it looks: the orbit centre is a point straight
-- ahead of it (its OrbitDistance attribute, 250 studs by default) and the camera keeps the same distance and height
-- while circling. Without that part it circles low over the middle of the whole map instead.
local Controller = {}
Controller.__index = Controller
local ORBIT_SECONDS = 140 -- one full lap
local DEFAULT_DISTANCE, FALLBACK_RADIUS, FALLBACK_HEIGHT = 250, 140, 35
-- A plain child-by-child search, not FindFirstChild(name, true): Workspace's own render Camera instance is also
-- named "Camera" (and typically a direct child), but it is not a BasePart, so this keeps looking past it for the
-- authored orbit marker instead of stopping on the first same-named match.
local function findMarker(root: Instance): BasePart?
	for _, child in root:GetChildren() do
		if child.Name == "Camera" and child:IsA("BasePart") then
			return child :: BasePart
		end
		local found = findMarker(child)
		if found then
			return found
		end
	end
	return nil
end

function Controller.new(d: any)
	local self: any=setmetatable({D=d,Connections={},LastReturn=-math.huge,Time=0},Controller)
	self.View=d.View.new(d.Player:WaitForChild("PlayerGui"),d.Config,d.Storage,d.Catalog)
	self.View.Lighting=d.Lighting -- the travel loading screen blurs the world
	local function connect(signal,callback) table.insert(self.Connections,signal:Connect(callback)) end
	connect(d.Remote.OnClientEvent,function(packet)
		-- A new reward arrived (the sequence went up, not the first packet): play the reward sound.
		if type(packet)=="table" and packet.Ready and type(packet.Sequence)=="number" then
			if self.Sequence and packet.Sequence>self.Sequence then self:Sound(d.Config.RewardSounds) end
			self.Sequence=packet.Sequence
		end
		self.View:Receive(packet)
	end)
	connect(self.View.Return.Activated,function()
		local now=d.World:GetServerTimeNow()
		if not self.View.Traveling and now-self.LastReturn>=1 then self.LastReturn=now;d.Remote:FireServer("Return") end
	end)
	connect(d.RunService.RenderStepped,function(dt)
		local step=dt or 1/60
		local camera=d.World.CurrentCamera
		if camera then
			if camera~=self.Camera then
				self:RestoreCamera();self.Camera=camera
				self.Saved={Type=camera.CameraType,CFrame=camera.CFrame,FOV=camera.FieldOfView}
			end
			self:Orbit(camera,step)
		end
		local now=d.World:GetServerTimeNow()
		self.View:Step(now,step)
		-- A tick every second of the countdown to the next reward.
		local state=self.View.State
		if state and not self.View.Traveling and state.NextReward then
			local second=math.ceil(math.max(0,state.NextReward-now))
			if self.TickSecond and second~=self.TickSecond and second>0 then self:Sound(d.Config.TickSounds) end
			self.TickSecond=second
		end
	end)
	d.Remote:FireServer("Ready")
	return self
end
-- Plays the first of these SoundService.SFX sounds that exists, at AFKConfig.SoundVolume of its authored volume
-- (a clone, so the authored sound is never changed).
function Controller.Sound(self: any,names: {string}?)
	local folder=self.D.Sounds
	if not folder or not names then return end
	for _,name in names do
		local sound=folder:FindFirstChild(name)
		if sound and sound:IsA("Sound") then
			local copy=sound:Clone()
			copy.Looped=false
			copy.Volume=sound.Volume*(self.D.Config.SoundVolume or 1)
			copy.Parent=folder.Parent or folder
			copy:Play()
			local function cleanup() if copy.Parent then copy:Destroy() end end
			copy.Ended:Connect(cleanup)
			-- Ended is not guaranteed for an asset that fails to load, so keep sound clones strictly bounded.
			task.delay(math.max(copy.TimeLength, 2) + 1, cleanup)
			return
		end
	end
end
-- Works out the orbit (centre, radius, height, starting angle) once the map is available.
function Controller.Plan(self: any): any?
	if self.Path then return self.Path end
	local world=self.D.World
	local marker=findMarker(world)
	local path
	if marker then
		local distance=marker:GetAttribute("OrbitDistance") or DEFAULT_DISTANCE
		local origin=marker.CFrame.Position
		local centre=origin+marker.CFrame.LookVector*distance
		local flat=Vector3.new(origin.X-centre.X,0,origin.Z-centre.Z)
		path={Centre=centre,Radius=math.max(1,flat.Magnitude),Height=origin.Y-centre.Y,Start=math.atan2(flat.Z,flat.X)}
	else
		-- The bounding-box centre (not GetPivot, which can sit anywhere depending on part order) keeps this
		-- fallback lap low over the middle of the actual map instead of high above an arbitrary pivot point. A
		-- near-empty box means the map has not streamed in yet: try again next frame instead of caching that.
		local cf,size=world:GetBoundingBox()
		if size.Magnitude<10 then return nil end
		path={Centre=cf.Position,Radius=FALLBACK_RADIUS,Height=FALLBACK_HEIGHT,Start=0}
	end
	self.Path=path
	return path
end
function Controller.Orbit(self: any,camera: Camera,dt: number)
	local path=self:Plan()
	if not path then return end
	self.Time+=dt
	local angle=path.Start+self.Time*(math.pi*2/ORBIT_SECONDS)
	local position=path.Centre+Vector3.new(math.cos(angle)*path.Radius,path.Height,math.sin(angle)*path.Radius)
	camera.CameraType=Enum.CameraType.Scriptable
	camera.CFrame=CFrame.lookAt(position,path.Centre)
	camera.FieldOfView=70
end
function Controller.RestoreCamera(self: any)
	if self.Camera and self.Saved then self.Camera.CameraType=self.Saved.Type;self.Camera.CFrame=self.Saved.CFrame;self.Camera.FieldOfView=self.Saved.FOV end
end
function Controller.Destroy(self: any)
	for _,connection in self.Connections do connection:Disconnect() end
	self:RestoreCamera();self.View:Destroy()
end
return Controller
