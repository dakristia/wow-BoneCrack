local _, ns = ...
-- A test addon has its own private table and cannot see ns, so this one global hands it over.
BoneCrackNS = ns

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
-- The saved log keeps only the newest lines so the SavedVariables file stays small.
local DEBUG_LOG_MAX = 500
-- A fall that costs less than a tenth of maximum health is only a scrape, so it is the small tier.
local TIER_SMALL_LOSS = 0.10
-- A fall that costs up to 30 percent of maximum health is a normal hard landing, and anything above
-- that is the big tier because it is close to killing a low-level character.
local TIER_MEDIUM_LOSS = 0.30
-- Without the health loss, air time is the stand-in. Damage starts at about 1.6 seconds (see
-- FALL_SECONDS), so a fall shorter than this stays small because its damage is still low.
local TIER_SMALL_AIR = 2.0
-- A fall of this many seconds or more is the big tier, because the damage grows with the drop height.
local TIER_MEDIUM_AIR = 2.6
-- The details message and the plain "fell" arrive back to back on one channel, so a plain "fell" this
-- soon after a details message from the same sender is the same fall and is ignored.
local DETAILS_WINDOW = 1.0

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
local lastDetails = {}
local pendingInfo = nil

local function readable(value)
    -- The Midnight client can hand addons secret values, which cannot be compared.
    return not (issecretvalue and issecretvalue(value))
end
ns.readable = readable

-- Turns the facts of a fall into the details message. The old client only knows "fell", so the
-- details use a different word and are sent first.
function ns.encodeFall(info)
    return string.format("fell2:%s:%.2f:%d:%s",
        info.loss and string.format("%.3f", info.loss) or "-",
        info.air or 0,
        info.dead and 1 or 0,
        info.map and tostring(info.map) or "-")
end

-- Returns the info table for a details message, or nil for anything else, because the text comes
-- from another player and may be anything.
function ns.decodeFall(text)
    if type(text) ~= "string" then return nil end
    local loss, air, dead, map = text:match("^fell2:([^:]*):([^:]*):([^:]*):([^:]*)$")
    if not loss then return nil end
    local info = { loss = nil, air = tonumber(air), map = nil }
    if not info.air then return nil end
    if loss ~= "-" then
        info.loss = tonumber(loss)
        if not info.loss then return nil end
    end
    if dead == "1" then info.dead = true elseif dead == "0" then info.dead = false else return nil end
    if map ~= "-" then
        info.map = tonumber(map)
        if not info.map then return nil end
    end
    return info
end

-- Returns 0 for a small fall, 1 for medium, 2 for big and 3 for a fall that killed the player.
function ns.fallTier(info)
    if info.dead then return 3 end
    if info.loss then
        if info.loss < TIER_SMALL_LOSS then return 0 end
        if info.loss <= TIER_MEDIUM_LOSS then return 1 end
        return 2
    end
    local air = info.air or 0
    if air < TIER_SMALL_AIR then return 0 end
    if air < TIER_MEDIUM_AIR then return 1 end
    return 2
end

