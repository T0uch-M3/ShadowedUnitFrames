local Units = {headerFrames = {}, unitFrames = {}, frameList = {}, unitEvents = {}}
Units.childUnits = {["partytarget"] = "party", ["partypet"] = "party", ["maintanktarget"] = "maintank", ["mainassisttarget"] = "mainassist"}
Units.zoneUnits = {}

local stateMonitor = CreateFrame("Frame", nil, nil, "SecureFrameTemplate")
local playerClass = select(2, UnitClass("player"))
local unitFrames, headerFrames, frameList, unitEvents, childUnits, queuedCombat = Units.unitFrames, Units.headerFrames, Units.frameList, Units.unitEvents, Units.childUnits, {}
local _G = getfenv(0)

ShadowUF.Units = Units
ShadowUF:RegisterModule(Units, "units")
	
-- Frame shown, do a full update
local function FullUpdate(self)
	for i=1, #(self.fullUpdates), 2 do
		local handler = self.fullUpdates[i]
		handler[self.fullUpdates[i + 1]](handler, self)
	end
end

-- Register an event that should always call the frame
local function RegisterNormalEvent(self, event, handler, func)
	-- Make sure the handler/func exists
	if( not handler[func] ) then
		error(string.format("Invalid handler/function passed for %s on event %s, the function %s does not exist.", self:GetName() or tostring(self), tostring(event), tostring(func)), 3)
		return
	end

	self:RegisterEvent(event)
	self.registeredEvents[event] = self.registeredEvents[event] or {}
	
	-- Each handler can only register an event once per a frame.
	if( self.registeredEvents[event][handler] ) then
		return
	end
			
	self.registeredEvents[event][handler] = func
end

-- Unregister an event
local function UnregisterEvent(self, event, handler)
	if( self.registeredEvents[event] ) then
		self.registeredEvents[event][handler] = nil
		
		local hasHandler
		for handler in pairs(self.registeredEvents[event]) do
			hasHandler = true
			break
		end
		
		if( not hasHandler ) then
			self:UnregisterEvent(event)
		end
	end
end

-- Register an event thats only called if it's for the actual unit
local function RegisterUnitEvent(self, event, handler, func)
	unitEvents[event] = true
	RegisterNormalEvent(self, event, handler, func)
end

-- Register a function to be called in an OnUpdate if it's an invalid unit (targettarget/etc)
local function RegisterUpdateFunc(self, handler, func)
	if( not handler[func] ) then
		error(string.format("Invalid handler/function passed to RegisterUpdateFunc for %s, the function %s does not exist.", self:GetName() or tostring(self), event, func), 3)
		return
	end

	for i=1, #(self.fullUpdates), 2 do
		local data = self.fullUpdates[i]
		if( data == handler and self.fullUpdates[i + 1] == func ) then
			return
		end
	end
	
	table.insert(self.fullUpdates, handler)
	table.insert(self.fullUpdates, func)
end

local function UnregisterUpdateFunc(self, handler, func)
	for i=#(self.fullUpdates), 1, -1 do
		if( self.fullUpdates[i] == handler and self.fullUpdates[i + 1] == func ) then
			table.remove(self.fullUpdates, i + 1)
			table.remove(self.fullUpdates, i)
		end
	end
end

-- Used when something is disabled, removes all callbacks etc to it
local function UnregisterAll(self, handler)
	for i=#(self.fullUpdates), 1, -1 do
		if( self.fullUpdates[i] == handler ) then
			table.remove(self.fullUpdates, i + 1)
			table.remove(self.fullUpdates, i)
		end
	end

	for event, list in pairs(self.registeredEvents) do
		list[handler] = nil
		
		local hasRegister
		for handler in pairs(list) do
			hasRegister = true
			break
		end
		
		if( not hasRegister ) then
			self:UnregisterEvent(event)
		end
	end
end

-- Handles setting alphas in a way so combat fader and range checker don't override each other
local function DisableRangeAlpha(self, toggle)
	self.disableRangeAlpha = toggle
	
	if( not toggle and self.rangeAlpha ) then
		self:SetAlpha(self.rangeAlpha)
	end
end

local function SetRangeAlpha(self, alpha)
	if( not self.disableRangeAlpha ) then
		self:SetAlpha(alpha)
	else
		self.rangeAlpha = alpha
	end
end

-- Event handling
local function OnEvent(self, event, unit, ...)
	if( not unitEvents[event] or self.unit == unit ) then
		for handler, func in pairs(self.registeredEvents[event]) do
			handler[func](handler, self, event, unit, ...)
		end
	end
end

Units.OnEvent = OnEvent

-- Do a full update OnShow, and stop watching for events when it's not visible
local function OnShow(self)
	-- Reset the event handler
	self:SetScript("OnEvent", OnEvent)
	Units:CheckUnitStatus(self)
end

local function OnHide(self)
	self:SetScript("OnEvent", nil)
	
	-- If it's a volatile such as target or focus, next time it's shown it has to do an update
	-- OR if the unit is still shown, but it's been hidden because our parent (Basically UIParent)
	-- we want to flag it as having changed so it can be updated
	if( self.isUnitVolatile or self:IsShown() ) then
		self.unitGUID = nil
	end
end

-- *target units do not give events, polling is necessary here
local function TargetUnitUpdate(self, elapsed)
	self.timeElapsed = self.timeElapsed + elapsed
	
	if( self.timeElapsed >= 0.50 ) then
		self.timeElapsed = self.timeElapsed - 0.50
		
		-- Have to make sure the unit exists or else the frame will flash offline for a second until it hides
		if( UnitExists(self.unit) ) then
			self:FullUpdate()
		end
	end
