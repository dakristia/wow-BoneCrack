local SOUND = "Interface\\AddOns\\BoneCrack\\bone-crack.ogg"
-- Several group members can land at once, so one crack per window is enough.
local COOLDOWN = 0.5
-- Health drops on landing, so the player counts as having fallen if IsFalling was true this recently.
local LANDING_WINDOW = 0.5
-- The client does not tell an addon whether another player is falling, so a group member's health
-- drop of at least this fraction of their maximum, out of combat, counts as fall damage.
local GROUP_MIN_LOSS = 0.05

local lastPlayed = 0
local lastFalling = -math.huge
local health = {}

local function play()
    local now = GetTime()
    if now - lastPlayed < COOLDOWN then return end
    lastPlayed = now
    PlaySoundFile(SOUND, "Master")
end

local function readable(value)
    -- The Midnight client can hand addons secret values, which cannot be compared.
    return not (issecretvalue and issecretvalue(value))
end

-- Returns the fraction of maximum health that the unit lost since the last event, or nil.
local function healthLost(unit)
    local current, max = UnitHealth(unit), UnitHealthMax(unit)
    if not readable(current) or not readable(max) or max == 0 then return nil end
    local previous = health[unit]
    health[unit] = current
    if previous and current < previous then return (previous - current) / max end
end

local function isGroupUnit(unit)
    return unit == "player" or unit:match("^party%d$") ~= nil or unit:match("^raid%d+$") ~= nil
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("UNIT_HEALTH")
frame:SetScript("OnUpdate", function()
    if IsFalling() then lastFalling = GetTime() end
end)
frame:SetScript("OnEvent", function(_, _, unit)
    if type(unit) ~= "string" or not isGroupUnit(unit) then return end
    local loss = healthLost(unit)
    if not loss then return end
    if UnitIsUnit(unit, "player") then
        if GetTime() - lastFalling <= LANDING_WINDOW then play() end
    elseif loss >= GROUP_MIN_LOSS and not UnitAffectingCombat(unit) then
        play()
    end
end)

SLASH_BONECRACK1 = "/bonecrack"
SlashCmdList["BONECRACK"] = play
