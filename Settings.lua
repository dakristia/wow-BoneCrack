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
        { "minimap", "Show minimap button", "Adds a button to the minimap. Left-click opens these options, right-click opens the test panel." },
        { "instances", "Run in instances", "Instances hide more from addons, so BoneCrack may cause Lua errors there." },
        { "debug", "Debug log", "Saves what BoneCrack sees to the SavedVariables file. Prints nothing to chat." },
    } },
}
-- Each checkbox takes this much height with its help line under it.
local ROW = 44
-- A slider takes this much height with its label above it. Each step below the Sound heading was
-- measured from a screenshot so the visible gap between the rows is the same, about 22 units.
local SLIDER_ROW = 59
-- A checkbox draws its box a little below its frame's top, so the row above it can sit closer.
local SLIDER_TO_CHECKBOX = 52
local CHECKBOX_TO_SLIDER = 51
-- The dropdown is taller than its frame's anchor suggests, so the row under it needs more room.
local DROPDOWN_ROW = 46

-- The slider template differs between client versions, so this tries the modern one first and falls
-- back to an older one, and to a bare slider if both are missing.
local function newSlider(parent)
    for _, template in ipairs({ "MinimalSliderTemplate", "OptionsSliderTemplate" }) do
        local ok, s = pcall(CreateFrame, "Slider", nil, parent, template)
        if ok and s then return s end
    end
    return CreateFrame("Slider", nil, parent)
end

-- Adds a slider that saves its value to BoneCrackSettings[key] while it is dragged, with a box next to
-- it for typing an exact value, because a slider is hard to stop on one value. It returns the slider
-- and the refresh function that reads the saved value. format turns a value into the label text.
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
    local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    box:SetSize(50, 20)
    box:SetPoint("LEFT", s, "RIGHT", 16, 0)
    box:SetAutoFocus(false)
    local refreshing = false
    local function show(v)
        label:SetText(name .. ": " .. format(v))
        if not box:HasFocus() then box:SetText(tostring(tonumber(string.format("%.2f", v)))) end
    end
    s:SetScript("OnValueChanged", function(_, v)
        show(v)
        if refreshing then return end
        if type(BoneCrackSettings) ~= "table" then BoneCrackSettings = {} end
        BoneCrackSettings[key] = tonumber(string.format("%.2f", v))
    end)
    -- A typed value snaps to the slider's range and step, and a value that is not a number is dropped.
    box:SetScript("OnEnterPressed", function(self)
        local v = tonumber(self:GetText())
        self:ClearFocus()
        if not v then show(ns.soundSetting(key)) return end
        v = math.max(low, math.min(high, math.floor(v / step + 0.5) * step))
        s:SetValue(v)
        show(v)
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        show(ns.soundSetting(key))
    end)
    local function refresh()
        refreshing = true
        s:SetValue(ns.soundSetting(key))
        show(ns.soundSetting(key))
        refreshing = false
    end
    return s, refresh
end

