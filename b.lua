repeat task.wait() until game:IsLoaded() and game.Players.LocalPlayer

-- ==========================================
-- SERVICES & VARIABLES
-- ==========================================
local Config = getgenv().Config
local FeedConfig = Config["Auto Feed"] or {}
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Http = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local Player = Players.LocalPlayer
local Events = RS:WaitForChild("Events")

local Cache = { data = nil, last = 0 }
local SCRIPT_START_TIME = tick()

local ITEM_KEYS = {
    MoonCharm = "MoonCharm", Pineapple = "Pineapple", Strawberry = "Strawberry",
    Blueberry = "Blueberry", SunflowerSeed = "SunflowerSeed", Bitterberry = "Bitterberry",
    Neonberry = "Neonberry", GingerbreadBear = "GingerbreadBear", Treat = "Treat",
    Silver = "Silver", Ticket = "Ticket", Gold = "Gold", Diamond = "Diamond",
    ["Star Egg"] = "Star", Basic = "Basic"
}

local BOND_ITEMS = {
    { Name = "Neonberry", Value = 500 }, { Name = "MoonCharm", Value = 250 },
    { Name = "GingerbreadBear", Value = 250 }, { Name = "Bitterberry", Value = 100 },
    { Name = "Pineapple", Value = 50 }, { Name = "Strawberry", Value = 50 },
    { Name = "Blueberry", Value = 50 }, { Name = "SunflowerSeed", Value = 50 },
    { Name = "Treat", Value = 10 }
}

local QUEST_ORDER = {
    "Treat Tutorial", "Bonding With Bees", "Search For A Sunflower Seed",
    "The Gist Of Jellies", "Search For Strawberries", "Binging On Blueberries",
    "Royal Jelly Jamboree", "Search For Sunflower Seeds", "Picking Out Pineapples",
    "Seven To Seven"
}

-- Weighted difficulty for progress and ETA calculations
local QUEST_WEIGHTS = {
    ["Treat Tutorial"] = 2, ["Bonding With Bees"] = 5, ["Search For A Sunflower Seed"] = 10,
    ["The Gist Of Jellies"] = 15, ["Search For Strawberries"] = 20, ["Binging On Blueberries"] = 30,
    ["Royal Jelly Jamboree"] = 50, ["Search For Sunflower Seeds"] = 80, ["Picking Out Pineapples"] = 120,
    ["Seven To Seven"] = 200
}

local TOTAL_QUEST_WEIGHT = 0
for _, weight in pairs(QUEST_WEIGHTS) do TOTAL_QUEST_WEIGHT += weight end

local QUEST_TREAT_REQ = {
    ["Treat Tutorial"] = 1, ["Bonding With Bees"] = 5, ["Search For A Sunflower Seed"] = 10,
    ["The Gist Of Jellies"] = 15, ["Search For Strawberries"] = 20, ["Binging On Blueberries"] = 30,
    ["Royal Jelly Jamboree"] = 50, ["Search For Sunflower Seeds"] = 100, ["Picking Out Pineapples"] = 250,
    ["Seven To Seven"] = 500
}

local QUEST_FRUIT_REQ = {
    ["Search For A Sunflower Seed"] = { SunflowerSeed = 1 },
    ["Search For Strawberries"] = { Strawberry = 5 },
    ["Binging On Blueberries"] = { Blueberry = 10 },
    ["Search For Sunflower Seeds"] = { SunflowerSeed = 25 },
    ["Picking Out Pineapples"] = { Pineapple = 25 },
    ["Seven To Seven"] = { Blueberry = 25, Strawberry = 25 }
}

local LAST_STAR = {}
local QUEST_DONE = false
local FEED_DONE = false
local PRINTER_CD = 0
local LAST_EGG_BUY = 0
local REPORTED_QUESTS = {}

local STATE = {
    QUEST_DONE = false,
    WROTE_STATUS = false,
    NO_STAR_TIMER = 0,
    PRINTER_CD = 0,
    LAST_SIGNS = {}
}

-- ==========================================
-- HELPER FUNCTIONS
-- ==========================================
local function getCache()
    if tick() - Cache.last > 1 then
        local ok, res = pcall(function()
            return require(RS.ClientStatCache):Get()
        end)
        if ok then
            Cache.data = res
            Cache.last = tick()
        end
    end
    return Cache.data
end

