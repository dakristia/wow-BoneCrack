local _, ns = ...

-- The panel's buttons run the slash commands, so the panel and the commands always do the same thing.
local function run(command)
    SlashCmdList["BONECRACK"](command)
end

local TIERS = { "small", "medium", "big", "death" }
local UNITS = { "player", "party1", "party2", "party3", "party4" }
-- The toggles are the slash commands that turn a setting on or off.
local TOGGLES = { { "Pop-ups", "popups" }, { "Own pop-up", "selfpopup" }, { "Instances", "instances" }, { "Debug", "debug" } }
local panel

local function toggleState(command)
    if command == "popups" then return ns.popupSetting("popups") end
    if command == "selfpopup" then return ns.popupSetting("popupSelf") end
    if command == "instances" then return type(BoneCrackSettings) == "table" and BoneCrackSettings.instances end
    return BoneCrackDebug
end

local function button(parent, text, x, y, w, command)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", function() run(command) end)
    return b
end

local function build()
    local f = CreateFrame("Frame", "BoneCrackPanel", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(420, 300)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f.TitleText:SetText("BoneCrack test panel")
    for row, unit in ipairs(UNITS) do
        local y = -32 - (row - 1) * 26
        local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", 14, y - 4)
        label:SetText(unit)
        for col, tier in ipairs(TIERS) do
            button(f, tier, 70 + (col - 1) * 84, y, 80, "test " .. unit .. " " .. tier)
        end
    end
    button(f, "Group fall", 14, -168, 120, "test group")
    button(f, "Play crack", 140, -168, 120, "")
    -- The settings get their own heading and show their state, so a player sees that these buttons
    -- change saved settings and do not just test something.
    local heading = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    heading:SetPoint("TOPLEFT", 14, -200)
    heading:SetText("Settings (saved)")
    for i, t in ipairs(TOGGLES) do
        local b = button(f, t[1], 14 + (i - 1) * 100, -218, 96, t[2])
        local function refresh() b:SetText(t[1] .. ": " .. (toggleState(t[2]) and "on" or "off")) end
        b:SetScript("OnClick", function() run(t[2]) refresh() end)
        b:SetScript("OnShow", refresh)
        refresh()
    end
    tinsert(UISpecialFrames, "BoneCrackPanel")
    return f
end

function ns.togglePanel()
    panel = panel or build()
    panel:SetShown(not panel:IsShown())
end