end

-- Deal with enabling modules inside a zone
local function SetVisibility(self)
	local layoutUpdate
	local instanceType = select(2, IsInInstance())

	-- Selectively disable modules
	for _, module in pairs(ShadowUF.moduleOrder) do
		if( module.OnEnable and module.OnDisable and ShadowUF.db.profile.units[self.unitType][module.moduleKey] ) then
			local key = module.moduleKey
			local enabled = ShadowUF.db.profile.units[self.unitType][key].enabled
			
			-- These modules have mini-modules, the entire module should be enabled if at least one is enabled, and disabled if all are disabled
			if( key == "auras" or key == "indicators" or key == "highlight" ) then
				enabled = nil
				for _, option in pairs(ShadowUF.db.profile.units[self.unitType][key]) do
					if( type(option) == "table" and option.enabled or option == true ) then
						enabled = true
						break
					end
				end
			end
			
			-- In an actual zone, check to see if we have an override for the zone
			if( instanceType ~= "none" ) then
				if( ShadowUF.db.profile.visibility[instanceType][self.unitType .. key] == false ) then
					enabled = nil
				elseif( ShadowUF.db.profile.visibility[instanceType][self.unitType .. key] == true ) then
					enabled = true
				end
			end
			
			-- Force disable modules for people who aren't the appropriate class
			if( module.moduleClass and module.moduleClass ~= playerClass ) then
				enabled = nil
			end
						
			-- Module isn't enabled all the time, only in this zone so we need to force it to be enabled
			if( not self.visibility[key] and enabled ) then
				module:OnEnable(self)
				layoutUpdate = true
			elseif( self.visibility[key] and not enabled ) then
				module:OnDisable(self)
				layoutUpdate = true
			end
			
			self.visibility[key] = enabled or nil
		end
	end
	
	-- We had a module update, force a full layout update of this frame
	if( layoutUpdate ) then
		ShadowUF.Layout:Load(self)
	end
end

-- Vehicles do not always return their data right away, a pure OnUpdate check seems to be the most accurate unfortunately
local function checkVehicleData(self, elapsed)
	self.timeElapsed = self.timeElapsed + elapsed
	if( self.timeElapsed >= 0.50 ) then
		self.timeElapsed = 0
		self.dataAttempts = self.dataAttempts + 1
		
		-- Took too long to get vehicle data, or they are no longer in a vehicle
		if( self.dataAttempts >= 6 or not UnitHasVehicleUI(self.unitOwner) ) then
			self.timeElapsed = nil
			self.dataAttempts = nil
			self:SetScript("OnUpdate", nil)

			self.inVehicle = false
			self.unit = self.unitOwner
			self:FullUpdate()
			
		-- Got data, stop checking and do a full frame update
		elseif( UnitIsConnected(self.unit) or UnitHealthMax(self.unit) > 0 ) then
			self.timeElapsed = nil
			self.dataAttempts = nil
			self:SetScript("OnUpdate", nil)
			
			self.unitGUID = UnitGUID(self.unit)
			self:FullUpdate()
		end
	end
end 

-- Check if a unit entered a vehicle
function Units:CheckVehicleStatus(frame, event, unit)
	if( event and frame.unitOwner ~= unit ) then return end
		
	-- Not in a vehicle yet, and they entered one that has a UI or they were in a vehicle but the GUID changed (vehicle -> vehicle)
	if( ( not frame.inVehicle or frame.unitGUID ~= UnitGUID(frame.vehicleUnit) ) and UnitHasVehicleUI(frame.unitOwner) and not ShadowUF.db.profile.units[frame.unitType].disableVehicle ) then
		
		frame.inVehicle = true
		frame.unit = frame.vehicleUnit

		if( not UnitIsConnected(frame.unit) or UnitHealthMax(frame.unit) == 0 ) then
			frame.timeElapsed = 0
			frame.dataAttempts = 0
			frame:SetScript("OnUpdate", checkVehicleData)
		else
			frame.unitGUID = UnitGUID(frame.unit)
			frame:FullUpdate()
		end
				
	-- Was in a vehicle, no longer has a UI
	elseif( frame.inVehicle and ( not UnitHasVehicleUI(frame.unitOwner) or ShadowUF.db.profile.units[frame.unitType].disableVehicle ) ) then
		frame.inVehicle = false
		frame.unit = frame.unitOwner
		frame.unitGUID = UnitGUID(frame.unit)
		frame:FullUpdate()
	end

	-- Keep track of the actual players unit so we can quickly see what unit to scan
	--[[
	if( frame.unitOwner == "player" and ShadowUF.playerUnit ~= frame.unit ) then
		ShadowUF.playerUnit = frame.unit
		
		if( not ShadowUF.db.profile.hidden.buffs and ShadowUF.db.profile.units.player.enabled and BuffFrame:IsVisible() ) then
			PlayerFrame.unit = frame.unit
			BuffFrame_Update() 
		end
	end
	]]
end

-- Handles checking for GUID changes for doing a full update, this fixes frames sometimes showing the wrong unit when they change
function Units:CheckUnitStatus(frame)
	local guid = frame.unit and UnitGUID(frame.unit)
	if( guid ~= frame.unitGUID ) then
		frame.unitGUID = guid
		
		if( guid ) then
			frame:FullUpdate()
		end
	end
end


