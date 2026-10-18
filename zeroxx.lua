-- ========================================================
-- Anime Zero Match Drops & Inventory Web Tracker
-- Sends real-time drops and inventory updates to http://localhost:18888/
-- ========================================================

local Rep = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local accStore = require(Rep.global.stores.accountNamespace)
local matConfig = require(Rep.assets.config.materialConfig)
local accConfig = require(Rep.assets.config.accessoryConfig)
local levelProg = require(Rep.global.utils.levelProgression)

local LOCAL_SERVER_URL = "http://localhost:18888/api/report"
local CLOUD_SERVER_URL = "https://anime-zero-tracker.onrender.com/api/report"

local function requestHttp(payload)
    local fn = request or http_request or (syn and syn.request)
    if not fn then return end

    local cfg = getgenv().DuckyConfig or getgenv().TrackerConfig or {}
    if cfg["discord_id"] then
        payload.discord_id = tostring(cfg["discord_id"])
    end
    if cfg["PC_NAME"] then
        payload.pc_name = tostring(cfg["PC_NAME"])
    end

    local body = HttpService:JSONEncode(payload)
    pcall(function()
        fn({
            Url = LOCAL_SERVER_URL,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = body
        })
    end)
    pcall(function()
        fn({
            Url = CLOUD_SERVER_URL,
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

local function getSnapshot()
    local acc = accStore.getLocalPlayerAccount()
    if not acc or not acc.state then return nil end

    -- Currencies
    local currencies = {}
    if acc.state.currencies then
        for k, v in pairs(acc.state.currencies) do
            if type(v) == "table" and v.current ~= nil then
                currencies[k] = tonumber(v.current) or v.current
            end
        end
    end

    local KNOWN_MAT_RARITIES = {
        [101] = "Common", [102] = "Common", [117] = "Common", [121] = "Common",
        [103] = "Epic", [106] = "Epic", [107] = "Epic", [115] = "Epic", [118] = "Epic", [122] = "Epic",
        [104] = "Legendary", [105] = "Legendary", [108] = "Legendary", [112] = "Legendary", [116] = "Legendary", [119] = "Legendary", [123] = "Legendary",
        [109] = "Mythic", [110] = "Mythic", [111] = "Mythic", [113] = "Mythic", [114] = "Mythic", [120] = "Mythic", [124] = "Mythic"
    }

    local KNOWN_ACC_RARITIES = {
        [101] = "Common", [102] = "Common", [103] = "Common", [104] = "Common", [124] = "Common",
        [105] = "Rare",
        [106] = "Epic", [107] = "Epic", [108] = "Epic", [118] = "Epic", [120] = "Epic", [125] = "Epic", [126] = "Epic",
        [109] = "Legendary", [110] = "Legendary", [111] = "Legendary", [112] = "Legendary",
        [121] = "Legendary", [122] = "Legendary", [123] = "Legendary", [127] = "Legendary", [128] = "Legendary",
        [113] = "Mythic", [114] = "Mythic", [115] = "Mythic", [116] = "Mythic", [117] = "Mythic", [119] = "Mythic"
    }

    local function resolveMatRarity(id, name, info)
        local numId = tonumber(id)
        if numId and KNOWN_MAT_RARITIES[numId] then return KNOWN_MAT_RARITIES[numId] end
        if info and (info.Tier or info.tier) then
            local t = tonumber(info.Tier or info.tier)
            if t == 4 then return "Mythic"
            elseif t == 3 then return "Legendary"
            elseif t == 2 then return "Epic"
            elseif t == 1 then return "Common" end
        end
        if info and info.Rarity and type(info.Rarity) == "string" and info.Rarity ~= "" then return info.Rarity end
        return "Common"
    end

    local function resolveAccRarity(id, name, info)
        local numId = tonumber(id)
        if numId and KNOWN_ACC_RARITIES[numId] then return KNOWN_ACC_RARITIES[numId] end
        if info and (info.Tier or info.tier) then
            local t = tonumber(info.Tier or info.tier)
            if t == 4 then return "Mythic"
            elseif t == 3 then return "Legendary"
            elseif t == 2 then return "Epic"
            elseif t == 1 then return "Common" end
        end
        if info and info.Rarity and type(info.Rarity) == "string" and info.Rarity ~= "" then return info.Rarity end
        return "Common"
    end

    -- Materials
    local materials = {}
    if acc.state.material and acc.state.material.entries then
        for id, v in pairs(acc.state.material.entries) do
            local count = tonumber(getVal(v)) or 0
            if count > 0 then
                local info = matConfig[tonumber(id)] or matConfig[tostring(id)] or {}
                local mName = info.Name or info.name or ("Material " .. id)
                materials[tostring(id)] = {
                    id = tostring(id),
                    name = mName,
                    count = count,
                    rarity = resolveMatRarity(id, mName, info)
                }
            end
        end
    end

    -- Accessories
    local accessories = {}
    if acc.state.accessory and acc.state.accessory.entries then
        for id, v in pairs(acc.state.accessory.entries) do
            local count = tonumber(getVal(v)) or 0
            if count > 0 then
                local info = accConfig[tonumber(id)] or accConfig[tostring(id)] or {}
                local aName = info.Name or info.name or ("Accessory " .. id)
                accessories[tostring(id)] = {
                    id = tostring(id),
                    name = aName,
                    count = count,
                    rarity = resolveAccRarity(id, aName, info)
                }
            end
        end
    end

    -- Matches
    local matches = {}
    if acc.state.matchHistory and acc.state.matchHistory.current then
        pcall(function()
            matches = HttpService:JSONDecode(acc.state.matchHistory.current)
        end)
    end

    -- Player Progression
    local playerXp = currencies.xp or 0
    local playerProg = levelProg and levelProg.getProgress(tostring(playerXp))

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

    -- Scan all players in server for real-time Server Leaderboard
    local serverPlayers = {}
    for _, p in ipairs(Players:GetPlayers()) do
        local pLvl = 0
        local pCurXp = 0
        local pReqXp = 0
        local pTotXp = 0
        local pRatio = 0

        local pAcc = nil
        pcall(function()
            if accStore.getPlayerAccount then
                pAcc = accStore.getPlayerAccount(p)
            end
            if not pAcc and accStore.namespace and accStore.namespace._stores then
                pAcc = accStore.namespace._stores[tostring(p.UserId)]
            end
        end)

        if pAcc and pAcc.state and pAcc.state.currencies and pAcc.state.currencies.xp then
            local xpVal = pAcc.state.currencies.xp
            if type(xpVal) == "table" and xpVal.current ~= nil then xpVal = xpVal.current end
            pTotXp = tonumber(xpVal) or 0
            local prog = levelProg and levelProg.getProgress(tostring(xpVal))
            if prog then
                pLvl = tonumber(prog.level) or 0
                pCurXp = tonumber(prog.currentXp) or 0
                pReqXp = tonumber(prog.requiredXp) or 0
                pRatio = prog.ratio or 0
            end
        end

        if pLvl == 0 and p.Character then
            local oh = p.Character:FindFirstChild("OverHead")
            if oh and oh:FindFirstChild("Main") and oh.Main:FindFirstChild("Level") then
                local txt = oh.Main.Level.TxtShadow and oh.Main.Level.TxtShadow.Text
                if txt then
                    local num = txt:match("%d+")
                    if num then pLvl = tonumber(num) or 0 end
                end
            end
        end

        if pLvl == 0 then
            local ls = p:FindFirstChild("leaderstats")
            if ls and ls:FindFirstChild("Level") and ls.Level.Value > 0 then
                pLvl = ls.Level.Value
            elseif p:GetAttribute("Level") and tonumber(p:GetAttribute("Level")) > 0 then
                pLvl = tonumber(p:GetAttribute("Level"))
            end
        end

        local gName = p:GetAttribute("GuildName") or "None"
        local gTag = p:GetAttribute("GuildTag") or ""

        table.insert(serverPlayers, {
            name = p.Name,
            displayName = p.DisplayName,
            userId = p.UserId,
            level = pLvl,
            currentXp = pCurXp,
            requiredXp = pReqXp,
            totalXp = pTotXp,
            ratio = pRatio,
            guild = gName,
            guildTag = gTag,
            isLocal = (p == player)
        })
    end

    table.sort(serverPlayers, function(a, b)
        if a.level == b.level then
            return (a.totalXp or 0) > (b.totalXp or 0)
        end
        return (a.level or 0) > (b.level or 0)
    end)

    for i, sp in ipairs(serverPlayers) do
        sp.rank = i
    end

    return {
        player = {
            name = player.Name,
            displayName = player.DisplayName,
            userId = player.UserId,
            level = level,
            guild = player:GetAttribute("GuildName") or "",
            avatarUrl = "/api/avatar?userId=" .. tostring(player.UserId)
        },
        playerProg = playerProg,
        serverLeaderboard = serverPlayers,
        currencies = currencies,
        materials = materials,
        accessories = accessories,
        matches = matches,
        latestMatch = matches[1],
        timestamp = os.time()
    }
end

-- Initialize Tracker
task.spawn(function()
    print("[Tracker] Starting Anime Zero Drop Tracker...")
    local baseline = nil

    -- Wait until account is loaded
    while not baseline do
        baseline = getSnapshot()
        task.wait(1)
    end

    local lastMatchTime = baseline.latestMatch and baseline.latestMatch.time or 0
    local lastHeartbeat = tick()

    -- Send initial state to dashboard
    requestHttp({
        type = "init",
        player = baseline.player,
        playerProg = baseline.playerProg,
        serverLeaderboard = baseline.serverLeaderboard,
        currencies = baseline.currencies,
        materials = baseline.materials,
        accessories = baseline.accessories,
        latestMatch = baseline.latestMatch
    })

    print("[Tracker] Baseline recorded. Monitoring for match completions...")

    -- Monitoring Loop
    while task.wait(1.5) do
        local current = getSnapshot()
        if current then
            local currentLatest = current.latestMatch
            local isNewMatch = currentLatest and currentLatest.time and (currentLatest.time > lastMatchTime)

            if isNewMatch then
                lastMatchTime = currentLatest.time
                local rewards = {}

                -- Check Currency differences
                local cDiff = {
                    { key = "gems", name = "Gems", icon = "💎", cat = "currency" },
                    { key = "money", name = "Gold / Money", icon = "🪙", cat = "currency" },
                    { key = "luckySpins", name = "Lucky Spins", icon = "🎲", cat = "currency" },
                    { key = "traitRerolls", name = "Trait Rerolls", icon = "🔄", cat = "currency" },
                    { key = "rolls", name = "Rolls", icon = "📜", cat = "currency" },
                    { key = "xp", name = "XP", icon = "⚡", cat = "currency" }
                }

                for _, item in ipairs(cDiff) do
                    local curVal = tonumber(current.currencies[item.key]) or 0
                    local prevVal = tonumber(baseline.currencies[item.key]) or 0
                    local delta = curVal - prevVal
                    if delta > 0 then
                        table.insert(rewards, {
                            category = item.cat,
                            name = item.name,
                            amount = delta,
                            icon = item.icon
                        })
                    end
                end

                -- Check Materials differences
                for id, curMat in pairs(current.materials) do
                    local prevCount = (baseline.materials[id] and baseline.materials[id].count) or 0
                    local delta = curMat.count - prevCount
                    if delta > 0 then
                        table.insert(rewards, {
                            category = "material",
                            name = curMat.name,
                            amount = delta,
                            rarity = curMat.rarity,
                            icon = "🎒"
                        })
                    end
                end

                -- Check Accessories differences
                for id, curAcc in pairs(current.accessories) do
                    local prevCount = (baseline.accessories[id] and baseline.accessories[id].count) or 0
                    local delta = curAcc.count - prevCount
                    if delta > 0 then
                        table.insert(rewards, {
                            category = "accessory",
                            name = curAcc.name,
                            amount = delta,
                            rarity = curAcc.rarity,
                            icon = "👑"
                        })
                    end
                end

                print(string.format("[Tracker] Match Completed! Map: %s, Won: %s, Rewards Count: %d",
                    tostring(currentLatest.map),
                    tostring(currentLatest.won),
                    #rewards
                ))

                -- Send report to web dashboard
                requestHttp({
                    type = "match_finish",
                    player = current.player,
                    playerProg = current.playerProg,
                    serverLeaderboard = current.serverLeaderboard,
                    match = currentLatest,
                    rewards = rewards,
                    currencies = current.currencies,
                    materials = current.materials,
                    accessories = current.accessories
                })

                -- Update baseline to current after match
                baseline = current
            else
                -- Keep baseline currencies/materials in sync if items were spent in lobby (e.g. rolls/crafts)
                baseline.currencies = current.currencies
                baseline.materials = current.materials
                baseline.accessories = current.accessories
                baseline.player = current.player
                baseline.playerProg = current.playerProg
                baseline.serverLeaderboard = current.serverLeaderboard

                -- Periodic heartbeat for 100% real-time leaderboard sync
                if tick() - lastHeartbeat >= 8 then
                    lastHeartbeat = tick()
                    requestHttp({
                        type = "heartbeat",
                        player = current.player,
                        playerProg = current.playerProg,
                        serverLeaderboard = current.serverLeaderboard,
                        currencies = current.currencies,
                        materials = current.materials,
                        accessories = current.accessories
                    })
                end
            end
        end
    end
end)
