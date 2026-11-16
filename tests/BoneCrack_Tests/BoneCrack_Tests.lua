-- Runs inside wowless at PLAYER_LOGIN, prints PASS/FAIL lines and quits with the result.
local passed, failed = 0, 0

local function check(cond, reason)
    if not cond then error(reason or "assertion failed", 0) end
end

local function run(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        __wowless.printf("PASS %s\n", name)
    else
        failed = failed + 1
        __wowless.printf("FAIL %s: %s\n", name, tostring(err))
    end
end

-- Replaces PlaySoundFile with a recorder while fn runs, then restores it.
local function record(fn)
    local original = PlaySoundFile
    local calls = {}
    PlaySoundFile = function(path, channel) calls[#calls + 1] = { path = path, channel = channel } end
    local ok, err = pcall(fn, calls)
    PlaySoundFile = original
    if not ok then error(err, 0) end
    return calls
end

local function isBoneCrack(path)
    return type(path) == "string" and path:match("bone%-crack%.ogg$") ~= nil
end

-- The addon's event handler is a local, so find its frame and call its OnEvent script.
local function findAddonFrame()
    local frame = EnumerateFrames()
    while frame do
        if frame.IsEventRegistered and frame:IsEventRegistered("COMBAT_LOG_EVENT_UNFILTERED")
            and frame:GetScript("OnEvent") then
            return frame
        end
        frame = EnumerateFrames(frame)
    end
end

local function fireCombatLog(frame, envType)
    local original = CombatLogGetCurrentEventInfo
    CombatLogGetCurrentEventInfo = function()
        return 0, "ENVIRONMENTAL_DAMAGE", false, nil, nil, nil, nil, UnitGUID("player"), "Name", 0, 0, envType, 10
    end
    local ok, err = pcall(frame:GetScript("OnEvent"), frame, "COMBAT_LOG_EVENT_UNFILTERED")
    CombatLogGetCurrentEventInfo = original
    if not ok then error(err, 0) end
end

-- wowless does not advance GetTime inside a busy loop, so jump the clock past the cooldown
-- from the earlier checks instead of waiting.
local clockJumps = 0
local function withLaterClock(fn)
    local original = GetTime
    clockJumps = clockJumps + 1
    local later = original() + 100 * clockJumps
    GetTime = function() return later end
    local ok, err = pcall(fn)
    GetTime = original
    if not ok then error(err, 0) end
end

local function runAll()
    run("slash command is registered", function()
        check(type(SlashCmdList["BONECRACK"]) == "function", "SlashCmdList.BONECRACK is not a function")
    end)

    run("slash command plays bone-crack.ogg once", function()
        local calls = record(function() SlashCmdList["BONECRACK"]() end)
        check(#calls == 1, "expected 1 play, got " .. #calls)
        check(isBoneCrack(calls[1].path), "unexpected path " .. tostring(calls[1].path))
    end)

    run("two back-to-back calls play only once", function()
        local before, after
        record(function(calls)
            SlashCmdList["BONECRACK"]()
            before = #calls
            SlashCmdList["BONECRACK"]()
            after = #calls
        end)
        check(before <= 1, "first call played " .. before .. " times")
        check(after == before, "second call played within the cooldown")
    end)

    local frame = findAddonFrame()
    run("addon frame with an OnEvent script is found", function()
        check(frame ~= nil, "no frame registered for COMBAT_LOG_EVENT_UNFILTERED")
    end)

    if frame then
        run("Falling damage to the player plays the sound", function()
            local calls = record(function() withLaterClock(function() fireCombatLog(frame, "Falling") end) end)
            check(#calls == 1, "expected 1 play, got " .. #calls)
            check(isBoneCrack(calls[1].path), "unexpected path " .. tostring(calls[1].path))
        end)

        run("non-Falling damage to the player stays silent", function()
            local calls = record(function() withLaterClock(function() fireCombatLog(frame, "Lava") end) end)
            check(#calls == 0, "expected 0 plays, got " .. #calls)
        end)
    end

    __wowless.printf("RESULT %d passed, %d failed\n", passed, failed)
    __wowless.quit(failed == 0 and 0 or 1)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", runAll)