-- The argument from UNIT_PET is the pets owner, so the player summoning a new pet gets "player", party1 summoning a new pet gets "party1" and so on
function Units:CheckPetUnitUpdated(frame, event, unit)
	if( unit == frame.unitRealOwner and UnitExists(frame.unit) ) then
		frame.unitGUID = UnitGUID(frame.unit)
		frame:FullUpdate()
	end
end

-- When raid1, raid2, raid3 are in a group with each other and raid1 or raid2 are in a vehicle and get kicked
-- OnAttributeChanged won't do anything because the frame is already setup, however, the active unit is non-existant
-- while the primary unit is. So if we see they're in a vehicle with this case, we force the full update to get the vehicle change
function Units:CheckGroupedUnitStatus(frame)
	if( frame.inVehicle and not UnitExists(frame.unit) and UnitExists(frame.unitOwner) ) then
		frame.inVehicle = false
		frame.unit = frame.unitOwner
		frame.unitGUID = guid
		frame:FullUpdate()
	else
		frame.unitGUID = UnitGUID(frame.unit)
		frame:FullUpdate()
	end
end

local function ShowMenu(self)
	if( UnitIsUnit(self.unit, "player") ) then
		ToggleDropDownMenu(1, nil, PlayerFrameDropDown, "cursor")
	elseif( self.unit == "pet" ) then
		ToggleDropDownMenu(1, nil, PetFrameDropDown, "cursor")
	elseif( self.unit == "target" ) then
		ToggleDropDownMenu(1, nil, TargetFrameDropDown, "cursor")
	elseif( self.unitType == "boss" ) then
		ToggleDropDownMenu(1, nil, _G["Boss" .. self.unitID .. "TargetFrameDropDown"], "cursor")
	elseif( self.unit == "focus" ) then
		ToggleDropDownMenu(1, nil, FocusFrameDropDown, "cursor")
	elseif( self.unitRealType == "party" ) then
		ToggleDropDownMenu(1, nil, _G["PartyMemberFrame" .. self.unitID .. "DropDown"], "cursor")
	elseif( self.unitRealType == "raid" ) then
		HideDropDownMenu(1)
		
		local menuFrame = FriendsDropDown
		menuFrame.displayMode = "MENU"
		menuFrame.initialize = RaidFrameDropDown_Initialize
		menuFrame.userData = self.unitID
		menuFrame.unit = self.unitOwner
		menuFrame.name = UnitName(self.unitOwner)
		menuFrame.id = self.unitID
		ToggleDropDownMenu(1, nil, menuFrame, "cursor")
	end	
end

-- More fun with sorting, due to sorting magic we have to check if we want to create stuff when the frame changes of partys too
local function createChildUnits(self)
	if( not self.unitID ) then return end
	
	for child, parentUnit in pairs(childUnits) do
		if( parentUnit == self.unitType and ShadowUF.db.profile.units[child].enabled ) then
			Units:LoadChildUnit(self, child, self.unitID)
		end
	end
end

local OnAttributeChanged
local function updateChildUnits(...)
	if( not ShadowUF.db.profile.locked ) then return end
	
	for i=1, select("#", ...) do
		local child = select(i, ...)
		if( child.parent and child.unitType ) then
			OnAttributeChanged(child, "unit", SecureButton_GetModifiedUnit(child))
		end
	end
end

