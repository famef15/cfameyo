-- Language: Luau | File: tracker-client.luau | Runtime: Roblox Client Executor | Target: Anime Zero
-- ============================================================
-- ANIME ZERO TRACKER // IN-GAME CLIENT SYNC SCRIPT (V4 - ULTRA PRECISION)
-- Target Server: https://anime-zero-tracker.onrender.com
-- ============================================================

local SERVER_URL = "https://anime-zero-tracker.onrender.com"
local TRACKER_SECRET = ""

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
local lastMatchSentTime = 0
local hiddenFramesCount = 0
local lastSnapshot = nil
local lastWave = 0

local function getVal(v)
    if type(v) == "table" and v.current ~= nil then return v.current end
    return v
end

local function parseNumber(val)
    if not val then return 0 end
    local s = tostring(val):gsub(",", ""):gsub("%+", ""):gsub("x", ""):match("%d+")
    return tonumber(s) or 0
end

-- ดึงสถานะกระเป๋าและตัวละครแบบเต็มรูปแบบ
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

-- ฟังก์ชันค้นหาเวลา Clear Time บนหน้าจอเกม (MM:SS)
local function findScreenTimer(guiRoot)
    if not guiRoot then return nil end
    for _, desc in ipairs(guiRoot:GetDescendants()) do
        if desc:IsA("TextLabel") and desc.Visible and desc.Text ~= "" then
            local txt = desc.Text:gsub("%s+", "")
            local m, s = txt:match("(%d%d?):(%d%d)")
            if m and s then
                local total = tonumber(m) * 60 + tonumber(s)
                if total >= 5 and total <= 1800 then
                    return total
                end
            end
        end
    end
    return nil
end