local function deepFind(tbl, key, seen)
    seen = seen or {}
    if seen[tbl] then return end
    seen[tbl] = true
    for k, v in pairs(tbl) do
        if k == key then return v end
        if type(v) == "table" then
            local f = deepFind(v, key, seen)
            if f then return f end
        end
    end
end

local function isQuestCompleted(list, name)
    for _, q in pairs(list or {}) do
        if tostring(q) == name then return true end
    end
    return false
end

local function formatTime(seconds)
    if seconds == math.huge or seconds <= 0 then return "Calculating..." end
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    return string.format("%02d:%02d:%02d", h, m, s)
end

local function calculateProgressAndETA()
    local cache = getCache()
    if not cache then return "0.0%", "Calculating..." end
    
    local completed = deepFind(cache, "Completed") or {}
    local currentWeight = 0
    
    for _, q in ipairs(QUEST_ORDER) do
        if isQuestCompleted(completed, q) then
            currentWeight += (QUEST_WEIGHTS[q] or 0)
        end
    end
    
    local progress = math.clamp((currentWeight / TOTAL_QUEST_WEIGHT) * 100, 0, 100)
    local elapsedTime = tick() - SCRIPT_START_TIME
    
    local etaString = "Calculating..."
    if currentWeight > 0 and progress < 100 then
        local timePerWeight = elapsedTime / currentWeight
        local remainingWeight = TOTAL_QUEST_WEIGHT - currentWeight
        local remainingSeconds = timePerWeight * remainingWeight
        etaString = formatTime(remainingSeconds)
    elseif progress >= 100 then
        etaString = "Completed!"
    end
    
    return string.format("%.1f%%", progress), etaString
end

local function sendWebhook(title, fields, color)
    local progress, eta = calculateProgressAndETA()
    
    -- Inject universal fields
    table.insert(fields, 1, { name = "Roblox Account", value = Player.Name, inline = true })
    table.insert(fields, { name = "Star Egg Progress", value = progress, inline = true })
    table.insert(fields, { name = "Estimated Time Left", value = eta, inline = true })

    local data = {
        content = "<@" .. tostring(Config["Ping Id"] or "") .. ">",
        embeds = {{
            title = title,
            color = color,
            fields = fields,
            footer = { text = "made by Jung Ganmyeon | Enhanced Script" }
        }}
    }

    pcall(function()
        request({
            Url = Config["Link Wh"],
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = Http:JSONEncode(data)
        })
    end)
end

local function getInventory()
    local cache = getCache()
    if not cache or not cache.Eggs then return {} end
    local inv = {}
    for name, key in pairs(ITEM_KEYS) do
        inv[name] = tonumber(cache.Eggs[key]) or 0
    end
    return inv
end

local function getBees()
    local cache = getCache()
    local bees = {}
    if not cache or not cache.Honeycomb then return bees end

    for cx, col in pairs(cache.Honeycomb) do
        for cy, bee in pairs(col) do
            if bee and bee.Lvl then
                local x = tonumber(tostring(cx):match("%d+"))
                local y = tonumber(tostring(cy):match("%d+"))
                if x and y then
                    table.insert(bees, { col = x, row = y, level = bee.Lvl })
                end
            end
        end
    end
    return bees
end

local function findEmptySlot()
    local hives = Workspace:WaitForChild("Honeycombs")
    for _, hive in ipairs(hives:GetChildren()) do
        local owner = hive:FindFirstChild("Owner")
        local isMine = (owner and owner:IsA("ObjectValue") and owner.Value == Player) or
                       (owner and owner:IsA("StringValue") and owner.Value == Player.Name) or
                       (owner and owner:IsA("IntValue") and owner.Value == Player.UserId)

        if isMine then
            local slots = {}
            for _, cell in ipairs(hive.Cells:GetChildren()) do
                local cellType = cell:FindFirstChild("CellType")
                local x = cell:FindFirstChild("CellX")
                local y = cell:FindFirstChild("CellY")
                local locked = cell:FindFirstChild("CellLocked")

                if cellType and x and y and locked and not locked.Value then
                    table.insert(slots, {
                        x = x.Value, y = y.Value,
                        empty = (cellType.Value == "" or tostring(cellType.Value):lower() == "empty")
                    })
                end
            end

            table.sort(slots, function(a, b)
                if a.x == b.x then return a.y < b.y end
                return a.x < b.x
            end)

            for _, s in ipairs(slots) do
                if s.empty then return s.x, s.y end
            end
        end
    end