-- Attribute set, something changed
-- unit = Active unitid
-- unitID = Just the number from the unitid
-- unitType = Unitid minus numbers in it, used for configuration
-- unitRealType = The actual unit type, if party is shown in raid this will be "party" while unitType is still "raid"
-- unitOwner = Always the units owner even when unit changes due to vehicles
-- vehicleUnit = Unit to use when the unitOwner is in a vehicle
OnAttributeChanged = function(self, name, unit)
	if( name ~= "unit" or not unit or unit == self.unitOwner ) then return end
	-- Nullify the previous entry if it had one
	if( self.unit and unitFrames[self.unit] == self ) then unitFrames[self.unit] = nil end
	
	-- Setup identification data
	self.unit = unit
	self.unitID = tonumber(string.match(unit, "([0-9]+)"))
	self.unitRealType = string.gsub(unit, "([0-9]+)", "")
	self.unitType = self.unitType or self.unitRealType
	self.unitOwner = unit
	
	-- Split everything into two maps, this is the simple parentUnit -> frame map
	-- This is for things like finding a party parent for party target/pet, the main map for doing full updates is
	-- an indexed frame that is updated once and won't have unit conflicts.
	if( self.unitRealType == self.unitType ) then
		unitFrames[unit] = self
	end
	
	frameList[self] = true

	if( self.hasChildren ) then
		updateChildUnits(self:GetChildren())
	end

	-- Create child frames
	createChildUnits(self)

	-- Unit already exists but unitid changed, update the info we got on them
	-- Don't need to recheck the unitType and force a full update, because a raid frame can never become
	-- a party frame, or a player frame and so on
	if( self.unitInitialized ) then
		self:FullUpdate()
		return
	end
	
	self.unitInitialized = true

	-- Add to Clique
	ClickCastFrames = ClickCastFrames or {}
	ClickCastFrames[self] = true
	
	-- Pet changed, going from pet -> vehicle for one
	if( self.unit == "pet" or self.unitType == "partypet" ) then
		self.unitRealOwner = self.unit == "pet" and "player" or ShadowUF.partyUnits[self.unitID]
		self:RegisterNormalEvent("UNIT_PET", Units, "CheckPetUnitUpdated")
	-- Automatically do a full update on target change
	elseif( self.unit == "target" ) then
		self.isUnitVolatile = true
		self:RegisterNormalEvent("PLAYER_TARGET_CHANGED", Units, "CheckUnitStatus")

	-- Automatically do a full update on focus change
	elseif( self.unit == "focus" ) then
		self.isUnitVolatile = true
		self:RegisterNormalEvent("PLAYER_FOCUS_CHANGED", Units, "CheckUnitStatus")
				
	elseif( self.unit == "player" ) then

		-- Force a full update when the player is alive to prevent freezes when releasing in a zone that forces a ressurect (naxx/tk/etc)
		self:RegisterNormalEvent("PLAYER_ALIVE", self, "FullUpdate")
	
	-- Check for a unit guid to do a full update
	elseif( self.unitRealType == "raid" ) then
		self:RegisterNormalEvent("RAID_ROSTER_UPDATE", Units, "CheckGroupedUnitStatus")
		self:RegisterUnitEvent("UNIT_NAME_UPDATE", Units, "CheckUnitStatus")
		
	-- Party members need to watch for changes
	elseif( self.unitRealType == "party" ) then
		self:RegisterNormalEvent("PARTY_MEMBERS_CHANGED", Units, "CheckGroupedUnitStatus")
		self:RegisterUnitEvent("UNIT_NAME_UPDATE", Units, "CheckUnitStatus")
	
	-- *target units are not real units, thus they do not receive events and must be polled for data
	elseif( ShadowUF.fakeUnits[self.unitRealType] ) then
		self.timeElapsed = 0
		self:SetScript("OnUpdate", TargetUnitUpdate)
		
		-- Speeds up updating units when their owner changes target, if party1 changes target then party1target is force updated, if target changes target
		-- then targettarget and targettargettarget are also force updated
		if( self.unitRealType == "partytarget" ) then
			self.unitRealOwner = ShadowUF.partyUnits[self.unitID]
		elseif( self.unitRealType == "raid" ) then
			self.unitRealOwner = ShadowUF.raidUnits[self.unitID]
		elseif( self.unitRealType == "arenatarget" ) then
			self.unitRealOwner = ShadowUF.arenaUnits[self.unitID]
		elseif( self.unit == "focustarget" ) then
			self.unitRealOwner = "focus"
			self:RegisterNormalEvent("PLAYER_FOCUS_CHANGED", Units, "CheckUnitStatus")
		elseif( self.unit == "targettarget" or self.unit == "targettargettarget" ) then
			self.unitRealOwner = "target"
			self:RegisterNormalEvent("PLAYER_TARGET_CHANGED", Units, "CheckUnitStatus")
		end

		self:RegisterNormalEvent("UNIT_TARGET", Units, "CheckPetUnitUpdated")
	end
	
	self.menu = ShowMenu
	self:SetVisibility()
	Units:CheckUnitStatus(self)
end

Units.OnAttributeChanged = OnAttributeChanged

-- Header unit initialized
local function initializeUnit(self)
	local unitType = self:GetParent().unitType
	local config = ShadowUF.db.profile.units[unitType]

	self.ignoreAnchor = true
	self.unitType = unitType
	self:SetAttribute("initial-height", config.height)
	self:SetAttribute("initial-width", config.width)
	self:SetAttribute("initial-scale", config.scale)
	
	Units:CreateUnit(self)
end

-- Show tooltip
local function OnEnter(self)
	if( not ShadowUF.db.profile.tooltipCombat or not UnitAffectingCombat("player") ) then
		UnitFrame_OnEnter(self)
	end
end

-- Reset the fact that we clamped the dropdown to the screen to be safe
DropDownList1:HookScript("OnHide", function(self)
	self:SetClampedToScreen(false)
end)

-- Reposition the dropdown
local function PostClick(self)
	if( UIDROPDOWNMENU_OPEN_MENU and DropDownList1:IsShown() ) then
		DropDownList1:ClearAllPoints()
		DropDownList1:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, 0)
		DropDownList1:SetClampedToScreen(true)
	end
end

-- Create the generic things that we want in every secure frame regardless if it's a button or a header
function Units:CreateUnit(...)
	local frame = select("#", ...) > 1 and CreateFrame(...) or select(1, ...)
	frame.fullUpdates = {}
	frame.registeredEvents = {}
	frame.visibility = {}
	frame.RegisterNormalEvent = RegisterNormalEvent
	frame.RegisterUnitEvent = RegisterUnitEvent
	frame.RegisterUpdateFunc = RegisterUpdateFunc
	frame.UnregisterAll = UnregisterAll
	frame.UnregisterSingleEvent = UnregisterEvent
	frame.SetRangeAlpha = SetRangeAlpha
	frame.DisableRangeAlpha = DisableRangeAlpha
	frame.UnregisterUpdateFunc = UnregisterUpdateFunc
	frame.FullUpdate = FullUpdate
	frame.SetVisibility = SetVisibility
	frame.topFrameLevel = 5
	
	-- Ensures that text is the absolute highest thing there is
	frame.highFrame = CreateFrame("Frame", nil, frame)
	frame.highFrame:SetFrameLevel(frame.topFrameLevel + 2)
	frame.highFrame:SetAllPoints(frame)
	
	frame:SetScript("OnAttributeChanged", OnAttributeChanged)
	frame:SetScript("OnEvent", OnEvent)
	frame:SetScript("OnEnter", OnEnter)
	frame:SetScript("OnLeave", UnitFrame_OnLeave)
	frame:SetScript("OnShow", OnShow)
	frame:SetScript("OnHide", OnHide)
	frame:SetScript("PostClick", PostClick)

	frame:RegisterForClicks("AnyUp")	
	frame:SetAttribute("*type1", "target")
	frame:SetAttribute("*type2", "menu")
	
	return frame
