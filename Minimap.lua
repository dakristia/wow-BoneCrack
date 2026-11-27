local _, ns = ...

-- The button uses the addon's own icon, the same one the AddOns list and CurseForge show.
local ICON = "Interface\\AddOns\\BoneCrack\\media\\icon"
-- The button sits at this angle on the minimap edge until the player drags it, and 225 degrees is the
-- lower left, where it stays out of the way of the tracking and calendar buttons.
local DEFAULT_ANGLE = 225
-- The button center sits this far outside the minimap's edge, so the round border hugs the map.
local EDGE_OFFSET = 5

local button

local function onClick(_, mouse)
    if mouse == "RightButton" then
        ns.togglePanel()
    elseif Settings and Settings.OpenToCategory and ns.settingsCategoryID then
        Settings.OpenToCategory(ns.settingsCategoryID)
    end
end

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
    icon:SetTexture(ICON)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    button:SetScript("OnClick", onClick)
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

-- Button collectors such as EllesmereUI only gather LibDBIcon buttons, so BoneCrack registers through
-- LibDBIcon when another addon has loaded it. BoneCrack does not ship the library, so without it the
-- button falls back to its own frame. It returns the library, or nil when it is missing.
local registered
local function libIcon()
    local stub = _G.LibStub
    local ldb = stub and stub("LibDataBroker-1.1", true)
    local icon = stub and stub("LibDBIcon-1.0", true)
    if not (ldb and icon) then return nil end
    if not registered then
        if type(BoneCrackSettings) ~= "table" then BoneCrackSettings = {} end
        if type(BoneCrackSettings.minimapIcon) ~= "table" then
            BoneCrackSettings.minimapIcon = { minimapPos = angle() }
        end
        local object = ldb:NewDataObject("BoneCrack", {
            type = "launcher",
            icon = ICON,
            OnClick = onClick,
            OnTooltipShow = function(tip)
                tip:AddLine("BoneCrack")
                tip:AddLine("Left-click: options", 1, 1, 1)
                tip:AddLine("Right-click: test panel", 1, 1, 1)
            end,
        })
        icon:Register("BoneCrack", object, BoneCrackSettings.minimapIcon)
        registered = true
    end
    return icon
end

-- Shows or hides the button to match the saved setting. The button is only built the first time it is needed.
function ns.updateMinimap()
    if not Minimap then return end
    local icon = libIcon()
    if icon then
        BoneCrackSettings.minimapIcon.hide = not ns.popupSetting("minimap")
        if ns.popupSetting("minimap") then icon:Show("BoneCrack") else icon:Hide("BoneCrack") end
        return
    end
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
