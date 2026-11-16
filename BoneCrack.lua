local SOUND = "Interface\\AddOns\\BoneCrack\\bone-crack.ogg"
-- Several group members can land at once, so one crack per window is enough.
local COOLDOWN = 0.5
-- Health drops on landing, so the player counts as having fallen if IsFalling was true this recently.
local LANDING_WINDOW = 0.5
-- The client does not tell an addon whether another player is falling, so a group member's health
-- drop of at least this fraction of their maximum, out of combat, counts as fall damage.
local GROUP_MIN_LOSS = 0.05
-- Falling damage starts at about 14.6 yards, which takes about 1.2 seconds of free fall. This is the
-- stand-in for the health drop when the client hides the player's health from addons.
local FALL_SECONDS = 1.2

local lastPlayed = 0
local lastFalling = -math.huge
local fallStart = 0
local wasFalling = false
local debugging = false
local health = {}

local function log(...)
    if debugging then print("|cffff8800BoneCrack|r", ...) end
end

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
    if not readable(current) or not readable(max) or max == 0 then
        log(unit, "health is secret or the maximum is 0")
        return nil
    end
    local previous = health[unit]
    health[unit] = current
    log(unit, "health", tostring(previous), "->", current, "of", max)
    if previous and current < previous then return (previous - current) / max end
end

local function isGroupUnit(unit)
    return unit == "player" or unit:match("^party%d$") ~= nil or unit:match("^raid%d+$") ~= nil
end

-- Runs when the player stops falling. It only plays when the player's health is hidden, because
-- the health check in OnEvent covers the case where it is readable.
local function landed()
    local duration = GetTime() - fallStart
    local hidden = not readable(UnitHealth("player"))
    local water = IsSwimming() or IsFlying()
    log("landed after", duration, "seconds, health hidden:", hidden, "swimming or flying:", water)
    if hidden and duration >= FALL_SECONDS and not water then play() end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("UNIT_HEALTH")
frame:SetScript("OnUpdate", function()
    local falling = IsFalling() and true or false
    if falling then lastFalling = GetTime() end
    if falling ~= wasFalling then
        wasFalling = falling
        log(falling and "started falling" or "stopped falling")
        if falling then fallStart = GetTime() else landed() end
    end
end)
frame:SetScript("OnEvent", function(_, _, unit)
    if type(unit) ~= "string" or not isGroupUnit(unit) then return end
    local loss = healthLost(unit)
    if not loss then return end
    if UnitIsUnit(unit, "player") then
        local sinceFalling = GetTime() - lastFalling
        log("player lost", loss, "and was falling", sinceFalling, "seconds ago, window", LANDING_WINDOW)
        if sinceFalling <= LANDING_WINDOW then play() end
    elseif loss >= GROUP_MIN_LOSS and not UnitAffectingCombat(unit) then
        play()
    end
end)

SLASH_BONECRACK1 = "/bonecrack"
SlashCmdList["BONECRACK"] = function(message)
    if message == "debug" then
        debugging = not debugging
        print("BoneCrack debug " .. (debugging and "on" or "off"))
    else
        play()
    end
end
