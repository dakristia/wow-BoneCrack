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
                UnitIsVisible = function() return not opts.far end,
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
-- state has hidden, swimming, flying and combat, which the test can edit. step(time, falling) sets the fake
-- clock and IsFalling, then calls the addon's OnUpdate.
-- The addon's wasFalling state persists between checks, and the earlier checks leave it true. So the
-- helper first steps with IsFalling false and readable health, which makes the addon call landed()
-- without a play, and every check ends with a step where IsFalling is false.
local function withFall(frame, fn)
    local state = { hidden = false, swimming = false, flying = false, combat = false }
    local now, falling = 0, false
    return record(function()
        withLaterClock(function()
            local base = GetTime()
            withStubs({
                GetTime = function() return now end,
                IsFalling = function() return falling end,
                IsSwimming = function() return state.swimming end,
                IsFlying = function() return state.flying end,
                UnitAffectingCombat = function() return state.combat end,
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

    -- BoneCrack.lua shares its private table through one global, because a test addon has its own table.
    local ns = BoneCrackNS

    run("encodeFall and decodeFall round trip", function()
        check(ns and ns.encodeFall and ns.decodeFall, "ns functions are missing")
        local text = ns.encodeFall({ loss = 0.25, air = 2.1, dead = true, map = 84 })
        check(text == "fell2:0.250:2.10:1:84", "unexpected text " .. tostring(text))
        local info = ns.decodeFall(text)
        check(info.loss == 0.25 and info.air == 2.1 and info.dead == true and info.map == 84, "round trip differs")
        local bare = ns.decodeFall(ns.encodeFall({ air = 1.5, dead = false }))
        check(bare.loss == nil and bare.map == nil and bare.air == 1.5 and bare.dead == false, "bare round trip differs")
        check(ns.encodeFall({ air = 1.5, dead = false }) == "fell2:-:1.50:0:-", "unexpected bare text")
    end)

    run("decodeFall returns nil for malformed text without erroring", function()
        for _, text in ipairs({ "fell2:", "fell2:x:y:z:w", "fell", "", "fell2:0.1:2:3:4", "fell2:-:1.0:1:-:extra" }) do
            local ok, result = pcall(ns.decodeFall, text)
            check(ok, "decodeFall errored on " .. text)
            check(result == nil, "expected nil for " .. text)
        end
        for _, junk in ipairs({ 5, true, {} }) do
            local ok, result = pcall(ns.decodeFall, junk)
            check(ok and result == nil, "decodeFall mishandled " .. type(junk))
        end
        check(select("#", pcall(ns.decodeFall, nil)) == 2, "decodeFall errored on nil")
    end)

    run("fallTier sorts by loss, air time and death", function()
        local function tier(info) return ns.fallTier(info) end
        check(tier({ loss = 0.099, air = 1, dead = false }) == 0, "0.099 is not small")
        check(tier({ loss = 0.10, air = 1, dead = false }) == 1, "0.10 is not medium")
        check(tier({ loss = 0.30, air = 1, dead = false }) == 1, "0.30 is not medium")
        check(tier({ loss = 0.301, air = 1, dead = false }) == 2, "0.301 is not big")
        check(tier({ loss = 0.05, air = 1, dead = true }) == 3, "dead is not death")
        check(tier({ air = 1.9, dead = false }) == 0, "1.9s is not small")
        check(tier({ air = 2.0, dead = false }) == 1, "2.0s is not medium")
        check(tier({ air = 2.59, dead = false }) == 1, "2.59s is not medium")
        check(tier({ air = 2.6, dead = false }) == 2, "2.6s is not big")
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

        run("far-away party member losing 10% out of combat stays silent", function()
            -- party5 is not visible to the client, so its combat flag cannot be trusted.
            local calls = withHealth(frame, { combat = false, far = true }, function(fire)
                fire("party5", 100)
                fire("party5", 90)
            end)
            check(#calls == 0, "expected 0 plays, got " .. #calls)
        end)

        -- The fall checks use withFall, which resets the addon's falling state and uses a later clock.
        run("hidden health and a 2.0s fall plays the sound", function()
            local calls = withFall(frame, function(state, step)
                state.hidden = true
                step(10, true)
                step(12, false)
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

        run("hidden health and a 2.0s fall ending in water stays silent", function()
            local calls = withFall(frame, function(state, step)
                state.hidden = true
                step(10, true)
                state.swimming = true
                step(12, false)
            end)
            check(#calls == 0, "expected 0 plays, got " .. #calls)
        end)

        run("readable health and a 2.0s fall stays silent", function()
            -- No UNIT_HEALTH event is fired, so only the fall fallback could play.
            local calls = withFall(frame, function(state, step)
                step(10, true)
                step(12, false)
            end)
            check(#calls == 0, "expected 0 plays, got " .. #calls)
        end)

        -- woundsReadable in the addon is a module local that stays true once a readable UNIT_COMBAT
        -- for the player arrives. So every check that needs it false runs before the first check
        -- that fires such an event (the WOUND checks at the end of this file).
        run("hidden health and a 1.4s fall stays silent without a readable WOUND", function()
            local calls = withFall(frame, function(state, step)
                state.hidden = true
                step(10, true)
                step(11.4, false)
            end)
            check(#calls == 0, "expected 0 plays, got " .. #calls)
        end)

        run("hidden health and a 1.8s fall plays the sound without a readable WOUND", function()
            local calls = withFall(frame, function(state, step)
                state.hidden = true
                step(10, true)
                step(11.8, false)
            end)
            check(#calls == 1, "expected 1 play, got " .. #calls)
        end)

        -- Runs a hidden-health 2.0s fall with the group and chat APIs stubbed. Returns the recorded
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
                        step(12, false)
                    end)
                end)
                return result
            end)
            chat.SendAddonMessage = originals.SendAddonMessage
            chat.InChatMessagingLockdown = originals.InChatMessagingLockdown
            if not ok then error(calls, 0) end
            return calls, sent
        end

        run("own fall in a party plays once and sends details then fell to PARTY", function()
            local calls, sent = fallInGroup({ group = true })
            check(#calls == 1, "expected 1 play, got " .. #calls)
            check(#sent == 2, "expected 2 messages, got " .. #sent)
            check(sent[1].prefix == "BoneCrack", "unexpected prefix " .. tostring(sent[1].prefix))
            check(sent[1].text:match("^fell2:") ~= nil, "first message is not details: " .. tostring(sent[1].text))
            check(sent[2].prefix == "BoneCrack", "unexpected prefix " .. tostring(sent[2].prefix))
            check(sent[2].text == "fell", "unexpected text " .. tostring(sent[2].text))
            check(sent[1].channel == "PARTY", "unexpected channel " .. tostring(sent[1].channel))
            check(sent[2].channel == "PARTY", "unexpected channel " .. tostring(sent[2].channel))
        end)

        run("own fall in a raid sends both messages to RAID", function()
            local calls, sent = fallInGroup({ group = true, raid = true })
            check(#calls == 1, "expected 1 play, got " .. #calls)
            check(#sent == 2, "expected 2 messages, got " .. #sent)
            check(sent[1].channel == "RAID", "unexpected channel " .. tostring(sent[1].channel))
            check(sent[2].channel == "RAID", "unexpected channel " .. tostring(sent[2].channel))
        end)

        run("own fall sends details that decode to the fall's air time", function()
            local _, sent = fallInGroup({ group = true })
            local info = ns.decodeFall(sent[1].text)
            check(info ~= nil, "details did not decode: " .. tostring(sent[1].text))
            check(info.loss == nil, "expected no loss for hidden health")
            check(info.air == 2, "expected 2.0 air, got " .. tostring(info.air))
            check(info.dead == false, "expected dead false")
        end)

        run("own fall calls onFall with player and the info", function()
            local who, got, n = nil, nil, 0
            local original = ns.onFall
            ns.onFall = function(w, i) who, got, n = w, i, n + 1 end
            local ok, err = pcall(fallInGroup, { group = false })
            ns.onFall = original
            if not ok then error(err, 0) end
            check(n == 1, "expected 1 onFall call, got " .. n)
            check(who == "player", "unexpected who " .. tostring(who))
            check(got.air == 2 and got.loss == nil and got.dead == false, "unexpected info")
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

        -- Fires several CHAT_MSG_ADDON events in order on one clock, like messages on one channel.
        -- Each message is { text, sender }. Returns the recorded plays and the onFall calls.
        local function receiveAll(messages)
            local falls = {}
            local original = ns.onFall
            ns.onFall = function(who, info) falls[#falls + 1] = { who = who, info = info } end
            local ok, calls = pcall(function()
                return record(function()
                    withLaterClock(function()
                        withStubs({
                            Ambiguate = function(name) return (name:gsub("%-.*$", "")) end,
                            UnitName = function(unit) if unit == "player" then return "Me" end end,
                        }, function()
                            for _, m in ipairs(messages) do
                                frame:GetScript("OnEvent")(frame, "CHAT_MSG_ADDON", "BoneCrack", m[1], "PARTY", m[2])
                            end
                        end)
                    end)
                end)
            end)
            ns.onFall = original
            if not ok then error(calls, 0) end
            return calls, falls
        end

        run("details then fell from a new client plays once", function()
            local calls = receiveAll({ { "fell2:0.250:2.10:0:1", "New-Realm" }, { "fell", "New-Realm" } })
            check(#calls == 1, "expected 1 play, got " .. #calls)
        end)

        run("a lone fell from an old client plays and calls no onFall", function()
            local calls, falls = receiveAll({ { "fell", "Old-Realm" } })
            check(#calls == 1, "expected 1 play, got " .. #calls)
            check(#falls == 0, "expected 0 onFall calls, got " .. #falls)
        end)

        run("details message calls onFall with the sender and decoded info", function()
            local calls, falls = receiveAll({ { "fell2:0.250:2.10:1:1", "New-Realm" } })
            check(#calls == 1, "expected 1 play, got " .. #calls)
            check(#falls == 1, "expected 1 onFall call, got " .. #falls)
            check(falls[1].who == "New-Realm", "unexpected who " .. tostring(falls[1].who))
            check(falls[1].info.loss == 0.25 and falls[1].info.air == 2.1, "unexpected loss or air")
            check(falls[1].info.dead == true and falls[1].info.map == 1, "unexpected dead or map")
        end)

        run("malformed details message stays silent", function()
            local calls, falls = receiveAll({ { "fell2:x:y:z:w", "New-Realm" } })
            check(#calls == 0, "expected 0 plays, got " .. #calls)
            check(#falls == 0, "expected 0 onFall calls, got " .. #falls)
        end)

        run("fall message from the player's own name stays silent", function()
            local calls = receive("BoneCrack", "fell", "PARTY", "Me-Realm")
            check(#calls == 0, "expected 0 plays, got " .. #calls)
        end)

        run("addon message with another prefix stays silent", function()
            local calls = receive("OtherAddon", "fell", "PARTY", "Friend-Realm")
            check(#calls == 0, "expected 0 plays, got " .. #calls)
        end)

        -- Debug log checks. UNIT_COMBAT for party1 logs a line but never sets woundsReadable, and debug
        -- is off again at the end, so later checks see the same state as before.
        local function combatLine(n)
            frame:GetScript("OnEvent")(frame, "UNIT_COMBAT", "party1", "HIT", "", n, 1)
        end

        run("debug on saves a line to BoneCrackDebugLog", function()
            SlashCmdList["BONECRACK"]("debug")
            local ok, err = pcall(function()
                BoneCrackDebugLog = {}
                combatLine(1)
                check(#BoneCrackDebugLog == 1, "expected 1 line, got " .. #BoneCrackDebugLog)
                check(BoneCrackDebugLog[1]:find("UNIT_COMBAT party1", 1, true) ~= nil,
                    "unexpected line " .. tostring(BoneCrackDebugLog[1]))
            end)
            SlashCmdList["BONECRACK"]("debug")
            if not ok then error(err, 0) end
        end)

        run("debug log keeps only the newest 500 lines", function()
            SlashCmdList["BONECRACK"]("debug")
            local ok, err = pcall(function()
                for i = 1, 520 do combatLine(i) end
                check(#BoneCrackDebugLog == 500, "expected 500 lines, got " .. #BoneCrackDebugLog)
                local last = BoneCrackDebugLog[#BoneCrackDebugLog]
                check(last:find("party1 HIT  520 1", 1, true) ~= nil, "last line is not the newest: " .. tostring(last))
            end)
            SlashCmdList["BONECRACK"]("debug")
            if not ok then error(err, 0) end
        end)

        run("debug off keeps the log and debug on no longer clears it", function()
            check(#BoneCrackDebugLog == 500, "debug off did not keep the log")
            combatLine(1)
            check(#BoneCrackDebugLog == 500, "a line was logged while debug was off")
            SlashCmdList["BONECRACK"]("debug")
            local count = #BoneCrackDebugLog
            SlashCmdList["BONECRACK"]("debug")
            check(count == 500, "expected the log to stay at 500 lines after debug on, got " .. count)
        end)

        run("debug on sets BoneCrackDebug to true and off sets it to false", function()
            SlashCmdList["BONECRACK"]("debug")
            local onValue = BoneCrackDebug
            SlashCmdList["BONECRACK"]("debug")
            check(onValue == true, "expected BoneCrackDebug true after debug on, got " .. tostring(onValue))
            check(BoneCrackDebug == false, "expected BoneCrackDebug false after debug off, got " .. tostring(BoneCrackDebug))
        end)

        run("debug does not print each log line to chat", function()
            local printed = 0
            local original = print
            print = function() printed = printed + 1 end
            SlashCmdList["BONECRACK"]("debug")
            local ok, err = pcall(function()
                local before = printed
                combatLine(1)
                check(printed == before, "log printed " .. (printed - before) .. " lines to chat")
            end)
            SlashCmdList["BONECRACK"]("debug")
            print = original
            if not ok then error(err, 0) end
        end)

        run("clearlog empties the log", function()
            SlashCmdList["BONECRACK"]("debug")
            local ok, err = pcall(function()
                BoneCrackDebugLog = {}
                combatLine(1)
                check(#BoneCrackDebugLog == 1, "expected 1 line, got " .. #BoneCrackDebugLog)
                SlashCmdList["BONECRACK"]("clearlog")
                check(#BoneCrackDebugLog == 0, "log was not cleared")
            end)
            SlashCmdList["BONECRACK"]("debug")
            if not ok then error(err, 0) end
        end)

        -- WOUND checks. The first one that fires a readable UNIT_COMBAT sets woundsReadable for the
        -- rest of the run, so no check that needs it false may come after this point.
        local function wound()
            frame:GetScript("OnEvent")(frame, "UNIT_COMBAT", "player", "WOUND", "", 50, 1)
        end

        -- withFall with IsInGroup false, so nothing is sent.
        local function soloFall(fn)
            local result
            withStubs({ IsInGroup = function() return false end, IsInRaid = function() return false end }, function()
                result = withFall(frame, fn)
            end)
            return result
        end

        -- This check must fire the first readable UNIT_COMBAT, because it covers a login where the
        -- addon has not seen one yet.
        run("hidden health, 1.4s fall and the first WOUND 0.2s after landing plays the sound", function()
            local calls = soloFall(function(state, step)
                state.hidden = true
                step(10, true)
                step(11.4, false)
                step(11.6, false)
                wound()
            end)
            check(#calls == 1, "expected 1 play, got " .. #calls)
        end)

        run("hidden health, 1.2s fall and a WOUND 0.1s before landing plays the sound", function()
            local calls = soloFall(function(state, step)
                state.hidden = true
                step(10, true)
                step(11.1, true)
                wound()
                step(11.2, false)
            end)
            check(#calls == 1, "expected 1 play, got " .. #calls)
        end)

        run("hidden health, 1.2s fall and a WOUND 0.2s after landing plays the sound", function()
            local calls = soloFall(function(state, step)
                state.hidden = true
                step(10, true)
                step(11.2, false)
                step(11.3, false)
                step(11.4, false)
                wound()
            end)
            check(#calls == 1, "expected 1 play, got " .. #calls)
        end)

        run("hidden health and a 2.5s fall without a WOUND stays silent once wounds are readable", function()
            local calls = soloFall(function(state, step)
                state.hidden = true
                step(10, true)
                step(12.5, false)
                step(12.8, false)
                step(13.2, false)
            end)
            check(#calls == 0, "expected 0 plays, got " .. #calls)
        end)

        run("hidden health and a 0.7s jump with a WOUND stays silent", function()
            local calls = soloFall(function(state, step)
                state.hidden = true
                step(10, true)
                step(10.6, true)
                wound()
                step(10.7, false)
            end)
            check(#calls == 0, "expected 0 plays, got " .. #calls)
        end)

        run("hidden health, 1.2s fall and a WOUND 0.8s after landing stays silent", function()
            local calls = soloFall(function(state, step)
                state.hidden = true
                step(10, true)
                step(11.2, false)
                step(11.8, false)
                step(12.0, false)
                wound()
            end)
            check(#calls == 0, "expected 0 plays, got " .. #calls)
        end)

        run("in combat, hidden health, 1.2s fall and a WOUND at landing stays silent", function()
            local calls = soloFall(function(state, step)
                state.hidden = true
                state.combat = true
                step(10, true)
                step(11.1, true)
                wound()
                step(11.2, false)
            end)
            check(#calls == 0, "expected 0 plays, got " .. #calls)
        end)

        run("in combat, hidden health, 2.0s fall and a WOUND at landing plays the sound", function()
            local calls = soloFall(function(state, step)
                state.hidden = true
                state.combat = true
                step(10, true)
                step(11.9, true)
                wound()
                step(12, false)
            end)
            check(#calls == 1, "expected 1 play, got " .. #calls)
        end)
    end

    __wowless.printf("RESULT %d passed, %d failed\n", passed, failed)
    __wowless.quit(failed == 0 and 0 or 1)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", runAll)
