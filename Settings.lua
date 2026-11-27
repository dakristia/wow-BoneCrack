local _, ns = ...

-- Each checkbox runs the slash command for its setting, so the chat message and the instance warning
-- show the same way as when the command is typed. A section with a heading groups related settings.
local SECTIONS = {
    { "Graphics and animation", {
        { "popups", "Show party pop-ups", "Shows a pop-up on the Blizzard party frame of a party member who fell." },
        { "raidpopups", "Show raid pop-ups", "Shows a pop-up on the Blizzard raid frame of a raid member who fell." },
        { "selfpopup", "Show your own pop-ups", "Shows a pop-up on your own frame when you fall." },
    } },
    { "General", {
        { "instances", "Run in instances", "Instances hide more from addons, so BoneCrack may cause Lua errors there." },
        { "debug", "Debug log", "Saves what BoneCrack sees to the SavedVariables file. Prints nothing to chat." },
    } },
}
-- Each checkbox takes this much height with its help line under it.
local ROW = 44
-- A slider takes this much height with its label above it and room for a help line below.
local SLIDER_ROW = 56

-- The slider template differs between client versions, so this tries the modern one first and falls
-- back to an older one, and to a bare slider if both are missing.
local function newSlider(parent)
    for _, template in ipairs({ "MinimalSliderTemplate", "OptionsSliderTemplate" }) do
        local ok, s = pcall(CreateFrame, "Slider", nil, parent, template)
        if ok and s then return s end
    end
    return CreateFrame("Slider", nil, parent)
end

-- Adds a slider that saves its value to BoneCrackSettings[key] while it is dragged. It returns the
-- refresh function that reads the saved value. format turns a value into the label text.
local function addSlider(f, y, key, name, low, high, step, format)
    local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", 24, y)
    local s = newSlider(f)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(220, 16)
    s:SetPoint("TOPLEFT", 24, y - 20)
    s:SetMinMaxValues(low, high)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    local refreshing = false
    local function show(v) label:SetText(name .. ": " .. format(v)) end
    s:SetScript("OnValueChanged", function(_, v)
        show(v)
        if refreshing then return end
        if type(BoneCrackSettings) ~= "table" then BoneCrackSettings = {} end
        BoneCrackSettings[key] = tonumber(string.format("%.2f", v))
    end)
    local function refresh()
        refreshing = true
        s:SetValue(ns.soundSetting(key))
        show(ns.soundSetting(key))
        refreshing = false
    end
    return s, refresh
end

-- Builds the Sound section from y and returns the next free y and the functions that refresh its controls.
local function buildSound(f, y)
    local refreshers = {}
    local heading = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    heading:SetPoint("TOPLEFT", 16, y)
    heading:SetText("Sound")
    y = y - 20

    local _, refreshCooldown = addSlider(f, y, "cooldown", "Cooldown", 0, 5, 0.1,
        function(v) return string.format("%.1f seconds", v) end)
    refreshers[#refreshers + 1] = refreshCooldown
    y = y - SLIDER_ROW

    -- The two boxes act as one choice, so the saved scope decides which of them is checked.
    local scopes = {}
    local function refreshScopes()
        local current = ns.soundSetting("cooldownScope") == "group" and "group" or "person"
        for scope, box in pairs(scopes) do box:SetChecked(scope == current) end
    end
    for i, scope in ipairs({ "person", "group" }) do
        local box = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        box:SetPoint("TOPLEFT", 24 + (i - 1) * 180, y)
        local text = box.text or box.Text
        if text then text:SetText(scope == "person" and "Cooldown per person" or "Cooldown for the whole group") end
        box:SetScript("OnClick", function()
            SlashCmdList["BONECRACK"]("cooldownscope " .. scope)
            refreshScopes()
        end)
        scopes[scope] = box
    end
    refreshers[#refreshers + 1] = refreshScopes
    y = y - 30

    local capSlider, refreshCap = addSlider(f, y, "cap", "Cracks per second", 0, 40, 1,
        function(v) return v == 0 and "Off" or string.format("%d", v) end)
    local warning = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    warning:SetPoint("TOPLEFT", 24, y - 40)
    warning:SetWidth(400)
    warning:SetJustifyH("LEFT")
    warning:SetTextColor(1, 0.2, 0.2)
    local function refreshWarning() warning:SetText(ns.capWarning() or "") end
    capSlider:HookScript("OnValueChanged", refreshWarning)
    -- The chat message prints when the player lets go, so dragging does not fill the chat.
    capSlider:HookScript("OnMouseUp", function() if ns.capWarning() then print(ns.capWarning()) end end)
    refreshers[#refreshers + 1] = function() refreshCap() refreshWarning() end
    y = y - SLIDER_ROW - 18

    local channelLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    channelLabel:SetPoint("TOPLEFT", 24, y)
    channelLabel:SetText("Sound channel")
    y = y - 20
    local buttons = {}
    for i, name in ipairs(ns.CHANNELS) do
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(84, 22)
        b:SetPoint("TOPLEFT", 24 + (i - 1) * 88, y)
        b:SetScript("OnClick", function()
            SlashCmdList["BONECRACK"]("channel " .. name)
            for _, other in ipairs(buttons) do other.refresh() end
        end)
        b.refresh = function()
            b:SetText(ns.soundSetting("channel") == name and ("[" .. name .. "]") or name)
        end
        buttons[i] = b
    end
    refreshers[#refreshers + 1] = function() for _, b in ipairs(buttons) do b.refresh() end end
    y = y - 40
    return y, refreshers
end

local function build()
    local f = CreateFrame("Frame")
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("BoneCrack")
    local note = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    note:SetText("BoneCrack plays the sound out of the box. Everything below is off until you turn it on.")
    local boxes = {}
    local y, refreshers = buildSound(f, -56)
    for _, section in ipairs(SECTIONS) do
        local heading = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        heading:SetPoint("TOPLEFT", 16, y)
        heading:SetText(section[1])
        y = y - 20
        for _, o in ipairs(section[2]) do
            local box = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
            box:SetPoint("TOPLEFT", 24, y)
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
            y = y - ROW
        end
        y = y - 8
    end
    local test = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    test:SetSize(160, 22)
    test:SetPoint("TOPLEFT", 24, y)
    test:SetText("Open test panel")
    test:SetScript("OnClick", function() ns.togglePanel() end)
    -- The checkboxes read the settings each time the page opens, because a slash command can change
    -- them while the page is closed.
    f:SetScript("OnShow", function()
        for _, b in ipairs(boxes) do b.box:SetChecked(ns.toggleState(b.command) and true or false) end
        for _, refresh in ipairs(refreshers) do refresh() end
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
