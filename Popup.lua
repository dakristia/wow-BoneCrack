local _, ns = ...

-- The paths leave out the extension, so the client finds the .tga files.
local MEDIA = "Interface\\AddOns\\BoneCrack\\media\\popup\\"
-- The pop-up punches in from this many times its size, so a small fall gets a small punch and a big
-- fall a big one. The index is the damage tier from ns.fallTier: small, medium, big, death.
local PUNCH_FROM = { 1.4, 1.7, 2.1, 2.0 }
-- The bone and the word grow with the damage tier, so the size alone tells how bad the fall was.
local TIER_SCALE = { 0.75, 1.0, 1.25, 1.15 }
-- The word for each damage tier, in the same order as the tables above.
local WORDS = { "word_ow", "word_ouch", "word_ouch2", "word_crack" }
-- The punch takes this long, then the pop-up holds for a moment and fades. The whole pop-up is gone
-- after about half a second, so it never covers the frame while the player needs it.
local PUNCH_SECONDS = 0.08
local HOLD_SECONDS = 0.1
local FADE_SECONDS = 0.25
-- The word lands a moment after the bone, so the two read as one hit with a small follow-up.
local WORD_DELAY = 0.03
-- On death the whole bone shows for this long before it snaps in two.
local SNAP_SECONDS = 0.07
-- The broken halves and splinters fall with this pull, in UI units per second squared.
local GRAVITY = 260
-- These sizes in UI units match the textures' 2:1 and 1:1 shapes, and they fit the end of a party
-- frame that is about 140 by 50.
local BONE_W, BONE_H = 64, 32
local WORD_W, WORD_H = 76, 38
-- The bone that snaps on death is drawn at one size, a little bigger than the medium tier, so the
-- halves line up with it whatever the tier sizes are.
local DEATH_W, DEATH_H = 72, 36
local HALF_SIZE = 36
local CHIP_SIZE = 9
-- chips.tga holds this many splinters side by side, and each one flies off on its own.
local CHIPS = 4
-- The bone sits this far left of the frame's right edge and a little low, so the word fits above it
-- and the name on the frame stays readable.
local BONE_X, BONE_Y = -30, -6
local WORD_X, WORD_Y = -4, 18

-- Both pop-ups start off because out of the box BoneCrack only plays the sound, and a player turns
-- them on with a slash command or the panel.
local defaults = { popups = false, popupSelf = false }
local pool = {}

local function setting(key)
    if type(BoneCrackSettings) ~= "table" or BoneCrackSettings[key] == nil then return defaults[key] end
    return BoneCrackSettings[key]
end

local function popScale(d, from)
    if d < PUNCH_SECONDS then return from + (1 - from) * d / PUNCH_SECONDS end
    local e = d - PUNCH_SECONDS
    return 1 + 0.08 * math.exp(-e * 30) * math.cos(e * 45)
end

local function popAlpha(d)
    if d < 0 then return 0 end
    if d < PUNCH_SECONDS / 2 then return d / (PUNCH_SECONDS / 2) end
    if d < PUNCH_SECONDS + HOLD_SECONDS then return 1 end
    return math.max(0, 1 - (d - PUNCH_SECONDS - HOLD_SECONDS) / FADE_SECONDS)
end

local function texture(parent, file, layer)
    local t = parent:CreateTexture(nil, layer or "OVERLAY")
    t:SetTexture(MEDIA .. file)
    t:Hide()
    return t
end

local function place(t, parent, x, y, w, h, scale, alpha, rotation)
    if alpha <= 0 then t:Hide() return end
    t:ClearAllPoints()
    t:SetPoint("CENTER", parent, "RIGHT", x, y)
    t:SetSize(w * scale, h * scale)
    t:SetAlpha(alpha)
    t:SetRotation(rotation or 0)
    t:Show()
end

local function newPopup()
    local p = CreateFrame("Frame", nil, UIParent)
    p:SetFrameStrata("HIGH")
    p:SetSize(1, 1)
    p.bone = texture(p, "bone")
    p.word = texture(p, "word_ow", "ARTWORK")
    p.left = texture(p, "bone_left")
    p.right = texture(p, "bone_right")
    p.chips = {}
    for i = 1, CHIPS do
        local c = texture(p, "chips")
        c:SetTexCoord((i - 1) / CHIPS, i / CHIPS, 0, 1)
        p.chips[i] = { tex = c, vx = (i - 2.5) * 45, vy = 60 + (i % 2) * 40, spin = (i - 2.5) * 6 }
    end
    p:Hide()
    return p
end

local function hideAll(p)
    p.bone:Hide() p.word:Hide() p.left:Hide() p.right:Hide()
    for _, c in ipairs(p.chips) do c.tex:Hide() end
end

-- Each frame keeps its own pop-up, so a group fall shows one pop-up per member at the same time.
local function popupFor(frame)
    local p = pool[frame]
    if not p then p = newPopup() pool[frame] = p end
    return p
end