local function log(...)
    if not debugging then return end
    local parts = { ... }
    for i = 1, select("#", ...) do
        if not readable(parts[i]) then parts[i] = "<secret>" else parts[i] = tostring(parts[i]) end
    end
    if type(BoneCrackDebugLog) ~= "table" then BoneCrackDebugLog = {} end
    local text = table.concat(parts, " ", 1, select("#", ...))
    local clock = date and date("%H:%M:%S") or ""
    BoneCrackDebugLog[#BoneCrackDebugLog + 1] = clock .. " " .. string.format("%.2f", GetTime()) .. " " .. text
    while #BoneCrackDebugLog > DEBUG_LOG_MAX do table.remove(BoneCrackDebugLog, 1) end
end

ns.log = log

local function play()
    local now = GetTime()
    if now - lastPlayed < COOLDOWN then return end
    lastPlayed = now
    PlaySoundFile(SOUND, "Master")
end

-- Group members who run BoneCrack hear the player's fall through an addon message, because their
-- client hides the player's health and falling state from their addon.
local function broadcast(info)
    if not IsInGroup() then return end
    if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
        log("addon messages are locked down here, so the fall was not sent")
        return
    end
    local channel = IsInRaid() and "RAID" or "PARTY"
    -- Messages on one channel arrive in order, so the details come before the plain "fell" that an
    -- old client waits for.
    local details = C_ChatInfo.SendAddonMessage(PREFIX, ns.encodeFall(info), channel)
    local result = C_ChatInfo.SendAddonMessage(PREFIX, "fell", channel)
    log("sent fall to", channel, "results", details, result)
end

-- Collects the facts of the player's own fall. loss is nil when the client hides the health.
local function buildInfo(loss, air)
    local deadFlag = UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")
    local dead = readable(deadFlag) and deadFlag and true or false
    local current = UnitHealth("player")
    if readable(current) and current == 0 then dead = true end
    local map = C_Map.GetBestMapForUnit("player")
    if not readable(map) then map = nil end
    return { loss = loss, air = math.max(0, air), dead = dead, map = map }
end

local function playerFell(info)
    play()
    broadcast(info)
    if ns.onFall then ns.onFall("player", info) end
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
    local info = buildInfo(nil, duration)
    if now - lastWound <= WOUND_WINDOW then
        playerFell(info)
    elseif not woundsReadable and duration >= FALL_SECONDS then
        playerFell(info)
    else
        -- The WOUND for this landing may still be on its way. woundsReadable is false after a login
        -- until the first readable UNIT_COMBAT, so that first WOUND can come from this landing too.
        pendingLanding = now
        pendingInfo = info
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
        playerFell(pendingInfo)
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

-- Debug only: logs what the distance APIs return for each party member, to find out which of them
-- give readable values on this client before the distance tiers rely on them.
local function probeDistance()
    if not debugging then return end
    log("player map", C_Map.GetBestMapForUnit("player"), "sound channels", GetCVar("Sound_NumChannels"))
    for i = 1, GetNumSubgroupMembers() do
        local unit = "party" .. i
        local inRange, checked = UnitInRange(unit)
        log(unit, UnitName(unit), "in range:", inRange, "checked:", checked,
            "visible:", UnitIsVisible(unit), "map:", C_Map.GetBestMapForUnit(unit))
    end
end

local function onHealth(unit)
    local loss = healthLost(unit)
    if not loss then return end
    if UnitIsUnit(unit, "player") then
        local sinceFalling = GetTime() - lastFalling
        log("player lost", loss, "and was falling", sinceFalling, "seconds ago, window", LANDING_WINDOW)
        if sinceFalling <= LANDING_WINDOW then
            -- lastFalling is the last moment the player was in the air, so it ends the fall's air time.
            playerFell(buildInfo(loss, lastFalling - fallStart))
        end
    elseif loss >= GROUP_MIN_LOSS and not UnitAffectingCombat(unit) then
        -- UnitAffectingCombat is unreliable for a far-away member, so a member who is fighting on
        -- another continent could look out of combat. UnitIsVisible is only true when the client can
        -- see the unit, so it keeps those drops from playing the sound.
        if UnitIsVisible(unit) then
            play()
        else
            log(unit, "lost", loss, "but is not visible, so the drop was skipped")
        end
    end
end

local function onAddonMessage(prefix, text, _, sender)
    if prefix ~= PREFIX or not readable(text) or type(text) ~= "string" then return end
    local details = text:sub(1, 6) == "fell2:"
    if text ~= "fell" and not details then return end
    if not readable(sender) then return end
    -- The sender hears its own message too, and already played the sound.
    if Ambiguate(sender, "none") == UnitName("player") then return end
    local now = GetTime()
    if details then
        local info = ns.decodeFall(text)
        if not info then return end
        lastDetails[sender] = now
        log("fall details from", sender)
        probeDistance()
        play()
        if ns.onFall then ns.onFall(sender, info) end
        return
    end
    -- A new client sends the details first, so the plain "fell" after them is the same fall.
    if lastDetails[sender] and now - lastDetails[sender] <= DETAILS_WINDOW then return end
    log("fall message from", sender)
    probeDistance()
    play()
end

C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
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
    if event == "ADDON_LOADED" then
        -- SavedVariables are only filled in once the addon has loaded, so the saved setting is read here.
        if ... == PREFIX then
            debugging = BoneCrackDebug == true
            -- The log carries over between sessions, so this line marks where a new one starts.
            log("session start")
        end
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
        -- The setting is saved so debug stays on after a /reload. The log is not cleared here because
        -- the 500-line cap keeps it small, and /bonecrack clearlog empties it.
        BoneCrackDebug = debugging
        print("BoneCrack debug " .. (debugging and "on" or "off"))
        probeDistance()
    elseif message == "probe" then
        probeDistance()
    elseif message == "clearlog" then
        BoneCrackDebugLog = {}
        print("BoneCrack debug log cleared")
    else
        play()
    end
end
