local SOUND = "Interface\\AddOns\\BoneCrack\\bone-crack.ogg"
local PREFIX = "BoneCrack"
-- Several group members can land at once, so one crack per window is enough.
local COOLDOWN = 0.5
-- Health drops on landing, so the player counts as having fallen if IsFalling was true this recently.
local LANDING_WINDOW = 0.5
-- The client does not tell an addon whether another player is falling, so a group member's health
-- drop of at least this fraction of their maximum, out of combat, counts as fall damage.
local GROUP_MIN_LOSS = 0.05
-- A normal jump keeps the player in the air for about 0.75 seconds, so shorter landings are never falls.
local MIN_FALL_SECONDS = 1.0
-- UNIT_COMBAT can arrive just before or just after the OnUpdate script sees the landing, so a WOUND
-- this close to the landing counts as the fall's damage.
local WOUND_WINDOW = 0.5
-- Falling damage starts at about 14.6 yards. A jump followed by that drop takes about 1.6 seconds,
-- so this is the stand-in for damage when the client hides both health and UNIT_COMBAT. In combat a
-- mob's hit is also a WOUND, so a landing in combat needs this much air time too.
local FALL_SECONDS = 1.6
-- The debug probe samples party positions this often and logs height changes bigger than this.
local PROBE_INTERVAL = 0.2
local PROBE_MIN_DROP = 2

local lastPlayed = 0
local lastFalling = -math.huge
local fallStart = 0
local wasFalling = false
local lastWound = -math.huge
local pendingLanding = nil
local woundsReadable = false
local debugging = false
local health = {}
local lastProbe = 0
local heights = {}
local secretLogged = {}

local function readable(value)
    -- The Midnight client can hand addons secret values, which cannot be compared.
    return not (issecretvalue and issecretvalue(value))
end

local function log(...)
    if not debugging then return end
    local parts = { ... }
    for i = 1, select("#", ...) do
        if not readable(parts[i]) then parts[i] = "<secret>" else parts[i] = tostring(parts[i]) end
    end
    print("|cffff8800BoneCrack|r", unpack(parts, 1, select("#", ...)))
end

local function play()
    local now = GetTime()
    if now - lastPlayed < COOLDOWN then return end
    lastPlayed = now
    PlaySoundFile(SOUND, "Master")
end

-- Group members who run BoneCrack hear the player's fall through an addon message, because their
-- client hides the player's health and falling state from their addon.
local function broadcast()
    if not IsInGroup() then return end
    if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
        log("addon messages are locked down here, so the fall was not sent")
        return
    end
    local channel = IsInRaid() and "RAID" or "PARTY"
    local result = C_ChatInfo.SendAddonMessage(PREFIX, "fell", channel)
    log("sent fall to", channel, "result", result)
end

local function playerFell()
    play()
    broadcast()
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
    log(unit, "health", previous, "->", current, "of", max)
    if previous and current < previous then return (previous - current) / max end
end

local function isGroupUnit(unit)
    return unit == "player" or unit:match("^party%d$") ~= nil or unit:match("^raid%d+$") ~= nil
end

-- Runs when the player stops falling. The health check in onHealth covers readable health, so this
-- only decides when health is hidden. A WOUND from UNIT_COMBAT is the damage proof when the client
-- shows it; otherwise only a fall long enough to hurt counts.
local function landed()
    local now = GetTime()
    local duration = now - fallStart
    local hidden = not readable(UnitHealth("player"))
    local water = IsSwimming() or IsFlying()
    local combat = UnitAffectingCombat("player")
    log("landed after", duration, "seconds, health hidden:", hidden, "swimming or flying:", water,
        "wounds readable:", woundsReadable, "in combat:", combat)
    local minimum = combat and FALL_SECONDS or MIN_FALL_SECONDS
    if not hidden or water or duration < minimum then return end
    if woundsReadable then
        if now - lastWound <= WOUND_WINDOW then
            playerFell()
        else
            -- The WOUND for this landing may still be on its way.
            pendingLanding = now
        end
    elseif duration >= FALL_SECONDS then
        playerFell()
    end
end

local function onPlayerCombat(action)
    if not readable(action) then return end
    woundsReadable = true
    if action ~= "WOUND" then return end
    local now = GetTime()
    lastWound = now
    if pendingLanding and now - pendingLanding <= WOUND_WINDOW then
        pendingLanding = nil
        playerFell()
    end
end

-- Debug only: logs big height changes of party members, to find out whether UnitPosition can see
-- another player fall on this client.
local function probePositions(now)
    if now - lastProbe < PROBE_INTERVAL then return end
    lastProbe = now
    for i = 1, GetNumSubgroupMembers() do
        local unit = "party" .. i
        local _, _, z = UnitPosition(unit)
        if not readable(z) or z == nil then
            if not secretLogged[unit] then
                secretLogged[unit] = true
                log(unit, "height is", z == nil and "nil" or "<secret>")
            end
        else
            local previous = heights[unit]
            heights[unit] = z
            if previous and math.abs(previous - z) >= PROBE_MIN_DROP then
                log(unit, "height", previous, "->", z)
            end
        end
    end
end

local function onHealth(unit)
    local loss = healthLost(unit)
    if not loss then return end
    if UnitIsUnit(unit, "player") then
        local sinceFalling = GetTime() - lastFalling
        log("player lost", loss, "and was falling", sinceFalling, "seconds ago, window", LANDING_WINDOW)
        if sinceFalling <= LANDING_WINDOW then playerFell() end
    elseif loss >= GROUP_MIN_LOSS and not UnitAffectingCombat(unit) then
        play()
    end
end

local function onAddonMessage(prefix, text, _, sender)
    if prefix ~= PREFIX or text ~= "fell" then return end
    if not readable(sender) then return end
    -- The sender hears its own message too, and already played the sound.
    if Ambiguate(sender, "none") == UnitName("player") then return end
    log("fall message from", sender)
    play()
end

C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

local frame = CreateFrame("Frame")
frame:RegisterEvent("UNIT_HEALTH")
frame:RegisterEvent("UNIT_COMBAT")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnUpdate", function()
    local now = GetTime()
    local falling = IsFalling() and true or false
    if falling then lastFalling = now end
    if falling ~= wasFalling then
        wasFalling = falling
        log(falling and "started falling" or "stopped falling")
        if falling then fallStart = now else landed() end
    end
    if pendingLanding and now - pendingLanding > WOUND_WINDOW then pendingLanding = nil end
    if debugging then probePositions(now) end
end)
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        onAddonMessage(...)
        return
    end
    local unit = ...
    if type(unit) ~= "string" or not isGroupUnit(unit) then return end
    if event == "UNIT_HEALTH" then
        onHealth(unit)
    else
        log("UNIT_COMBAT", ...)
        if unit == "player" then onPlayerCombat(select(2, ...)) end
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
