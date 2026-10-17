-- ========================================================
-- 1. Roblox Executor MCP Auto-Loader (AI Bridge)
-- ========================================================
task.spawn(function()
    while not getgenv().MCP_Loaded do
        local bridgeUrl = getgenv().BridgeURL or "localhost:16384"
        pcall(function() loadstring(game:HttpGet("http://" .. bridgeUrl .. "/script.luau"))() end)
        task.wait(0.5)
    end
end)

-- ========================================================
-- 2. Anime Zero 24/7 Web Tracker (Cloud & Local)
-- ========================================================
repeat task.wait(0.5) until game:IsLoaded()

local Players = game:GetService("Players")
local player = Players.LocalPlayer or Players.PlayerAdded:Wait()
local Rep = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local CLOUD_SERVER_URL = "https://anime-zero-tracker.onrender.com/api/report"
local LOCAL_SERVER_URL = "http://localhost:18888/api/report"
local BASELINE_FILE = "AnimeZero_Tracker_Baseline.json"

-- Stop previous running instance if reloaded
if getgenv().AnimeZeroTrackerStop then
    pcall(getgenv().AnimeZeroTrackerStop)
end

local isRunning = true
getgenv().AnimeZeroTrackerStop = function()
    isRunning = false
end

local function sendHttp(payload)
    local fn = request or http_request or (syn and syn.request)
    if not fn then return end
    local body = HttpService:JSONEncode(payload)
    -- Send to Cloud 24/7 Dashboard (Render)
    pcall(function()
        fn({
            Url = CLOUD_SERVER_URL,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = body
        })
    end)
    -- Send to Local Dashboard
    pcall(function()
        fn({
            Url = LOCAL_SERVER_URL,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = body
        })
    end)
end

local function getVal(v)
    if type(v) == "table" and v.current ~= nil then return v.current end
    return v
end

local function safeReadBaseline()
    if type(readfile) ~= "function" or type(isfile) ~= "function" then return nil end
    local ok, content = pcall(function()
        if isfile(BASELINE_FILE) then
            return HttpService:JSONDecode(readfile(BASELINE_FILE))
        end
        return nil
    end)
    return ok and content or nil
end

local function safeWriteBaseline(data)
    if type(writefile) ~= "function" then return end
    pcall(function()
        writefile(BASELINE_FILE, HttpService:JSONEncode(data))
    end)
end

