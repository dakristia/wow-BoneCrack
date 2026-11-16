local SOUND = "Interface\\AddOns\\BoneCrack\\bone-crack.ogg"
-- Several group members can land at once, so one crack per window is enough.
local COOLDOWN = 0.5

local lastPlayed = 0

local function play()
    local now = GetTime()
    if now - lastPlayed < COOLDOWN then return end
    lastPlayed = now
    PlaySoundFile(SOUND, "Master")
end

local function isGroupMember(guid)
    if guid == UnitGUID("player") then return true end
    local prefix, count
    if IsInRaid() then
        prefix, count = "raid", GetNumGroupMembers()
    else
        prefix, count = "party", GetNumSubgroupMembers()
    end
    for i = 1, count do
        if guid == UnitGUID(prefix .. i) then return true end
    end
    return false
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:SetScript("OnEvent", function()
    -- Fields 8 and 12 of an ENVIRONMENTAL_DAMAGE event are the victim's GUID and the damage type.
    local _, subevent, _, _, _, _, _, destGUID, _, _, _, envType = CombatLogGetCurrentEventInfo()
    if subevent ~= "ENVIRONMENTAL_DAMAGE" or envType ~= "Falling" then return end
    -- The Midnight client can hand addons secret values, which cannot be compared.
    if issecretvalue and issecretvalue(destGUID) then return end
    if isGroupMember(destGUID) then play() end
end)

SLASH_BONECRACK1 = "/bonecrack"
SlashCmdList["BONECRACK"] = play
