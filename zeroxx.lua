-- ============================================================
-- ANIME ZERO TRACKER // IN-GAME CLIENT SYNC SCRIPT
-- Execute in your Roblox Executor (or place in autoexec)
-- ============================================================

local SERVER_URL = "https://anime-zero-tracker.onrender.com/"
local TRACKER_SECRET = "" -- หากตั้ง TRACKER_SECRET ไว้ที่เซิร์ฟเวอร์ ให้ใส่ที่นี่

-- HTTP Request Wrapper
local httpRequest = (syn and syn.request) 
    or (http and http.request) 
    or http_request 
    or (fluxus and fluxus.request) 
    or request

if not httpRequest then
    warn("[Tracker] HTTP Request is not supported by your executor!")
    return
end

local Rep = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local accStore = require(Rep.global.stores.accountNamespace)
local matConfig = require(Rep.assets.config.materialConfig)
local accConfig = require(Rep.assets.config.accessoryConfig)
local levelProg = require(Rep.global.utils.levelProgression)
local charRoll = require(Rep.assets.config.characterRollConfig)

local function getVal(v)
    if type(v) == "table" and v.current ~= nil then return v.current end
    return v
end

local function buildSnapshot()
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

    -- Materials
    local materials = {}
    if acc.state.material and acc.state.material.entries then
        for id, v in pairs(acc.state.material.entries) do
            local count = tonumber(getVal(v)) or 0
            if count > 0 then
                local info = matConfig[tonumber(id)] or matConfig[tostring(id)] or {}
                local tier = tostring(info.Tier or "1")
                materials[tostring(id)] = {
                    id = tostring(id),
                    name = info.Name or info.name or ("Material " .. id),
                    count = count,
                    tier = tier,
                    rarity = (tier == "4" and "Mythic") or (tier == "3" and "Legendary") or (tier == "2" and "Epic") or "Common",
                    icon = info.Icon and tostring(info.Icon) or "",
                    iconUrl = "/icons/material_" .. tostring(id) .. ".png",
                    description = info.Description or ""
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
                local tier = tostring(info.Tier or "1")
                accessories[tostring(id)] = {
                    id = tostring(id),
                    name = info.Name or info.name or ("Accessory " .. id),
                    count = count,
                    tier = tier,
                    rarity = (tier == "4" and "Mythic") or (tier == "3" and "Legendary") or (tier == "2" and "Epic") or "Common",
                    slot = tostring(info.Slot or ""),
                    icon = info.Icon and tostring(info.Icon) or "",
                    iconUrl = "/icons/accessory_" .. tostring(id) .. ".png",
                    description = info.Description or ""
                }
            end
        end
    end

    -- Player Progression
    local playerXp = currencies.xp or 0
    local prog = levelProg.getProgress(tostring(playerXp))
    local level = (prog and tonumber(prog.level) and tonumber(prog.level) > 0 and tonumber(prog.level)) or 0
    if level == 0 then
        local leaderstats = player:FindFirstChild("leaderstats")
        if leaderstats and leaderstats:FindFirstChild("Level") and leaderstats.Level.Value > 0 then
            level = leaderstats.Level.Value
        end
    end

    return {
        player = {
            name = player.Name,
            displayName = player.DisplayName,
            userId = player.UserId,
            level = level,
            guild = player:GetAttribute("GuildName") or "None"
        },
        playerProg = prog,
        currencies = currencies,
        materials = materials,
        accessories = accessories,
        timestamp = os.time()
    }
end

local function sendReport(payload)
    local jsonBody = HttpService:JSONEncode(payload)
    local headers = { ["Content-Type"] = "application/json" }
    if TRACKER_SECRET and TRACKER_SECRET ~= "" then
        headers["x-tracker-secret"] = TRACKER_SECRET
    end

    local success, response = pcall(function()
        return httpRequest({
            Url = SERVER_URL:gsub("/$", "") .. "/api/report",
            Method = "POST",
            Headers = headers,
            Body = jsonBody
        })
    end)

    if success and response and (response.StatusCode == 200 or response.Status == 200) then
        -- Synced successfully
    else
        warn("[Tracker] Sync failed: " .. tostring(response and response.Body or "Network Error"))
    end
end

-- 1. Initial Sync
task.spawn(function()
    task.wait(2)
    local snap = buildSnapshot()
    if snap then sendReport(snap) end
end)

-- 2. Periodic Live Sync (Every 8 seconds)
task.spawn(function()
    while task.wait(8) do
        pcall(function()
            local snap = buildSnapshot()
            if snap then sendReport(snap) end
        end)
    end
end)

-- 3. Match End Detection (EndScreen Listener)
task.spawn(function()
    local pGui = player:WaitForChild("PlayerGui", 10)
    if not pGui then return end

    local endScreen = pGui:WaitForChild("EndScreen", 15)
    if endScreen then
        endScreen:GetPropertyChangedSignal("Enabled"):Connect(function()
            if endScreen.Enabled then
                task.wait(1.5)
                pcall(function()
                    local snap = buildSnapshot()
                    if snap then sendReport(snap) end
                end)
            end
        end)
    end
end)

print("[Anime Zero Tracker] In-Game Client Live Sync Activated -> " .. SERVER_URL)