-- The rotations are in WoW's direction, counter-clockwise, so the bone tilts up to the right.
local function update(p, d)
    local tier, frame = p.tier, p.target
    local scale, from = TIER_SCALE[tier], PUNCH_FROM[tier]
    local bx, by = BONE_X, BONE_Y
    local wd = d - WORD_DELAY
    place(p.word, frame, WORD_X, WORD_Y, WORD_W, WORD_H, scale * popScale(wd, from), wd < 0 and 0 or popAlpha(wd), -0.1)
    if tier < 4 then
        place(p.bone, frame, bx, by, BONE_W, BONE_H, scale * popScale(d, from), popAlpha(d), 0.25)
        return
    end
    local a = popAlpha(d)
    if d < SNAP_SECONDS then
        place(p.bone, frame, bx, by, DEATH_W, DEATH_H, popScale(d, from), a, 0.25)
        return
    end
    p.bone:Hide()
    local e = d - SNAP_SECONDS
    local fall = GRAVITY * e * e
    place(p.left, frame, bx - 12 - 30 * e, by - 3 - 6 * e - fall, HALF_SIZE, HALF_SIZE, 1, a, 0.25 + 3 * e)
    place(p.right, frame, bx + 12 + 30 * e, by + 3 + 4 * e - fall, HALF_SIZE, HALF_SIZE, 1, a, 0.25 - 3 * e)
    for _, c in ipairs(p.chips) do
        local cx = bx + c.vx * e
        local cy = by + c.vy * e - 2 * GRAVITY * e * e
        place(c.tex, frame, cx, cy, CHIP_SIZE, CHIP_SIZE, 1, math.max(0, 1 - e / 0.4) * a, c.spin * e)
    end
end

local function play(frame, tier)
    local p = popupFor(frame)
    hideAll(p)
    p.target, p.tier, p.start = frame, tier + 1, GetTime()
    p.word:SetTexture(MEDIA .. WORDS[p.tier])
    p:SetScript("OnUpdate", function(self)
        local d = GetTime() - self.start
        if d > PUNCH_SECONDS + HOLD_SECONDS + FADE_SECONDS + 0.1 then
            hideAll(self)
            self:SetScript("OnUpdate", nil)
            self:Hide()
            return
        end
        update(self, d)
    end)
    p:Show()
end

-- Returns whether the frame shows this unit. frame.unit can be missing or secret, so both are skipped.
local function shows(frame, unit)
    if not frame or not frame.IsVisible or not frame:IsVisible() then return false end
    local u = frame.displayedUnit or frame.unit
    if type(u) ~= "string" or not ns.readable(u) then return false end
    local same = UnitIsUnit(u, unit)
    return ns.readable(same) and same and true or false
end

-- Finds the Blizzard frame that shows the unit: the player frame, the party frames in either style,
-- or the raid frames. Third-party frames are not supported, so this returns nil for them.
local function frameFor(unit)
    local isMe = UnitIsUnit(unit, "player")
    if ns.readable(isMe) and isMe and shows(PlayerFrame, "player") then
        -- The raid-style party frames also show the player, and they are where the group looks.
        for i = 1, 5 do
            local f = _G["CompactPartyFrameMember" .. i]
            if shows(f, unit) then return f end
        end
        return PlayerFrame
    end
    for i = 1, 5 do
        local f = _G["CompactPartyFrameMember" .. i]
        if shows(f, unit) then return f end
    end
    if PartyFrame then
        for i = 1, 4 do
            local f = PartyFrame["MemberFrame" .. i]
            if shows(f, unit) then return f end
        end
    end
    for i = 1, 40 do
        local f = _G["CompactRaidFrame" .. i]
        if shows(f, unit) then return f end
    end
    for g = 1, 8 do
        for m = 1, 5 do
            local f = _G["CompactRaidGroup" .. g .. "Member" .. m]
            if shows(f, unit) then return f end
        end
    end
end

-- Turns a sender's name from an addon message into a unit token of the group.
local function unitForName(name)
    -- The test command passes unit tokens, and addon messages pass player names.
    if name == "player" or name:match("^party%d$") or name:match("^raid%d+$") then
        return UnitExists(name) and name or nil
    end
    local short = Ambiguate(name, "none")
    local prefix, count = "party", GetNumSubgroupMembers()
    if IsInRaid() then prefix, count = "raid", GetNumGroupMembers() end
    for i = 1, count do
        local unit = prefix .. i
        local n = GetUnitName(unit, true)
        if ns.readable(n) and n and (n == name or Ambiguate(n, "none") == short) then return unit end
    end
end

-- Shows the pop-up for a unit token or a sender's name, at a damage tier from 0 to 3. Returns whether
-- a frame was found.
function ns.showPopup(who, tier)
    local unit = unitForName(who)
    local frame = unit and frameFor(unit)
    if not frame then
        ns.log("no Blizzard frame shows", who, "so no pop-up")
        return false
    end
    play(frame, tier)
    return true
end

function ns.onFall(who, info)
    if not setting("popups") then return end
    if who == "player" and not setting("popupSelf") then return end
    ns.showPopup(who, ns.fallTier(info))
end

ns.popupSetting = setting
