local _, NS = ...
local SC = NS.SC

-- Some screens only get their data once the game's View spell for them is cast, and a spell can only be cast from a
-- secure button the player clicks. Secure buttons can't be shown, moved or changed in combat, and lock what they're
-- anchored to, so each overlay is a secure button on UIParent laid over an ordinary control (its spot). Out of
-- combat it follows the spot every frame and shows while its spell is needed; combat hides them all. The spot's
-- tooltip and the rest of its click run through the overlay.
local SecureCast = { overlays = {} }
SC.SecureCast = SecureCast

-- Update runs every frame, so it builds nothing it doesn't have to: macros are made once per spell, and an
-- overlay's attributes, place and size only change when they differ.
local macros = {}
local function macro(spell)
	local text = macros[spell]
	if not text then
		local name = GetSpellInfo(spell)
		if name then
			text = "/cast " .. name
			macros[spell] = text
		end
	end
	return text
end

-- spot: the control to cover. opts: spell(), the spell ID needed now or nil; onClick(mouse) runs after the cast;
-- right = true lets right-clicks through to onClick without casting; onDragStart/onDragStop for draggable spots;
-- name names the overlay frame.
function SecureCast.Overlay(spot, opts)
	local o = CreateFrame("Button", opts.name, UIParent, "SecureActionButtonTemplate")
	o:Hide()
	o:RegisterForClicks(opts.right and "AnyUp" or "LeftButtonUp")
	o.spot, o.opts = spot, opts
	o:SetScript("OnEnter", function()
		local fn = spot:GetScript("OnEnter")
		if fn then fn(spot) end
	end)
	o:SetScript("OnLeave", function()
		local fn = spot:GetScript("OnLeave")
		if fn then fn(spot) end
	end)
	o:HookScript("OnClick", function(_, mouse)
		if opts.onClick then opts.onClick(mouse) end
	end)
	if opts.onDragStart then
		o:RegisterForDrag("LeftButton")
		o:SetScript("OnDragStart", function() opts.onDragStart() end)
		o:SetScript("OnDragStop", function() if opts.onDragStop then opts.onDragStop() end end)
	end
	SecureCast.overlays[#SecureCast.overlays + 1] = o
	return o
end

local function place(o)
	local spot = o.spot
	local spell = spot:IsVisible() and o.opts.spell()
	local text = spell and macro(spell)
	local left, bottom = spot:GetLeft(), spot:GetBottom()
	if text and left and bottom then
		local scale = spot:GetEffectiveScale() / UIParent:GetEffectiveScale()
		local x, y, w, h = left * scale, bottom * scale, spot:GetWidth() * scale, spot:GetHeight() * scale
		if o.text ~= text then
			o.text = text
			-- only the left button casts, so a right-click can do what the spot's does
			o:SetAttribute("type1", "macro")
			o:SetAttribute("macrotext1", text)
		end
		if o.x ~= x or o.y ~= y or o.w ~= w or o.h ~= h then
			o.x, o.y, o.w, o.h = x, y, w, h
			o:ClearAllPoints()
			o:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
			o:SetSize(w, h)
		end
		if not o:IsShown() then
			o:SetFrameStrata(spot:GetFrameStrata())
			o:SetFrameLevel(spot:GetFrameLevel() + 10)
			o:Show()
		end
	elseif o:IsShown() then
		o:Hide()
	end
end

function SecureCast.Update()
	if not InCombatLockdown() then
		for _, o in ipairs(SecureCast.overlays) do place(o) end
	end
end

local watch = CreateFrame("Frame")
watch:SetScript("OnUpdate", SecureCast.Update)
watch:RegisterEvent("PLAYER_REGEN_DISABLED")
watch:SetScript("OnEvent", function()
	-- fires just before the lockdown starts, so they can still hide here; placing them again after combat starts
	-- from scratch
	for _, o in ipairs(SecureCast.overlays) do
		o:Hide()
		o.x = nil
	end
end)

-- The spell a screen needs cast right now, or nil.
function SecureCast.ScreenSpell(screen)
	return screen and screen.spell and screen.needsSpell and screen.needsSpell() and screen.spell or nil
end
