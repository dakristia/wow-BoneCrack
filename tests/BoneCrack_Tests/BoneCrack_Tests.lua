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

-- Sets globals while fn runs, then restores them.
local function withStubs(stubs, fn)
    local originals = {}
    for name, value in pairs(stubs) do
        originals[name] = _G[name]
        _G[name] = value
    end
    local ok, err = pcall(fn)
    for name, value in pairs(stubs) do _G[name] = originals[name] end
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

-- Runs fn(unitHealth, fire, update) with health and combat APIs stubbed on a later fake clock.
-- unitHealth is a table the test edits; fire(unit, hp) sets the health and sends UNIT_HEALTH.
local function withHealth(frame, opts, fn)
    local hp, maxhp = {}, {}
    local calls = record(function()
        withLaterClock(function()
            withStubs({
                UnitHealth = function(u) return hp[u] end,
                UnitHealthMax = function(u) return maxhp[u] or 100 end,
                IsFalling = function() return opts.falling or false end,
                UnitIsUnit = function(a, b) return a == b end,
                UnitAffectingCombat = function() return opts.combat or false end,
            }, function()
                local function fire(unit, value)
                    hp[unit] = value
                    frame:GetScript("OnEvent")(frame, "UNIT_HEALTH", unit)
                end
                fn(fire, function() frame:GetScript("OnUpdate")(frame, 0) end)
            end)
        end)
    end)
    return calls
end

-- The addon's handlers are locals, so find its frame and call its scripts. wowless has no
-- debug.getinfo and Blizzard frames also register UNIT_HEALTH, so this keeps the unnamed frames
-- that have both scripts and picks the one that plays the sound when party4 drops 10% out of
-- combat. Blizzard frames cannot play it, and errors from them are ignored. This uses up the
-- party4 baseline, so no check below uses party4.
local function findAddonFrame()
    local frame = EnumerateFrames()
    while frame do
        if frame.IsEventRegistered and frame:IsEventRegistered("UNIT_HEALTH") and not frame:GetName()
            and frame:GetScript("OnEvent") and frame:GetScript("OnUpdate") then
            local candidate = frame
            local ok, calls = pcall(withHealth, candidate, {}, function(fire)
                fire("party4", 100)
                fire("party4", 90)
            end)
            if ok and #calls == 1 then return candidate end
        end
        frame = EnumerateFrames(frame)
    end
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
    run("addon frame with OnEvent and OnUpdate scripts is found", function()
        check(frame ~= nil, "no UNIT_HEALTH frame with an OnEvent function from BoneCrack")
        check(frame:GetScript("OnUpdate") ~= nil, "addon frame has no OnUpdate script")
    end)

    if frame then
        -- The addon keeps a health table across checks, so each check uses a unit or a fresh
        -- baseline that no earlier check left behind. Each check also gets a later clock, so the
        -- play cooldown from earlier checks is over.
        run("player losing health while falling plays the sound", function()
            local calls = withHealth(frame, { falling = true }, function(fire, update)
                update()
                fire("player", 100)
                update()
                fire("player", 70)
            end)
            check(#calls == 1, "expected 1 play, got " .. #calls)
            check(isBoneCrack(calls[1].path), "unexpected path " .. tostring(calls[1].path))
        end)

        run("player losing health while not falling stays silent", function()
            -- The clock is 100s later than the falling check, so lastFalling is outside the window.
            local calls = withHealth(frame, { falling = false }, function(fire, update)
                update()
                fire("player", 100)
                update()
                fire("player", 70)
            end)
            check(#calls == 0, "expected 0 plays, got " .. #calls)
        end)

        run("party member losing 10% out of combat plays the sound", function()
            local calls = withHealth(frame, { combat = false }, function(fire)
                fire("party1", 100)
                fire("party1", 90)
            end)
            check(#calls == 1, "expected 1 play, got " .. #calls)
            check(isBoneCrack(calls[1].path), "unexpected path " .. tostring(calls[1].path))
        end)

        run("party member losing 10% in combat stays silent", function()
            -- party2 keeps its own baseline apart from party1.
            local calls = withHealth(frame, { combat = true }, function(fire)
                fire("party2", 100)
                fire("party2", 90)
            end)
            check(#calls == 0, "expected 0 plays, got " .. #calls)
        end)

        run("party member losing 2% out of combat stays silent", function()
            local calls = withHealth(frame, { combat = false }, function(fire)
                fire("party3", 100)
                fire("party3", 98)
            end)
            check(#calls == 0, "expected 0 plays, got " .. #calls)
        end)
    end

    __wowless.printf("RESULT %d passed, %d failed\n", passed, failed)
    __wowless.quit(failed == 0 and 0 or 1)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", runAll)