task.spawn(function()
    print("[AnimeZero Tracker] Initializing tracker with Dual-Cloud & Live Real-Time...")

    local accStore, matConfig, accConfig, levelProg, charRoll
    for i = 1, 30 do
        pcall(function()
            accStore = require(Rep:WaitForChild("global", 5):WaitForChild("stores", 5):WaitForChild("accountNamespace", 5))
            matConfig = require(Rep:WaitForChild("assets", 5):WaitForChild("config", 5):WaitForChild("materialConfig", 5))
            accConfig = require(Rep:WaitForChild("assets", 5):WaitForChild("config", 5):WaitForChild("accessoryConfig", 5))
            levelProg = require(Rep:WaitForChild("global", 5):WaitForChild("utils", 5):WaitForChild("levelProgression", 5))
            charRoll = require(Rep:WaitForChild("assets", 5):WaitForChild("config", 5):WaitForChild("characterRollConfig", 5))
        end)
        if accStore and matConfig and accConfig and levelProg then break end
        task.wait(1)
    end

    if not accStore then
        warn("[AnimeZero Tracker] accountNamespace could not be loaded.")
        return
    end

    local function getSnapshot()
        local acc = accStore.getLocalPlayerAccount()
        if not acc or not acc.state then return nil end

        local currencies = {}
        if acc.state.currencies then
            for k, v in pairs(acc.state.currencies) do
                if type(v) == "table" and v.current ~= nil then
                    currencies[k] = tonumber(v.current) or v.current
                end
            end
        end

        local materials = {}
        if acc.state.material and acc.state.material.entries then
            for id, v in pairs(acc.state.material.entries) do
                local count = tonumber(getVal(v)) or 0
                if count > 0 then
                    local info = (matConfig and (matConfig[tonumber(id)] or matConfig[tostring(id)])) or {}
                    materials[tostring(id)] = {
                        id = tostring(id),
                        name = info.Name or info.name or ("Material " .. id),
                        count = count,
                        tier = tostring(info.Tier or "1"),
                        rarity = (info.Tier == "4" and "Legendary") or (info.Tier == "3" and "Epic") or (info.Tier == "2" and "Rare") or "Common",
                        icon = tostring(info.Icon or ""),
                        description = info.Description or ""
                    }
                end
            end
        end

        local accessories = {}
        if acc.state.accessory and acc.state.accessory.entries then
            for id, v in pairs(acc.state.accessory.entries) do
                local count = tonumber(getVal(v)) or 0
                if count > 0 then
                    local info = (accConfig and (accConfig[tonumber(id)] or accConfig[tostring(id)])) or {}
                    accessories[tostring(id)] = {
                        id = tostring(id),
                        name = info.Name or info.name or ("Accessory " .. id),
                        count = count,
                        tier = tostring(info.Tier or "1"),
                        rarity = (info.Tier == "4" and "Legendary") or (info.Tier == "3" and "Epic") or (info.Tier == "2" and "Rare") or "Common",
                        icon = tostring(info.Icon or ""),
                        slot = tostring(info.Slot or ""),
                        description = info.Description or ""
                    }
                end
            end
        end

        -- Characters Progression
        local chars = {}
        if acc.state.CharactersData and levelProg then
            for charName, charData in pairs(acc.state.CharactersData) do
                if type(charData) == "table" and charData.Progression and charData.Progression.Xp then
                    local xpVal = charData.Progression.Xp.current or "0"
                    local prog = levelProg.getProgress(xpVal)
                    local skills = {}
                    if charData.Progression.Skills then
                        for sk, sv in pairs(charData.Progression.Skills) do
                            if type(sv) == "number" or (type(sv) == "table" and sv.current) then
                                skills[sk] = type(sv) == "table" and sv.current or sv
                            end
                        end
                    end
                    table.insert(chars, {
                        id = charName,
                        name = charName:gsub("_", " "):gsub("^%l", string.upper),
                        rarity = (charRoll and charRoll.rarityByCharacter and charRoll.rarityByCharacter[charName]) or "Common",
                        level = prog and prog.level or 0,
                        currentXp = prog and tonumber(prog.currentXp) or 0,
                        requiredXp = prog and tonumber(prog.requiredXp) or 100,
                        ratio = prog and prog.ratio or 0,
                        skills = skills
                    })
                end
            end
        end
        table.sort(chars, function(a, b) return a.level > b.level end)

        local playerXp = currencies.xp or 0
        local playerProg = levelProg and levelProg.getProgress(tostring(playerXp))

        local matches = {}
        if acc.state.matchHistory and acc.state.matchHistory.current then
            pcall(function()
                matches = HttpService:JSONDecode(acc.state.matchHistory.current)
            end)
        end

        local level = (playerProg and tonumber(playerProg.level) and tonumber(playerProg.level) > 0 and tonumber(playerProg.level)) or 0
        if level == 0 then
            local leaderstats = player:FindFirstChild("leaderstats")
            if leaderstats and leaderstats:FindFirstChild("Level") and leaderstats.Level.Value > 0 then
                level = leaderstats.Level.Value
            end
        end
        if level == 0 and currencies.level then
            level = tonumber(currencies.level) or 0
        end

        return {
            player = {
                name = player.Name,
                displayName = player.DisplayName,
                userId = player.UserId,
                level = level,
                guild = player:GetAttribute("GuildName") or "None"
            },
            playerProg = playerProg,
            characters = chars,
            currencies = currencies,
            materials = materials,
            accessories = accessories,
            matches = matches,
            latestMatch = matches[1],
            timestamp = os.time()
        }
    end

    local current = nil
    while not current and isRunning do
        current = getSnapshot()
        task.wait(1)
    end
    if not isRunning then return end

    local baseline = safeReadBaseline() or current
    local lastMatchTime = (baseline.latestMatch and baseline.latestMatch.time) or 0
    local lastLoggedMatchTime = os.time()
    local matchStartTime = os.time()
    local heartbeatTick = 0

    sendHttp({
        type = "init",
        player = current.player,
        playerProg = current.playerProg,
        characters = current.characters,
        currencies = current.currencies,
        materials = current.materials,
        accessories = current.accessories,
        latestMatch = current.latestMatch
    })

    print("[AnimeZero Tracker] Connected to Web Dashboard (Cloud & Local)!")

    local cKeys = {
        { key = "gems", name = "Gems", icon = "💎" },
        { key = "money", name = "Gold", icon = "🪙" },
        { key = "luckySpins", name = "Lucky Spins", icon = "🎲" },
        { key = "traitRerolls", name = "Trait Rerolls", icon = "🔄" },
        { key = "rolls", name = "Rolls", icon = "📜" },
        { key = "xp", name = "XP", icon = "⚡" }
    }

    while isRunning and task.wait(1.5) do
        local nowState = getSnapshot()
        if nowState then
            local currentLatest = nowState.latestMatch
            local isNewMatch = currentLatest and currentLatest.time and (currentLatest.time > lastMatchTime)
            local rewards = {}

            for _, item in ipairs(cKeys) do
                local curVal = tonumber(nowState.currencies[item.key]) or 0
                local prevVal = tonumber(baseline.currencies[item.key]) or 0
                local delta = curVal - prevVal
                if delta > 0 then
                    table.insert(rewards, {
                        category = "currency",
                        name = item.name,
                        amount = delta,
                        icon = item.icon
                    })
                end
            end

            for id, mat in pairs(nowState.materials) do
                local prevCount = (baseline.materials[id] and baseline.materials[id].count) or 0
                local delta = mat.count - prevCount
                if delta > 0 then
                    table.insert(rewards, {
                        category = "material",
                        name = mat.name,
                        amount = delta,
                        rarity = mat.rarity,
                        icon = mat.icon and ("http://localhost:18888/api/icon/" .. mat.icon) or "🎒"
                    })
                end
            end

            for id, acc in pairs(nowState.accessories) do
                local prevCount = (baseline.accessories[id] and baseline.accessories[id].count) or 0
                local delta = acc.count - prevCount
                if delta > 0 then
                    table.insert(rewards, {
                        category = "accessory",
                        name = acc.name,
                        amount = delta,
                        icon = acc.icon and ("http://localhost:18888/api/icon/" .. acc.icon) or "👑"
                    })
                end
            end

            -- Match finish trigger:
            -- 1. Official game matchHistory updated (isNewMatch)
            -- 2. OR Drops received after battle (#rewards > 0 with 35s debounce)
            local matchFinished = isNewMatch or (#rewards > 0 and (os.time() - lastLoggedMatchTime >= 35))

            if matchFinished then
                lastLoggedMatchTime = os.time()
                if isNewMatch and currentLatest and currentLatest.time then
                    lastMatchTime = currentLatest.time
                end

                -- Brief wait to let rewards fully settle into account
                task.wait(0.5)
                local settled = getSnapshot()
                if settled then
                    nowState = settled
                    rewards = {}
                    for _, item in ipairs(cKeys) do
                        local curVal = tonumber(nowState.currencies[item.key]) or 0
                        local prevVal = tonumber(baseline.currencies[item.key]) or 0
                        local delta = curVal - prevVal
                        if delta > 0 then
                            table.insert(rewards, {
                                category = "currency",
                                name = item.name,
                                amount = delta,
                                icon = item.icon
                            })
                        end
                    end
                    for id, mat in pairs(nowState.materials) do
                        local prevCount = (baseline.materials[id] and baseline.materials[id].count) or 0
                        local delta = mat.count - prevCount
                        if delta > 0 then
                            table.insert(rewards, {
                                category = "material",
                                name = mat.name,
                                amount = delta,
                                rarity = mat.rarity,
                                icon = mat.icon and ("http://localhost:18888/api/icon/" .. mat.icon) or "🎒"
                            })
                        end
                    end
                    for id, acc in pairs(nowState.accessories) do
                        local prevCount = (baseline.accessories[id] and baseline.accessories[id].count) or 0
                        local delta = acc.count - prevCount
                        if delta > 0 then
                            table.insert(rewards, {
                                category = "accessory",
                                name = acc.name,
                                amount = delta,
                                icon = acc.icon and ("http://localhost:18888/api/icon/" .. acc.icon) or "👑"
                            })
                        end
                    end
                end

                local duration = math.max(1, os.time() - matchStartTime)
                matchStartTime = os.time()

                local matchData = {
                    map = (currentLatest and currentLatest.map) or "Hxh",
                    mode = (currentLatest and currentLatest.mode) or "Story",
                    difficulty = (currentLatest and currentLatest.difficulty) or "Nightmare",
                    won = (currentLatest and currentLatest.won ~= nil) and currentLatest.won or true,
                    wave = (currentLatest and currentLatest.wave) or 11,
                    kills = (currentLatest and currentLatest.kills) or 0,
                    character = (currentLatest and currentLatest.character) or (nowState.characters[1] and nowState.characters[1].id) or "rin",
                    time = os.time(),
                    duration = duration
                }

                print("[AnimeZero Tracker] Match finished! Duration: " .. duration .. "s, Drops: " .. #rewards)

                sendHttp({
                    type = "match_finish",
                    player = nowState.player,
                    playerProg = nowState.playerProg,
                    characters = nowState.characters,
                    match = matchData,
                    rewards = rewards,
                    currencies = nowState.currencies,
                    materials = nowState.materials,
                    accessories = nowState.accessories
                })

                baseline = nowState
                safeWriteBaseline(nowState)
            elseif #rewards > 0 then
                -- Intermediate drop within debounce
                print("[AnimeZero Tracker] Passive drops detected: " .. #rewards)
                sendHttp({
                    type = "reward_update",
                    player = nowState.player,
                    playerProg = nowState.playerProg,
                    characters = nowState.characters,
                    rewards = rewards,
                    currencies = nowState.currencies,
                    materials = nowState.materials,
                    accessories = nowState.accessories
                })
                baseline = nowState
                safeWriteBaseline(nowState)
            end

            -- Live HUD & Real-time Heartbeat
            local pgui = player:FindFirstChild("PlayerGui")
            local roundHud = pgui and pgui:FindFirstChild("RoundHUD")
            local liveData = nil
            if roundHud and roundHud.Enabled then
                local titleLabel = roundHud:FindFirstChild("Title", true)
                local timerLabel = roundHud:FindFirstChild("Timer", true)
                local enemyLabel = roundHud:FindFirstChild("EnemyCount", true)
                liveData = {
                    inMatch = true,
                    wave = titleLabel and titleLabel.Text or "In Match",
                    timer = timerLabel and timerLabel.Text or "",
                    info = enemyLabel and enemyLabel.Text or ""
                }
            end

            heartbeatTick = (heartbeatTick or 0) + 1
            if heartbeatTick >= 2 then
                heartbeatTick = 0
                -- Real-time 3-second live sync for XP bar, wave, and currency ticks
                sendHttp({
                    type = "heartbeat",
                    player = nowState.player,
                    playerProg = nowState.playerProg,
                    currencies = nowState.currencies,
                    live = liveData
                })
            end

            baseline.currencies = nowState.currencies
            baseline.materials = nowState.materials
            baseline.accessories = nowState.accessories
            baseline.player = nowState.player
            baseline.playerProg = nowState.playerProg
            baseline.characters = nowState.characters
            safeWriteBaseline(baseline)
        end
    end
end)
