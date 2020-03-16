local Totems = {}
local totemColors = {}

ShadowUF:RegisterModule(Totems, "totemBar", ShadowUF.L["Totem bar"], true, "SHAMAN")

function Totems:OnEnable(frame)
	if( not frame.totemBar ) then
		frame.totemBar = CreateFrame("Frame", nil, frame)
		frame.totemBar.totems = {}
		
		for id=1, 4 do
			local totem = ShadowUF.Units:CreateBar(frame)
			totem:SetFrameLevel(1)
			totem:SetMinMaxValues(0, 1)
			totem:SetValue(0)
			totem.id = TOTEM_PRIORITIES[id]
			
			if( id > 1 ) then
				totem:SetPoint("TOPLEFT", frame.totemBar.totems[id - 1], "TOPRIGHT", 1, 0)
			else
				totem:SetPoint("TOPLEFT", frame.totemBar, "TOPLEFT", 0, 0)
			end
			
			table.insert(frame.totemBar.totems, totem)
		end
		
		totemColors[1] = {r = 1, g = 0, b = 0.4}
		totemColors[2] = {r = 0, g = 1, b = 0.4}
		totemColors[3] = {r = 0, g = 0.4, b = 1}
		totemColors[4] = {r = 0.90, g = 0.90, b = 0.90}
	end
	
	frame:RegisterNormalEvent("PLAYER_TOTEM_UPDATE", self, "Update")
	frame:RegisterUpdateFunc(self, "Update")
end

function Totems:OnDisable(frame)
	frame:UnregisterAll(self)
end

function Totems:OnLayoutApplied(frame)
	if( frame.visibility.totemBar ) then
		local barWidth = (frame.totemBar:GetWidth() - 3) / 4
		
		for _, totem in pairs(frame.totemBar.totems) do
			if( ShadowUF.db.profile.units[frame.unitType].totemBar.background ) then
				local color = ShadowUF.db.profile.bars.backgroundColor or ShadowUF.db.profile.units[frame.unitType].totemBar.backgroundColor or totemColors[totem.id]
				totem.background:SetTexture(ShadowUF.Layout.mediaPath.statusbar)
				totem.background:SetVertexColor(color.r, color.g, color.b, ShadowUF.db.profile.bars.backgroundAlpha)
				totem.background:Show()
			else
				totem.background:Hide()
			end
			
			totem:SetHeight(frame.totemBar:GetHeight())
			totem:SetWidth(barWidth)
			totem:SetStatusBarTexture(ShadowUF.Layout.mediaPath.statusbar)
			totem:SetStatusBarColor(totemColors[totem.id].r, totemColors[totem.id].g, totemColors[totem.id].b, ShadowUF.db.profile.bars.alpha)
		end
	end
end

local function totemMonitor(self, elapsed)
	local time = GetTime()
	self:SetValue(self.endTime - time)
	
	if( time >= self.endTime ) then
		self:SetValue(0)
		self:SetScript("OnUpdate", nil)
	end
end

function Totems:Update(frame)
	local totalActive = 0
	for _, indicator in pairs(frame.totemBar.totems) do
		local have, name, start, duration = GetTotemInfo(indicator.id)
		if( have and start > 0 ) then
			indicator.have = true
			indicator.endTime = start + duration
			indicator:SetMinMaxValues(0, duration)
			indicator:SetValue(indicator.endTime - GetTime())
			indicator:SetScript("OnUpdate", totemMonitor)
			indicator:SetAlpha(1.0)
			
			totalActive = totalActive + 1
			
		elseif( indicator.have ) then
			indicator.have = nil
			indicator:SetScript("OnUpdate", nil)
			indicator:SetMinMaxValues(0, 1)
			indicator:SetValue(0)
		end
	end
end