end

-- Reload a header completely
function Units:ReloadHeader(type)
	if( ShadowUF.db.profile.units[type].frameSplit ) then
		if( headerFrames.raid ) then
			self:InitializeFrame("raid")
		else
			self:SetHeaderAttributes(headerFrames.raidParent, type)
			ShadowUF.Layout:AnchorFrame(UIParent, headerFrames.raidParent, ShadowUF.db.profile.positions[type])
			ShadowUF:FireModuleEvent("OnLayoutReload", type)
		end
	elseif( type == "raid" and not ShadowUF.db.profile.units[type].frameSplit and headerFrames.raidParent ) then
		self:InitializeFrame("raid")
	
	elseif( headerFrames[type] ) then
		self:SetHeaderAttributes(headerFrames[type], type)
		ShadowUF:FireModuleEvent("OnLayoutReload", type)
		ShadowUF.Layout:AnchorFrame(UIParent, headerFrames[type], ShadowUF.db.profile.positions[type])
	end
end

function Units:PositionHeaderChildren(frame)
    local point = frame:GetAttribute("point") or "TOP"
    local relativePoint = ShadowUF.Layout:GetRelativeAnchor(point)
	
	if( #(frame.children) == 0 ) then return end

    local xMod, yMod = math.abs(frame:GetAttribute("xMod")), math.abs(frame:GetAttribute("yMod"))
    local x = frame:GetAttribute("xOffset") or 0
    local y = frame:GetAttribute("yOffset") or 0
	
	for id, child in pairs(frame.children) do
		if( id > 1 ) then
			frame.children[id]:ClearAllPoints()
			frame.children[id]:SetPoint(point, frame.children[id - 1], relativePoint, xMod * x, yMod * y)
		else
			frame.children[id]:ClearAllPoints()
			frame.children[id]:SetPoint(point, frame, point, 0, 0)
		end
	end
end

function Units:CheckGroupVisibility()
	if( not ShadowUF.db.profile.locked ) then return end
	local raid = headerFrames.raid and not ShadowUF.db.profile.units.raid.frameSplit and headerFrames.raid or headerFrames.raidParent
	local party = headerFrames.party
	if( party ) then
		party:SetAttribute("showParty", ( not ShadowUF.db.profile.units.raid.showParty or not ShadowUF.enabledUnits.raid ) and true or false)
		party:SetAttribute("showPlayer", ShadowUF.db.profile.units.party.showPlayer)
	end

	if( raid and party ) then
		raid:SetAttribute("showParty", not party:GetAttribute("showParty"))
		raid:SetAttribute("showPlayer", party:GetAttribute("showPlayer"))
	end
end

function Units:SetHeaderAttributes(frame, type)
	local config = ShadowUF.db.profile.units[type]
	local xMod = config.attribPoint == "LEFT" and 1 or config.attribPoint == "RIGHT" and -1 or 0
	local yMod = config.attribPoint == "TOP" and -1 or config.attribPoint == "BOTTOM" and 1 or 0
	local widthMod = (config.attribPoint == "LEFT" or config.attribPoint == "RIGHT") and MEMBERS_PER_RAID_GROUP or 1
	local heightMod = (config.attribPoint == "TOP" or config.attribPoint == "BOTTOM") and MEMBERS_PER_RAID_GROUP or 1
	
	frame:SetAttribute("point", config.attribPoint)
	frame:SetAttribute("sortMethod", config.sortMethod)
	frame:SetAttribute("sortDir", config.sortOrder)
	
	frame:SetAttribute("xOffset", config.offset * xMod)
	frame:SetAttribute("yOffset", config.offset * yMod)
	frame:SetAttribute("xMod", xMod)
	frame:SetAttribute("yMod", yMod)
	
	-- Split up raid frame groups
	if( config.frameSplit and type == "raid" ) then
		local anchorPoint, relativePoint, xMod, yMod = ShadowUF.Layout:GetSplitRelativeAnchor(config.attribPoint, config.attribAnchorPoint)
		local columnPoint, xColMod, yColMod = ShadowUF.Layout:GetRelativeAnchor(config.attribPoint)
		
		local lastHeader = frame
		for id=1, 8 do
			local childHeader = headerFrames["raid" .. id]
			if( childHeader and childHeader:IsVisible() ) then
				childHeader:SetAttribute("showRaid", ShadowUF.db.profile.locked and true)
				
				childHeader:SetAttribute("minWidth", config.width * widthMod)
				childHeader:SetAttribute("minHeight", config.height * heightMod)
				
				if( childHeader ~= frame ) then
					childHeader:SetAttribute("point", config.attribPoint)
					childHeader:SetAttribute("sortMethod", config.sortMethod)
					childHeader:SetAttribute("sortDir", config.sortOrder)
					childHeader:SetAttribute("showPlayer", nil)
					childHeader:SetAttribute("showParty", nil)
					
					childHeader:SetAttribute("xOffset", frame:GetAttribute("xOffset"))
					childHeader:SetAttribute("yOffset", frame:GetAttribute("yOffset"))
					
					childHeader:ClearAllPoints()
					if( id % config.groupsPerRow == 1 ) then
						local x = config.groupSpacing * xColMod
						local y = config.groupSpacing * yColMod
						
						-- When we're anchoring a new column to the bottom of naother one, the height will mess it up
						-- if what we anchored to isn't full, by anchoring it to the top instead will get a consistent result
						local point = columnPoint
						if( point == "BOTTOM" ) then
							point = config.attribPoint
							x = x + (config.height * 5) * xColMod
							y = y + (config.height * 5) * yColMod
						end
						
						childHeader:SetPoint(config.attribPoint, headerFrames["raid" .. id - config.groupsPerRow], point, x, y)
					else
						childHeader:SetPoint(anchorPoint, lastHeader, relativePoint, config.columnSpacing * xMod, config.columnSpacing * yMod)
					end

					lastHeader = childHeader
				end
			end	
		end
		
	-- Normal raid, ma or mt
	elseif( type == "raidpet" or type == "raid" or type == "mainassist" or type == "maintank" ) then
		local filter
		if( config.filters ) then
			for id, enabled in pairs(config.filters) do
				if( enabled ) then
					if( filter ) then
						filter = filter .. "," .. id
					else
						filter = id
					end
				end
			end
		else
			filter = config.groupFilter
		end
		
		frame:SetAttribute("showRaid", ShadowUF.db.profile.locked and true)
		frame:SetAttribute("maxColumns", config.maxColumns)
		frame:SetAttribute("unitsPerColumn", config.unitsPerColumn)
		frame:SetAttribute("columnSpacing", config.columnSpacing)
		frame:SetAttribute("columnAnchorPoint", config.attribAnchorPoint)
		frame:SetAttribute("groupFilter", filter or "1,2,3,4,5,6,7,8")
		
		if( config.groupBy == "CLASS" ) then
			frame:SetAttribute("groupingOrder", "DEATHKNIGHT,DRUID,HUNTER,MAGE,PALADIN,PRIEST,ROGUE,SHAMAN,WARLOCK,WARRIOR")
			frame:SetAttribute("groupBy", "CLASS")
		else
			frame:SetAttribute("groupingOrder", "1,2,3,4,5,6,7,8")
			frame:SetAttribute("groupBy", "GROUP")
		end
	
	-- Update party frames to not show anyone if they should be in raids
	elseif( type == "party" ) then
		frame:SetAttribute("maxColumns", math.ceil((config.showPlayer and 5 or 4) / config.unitsPerColumn))
		frame:SetAttribute("unitsPerColumn", config.unitsPerColumn)
		frame:SetAttribute("columnSpacing", config.columnSpacing)
		frame:SetAttribute("columnAnchorPoint", config.attribAnchorPoint)
	end
	
	-- Update the raid frames to if they should be showing raid or party
	if( type == "party" or type == "raid" ) then
		self:CheckGroupVisibility()
		
		-- Need to update our flags on the state monitor so it knows what to do
		stateMonitor:SetAttribute("hideSemiRaid", ShadowUF.db.profile.units.party.hideSemiRaid)
		stateMonitor:SetAttribute("hideAnyRaid", ShadowUF.db.profile.units.party.hideAnyRaid)
	end
end

-- Load a single unit such as player, target, pet, etc
function Units:LoadUnit(unit)
	-- Already be loaded, just enable
	if( unitFrames[unit] ) then
		RegisterUnitWatch(unitFrames[unit], unitFrames[unit].hasStateWatch)
		return
	end
	
	local frame = self:CreateUnit("Button", "SUFUnit" .. unit, UIParent, "SecureUnitButtonTemplate")
	frame:SetAttribute("unit", unit)
	--frame.hasStateWatch = unit == "pet"
		
	-- Annd lets get this going
	RegisterUnitWatch(frame, frame.hasStateWatch)
end

function Units:LoadSplitGroupHeader(type)
	if( headerFrames.raid ) then headerFrames.raid:Hide() end
	headerFrames.raidParent = nil

	for id, enabled in pairs(ShadowUF.db.profile.units[type].filters) do
		local frame = headerFrames["raid" .. id]
		if( enabled ) then
			if( not frame ) then
				frame = CreateFrame("Frame", "SUFHeader" .. type .. id, UIParent, "SecureGroupHeaderTemplate")
				frame:SetAttribute("template", "SecureUnitButtonTemplate")
				frame:SetAttribute("initial-unitWatch", true)
				frame:SetAttribute("showRaid", true)
				frame:SetAttribute("groupFilter", id)
				frame:UnregisterEvent("UNIT_NAME_UPDATE")
				frame.initialConfigFunction = initializeUnit
				frame.isHeaderFrame = true
				frame.unitType = type
				frame.splitParent = type
				frame.groupID = id
				--frame:SetBackdrop({bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeSize = 1})
				--frame:SetBackdropBorderColor(1, 0, 0, 1)
				--frame:SetBackdropColor(0, 0, 0, 0)
				
				headerFrames["raid" .. id] = frame
			end
			
			frame:Show()
			
			if( not headerFrames.raidParent or headerFrames.raidParent.groupID > id ) then
				headerFrames.raidParent = frame
			end
			
		elseif( frame ) then
			frame:Hide()	
		end
	end
	
	if( headerFrames.raidParent ) then
		self:SetHeaderAttributes(headerFrames.raidParent, type)
		ShadowUF.Layout:AnchorFrame(UIParent, headerFrames.raidParent, ShadowUF.db.profile.positions.raid)
	end
end

-- Load a header unit, party or raid
function Units:LoadGroupHeader(type)
	-- Any frames that were split out in this group need to be hidden
	for _, headerFrame in pairs(headerFrames) do
		if( headerFrame.splitParent == type ) then
			headerFrame:Hide()
		end
	end
	
	-- Already created, so just reshow and we out
	if( headerFrames[type] ) then
		headerFrames[type]:Show()
		
		if( type == "party" ) then
			stateMonitor:SetAttribute("partyDisabled", nil)
		end
		
		if( type == "party" or type == "raid" ) then
			self:CheckGroupVisibility()
		end
		return
	end
	
	local headerFrame = CreateFrame("Frame", "SUFHeader" .. type, UIParent, type == "raidpet" and "SecureGroupPetHeaderTemplate" or "SecureGroupHeaderTemplate")
	headerFrames[type] = headerFrame

	self:SetHeaderAttributes(headerFrame, type)
	
	headerFrame:SetAttribute("template", "SecureUnitButtonTemplate")
	headerFrame:SetAttribute("initial-unitWatch", true)
	headerFrame.initialConfigFunction = initializeUnit
	headerFrame.isHeaderFrame = true
	headerFrame.unitType = type
	headerFrame:UnregisterEvent("UNIT_NAME_UPDATE")
	
	ShadowUF.Layout:AnchorFrame(UIParent, headerFrame, ShadowUF.db.profile.positions[type])
	
	-- We have to do party hiding based off raid as a state driver so that we can smoothly hide the party frames based off of combat and such
	-- technically this isn't the cleanest solution because party frames will still have unit watches active
	-- but this isn't as big of a deal, because SUF automatically will unregister the OnEvent for party frames while hidden
	if( type == "party" ) then
		stateMonitor:SetScript("OnAttributeChanged", function (self, name, unit)
			if( name ~= "state-raidmonitor" and name ~= "partydisabled" and name ~= "hideanyraid" and name ~= "hidesemiraid" ) then return end
			if( self:GetAttribute("partyDisabled") ) then return end
			
			if( self:GetAttribute("hideAnyRaid") and ( self:GetAttribute("state-raidmonitor") == "raid1" or self:GetAttribute("state-raidmonitor") == "raid6" ) ) then
				ShadowUF.Units.headerFrames.party:Hide()
			elseif( self:GetAttribute("hideSemiRaid") and self:GetAttribute("state-raidmonitor") == "raid6" ) then
				ShadowUF.Units.headerFrames.party:Hide()
			else
				ShadowUF.Units.headerFrames.party:Show()
			end
		end)
		RegisterStateDriver(stateMonitor, "raidmonitor", "[target=raid6, exists] raid6; [target=raid1, exists] raid1; none")
	else
		headerFrame:Show()
	end
end

-- Fake headers that are supposed to act like headers to the users, but are really not
function Units:LoadZoneHeader(type)
	if( headerFrames[type] ) then
		headerFrames[type]:Show()
		return
	end
	
	local headerFrame = CreateFrame("Frame", "SUFHeader" .. type, UIParent)
	headerFrame.isHeaderFrame = true
	headerFrame.unitType = type
	headerFrame:SetClampedToScreen(true)
	headerFrame:SetMovable(true)
	headerFrame:SetHeight(0.1)
	headerFrame.children = {}
	headerFrames[type] = headerFrame
	
	for id, unit in pairs(ShadowUF[type .. "Units"]) do
		local frame = self:CreateUnit("Button", "SUFHeader" .. type .. "UnitButton" .. id, headerFrame, "SecureUnitButtonTemplate")
		frame.ignoreAnchor = true
		frame:SetAttribute("unit", unit)
		frame:Hide()
		
		headerFrame.children[id] = frame
		
		-- Arena frames are only allowed to be shown not hidden from the unit existing, or else when a Rogue
		-- stealths the frame will hide which looks bad. Instead force it to stay open and it has to be manually hidden when the player leaves an arena.

 	end
	

	self:SetHeaderAttributes(headerFrame, type)
	
	ShadowUF.Layout:AnchorFrame(UIParent, headerFrame, ShadowUF.db.profile.positions[type])	
end

-- Load a unit that is a child of another unit (party pet/party target)
function Units:LoadChildUnit(parent, type, id)
	if( UnitAffectingCombat("player") ) then
		if( not queuedCombat[parent:GetName() .. type] ) then
			queuedCombat[parent:GetName() .. type] = {parent = parent, type = type, id = id}
		end
		return
	else
		-- This is a bit confusing to write down, but just in case I forget:
		-- It's possible theres a bug where you have a frame skip creating it's child because it thinks one was already created, but the one that was created is actually associated to another parent. What would need to be changed is it checks if the frame has the parent set to it and it's the same unit type before returning, not that the units match.
		for frame in pairs(frameList) do
			if( frame.unitType == type and frame.parent == parent ) then
				RegisterUnitWatch(frame, frame.hasStateWatch)
				return
			end
		end
	end
	
	parent.hasChildren = true

	-- Now we can create the actual frame
	local frame = self:CreateUnit("Button", "SUFChild" .. type .. string.match(parent:GetName(), "(%d+)"), parent, "SecureUnitButtonTemplate")
	frame.unitType = type
	frame.parent = parent
	frame.isChildUnit = true
	frame.hasStateWatch = type == "partypet"
	frame:SetFrameStrata("LOW")
	frame:SetAttribute("useparent-unit", true)
	frame:SetAttribute("unitsuffix", string.match(type, "pet$") and "pet" or "target")
	OnAttributeChanged(frame, "unit", SecureButton_GetModifiedUnit(frame))
	frameList[frame] = true
	
	RegisterUnitWatch(frame, frame.hasStateWatch)
	ShadowUF.Layout:AnchorFrame(parent, frame, ShadowUF.db.profile.positions[type])
end

-- Initialize units
function Units:InitializeFrame(type)
	if( type == "raid" and ShadowUF.db.profile.units[type].frameSplit ) then
		self:LoadSplitGroupHeader(type)
	elseif( type == "party" or type == "raid" or type == "maintank" or type == "mainassist" or type == "raidpet" ) then
		self:LoadGroupHeader(type)
	elseif( self.zoneUnits[type] ) then
		self:LoadZoneHeader(type)
	elseif( self.childUnits[type] ) then
		for frame in pairs(frameList) do
			if( frame.unitType == self.childUnits[type] and ShadowUF.db.profile.units[frame.unitType] and frame.unitID ) then
				self:LoadChildUnit(frame, type, frame.unitID)
			end
		end
	else
		self:LoadUnit(type)
	end
end

-- Uninitialize units
function Units:UninitializeFrame(type)
	-- Disables showing party in raid automatically if raid frames are disabled
	if( type == "party" ) then
		stateMonitor:SetAttribute("partyDisabled", true)
	end
	if( type == "party" or type == "raid" ) then
		self:CheckGroupVisibility()
	end

	-- Disable the parent and the children will follow
	if( ShadowUF.db.profile.units[type].frameSplit ) then
		for _, headerFrame in pairs(headerFrames) do
			if( headerFrame.splitParent == type ) then
				headerFrame:Hide()
			end
		end
	elseif( headerFrames[type] ) then
		headerFrames[type]:Hide()
		
		if( headerFrames[type].children ) then
			for _, frame in pairs(headerFrames[type].children) do
				frame:Hide()
			end
		end
	else
		-- Disable all frames of this type
		for frame in pairs(frameList) do
			if( frame.unitType == type ) then
				UnregisterUnitWatch(frame)
				frame:Hide()
			end
		end
	end
end

-- Profile changed, reload units
function Units:ProfileChanged()
	-- Reset the anchors for all frames to prevent X is dependant on Y
	for frame in pairs(frameList) do
		if( frame.unit ) then
			frame:ClearAllPoints()
		end
	end
	
	for frame in pairs(frameList) do
		if( frame.unit and ShadowUF.db.profile.units[frame.unitType].enabled ) then
			-- Force all enabled modules to disable
			for key, module in pairs(ShadowUF.modules) do
				if( frame[key] and frame.visibility[key] ) then
					frame.visibility[key] = nil
					module:OnDisable(frame)
				end
			end
			
			-- Now enable whatever we need to
			frame:SetVisibility()
			ShadowUF.Layout:Load(frame)
			frame:FullUpdate()
		end
	end
	
	for _, frame in pairs(headerFrames) do
		if( ShadowUF.db.profile.units[frame.unitType].enabled ) then
			self:ReloadHeader(frame.unitType)
		end
	end
end

-- Small helper function for creating bars with
function Units:CreateBar(parent)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetFrameLevel(parent.topFrameLevel or 5)
	bar.parent = parent
	
	bar.background = bar:CreateTexture(nil, "BORDER")
	bar.background:SetHeight(1)
	bar.background:SetWidth(1)
	bar.background:SetAllPoints(bar)
--	bar.background:SetHorizTile(false)

	return bar
end

-- Deal with zone changes for enabling modules
local instanceType, queueZoneCheck
function Units:CheckPlayerZone(force)
	if( UnitAffectingCombat("player") ) then
		queueZoneCheck = force and 2 or 1
		return
	end
	
	-- CanHearthAndResurrectFromArea() returns true for world pvp areas, according to BattlefieldFrame.lua
	local instance = select(2, IsInInstance())
	if( instance == instanceType and not force ) then return end
	instanceType = instance
	
	ShadowUF:LoadUnits()
	for frame in pairs(frameList) do
		if( frame.unit and ShadowUF.db.profile.units[frame.unitType].enabled ) then
			frame:SetVisibility()
			
			-- Auras are enabled so will need to check if the filter has to change
			if( frame.visibility.auras ) then
				ShadowUF.modules.auras:UpdateFilter(frame)
			end
			
			if( UnitExists(frame.unit) ) then
				frame:FullUpdate()
			end
		end
	end
end

local centralFrame = CreateFrame("Frame")
centralFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
centralFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
centralFrame:SetScript("OnEvent", function(self, event, unit)
	-- Check if the player changed zone types and we need to change module status, while they are dead
	-- we won't change their zone type as releasing from an instance will change the zone type without them
	-- really having left the zone
	if( event == "ZONE_CHANGED_NEW_AREA" ) then
		if( UnitIsDeadOrGhost("player") ) then
			self:RegisterEvent("PLAYER_UNGHOST")
		else
			self:UnregisterEvent("PLAYER_UNGHOST")
			Units:CheckPlayerZone()
		end				
		
	-- They're alive again so they "officially" changed zone types now
	elseif( event == "PLAYER_UNGHOST" ) then
		Units:CheckPlayerZone()
		
	-- This is slightly hackish, but it suits the purpose just fine for somthing thats rarely called.
	elseif( event == "PLAYER_REGEN_ENABLED" ) then
		-- Now do all of the creation for child wrapping
		for _, queue in pairs(queuedCombat) do
			Units:LoadChildUnit(queue.parent, queue.type, queue.id)
		end
		
		queuedCombat = {}
		
		if( queueZoneCheck ) then
			Units:CheckPlayerZone(queueZoneCheck == 2 and true)
			queueZoneCheck = nil
		end
	end
end)