-- ============================================================
-- ANIME ZERO TRACKER // IN-GAME CLIENT SYNC SCRIPT (V2 - WITH AUTO MATCH FINISH)
-- Execute in your Roblox Executor (or place in your executor's autoexec folder)
-- ============================================================

local SERVER_URL = "https://anime-zero-tracker.onrender.com" -- หรือ "http://localhost:18888" ถ้าเปิดในเครื่อง
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

local matchStartTime = os.time()
local matchReported = false

local function getVal(v)
    if type(v) == "table" and v.current ~= nil then return v.current end
    return v
end

local function parseNumber(val)
    if not val then return 0 end
    local s = tostring(val):gsub(",", ""):gsub("%+", ""):gsub("x", ""):match("%d+")
    return tonumber(s) or 0
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
        return true
    else
        warn("[Tracker] Sync failed: " .. tostring(response and response.Body or "Network Error"))
        return false
    end
end

-- ============================================================
-- MATCH FINISH SCRAPER & EXTRACTOR
-- ============================================================
local function extractAndSendMatch(endScreen)
    task.wait(1.2) -- รอให้เอฟเฟกต์การ์ดรางวัลในเกมโหลดแสดงผลครบ

    local rewards = {}
    local seenRewards = {}
    local matchWon = true
    local mapName = "Hxh"
    local difficulty = "Nightmare"
    local modeName = "Story"
    local charName = "rin"
    local waveNum = 11
    local killsNum = 0

    -- 1. ตรวจหาตัวละครหลักที่ใช้งาน
    local acc = accStore.getLocalPlayerAccount()
    if acc and acc.state and acc.state.characters then
        local topLvl = -1
        for cid, cdata in pairs(acc.state.characters) do
            local prog = cdata.Progression and cdata.Progression.Xp and cdata.Progression.Xp.current
            local lvl = tonumber(prog) or 0
            if lvl > topLvl then
                topLvl = lvl
                charName = tostring(cid):gsub("_", " "):gsub("^%l", string.upper)
            end
        end
    end

    -- 2. ดึงข้อความจาก TextLabel ใน EndScreen
    for _, desc in ipairs(endScreen:GetDescendants()) do
        if desc:IsA("TextLabel") and desc.Visible then
            local txt = desc.Text
            local lower = txt:lower()

            -- ผลแพ้ชนะ
            if lower:find("defeat") or lower:find("lost") or lower:find("game over") or lower:find("failed") then
                matchWon = false
            elseif lower:find("victory") or lower:find("cleared") or lower:find("success") or lower:find("win") then
                matchWon = true
            end

            -- ตรวจ Wave เช่น "Wave 11"
            local w = txt:match("[Ww]ave%s*[:#]?%s*(%d+)")
            if w then waveNum = tonumber(w) end

            -- ตรวจ Kills เช่น "106 Kills"
            local k = txt:match("(%d+)%s*[Kk]ills?") or txt:match("[Kk]ills?%s*[:#]?%s*(%d+)")
            if k then killsNum = tonumber(k) end

            -- ตรวจชื่อด่านและความยาก
            for _, m in ipairs({"Hxh", "Solo", "Namek", "Shibuya", "Wano", "Bleach", "Demon", "Jujutsu"}) do
                if lower:find(m:lower()) then mapName = m end
            end
            for _, d in ipairs({"Nightmare", "Hard", "Normal", "Easy", "Infinite", "Raid", "Abyss"}) do
                if lower:find(d:lower()) then difficulty = d end
            end
            if lower:find("infinite") then modeName = "Infinite" end
            if lower:find("raid") then modeName = "Raid" end
        end
    end

    -- ตรวจสอบค่าจาก leaderstats เพิ่มเติม
    local lstats = player:FindFirstChild("leaderstats")
    if lstats then
        if killsNum == 0 then
            local kStat = lstats:FindFirstChild("Kills") or lstats:FindFirstChild("Kill")
            if kStat and tonumber(kStat.Value) then killsNum = tonumber(kStat.Value) end
        end
        local wStat = lstats:FindFirstChild("Wave")
        if wStat and tonumber(wStat.Value) and tonumber(wStat.Value) > 0 then
            waveNum = tonumber(wStat.Value)
        end
    end

    -- 3. ดึงของรางวัลจาก RewardsFrame
    local rewardsHolder = endScreen:FindFirstChild("RewardsFrame", true)
    if rewardsHolder then
        local cutFrame = rewardsHolder:FindFirstChild("CutFrame") or rewardsHolder
        local itemsHolder = cutFrame:FindFirstChild("Holder") or cutFrame

        for _, itemFrame in ipairs(itemsHolder:GetChildren()) do
            if itemFrame:IsA("GuiObject") and not itemFrame:IsA("UIComponent") and not itemFrame.Name:find("Layout") then
                local itemName = itemFrame.Name:lower()
                local amount = 0

                for _, lbl in ipairs(itemFrame:GetDescendants()) do
                    if lbl:IsA("TextLabel") and lbl.Visible and lbl.Text ~= "" and not lbl.Name:lower():find("rarity") then
                        local amt = parseNumber(lbl.Text)
                        if amt > 0 then
                            amount = amt
                            break
                        end
                    end
                end
                if amount == 0 then amount = 1 end

                -- ตรวจจับหมวดเงิน
                if itemName == "gems" or itemName:find("gem") then
                    if not seenRewards["gems"] then
                        table.insert(rewards, { name = "Gems", amount = amount, category = "currency", icon = "💎" })
                        seenRewards["gems"] = true
                    end
                elseif itemName == "money" or itemName == "gold" or itemName:find("coin") then
                    if not seenRewards["money"] then
                        table.insert(rewards, { name = "Gold", amount = amount, category = "currency", icon = "🪙" })
                        seenRewards["money"] = true
                    end
                elseif itemName:find("reroll") or itemName:find("trait") then
                    if not seenRewards["reroll"] then
                        table.insert(rewards, { name = "Trait Rerolls", amount = amount, category = "currency", icon = "🎲" })
                        seenRewards["reroll"] = true
                    end
                elseif itemName:find("spin") then
                    if not seenRewards["spin"] then
                        table.insert(rewards, { name = "Lucky Spins", amount = amount, category = "currency", icon = "🎰" })
                        seenRewards["spin"] = true
                    end
                elseif itemName:find("material") then
                    local matId = itemName:match("material(%d+)") or itemName:match("(%d+)")
                    if matId then
                        local info = matConfig[tonumber(matId)] or matConfig[tostring(matId)] or {}
                        local realName = info.Name or info.name or ("Material " .. matId)
                        if not seenRewards["mat_" .. matId] then
                            table.insert(rewards, {
                                name = realName,
                                amount = amount,
                                category = "material",
                                id = tostring(matId),
                                tier = tostring(info.Tier or "1")
                            })
                            seenRewards["mat_" .. matId] = true
                        end
                    end
                elseif itemName:find("accessory") then
                    local accId = itemName:match("accessory(%d+)") or itemName:match("(%d+)")
                    if accId then
                        local info = accConfig[tonumber(accId)] or accConfig[tostring(accId)] or {}
                        local realName = info.Name or info.name or ("Accessory " .. accId)
                        if not seenRewards["acc_" .. accId] then
                            table.insert(rewards, {
                                name = realName,
                                amount = amount,
                                category = "accessory",
                                id = tostring(accId),
                                tier = tostring(info.Tier or "1")
                            })
                            seenRewards["acc_" .. accId] = true
                        end
                    end
                end
            end
        end
    end

    -- คำนวณเวลาที่ใช้ลงดันเจี้ยน
    local now = os.time()
    local duration = math.max(15, now - matchStartTime)

    local matchRecord = {
        map = mapName,
        difficulty = difficulty,
        mode = modeName,
        character = charName,
        won = matchWon,
        wave = waveNum,
        kills = killsNum > 0 and killsNum or 100,
        duration = duration,
        time = now
    }

    local matchPayload = {
        type = "match_finish",
        match = matchRecord,
        rewards = rewards
    }

    print(string.format("[Tracker] Sending match finish: %s (%s) - %s (Rewards: %d, Dur: %ds)", 
        mapName, difficulty, matchWon and "VICTORY" or "DEFEAT", #rewards, duration))

    sendReport(matchPayload)

    -- ส่งอัปเดตกระเป๋าตามหลังเพื่อรีเฟรชยอดไอเทม
    task.wait(1.5)
    local snap = buildSnapshot()
    if snap then sendReport(snap) end
end

-- ============================================================
-- HOOKS & TIMERS
-- ============================================================

-- 1. ซิงก์ข้อมูลเริ่มต้น
task.spawn(function()
    task.wait(2)
    local snap = buildSnapshot()
    if snap then sendReport(snap) end
end)

-- 2. ซิงก์ต่อเนื่องทุก 8 วินาที (เงิน / EXP / เลเวล)
task.spawn(function()
    while task.wait(8) do
        pcall(function()
            local snap = buildSnapshot()
            if snap then sendReport(snap) end
        end)
    end
end)

-- 3. ตรวจสอบหน้าจอจบแมตช์ (Watchdog Listener)
local function checkEndScreen()
    local pGui = player:FindFirstChild("PlayerGui")
    if not pGui then return end

    local endScreen = pGui:FindFirstChild("EndScreen")
    if endScreen and endScreen:IsA("ScreenGui") then
        local holder = endScreen:FindFirstChild("Holder")
        local isVisible = endScreen.Enabled and (not holder or holder.Visible)

        if isVisible and not matchReported then
            matchReported = true
            task.spawn(function()
                pcall(extractAndSendMatch, endScreen)
            end)
        elseif not isVisible and matchReported then
            -- ปิดหน้าจอจบเกม หรือเข้าดันเจี้ยนรอบใหม่
            matchReported = false
            matchStartTime = os.time()
        end
    end
end

task.spawn(function()
    local pGui = player:WaitForChild("PlayerGui", 15)
    if not pGui then return end

    local function hookEndScreen(endScreen)
        if not endScreen or not endScreen:IsA("ScreenGui") then return end
        
        endScreen:GetPropertyChangedSignal("Enabled"):Connect(checkEndScreen)
        local holder = endScreen:FindFirstChild("Holder")
        if holder then
            holder:GetPropertyChangedSignal("Visible"):Connect(checkEndScreen)
        end
    end

    local es = pGui:FindFirstChild("EndScreen")
    if es then hookEndScreen(es) end

    pGui.ChildAdded:Connect(function(child)
        if child.Name == "EndScreen" then
            hookEndScreen(child)
        end
    end)

    -- วนเช็กสถานะทุก 1 วินาทีแบบ Realtime
    while task.wait(1) do
        pcall(checkEndScreen)
    end
end)

print("[Anime Zero Tracker] V2 Sync & Auto Match-Finish Activated -> " .. SERVER_URL)