-- The modern client has the WowStyle1 dropdown, and an older one only has UIDropDownMenu, so this
-- builds whichever exists. It returns the refresh function that shows the saved channel.
local function addChannelDropdown(f, y)
    local function choose(name) SlashCmdList["BONECRACK"]("channel " .. name) end
    local ok, d = pcall(CreateFrame, "DropdownButton", nil, f, "WowStyle1DropdownTemplate")
    if ok and d and d.SetupMenu then
        d:SetWidth(160)
        d:SetPoint("TOPLEFT", 24, y)
        d:SetupMenu(function(_, root)
            for _, name in ipairs(ns.CHANNELS) do
                root:CreateRadio(name, function() return ns.soundSetting("channel") == name end, function() choose(name) end)
            end
        end)
        return function() if d.GenerateMenu then d:GenerateMenu() end end
    end
    d = CreateFrame("Frame", "BoneCrackChannelDropdown", f, "UIDropDownMenuTemplate")
    d:SetPoint("TOPLEFT", 8, y + 2)
    UIDropDownMenu_SetWidth(d, 140)
    UIDropDownMenu_Initialize(d, function()
        for _, name in ipairs(ns.CHANNELS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text, info.checked = name, ns.soundSetting("channel") == name
            info.func = function() choose(name) UIDropDownMenu_SetText(d, name) end
            UIDropDownMenu_AddButton(info)
        end
    end)
    return function() UIDropDownMenu_SetText(d, ns.soundSetting("channel")) end
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
    y = y - SLIDER_TO_CHECKBOX

    -- The two boxes act as one choice, so the saved scope decides which of them is checked.
    local scopes = {}
    local function refreshScopes()
        local current = ns.soundSetting("cooldownScope") == "group" and "group" or "person"
        for scope, box in pairs(scopes) do box:SetChecked(scope == current) end
    end
    for i, scope in ipairs({ "person", "group" }) do
        local box = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        box:SetPoint("TOPLEFT", 24 + (i - 1) * 240, y)
        local text = box.text or box.Text
        if text then
            text:SetText(scope == "person" and "Individual cooldown per person" or "Shared cooldown for the entire group/raid")
        end
        box:SetScript("OnClick", function()
            SlashCmdList["BONECRACK"]("cooldownscope " .. scope)
            refreshScopes()
        end)
        scopes[scope] = box
    end
    refreshers[#refreshers + 1] = refreshScopes
    y = y - CHECKBOX_TO_SLIDER

    local capSlider, refreshCap = addSlider(f, y, "cap", "Cracks per second", 0, 40, 1,
        function(v) return v == 0 and "Off" or string.format("%d", v) end)
    -- The warning sits to the right of the value box, so it takes no row of its own and the rows keep
    -- the same spacing whether it shows or not.
    local warning = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    warning:SetPoint("LEFT", capSlider, "RIGHT", 82, 0)
    warning:SetWidth(320)
    warning:SetJustifyH("LEFT")
    warning:SetTextColor(1, 0.2, 0.2)
    local function refreshWarning() warning:SetText(ns.capWarning() or "") end
    capSlider:HookScript("OnValueChanged", refreshWarning)
    -- The chat message prints when the player lets go, so dragging does not fill the chat.
    capSlider:HookScript("OnMouseUp", function() if ns.capWarning() then print(ns.capWarning()) end end)
    refreshers[#refreshers + 1] = function() refreshCap() refreshWarning() end
    y = y - SLIDER_ROW

    local channelLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    channelLabel:SetPoint("TOPLEFT", 24, y)
    channelLabel:SetText("Sound channel")
    y = y - 22
    refreshers[#refreshers + 1] = addChannelDropdown(f, y)
    y = y - DROPDOWN_ROW

    local _, refreshVolume = addSlider(f, y, "volume", "Volume", 10, 100, 10,
        function(v) return string.format("%d%%", v) end)
    refreshers[#refreshers + 1] = refreshVolume
    y = y - SLIDER_ROW
    return y, refreshers
end

-- The page is taller than the options window, so the controls sit in a scroll frame. The scroll bar
-- takes this much room on the right.
local SCROLLBAR_WIDTH = 28

local function build()
    local page = CreateFrame("Frame")
    local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR_WIDTH, 4)
    local f = CreateFrame("Frame", nil, scroll)
    f:SetSize(600, 1)
    scroll:SetScrollChild(f)
    -- The scroll child has no anchors, so its width follows the page by hand.
    page:SetScript("OnSizeChanged", function(_, w) f:SetWidth(math.max(1, w - SCROLLBAR_WIDTH)) end)
    local boxes = {}
    local y, refreshers = buildSound(f, -16)
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
    -- The scroll child is as tall as its content plus a margin, so the scroll bar reaches the button.
    f:SetHeight(-y + 40)
    -- The checkboxes read the settings each time the page opens, because a slash command can change
    -- them while the page is closed.
    page:SetScript("OnShow", function()
        for _, b in ipairs(boxes) do b.box:SetChecked(ns.toggleState(b.command) and true or false) end
        for _, refresh in ipairs(refreshers) do refresh() end
    end)
    return page
end

-- The Settings API is the modern options window. Older clients only have InterfaceOptions_AddCategory.
local frame = build()
if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(frame, "BoneCrack")
    Settings.RegisterAddOnCategory(category)
    -- The minimap button opens the page by this ID.
    ns.settingsCategoryID = category.GetID and category:GetID() or nil
elseif InterfaceOptions_AddCategory then
    frame.name = "BoneCrack"
    InterfaceOptions_AddCategory(frame)
end
