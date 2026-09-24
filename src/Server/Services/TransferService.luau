--!strict
-- Resumable debit-then-credit journal. Never credit an unsaved target debit.
local TransferService = {}
TransferService.__index = TransferService
function TransferService.new(profiles: any, newId: any, isOnline: any?, callbacks: any?)
	return setmetatable({ Profiles = profiles, NewId = newId, Busy = {}, Notified = {}, Callbacks = callbacks or {}, IsOnline = isOnline or function() return false end }, TransferService)
end
function TransferService.Run(self: any, buyerId: number, targetId: number?, free: boolean?, receiptAuthorized: boolean?)
	if self.Busy[buyerId] then return false end
	local buyer = self.Profiles:Get(buyerId)
	if not buyer then return false end
	-- A developer-product receipt is validated before Roblox opens its purchase UI.
	-- Persist that authorization with the journal so a reconnect/retry does not
	-- reject an already-paid transfer merely because the players moved apart.
	local authorized = receiptAuthorized == true
	if buyer.PendingTransfer and buyer.PendingTransfer.ReceiptAuthorized == true then authorized = true end
	local selected = if buyer.PendingTransfer then buyer.PendingTransfer.Target else targetId
	if not selected or selected == buyerId or self.Busy[selected] then return false end
	self.Busy[buyerId],self.Busy[selected] = true,true
	local ok, result, details = pcall(function()
		local function cancel(transaction)
			transaction.Cancelled = true
			buyer.PendingTransfer = nil
			if not self.Profiles:Save(buyerId) then buyer.PendingTransfer = transaction end
			return false
		end
		if not buyer.PendingTransfer then
			if free ~= true and buyer.StealCredits < 1 then return false end
			if not authorized and self.Callbacks.CanBegin and not self.Callbacks.CanBegin(buyerId,selected) then return false end
			local target = self.Profiles:Get(selected)
			if not target or target.Cash <= 0 then return false end
			buyer.PendingTransfer = {
				Id = self.NewId(),
				Target = selected,
				Free = free == true,
				ReceiptAuthorized = authorized,
			}
		end
		local transaction = buyer.PendingTransfer
		if transaction.Cancelled then return cancel(transaction) end
		if not self.Profiles:Save(buyerId) then return false end
		if self.Profiles:Get(buyerId) ~= buyer then return false end
		local temporary = self.Profiles.Entries[transaction.Target] == nil
		if temporary then self.Profiles:Load(transaction.Target) end
		local target = self.Profiles:Get(transaction.Target)
		if not target then return false end
		local debit = target.TransfersOut[transaction.Id]
		if not debit then
			-- Saving can yield: recheck proximity/liveness/profile availability
			-- before taking money. Already journaled debits must finish on recovery.
			if
				target.Cash <= 0
				or (not authorized and self.Callbacks.CanBegin and not self.Callbacks.CanBegin(buyerId,transaction.Target))
			then
				if temporary and not self.IsOnline(transaction.Target) then self.Profiles:Save(transaction.Target,true) end
				return cancel(transaction)
			end
			debit = { Amount = target.Cash, Buyer = buyerId }
			target.TransfersOut[transaction.Id] = debit
			target.Cash = 0
		end
		local durable = self.Profiles:Save(transaction.Target, temporary and not self.IsOnline(transaction.Target))
		if not durable then return false end
		if not self.Notified[transaction.Id] and self.Callbacks.OnDebited then
			self.Notified[transaction.Id] = true
			self.Callbacks.OnDebited(buyerId,transaction.Target,debit.Amount)
		end
		if self.Profiles:Get(buyerId) ~= buyer then return false end
		if not buyer.TransfersIn[transaction.Id] then
			buyer.Cash += debit.Amount
			if not transaction.Free then buyer.StealCredits = math.max(0, buyer.StealCredits - 1) end
			buyer.TransfersIn[transaction.Id] = true
		end
		-- If this save fails the persisted pending journal resumes on next join.
		buyer.PendingTransfer, buyer.PendingStealTarget = nil, nil
		local saved = self.Profiles:Save(buyerId)
		if not saved then buyer.PendingTransfer = transaction end
		if saved then self.Notified[transaction.Id] = nil end
		return saved, { Target = transaction.Target, Amount = debit.Amount }
	end)
	self.Busy[buyerId],self.Busy[selected] = nil,nil
	return ok and result == true, if ok then details else nil
end
return TransferService
