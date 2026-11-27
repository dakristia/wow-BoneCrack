local _, ns = ...

-- Each checkbox runs the slash command for its setting, so the chat message and the instance warning
-- show the same way as when the command is typed.
local OPTIONS = {
    { "popups", "Show pop-ups", "Shows a pop-up on the Blizzard party, raid or player frame of whoever fell." },
    { "selfpopup", "Show the pop-up for your own falls", "Needs the pop-ups above to be on." },
    { "instances", "Run in instances", "Instances hide more from addons, so BoneCrack may cause Lua errors there." },
    { "debug", "Debug log", "Saves what BoneCrack sees to the SavedVariables file. Prints nothing to chat." },
}

local function build()
    local f = CreateFrame("Frame")
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("BoneCrack")
    local note = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    note:SetText("BoneCrack plays the sound out of the box. Everything below is off until you turn it on.")
    local boxes = {}
    for i, o in ipairs(OPTIONS) do
        local box = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        box:SetPoint("TOPLEFT", 16, -60 - (i - 1) * 44)
        local label = box.text or box.Text
        if label then label:SetText(o[2]) end
        local help = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        help:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 30, 4)
        help:SetText(o[3])
        box:SetScript("OnClick", function(self)
            SlashCmdList["BONECRACK"](o[1])
            self:SetChecked(ns.toggleState(o[1]) and true or false)
        end)
        boxes[#boxes + 1] = { box = box, command = o[1] }
    end
    local test = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    test:SetSize(160, 22)
    test:SetPoint("TOPLEFT", 20, -60 - #OPTIONS * 44 - 8)
    test:SetText("Open test panel")
    test:SetScript("OnClick", function() ns.togglePanel() end)
    -- The checkboxes read the settings each time the page opens, because a slash command can change
    -- them while the page is closed.
    f:SetScript("OnShow", function()
        for _, b in ipairs(boxes) do b.box:SetChecked(ns.toggleState(b.command) and true or false) end
    end)
    return f
end

-- The Settings API is the modern options window. Older clients only have InterfaceOptions_AddCategory.
local frame = build()
if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(frame, "BoneCrack")
    Settings.RegisterAddOnCategory(category)
elseif InterfaceOptions_AddCategory then
    frame.name = "BoneCrack"
    InterfaceOptions_AddCategory(frame)
end
