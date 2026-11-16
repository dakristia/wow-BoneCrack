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

-- Runs fn(state, step) with the fall APIs stubbed on a later fake clock, and returns the recorded plays.
-- state has hidden, swimming and flying, which the test can edit. step(time, falling) sets the fake
-- clock and IsFalling, then calls the addon's OnUpdate.
-- The addon's wasFalling state persists between checks, and the earlier checks leave it true. So the
-- helper first steps with IsFalling false and readable health, which makes the addon call landed()
-- without a play, and every check ends with a step where IsFalling is false.
local function withFall(frame, fn)
    local state = { hidden = false, swimming = false, flying = false }
    local now, falling = 0, false
    return record(function()
        withLaterClock(function()
            local base = GetTime()
            withStubs({
                GetTime = function() return now end,
                IsFalling = function() return falling end,
                IsSwimming = function() return state.swimming end,
                IsFlying = function() return state.flying end,
                UnitHealth = function() return state.hidden and "SECRET" or 100 end,
                issecretvalue = function(v) return state.hidden and v == "SECRET" end,
            }, function()
                local function step(offset, isFalling)
                    now, falling = base + offset, isFalling
                    frame:GetScript("OnUpdate")(frame, 0)
                end
                local hidden = state.hidden
                state.hidden = false
                step(0, false)
                state.hidden = hidden
                fn(state, step)
                step(100, false)
            end)
        end)
    end)
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

        -- The fall checks use withFall, which resets the addon's falling state and uses a later clock.
        run("hidden health and a 1.5s fall plays the sound", function()
            local calls = withFall(frame, function(state, step)
                state.hidden = true
                step(10, true)
                step(11.5, false)
            end)
            check(#calls == 1, "expected 1 play, got " .. #calls)
            check(isBoneCrack(calls[1].path), "unexpected path " .. tostring(calls[1].path))
        end)

        run("hidden health and a 0.5s fall stays silent", function()
            local calls = withFall(frame, function(state, step)
                state.hidden = true
                step(10, true)
                step(10.5, false)
            end)
            check(#calls == 0, "expected 0 plays, got " .. #calls)
        end)

        run("hidden health and a 1.5s fall ending in water stays silent", function()
            local calls = withFall(frame, function(state, step)
                state.hidden = true
                step(10, true)
                state.swimming = true
                step(11.5, false)
            end)
            check(#calls == 0, "expected 0 plays, got " .. #calls)
        end)

        run("readable health and a 1.5s fall stays silent", function()
            -- No UNIT_HEALTH event is fired, so only the fall fallback could play.
            local calls = withFall(frame, function(state, step)
                step(10, true)
                step(11.5, false)
            end)
            check(#calls == 0, "expected 0 plays, got " .. #calls)
        end)

        -- Runs a hidden-health 1.5s fall with the group and chat APIs stubbed. Returns the recorded
        -- plays and the addon messages that were sent.
        local function fallInGroup(opts)
            local sent = {}
            local chat = C_ChatInfo
            local originals = {
                SendAddonMessage = chat.SendAddonMessage,
                InChatMessagingLockdown = chat.InChatMessagingLockdown,
            }
            chat.SendAddonMessage = function(prefix, text, channel)
                sent[#sent + 1] = { prefix = prefix, text = text, channel = channel }
                return 0
            end
            chat.InChatMessagingLockdown = function() return opts.lockdown or false end
            local ok, calls = pcall(function()
                local result
                withStubs({
                    IsInGroup = function() return opts.group or false end,
                    IsInRaid = function() return opts.raid or false end,
                }, function()
                    result = withFall(frame, function(state, step)
                        state.hidden = true
                        step(10, true)
                        step(11.5, false)
                    end)
                end)
                return result
            end)
            chat.SendAddonMessage = originals.SendAddonMessage
            chat.InChatMessagingLockdown = originals.InChatMessagingLockdown
            if not ok then error(calls, 0) end
            return calls, sent
        end

        run("own fall in a party plays once and sends fell to PARTY", function()
            local calls, sent = fallInGroup({ group = true })
            check(#calls == 1, "expected 1 play, got " .. #calls)
            check(#sent == 1, "expected 1 message, got " .. #sent)
            check(sent[1].prefix == "BoneCrack", "unexpected prefix " .. tostring(sent[1].prefix))
            check(sent[1].text == "fell", "unexpected text " .. tostring(sent[1].text))
            check(sent[1].channel == "PARTY", "unexpected channel " .. tostring(sent[1].channel))
        end)

        run("own fall in a raid sends fell to RAID", function()
            local calls, sent = fallInGroup({ group = true, raid = true })
            check(#calls == 1, "expected 1 play, got " .. #calls)
            check(#sent == 1, "expected 1 message, got " .. #sent)
            check(sent[1].channel == "RAID", "unexpected channel " .. tostring(sent[1].channel))
        end)

        run("own fall during chat lockdown plays once and sends nothing", function()
            local calls, sent = fallInGroup({ group = true, lockdown = true })
            check(#calls == 1, "expected 1 play, got " .. #calls)
            check(#sent == 0, "expected 0 messages, got " .. #sent)
        end)

        run("own fall outside a group plays once and sends nothing", function()
            local calls, sent = fallInGroup({ group = false })
            check(#calls == 1, "expected 1 play, got " .. #calls)
            check(#sent == 0, "expected 0 messages, got " .. #sent)
        end)

        -- Fires CHAT_MSG_ADDON at the addon frame on a later clock and returns the recorded plays.
        local function receive(...)
            local args = { ... }
            return record(function()
                withLaterClock(function()
                    -- wowless has no real Ambiguate, so this strips the realm like a same-realm "none" does.
                    withStubs({
                        Ambiguate = function(name) return (name:gsub("%-.*$", "")) end,
                        UnitName = function(unit) if unit == "player" then return "Me" end end,
                    }, function()
                        frame:GetScript("OnEvent")(frame, "CHAT_MSG_ADDON", unpack(args))
                    end)
                end)
            end)
        end

        run("fall message from a group member plays the sound", function()
            local calls = receive("BoneCrack", "fell", "PARTY", "Friend-Realm")
            check(#calls == 1, "expected 1 play, got " .. #calls)
            check(isBoneCrack(calls[1].path), "unexpected path " .. tostring(calls[1].path))
        end)

        run("fall message from the player's own name stays silent", function()
            local calls = receive("BoneCrack", "fell", "PARTY", "Me-Realm")
            check(#calls == 0, "expected 0 plays, got " .. #calls)
        end)

        run("addon message with another prefix stays silent", function()
            local calls = receive("OtherAddon", "fell", "PARTY", "Friend-Realm")
            check(#calls == 0, "expected 0 plays, got " .. #calls)
        end)
    end

    __wowless.printf("RESULT %d passed, %d failed\n", passed, failed)
    __wowless.quit(failed == 0 and 0 or 1)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", runAll)
