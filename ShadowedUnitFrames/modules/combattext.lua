local Combat = {}
ShadowUF:RegisterModule(Combat, "combatText", ShadowUF.L["Combat text"])

local function CombatFeedback_OnCombatEvent(frame, event, flags, amount, type)
	local feedbackText = frame.feedbackText
	local fontHeight = frame.feedbackFontHeight;
	local text = "";
	local r = 1.0;
	local g = 1.0;
	local b = 1.0;

	if( event == "IMMUNE" ) then
		fontHeight = fontHeight * 0.5;
		text = CombatFeedbackText[event];
	elseif ( event == "WOUND" ) then
		if ( amount ~= 0 ) then
			if ( flags == "CRITICAL" or flags == "CRUSHING" ) then
				fontHeight = fontHeight * 1.5;
			elseif ( flags == "GLANCING" ) then
				fontHeight = fontHeight * 0.75;
			end
			if ( type ~= SCHOOL_MASK_PHYSICAL ) then
				r = 1.0;
				g = 1.0;
				b = 0.0;
			end
			text = amount;
		elseif ( flags == "ABSORB" ) then
			fontHeight = fontHeight * 0.75;
			text = CombatFeedbackText["ABSORB"];
		elseif ( flags == "BLOCK" ) then
			fontHeight = fontHeight * 0.75;
			text = CombatFeedbackText["BLOCK"];
		elseif ( flags == "RESIST" ) then
			fontHeight = fontHeight * 0.75;
			text = CombatFeedbackText["RESIST"];
		else
			text = CombatFeedbackText["MISS"];
		end
	elseif ( event == "BLOCK" ) then
		fontHeight = fontHeight * 0.75;
		text = CombatFeedbackText[event];
	elseif ( event == "HEAL" ) then
		text = amount;
		r = 0.0;
		g = 1.0;
		b = 0.0;
		if ( flags == "CRITICAL" ) then
			fontHeight = fontHeight * 1.5;
		end
	elseif ( event == "ENERGIZE" ) then
		text = amount;
		r = 0.41;
		g = 0.8;
		b = 0.94;
		if ( flags == "CRITICAL" ) then
			fontHeight = fontHeight * 1.5;
		end
	else
		text = CombatFeedbackText[event];
	end

	frame.feedbackStartTime = GetTime();

	feedbackText:SetTextHeight(fontHeight);
	feedbackText:SetText(text);
	feedbackText:SetTextColor(r, g, b);
	feedbackText:SetAlpha(0.0);
	feedbackText:Show();
end

function Combat:OnEnable(frame)
	if( not frame.combatText ) then
		frame.combatText = CreateFrame("Frame", nil, frame.highFrame)
		frame.combatText:SetFrameStrata("HIGH")
		frame.combatText.feedbackText = frame.combatText:CreateFontString(nil, "ARTWORK")
		frame.combatText.feedbackText:SetPoint("CENTER", frame.combatText, "CENTER", 0, 0)
		frame.combatText:SetFrameLevel(frame.topFrameLevel)
		
		frame.combatText.feedbackStartTime = 0
		frame.combatText:SetScript("OnUpdate", CombatFeedback_OnUpdate)
		frame.combatText:SetHeight(1)
		frame.combatText:SetWidth(1)
	end
		
	frame:RegisterUnitEvent("UNIT_COMBAT", self, "Update")
end

function Combat:OnLayoutApplied(frame, config)
	-- Update feedback text
	ShadowUF.Layout:ToggleVisibility(frame.combatText, frame.visibility.combatText)
	if( frame.visibility.combatText ) then
		frame.combatText.feedbackFontHeight = ShadowUF.db.profile.font.size + 1
		frame.combatText.fontPath = ShadowUF.Layout.mediaPath.font
		
		ShadowUF.Layout:SetupFontString(frame.combatText.feedbackText, 1)
		ShadowUF.Layout:AnchorFrame(frame, frame.combatText, config.combatText)
	end
end

function Combat:OnDisable(frame)
	frame:UnregisterAll(self)
end

function Combat:Update(frame, event, unit, type, ...)
	CombatFeedback_OnCombatEvent(frame.combatText, type, ...)
	if( type == "IMMUNE" ) then
		frame.combatText.feedbackText:SetTextHeight(frame.combatText.feedbackFontHeight * 0.75)
	end
	
	-- Increasing the font size will make the text look pixelated, however scaling it up will make it look smooth and awesome
	frame.combatText:SetScale(frame.combatText.feedbackText:GetStringHeight() / ShadowUF.db.profile.font.size)
	frame.combatText.feedbackText:SetFont(frame.combatText.fontPath, ShadowUF.db.profile.font.size, "OUTLINE")
end
