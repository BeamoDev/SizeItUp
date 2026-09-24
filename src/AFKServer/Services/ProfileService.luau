--!strict
-- One leased document per player. Serialize writes; never save a load-failure default.
local ProfileService = {}
ProfileService.__index = ProfileService
function ProfileService.new(store: any, schema: any, catalog: any, config: any, adapters: any)
	return setmetatable({ Store = store, Schema = schema, Catalog = catalog, Config = config, A = adapters, Entries = {}, Loading = {} }, ProfileService)
end
function ProfileService.Load(self: any, userId: number)
	local deadline = self.A.Now() + 24
	while (self.Loading[userId] or (self.Entries[userId] and self.Entries[userId].Closing)) and self.A.Now() < deadline do self.A.Wait(0.1) end
	if self.Entries[userId] then return self:Get(userId) end
	if self.Loading[userId] then return nil end
	self.Loading[userId] = true
	local acquired
	for attempt = 1, 4 do
		local now = self.A.Now()
		local ok, value = pcall(function()
			return self.Store:UpdateAsync("Player_" .. userId, function(old)
				local checkedNow = self.A.Now()
				if old and old.Lock and old.Lock.Id ~= self.A.JobId and old.Lock.Expires > checkedNow then return nil end
				return { Data = self.Schema.Reconcile(old and old.Data, self.Catalog), Lock = { Id = self.A.JobId, Expires = checkedNow + self.Config.LeaseSeconds } }
			end)
		end)
		if ok and value and value.Lock.Id == self.A.JobId then acquired = value; break end
		if attempt < 4 then self.A.Wait(attempt) end
	end
	self.Loading[userId] = nil
	if not acquired then return nil end
	self.Entries[userId] = { Data = acquired.Data, Expires = acquired.Lock.Expires, LastSave = self.A.Now(), Busy = false, Closing = false }
	return acquired.Data
end
function ProfileService.Get(self: any, userId: number)
	local entry = self.Entries[userId]
	return if entry and not entry.Closing and not entry.Lost and entry.Expires > self.A.Now() + 5 then entry.Data else nil
end
function ProfileService.Save(self: any, userId: number, release: boolean?): boolean
	local entry = self.Entries[userId]
	if not entry or entry.Lost then return false end
	local deadline = self.A.Now() + 24
	while entry.Busy and self.A.Now() < deadline do self.A.Wait(0.1) end
	if entry.Busy or self.Entries[userId] ~= entry then return false end
	entry.Busy = true
	if release then entry.Closing = true end
	local saved = false
	for attempt = 1, 3 do
		local now = self.A.Now()
		local copy = self.Schema.Copy(entry.Data)
		local ok, value = pcall(function()
			return self.Store:UpdateAsync("Player_" .. userId, function(old)
				local checkedNow = self.A.Now()
				if not old or not old.Lock or old.Lock.Id ~= self.A.JobId or old.Lock.Expires <= checkedNow then return nil end
				return { Data = copy, Lock = if release then nil else { Id = self.A.JobId, Expires = checkedNow + self.Config.LeaseSeconds } }
			end)
		end)
		if ok and value then
			saved, entry.LastSave, entry.Expires = true, self.A.Now(), if value.Lock then value.Lock.Expires else self.A.Now(); break
		elseif ok then entry.Lost = true; break end
		if attempt < 3 then self.A.Wait(attempt) end
	end
	entry.Busy = false
	if saved and release then self.Entries[userId] = nil end
	if not saved and (entry.Lost or entry.Expires <= self.A.Now() + 10) then entry.Lost = true; self.A.Lost(userId) end
	return saved
end
return ProfileService
