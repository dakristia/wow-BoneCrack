local _, ns = ...

-- The icon file is not in the addon yet. Switch the button to ICON when media/icon.tga lands.
local ICON = "Interface\\AddOns\\BoneCrack\\media\\icon"
-- This is a temporary built-in bone icon, because the client cannot tell an addon whether a file is
-- missing, and a missing file would show a green square.
local FALLBACK_ICON = 134368
-- The button sits at this angle on the minimap edge until the player drags it, and 225 degrees is the
-- lower left, where it stays out of the way of the tracking and calendar buttons.
local DEFAULT_ANGLE = 225
-- The button center sits this far outside the minimap's edge, so the round border hugs the map.
local EDGE_OFFSET = 5

local button

local function angle()
    local saved = type(BoneCrackSettings) == "table" and BoneCrackSettings.minimapAngle
    return type(saved) == "number" and saved or DEFAULT_ANGLE
end

local function place()
    local radius = Minimap:GetWidth() / 2 + EDGE_OFFSET
    local a = math.rad(angle())
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * radius, math.sin(a) * radius)
end

-- Turns the cursor position into the angle around the minimap center, and saves it.
local function dragTo()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    local a = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
    if type(BoneCrackSettings) ~= "table" then BoneCrackSettings = {} end
    BoneCrackSettings.minimapAngle = a
    place()
end

local function create()
    button = CreateFrame("Button", "BoneCrackMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 1, -1)
    icon:SetTexture(FALLBACK_ICON)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    button:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then
            ns.togglePanel()
        elseif Settings and Settings.OpenToCategory and ns.settingsCategoryID then
            Settings.OpenToCategory(ns.settingsCategoryID)
        end
    end)
    button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", dragTo) end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("BoneCrack")
        GameTooltip:AddLine("Left-click: options", 1, 1, 1)
        GameTooltip:AddLine("Right-click: test panel", 1, 1, 1)
        GameTooltip:AddLine("Drag: move", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    place()
end

-- Shows or hides the button to match the saved setting. The button is only built the first time it is needed.
function ns.updateMinimap()
    if not Minimap then return end
    if ns.popupSetting("minimap") then
        if not button then create() end
        place()
        button:Show()
    elseif button then
        button:Hide()
    end
end

-- SavedVariables are only filled in after this file runs, so the setting is read at login.
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function() ns.updateMinimap() end)