end

local function getBondLeft(col, row)
    local result
    pcall(function() result = Events.GetBondToLevel:InvokeServer(col, row) end)
    if type(result) == "number" then return result end
    if type(result) == "table" then
        for _, v in pairs(result) do
            if type(v) == "number" then return v end
        end
    end
end

-- ==========================================
-- CORE LOGIC
-- ==========================================

local function getCurrentQuest(completed)
    for _, q in ipairs(QUEST_ORDER) do
        if not isQuestCompleted(completed, q) then
            return q
        end
    end
end

local function getGlobalReserve(completed)
    local treat = 0
    local fruits = {}
    for _, q in ipairs(QUEST_ORDER) do
        if not isQuestCompleted(completed, q) then
            treat += (QUEST_TREAT_REQ[q] or 0)
            local f = QUEST_FRUIT_REQ[q]
            if f then
                for name, amt in pairs(f) do
                    fruits[name] = (fruits[name] or 0) + amt
                end
            end
        end
    end
    return treat, fruits
end

local function autoFeed()
    if FEED_DONE or not FeedConfig["Enable"] then return end

    local cache = getCache()
    if not cache then return end

    local completed = deepFind(cache, "Completed") or {}
    local currentQuest = getCurrentQuest(completed)

    if not currentQuest then
        FEED_DONE = true
        return
    end

    local isFinalQuest = (currentQuest == "Seven To Seven")
    local reserveTreat, reserveFruits = getGlobalReserve(completed)
    local bees = getBees()
    table.sort(bees, function(a, b) return a.level < b.level end)

    local maxCount = FeedConfig["Bee Amount"] or 7
    local group = {}
    for i = 1, math.min(maxCount, #bees) do group[#group + 1] = bees[i] end

    for _, b in ipairs(group) do
        local bondLeft = getBondLeft(b.col, b.row)
        if bondLeft and bondLeft > 0 then
            local remaining = bondLeft
            local inventory = getInventory()

            for _, item in ipairs(BOND_ITEMS) do
                if remaining <= 0 then break end
                if FeedConfig["Bee Food"] and FeedConfig["Bee Food"][item.Name] then
                    local keep = 0
                    if not isFinalQuest then
                        if item.Name == "Treat" then keep = reserveTreat end
                        if reserveFruits[item.Name] then keep = reserveFruits[item.Name] end
                    end

                    local have = (inventory[item.Name] or 0) - keep
                    if have > 0 then
                        local need = math.ceil(remaining / item.Value)
                        local use = math.min(have, need)

                        if use > 0 then
                            local keyName = ITEM_KEYS[item.Name]
                            local bondGain = use * item.Value

                            Events.ConstructHiveCellFromEgg:InvokeServer(b.col, b.row, keyName, use, false)
                            remaining -= bondGain
                            task.wait(1.5)
                        end
                    end
                end
            end

            if remaining > 0 and FeedConfig["Auto Buy Treat"] then
                local inv = getInventory()
                local haveTreat = inv["Treat"] or 0
                local freeTreat = haveTreat - reserveTreat
                local needTreat = math.max(0, math.ceil(remaining / 10) - freeTreat)

                if needTreat > 0 then
                    local honey = Player.CoreStats.Honey.Value
                    local cost = needTreat * 10000
                    if honey >= cost then
                        Events.ItemPackageEvent:InvokeServer("Purchase", { Type = "Treat", Amount = needTreat, Category = "Eggs" })
                    end
                end
            end
            return
        end
    end
end

local function autoHatch()
    local cfg = Config["Auto Hatch"]
    if not cfg or not cfg["Enable"] then return end

    local col, row = findEmptySlot()
    if not col then return end

    local inv = getInventory()
    for _, egg in ipairs(cfg["Egg Hatch"]) do
        if (inv[egg] or 0) > 0 then
            pcall(function() Events.ConstructHiveCellFromEgg:InvokeServer(col, row, egg, 1, false) end)
            task.wait(3)
            return
        end
    end
end

local function autoPrinter()
    local cfg = Config["Auto Printer"]
    if not cfg or not cfg["Enable"] then return end
    if tick() - PRINTER_CD < 10 then return end

    local inv = getInventory()
    if (inv["Star Egg"] or 0) > 0 then
        PRINTER_CD = tick()
        Events.StickerPrinterActivate:FireServer("Star Egg")
        sendWebhook("🖨️ Star Egg Rolled In Printer!", {}, 16777215)
    end
end

local function checkQuest()
    if QUEST_DONE or not Config["Check Quest"] then return end

    local cache = getCache()
    if not cache then return end

    local completed = deepFind(cache, "Completed")
    if not completed then return end

    for _, q in pairs(completed) do
        if tostring(q) == "Seven To Seven" and not REPORTED_QUESTS["Seven To Seven"] then
            sendWebhook("🐝 Quest 'Seven To Seven' Completed!", {
                { name = "Bee Count", value = tostring(#getBees()), inline = true }
            }, 16776960)
            
            REPORTED_QUESTS["Seven To Seven"] = true
            QUEST_DONE = true
            return
        end
    end
end

local function writeStatus(text)
    if not Config["Auto Change Acc"] then return end
    pcall(function() writefile(Player.Name .. ".txt", text) end)
end

local STICKER_TYPES
pcall(function() STICKER_TYPES = require(RS:FindFirstChild("StickerTypes", true)) end)

local function buildIDMap(tbl, map, seen)
    map = map or {}
    seen = seen or {}
    if seen[tbl] then return map end
    seen[tbl] = true
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            if v.ID then map[tonumber(v.ID)] = tostring(k) end
            buildIDMap(v, map, seen)
        end
    end
    return map
end

local STICKER_ID_MAP = STICKER_TYPES and buildIDMap(STICKER_TYPES) or {}

local function checkStarSign()
    if STATE.WROTE_STATUS then return end

    local cache = getCache()
    if not cache then return end

    local received = deepFind(cache, "Received") or {}
    local completed = deepFind(cache, "Completed") or {}
    local hasEverFound = false
    local foundThisTick = false

    for id, amount in pairs(received) do
        local name = STICKER_ID_MAP[tonumber(id)]
        if name and name:lower():find("star sign") then
            hasEverFound = true
            local last = STATE.LAST_SIGNS[name] or 0
            if amount > last then
                foundThisTick = true
                sendWebhook("🌟 Star Sign Collected!", {
                    { name = "Star Sign", value = name, inline = true },
                    { name = "Amount", value = tostring(amount), inline = true }
                }, 65280) -- Green
                STATE.LAST_SIGNS[name] = amount
            end
        end
    end

    local beeCount = #getBees()
    local playTime = tonumber(deepFind(cache, "PlayTime")) or 0

    -- SUCCESS: Account finished the run and got a Star Sign
    if hasEverFound and beeCount >= 20 and playTime >= 28900 then
        sendWebhook("✅ Run Completed: Star Sign Found!", {
            { name = "Final Status", value = "Obtained Star Sign. Swapping accounts...", inline = false }
        }, 65280) -- Green
        
        writeStatus("Completed-CoStarSign")
        STATE.WROTE_STATUS = true
        return
    end

    -- FAILURE: Account finished the final quest, rolled the egg, and got NO Star Sign
    if isQuestCompleted(completed, "Seven To Seven") and not hasEverFound then
        local inv = getInventory()
        local hasStarEgg = (inv["Star Egg"] or 0) > 0

        if not hasStarEgg and not foundThisTick then
            if STATE.NO_STAR_TIMER == 0 then
                STATE.NO_STAR_TIMER = tick()
            elseif tick() - STATE.NO_STAR_TIMER >= 20 then
                sendWebhook("❌ Run Completed: No Star Sign", {
                    { name = "Final Status", value = "Unlucky run. Swapping to next alt...", inline = false }
                }, 16711680) -- Red
                
                writeStatus("Completed-KoStarSign")
                STATE.WROTE_STATUS = true
                return
            end
        else
            STATE.NO_STAR_TIMER = 0
        end
    end
end

local function autoBuyEggTicket()
    if not Config["Auto Buy Egg Ticket"] then return end
    if tick() - LAST_EGG_BUY < 10 then return end

    local inv = getInventory()
    if (inv["Ticket"] or 0) < 50 then return end

    LAST_EGG_BUY = tick()
    pcall(function()
        Events.ItemPackageEvent:InvokeServer("Purchase", { Type = "Silver", Amount = 1, Category = "Eggs" })
    end)
end

-- ==========================================
-- MAIN LOOP
-- ==========================================
while true do
    autoBuyEggTicket()
    checkStarSign()
    autoFeed()
    autoHatch()
    autoPrinter()
    checkQuest()
    task.wait(5)
end