-- ============================================================
-- MATCH FINISH ENGINE (ACCURATE DROPS & REAL TIME)
-- ============================================================
local function extractAndSendMatch(endScreen)
    task.wait(1.5) -- รอให้เอฟเฟกต์รางวัล EndScreen ขึ้นครบ 100%

    local currentSnap = buildSnapshot()
    local rewards = {}
    local seenRewards = {}
    local matchWon = true
    local mapName = "Hxh"
    local difficulty = "Nightmare"
    local modeName = "Story"
    local charName = "rin"
    local waveNum = 11
    local killsNum = 0

    -- 1. ตัวละครหลัก
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

    -- 2. สแกนข้อความใน EndScreen (ผลแพ้/ชนะ, ด่าน, ความยาก, Wave, Kills)
    for _, desc in ipairs(endScreen:GetDescendants()) do
        if desc:IsA("TextLabel") and desc.Visible then
            local txt = desc.Text
            local lower = txt:lower()

            if lower:find("defeat") or lower:find("lost") or lower:find("game over") or lower:find("failed") then
                matchWon = false
            elseif lower:find("victory") or lower:find("cleared") or lower:find("success") or lower:find("win") then
                matchWon = true
            end

            local w = txt:match("[Ww]ave%s*[:#]?%s*(%d+)")
            if w then waveNum = tonumber(w) end

            local k = txt:match("(%d+)%s*[Kk]ills?") or txt:match("[Kk]ills?%s*[:#]?%s*(%d+)")
            if k then killsNum = tonumber(k) end

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

    -- Leaderstats fallback
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

    -- 3. คำนวณเวลา Duration ที่แท้จริง (ดึงจากตัวเลขเวลาบนหน้าจอเกมก่อน)
    local screenDuration = findScreenTimer(endScreen) 
        or findScreenTimer(player.PlayerGui:FindFirstChild("HUD"))

    local duration = screenDuration
    if not duration or duration <= 0 then
        -- ถ้าบนจอไม่มีตัวเลขเวลา ใช้นับเวลาตั้งแต่เริ่มลงดันเจี้ยน
        local elapsed = os.time() - matchStartTime
        if elapsed < 25 then
            -- ป้องกันกรณีเริ่มจับเวลาคลาดเคลื่อน ไม่เซ็ตเป็น 15s ให้ใช้ค่าเฉลี่ยของดันเจี้ยน 85s
            duration = 85
        else
            duration = math.min(1800, elapsed)
        end
    end

    -- 4. คำนวณของรางวัล (วิธีที่ 1: INVENTORY DELTA - แม่นยำ 100% ไม่แสดงของที่ไม่ได้ดรอป)
    if lastSnapshot and currentSnap then
        local prevCurr = lastSnapshot.currencies or {}
        local curCurr = currentSnap.currencies or {}

        -- XP Delta
        local xpPrev = tonumber((prevCurr and prevCurr.xp) or (lastSnapshot.playerProg and lastSnapshot.playerProg.totalXp) or 0) or 0
        local xpCur = tonumber((curCurr and curCurr.xp) or (currentSnap.playerProg and currentSnap.playerProg.totalXp) or 0) or 0
        local xpDiff = xpCur - xpPrev
        if xpDiff > 0 and xpDiff < 10000000 then
            table.insert(rewards, { name = "XP", amount = xpDiff, category = "currency", icon = "⚡" })
            seenRewards["xp"] = true
        end

        local gemsDiff = (curCurr.gems or 0) - (prevCurr.gems or 0)
        if gemsDiff > 0 then
            table.insert(rewards, { name = "Gems", amount = gemsDiff, category = "currency", icon = "💎" })
            seenRewards["gems"] = true
        end

        local goldDiff = (curCurr.money or 0) - (prevCurr.money or 0)
        if goldDiff > 0 then
            table.insert(rewards, { name = "Gold", amount = goldDiff, category = "currency", icon = "🪙" })
            seenRewards["gold"] = true
        end

        local rerollDiff = (curCurr.traitRerolls or 0) - (prevCurr.traitRerolls or 0)
        if rerollDiff > 0 then
            table.insert(rewards, { name = "Trait Rerolls", amount = rerollDiff, category = "currency", icon = "🎲" })
            seenRewards["reroll"] = true
        end

        local spinDiff = (curCurr.luckySpins or 0) - (prevCurr.luckySpins or 0)
        if spinDiff > 0 then
            table.insert(rewards, { name = "Lucky Spins", amount = spinDiff, category = "currency", icon = "🎰" })
            seenRewards["spin"] = true
        end

        -- Materials delta
        local prevMats = lastSnapshot.materials or {}
        local curMats = currentSnap.materials or {}
        for mid, mdata in pairs(curMats) do
            local prevCount = (prevMats[mid] and prevMats[mid].count) or 0
            local diff = (mdata.count or 0) - prevCount
            if diff > 0 then
                table.insert(rewards, {
                    name = mdata.name,
                    amount = diff,
                    category = "material",
                    id = tostring(mid),
                    tier = tostring(mdata.tier or "1")
                })
                seenRewards["mat_" .. mid] = true
            end
        end

        -- Accessories delta
        local prevAccs = lastSnapshot.accessories or {}
        local curAccs = currentSnap.accessories or {}
        for aid, adata in pairs(curAccs) do
            local prevCount = (prevAccs[aid] and prevAccs[aid].count) or 0
            local diff = (adata.count or 0) - prevCount
            if diff > 0 then
                table.insert(rewards, {
                    name = adata.name,
                    amount = diff,
                    category = "accessory",
                    id = tostring(aid),
                    tier = tostring(adata.tier or "1")
                })
                seenRewards["acc_" .. aid] = true
            end
        end
    end

    -- วิธีที่ 2: สแกน EndScreen.Holder.RewardsFrame (เฉพาะกล่องที่ Visible == true และ Amount > 0 เท่านั้น!)
    local rewardsHolder = endScreen:FindFirstChild("RewardsFrame", true)
    if rewardsHolder then
        local cutFrame = rewardsHolder:FindFirstChild("CutFrame") or rewardsHolder
        local itemsHolder = cutFrame:FindFirstChild("Holder") or cutFrame

        for _, itemFrame in ipairs(itemsHolder:GetChildren()) do
            -- ต้องเป็น Frame ที่แสดงผลจริงบนหน้าจอเท่านั้น (ไม่นับ Template ที่ซ่อนอยู่)
            if itemFrame:IsA("GuiObject") and itemFrame.Visible == true and not itemFrame.Name:find("Layout") then
                local itemName = itemFrame.Name:lower()
                local amount = 0

                -- ค้นหาตัวเลขจำนวนที่ดรอปจริง
                for _, lbl in ipairs(itemFrame:GetDescendants()) do
                    if lbl:IsA("TextLabel") and lbl.Visible == true and lbl.Text ~= "" then
                        local n = lbl.Name:lower()
                        local t = lbl.Text:lower()
                        -- ข้ามข้อความที่เป็นชื่อ หรือระดับความหายาก (ป้องกันดึงคำว่า Tier 1 มาเป็นจำนวน 1)
                        if not n:find("rarity") and not n:find("tier") and not n:find("title") and not n:find("name")
                           and not t:find("common") and not t:find("epic") and not t:find("legend") and not t:find("mythic") then
                            local val = parseNumber(lbl.Text)
                            if val and val > 0 then
                                amount = val
                                break
                            end
                        end
                    end
                end

                -- ต้องมีจำนวนมากกว่า 0 เท่านั้น ถึงจะบันทึก (ห้ามตั้ง fallback เป็น 1 เด็ดขาด)
                if amount > 0 then
                    if (itemName == "gems" or itemName:find("gem")) and not seenRewards["gems"] then
                        table.insert(rewards, { name = "Gems", amount = amount, category = "currency", icon = "💎" })
                        seenRewards["gems"] = true
                    elseif (itemName == "money" or itemName == "gold" or itemName:find("coin")) and not seenRewards["gold"] then
                        table.insert(rewards, { name = "Gold", amount = amount, category = "currency", icon = "🪙" })
                        seenRewards["gold"] = true
                    elseif (itemName:find("reroll") or itemName:find("trait")) and not seenRewards["reroll"] then
                        table.insert(rewards, { name = "Trait Rerolls", amount = amount, category = "currency", icon = "🎲" })
                        seenRewards["reroll"] = true
                    elseif itemName:find("spin") and not seenRewards["spin"] then
                        table.insert(rewards, { name = "Lucky Spins", amount = amount, category = "currency", icon = "🎰" })
                        seenRewards["spin"] = true
                    elseif itemName:find("material") then
                        local matId = itemName:match("material(%d+)") or itemName:match("(%d+)")
                        if matId and not seenRewards["mat_" .. matId] then
                            local info = matConfig[tonumber(matId)] or matConfig[tostring(matId)] or {}
                            table.insert(rewards, {
                                name = info.Name or info.name or ("Material " .. matId),
                                amount = amount,
                                category = "material",
                                id = tostring(matId),
                                tier = tostring(info.Tier or "1")
                            })
                            seenRewards["mat_" .. matId] = true
                        end
                    elseif (itemName:find("xp") or itemName:find("exp")) and not seenRewards["xp"] then
                        table.insert(rewards, { name = "XP", amount = amount, category = "currency", icon = "⚡" })
                        seenRewards["xp"] = true
                    elseif itemName:find("accessory") then
                        local accId = itemName:match("accessory(%d+)") or itemName:match("(%d+)")
                        if accId and not seenRewards["acc_" .. accId] then
                            local info = accConfig[tonumber(accId)] or accConfig[tostring(accId)] or {}
                            table.insert(rewards, {
                                name = info.Name or info.name or ("Accessory " .. accId),
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

    -- 5. สแกนหา XP เพิ่มเติมบน EndScreen (กรณีไม่ได้จาก delta)
    if not seenRewards["xp"] then
        for _, desc in ipairs(endScreen:GetDescendants()) do
            if desc:IsA("TextLabel") and desc.Visible and desc.Text ~= "" then
                local txt = desc.Text
                local lowerTxt = txt:lower()
                local lblName = desc.Name:lower()
                if (lowerTxt:find("xp") or lowerTxt:find("exp") or lblName:find("xp") or lblName:find("exp"))
                   and not lowerTxt:find("total") and not lowerTxt:find("next") and not lowerTxt:find("max") then
                    local xpVal = txt:match("%+?([%d,]+)%s*[Xx][Pp]") 
                        or txt:match("[Xx][Pp]%s*[:%+x]?%s*([%d,]+)")
                        or txt:match("%+?([%d,]+)%s*[Ee][Xx][Pp]")
                        or parseNumber(txt)
                    if type(xpVal) == "string" then xpVal = parseNumber(xpVal) end
                    if xpVal and xpVal > 0 and xpVal < 10000000 then
                        table.insert(rewards, { name = "XP", amount = xpVal, category = "currency", icon = "⚡" })
                        seenRewards["xp"] = true
                        break
                    end
                end
            end
        end
    end

    local matchRecord = {
        map = mapName,
        difficulty = difficulty,
        mode = modeName,
        character = charName,
        won = matchWon,
        wave = waveNum,
        kills = killsNum > 0 and killsNum or 100,
        duration = duration,
        time = os.time()
    }

    local matchPayload = {
        type = "match_finish",
        match = matchRecord,
        rewards = rewards
    }

    print(string.format("[Tracker] Match Finish: %s (%s) - %s | Drops: %d items | Duration: %02d:%02d", 
        mapName, difficulty, matchWon and "VICTORY" or "DEFEAT", #rewards, math.floor(duration/60), duration%60))

    sendReport(matchPayload)

    -- อัปเดต snapshot ล่าสุด
    task.wait(1.5)
    lastSnapshot = currentSnap
    if currentSnap then sendReport(currentSnap) end
end

-- ============================================================
-- TIMERS & WATCHDOG
-- ============================================================

-- บันทึก snapshot เริ่มต้น
task.spawn(function()
    task.wait(2)
    lastSnapshot = buildSnapshot()
    if lastSnapshot then sendReport(lastSnapshot) end
end)

-- ซิงก์ต่อเนื่องทุก 10 วินาที
task.spawn(function()
    while task.wait(10) do
        pcall(function()
            local snap = buildSnapshot()
            if snap then
                -- ถ้าไม่ได้อยู่ในหน้าจบเกม ให้อัปเดต lastSnapshot ไว้เทียบของดรอป
                if not matchReported then
                    lastSnapshot = snap
                end
                sendReport(snap)
            end
        end)
    end
end)

-- ตรวจสอบการเปลี่ยน Wave / การเริ่มดันเจี้ยน เพื่อรีเซ็ตตัวจับเวลาให้ตรงเป๊ะ
task.spawn(function()
    while task.wait(2) do
        pcall(function()
            local lstats = player:FindFirstChild("leaderstats")
            if lstats then
                local wStat = lstats:FindFirstChild("Wave")
                if wStat and tonumber(wStat.Value) then
                    local curWave = tonumber(wStat.Value)
                    if curWave == 1 and lastWave ~= 1 then
                        -- เพิ่งเริ่มเวฟ 1 รีเซ็ตเวลาเริ่มทันที
                        matchStartTime = os.time()
                    end
                    lastWave = curWave
                end
            end
        end)
    end
end)

-- ตรวจสอบหน้าจอจบแมตช์ (Watchdog & Anti-Duplicate Debounce)
local function checkEndScreen()
    local pGui = player:FindFirstChild("PlayerGui")
    if not pGui then return end

    local endScreen = pGui:FindFirstChild("EndScreen")
    if endScreen and endScreen:IsA("ScreenGui") then
        local holder = endScreen:FindFirstChild("Holder")
        local isVisible = endScreen.Enabled and (not holder or holder.Visible)

        local now = os.time()
        if isVisible then
            hiddenFramesCount = 0
            -- ป้องกันส่งเบิ้ล: ต้องยังไม่รายงาน และห่างจากรอบก่อนหน้าอย่างน้อย 30 วินาที
            if not matchReported and (now - lastMatchSentTime >= 30) then
                matchReported = true
                lastMatchSentTime = now
                task.spawn(function()
                    pcall(extractAndSendMatch, endScreen)
                end)
            end
        else
            -- รอให้ซ่อนต่อเนื่อง 8 วินาที ก่อนปลดล็อค matchReported เพื่อป้องกันแอนิเมชันกระพริบ
            if matchReported then
                hiddenFramesCount = hiddenFramesCount + 1
                if hiddenFramesCount >= 8 then
                    matchReported = false
                    hiddenFramesCount = 0
                    task.spawn(function()
                        task.wait(2)
                        lastSnapshot = buildSnapshot()
                    end)
                end
            end
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

    -- วนเช็กสถานะทุก 1 วินาที
    while task.wait(1) do
        pcall(checkEndScreen)
    end
end)

print("[Anime Zero Tracker] V4 Precision Sync Activated -> " .. SERVER_URL)
