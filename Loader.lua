-- ROBUST INITIALIZATION
if not table.clear then table.clear = function(t) for k in pairs(t) do t[k] = nil end end end

if not game:IsLoaded() then game.Loaded:Wait() end
local Players = game:GetService("Players")
local player = Players.LocalPlayer or Players.PlayerAdded:Wait()

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- AUTOMATIC CLEANUP
pcall(function()
    if _G.TerminateHybridScriptUI then _G.TerminateHybridScriptUI() end
end)

local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid", 5)
local rootPart = character:WaitForChild("HumanoidRootPart", 5)

local httpRequest = (syn and syn.request) or (http and http.request) or http_request or request
local setClipboard = setclipboard or toclipboard or function(text) end
local delFile = delfile or function(path) pcall(function() writefile(path, "") end) end

-- CONFIGURATION
local SPOOF_NAME = "NCL"
local MOVE_SPEED = 19
local FOLDER_NAME = "dungeonmacros"
local CONFIG_FILE = string.format("%s/config_%s.json", FOLDER_NAME, player.Name)
local SPAWN_SHIELD_DURATION = 5.0
local MAX_INVENTORY_CAPACITY = 300
local MAIN_LOBBY_PLACE_ID = 77649408247578
local DISCORD_INVITE = "https://discord.gg/sGJ3brqcJu"

-- UI CONTAINER (Prevents exceeding Luau's 200 local register limit)
local UI = {
    catSections = {}
}
local evadingDisplayUntil = 0
local isCleaningUp = false

local function setStatus(text, force)
    if UI.statusLabel and UI.statusLabel.Parent then
        if force or os.clock() >= evadingDisplayUntil then
            UI.statusLabel.Text = text
        end
    end
end

-- SAFE UI SEARCH HELPER
local function findNested(parent, ...)
    local current = parent
    for _, name in ipairs({...}) do
        if not current then return nil end
        current = current:FindFirstChild(name)
    end
    return current
end

-- NON-BLOCKING REMOTE FIRE HELPER
local function safeInvoke(remote, ...)
    if not remote then return end
    local args = {...}
    task.spawn(function()
        pcall(function()
            if remote:IsA("RemoteFunction") then
                remote:InvokeServer(unpack(args))
            elseif remote:IsA("RemoteEvent") then
                remote:FireServer(unpack(args))
            end
        end)
    end)
end

-- LIVE SETTINGS
local SETTINGS = {
    Autoplay = false,
    MinDistance = 15,
    MaxDistance = 35,
    AttackReach = 45,
    AttackCooldown = 0,
    CustomTargetName = "",
    CustomTargetExtraRange = 0,
    IgnoreEnemyNames = "",
    EIFSpammerEnabled = false,
    EIFSpammerSlot = "E",
    EIFSpammerDelay = 0.5,
    DodgeBuffer = 3.5,
    WaypointTriggerDist = 40,
    MaxNodeDistance = 25,
    WallRayLength = 5.5,
    NoEnemyDelay = 10,
    Webhook = "",
    WebhookLogo = "",
    IgnoreKeywords = "ring1, ring2, ring3, ring4, ring5, ring6",
    AutoSellEnabled = false,
    AutoSellConfig = {
        weapon = { common = false, uncommon = false, rare = false, epic = false, legendary = false, ultimate = false },
        helmet = { common = false, uncommon = false, rare = false, epic = false, legendary = false, ultimate = false },
        chest = { common = false, uncommon = false, rare = false, epic = false, legendary = false, ultimate = false },
        ability = { common = false, uncommon = false, rare = false, epic = false, legendary = false, ultimate = false }
    },
    AutoLobbyEnabled = true,
    LobbyMode = "Host",
    JoinPlayerName = "",
    LobbyMap = "Volcanic Chambers",
    LobbyDifficulty = "Easy",
    LobbyHardcore = false,
    LobbyPrivate = false,
    FollowHost = false,
    AutoCreateLobby = true,
    TargetPartySize = 0,
    WaitForPlayers = true,
    AutoDodgeEnabled = true,
    BlackScreen = false,
    ShowRangeCircle = false,
    AutoHideUI = false,
    BoostFPS = false,
    MaxFPS = 60,
    CustomName = "",
    RenameParty = true,
    LogoAvatar = true,
    AutoTrade = false,
    AutoAcceptTrade = false,
    AutoAcceptRequireGold = false,
    AcceptUsername = "",
    TradeUsername = "",
    GameplayMode = "No TP Auto Play",
    ReplayOnDisconnect = false,
    RejoinOnDisconnect = false,
    ReplayTime = ""
}

-- STATE VARIABLES
local isAutoplay = false
local isRecording = false
local isCasting = false
local isDodgeBlinking = false
local hasReturnedToLobby = false
local isHandlingLobbyRoutine = false
local waypoints = {}
local visualNodes = {}
local currentWaypointIndex = 1
local traversingManualNodes = false
local selectedMacroName = ""
local connections = {}
local activeDodgePoint = nil
local dodgeExpiration = 0
local characterSpawnTime = os.clock()
local postDodgeHoldUntil = 0
local lastInvCheckTime = 0
local lastEnemySeenTime = os.clock()
local lastStartValueTime = os.clock()
local partyWasFull = false
local hasReplayedFromTime = false
local lastEifSpamTime = 0

-- PERFORMANCE OPTIMIZATIONS & TEAMMATE TRACKING
local persistentIgnoreList = {character}
local activeHazards = {}
local hazardTracking = {}
local hazardSignals = {}
local trackedHumanoids = setmetatable({}, {__mode = "k"})
local cachedInviswalls = {}
local parsedIgnoreKeywords = {}
local parsedIgnoreEnemyNames = {}
local playerCharacters = {}

local function registerPlayerChar(char)
    if char then playerCharacters[char] = true end
end

local function unregisterPlayerChar(char)
    if char then playerCharacters[char] = nil end
end

local function hookPlayer(p)
    if p.Character then registerPlayerChar(p.Character) end
    table.insert(connections, p.CharacterAdded:Connect(registerPlayerChar))
    table.insert(connections, p.CharacterRemoving:Connect(unregisterPlayerChar))
end

for _, p in ipairs(Players:GetPlayers()) do hookPlayer(p) end
table.insert(connections, Players.PlayerAdded:Connect(hookPlayer))
table.insert(connections, Players.PlayerRemoving:Connect(function(p)
    if p.Character then unregisterPlayerChar(p.Character) end
end))

local function isPlayerOrTeammatePart(obj)
    for char, _ in pairs(playerCharacters) do
        if char and char.Parent and obj:IsDescendantOf(char) then
            return true
        end
    end
    return false
end

local BODY_LIMB_NAMES = {
    ["head"] = true, ["torso"] = true, ["humanoidrootpart"] = true,
    ["left arm"] = true, ["right arm"] = true, ["left leg"] = true, ["right leg"] = true,
    ["uppertorso"] = true, ["lowertorso"] = true,
    ["leftupperarm"] = true, ["leftlowerarm"] = true, ["lefthand"] = true,
    ["rightupperarm"] = true, ["rightlowerarm"] = true, ["righthand"] = true,
    ["leftupperleg"] = true, ["leftlowerleg"] = true, ["leftfoot"] = true,
    ["rightupperleg"] = true, ["rightlowerleg"] = true, ["rightfoot"] = true,
    ["handle"] = true
}

local function isMobLimb(obj)
    local name = obj.Name:lower()
    if BODY_LIMB_NAMES[name] then
        local model = obj:FindFirstAncestorOfClass("Model")
        if model and model:FindFirstChildOfClass("Humanoid") and not Players:GetPlayerFromCharacter(model) then
            return true
        end
    end
    return false
end

local DECORATION_NAMES = { "torch", "lantern", "brazier", "candle", "lamp", "chandelier", "lightpost", "campfire" }

local function isDecoration(obj)
    local name = obj.Name:lower()
    for _, deco in ipairs(DECORATION_NAMES) do
        if name:find(deco) then return true end
    end
    return false
end

local DODGE_DIRECTIONS = (function()
    local dirs = {}
    for i = 0, 15 do
        local angle = (math.pi / 8) * i
        dirs[i + 1] = Vector3.new(math.cos(angle), 0, math.sin(angle))
    end
    return dirs
end)()

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.IgnoreWater = true
raycastParams.FilterDescendantsInstances = persistentIgnoreList

local teleportRayParams = RaycastParams.new()
teleportRayParams.FilterType = Enum.RaycastFilterType.Exclude
teleportRayParams.IgnoreWater = true
teleportRayParams.RespectCanCollide = true
teleportRayParams.FilterDescendantsInstances = persistentIgnoreList

pcall(function()
    if isfolder and makefolder and not isfolder(FOLDER_NAME) then makefolder(FOLDER_NAME) end
end)

local function updateIgnoreKeywords()
    table.clear(parsedIgnoreKeywords)
    table.insert(parsedIgnoreKeywords, "macropathnode")
    if SETTINGS.IgnoreKeywords and SETTINGS.IgnoreKeywords ~= "" then
        for word in string.gmatch(SETTINGS.IgnoreKeywords, "([^,]+)") do
            local cleanWord = word:match("^%s*(.-)%s*$"):lower()
            if cleanWord ~= "" then table.insert(parsedIgnoreKeywords, cleanWord) end
        end
    end
end
updateIgnoreKeywords()

local function updateIgnoreEnemyNames()
    table.clear(parsedIgnoreEnemyNames)
    if SETTINGS.IgnoreEnemyNames and SETTINGS.IgnoreEnemyNames ~= "" then
        for word in string.gmatch(SETTINGS.IgnoreEnemyNames, "([^,]+)") do
            local cleanWord = word:match("^%s*(.-)%s*$"):lower()
            if cleanWord ~= "" then table.insert(parsedIgnoreEnemyNames, cleanWord) end
        end
    end
end
updateIgnoreEnemyNames()

local function isIgnoredEnemy(mob)
    if not mob or not mob.Name then return false end
    local mobName = mob.Name:lower()
    for _, ign in ipairs(parsedIgnoreEnemyNames) do
        if string.find(mobName, ign, 1, true) then
            return true
        end
    end
    return false
end

local function isInLobby()
    if game.PlaceId == MAIN_LOBBY_PLACE_ID then return true end
    local dungeonNameObj = Workspace:FindFirstChild("dungeonName")
    return not dungeonNameObj or not dungeonNameObj.Parent
end
-- AUTO-SELL SYSTEM (Category-Specific Customization)

local function executeAutoSell(quiet)
-- works in the lobby and in a dungeon; it only needs the sell shop GUI to exist in PlayerGui
local pGui = player:FindFirstChild("PlayerGui")
if not pGui then return end
local sellShop = pGui:FindFirstChild("sellShop")
if not sellShop then
    if not quiet then setStatus("Auto-Sell: sell shop GUI not found", true) end
    return
end

local scroll = findNested(sellShop, "Frame", "innerFrame", "rightSideFrame", "ScrollingFrame")
if not scroll then
    if not quiet then setStatus("Auto-Sell: item list not found", true) end
    return
end

local payload = { chest = {}, ability = {}, helmet = {}, weapon = {} }
local totalItemCount = 0

for _, slot in ipairs(scroll:GetChildren()) do
    if slot:IsA("GuiObject") then
        local itemTypeObj = slot:FindFirstChild("itemType")
        if itemTypeObj then
            local rarityObj = itemTypeObj:FindFirstChild("rarity") or slot:FindFirstChild("rarity")
            local uniqueNumObj = itemTypeObj:FindFirstChild("uniqueItemNum") or slot:FindFirstChild("uniqueItemNum")
            
            if rarityObj and uniqueNumObj then
                local s1, catRaw = pcall(function() return itemTypeObj.Value end)
                local s2, rarRaw = pcall(function() return rarityObj.Value end)
                local s3, numRaw = pcall(function() return uniqueNumObj.Value end)
                
                if s1 and s2 and s3 and catRaw and rarRaw and numRaw then
                    local category = tostring(catRaw):lower():gsub("%s+", "")
                    local rarity = tostring(rarRaw):lower():gsub("%s+", "")
                    local uniqueId = tonumber(numRaw)

                    -- Check against category-specific rarity tables
                    if uniqueId and SETTINGS.AutoSellConfig[category] and SETTINGS.AutoSellConfig[category][rarity] then
                        if not payload[category] then payload[category] = {} end
                        table.insert(payload[category], uniqueId)
                        totalItemCount = totalItemCount + 1
                    end
                end
            end
        end
    end
end

if totalItemCount > 0 then
    pcall(function()
        local remotes = ReplicatedStorage:FindFirstChild("remotes")
        if remotes then
            local sellItemEvent = remotes:FindFirstChild("sellItemEvent")
            safeInvoke(sellItemEvent, payload)
        end
    end)
    setStatus(string.format("Auto-Sell: sold %d items", totalItemCount), true)
end
end

-- REPLAY & LOBBY ROUTINE

local function fireReplayDungeonRemote()
if isInLobby() then return end

local currentDungeonName = SETTINGS.LobbyMap
pcall(function()
    local dObj = Workspace:FindFirstChild("dungeonName")
    if dObj then
        if dObj:IsA("StringValue") then currentDungeonName = dObj.Value
        else currentDungeonName = tostring(dObj.Value or dObj) end
    end
end)

pcall(function()
    local remotes = ReplicatedStorage:WaitForChild("remotes", 5)
    if remotes then
        local replayDungeon = remotes:WaitForChild("replayDungeon", 2)
        safeInvoke(replayDungeon, {
            dungeonProgress = "bossKilled", dungeonStarted = true, hardcore = SETTINGS.LobbyHardcore,
            dungeonFinished = true, dungeonName = currentDungeonName, isHardcore = SETTINGS.LobbyHardcore, fightingBoss = true
        })
    end
end)

lastEnemySeenTime = os.clock() + 15
end

local function getInventoryCount()
local pGui = player:FindFirstChild("PlayerGui")
if not pGui then return 0 end
local count = 0
local sellShop = pGui:FindFirstChild("sellShop")

local sellScroll = findNested(sellShop, "Frame", "innerFrame", "rightSideFrame", "ScrollingFrame")
if sellScroll then
    for _, slot in ipairs(sellScroll:GetChildren()) do
        if slot:IsA("GuiObject") and slot:FindFirstChild("itemType") then count = count + 1 end
    end
end

local invSpaceLabel = findNested(pGui, "inventory", "mainBackground", "innerBackground", "rightSideFrame", "inventorySpace")
if invSpaceLabel and invSpaceLabel:IsA("TextLabel") then
    local rawNum = invSpaceLabel.Text:match("(%d+)")
    if rawNum and tonumber(rawNum) then count = math.max(count, tonumber(rawNum)) end
end
return count
end

local function returnToLobby()
if hasReturnedToLobby then return end
hasReturnedToLobby = true
isAutoplay = false
if humanoid then
humanoid.AutoRotate = true
humanoid.WalkSpeed = 16
end
if alignOrient then alignOrient.Enabled = false end
task.spawn(function()
pcall(function()
local remotes = ReplicatedStorage:WaitForChild("remotes", 5)
if remotes then
local returnEvent = remotes:WaitForChild("ReturnToLobbyEvent", 5)
safeInvoke(returnEvent)
end
end)
end)
end

local function checkInventoryFull()
if hasReturnedToLobby then return end
local currentCount = getInventoryCount()
if currentCount >= MAX_INVENTORY_CAPACITY then returnToLobby() end
end

local function getPartyMemberCount()
local pGui = player:FindFirstChild("PlayerGui")
if not pGui then return 0 end

local scroll = findNested(pGui, "queueGui", "lobbyInfo", "backgroundFill", "ScrollingFrame")
if not scroll then return 0 end

local count = 0
for _, child in ipairs(scroll:GetChildren()) do
    if child:IsA("GuiObject") and child.Name ~= "UIListLayout" and child.Name ~= "UIPadding" and child.Name ~= "UIGridLayout" then
        if child.Name ~= player.Name then
            count = count + 1
        end
    end
end
return count
end

local function handleLobbyAutomation()
if isHandlingLobbyRoutine or not isAutoplay or hasReturnedToLobby then return end
if not isInLobby() then return end

isHandlingLobbyRoutine = true

task.spawn(function()
    task.wait(2.5)
    if not isAutoplay then isHandlingLobbyRoutine = false; return end

    if SETTINGS.AutoSellEnabled then
        setStatus("Status: Executing Auto-Sell...")
        executeAutoSell()
        task.wait(1.0)
    end

    checkInventoryFull()
    if hasReturnedToLobby or not isAutoplay then
        isHandlingLobbyRoutine = false
        return
    end

    if not SETTINGS.AutoLobbyEnabled and not SETTINGS.FollowHost then
        isHandlingLobbyRoutine = false
        return
    end

    local remotes = ReplicatedStorage:WaitForChild("remotes", 5)
    if not remotes then isHandlingLobbyRoutine = false; return end

    if SETTINGS.FollowHost or SETTINGS.LobbyMode == "Join" then
        if SETTINGS.JoinPlayerName ~= "" then
            local hostInServer = false
            for _, p in ipairs(Players:GetPlayers()) do
                if p.Name:lower() == SETTINGS.JoinPlayerName:lower() then
                    hostInServer = true
                    break
                end
            end

            if hostInServer then
                local joinRemote = remotes:WaitForChild("joinDungeon", 2)
                safeInvoke(joinRemote, SETTINGS.JoinPlayerName)
            else
                local sendJoinRequest = remotes:WaitForChild("sendJoinRequest", 2)
                safeInvoke(sendJoinRequest, SETTINGS.JoinPlayerName)
            end
        end
        task.wait(2.0)
        isHandlingLobbyRoutine = false
        return
    elseif not SETTINGS.AutoCreateLobby then
        isHandlingLobbyRoutine = false
        return
    else
        local createLobbyRemote = remotes:WaitForChild("createLobby", 2)
        safeInvoke(createLobbyRemote, SETTINGS.LobbyMap, SETTINGS.LobbyDifficulty, 0, SETTINGS.LobbyHardcore, SETTINGS.LobbyPrivate, false)
        
        task.wait(0.6)

        local joinRemote = remotes:WaitForChild("joinDungeon", 2)
        safeInvoke(joinRemote, player.Name)

        if SETTINGS.TargetPartySize > 0 then
            while isAutoplay do
                local currentOtherPlayers = getPartyMemberCount()
                if currentOtherPlayers >= SETTINGS.TargetPartySize then break end
                setStatus(string.format("Status: Waiting for party (%d/%d)...", currentOtherPlayers, SETTINGS.TargetPartySize))
                task.wait(1.0)
            end
        end

        if not isAutoplay then isHandlingLobbyRoutine = false; return end
        task.wait(1.5)

        local startDungeonRemote = remotes:WaitForChild("startDungeon", 2)
        safeInvoke(startDungeonRemote)
        task.wait(0.5)
        safeInvoke(startDungeonRemote)

        isHandlingLobbyRoutine = false
    end
end)
end

local function formatNumber(n) return tostring(n):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "") end
local runStartTime = os.clock()

local function getHttpRequest()
    return (syn and syn.request) or (http and http.request) or http_request or request or (fluxus and fluxus.request)
end

local function cleanWebhookUrl(raw)
    local url = tostring(raw or ""):gsub("^%s+", ""):gsub("%s+$", "")
    return url
end

-- NCL logo (128x128 PNG, base64) uploaded with every webhook message
local NCL_LOGO_B64 = "iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAYAAADDPmHLAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAABnVSURBVHhe7Zx3WBTn2oeNBaR3bCh2RdQco7ELKoIK7C51YYFdyoIURURAFATsMXaNUZPYNRqNMfZeYjQW7CUxCTExlmAv8TigAX/f9b67sztbQPB8+h2+mT/uC710ZneZ+/nNM2/ZWhY2zXcK8JdalnYtIcBfalnYNocAfxEE4DmCADxHEIDnCALwHEEAniMIwHMEAXiOIADPEQTgOYIAPEcQgOcIAvAcQQCeIwjAcwQBeI4gAM8RBOA5ggA8RxCA5wgC8BxBAJ4jCMBzBAF4jiAAzxEE4DmCADxHEIDnCALwHEEAniMIwHMEAXiOIADPEQTgOYIAPEcQgOcIAvAcQQCeIwjAcwQBeI4gAM8RBOA5ggA8RxCA5wgC8JxqC2Bu3QRmlg1hZtmoAhrS/6N/XKXYuKK+VaPXYm7TzPDYGoCpdRPUs24ME+vG9Kcx6ts0NTjuXVA9AWxcYe3cEbZNe8LWpbsGuybdYUd+unSHvUtPWDl1gJlVY1jYtjA8hwGu9GvL7Rt3g2OTHnBo3B2OBvSgP63sW8Pc1tXIOd4EV5jZuKCepRPqWNhzcKA/a1vYo66lI0ytG/9Hr0mOdXbqhKYNu8GlQVdK0wYf6NCsQVc4OLT/j17nTamyAKT6zK1d0DF6B3oXPEHvccXoM7YYfbOL4ZFdDM8xxeg/phiDxj5E3+TzsG3UhaaB/nn0MbVwRNP2QQgdeRfS1LuQDi9GWEoxZCnFiEguRlRyMeRJxVCmPoJ7l+GoZ25vcI7qQD5HXQsHirV9W7Rq7o/O7RTo1WkUvLtNgV+PWRjUdRJ6dEhB+xYBaNCgG+pZNaBC1K9mstW3bgpb+7aYMXgb1gedx5qAE/hS8gPWSY7iK8n32CA+gq/Fh7Er6CTG9voYta0aGJzjbVMtASxsmqFr6gX0nwF4TinDgMllGDipDF6TyuA9sQw+E8owZEIZxNOA9yXLYWpmRytN/1xcTMzt0KpzLKJzAEVWOaKzyhCTWYa4zDIoR5chfnQZhqX/g5Fjga69C1DPzNbgHFXB3KYp6pjbwdS6ETq0lSF4wBqkh1zF5BgGs5TAbCUwNw6YHwcsiAUWxgLz5CWYFnoDiV7fopdbAuwc3DgivD7dTK1d4OjojlUBhdgtu47t0p+xU/oTdkt/xN7Qy9gXegkHQi7glOwXzBmwDLWtGr7zFKi2AB+kFMLzI8BjAoP+BQwGFDDwymcwKJ+Bdx6DwXkMhua/hO/4EjRqJ4GpGanYin9ZJub2aNlJAXn2K0RllEI+mkF0OoOYUQxiRzFQpjGIT2MwIgv4oGcu6lKpDM9TGSaWzvSidWyvQIzoEKbEl2NGIvCREpgW+wJTo0vwkYLBdDmDj+UMZkYxmB31HHOjnmOhvBSfx7zCF4qXmBb0E0RdJ8DarjVqWzgYvI4+KgE6YJn4GLaH/YotoZexLeQitoecx86Qc9gVfAZ7gk7jeNgVzPBcUnME6D8N8JyguvgDOQL4EAHGMxiay0A8Cegbd4zeNsytK25wWAEU2a8g1xMgjhVgJIPUzDcRwBV1zG3RsHEfRIsOYfIwYFoiMDGuFJNiGFr9U6MZTFMwGgFmsAJE/htzo55hXuRTLIh8jE8jHuML+XOsjn6JiaITcG/uj1oW9jCrpDHlCrCDCnCJCrCDCBB8FruDz2BvcCGOSy/XfAFI9RMBhqgF8MstQeBEoE3vMTCpb2NwPhZdAUqgUAtAqj8uTSVAglqArtUQgLxfEvnubgpkyG9jajJQoCxFQSyDibGMUQFI9c+IYjAr6jnmEAEi/8Z8IkDEYyyMeIhFsvtYIruH1fLnWCorhlfH4XjPwgFmFXTwrADLxUexI+wXbA25hO0hF7AjmFT/WewJPk0FOCG9jJk1RYCuKYUYMA3orxZAv/qJAL5EgBwGkvxyDBl1E7YNu6C+pfEGhxUgeswrKDJKDON/JINhIxmMrIYA7MXv1TUH+YllmJgI5CmfIz+OwQS1AOTiT4lmMNVo9RMB2Op/gk8iHuHTiAdYTASIuIvPZcVYGfkAX0Y9RsAH41HXsgHMbQ2TQCvA99gZ9rM2/oPP0eonAuwLPoUT0kuY6bm4hgiQrBVAE//q6qfxzxFAlMMgZCLQVbQCJhU0hDoCjNYKwMY/qX6NAD2qJgCJ/e4fZKEgGcgfVobx5OIrGRSwAqirnwhgNP6jSPz/rRKAVv8jLKIC3MNnsrv4QlaMpeG3sSriDr6NZuD3/mjUsXQyeB+sACs4AuwI1o3/fUGncFJ6sWYIQOiWXIiBU2G0+dPEfw4D/xwG4nEMAnJeInBcKRq3lcDU3LBxIgK06qRAzJhXiB5dqhP/pPmjAqQySMuomgCk8tu3kyE38QXyEsuQq3yOPCWjU/0k/qeo459efEUJZihKMVv+EnMJUc8xL/IZ5tPq58R/xD18LrtDBVgWfhsbFU8xU3QcHZoNpoM8+u+FK8Au6VUa/6T6NfEfdAr7g07ilPQiZtUEAUgCEAG8jAmgF/+sAJKxDELzgYHRbEPoonNeKkBHrQDG4j+xigKYWjaAY8OuGKm4ifxkICeewXglYyCApvpjSjFHCcyLA2ZHl2F6xFN8FH4P8+UlWBJdjs+jy7Ao8qkq/iPu0+on8b9MdgcbFP9GtvdmODi6ozatfsMnHVaAleIj2E0F0Iv/oFM4EHQCp6QXMMtzUc0SQL/548Y/ufiiceoEGMsgaGwJwvKBdr0yUU+vIWQFiM3SCsA2f1wBRmUA3SoVwBX1LOwh8l6LianAuHgGuRwB2Phnm78ZSmBGbDkShu7HgC756NAyBM2aeKJJo95o31yMAZ2zMMJ7JxZFPsYyRQkWR5D4v4PlkfexXv4Myr6L6BNAXTp4Y3jxCRoBRESAn2j3T6qfxn8Qif+TVIBC6QXMrgkCED5MLsQgPQF04l8tAFv9RIDAbAbSnHKIU2/CrsG/UJ8zQsgVICa9RBX/o7TxTy5+UhUEMLFwhqvrYGQPY5Cb+JJWf65SJQCpfiIAG/+zEoDMkKvo3FYOE6sGeM/chg77kj+bWDVEXUsnvGdhh3qWznBrLkae/3GsUpRgRdQTrIp8BMkHeahj6ayOfeMXn8AKsEr0HfZIf9R59t8brIr/g4HHUSg9j9men/73C0ASgAowBZrmj41/TfOXq61+IkAgSYBsBiFjGETmAT38lqkbQtV5WQHiOAKw1c8VIH105QLUNbeHv9dKTBgBjEtgdOKf2/zNTABih+yBLRnVM7dRfS4j52M/MxHBxr4txgzegy8i7qKvmxK1LOwqfPTjYiCAJv5VzR+p/oNBP+C09Bzm1BgBkrQCeOsN/ujHPxUgWytAWPYLhI8pgUtbCUzUDSFXgNj0EoPunwiQPILB6EoEqG/dGA4N3keq4ibGJ5VRAdj4Z6ufCPBxApAo+gGWdi3oJFBl1aulBZ0LcHLqhLbNfFDb0rHKF4kVYLXoMPZKr6jjnzR/2vg/RAQIrUECdE8qhPcUGDR/FcU/ufjB2QxCxzCQZjGIygV85MdgRhpCGxeNAMrMV4gjAnC6f7b6XycAqf6O7nEYn0Kqv1QT/2zzRwZ/pij/Qb7iEVyaeNCJoKpdfJYWdCiZiGD4bxXDCrBGdBj7qADa5o/Gf9BxHA48hjOhZzHHY2HNFoD77K8f/8FjtAKEZ5XQiR/3HlmoZ2ajK8CoUoPmjwiQUgUBBvVbYDT+2e7/42GAb+/59H6vf/zbQivAIewLvazz7H+AI8DZ0LOYW1ME6JFUCJ/JMDL0qxaAXPxxJQgYV0rjn1Q/iX9y8cOIAJkM5NnlCElRNYS1TczRuqMC8RwB9OOfCJAxGviQCGCuKwB5X2SGT+q3EwUkATjdPxv/k+NeYmLMv9G8mY86+g0/39uAFWCt6BD2h15WP/sX0upn4/+7wKM4G3oG8zw++e8XgMAVQCf+Nc/+JRBnP0PguBIEZZfoxH9YJgNZJoOIDAZxOUAf3+WoVacOWrnLEZ/xCspRpUbjf/hwBhnpFQtApnqVoWc1z/5EAG71T4t/hbTgK7C2b0MXgeh/treFVoCDOBB6iXb/+vFPBDgXerpmCTB4MoyO/ZP4D8wrx8D4s+gt3YqwPNDq18S/WoDIDAbyzJeIzihBQ9cBaNY2EAmZWgE08a+ufiJAZgUCkG7cyr4VkmRXkZfEGfyJ0wowPQGI8ztAL35ls3f/26gEcMNa0QEcCL2o1/2rBDgS+D3O1yQBeiYWYghHAP3uPzAfGBB3Ck7NPCBJv4ewcWUI5cQ/qX4iQNRoBsqxgE/ILrTqEIH49H8Qn1aqGfrlVv8ItQDdjQlg7QJbRzekRBQhP/GVQfyTZ/8Zw4Aon630Gb+yx77/bVgBvhQdwMHQi9pnfxL/gar4/z7we1wILcR8jwU1SIBJ0Az+6A/9BuUB3omXYWJmj44ekxCRB0izSjTVTwSIIglAp31LEJPOYHDwLsSm/o34tBKj8U8EyCICdDciAEkAu1ZIll1FQRJ0un926Jc8/il9D9L/S24X+p/tbcEKsE60HwdDLxg0fyoBjuBCSE0UgFP9bPNHBAjOA3wSL9NfNPkwQ+IvIDIHmvs/W/3swo/Y9FIo019CmfZcp/tnmz8iQCoRYJRxATQ9QHAhFcDY4M905Suk/5/1AG5Y578fh0LPa+L/UKA2/o8GHsHFkFOY7zG/ZgjQK7EQQydB0/xx41/CEcDSrhXqmVqjeacoRIwrgyzrhSb+ycXXXfhRotP9s9Wfoq7+1BQGYyoUwBWmVg0ROnQLJiWTeX/tsz879Ds19gWmRZegdXN/OuSr/9neFqwA6/33UQHY5o8b/0cDvsPFkJNYUGMEGKYVQD/+iQAh4wGfYSoByP4AU3NH9AvaBEUudAUg8/5Gpn7Z5o8b/yMrEUC17MsOg/rMxZQUrQD6M39z4oEQj+WobU4Wlb6bXzJXgMMh5wzjP+AIjgUcxiUqwLyaIUDvYYXwnQiDhR/s4A8RYDAVoCVdC2hq4Qynpn0gTXsA+ZgynfgnAlQ09KuJ/xSVANlpQPcPjQnQnI7subeXY0JiOfLJsi8jAkyPeYmPFM/R2tUX71EJqj4SaGnbgk78kGnf6lwgVoCv/PfiOyqAqvnjxr9KgBP4pCYJ4EcEIPGvrn42/snQb6ieAORYMgX8L8+piM0B5KNLaPVXtPBDv/kjAqSpBehRgQBm1k1g5+iOtIhrmJRQrjPzN5ks+1Kv/JkTB2QFXoGTcxfUtjA8T0WQxZ8tm3igv5uSzgLWr2IfoSvAWTrzd1gT/0do/P8QcAiXa5IAfdQCGKt+VoAhmluASgBygYgQ4riLiMuGTvyzy7653T9b/Wz8pyUzGFuJAARyG/D1WIzpSTCofs3KHzmDBXFAdsBlNHPxRC0zq0o3e5AtXbXMbdHaZQBmi0/iW/kThHcrQF2rhjQRSDLoH6N7vEqADf57cCTkDOfZXyUAqf7jAYdwJeQ4Puk3F7WoXE3pWEXFkB1NhtQnP99Anv9IAP2FH2TsX5oLDEnQFYDOqJnZoWVHOWLJxo/RL4yu+9PEP6f6iQCjkhmMe40AZC6/SRMPjI95isnx/+iu+lULwK76XRgDTA27A8/OmbC1b4f3zO3oOn8y01fbguCA9yzs6TSwqMtYLJX+jg2R97Eu/Aa2RN1HWr/P6IxiHbrQtWIJtALsxvchZ+jQryb+afUTAQ6qBZiDWpZOMLVpSiUwtWmG+hzI319HPWuXakvwRgL4T4Bm5o8b/2TiRyuA9hZAsWkGEwtHDAzYjGFjYSgAN/5HcOI/WS3AyMoFINQhawL6LcbMJBgs+56ut+x7geIlFke/QkHgjwjrvZDu/OnSOhz/ahUKr05piO6zEB9LTmN91GOsld3BqrDrWBv2O9aH/Y7tUfcw2XszGjh1Ri2Lip8qWAE2UgFOa8b+ufF/IuAgzgQexEG/zVjiMRdLPeZhmcdcrPCYg5Ues7Cq30ys7jcDa/tNx5f9pmNdv2n4qu9UbOg7BRv7TsLXfSZiU58J2NF3Mj7tlgY7+1ZUBv33UhHVFqBvQiFEHAH0Z/7CcoGhxgQgvxALZzg37Qt56gPEZ5QZXfihuf+rq58IkJ7MIKcKAtS3bgQbh3YYGXwFMxKgWvenWfjJXfWrWvY9P/JvLFaUYml0GZYqSrBM/hwr5M+wWv4M6+TPsCbyAVaE38Sq8D+xWi3AOulv+EpahJ2RxVjk/x3au/SvUAKNAH67cTTktDb+1d0/if8TAQdwSrIP5wL24+egI/gl6BCKgg7gWuB+/BG4F38G7sHNgF24JdmBvyTbcEeyBffE3+K++Bs8FG/CY9FGPBF9hZfijbjmsxiNHd1QrxqDXW8sgEH8q2f+tAJwbwFa6ta3Qbd+U5GUDSjVI3+k+rndv378pydVTQASx2R3b0vXoZgY/ZSu+5umeG6w6YPu+mE3fUSyy74fYknEfXwuu4cvZHfoqt/l4bewMvwGVoVfx5qwP/Bl2DWspwL8io1kn5/sBjaGXIRHm3DUtWpk8H5YAb7224VjwYW0+lXdv6r6SfyfDNiPQsk+nJbswVnxbpwX78RF8XZcEm/DFdEW/CT6Flf9v8Ev/l+jyH8jrvl/hd/91uG675f403cNbvquwm3flXjotxqXvOahkWP7tytAv4RCiNUCsM/+3IUf4ZUkAIFtCIMVF5GUCYP4Z+//bPUTAUYnMcgdCfT8MJc2e/rn1Ke2uR26uCkxLaYEs+KA6fLnmj1/dNcPWfdPBXiCTyLJpo+HWBSh2vWjWvb9FxWAVD8RQFv9RIAibKACXMXW8N+wO/x3+LSPRR0ji0WIAE6ObtjEEUDV/LHxfwAnJUSAvTgj2YNz4l04L95BBbgs2qoWYDN+9t+kFmADrvmtxx9qAW74rsEtKsAKPHqnAhRwBNBb+BGeA/hWIgDbELZ2j0IS2fmb9kJV/Zz4Z6ufjX8qQGrVBSCQAZ/O7eSYGHGf7vjVbPqMfI65nF0/pPqJAHTXD132fQdLqQC3OPH/h078b5D+jO2y69gS9it83OJeewvY5LcTPwSfUjd/bPwf1MT/aclenJXspgJcEO+g1U8E+JFWv0qAX/034jc/Uv1EAFL9a3HDdzUV4K+hRIBVuPyuBJAUQPP4x41/MvUrIwLEV3wLUKFqCH3E3yA1C6+N/4wkBuNTgV7VEIBAkqCpiyfSJefwqRKYI3/JiX9S/epNHxEPaPVrdv3I/sJydfWT5k8b/0XYGFaEXZHFWBFwEj1bBaGWhUOFz+5sAnzDChDAdv/q+KfVv49W/1la/er4Z6vff7NO/KsE0FY/G/9/DV2Ox76rcMVr7tsXwCNeLYDesm+uAH5UgIoSQAVtCF36IC75AYaPKjMY+uXG/5sKQCCjhKQxjPBciznyUiyOARbIGfWuH3X8qzd9GsR/mKr5W0O6//A/sDXyL2yLuIm8AWvpN32Qi6//ely0AuzA8eCTquZPff8/ISHVr45/sSr+SfWz8f+jWgBV9evHP6l+bfwXD12OJ74rccVrzrsRIKAABvHPLvyI4ArwmjdS18wGPfpOQ1omjA7+sPGfkcgg7w0FILccsmSMrPVv29wf8V7fYrbsIb6IeYWl0S/xWdTfWBLxQNP8kV2/K8JvY2X4TayV3cbGyLvYEvUAX8v+xFSfrfBsJ0c9q8Z0MMjwtXRhBdjMCqAZ/DmoFkAd/+rmj8a/iBv/32jjnxWANn9s/JPqJwIswxPfFfjxXQgwIOkigiaBrvwJGl+OkNxyhOaWI2xcOcLHlUOeB0iSil5zC1DBNoQy+SVkZABpI8sxKrUco0eUI3NEObKGl2PM8HJkp5Rj0iigT48CuvFT/zxVgcQ0mQmsZ+VMdwB5vZ+NEd7bMEd6HcujnmFF1N9YLX+KteS5nwz6RN7DFyG/YOrQvYjpMR1dWojpegJyv6/qqiIigLNjB+wU7aULPwuDj+N00DGcDfoe5wO/w8XAw7gUeAhXAg/gp4B9+DlgD34J2IUiyU5ck2zH75JtuC7eghuizbgl+ga3RV/jjv9G3BV9hfv+6/DAby0e+a3BE79VeOG/BtcGLXjLj4HWLvgwZCOGpN+Cz4giDBlehKEpRfBNKYJfchFESUUIHHEL/UO30y+UIsfon0cf8p0/rd3CERN7DbEx1xAbXYQ4RRGUiiIkyIswLKoIiVG/YWT0DXTuOEy9pNvwPFWFiECWd9OdP1YN0aRhT3RuGYxe7WMxqFMaBrgno3sbGd5vIUHzxn3ozCH5DgAyEVTVC89CRvRs7dtgQf/PsNVvOzYN2YTNQzZiy+AN2Dp4PbYNXocdg9di1+A12O2zCnt8VmKf9wrs916Gg95Lcdj7c3w36DMcGbQER70W4ZjXpzjutRAnvBbg1MD5KBw4F2cGzsHZAbPxk9c8bOuVAwf7Nm9nIEiFKyzt28DGuSNsnN21OHFw7ggr+zZUAMPjjUOSwMbBDbZOHWHr5K6DHaUjbB3dKx12fROIDCZWjVCHDAHTYWAH1VAw+eYwSycqSHUvuj7kNYgEzo5ucHJoXyHORmlnlAZGaOjQDvb2rSpsSCuimgKQ7wlsCjOrJirIdwbqY9XktdFviKvhedSQyRoWsvjD8Nj/fkgSmFi70FsCgfyZQjbG6ND0jSGxX53KZ6m2AAL/vxAE4DmCADxHEIDnCALwHEEAniMIwHMEAXiOIADPEQTgOYIAPEcQgOcIAvAcQQCeIwjAcwQBeI4gAM8RBOA5ggA8RxCA5wgC8BxBAJ4jCMBzBAF4jiAAzxEE4DmCADxHEIDnCALwHEEAniMIwHMEAXiOIADPEQTgOYIAPEcQgOcIAvAcQQCeIwjAc2qRr2oV4C//A+Fvuv39VvVXAAAAAElFTkSuQmCC"
local ncLogoBytes
local function getLogoBytes()
    if ncLogoBytes then return ncLogoBytes end
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local lookup = {}
    for i = 1, #chars do lookup[chars:sub(i, i)] = i - 1 end
    local out, bits, nbits = {}, 0, 0
    for i = 1, #NCL_LOGO_B64 do
        local v = lookup[NCL_LOGO_B64:sub(i, i)]
        if v then
            bits = bits * 64 + v
            nbits = nbits + 6
            if nbits >= 8 then
                nbits = nbits - 8
                local byte = math.floor(bits / (2 ^ nbits))
                out[#out + 1] = string.char(byte)
                bits = bits - byte * (2 ^ nbits)
            end
        end
    end
    ncLogoBytes = table.concat(out)
    return ncLogoBytes
end
-- Posts a JSON payload to the webhook and reports the result (status bar, Webhook tab and console).
local function postWebhook(url, payload, label)
    local function report(msg)
        setStatus(msg, true)
        if UI.webhookResult and UI.webhookResult.Parent then UI.webhookResult.Text = msg end
        pcall(warn, "[Webhook] " .. msg)
    end

    url = cleanWebhookUrl(url)
    if url == "" then report("No webhook URL set."); return end
    if not url:match("^https://") then report("URL must start with https://"); return end

    local requestFn = getHttpRequest()
    if not requestFn then report("Your executor has no HTTP request function (request / http_request / syn.request)."); return end

    local attachData
    if payload._attachLogo then
        payload._attachLogo = nil
        pcall(function() attachData = getLogoBytes() end)
    end
    local okEncode, body = pcall(function() return HttpService:JSONEncode(payload) end)
    if not okEncode then report("Could not build the message: " .. tostring(body)); return end

    -- with a local logo file the message is sent as multipart so the image can be referenced as attachment://logo.png
    local contentType = "application/json"
    if attachData then
        local boundary = "----NCL" .. HttpService:GenerateGUID(false):gsub("-", "")
        body = "--" .. boundary .. "\r\nContent-Disposition: form-data; name=\"payload_json\"\r\nContent-Type: application/json\r\n\r\n" .. body
            .. "\r\n--" .. boundary .. "\r\nContent-Disposition: form-data; name=\"files[0]\"; filename=\"logo.png\"\r\nContent-Type: image/png\r\n\r\n" .. attachData
            .. "\r\n--" .. boundary .. "--\r\n"
        contentType = "multipart/form-data; boundary=" .. boundary
    end

    report("Sending...")
    task.spawn(function()
        local ok, response = pcall(requestFn, {
            Url = url,
            Method = "POST",
            Headers = {
                ["Content-Type"] = contentType,
                ["User-Agent"] = "Mozilla/5.0",
            },
            Body = body,
        })
        if not ok then
            report("Request failed: " .. tostring(response))
            return
        end
        if type(response) ~= "table" then
            report("Unexpected response from executor: " .. tostring(response))
            return
        end

        local code = tonumber(response.StatusCode or response.status_code or response.Status)
        local success = response.Success
        if success == nil and code then success = code >= 200 and code < 300 end
        if success then
            report("Sent OK" .. (label and (" (" .. label .. ")") or "") .. " - HTTP " .. tostring(code or "?"))
        else
            local detail = tostring(response.Body or response.body or response.StatusMessage or "")
            if #detail > 120 then detail = detail:sub(1, 120) .. "..." end
            report("Discord refused it: HTTP " .. tostring(code) .. " " .. detail)
        end
    end)
end
local function safeField(value)
    value = tostring(value)
    if value == "" then value = "None" end
    if #value > 1000 then value = value:sub(1, 997) .. "..." end
    return value
end

-- Reads a text label anywhere in PlayerGui whose name (or a parent's name) matches one of the keywords
-- and whose text looks like a number, e.g. "3.75T" or "1,234".
local function findHudNumber(keywords)
    local pGui = player:FindFirstChild("PlayerGui")
    if not pGui then return nil end
    for _, obj in ipairs(pGui:GetDescendants()) do
        if obj:IsA("TextLabel") or obj:IsA("TextButton") then
            local value = obj.Text:match("^%s*([%d%.,]+%s*[KMBTkmbt]?)%s*$")
            if value then
                local current = obj
                for _ = 1, 3 do
                    if not current or current == pGui then break end
                    local lname = current.Name:lower()
                    for _, kw in ipairs(keywords) do
                        if lname:find(kw, 1, true) then return (value:gsub("%s+", "")) end
                    end
                    current = current.Parent
                end
            end
        end
    end
    return nil
end

local function findPlayerStat(names)
    local sources = { player, player:FindFirstChild("leaderstats"), player:FindFirstChild("Data"), player:FindFirstChild("stats") }
    for _, source in ipairs(sources) do
        if source then
            for _, n in ipairs(names) do
                local obj = source:FindFirstChild(n)
                if obj and obj:IsA("ValueBase") then return obj.Value end
            end
        end
    end
    return nil
end

local function displayNumber(value)
    if value == nil then return "Unknown" end
    if type(value) == "number" then return (formatNumber(math.floor(value))) end
    return tostring(value)
end

-- "2,748,635,920,988 (2.75T)": full number plus a short K / M / B / T / Q form
local function abbreviateNumber(n)
    local units = { {1e15, "Q"}, {1e12, "T"}, {1e9, "B"}, {1e6, "M"}, {1e3, "K"} }
    for _, u in ipairs(units) do
        if n >= u[1] then
            return tostring(tonumber(string.format("%.2f", n / u[1]))) .. u[2]
        end
    end
    return tostring(n)
end

local function displayCurrency(value)
    if value == nil then return "Unknown" end
    local num = value
    if type(value) == "string" then num = tonumber((value:gsub(",", ""))) end
    if type(num) ~= "number" then return tostring(value) end -- already short text like "3.75T"
    local full = (formatNumber(math.floor(num)))
    if num >= 1000 then return full .. " (**" .. abbreviateNumber(num) .. "**)" end
    return full
end

local function readTimeLeft()
    local pGui = player:FindFirstChild("PlayerGui")
    local timeGui = pGui and pGui:FindFirstChild("timeLeftGui")
    local label = timeGui and findNested(timeGui, "Frame", "time")
    if label and label:IsA("TextLabel") and label.Text ~= "" then return label.Text end
    return "N/A"
end

local function buildItemsText(rewardData)
    local itemsList = {}
    if type(rewardData) == "table" and type(rewardData.items) == "table" then
        for _, item in ipairs(rewardData.items) do
            local lname = type(item) == "table" and tostring(item.itemName or item.name or ""):lower() or ""
            if type(item) == "table" and not lname:find("gem", 1, true) and not lname:find("gold", 1, true) then
                local name = tostring(item.itemName or "Unknown Item")
                local rarity = item.rarity and ("[" .. tostring(item.rarity):upper() .. "]") or ""
                local tier = item.tier and ("(" .. tostring(item.tier) .. ")") or ""
                local itemType = item.itemType and ("• " .. tostring(item.itemType)) or ""
                table.insert(itemsList, string.format("• **%s** %s %s %s", name, rarity, tier, itemType))
            end
        end
    end
    return #itemsList > 0 and table.concat(itemsList, "\n") or "None"
end

local function toAmount(v)
    if type(v) == "number" then return v end
    if type(v) == "string" then
        local n = tonumber((v:gsub(",", "")))
        if n then return n end
        return tonumber(v:match("([%d,%.]+)") and (v:match("([%d,%.]+)"):gsub(",", "")))
    end
    return nil
end

-- amount of an item entry: numeric fields first, then a number inside its name ("3,230 Gems", "x50 Gems")
local function itemAmount(item)
    for _, k in ipairs({ "amount", "quantity", "count", "value", "qty", "number", "total", "gems", "gem", "gold" }) do
        local n = toAmount(item[k])
        if n then return n end
    end
    local n = toAmount(tostring(item.itemName or item.name or ""):match("[%d,%.]+"))
    return n or 1
end

local function extractGains(rewardData)
    local gold, gems
    -- 1) numeric fields whose key contains "gold" / "gem", searched through nested tables too (first hit wins, no double counting)
    local function scan(tbl, depth)
        if depth > 4 then return end
        for k, v in pairs(tbl) do
            if type(v) == "table" then
                if k ~= "items" then scan(v, depth + 1) end
            elseif type(k) == "string" then
                local lk, n = k:lower(), toAmount(v)
                if n then
                    if lk:find("gem", 1, true) and gems == nil then gems = n end
                    if lk:find("gold", 1, true) and gold == nil then gold = n end
                end
            end
        end
    end
    scan(rewardData, 0)
    -- 2) item entries named gold / gems, only when the fields above did not have it
    if type(rewardData.items) == "table" then
        local itemGold, itemGems
        for _, item in pairs(rewardData.items) do
            if type(item) == "table" then
                local name = tostring(item.itemName or item.name or item.itemType or ""):lower()
                if name:find("gem", 1, true) then itemGems = (itemGems or 0) + itemAmount(item)
                elseif name:find("gold", 1, true) then itemGold = (itemGold or 0) + itemAmount(item) end
            end
        end
        if gems == nil then gems = itemGems end
        if gold == nil then gold = itemGold end
    end
    -- 3) gems still unknown: use how much your total Gems changed since the last reward
    local cur = findPlayerStat({"Gems", "gems", "Diamonds", "Gem"})
    -- the real change in your Gems stat is the most reliable amount, so it wins over field guesses
    if type(cur) == "number" and type(UI.lastGems) == "number" and cur > UI.lastGems then
        gems = cur - UI.lastGems
    end
    if type(cur) == "number" then UI.lastGems = cur end
    -- console dump so the real reward layout can be checked if this still shows 0
    if gems == nil then
        pcall(function() warn("[Webhook] no gems found in reward data: " .. HttpService:JSONEncode(rewardData)) end)
    end
    return gold or 0, gems or 0
end
pcall(function() local g = findPlayerStat({"Gems", "gems", "Diamonds", "Gem"}); if type(g) == "number" then UI.lastGems = g end end)

-- " (Nightmare)": difficulty of the current run. Uses a difficulty value from the game if one exists in Workspace,
-- otherwise the difficulty picked in the Misc tab.
function UI.getDifficultyTextBasic(mapName)
    local diff
    -- 1) look for a real difficulty value / attribute / HUD label in the game (name contains "difficulty" or "diff")
    pcall(function()
        local function isDiffName(n) n = tostring(n):lower(); return n:find("difficulty", 1, true) or n == "diff" end
        local function fromAttributes(inst)
            for k, v in pairs(inst:GetAttributes()) do
                if isDiffName(k) and tostring(v) ~= "" then return tostring(v) end
            end
        end
        local dObj = Workspace:FindFirstChild("dungeonName")
        diff = dObj and fromAttributes(dObj) or fromAttributes(Workspace)
        if diff then return end
        for _, root in ipairs({ Workspace, ReplicatedStorage, player }) do
            for _, obj in ipairs(root:GetDescendants()) do
                if obj:IsA("ValueBase") and isDiffName(obj.Name) and tostring(obj.Value) ~= "" then diff = tostring(obj.Value); return end
            end
        end
        local pGui = player:FindFirstChild("PlayerGui")
        for _, obj in ipairs(pGui and pGui:GetDescendants() or {}) do
            if obj:IsA("TextLabel") and isDiffName(obj.Name) and obj.Text ~= "" and #obj.Text < 20 then diff = obj.Text; return end
        end
    end)
    -- 2) no real value found: only trust the Misc tab setting when you hosted this exact map yourself
    if not diff and SETTINGS.LobbyMode == "Host" and tostring(mapName or ""):lower() == tostring(SETTINGS.LobbyMap):lower() then
        diff = SETTINGS.LobbyDifficulty
    end
    diff = tostring(diff or "")
    return diff ~= "" and (" (" .. diff .. ")") or ""
end

UI.knownDifficulties = { easy = true, normal = true, medium = true, hard = true, expert = true, insane = true, nightmare = true, extreme = true, impossible = true }

-- Looks for the run's difficulty in (1) the reward data the game sent, (2) a visible HUD label that shows exactly one
-- difficulty name, (3) the game values / your own setting (see UI.getDifficultyTextBasic). Logs the reward data if all fail.
function UI.getDifficultyText(mapName, rewardData)
    local found
    pcall(function()
        local function scan(tbl, depth)
            if found or depth > 4 then return end
            for k, v in pairs(tbl) do
                if type(v) == "table" then scan(v, depth + 1)
                elseif type(k) == "string" and k:lower():find("diff", 1, true) and tostring(v) ~= "" then found = tostring(v); return end
            end
        end
        if type(rewardData) == "table" then scan(rewardData, 0) end
    end)
    if not found then
        pcall(function()
            local pGui = player:FindFirstChild("PlayerGui")
            local names, list = {}, {}
            for _, obj in ipairs(pGui and pGui:GetDescendants() or {}) do
                if obj:IsA("TextLabel") and obj.Visible and obj.AbsoluteSize.X > 0 and not (UI.screenGui and obj:IsDescendantOf(UI.screenGui)) then
                    local txt = obj.Text:match("^%s*(.-)%s*$")
                    if UI.knownDifficulties[txt:lower()] then
                        local shown, cur = true, obj
                        while cur and cur ~= pGui do
                            if (cur:IsA("GuiObject") and not cur.Visible) or (cur:IsA("ScreenGui") and not cur.Enabled) then shown = false break end
                            cur = cur.Parent
                        end
                        if shown then names[txt] = true end
                    end
                end
            end
            for n in pairs(names) do table.insert(list, n) end
            if #list == 1 then found = list[1] end
        end)
    end
    if found then return " (" .. found .. ")" end
    local basic = UI.getDifficultyTextBasic(mapName)
    if basic == "" and type(rewardData) == "table" then
        pcall(function() warn("[Webhook] difficulty not found. Reward data from the game: " .. HttpService:JSONEncode(rewardData)) end)
    end
    return basic
end

local function buildStatusEmbed(clearTime, title, rewardData)
    local level = findPlayerStat({"Level", "level", "Lvl"})
    if level == nil then level = findHudNumber({"level", "lvl"}) end
    local gold = findPlayerStat({"Gold", "gold", "Coins", "Money"})
    if gold == nil then gold = findHudNumber({"gold", "coin", "money"}) end
    local gems = findPlayerStat({"Gems", "gems", "Diamonds", "Gem"})
    if gems == nil then gems = findHudNumber({"gem", "diamond"}) end

    -- map name of the dungeon you are in (the game keeps it in Workspace.dungeonName)
    local mapName = "Lobby"
    if not isInLobby() then
        mapName = SETTINGS.LobbyMap
        pcall(function()
            local dObj = Workspace:FindFirstChild("dungeonName")
            if dObj then
                local v = dObj:IsA("ValueBase") and dObj.Value or dObj.Name
                if tostring(v) ~= "" then mapName = tostring(v) end
            end
        end)
    end

    local logo = "attachment://logo.png"
    local attach = true
    local embed = {
        ["author"] = { ["name"] = "NCL MACRO  •  Auto Farm Report" },
        ["title"] = "⚔️ " .. (title or "Dungeon Quest Reborn"),
        ["color"] = 5814783,
        ["fields"] = {
            {["name"] = "👤 Player", ["value"] = "||" .. player.Name .. "||", ["inline"] = true},
            {["name"] = "⭐ Level", ["value"] = "**" .. displayNumber(level) .. "**", ["inline"] = true},
            {["name"] = "👥 Party", ["value"] = "**" .. tostring(#Players:GetPlayers()) .. "**", ["inline"] = true},
            {["name"] = "🪙 Total Gold", ["value"] = safeField(displayCurrency(gold)), ["inline"] = true},
            {["name"] = "💎 Total Gems", ["value"] = safeField(displayCurrency(gems)), ["inline"] = true},
            {["name"] = "⏱️ Run Time: " .. tostring(clearTime), ["value"] = "⌛ **Time Left: " .. readTimeLeft() .. "**", ["inline"] = true},
            {["name"] = "🗺️ Map Cleared", ["value"] = "**" .. safeField(mapName .. (isInLobby() and "" or UI.getDifficultyText(mapName, rewardData))) .. "**", ["inline"] = true},
            {["name"] = "🎒 Inventory", ["value"] = "**" .. tostring(getInventoryCount()) .. "/" .. tostring(MAX_INVENTORY_CAPACITY) .. "**", ["inline"] = true},
        },
        ["footer"] = { ["text"] = "NCL MACRO  •  Dungeon Quest Reborn" },
        ["timestamp"] = DateTime.now():ToIsoDate()
    }
    if logo ~= "" then
        embed["thumbnail"] = { ["url"] = logo }
        embed["footer"]["icon_url"] = logo
        embed["author"]["icon_url"] = logo
    end
    if rewardData ~= nil then
        local goldGain, gemGain = extractGains(rewardData)
        table.insert(embed["fields"], {["name"] = "🎁 Rewards", ["value"] = "🪙 **+" .. safeField(displayCurrency(goldGain)) .. "**\n💎 **+" .. safeField(displayCurrency(gemGain)) .. "**", ["inline"] = false})
        table.insert(embed["fields"], {["name"] = "📦 Items Received", ["value"] = safeField(buildItemsText(rewardData)), ["inline"] = false})
    end

    local body = { ["username"] = "NCL MACRO", ["embeds"] = { embed } }
    if logo ~= "" and not attach then body["avatar_url"] = logo end
    if attach then body["_attachLogo"] = true end
    return body
end
local function sendRewardWebhook(rewardData)
    local url = cleanWebhookUrl(SETTINGS.Webhook)
    if url == "" then return end

    local elapsed = os.clock() - runStartTime
    local timeText = string.format("%dm %ds", math.floor(elapsed / 60), math.floor(elapsed % 60))
    runStartTime = os.clock()

    -- wait a moment so the game has added the rewards to your Gems stat before it is read
    task.spawn(function()
        task.wait(1.5)
        postWebhook(url, buildStatusEmbed(timeText, nil, rewardData), "match")
    end)
end

local function sendTestWebhook(url)
    local elapsed = os.clock() - runStartTime
    postWebhook(url, buildStatusEmbed(string.format("%dm %ds", math.floor(elapsed / 60), math.floor(elapsed % 60)), nil, {}), "test")
end
UI.sendTestWebhook = sendTestWebhook
-- Reward Hook
task.spawn(function()
local remotes = ReplicatedStorage:WaitForChild("remotes", 5)
if remotes then
local cloneRewardGui = remotes:WaitForChild("cloneRewardGui", 5)
if cloneRewardGui then
local conn = cloneRewardGui.OnClientEvent:Connect(function(data)
if type(data) == "table" then pcall(sendRewardWebhook, data) end

            if isAutoplay then
                task.spawn(function()
                    task.wait(1.5)
                    checkInventoryFull()
                    if not hasReturnedToLobby then
                        fireReplayDungeonRemote()
                    end
                end)
            end
        end)
        table.insert(connections, conn)
    end
end
end)

-- Invite Request Hook
task.spawn(function()
local remotes = ReplicatedStorage:WaitForChild("remotes", 5)
if remotes then
local showJoinRequest = remotes:WaitForChild("showJoinRequest", 5)
if showJoinRequest then
local conn = showJoinRequest.OnClientEvent:Connect(function(reqId, pName)
pcall(warn, "[Join] showJoinRequest fired: " .. tostring(reqId) .. ", " .. tostring(pName) .. " (autoplay=" .. tostring(isAutoplay) .. ", role=" .. tostring(SETTINGS.LobbyMode) .. ")")
if isAutoplay and SETTINGS.LobbyMode == "Host" and not SETTINGS.FollowHost then
task.spawn(function()
task.wait(0.1)
local respondJoinRequest = remotes:FindFirstChild("respondJoinRequest")
if respondJoinRequest then
respondJoinRequest:FireServer(reqId, true)
end
end)
end
end)
table.insert(connections, conn)
end
end
end)

-- Rejoin Hook
task.spawn(function()
local promptOverlay
pcall(function() promptOverlay = CoreGui:WaitForChild("RobloxPromptGui", 3):WaitForChild("promptOverlay", 3) end)

if promptOverlay then
    local conn = promptOverlay.ChildAdded:Connect(function(child)
        if SETTINGS.RejoinOnDisconnect and child.Name == "ErrorPrompt" then
            task.wait(1.5)
            local TeleportService = game:GetService("TeleportService")
            pcall(function() TeleportService:Teleport(MAIN_LOBBY_PLACE_ID) end)
        end
    end)
    table.insert(connections, conn)
end
end)

-- 2. DISK PERSISTENCE & CONFIG CONSTRUCTORS

local function buildConfigTable()
return {
Autoplay = SETTINGS.Autoplay,
SelectedMacro = selectedMacroName,
Webhook = SETTINGS.Webhook,
WebhookLogo = SETTINGS.WebhookLogo,
IgnoreKeywords = SETTINGS.IgnoreKeywords,
IgnoreEnemyNames = SETTINGS.IgnoreEnemyNames,
MinDistance = SETTINGS.MinDistance,
MaxDistance = SETTINGS.MaxDistance,
AttackReach = SETTINGS.AttackReach,
AttackCooldown = SETTINGS.AttackCooldown,
CustomTargetName = SETTINGS.CustomTargetName,
CustomTargetExtraRange = SETTINGS.CustomTargetExtraRange,
EIFSpammerEnabled = SETTINGS.EIFSpammerEnabled,
EIFSpammerSlot = SETTINGS.EIFSpammerSlot,
EIFSpammerDelay = SETTINGS.EIFSpammerDelay,
DodgeBuffer = SETTINGS.DodgeBuffer,
WaypointTriggerDist = SETTINGS.WaypointTriggerDist,
MaxNodeDistance = SETTINGS.MaxNodeDistance,
WallRayLength = SETTINGS.WallRayLength,
NoEnemyDelay = SETTINGS.NoEnemyDelay,
AutoSellEnabled = SETTINGS.AutoSellEnabled,
AutoSellConfig = SETTINGS.AutoSellConfig,
AutoLobbyEnabled = SETTINGS.AutoLobbyEnabled,
LobbyMode = SETTINGS.LobbyMode,
JoinPlayerName = SETTINGS.JoinPlayerName,
LobbyMap = SETTINGS.LobbyMap,
LobbyDifficulty = SETTINGS.LobbyDifficulty,
LobbyHardcore = SETTINGS.LobbyHardcore,
LobbyPrivate = SETTINGS.LobbyPrivate,
FollowHost = SETTINGS.FollowHost,
AutoCreateLobby = SETTINGS.AutoCreateLobby,
TargetPartySize = SETTINGS.TargetPartySize,
WaitForPlayers = SETTINGS.WaitForPlayers,
AutoDodgeEnabled = SETTINGS.AutoDodgeEnabled,
BlackScreen = SETTINGS.BlackScreen,
ShowRangeCircle = SETTINGS.ShowRangeCircle,
AutoHideUI = SETTINGS.AutoHideUI,
BoostFPS = SETTINGS.BoostFPS,
MaxFPS = SETTINGS.MaxFPS,
CustomName = SETTINGS.CustomName,
RenameParty = SETTINGS.RenameParty,
LogoAvatar = SETTINGS.LogoAvatar,
AutoTrade = SETTINGS.AutoTrade,
AutoAcceptTrade = SETTINGS.AutoAcceptTrade,
AutoAcceptRequireGold = SETTINGS.AutoAcceptRequireGold,
AcceptUsername = SETTINGS.AcceptUsername,
TradeUsername = SETTINGS.TradeUsername,
GameplayMode = SETTINGS.GameplayMode,
ReplayOnDisconnect = SETTINGS.ReplayOnDisconnect,
RejoinOnDisconnect = SETTINGS.RejoinOnDisconnect,
ReplayTime = SETTINGS.ReplayTime
}
end

local function saveConfig()
if isCleaningUp then return end
if not writefile then return end
pcall(function() if not isfolder(FOLDER_NAME) then makefolder(FOLDER_NAME) end end)

local cfgData = buildConfigTable()
local encodeSuccess, encodedData = pcall(function() return HttpService:JSONEncode(cfgData) end)
if encodeSuccess and encodedData then pcall(function() writefile(CONFIG_FILE, encodedData) end) end
end

local function applySetting(inputBox, settingKey)
if isCleaningUp then return end
local val = tonumber(inputBox.Text)
if val then
SETTINGS[settingKey] = val
setStatus(settingKey .. " updated to " .. tostring(val))
saveConfig()
else
inputBox.Text = tostring(SETTINGS[settingKey])
end
end

-- 3. MACRO STORAGE & PATHFINDING HELPERS

local function rebuildIgnoreList()
table.clear(persistentIgnoreList)
if character then table.insert(persistentIgnoreList, character) end
for _, nodePart in ipairs(visualNodes) do
if nodePart and nodePart.Parent then table.insert(persistentIgnoreList, nodePart) end
end
raycastParams.FilterDescendantsInstances = persistentIgnoreList
teleportRayParams.FilterDescendantsInstances = persistentIgnoreList
end

local function clearWaypoints()
for _, nodePart in ipairs(visualNodes) do if nodePart then nodePart:Destroy() end end
table.clear(visualNodes)
table.clear(waypoints)
rebuildIgnoreList()
currentWaypointIndex = 1
traversingManualNodes = false
setStatus("Status: Waypoints Cleared")
end

local function renderVisualNode(pos, index)
local visualPart = Instance.new("Part")
visualPart.Name = "MacroPathNode_" .. index
visualPart.Shape = Enum.PartType.Ball
visualPart.Size = Vector3.new(1.5, 1.5, 1.5)
visualPart.Anchored = true
visualPart.CanCollide = false
visualPart.Material = Enum.Material.Neon
visualPart.Color = Color3.fromRGB(0, 255, 128)
visualPart.Transparency = 0.4
visualPart.CFrame = CFrame.new(pos)
visualPart.Parent = Workspace
table.insert(visualNodes, visualPart)
rebuildIgnoreList()
end

local function addWaypointNode()
if not rootPart then return end
local pos = rootPart.Position
table.insert(waypoints, pos)
renderVisualNode(pos, #waypoints)
setStatus(string.format("Waypoint (%.1f, %.1f, %.1f) added", pos.X, pos.Y, pos.Z))
end

local function loadMacroFromFile(macroName)
local filePath = FOLDER_NAME .. "/" .. macroName .. ".json"
if not isfile or not isfile(filePath) then return false end
clearWaypoints()
local success, decoded = pcall(function() return HttpService:JSONDecode(readfile(filePath)) end)
if success and type(decoded) == "table" then
for i, posData in ipairs(decoded) do
local vec = Vector3.new(posData.X, posData.Y, posData.Z)
table.insert(waypoints, vec)
renderVisualNode(vec, i)
end
return true
end
return false
end

local function refreshMacroList()
if not UI.macroScroll then return end
if UI.macroDropBtn then
    UI.macroDropBtn.Text = "  " .. (selectedMacroName ~= "" and selectedMacroName or "Select a macro...") .. "   ▼"
    UI.macroDropBtn.TextColor3 = selectedMacroName ~= "" and Color3.fromRGB(232, 236, 255) or Color3.fromRGB(128, 138, 172)
end
for _, child in ipairs(UI.macroScroll:GetChildren()) do
if child:IsA("TextButton") then child:Destroy() end
end
if not listfiles or not isfolder(FOLDER_NAME) then return end

local files = listfiles(FOLDER_NAME)
local count = 0
for _, filePath in ipairs(files) do
    local fileName = filePath:match("([^/\\]+)$") or filePath
    if fileName:sub(-5) == ".json" and not fileName:lower():match("^config") then
        count = count + 1
        local cleanName = fileName:sub(1, -6)

        local itemBtn = Instance.new("TextButton")
        itemBtn.Name = cleanName
        itemBtn.Text = "  " .. cleanName
        itemBtn.Size = UDim2.new(1, -4, 0, 24)
        itemBtn.ZIndex = 51
        itemBtn.BackgroundColor3 = (selectedMacroName == cleanName) and Color3.fromRGB(72, 92, 235) or Color3.fromRGB(28, 34, 62)
        itemBtn.TextColor3 = Color3.fromRGB(240, 240, 250)
        itemBtn.Font = Enum.Font.Gotham
        itemBtn.TextSize = 13
        itemBtn.TextXAlignment = Enum.TextXAlignment.Left
        itemBtn.BorderSizePixel = 0
        itemBtn.Parent = UI.macroScroll
        Instance.new("UICorner", itemBtn).CornerRadius = UDim.new(0, 6)

        itemBtn.MouseButton1Click:Connect(function()
            if selectedMacroName == cleanName then
                selectedMacroName = ""
                clearWaypoints()
                setStatus("Unselected Macro: " .. cleanName)
            else
                selectedMacroName = cleanName
                loadMacroFromFile(cleanName)
                setStatus("Selected Macro: " .. cleanName)
            end
            refreshMacroList()
            UI.macroScroll.Visible = false
            saveConfig()
        end)
    end
end
UI.macroScroll.CanvasSize = UDim2.new(0, 0, 0, count * 26 + 8)
end

local RARITY_ORDER = {"common", "uncommon", "rare", "epic", "legendary", "ultimate"}

local function updateCategoryDropdownTitle(catKey)
local data = UI.catSections[catKey]
if not data then return end
local activeRarities = {}
for _, r in ipairs(RARITY_ORDER) do
if SETTINGS.AutoSellConfig[catKey] and SETTINGS.AutoSellConfig[catKey][r] then
table.insert(activeRarities, r:sub(1, 3):upper())
end
end
local titleBase = data.displayName
if #activeRarities == 0 then
data.headerBtn.Text = string.format("%s [None Selected ▼]", titleBase)
else
data.headerBtn.Text = string.format("%s [%s ▼]", titleBase, table.concat(activeRarities, ", "))
end
end

-- BLACKSCREEN (AFK / low-GPU mode)

local BLACKSCREEN_KEY = Enum.KeyCode.RightControl

local function refreshBlackScreenButtons()
    local on = SETTINGS.BlackScreen
    if UI.blackScreenRow then
        UI.blackScreenRow.Text = "Black Screen (RightCtrl): " .. (on and "ON" or "OFF")
        UI.blackScreenRow.BackgroundColor3 = on and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
    end
    if UI.blackScreenQuickBtn then
        UI.blackScreenQuickBtn.Text = on and "☀" or "🌑"
    end
end

local function applyBlackScreen(enabled, skipSave)
    SETTINGS.BlackScreen = enabled and true or false
    pcall(function() RunService:Set3dRenderingEnabled(not SETTINGS.BlackScreen) end)

    if SETTINGS.BlackScreen then
        if not UI.blackGui or not UI.blackGui.Parent then
            local gui = Instance.new("ScreenGui")
            gui.Name = "DungeonBlackScreen"
            gui.ResetOnSpawn = false
            gui.IgnoreGuiInset = true
            gui.DisplayOrder = 100 -- above the game HUD (and the swapped NCL avatar icon), below the manager UI
            gui.Parent = UI.screenGui and UI.screenGui.Parent or player:WaitForChild("PlayerGui")

            local bg = Instance.new("Frame")
            bg.Size = UDim2.new(1, 0, 1, 0)
            bg.BackgroundColor3 = Color3.new(0, 0, 0)
            bg.BorderSizePixel = 0
            bg.Parent = gui

            -- centered info panel: logo + live stats
            -- faint full-screen logo watermark (the embedded logo is written to the workspace so Roblox can load it)
            pcall(function()
                local path = FOLDER_NAME .. "/nclbg.png"
                if writefile and getcustomasset then
                    writefile(path, getLogoBytes())
                    local wm = Instance.new("ImageLabel")
                    wm.AnchorPoint = Vector2.new(0.5, 0.5)
                    wm.Position = UDim2.new(0.5, 0, 0.5, 0)
                    wm.Size = UDim2.new(1, 0, 1, 0)
                    wm.BackgroundTransparency = 1
                    wm.Image = getcustomasset(path)
                    wm.ScaleType = Enum.ScaleType.Fit
                    wm.ImageTransparency = 0.88
                    wm.Parent = bg
                end
            end)

            local panel = Instance.new("Frame")
            panel.AnchorPoint = Vector2.new(0.5, 0.5)
            panel.Position = UDim2.new(0.5, 0, 0.5, 0)
            panel.Size = UDim2.new(1, 0, 0, 560)
            panel.BackgroundTransparency = 1
            panel.Parent = bg

            local info = Instance.new("TextLabel")
            info.Position = UDim2.new(0, 0, 0, 130)
            info.Size = UDim2.new(1, 0, 0, 430)
            info.BackgroundTransparency = 1
            info.TextColor3 = Color3.fromRGB(255, 255, 255)
            info.Font = Enum.Font.GothamBold
            info.TextSize = 36
            info.TextYAlignment = Enum.TextYAlignment.Top
            info.Text = ""
            info.Parent = panel

            local locationLabel = Instance.new("TextLabel")
            locationLabel.AnchorPoint = Vector2.new(0.5, 0)
            locationLabel.Position = UDim2.new(0.5, 0, 0, 10)
            locationLabel.Size = UDim2.new(1, 0, 0, 100)
            locationLabel.BackgroundTransparency = 1
            locationLabel.Font = Enum.Font.GothamBlack
            locationLabel.TextSize = 72
            locationLabel.TextStrokeTransparency = 0.5
            locationLabel.Parent = panel

            local function refreshInfo()
                local inLobby = isInLobby()
                locationLabel.Text = inLobby and "YOU ARE IN LOBBY" or "YOU ARE IN GAME"
                locationLabel.TextColor3 = inLobby and Color3.fromRGB(255, 50, 50) or Color3.fromRGB(70, 140, 255)
                local custom = tostring(SETTINGS.CustomName or ""):gsub("^%s+", ""):gsub("%s+$", "")
                local elapsed = os.clock() - runStartTime
                local lines = {
                    "NCL HUB",
                    player.Name:upper(),
                    "LEVEL " .. displayNumber(findPlayerStat({"Level", "level", "Lvl"}) or findHudNumber({"level", "lvl"})),
                    "GOLD " .. displayCurrency(findPlayerStat({"Gold", "gold", "Coins", "Money"}) or findHudNumber({"gold", "coin", "money"})),
                    "GEMS " .. displayCurrency(findPlayerStat({"Gems", "gems", "Diamonds", "Gem"}) or findHudNumber({"gem", "diamond"})),
                    "STORAGE " .. tostring(getInventoryCount()) .. "/" .. tostring(MAX_INVENTORY_CAPACITY),
                    "PARTY " .. tostring(#Players:GetPlayers()),
                    string.format("TIME RUNNING %dm %ds", math.floor(elapsed / 60), math.floor(elapsed % 60)),
                    "TIME LEFT " .. readTimeLeft(),
                }
                info.Text = (table.concat(lines, "\n"):gsub("%*%*", ""))
            end
            refreshInfo()
            task.spawn(function()
                while not isCleaningUp and gui.Parent do
                    if gui.Enabled then pcall(refreshInfo) end
                    task.wait(1)
                end
            end)

            UI.blackGui = gui
        end
        UI.blackGui.Enabled = true
    elseif UI.blackGui then
        UI.blackGui.Enabled = false
    end

    refreshBlackScreenButtons()
    setStatus(SETTINGS.BlackScreen and "Status: Black Screen ON" or "Status: Black Screen OFF", true)
    if not skipSave then saveConfig() end
end
UI.applyBlackScreen = applyBlackScreen

-- BOOST FPS: lowers rendering quality/effects so the client has less to draw each frame
local RENDER_BACKUP = {}
local boostedEffects = setmetatable({}, {__mode = "k"})
local boostFpsConnection

local function isEffectInstance(obj)
    return obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") or obj:IsA("Smoke") or obj:IsA("Fire") or obj:IsA("Sparkles")
end

local function applyBoostFPS(enabled, skipSave)
    SETTINGS.BoostFPS = enabled and true or false

    pcall(function()
        local Lighting = game:GetService("Lighting")
        if SETTINGS.BoostFPS then
            RENDER_BACKUP.GlobalShadows = Lighting.GlobalShadows
            RENDER_BACKUP.FogEnd = Lighting.FogEnd
            Lighting.GlobalShadows = false
            Lighting.FogEnd = 100000
        elseif RENDER_BACKUP.GlobalShadows ~= nil then
            Lighting.GlobalShadows = RENDER_BACKUP.GlobalShadows
            Lighting.FogEnd = RENDER_BACKUP.FogEnd
        end
    end)

    pcall(function()
        settings().Rendering.QualityLevel = SETTINGS.BoostFPS and Enum.QualityLevel.Level01 or Enum.QualityLevel.Automatic
    end)

    pcall(function()
        local terrain = Workspace:FindFirstChildOfClass("Terrain")
        if terrain then
            terrain.Decoration = not SETTINGS.BoostFPS
            terrain.WaterWaveSize = SETTINGS.BoostFPS and 0 or 0.15
            terrain.WaterWaveSpeed = SETTINGS.BoostFPS and 0 or 10
            terrain.WaterReflectance = SETTINGS.BoostFPS and 0 or 0.25
        end
    end)

    pcall(function()
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if isEffectInstance(obj) then
                if SETTINGS.BoostFPS then
                    if boostedEffects[obj] == nil then boostedEffects[obj] = obj.Enabled end
                    obj.Enabled = false
                elseif boostedEffects[obj] ~= nil then
                    obj.Enabled = boostedEffects[obj]
                    boostedEffects[obj] = nil
                end
            end
        end
    end)

    if boostFpsConnection then boostFpsConnection:Disconnect(); boostFpsConnection = nil end
    if SETTINGS.BoostFPS then
        boostFpsConnection = Workspace.DescendantAdded:Connect(function(obj)
            if isEffectInstance(obj) then
                if boostedEffects[obj] == nil then boostedEffects[obj] = obj.Enabled end
                obj.Enabled = false
            end
        end)
        table.insert(connections, boostFpsConnection)
    end

    if UI.boostFpsRow then
        UI.boostFpsRow.Text = "Boost FPS: " .. (SETTINGS.BoostFPS and "ON" or "OFF")
        UI.boostFpsRow.BackgroundColor3 = SETTINGS.BoostFPS and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
    end
    if UI.boostFpsQuickBtn then
        UI.boostFpsQuickBtn.BackgroundColor3 = SETTINGS.BoostFPS and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(13, 17, 33)
    end
    setStatus(SETTINGS.BoostFPS and "Status: Boost FPS ON" or "Status: Boost FPS OFF", true)
    if not skipSave then saveConfig() end
end
UI.applyBoostFPS = applyBoostFPS

-- MAX FPS: caps the client framerate via whatever fps-cap function the executor exposes (0 = unlimited)
local function getFpsCapSetter()
    return setfpscap or set_fps_cap or setfpscap_v2 or (fluxus and fluxus.set_fps_cap)
end

local function applyMaxFps(value, skipSave)
    value = tonumber(value) or SETTINGS.MaxFPS
    if value < 0 then value = 0 end
    SETTINGS.MaxFPS = value

    local setter = getFpsCapSetter()
    if setter then
        local ok = pcall(setter, value <= 0 and 9999 or value)
        setStatus(ok and ("Status: Max FPS set to " .. (value <= 0 and "Unlimited" or tostring(value))) or "Max FPS: your executor rejected the fps cap.", true)
    else
        setStatus("Max FPS: your executor has no setfpscap function - cap not changed.", true)
    end

    if UI.maxFpsInput then UI.maxFpsInput.Text = tostring(SETTINGS.MaxFPS) end
    if not skipSave then saveConfig() end
end
UI.applyMaxFps = applyMaxFps

-- LOGO MARK: uses "dungeonmacros/logo.png" (executor workspace) if present, else a bold slanted gradient "N".
local function createLogoMark(parent, zIndex)
    local asset
    pcall(function()
        if getcustomasset and isfile and isfile(FOLDER_NAME .. "/logo.png") then
            asset = getcustomasset(FOLDER_NAME .. "/logo.png")
        end
    end)

    if asset then
        local img = Instance.new("ImageLabel")
        img.Size = UDim2.new(1, 0, 1, 0)
        img.BackgroundTransparency = 1
        img.Image = asset
        img.ScaleType = Enum.ScaleType.Fit
        img.ZIndex = zIndex or 1
        img.Parent = parent
        return img
    end

    -- dark rounded square with a blue -> purple -> pink "NCL"
    local box = Instance.new("Frame")
    box.Size = UDim2.new(1, 0, 1, 0)
    box.BackgroundColor3 = Color3.fromRGB(10, 14, 26)
    box.BorderSizePixel = 0
    box.ZIndex = zIndex or 1
    box.Parent = parent
    local boxCorner = Instance.new("UICorner")
    boxCorner.CornerRadius = UDim.new(0.24, 0)
    boxCorner.Parent = box

    local mark = Instance.new("TextLabel")
    mark.Size = UDim2.new(1, 0, 1, 0)
    mark.BackgroundTransparency = 1
    mark.Name = "NCLLogoText"
    mark.Text = "NCL"
    mark.Font = Enum.Font.GothamBlack
    mark.TextSize = 20
    mark.ZIndex = (zIndex or 1) + 1
    mark.TextColor3 = Color3.fromRGB(255, 255, 255)
    mark.Parent = box
    local function fitText()
        local h = box.AbsoluteSize.Y
        if h > 0 then mark.TextSize = math.clamp(math.floor(h * 0.36), 6, 60) end
    end
    box:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitText)
    fitText()
    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(64, 132, 255)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(160, 90, 245)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(240, 70, 145)),
    })
    gradient.Rotation = 0
    gradient.Parent = mark
    return box
end
UI.createLogoMark = createLogoMark
-- 4. INTERFACE INITIALIZATION

local applyConfigData -- defined in section 5, used by the config import button

local function buildInterface()
-- THEME
local T = {
    bg = Color3.fromRGB(11, 14, 27),
    panel = Color3.fromRGB(16, 20, 38),
    field = Color3.fromRGB(13, 17, 33),
    stroke = Color3.fromRGB(38, 46, 84),
    text = Color3.fromRGB(232, 236, 255),
    muted = Color3.fromRGB(128, 138, 172),
    accent = Color3.fromRGB(72, 92, 235),
    accent2 = Color3.fromRGB(128, 86, 242),
    green = Color3.fromRGB(28, 220, 150),
    orange = Color3.fromRGB(250, 160, 50),
    pink = Color3.fromRGB(240, 45, 100),
    idle = Color3.fromRGB(28, 34, 62),
}
UI.theme = T

local function round(inst, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = inst
    return c
end

local function stroke(inst, color, thickness)
    local s = Instance.new("UIStroke")
    s.Color = color or T.stroke
    s.Thickness = thickness or 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = inst
    return s
end

local function makeText(parent, text, size, color, font, xAlign)
    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.TextSize = size
    lbl.TextColor3 = color
    lbl.Font = font or Enum.Font.Gotham
    lbl.TextXAlignment = xAlign or Enum.TextXAlignment.Left
    lbl.Parent = parent
    return lbl
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "NCL MACRO"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 200
UI.screenGui = screenGui

local targetParent = player:WaitForChild("PlayerGui", 5)
if gethui then
    pcall(function() targetParent = gethui() end)
else
    pcall(function()
        local test = Instance.new("Folder")
        test.Parent = CoreGui
        test:Destroy()
        targetParent = CoreGui
    end)
end
screenGui.Parent = targetParent

local WINDOW_W, WINDOW_H = 900, 540

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, WINDOW_W, 0, WINDOW_H)
mainFrame.AnchorPoint = Vector2.new(0.5, 0)
mainFrame.Position = UDim2.new(0.5, 0, 0.08, 0)
mainFrame.BackgroundColor3 = T.bg
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Draggable = true
mainFrame.ClipsDescendants = true
mainFrame.Parent = screenGui
round(mainFrame, 14)
stroke(mainFrame)

local uiScale = Instance.new("UIScale")
local cam = Workspace.CurrentCamera
local viewport = cam and cam.ViewportSize or Vector2.new(1280, 720)
UI.baseScale = math.clamp(math.min(viewport.X / 940, viewport.Y / 600), 0.45, 1)
uiScale.Scale = UI.baseScale
uiScale.Parent = mainFrame
UI.uiScale = uiScale

-- open animation: the window pops in from slightly smaller
function UI.popIn()
    pcall(function()
        local target = uiScale.Scale
        uiScale.Scale = target * 0.92
        game:GetService("TweenService"):Create(uiScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target }):Play()
    end)
end
UI.popIn()

-- HEADER
local header = Instance.new("Frame")
header.Size = UDim2.new(1, -24, 0, 64)
header.Position = UDim2.new(0, 12, 0, 8)
header.BackgroundColor3 = T.panel
header.BorderSizePixel = 0
header.Parent = mainFrame
round(header, 12)
stroke(header)

-- thin gradient accent line along the bottom of the header
local accentLine = Instance.new("Frame")
accentLine.Size = UDim2.new(1, -28, 0, 2)
accentLine.Position = UDim2.new(0, 14, 1, -2)
accentLine.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
accentLine.BorderSizePixel = 0
accentLine.Parent = header
local accentGrad = Instance.new("UIGradient")
accentGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, T.accent),
    ColorSequenceKeypoint.new(0.5, T.accent2),
    ColorSequenceKeypoint.new(1, T.pink),
})
accentGrad.Parent = accentLine

-- LOGO: uses "dungeonmacros/logo.png" from the executor workspace if it exists,
-- otherwise draws the "N" mark from gradient shapes.
local logo = Instance.new("Frame")
logo.Size = UDim2.new(0, 40, 0, 40)
logo.Position = UDim2.new(0, 12, 0, 12)
logo.BackgroundTransparency = 1
logo.Parent = header

createLogoMark(logo)

local titleLabel = makeText(header, '<font color="#FFFFFF">NCL</font> <font color="#5C86FF">MACRO</font>', 24, T.text, Enum.Font.GothamBlack)
titleLabel.RichText = true
titleLabel.Size = UDim2.new(0, 170, 1, 0)
titleLabel.Position = UDim2.new(0, 60, 0, 0)

local divider = Instance.new("Frame")
divider.Size = UDim2.new(0, 1, 0, 30)
divider.Position = UDim2.new(0, 236, 0, 17)
divider.BackgroundColor3 = T.stroke
divider.BorderSizePixel = 0
divider.Parent = header

UI.stateDot = Instance.new("Frame")
UI.stateDot.Size = UDim2.new(0, 10, 0, 10)
UI.stateDot.Position = UDim2.new(0, 252, 0, 27)
UI.stateDot.BackgroundColor3 = T.muted
UI.stateDot.BorderSizePixel = 0
UI.stateDot.Parent = header
round(UI.stateDot, 5)

UI.stateLabel = makeText(header, "IDLE", 15, T.muted, Enum.Font.GothamBold)
UI.stateLabel.Size = UDim2.new(0, 130, 1, 0)
UI.stateLabel.Position = UDim2.new(0, 272, 0, 0)

local statusLabel = makeText(header, "Status: Idle", 12, T.muted, Enum.Font.Gotham)
statusLabel.Size = UDim2.new(0, 246, 1, 0)
statusLabel.Position = UDim2.new(0, 408, 0, 0)
statusLabel.TextTruncate = Enum.TextTruncate.AtEnd
UI.statusLabel = statusLabel

local function makeWindowButton(x)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 34, 0, 34)
    btn.Position = UDim2.new(0, x, 0, 15)
    btn.BackgroundColor3 = T.field
    btn.Text = ""
    btn.BorderSizePixel = 0
    btn.Parent = header
    round(btn, 8)
    local btnStroke = stroke(btn)
    btn.MouseEnter:Connect(function() btnStroke.Color = T.accent end)
    btn.MouseLeave:Connect(function() btnStroke.Color = T.stroke end)
    return btn
end

local function makeBar(parent, w, h, rot)
    local f = Instance.new("Frame")
    f.AnchorPoint = Vector2.new(0.5, 0.5)
    f.Position = UDim2.new(0.5, 0, 0.5, 0)
    f.Size = UDim2.new(0, w, 0, h)
    f.BackgroundColor3 = T.text
    f.BorderSizePixel = 0
    f.Rotation = rot or 0
    f.Parent = parent
    return f
end

UI.blackScreenQuickBtn = makeWindowButton(664)
UI.blackScreenQuickBtn.Font = Enum.Font.GothamBold
UI.blackScreenQuickBtn.TextSize = 15
UI.blackScreenQuickBtn.TextColor3 = T.text
UI.blackScreenQuickBtn.Text = "🌑"

UI.autoHideQuickBtn = makeWindowButton(622)
UI.autoHideQuickBtn.Font = Enum.Font.GothamBold
UI.autoHideQuickBtn.TextSize = 15
UI.autoHideQuickBtn.TextColor3 = T.text
UI.autoHideQuickBtn.Text = "👁"

UI.boostFpsQuickBtn = makeWindowButton(580)
UI.boostFpsQuickBtn.Font = Enum.Font.GothamBold
UI.boostFpsQuickBtn.TextSize = 12
UI.boostFpsQuickBtn.TextColor3 = T.text
UI.boostFpsQuickBtn.Text = "FPS"
UI.boostFpsQuickBtn.BackgroundColor3 = SETTINGS.BoostFPS and Color3.fromRGB(40, 150, 70) or T.field
statusLabel.Size = UDim2.new(0, 158, 1, 0)

local minimizeBtn = makeWindowButton(706)
makeBar(minimizeBtn, 14, 2)
local maximizeBtn = makeWindowButton(748)
local maxIcon = Instance.new("Frame")
maxIcon.AnchorPoint = Vector2.new(0.5, 0.5)
maxIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
maxIcon.Size = UDim2.new(0, 13, 0, 13)
maxIcon.BackgroundTransparency = 1
maxIcon.Parent = maximizeBtn
stroke(maxIcon, T.text, 2)
local closeBtn = makeWindowButton(790)
makeBar(closeBtn, 17, 2, 45)
makeBar(closeBtn, 17, 2, -45)

-- BODY (everything under the header; hidden when minimized)
local body = Instance.new("Frame")
body.Size = UDim2.new(1, 0, 1, 0)
body.BackgroundTransparency = 1
body.Parent = mainFrame

-- COMPONENT HELPERS
local function MakeButton(text, color, parent)
    local btn = Instance.new("TextButton")
    btn.Text = text
    btn.Size = UDim2.new(1, 0, 0, 34)
    btn.BackgroundColor3 = color
    btn.TextColor3 = T.text
    btn.Font = Enum.Font.GothamSemibold
    btn.TextSize = 13
    btn.BorderSizePixel = 0
    btn.Parent = parent
    round(btn, 8)
    local g = Instance.new("UIGradient")
    g.Rotation = 90
    g.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(205, 208, 226))
    g.Parent = btn
    -- hover / press feedback via the gradient, so it never fights the ON/OFF colors set elsewhere
    local function shade(bottom, speed)
        pcall(function()
            game:GetService("TweenService"):Create(g, TweenInfo.new(speed or 0.12), { Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), bottom) }):Play()
        end)
    end
    btn.AutoButtonColor = false
    btn.MouseEnter:Connect(function() shade(Color3.fromRGB(245, 246, 255)) end)
    btn.MouseLeave:Connect(function() shade(Color3.fromRGB(205, 208, 226)) end)
    btn.MouseButton1Down:Connect(function() shade(Color3.fromRGB(150, 154, 180), 0.06) end)
    btn.MouseButton1Up:Connect(function() shade(Color3.fromRGB(245, 246, 255), 0.1) end)
    return btn
end

-- ON/OFF toggle row: a MakeButton with a small LED dot + colored glow outline that stays in sync automatically
-- whenever the button's BackgroundColor3 is set (every toggle handler already does this), so no other code
-- anywhere in the script needs to change - existing "row.Text = ..." / "row.BackgroundColor3 = ..." keeps working.
local TOGGLE_ON_COLOR = Color3.fromRGB(40, 150, 70)
local function MakeToggle(text, isOn, parent)
    local btn = MakeButton(text, isOn and TOGGLE_ON_COLOR or T.idle, parent)

    local led = Instance.new("Frame")
    led.Name = "ToggleLED"
    led.AnchorPoint = Vector2.new(1, 0.5)
    led.Position = UDim2.new(1, -12, 0.5, 0)
    led.Size = UDim2.new(0, 8, 0, 8)
    led.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    led.BorderSizePixel = 0
    led.ZIndex = 3
    led.Parent = btn
    round(led, 4)
    local ledGlow = Instance.new("UIStroke")
    ledGlow.Color = Color3.fromRGB(255, 255, 255)
    ledGlow.Thickness = 1
    ledGlow.Transparency = 0.5
    ledGlow.Parent = led

    local edge = stroke(btn, T.stroke, 1)

    local function sync()
        local on = btn.BackgroundColor3 == TOGGLE_ON_COLOR
        led.BackgroundColor3 = on and Color3.fromRGB(220, 255, 235) or Color3.fromRGB(120, 128, 150)
        edge.Color = on and Color3.fromRGB(70, 220, 140) or T.stroke
        edge.Transparency = on and 0.35 or 0.6
        pcall(function()
            game:GetService("TweenService"):Create(led, TweenInfo.new(0.15), {
                Size = on and UDim2.new(0, 9, 0, 9) or UDim2.new(0, 7, 0, 7)
            }):Play()
        end)
    end
    sync()
    btn:GetPropertyChangedSignal("BackgroundColor3"):Connect(sync)
    return btn
end

local function MakeInput(placeholder, parent)
    local box = Instance.new("TextBox")
    box.PlaceholderText = placeholder
    box.PlaceholderColor3 = T.muted
    box.Size = UDim2.new(1, 0, 0, 36)
    box.BackgroundColor3 = T.field
    box.TextColor3 = T.text
    box.Font = Enum.Font.Gotham
    box.TextSize = 13
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.Text = ""
    box.ClearTextOnFocus = false
    box.BorderSizePixel = 0
    box.Parent = parent
    round(box, 8)
    local boxStroke = stroke(box)
    box.Focused:Connect(function() boxStroke.Color = T.accent; boxStroke.Thickness = 1.5 end)
    box.FocusLost:Connect(function() boxStroke.Color = T.stroke; boxStroke.Thickness = 1 end)
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 12)
    pad.PaddingRight = UDim.new(0, 12)
    pad.Parent = box
    return box
end

local function MakeRow(parent, height)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, height or 38)
    row.BackgroundTransparency = 1
    row.Parent = parent
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.Padding = UDim.new(0, 8)
    layout.Parent = row
    return row
end

-- width helper for items inside a MakeRow: fraction of the row minus its share of the gaps
local function rowSize(fraction, count)
    return UDim2.new(fraction, -(count - 1) * 8 * fraction, 1, 0)
end

local function MakeSectionLabel(text, parent)
    local lbl = makeText(parent, text:upper(), 11, T.muted, Enum.Font.GothamBold)
    lbl.Size = UDim2.new(1, 0, 0, 18)
    return lbl
end

local function MakeSettingRow(labelText, defaultVal, parent)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, 36)
    frame.BackgroundTransparency = 1
    frame.Parent = parent

    local lbl = makeText(frame, labelText, 13, T.text, Enum.Font.GothamSemibold)
    lbl.Size = UDim2.new(0.58, 0, 1, 0)

    local box = Instance.new("TextBox")
    box.Size = UDim2.new(0.42, 0, 1, 0)
    box.Position = UDim2.new(0.58, 0, 0, 0)
    box.BackgroundColor3 = T.field
    box.TextColor3 = T.green
    box.PlaceholderColor3 = T.muted
    box.Font = Enum.Font.GothamBold
    box.TextSize = 13
    box.Text = tostring(defaultVal)
    box.BorderSizePixel = 0
    box.Parent = frame
    round(box, 8)
    local boxStroke = stroke(box)
    box.Focused:Connect(function() boxStroke.Color = T.accent; boxStroke.Thickness = 1.5 end)
    box.FocusLost:Connect(function() boxStroke.Color = T.stroke; boxStroke.Thickness = 1 end)
    return box
end

local function MakeDropdownRow(labelText, getOptionsFunc, defaultVal, parent, callback)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, 36)
    frame.BackgroundTransparency = 1
    frame.Parent = parent

    local lbl = makeText(frame, labelText, 13, T.text, Enum.Font.GothamSemibold)
    lbl.Size = UDim2.new(0.5, 0, 1, 0)

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0.5, 0, 1, 0)
    btn.Position = UDim2.new(0.5, 0, 0, 0)
    btn.BackgroundColor3 = T.field
    btn.TextColor3 = T.green
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 12
    btn.Text = tostring(defaultVal) .. " ▼"
    btn.BorderSizePixel = 0
    btn.Parent = frame
    round(btn, 8)
    stroke(btn)

    local dropdownContainer = Instance.new("Frame")
    dropdownContainer.Size = UDim2.new(1, 0, 0, 0)
    dropdownContainer.BackgroundTransparency = 1
    dropdownContainer.ClipsDescendants = true
    dropdownContainer.Visible = false
    dropdownContainer.Parent = parent

    local listLayout = Instance.new("UIListLayout")
    listLayout.Parent = dropdownContainer
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Padding = UDim.new(0, 2)

    local currentVal = defaultVal

    local function closeDropdown()
        dropdownContainer.Visible = false
        dropdownContainer.Size = UDim2.new(1, 0, 0, 0)
        btn.Text = tostring(currentVal) .. " ▼"
    end

    btn.MouseButton1Click:Connect(function()
        if dropdownContainer.Visible then
            closeDropdown()
        else
            for _, child in ipairs(dropdownContainer:GetChildren()) do
                if child:IsA("TextButton") then child:Destroy() end
            end
            local opts = getOptionsFunc()
            local height = 0
            for _, opt in ipairs(opts) do
                local optBtn = Instance.new("TextButton")
                optBtn.Size = UDim2.new(1, 0, 0, 26)
                optBtn.BackgroundColor3 = T.idle
                optBtn.TextColor3 = T.text
                optBtn.Font = Enum.Font.Gotham
                optBtn.TextSize = 12
                optBtn.Text = tostring(opt)
                optBtn.BorderSizePixel = 0
                optBtn.Parent = dropdownContainer
                round(optBtn, 6)

                optBtn.MouseButton1Click:Connect(function()
                    currentVal = opt
                    callback(opt)
                    closeDropdown()
                end)
                height = height + 28
            end
            dropdownContainer.Size = UDim2.new(1, 0, 0, height)
            dropdownContainer.Visible = true
            btn.Text = tostring(currentVal) .. " ▲"
        end
    end)

    local api = {}
    function api:SetValue(val)
        currentVal = val
        btn.Text = tostring(val) .. " ▼"
    end
    return api
end

local function getAvailableDifficulties()
    local diffs = {}
    pcall(function()
        local rightFill = findNested(player, "PlayerGui", "queueGui", "chooseDungeon", "backgroundFillRight")
        if rightFill then
            for _, child in ipairs(rightFill:GetChildren()) do
                if child:IsA("ImageLabel") then table.insert(diffs, child.Name) end
            end
        end
    end)
    if #diffs == 0 then return {"Easy", "Normal", "Hard", "Nightmare"} end
    return diffs
end

-- PAGES
local PAGE_W, PAGE_H = 620, 334
local RIGHT_COL_X = PAGE_W + 24

local function createPage(title, subtitle)
    local page = Instance.new("ScrollingFrame")
    page.Size = UDim2.new(0, PAGE_W, 0, PAGE_H)
    page.Position = UDim2.new(0, 12, 0, 140)
    page.BackgroundColor3 = T.panel
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 4
    page.ScrollBarImageColor3 = T.accent
    page.CanvasSize = UDim2.new(0, 0, 0, 0)
    page.Visible = false
    page.Parent = body
    round(page, 12)
    stroke(page)

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 14)
    pad.PaddingBottom = UDim.new(0, 14)
    pad.PaddingLeft = UDim.new(0, 16)
    pad.PaddingRight = UDim.new(0, 18)
    pad.Parent = page

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 10)
    layout.Parent = page
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        page.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 28)
    end)

    local head = Instance.new("Frame")
    head.Size = UDim2.new(1, 0, 0, 42)
    head.BackgroundTransparency = 1
    head.Parent = page
    local titleText = makeText(head, title, 19, T.text, Enum.Font.GothamBold)
    titleText.Size = UDim2.new(1, 0, 0, 24)
    local subText = makeText(head, subtitle, 12, T.muted, Enum.Font.Gotham)
    subText.Size = UDim2.new(1, 0, 0, 16)
    subText.Position = UDim2.new(0, 0, 0, 25)
    return page
end

local macroPage = createPage("Macro", "Manage your macro settings and configuration.")
local webhookPage = createPage("Webhook", "Send a summary to Discord after every match.")
local sellPage = createPage("Auto Sell", "Choose which rarities get sold automatically.")
local settingsPage = createPage("Setting", "Combat, movement and timing options.")
local tradePage = createPage("Auto Trade", "Send and accept trades automatically.")
local buildPage = createPage("Build", "Instantly spend all your free skill points.")
local miscPage = createPage("Misc", "Lobby routine, gameplay mode and extras.")
local joinPage = createPage("Auto Join", "Join a host's lobby and leave when they leave.")

-- TABS (horizontally scrollable: drag/swipe left-right when there are more tabs than fit)
local tabBar = Instance.new("ScrollingFrame")
tabBar.Size = UDim2.new(0, PAGE_W, 0, 46)
tabBar.Position = UDim2.new(0, 12, 0, 84)
tabBar.BackgroundColor3 = T.panel
tabBar.BorderSizePixel = 0
tabBar.ScrollingDirection = Enum.ScrollingDirection.X
tabBar.ScrollBarThickness = 3
tabBar.ScrollBarImageColor3 = T.accent2
tabBar.ScrollBarImageTransparency = 0.4
tabBar.CanvasSize = UDim2.new(0, 0, 0, 0)
tabBar.AutomaticCanvasSize = Enum.AutomaticSize.X
tabBar.Parent = body
round(tabBar, 12)
stroke(tabBar)

local tabPad = Instance.new("UIPadding")
tabPad.PaddingTop = UDim.new(0, 4)
tabPad.PaddingBottom = UDim.new(0, 4)
tabPad.PaddingLeft = UDim.new(0, 4)
tabPad.PaddingRight = UDim.new(0, 4)
tabPad.Parent = tabBar

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 4)
tabLayout.Parent = tabBar

local tabs = {}

local function switchTab(index)
    for i, t in ipairs(tabs) do
        local active = (i == index)
        t.page.Visible = active
        t.btn.BackgroundTransparency = active and 0 or 1
        t.btn.TextColor3 = active and T.text or T.muted
        t.bar.Visible = active
    end
    if UI.macroScroll then UI.macroScroll.Visible = false end
end

local function createTab(text, page)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 116, 1, 0)
    btn.BackgroundColor3 = T.accent
    btn.BackgroundTransparency = 1
    btn.Text = text
    btn.TextColor3 = T.muted
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 13
    btn.BorderSizePixel = 0
    btn.TextSize = 12
    btn.Parent = tabBar
    round(btn, 9)
    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(0.55, 0, 0, 3)
    bar.Position = UDim2.new(0.225, 0, 1, -4)
    bar.BackgroundColor3 = T.accent2
    bar.BorderSizePixel = 0
    bar.Visible = false
    bar.Parent = btn
    round(bar, 2)
    table.insert(tabs, { btn = btn, page = page, bar = bar })
    local index = #tabs
    btn.MouseButton1Click:Connect(function() switchTab(index) end)
    -- hover highlight for inactive tabs
    btn.MouseEnter:Connect(function()
        if not bar.Visible then btn.TextColor3 = T.text; btn.BackgroundTransparency = 0.85 end
    end)
    btn.MouseLeave:Connect(function()
        if not bar.Visible then btn.TextColor3 = T.muted; btn.BackgroundTransparency = 1 end
    end)
end

createTab("Macro", macroPage)
createTab("Webhook", webhookPage)
createTab("Auto Sell", sellPage)
createTab("Setting", settingsPage)
createTab("Auto Trade", tradePage)
createTab("Auto Join", joinPage)
createTab("Build", buildPage)
createTab("Misc", miscPage)

-- MACRO TAB
local macroRowA = MakeRow(macroPage, 40)
local recordBtn = MakeButton("▶  Start Recording", T.accent, macroRowA)
recordBtn.Size = rowSize(0.3, 4)
local stopRecordBtn = MakeButton("■  Stop Recording", T.idle, macroRowA)
stopRecordBtn.Size = rowSize(0.3, 4)
local clearWaypointsBtn = MakeButton("Clear Nodes", T.idle, macroRowA)
clearWaypointsBtn.Size = rowSize(0.2, 4)
local addWaypointBtn = MakeButton("+ Node", T.idle, macroRowA)
addWaypointBtn.Size = rowSize(0.2, 4)

MakeSectionLabel("Saved Macros", macroPage)

local macroRowB = MakeRow(macroPage, 38)
UI.macroDropBtn = Instance.new("TextButton")
UI.macroDropBtn.Size = rowSize(0.6, 3)
UI.macroDropBtn.BackgroundColor3 = T.field
UI.macroDropBtn.TextColor3 = T.muted
UI.macroDropBtn.Font = Enum.Font.Gotham
UI.macroDropBtn.TextSize = 13
UI.macroDropBtn.TextXAlignment = Enum.TextXAlignment.Left
UI.macroDropBtn.Text = "  Select a macro...   ▼"
UI.macroDropBtn.BorderSizePixel = 0
UI.macroDropBtn.Parent = macroRowB
round(UI.macroDropBtn, 8)
stroke(UI.macroDropBtn)
local exportBtn = MakeButton("Export", Color3.fromRGB(60, 52, 170), macroRowB)
exportBtn.Size = rowSize(0.2, 3)
local importBtn = MakeButton("Import", T.idle, macroRowB)
importBtn.Size = rowSize(0.2, 3)

local macroRowC = MakeRow(macroPage, 38)
local nameInput = MakeInput("Macro name (e.g. Run1)", macroRowC)
nameInput.Size = rowSize(0.6, 3)
local saveBtn = MakeButton("Save", Color3.fromRGB(34, 160, 100), macroRowC)
saveBtn.Size = rowSize(0.2, 3)
local deleteBtn = MakeButton("Delete", Color3.fromRGB(190, 48, 80), macroRowC)
deleteBtn.Size = rowSize(0.2, 3)

local importInput = MakeInput("Paste JSON to import...", macroPage)
importInput.Size = UDim2.new(1, 0, 0, 38)

-- floating macro list (opened by the dropdown button, lives above everything)
local macroScroll = Instance.new("ScrollingFrame")
macroScroll.Size = UDim2.new(0, 340, 0, 130)
macroScroll.BackgroundColor3 = T.field
macroScroll.BorderSizePixel = 0
macroScroll.ScrollBarThickness = 4
macroScroll.ScrollBarImageColor3 = T.accent
macroScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
macroScroll.ZIndex = 50
macroScroll.Visible = false
macroScroll.Parent = mainFrame
round(macroScroll, 8)
stroke(macroScroll, T.accent)
local macroScrollPad = Instance.new("UIPadding")
macroScrollPad.PaddingTop = UDim.new(0, 4)
macroScrollPad.PaddingLeft = UDim.new(0, 4)
macroScrollPad.PaddingRight = UDim.new(0, 4)
macroScrollPad.Parent = macroScroll
local UIListLayoutList = Instance.new("UIListLayout")
UIListLayoutList.Parent = macroScroll
UIListLayoutList.Padding = UDim.new(0, 2)
UI.macroScroll = macroScroll

UI.macroDropBtn.MouseButton1Click:Connect(function()
    if macroScroll.Visible then
        macroScroll.Visible = false
        return
    end
    refreshMacroList()
    local scale = uiScale.Scale
    local pos = UI.macroDropBtn.AbsolutePosition - mainFrame.AbsolutePosition
    local size = UI.macroDropBtn.AbsoluteSize
    macroScroll.Position = UDim2.new(0, pos.X / scale, 0, (pos.Y + size.Y) / scale + 4)
    macroScroll.Size = UDim2.new(0, size.X / scale, 0, 130)
    macroScroll.Visible = true
end)

-- WEBHOOK TAB
MakeSectionLabel("Webhook URL", webhookPage)
UI.webhookInput = MakeInput("Paste Webhook URL...", webhookPage)
UI.webhookInput.Text = SETTINGS.Webhook or ""
local webhookTestBtn = MakeButton("Send Test Message", T.accent, webhookPage)
webhookTestBtn.MouseButton1Click:Connect(function()
    SETTINGS.Webhook = UI.webhookInput.Text
    saveConfig()
    UI.sendTestWebhook(SETTINGS.Webhook)
end)
UI.webhookResult = makeText(webhookPage, "Result: nothing sent yet.", 12, T.muted, Enum.Font.Gotham)
UI.webhookResult.Size = UDim2.new(1, 0, 0, 44)
UI.webhookResult.TextWrapped = true
UI.webhookResult.TextYAlignment = Enum.TextYAlignment.Top
local webhookNote = makeText(webhookPage, "After each match a message with the run time, gold and items received is posted to this URL.", 12, T.muted, Enum.Font.Gotham)
webhookNote.Size = UDim2.new(1, 0, 0, 34)
webhookNote.TextWrapped = true
webhookNote.TextYAlignment = Enum.TextYAlignment.Top

-- SETTING TAB
UI.minDistInput = MakeSettingRow("Min Combat Dist (Run Away):", SETTINGS.MinDistance, settingsPage)
UI.maxDistInput = MakeSettingRow("Max Combat Dist (Kite):", SETTINGS.MaxDistance, settingsPage)
UI.atkReachInput = MakeSettingRow("Attack Reach (Max Fire Dist):", SETTINGS.AttackReach, settingsPage)

-- RANGE CIRCLES: rings on the ground around you (red = Min run-away, yellow = Max kite, green = Attack reach)
UI.rangeCircleRow = MakeToggle("Show Range Circle: " .. (SETTINGS.ShowRangeCircle and "ON" or "OFF"), SETTINGS.ShowRangeCircle, settingsPage)
UI.rangeCircleRow.MouseButton1Click:Connect(function()
    SETTINGS.ShowRangeCircle = not SETTINGS.ShowRangeCircle
    UI.rangeCircleRow.Text = "Show Range Circle: " .. (SETTINGS.ShowRangeCircle and "ON" or "OFF")
    UI.rangeCircleRow.BackgroundColor3 = SETTINGS.ShowRangeCircle and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
    saveConfig()
end)

local function destroyRangeRings()
    if UI.rangeRings then
        for _, ring in pairs(UI.rangeRings) do pcall(function() ring:Destroy() end) end
        UI.rangeRings = nil
    end
end
UI.destroyRangeRings = destroyRangeRings

task.spawn(function()
    local ringDefs = {
        { key = "MinDistance", color = Color3.fromRGB(255, 70, 70) },
        { key = "MaxDistance", color = Color3.fromRGB(255, 220, 60) },
        { key = "AttackReach", color = Color3.fromRGB(70, 255, 130) },
    }
    while not isCleaningUp do
        if SETTINGS.ShowRangeCircle and rootPart and rootPart.Parent and not isInLobby() then
            if UI.rangeRings and UI.rangeRings[1] and UI.rangeRings[1].Adornee ~= rootPart then destroyRangeRings() end
            if not UI.rangeRings then
                UI.rangeRings = {}
                for i, def in ipairs(ringDefs) do
                    local ring = Instance.new("CylinderHandleAdornment")
                    ring.Name = "NCLRangeRing"
                    ring.Adornee = rootPart
                    ring.Height = 0.2
                    ring.Color3 = def.color
                    ring.Transparency = 0.25
                    ring.AlwaysOnTop = true
                    ring.ZIndex = i
                    ring.CFrame = CFrame.new(0, -2.9, 0) * CFrame.Angles(math.rad(90), 0, 0)
                    ring.Parent = Workspace
                    UI.rangeRings[i] = ring
                end
            end
            for i, def in ipairs(ringDefs) do
                local radius = math.max(tonumber(SETTINGS[def.key]) or 0, 1)
                UI.rangeRings[i].Radius = radius
                UI.rangeRings[i].InnerRadius = math.max(radius - 0.35, 0)
            end
        else
            destroyRangeRings()
        end
        task.wait(0.2)
    end
    destroyRangeRings()
end)

UI.customTargetInput = MakeSettingRow("Bonus Target Name:", SETTINGS.CustomTargetName, settingsPage)
UI.customTargetInput.PlaceholderText = "e.g. Elderbark Tree"

UI.customRangeInput = MakeSettingRow("Bonus Reach (Added):", SETTINGS.CustomTargetExtraRange, settingsPage)
UI.customRangeInput.PlaceholderText = "e.g. 20"

UI.ignoreEnemyInput = MakeSettingRow("Ignore Enemy Names:", SETTINGS.IgnoreEnemyNames, settingsPage)
UI.ignoreEnemyInput.PlaceholderText = "e.g. Energy Spirit, Slime"

UI.atkDelayInput = MakeSettingRow("Attack Cooldown (Sec):", SETTINGS.AttackCooldown, settingsPage)
UI.dodgeBufferInput = MakeSettingRow("Dodge Buffer (Margin):", SETTINGS.DodgeBuffer, settingsPage)
UI.wpTriggerInput = MakeSettingRow("Waypoint Trigger Distance:", SETTINGS.WaypointTriggerDist, settingsPage)
UI.maxNodeDistInput = MakeSettingRow("Max Next Node Dist (Abort):", SETTINGS.MaxNodeDistance, settingsPage)
UI.wallRayInput = MakeSettingRow("Wall Ray Length (Gliding):", SETTINGS.WallRayLength, settingsPage)
UI.noEnemyDelayInput = MakeSettingRow("No Enemy Replay Delay (s):", SETTINGS.NoEnemyDelay, settingsPage)

UI.replayTimeInput = MakeSettingRow("Replay Time (MM:SS):", SETTINGS.ReplayTime, settingsPage)
UI.replayTimeInput.PlaceholderText = "e.g. 06:52"

MakeSectionLabel("Hazard filter keywords", settingsPage)
UI.filterInput = MakeInput("e.g. ring1, ring2, safezone", settingsPage)

-- CONFIG IMPORT / EXPORT UI
MakeSectionLabel("Config", settingsPage)
local configExportBtn = MakeButton("Export Config to Clipboard", Color3.fromRGB(60, 52, 170), settingsPage)

local configImportRow = MakeRow(settingsPage, 38)
local configImportInput = MakeInput("Paste Config JSON to Import...", configImportRow)
configImportInput.Size = rowSize(0.68, 2)
local configImportBtn = MakeButton("Import", T.accent, configImportRow)
configImportBtn.Size = rowSize(0.32, 2)

configExportBtn.MouseButton1Click:Connect(function()
    local cfgData = buildConfigTable()
    local success, encoded = pcall(function() return HttpService:JSONEncode(cfgData) end)
    if success and encoded then
        setClipboard(encoded)
        setStatus("Config copied to clipboard!")
    else
        setStatus("Failed to encode config!")
    end
end)

configImportBtn.MouseButton1Click:Connect(function()
    local text = configImportInput.Text
    if text == "" then setStatus("Paste JSON config first!"); return end
    local success, decoded = pcall(function() return HttpService:JSONDecode(text) end)
    if success and type(decoded) == "table" then
        applyConfigData(decoded)
        saveConfig()
        configImportInput.Text = ""
        setStatus("Config imported and saved successfully!")
    else
        setStatus("Invalid JSON Config Data!")
    end
end)

-- MISC TAB
MakeSectionLabel("Custom username (changes live)", miscPage).LayoutOrder = 100
local nameRow = MakeRow(miscPage, 38)
nameRow.LayoutOrder = 101
UI.customNameInput = MakeInput("Type a name...", nameRow)
UI.customNameInput.Text = SETTINGS.CustomName or ""
UI.customNameInput.Size = rowSize(0.68, 2)
local applyNameBtn = MakeButton("Apply Name", T.accent, nameRow)
applyNameBtn.Size = rowSize(0.32, 2)
UI.partyNameRow = MakeToggle("Rename Party Too: " .. (SETTINGS.RenameParty and "ON" or "OFF"), SETTINGS.RenameParty, miscPage)
UI.partyNameRow.LayoutOrder = 102
applyNameBtn.MouseButton1Click:Connect(function() UI.applyCustomName(UI.customNameInput.Text) end)
UI.customNameInput.FocusLost:Connect(function(enter) if enter then UI.applyCustomName(UI.customNameInput.Text) end end)
UI.partyNameRow.MouseButton1Click:Connect(function()
    SETTINGS.RenameParty = not SETTINGS.RenameParty
    UI.partyNameRow.Text = "Rename Party Too: " .. (SETTINGS.RenameParty and "ON" or "OFF")
    UI.partyNameRow.BackgroundColor3 = SETTINGS.RenameParty and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
    UI.refreshNames()
    saveConfig()
end)


MakeSectionLabel("Auto send trade", tradePage)
local tradeRow = MakeRow(tradePage, 40)
UI.tradeNameInput = MakeInput("Usernames (commas, spaces or new lines - no limit)...", tradeRow)
UI.tradeNameInput.MultiLine = true
UI.tradeNameInput.TextWrapped = true
UI.tradeNameInput.TextYAlignment = Enum.TextYAlignment.Top
UI.tradeNameInput.ClipsDescendants = true
UI.tradeNameInput.Text = SETTINGS.TradeUsername or ""
UI.tradeNameInput.Size = rowSize(0.68, 2)
local tradeNowBtn = MakeButton("Send Now", T.accent, tradeRow)
tradeNowBtn.Size = rowSize(0.32, 2)
UI.autoTradeRow = MakeToggle("Auto Send Trade: " .. (SETTINGS.AutoTrade and "ON" or "OFF"), SETTINGS.AutoTrade, tradePage)
UI.tradeStatus = makeText(tradePage, "Trade: idle", 12, T.muted, Enum.Font.Gotham)
UI.tradeStatus.Size = UDim2.new(1, 0, 0, 30)
UI.tradeStatus.TextWrapped = true
UI.tradeStatus.TextYAlignment = Enum.TextYAlignment.Top
UI.tradeNameInput.FocusLost:Connect(function()
    if isCleaningUp then return end
    SETTINGS.TradeUsername = UI.tradeNameInput.Text:match("^%s*(.-)%s*$")
    saveConfig()
end)
tradeNowBtn.MouseButton1Click:Connect(function()
    SETTINGS.TradeUsername = UI.tradeNameInput.Text:match("^%s*(.-)%s*$")
    saveConfig()
    task.spawn(function() UI.tradeStatus.Text = "Trade: " .. tostring(UI.sendTradeNow()) end)
end)
UI.autoTradeRow.MouseButton1Click:Connect(function()
    SETTINGS.AutoTrade = not SETTINGS.AutoTrade
    SETTINGS.TradeUsername = UI.tradeNameInput.Text:match("^%s*(.-)%s*$")
    UI.autoTradeRow.Text = "Auto Send Trade: " .. (SETTINGS.AutoTrade and "ON" or "OFF")
    UI.autoTradeRow.BackgroundColor3 = SETTINGS.AutoTrade and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
    saveConfig()
end)

MakeSectionLabel("Auto accept trade (only these users)", tradePage)
UI.acceptNameInput = MakeInput("Usernames to accept (commas, spaces or new lines)...", tradePage)
UI.acceptNameInput.Size = UDim2.new(1, 0, 0, 40)
UI.acceptNameInput.MultiLine = true
UI.acceptNameInput.TextWrapped = true
UI.acceptNameInput.TextYAlignment = Enum.TextYAlignment.Top
UI.acceptNameInput.ClipsDescendants = true
UI.acceptNameInput.Text = SETTINGS.AcceptUsername or ""
UI.acceptNameInput.FocusLost:Connect(function()
    if isCleaningUp then return end
    SETTINGS.AcceptUsername = UI.acceptNameInput.Text:match("^%s*(.-)%s*$")
    saveConfig()
end)
UI.autoAcceptRow = MakeToggle("Auto Accept Trade: " .. (SETTINGS.AutoAcceptTrade and "ON" or "OFF"), SETTINGS.AutoAcceptTrade, tradePage)
UI.requireGoldRow = MakeToggle("Skip Trade if Gold is 0: " .. (SETTINGS.AutoAcceptRequireGold and "ON" or "OFF"), SETTINGS.AutoAcceptRequireGold, tradePage)
UI.requireGoldRow.MouseButton1Click:Connect(function()
    SETTINGS.AutoAcceptRequireGold = not SETTINGS.AutoAcceptRequireGold
    UI.requireGoldRow.Text = "Skip Trade if Gold is 0: " .. (SETTINGS.AutoAcceptRequireGold and "ON" or "OFF")
    UI.requireGoldRow.BackgroundColor3 = SETTINGS.AutoAcceptRequireGold and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
    saveConfig()
end)
UI.acceptStatus = makeText(tradePage, "Accept: waiting for a trade request", 12, T.muted, Enum.Font.Gotham)
UI.acceptStatus.Size = UDim2.new(1, 0, 0, 30)
UI.acceptStatus.TextWrapped = true
UI.acceptStatus.TextYAlignment = Enum.TextYAlignment.Top
UI.autoAcceptRow.MouseButton1Click:Connect(function()
    SETTINGS.AutoAcceptTrade = not SETTINGS.AutoAcceptTrade
    UI.autoAcceptRow.Text = "Auto Accept Trade: " .. (SETTINGS.AutoAcceptTrade and "ON" or "OFF")
    UI.autoAcceptRow.BackgroundColor3 = SETTINGS.AutoAcceptTrade and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
    saveConfig()
end)

MakeSectionLabel("Instant build (open the Skills tab once first)", buildPage)
for _, b in ipairs({
    { "Warrior Build  -  all Physical Power", Color3.fromRGB(190, 60, 70), "Physical Power", "Warrior Build" },
    { "Mage Build  -  all Spell Power", Color3.fromRGB(120, 70, 210), "Spell Power", "Mage Build" },
    { "Guardian Build  -  all Stamina", Color3.fromRGB(40, 150, 90), "Stamina", "Guardian Build" },
}) do
    local buildBtn = MakeButton(b[1], b[2], buildPage)
    buildBtn.MouseButton1Click:Connect(function() UI.applyBuild(b[3], b[4]) end)
end
MakeSectionLabel("Reset stats (refunds all spent points)", buildPage)
local resetBtn = MakeButton("Reset Stats", Color3.fromRGB(200, 90, 60), buildPage)
resetBtn.MouseButton1Click:Connect(function() UI.resetStats() end)
UI.buildStatus = makeText(buildPage, "Build: idle", 12, T.muted, Enum.Font.Gotham)
UI.buildStatus.Size = UDim2.new(1, 0, 0, 30)
UI.buildStatus.TextWrapped = true
UI.buildStatus.TextYAlignment = Enum.TextYAlignment.Top

UI.blackScreenRow = MakeToggle("Black Screen (RightCtrl): OFF", false, miscPage)
UI.blackScreenRow.LayoutOrder = 103
UI.autoHideRow = MakeToggle("Auto Hide UI: " .. (SETTINGS.AutoHideUI and "ON" or "OFF"), SETTINGS.AutoHideUI, miscPage)
UI.autoHideRow.LayoutOrder = 104
UI.boostFpsRow = MakeToggle("Boost FPS: " .. (SETTINGS.BoostFPS and "ON" or "OFF"), SETTINGS.BoostFPS, miscPage)
UI.boostFpsRow.LayoutOrder = 105
UI.maxFpsInput = MakeSettingRow("Max FPS (0 = unlimited):", SETTINGS.MaxFPS, miscPage)
UI.maxFpsInput.Parent.LayoutOrder = 106
UI.autoLobbyRow = MakeToggle("Auto Lobby Routine: " .. (SETTINGS.AutoLobbyEnabled and "ON" or "OFF"), SETTINGS.AutoLobbyEnabled, miscPage)
UI.followHostRow = MakeToggle("Follow Host: " .. (SETTINGS.FollowHost and "ON" or "OFF"), SETTINGS.FollowHost, joinPage)
UI.followHostRow.MouseButton1Click:Connect(function()
    SETTINGS.FollowHost = not SETTINGS.FollowHost
    UI.followHostRow.Text = "Follow Host: " .. (SETTINGS.FollowHost and "ON" or "OFF")
    UI.followHostRow.BackgroundColor3 = SETTINGS.FollowHost and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
    UI.hostSeen, UI.hostMissingSince = false, nil
    saveConfig()
end)
local followNote = makeText(joinPage, "ON: joins the host typed below (sends a join request) and leaves the game when the host leaves.", 12, T.muted, Enum.Font.Gotham)
followNote.Size = UDim2.new(1, 0, 0, 30)
followNote.TextWrapped = true
followNote.TextYAlignment = Enum.TextYAlignment.Top
UI.roleRow = MakeButton("Lobby Role: " .. SETTINGS.LobbyMode:upper(), Color3.fromRGB(58, 80, 200), joinPage)

UI.joinNameInput = MakeSettingRow("Join Player Name:", SETTINGS.JoinPlayerName, joinPage)
UI.joinNameInput.PlaceholderText = "Friend's Username..."
UI.partySizeInput = MakeSettingRow("Required Party Size (0 for solo):", SETTINGS.TargetPartySize, joinPage)

UI.autoCreateLobbyRow = MakeToggle("Auto Create Lobby: " .. (SETTINGS.AutoCreateLobby and "ON" or "OFF"), SETTINGS.AutoCreateLobby, joinPage)
UI.autoCreateLobbyRow.MouseButton1Click:Connect(function()
    SETTINGS.AutoCreateLobby = not SETTINGS.AutoCreateLobby
    UI.autoCreateLobbyRow.Text = "Auto Create Lobby: " .. (SETTINGS.AutoCreateLobby and "ON" or "OFF")
    UI.autoCreateLobbyRow.BackgroundColor3 = SETTINGS.AutoCreateLobby and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
    saveConfig()
end)
local autoCreateNote = makeText(joinPage, "ON (Host role): creates a lobby with the Difficulty below, then auto-starts it.", 12, T.muted, Enum.Font.Gotham)
autoCreateNote.Size = UDim2.new(1, 0, 0, 30)
autoCreateNote.TextWrapped = true
autoCreateNote.TextYAlignment = Enum.TextYAlignment.Top

UI.diffDropdown = MakeDropdownRow("Difficulty:", getAvailableDifficulties, SETTINGS.LobbyDifficulty, joinPage, function(val)
    SETTINGS.LobbyDifficulty = val
    saveConfig()
end)

UI.waitForPlayersRow = MakeToggle("Wait for Party in Dungeon: " .. (SETTINGS.WaitForPlayers and "ON" or "OFF"), SETTINGS.WaitForPlayers, joinPage)
UI.hcRow = MakeToggle("Hardcore Mode: OFF", false, joinPage)
UI.privRow = MakeToggle("Private Lobby: OFF", false, joinPage)
UI.modeRow = MakeButton("Gameplay Mode: " .. SETTINGS.GameplayMode, Color3.fromRGB(58, 80, 200), miscPage)
UI.autoDodgeRow = MakeToggle("Auto Dodging: " .. (SETTINGS.AutoDodgeEnabled and "ON" or "OFF"), SETTINGS.AutoDodgeEnabled, miscPage)
UI.repDiscRow = MakeToggle("Replay on Disconnects: " .. (SETTINGS.ReplayOnDisconnect and "ON" or "OFF"), SETTINGS.ReplayOnDisconnect, miscPage)
UI.rejDiscRow = MakeToggle("Rejoin on Disconnect: " .. (SETTINGS.RejoinOnDisconnect and "ON" or "OFF"), SETTINGS.RejoinOnDisconnect, miscPage)

UI.eifToggleBtn = MakeToggle("EIF Spammer: " .. (SETTINGS.EIFSpammerEnabled and "ON" or "OFF"), SETTINGS.EIFSpammerEnabled, miscPage)
UI.eifSlotBtn = MakeButton("EIF Slot: " .. SETTINGS.EIFSpammerSlot:upper(), Color3.fromRGB(58, 80, 200), miscPage)
UI.eifDelayInput = MakeSettingRow("EIF Spam Delay (s):", SETTINGS.EIFSpammerDelay, miscPage)

-- AUTO-SELL TAB (Expanded Customizable Matrix)
UI.autoSellToggleBtn = MakeToggle("Auto Sell: OFF", false, sellPage)
local sellNowBtn = MakeButton("Sell Matching Items Now", Color3.fromRGB(190, 105, 30), sellPage)

local function setupCategoryRaritySection(catKey, catDisplayName)
    local headerBtn = MakeButton(catDisplayName .. " [Click to Configure ▼]", Color3.fromRGB(30, 40, 72), sellPage)

    local container = Instance.new("Frame")
    container.Size = UDim2.new(1, 0, 0, 100)
    container.BackgroundTransparency = 1
    container.Visible = false
    container.Parent = sellPage

    local grid = Instance.new("UIGridLayout")
    grid.Parent = container
    grid.CellSize = UDim2.new(0.32, 0, 0, 30)
    grid.CellPadding = UDim2.new(0.02, 0, 0, 6)

    local buttons = {}
    for _, rarity in ipairs(RARITY_ORDER) do
        local rBtn = MakeToggle(rarity:upper() .. ": OFF", false, container)
        buttons[rarity] = rBtn

        rBtn.MouseButton1Click:Connect(function()
            SETTINGS.AutoSellConfig[catKey][rarity] = not SETTINGS.AutoSellConfig[catKey][rarity]
            local isEnabled = SETTINGS.AutoSellConfig[catKey][rarity]
            rBtn.Text = rarity:upper() .. ": " .. (isEnabled and "ON" or "OFF")
            rBtn.BackgroundColor3 = isEnabled and Color3.fromRGB(40, 150, 70) or T.idle
            updateCategoryDropdownTitle(catKey)
            saveConfig()
        end)
    end

    headerBtn.MouseButton1Click:Connect(function()
        container.Visible = not container.Visible
        if not container.Visible then
            updateCategoryDropdownTitle(catKey)
        else
            headerBtn.Text = catDisplayName .. " [Close Configuration ▲]"
        end
    end)

    UI.catSections[catKey] = {
        headerBtn = headerBtn,
        container = container,
        buttons = buttons,
        displayName = catDisplayName
    }
    updateCategoryDropdownTitle(catKey)
end

setupCategoryRaritySection("weapon", "WEAPONS")
setupCategoryRaritySection("chest", "ARMOR / CHESTS")
setupCategoryRaritySection("helmet", "HELMETS")
setupCategoryRaritySection("ability", "ABILITIES")

UI.autoSellToggleBtn.MouseButton1Click:Connect(function()
    SETTINGS.AutoSellEnabled = not SETTINGS.AutoSellEnabled
    UI.autoSellToggleBtn.Text = "Auto Sell: " .. (SETTINGS.AutoSellEnabled and "ON" or "OFF")
    UI.autoSellToggleBtn.BackgroundColor3 = SETTINGS.AutoSellEnabled and Color3.fromRGB(40, 150, 70) or T.idle
    saveConfig()
end)

sellNowBtn.MouseButton1Click:Connect(executeAutoSell)

-- BOTTOM CONTROLS
local bottomBar = Instance.new("Frame")
bottomBar.Size = UDim2.new(0, PAGE_W, 0, 46)
bottomBar.Position = UDim2.new(0, 12, 0, 482)
bottomBar.BackgroundTransparency = 1
bottomBar.Parent = body

local runMacroBtn = MakeButton("RUN SCRIPT (Autoplay)", T.accent, bottomBar)
runMacroBtn.Size = UDim2.new(0.66, 0, 1, 0)
runMacroBtn.TextSize = 14
runMacroBtn.Font = Enum.Font.GothamBold
UI.runMacroBtn = runMacroBtn

local terminateBtn = MakeButton("💬  Discord", Color3.fromRGB(54, 62, 150), bottomBar)
terminateBtn.Size = UDim2.new(0.32, 0, 1, 0)
terminateBtn.Position = UDim2.new(0.68, 0, 0, 0)
local killStroke = stroke(terminateBtn, Color3.fromRGB(60, 70, 190))
terminateBtn.MouseEnter:Connect(function() killStroke.Color = T.accent2 end)
terminateBtn.MouseLeave:Connect(function() killStroke.Color = Color3.fromRGB(60, 70, 190) end)

-- RIGHT COLUMN: NODE + CLEAR NODE CARDS
local function createCard(title, y, height)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(0, 244, 0, height)
    card.Position = UDim2.new(0, RIGHT_COL_X, 0, y)
    card.BackgroundColor3 = T.panel
    card.BorderSizePixel = 0
    card.Parent = body
    round(card, 12)
    stroke(card)
    local dot = Instance.new("Frame")
    dot.Size = UDim2.new(0, 4, 0, 18)
    dot.Position = UDim2.new(0, 16, 0, 14)
    dot.BackgroundColor3 = T.accent2
    dot.BorderSizePixel = 0
    dot.Parent = card
    round(dot, 2)
    local titleText = makeText(card, title, 16, T.text, Enum.Font.GothamBold)
    titleText.Size = UDim2.new(1, -60, 0, 24)
    titleText.Position = UDim2.new(0, 28, 0, 11)
    return card
end

local nodeCard = createCard("Node", 84, 180)

local curLabel = makeText(nodeCard, "Current Node", 12, T.muted, Enum.Font.Gotham)
curLabel.Size = UDim2.new(0, 120, 0, 16)
curLabel.Position = UDim2.new(0, 16, 0, 48)

UI.nodeCountLabel = makeText(nodeCard, "0 / 0", 28, T.text, Enum.Font.GothamBold)
UI.nodeCountLabel.Size = UDim2.new(0, 130, 0, 36)
UI.nodeCountLabel.Position = UDim2.new(0, 16, 0, 66)

local function makeArrow(x, glyph)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 34, 0, 34)
    b.Position = UDim2.new(0, x, 0, 68)
    b.BackgroundColor3 = T.field
    b.Text = glyph
    b.TextColor3 = T.text
    b.Font = Enum.Font.GothamBold
    b.TextSize = 16
    b.BorderSizePixel = 0
    b.Parent = nodeCard
    round(b, 8)
    stroke(b)
    return b
end
UI.nodePrevBtn = makeArrow(156, "<")
UI.nodeNextBtn = makeArrow(198, ">")

UI.nodeDot = Instance.new("Frame")
UI.nodeDot.Size = UDim2.new(0, 9, 0, 9)
UI.nodeDot.Position = UDim2.new(0, 16, 0, 118)
UI.nodeDot.BackgroundColor3 = T.muted
UI.nodeDot.BorderSizePixel = 0
UI.nodeDot.Parent = nodeCard
round(UI.nodeDot, 5)
UI.nodeStateLabel = makeText(nodeCard, "Idle", 14, T.muted, Enum.Font.GothamSemibold)
UI.nodeStateLabel.Size = UDim2.new(0, 120, 0, 20)
UI.nodeStateLabel.Position = UDim2.new(0, 32, 0, 112)

local totalLabel = makeText(nodeCard, "Total Nodes", 12, T.muted, Enum.Font.Gotham)
totalLabel.Size = UDim2.new(0, 110, 0, 16)
totalLabel.Position = UDim2.new(0, 16, 0, 146)
UI.nodeTotalLabel = makeText(nodeCard, "0", 16, Color3.fromRGB(60, 225, 205), Enum.Font.GothamBold, Enum.TextXAlignment.Right)
UI.nodeTotalLabel.Size = UDim2.new(0, 100, 0, 20)
UI.nodeTotalLabel.Position = UDim2.new(0, 128, 0, 144)

local clearCard = createCard("Clear Node", 276, 252)

local statusTitle = makeText(clearCard, "Status", 12, T.muted, Enum.Font.Gotham)
statusTitle.Size = UDim2.new(0, 120, 0, 16)
statusTitle.Position = UDim2.new(0, 16, 0, 48)
local readyDot = Instance.new("Frame")
readyDot.Size = UDim2.new(0, 9, 0, 9)
readyDot.Position = UDim2.new(0, 16, 0, 72)
readyDot.BackgroundColor3 = T.green
readyDot.BorderSizePixel = 0
readyDot.Parent = clearCard
round(readyDot, 5)
local readyLabel = makeText(clearCard, "Ready", 14, T.text, Enum.Font.GothamSemibold)
readyLabel.Size = UDim2.new(0, 120, 0, 20)
readyLabel.Position = UDim2.new(0, 32, 0, 66)

local loadedTitle = makeText(clearCard, "Loaded Macro", 12, T.muted, Enum.Font.Gotham)
loadedTitle.Size = UDim2.new(0, 120, 0, 16)
loadedTitle.Position = UDim2.new(0, 16, 0, 104)
UI.loadedMacroLabel = makeText(clearCard, "None", 14, T.text, Enum.Font.GothamSemibold)
UI.loadedMacroLabel.Size = UDim2.new(1, -32, 0, 20)
UI.loadedMacroLabel.Position = UDim2.new(0, 16, 0, 122)
UI.loadedMacroLabel.TextTruncate = Enum.TextTruncate.AtEnd

local clearAllBtn = MakeButton("Clear All Nodes", T.accent, clearCard)
clearAllBtn.Size = UDim2.new(1, -24, 0, 40)
clearAllBtn.Position = UDim2.new(0, 12, 1, -52)

UI.nodePrevBtn.MouseButton1Click:Connect(function()
    if #waypoints > 0 then currentWaypointIndex = math.max(1, math.min(currentWaypointIndex, #waypoints) - 1) end
end)
UI.nodeNextBtn.MouseButton1Click:Connect(function()
    if #waypoints > 0 then currentWaypointIndex = math.min(#waypoints, currentWaypointIndex + 1) end
end)
clearAllBtn.MouseButton1Click:Connect(clearWaypoints)

-- LIVE STATE (header pill + node card)
task.spawn(function()
    while not isCleaningUp and screenGui.Parent do
        local total = #waypoints
        UI.nodeCountLabel.Text = string.format("%d / %d", total > 0 and math.min(currentWaypointIndex, total) or 0, total)
        UI.nodeTotalLabel.Text = tostring(total)

        local traversing = traversingManualNodes and isAutoplay
        UI.nodeStateLabel.Text = traversing and "Active" or "Idle"
        UI.nodeStateLabel.TextColor3 = traversing and T.green or T.muted
        UI.nodeDot.BackgroundColor3 = traversing and T.green or T.muted
        UI.loadedMacroLabel.Text = selectedMacroName ~= "" and selectedMacroName or "None"

        local stateText, stateColor = "IDLE", T.muted
        if isRecording then
            stateText, stateColor = "RECORDING", T.orange
        elseif isAutoplay then
            stateText, stateColor = "MACRO ACTIVE", T.green
        end
        UI.stateLabel.Text = stateText
        UI.stateLabel.TextColor3 = stateColor
        UI.stateDot.BackgroundColor3 = stateColor

        UI.runMacroBtn.Text = isAutoplay and "■  STOP AUTOPLAY" or "▶  RUN SCRIPT (Autoplay)"
        UI.runMacroBtn.BackgroundColor3 = isAutoplay and T.pink or T.accent
        task.wait(0.25)
    end
end)

-- WINDOW CONTROLS
local isUIMinimized = false
local function setMinimized(state)
    isUIMinimized = state
    macroScroll.Visible = false
    if state then
        if not UI.miniIcon then
            local icon = Instance.new("TextButton")
            icon.Name = "NCLMiniIcon"
            icon.Size = UDim2.new(0, 84, 0, 84)
            icon.Position = UDim2.new(0.71, -96, 0, 68) -- default: just left of the top timer
            icon.BackgroundTransparency = 1
            icon.Text = ""
            icon.AutoButtonColor = false
            icon.Visible = false
            icon.Parent = screenGui
            createLogoMark(icon, 2)
            -- custom drag (mouse + touch): drag anywhere to move, a plain click restores the window
            local dragging, moved, dragStart, startPos = false, false, nil, nil
            local function isPointer(input)
                return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
            end
            local dragKind
            local function moveTo(pointer)
                local delta = pointer - dragStart
                if delta.Magnitude > 4 then moved = true; UI.iconDragged = true end
                if moved then
                    icon.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
                end
            end
            icon.InputBegan:Connect(function(input)
                if isPointer(input) then
                    dragging, moved, dragKind = true, false, input.UserInputType
                    if dragKind == Enum.UserInputType.Touch then
                        dragStart = Vector2.new(input.Position.X, input.Position.Y)
                    else
                        dragStart = UserInputService:GetMouseLocation()
                    end
                    startPos = icon.Position
                end
            end)
            -- mouse: follow the cursor every frame; touch: follow the finger
            table.insert(connections, RunService.RenderStepped:Connect(function()
                if dragging and dragKind == Enum.UserInputType.MouseButton1 then
                    moveTo(UserInputService:GetMouseLocation())
                end
            end))
            table.insert(connections, UserInputService.InputChanged:Connect(function(input)
                if dragging and dragKind == Enum.UserInputType.Touch and input.UserInputType == Enum.UserInputType.Touch then
                    moveTo(Vector2.new(input.Position.X, input.Position.Y))
                end
            end))
            table.insert(connections, UserInputService.InputEnded:Connect(function(input)
                if dragging and isPointer(input) then
                    dragging = false
                    if not moved then setMinimized(false) end
                end
            end))
            UI.miniIcon = icon
        end
        -- park the icon just above the game's top timer (unless you dragged it somewhere yourself)
        if not UI.iconDragged then
            pcall(function()
                local timeGui = player.PlayerGui:FindFirstChild("timeLeftGui")
                local timer = timeGui and findNested(timeGui, "Frame", "time")
                if timer and timer.AbsoluteSize.X > 0 then
                    local inset = game:GetService("GuiService"):GetGuiInset()
                    local iconSize = UI.miniIcon.AbsoluteSize.X
                    local x = timer.AbsolutePosition.X + timer.AbsoluteSize.X / 2 - iconSize / 2
                    local y = math.max(timer.AbsolutePosition.Y - inset.Y - iconSize - 6, 0)
                    UI.miniIcon.Position = UDim2.new(0, x, 0, y)
                end
            end)
        end
        mainFrame.Visible = false
        UI.miniIcon.Visible = true
    else
        if UI.miniIcon then UI.miniIcon.Visible = false end
        mainFrame.Visible = true
        UI.popIn()
    end
end
minimizeBtn.MouseButton1Click:Connect(function() setMinimized(not isUIMinimized) end)
UI.setMinimized = setMinimized
function UI.refreshAutoHideBtns()
    local on = SETTINGS.AutoHideUI
    if UI.autoHideRow then
        UI.autoHideRow.Text = "Auto Hide UI: " .. (on and "ON" or "OFF")
        UI.autoHideRow.BackgroundColor3 = on and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
    end
    if UI.autoHideQuickBtn then
        UI.autoHideQuickBtn.BackgroundColor3 = on and Color3.fromRGB(40, 150, 70) or T.field
    end
end
local function toggleAutoHide()
    SETTINGS.AutoHideUI = not SETTINGS.AutoHideUI
    UI.refreshAutoHideBtns()
    saveConfig()
end
UI.autoHideRow.MouseButton1Click:Connect(toggleAutoHide)
UI.autoHideQuickBtn.MouseButton1Click:Connect(toggleAutoHide)
UI.refreshAutoHideBtns()
-- Auto Hide UI only minimizes the window right when the script executes (Run Script, or auto-resume on load) -
-- see the RUN SCRIPT handler below and loadConfigAndAutoExecute(). Simply reopening the menu never re-hides it.

local isUIMaximized = false
maximizeBtn.MouseButton1Click:Connect(function()
    isUIMaximized = not isUIMaximized
    local viewportSize = (Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize) or Vector2.new(1280, 720)
    local bigger = math.min(UI.baseScale * 1.25, (viewportSize.X - 20) / WINDOW_W, (viewportSize.Y - 20) / (WINDOW_H + 40))
    uiScale.Scale = isUIMaximized and math.max(bigger, UI.baseScale) or UI.baseScale
    macroScroll.Visible = false
end)

-- RESIZE HANDLE: drag the bottom-right corner to freely make the whole window bigger or smaller
local resizeHandle = Instance.new("TextButton")
resizeHandle.Size = UDim2.new(0, 22, 0, 22)
resizeHandle.AnchorPoint = Vector2.new(1, 1)
resizeHandle.Position = UDim2.new(1, -2, 1, -2)
resizeHandle.BackgroundTransparency = 1
resizeHandle.Text = "◢"
resizeHandle.TextColor3 = T.muted
resizeHandle.Font = Enum.Font.GothamBold
resizeHandle.TextSize = 16
resizeHandle.AutoButtonColor = false
resizeHandle.ZIndex = 50
resizeHandle.Parent = mainFrame
resizeHandle.MouseEnter:Connect(function() resizeHandle.TextColor3 = T.accent end)
resizeHandle.MouseLeave:Connect(function() resizeHandle.TextColor3 = T.muted end)

local isResizing, resizeStartPos, resizeStartScale = false, Vector2.zero, UI.baseScale
local function applyResizeDrag(cur)
    local delta = cur - resizeStartPos
    local drag = (delta.X + delta.Y) / 2
    uiScale.Scale = math.clamp(resizeStartScale + drag / 420, 0.4, 1.6)
    isUIMaximized = false
end
resizeHandle.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        isResizing = true
        resizeStartScale = uiScale.Scale
        resizeStartPos = (input.UserInputType == Enum.UserInputType.Touch) and Vector2.new(input.Position.X, input.Position.Y) or UserInputService:GetMouseLocation()
    end
end)
table.insert(connections, RunService.RenderStepped:Connect(function()
    if isResizing then applyResizeDrag(UserInputService:GetMouseLocation()) end
end))
table.insert(connections, UserInputService.InputChanged:Connect(function(input)
    if isResizing and input.UserInputType == Enum.UserInputType.Touch then
        applyResizeDrag(Vector2.new(input.Position.X, input.Position.Y))
    end
end))
table.insert(connections, UserInputService.InputEnded:Connect(function(input)
    if isResizing and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
        isResizing = false
    end
end))

closeBtn.MouseButton1Click:Connect(function() cleanup() end)

switchTab(1)

-- SETTINGS INPUT LISTENERS
UI.minDistInput.FocusLost:Connect(function() applySetting(UI.minDistInput, "MinDistance") end)
UI.maxDistInput.FocusLost:Connect(function() applySetting(UI.maxDistInput, "MaxDistance") end)
UI.atkReachInput.FocusLost:Connect(function() applySetting(UI.atkReachInput, "AttackReach") end)

UI.customTargetInput.FocusLost:Connect(function()
    if isCleaningUp then return end
    SETTINGS.CustomTargetName = UI.customTargetInput.Text
    saveConfig()
    setStatus("Bonus Target Mob set to: " .. UI.customTargetInput.Text)
end)

UI.customRangeInput.FocusLost:Connect(function()
    applySetting(UI.customRangeInput, "CustomTargetExtraRange")
end)

UI.ignoreEnemyInput.FocusLost:Connect(function()
    if isCleaningUp then return end
    SETTINGS.IgnoreEnemyNames = UI.ignoreEnemyInput.Text
    updateIgnoreEnemyNames()
    saveConfig()
    setStatus("Ignored enemies updated!")
end)

UI.eifToggleBtn.MouseButton1Click:Connect(function()
    SETTINGS.EIFSpammerEnabled = not SETTINGS.EIFSpammerEnabled
    UI.eifToggleBtn.Text = "EIF Spammer: " .. (SETTINGS.EIFSpammerEnabled and "ON" or "OFF")
    UI.eifToggleBtn.BackgroundColor3 = SETTINGS.EIFSpammerEnabled and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
    saveConfig()
end)

UI.eifSlotBtn.MouseButton1Click:Connect(function()
    SETTINGS.EIFSpammerSlot = (SETTINGS.EIFSpammerSlot:upper() == "Q") and "E" or "Q"
    UI.eifSlotBtn.Text = "EIF Slot: " .. SETTINGS.EIFSpammerSlot:upper()
    saveConfig()
end)

UI.eifDelayInput.FocusLost:Connect(function()
    applySetting(UI.eifDelayInput, "EIFSpammerDelay")
end)

UI.atkDelayInput.FocusLost:Connect(function() applySetting(UI.atkDelayInput, "AttackCooldown") end)
UI.dodgeBufferInput.FocusLost:Connect(function() applySetting(UI.dodgeBufferInput, "DodgeBuffer") end)
UI.wpTriggerInput.FocusLost:Connect(function() applySetting(UI.wpTriggerInput, "WaypointTriggerDist") end)
UI.maxNodeDistInput.FocusLost:Connect(function() applySetting(UI.maxNodeDistInput, "MaxNodeDistance") end)
UI.wallRayInput.FocusLost:Connect(function() applySetting(UI.wallRayInput, "WallRayLength") end)
UI.noEnemyDelayInput.FocusLost:Connect(function() applySetting(UI.noEnemyDelayInput, "NoEnemyDelay") end)
UI.partySizeInput.FocusLost:Connect(function() applySetting(UI.partySizeInput, "TargetPartySize") end)

UI.autoLobbyRow.MouseButton1Click:Connect(function()
    SETTINGS.AutoLobbyEnabled = not SETTINGS.AutoLobbyEnabled
    UI.autoLobbyRow.Text = "Auto Lobby Routine: " .. (SETTINGS.AutoLobbyEnabled and "ON" or "OFF")
    UI.autoLobbyRow.BackgroundColor3 = SETTINGS.AutoLobbyEnabled and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
    saveConfig()
end)

UI.roleRow.MouseButton1Click:Connect(function()
    SETTINGS.LobbyMode = (SETTINGS.LobbyMode == "Host") and "Join" or "Host"
    UI.roleRow.Text = "Lobby Role: " .. SETTINGS.LobbyMode:upper()
    saveConfig()
end)

UI.repDiscRow.MouseButton1Click:Connect(function()
    SETTINGS.ReplayOnDisconnect = not SETTINGS.ReplayOnDisconnect
    UI.repDiscRow.Text = "Replay on Disconnects: " .. (SETTINGS.ReplayOnDisconnect and "ON" or "OFF")
    UI.repDiscRow.BackgroundColor3 = SETTINGS.ReplayOnDisconnect and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
    saveConfig()
end)

UI.rejDiscRow.MouseButton1Click:Connect(function()
    SETTINGS.RejoinOnDisconnect = not SETTINGS.RejoinOnDisconnect
    UI.rejDiscRow.Text = "Rejoin on Disconnect: " .. (SETTINGS.RejoinOnDisconnect and "ON" or "OFF")
    UI.rejDiscRow.BackgroundColor3 = SETTINGS.RejoinOnDisconnect and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
    saveConfig()
end)

UI.joinNameInput.FocusLost:Connect(function()
    if isCleaningUp then return end
    SETTINGS.JoinPlayerName = UI.joinNameInput.Text
    saveConfig()
end)

UI.waitForPlayersRow.MouseButton1Click:Connect(function()
    SETTINGS.WaitForPlayers = not SETTINGS.WaitForPlayers
    UI.waitForPlayersRow.Text = "Wait for Party in Dungeon: " .. (SETTINGS.WaitForPlayers and "ON" or "OFF")
    UI.waitForPlayersRow.BackgroundColor3 = SETTINGS.WaitForPlayers and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
    saveConfig()
end)

UI.hcRow.MouseButton1Click:Connect(function()
    SETTINGS.LobbyHardcore = not SETTINGS.LobbyHardcore
    UI.hcRow.Text = "Hardcore Mode: " .. (SETTINGS.LobbyHardcore and "ON" or "OFF")
    UI.hcRow.BackgroundColor3 = SETTINGS.LobbyHardcore and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
    saveConfig()
end)

UI.privRow.MouseButton1Click:Connect(function()
    SETTINGS.LobbyPrivate = not SETTINGS.LobbyPrivate
    UI.privRow.Text = "Private Lobby: " .. (SETTINGS.LobbyPrivate and "ON" or "OFF")
    UI.privRow.BackgroundColor3 = SETTINGS.LobbyPrivate and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
    saveConfig()
end)

UI.modeRow.MouseButton1Click:Connect(function()
    if SETTINGS.GameplayMode == "Play Mode" then 
        SETTINGS.GameplayMode = "No TP Auto Play"
    elseif SETTINGS.GameplayMode == "No TP Auto Play" then
        SETTINGS.GameplayMode = "Legit Player"
    elseif SETTINGS.GameplayMode == "Legit Player" then 
        SETTINGS.GameplayMode = "Manual Play"
    elseif SETTINGS.GameplayMode == "Manual Play" then 
        SETTINGS.GameplayMode = "Ultra Carry Mode"
    elseif SETTINGS.GameplayMode == "Ultra Carry Mode" then 
        SETTINGS.GameplayMode = "Get Carried Mode"
    else 
        SETTINGS.GameplayMode = "Play Mode" 
    end
    UI.modeRow.Text = "Gameplay Mode: " .. SETTINGS.GameplayMode

    if humanoid then
        if SETTINGS.GameplayMode == "Manual Play" or not isAutoplay then
            humanoid.AutoRotate = true
            humanoid.WalkSpeed = 16
            if alignOrient then alignOrient.Enabled = false end
        else
            humanoid.AutoRotate = false
            humanoid.WalkSpeed = (SETTINGS.GameplayMode == "Legit Player") and 16 or MOVE_SPEED
            if alignOrient then alignOrient.Enabled = true end
        end
    end
    saveConfig()
end)

UI.blackScreenRow.MouseButton1Click:Connect(function()
    applyBlackScreen(not SETTINGS.BlackScreen)
end)
UI.blackScreenQuickBtn.MouseButton1Click:Connect(function()
    applyBlackScreen(not SETTINGS.BlackScreen)
end)
UI.boostFpsRow.MouseButton1Click:Connect(function()
    applyBoostFPS(not SETTINGS.BoostFPS)
end)
UI.boostFpsQuickBtn.MouseButton1Click:Connect(function()
    applyBoostFPS(not SETTINGS.BoostFPS)
end)
UI.maxFpsInput.FocusLost:Connect(function()
    if isCleaningUp then return end
    applyMaxFps(UI.maxFpsInput.Text)
end)
table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
    if processed or isCleaningUp then return end
    if input.KeyCode == BLACKSCREEN_KEY then applyBlackScreen(not SETTINGS.BlackScreen) end
end))

UI.autoDodgeRow.MouseButton1Click:Connect(function()
    SETTINGS.AutoDodgeEnabled = not SETTINGS.AutoDodgeEnabled
    UI.autoDodgeRow.Text = "Auto Dodging: " .. (SETTINGS.AutoDodgeEnabled and "ON" or "OFF")
    UI.autoDodgeRow.BackgroundColor3 = SETTINGS.AutoDodgeEnabled and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
    saveConfig()
end)

UI.replayTimeInput.FocusLost:Connect(function()
    if isCleaningUp then return end
    SETTINGS.ReplayTime = UI.replayTimeInput.Text
    saveConfig()
    setStatus("Replay Time updated!")
end)

UI.filterInput.FocusLost:Connect(function()
    if isCleaningUp then return end
    SETTINGS.IgnoreKeywords = UI.filterInput.Text
    updateIgnoreKeywords()
    saveConfig()
    setStatus("Hazard filters updated!")
end)

UI.webhookInput.FocusLost:Connect(function()
    if isCleaningUp then return end
    SETTINGS.Webhook = UI.webhookInput.Text
    saveConfig()
    setStatus("Webhook URL updated!")
end)

-- MACRO BUTTONS
recordBtn.MouseButton1Click:Connect(function()
    isRecording = true
    setStatus("Status: Recording Mode Active")
end)

stopRecordBtn.MouseButton1Click:Connect(function()
    isRecording = false
    setStatus("Status: Recording Stopped")
end)

addWaypointBtn.MouseButton1Click:Connect(function()
    if isRecording then addWaypointNode() else setStatus("Error: Enable Recording Mode first!") end 
end)

clearWaypointsBtn.MouseButton1Click:Connect(clearWaypoints)

exportBtn.MouseButton1Click:Connect(function()
    if selectedMacroName == "" then return end
    local filePath = FOLDER_NAME .. "/" .. selectedMacroName .. ".json"
    if isfile and isfile(filePath) then
        setClipboard(readfile(filePath))
        setStatus("Copied " .. selectedMacroName .. " to Clipboard!")
    end
end)

importBtn.MouseButton1Click:Connect(function()
    local text = importInput.Text
    local name = nameInput.Text
    if text == "" or name == "" then setStatus("Need Name AND JSON to import!"); return end

    local success, decoded = pcall(function() return HttpService:JSONDecode(text) end)
    if success and type(decoded) == "table" and decoded[1] and decoded[1].X then
        local filePath = FOLDER_NAME .. "/" .. name .. ".json"
        writefile(filePath, text)
        setStatus("Imported Macro as: " .. name)
        importInput.Text = ""
        refreshMacroList()
    else
        setStatus("Invalid JSON Macro Data!")
    end
end)

deleteBtn.MouseButton1Click:Connect(function()
    if selectedMacroName == "" then return end
    local filePath = FOLDER_NAME .. "/" .. selectedMacroName .. ".json"
    pcall(function() delFile(filePath) end)
    setStatus("Deleted Macro: " .. selectedMacroName)
    selectedMacroName = ""
    clearWaypoints()
    refreshMacroList()
    saveConfig()
end)

saveBtn.MouseButton1Click:Connect(function()
    local macroName = nameInput.Text
    if macroName == "" or #waypoints == 0 then return end
    local serializableTable = {}
    for _, vec in ipairs(waypoints) do table.insert(serializableTable, {X = vec.X, Y = vec.Y, Z = vec.Z}) end
    writefile(FOLDER_NAME .. "/" .. macroName .. ".json", HttpService:JSONEncode(serializableTable))
    selectedMacroName = macroName
    refreshMacroList()
    saveConfig()
end)

runMacroBtn.MouseButton1Click:Connect(function()
    isAutoplay = not isAutoplay
    SETTINGS.Autoplay = isAutoplay
    runMacroBtn.Text = isAutoplay and "■  STOP AUTOPLAY" or "▶  RUN SCRIPT (Autoplay)"
    runMacroBtn.BackgroundColor3 = isAutoplay and UI.theme.pink or UI.theme.accent
    hasReturnedToLobby = false
    lastEnemySeenTime = os.clock()
    
    if isAutoplay then
        if humanoid then
            if SETTINGS.GameplayMode == "Manual Play" then
                humanoid.AutoRotate = true
                humanoid.WalkSpeed = 16
                if alignOrient then alignOrient.Enabled = false end
            else
                humanoid.WalkSpeed = (SETTINGS.GameplayMode == "Legit Player") and 16 or MOVE_SPEED
                humanoid.AutoRotate = false
                if alignOrient then alignOrient.Enabled = true end
            end
        end
        if #waypoints == 0 and selectedMacroName ~= "" then loadMacroFromFile(selectedMacroName) end
        if SETTINGS.AutoHideUI then UI.setMinimized(true) end
    else
        if humanoid then
            humanoid.AutoRotate = true
            humanoid.WalkSpeed = 16
        end
        if alignOrient then alignOrient.Enabled = false end
    end
    saveConfig()
end)

terminateBtn.MouseButton1Click:Connect(function()
    setClipboard(DISCORD_INVITE)
    terminateBtn.Text = "Copied!"
    task.delay(1.5, function() if terminateBtn.Parent then terminateBtn.Text = "💬  Discord" end end)
end)
end

-- 5. LOAD CONFIG AND AUTO-EXECUTE

function applyConfigData(cfg)
if type(cfg) ~= "table" then return end

if cfg.Autoplay ~= nil then SETTINGS.Autoplay = cfg.Autoplay end
SETTINGS.MinDistance = cfg.MinDistance or SETTINGS.MinDistance
SETTINGS.MaxDistance = cfg.MaxDistance or SETTINGS.MaxDistance
SETTINGS.AttackReach = cfg.AttackReach or SETTINGS.AttackReach
SETTINGS.AttackCooldown = cfg.AttackCooldown or SETTINGS.AttackCooldown
SETTINGS.CustomTargetName = cfg.CustomTargetName or SETTINGS.CustomTargetName
SETTINGS.CustomTargetExtraRange = cfg.CustomTargetExtraRange or SETTINGS.CustomTargetExtraRange
SETTINGS.IgnoreEnemyNames = cfg.IgnoreEnemyNames or SETTINGS.IgnoreEnemyNames

if cfg.EIFSpammerEnabled ~= nil then SETTINGS.EIFSpammerEnabled = cfg.EIFSpammerEnabled end
if cfg.EIFSpammerSlot then SETTINGS.EIFSpammerSlot = cfg.EIFSpammerSlot end
if cfg.EIFSpammerDelay ~= nil then SETTINGS.EIFSpammerDelay = cfg.EIFSpammerDelay end

SETTINGS.DodgeBuffer = cfg.DodgeBuffer or SETTINGS.DodgeBuffer
SETTINGS.WaypointTriggerDist = cfg.WaypointTriggerDist or SETTINGS.WaypointTriggerDist
SETTINGS.MaxNodeDistance = cfg.MaxNodeDistance or SETTINGS.MaxNodeDistance
SETTINGS.WallRayLength = cfg.WallRayLength or SETTINGS.WallRayLength
SETTINGS.NoEnemyDelay = cfg.NoEnemyDelay or SETTINGS.NoEnemyDelay
SETTINGS.Webhook = cfg.Webhook or ""
if cfg.WebhookLogo ~= nil then SETTINGS.WebhookLogo = tostring(cfg.WebhookLogo) end
SETTINGS.IgnoreKeywords = cfg.IgnoreKeywords or SETTINGS.IgnoreKeywords

if cfg.AutoLobbyEnabled ~= nil then SETTINGS.AutoLobbyEnabled = cfg.AutoLobbyEnabled end
if cfg.LobbyMode then SETTINGS.LobbyMode = cfg.LobbyMode end
if cfg.JoinPlayerName then SETTINGS.JoinPlayerName = cfg.JoinPlayerName end
SETTINGS.LobbyMap = cfg.LobbyMap or SETTINGS.LobbyMap
SETTINGS.LobbyDifficulty = cfg.LobbyDifficulty or SETTINGS.LobbyDifficulty
SETTINGS.LobbyHardcore = cfg.LobbyHardcore or false
SETTINGS.LobbyPrivate = cfg.LobbyPrivate or false
SETTINGS.FollowHost = cfg.FollowHost or false
if UI.followHostRow then
    UI.followHostRow.Text = "Follow Host: " .. (SETTINGS.FollowHost and "ON" or "OFF")
    UI.followHostRow.BackgroundColor3 = SETTINGS.FollowHost and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
end
if cfg.AutoCreateLobby ~= nil then SETTINGS.AutoCreateLobby = cfg.AutoCreateLobby end
if UI.autoCreateLobbyRow then
    UI.autoCreateLobbyRow.Text = "Auto Create Lobby: " .. (SETTINGS.AutoCreateLobby and "ON" or "OFF")
    UI.autoCreateLobbyRow.BackgroundColor3 = SETTINGS.AutoCreateLobby and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
end
SETTINGS.TargetPartySize = cfg.TargetPartySize or 0
if cfg.WaitForPlayers ~= nil then SETTINGS.WaitForPlayers = cfg.WaitForPlayers end
if cfg.AutoDodgeEnabled ~= nil then SETTINGS.AutoDodgeEnabled = cfg.AutoDodgeEnabled end
if cfg.BlackScreen ~= nil then SETTINGS.BlackScreen = cfg.BlackScreen end
if cfg.ShowRangeCircle ~= nil then SETTINGS.ShowRangeCircle = cfg.ShowRangeCircle end
if UI.rangeCircleRow then
    UI.rangeCircleRow.Text = "Show Range Circle: " .. (SETTINGS.ShowRangeCircle and "ON" or "OFF")
    UI.rangeCircleRow.BackgroundColor3 = SETTINGS.ShowRangeCircle and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
end
if cfg.AutoHideUI ~= nil then SETTINGS.AutoHideUI = cfg.AutoHideUI end
if UI.autoHideRow then
    UI.autoHideRow.Text = "Auto Hide UI: " .. (SETTINGS.AutoHideUI and "ON" or "OFF")
    UI.autoHideRow.BackgroundColor3 = SETTINGS.AutoHideUI and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
end
if UI.refreshAutoHideBtns then UI.refreshAutoHideBtns() end
if cfg.BoostFPS ~= nil then applyBoostFPS(cfg.BoostFPS, true) end
if cfg.MaxFPS ~= nil then applyMaxFps(cfg.MaxFPS, true) end
if cfg.CustomName ~= nil then SETTINGS.CustomName = tostring(cfg.CustomName) end
if cfg.RenameParty ~= nil then SETTINGS.RenameParty = cfg.RenameParty end
SETTINGS.LogoAvatar = true -- icon is fixed; only the username can be changed
if cfg.AutoTrade ~= nil then SETTINGS.AutoTrade = cfg.AutoTrade end
if cfg.AutoAcceptTrade ~= nil then SETTINGS.AutoAcceptTrade = cfg.AutoAcceptTrade end
if cfg.AutoAcceptRequireGold ~= nil then SETTINGS.AutoAcceptRequireGold = cfg.AutoAcceptRequireGold end
if UI.requireGoldRow then
    UI.requireGoldRow.Text = "Skip Trade if Gold is 0: " .. (SETTINGS.AutoAcceptRequireGold and "ON" or "OFF")
    UI.requireGoldRow.BackgroundColor3 = SETTINGS.AutoAcceptRequireGold and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
end
if cfg.AcceptUsername ~= nil then SETTINGS.AcceptUsername = tostring(cfg.AcceptUsername) end
if cfg.TradeUsername ~= nil then SETTINGS.TradeUsername = tostring(cfg.TradeUsername) end
SETTINGS.AutoSellEnabled = cfg.AutoSellEnabled or false

if cfg.GameplayMode then SETTINGS.GameplayMode = cfg.GameplayMode end
if cfg.ReplayOnDisconnect ~= nil then SETTINGS.ReplayOnDisconnect = cfg.ReplayOnDisconnect end
if cfg.RejoinOnDisconnect ~= nil then SETTINGS.RejoinOnDisconnect = cfg.RejoinOnDisconnect end
if cfg.ReplayTime then SETTINGS.ReplayTime = cfg.ReplayTime end

-- Load Category-Specific Rarity Matrix
if cfg.AutoSellConfig and type(cfg.AutoSellConfig) == "table" then
    for catKey, rarities in pairs(cfg.AutoSellConfig) do
        if SETTINGS.AutoSellConfig[catKey] and type(rarities) == "table" then
            for rName, rVal in pairs(rarities) do
                SETTINGS.AutoSellConfig[catKey][rName] = rVal
                if UI.catSections[catKey] and UI.catSections[catKey].buttons[rName] then
                    local rBtn = UI.catSections[catKey].buttons[rName]
                    rBtn.Text = rName:upper() .. ": " .. (rVal and "ON" or "OFF")
                    rBtn.BackgroundColor3 = rVal and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
                end
            end
            updateCategoryDropdownTitle(catKey)
        end
    end
end

-- Synchronize and display updated settings cleanly
if UI.minDistInput then UI.minDistInput.Text = tostring(SETTINGS.MinDistance) end
if UI.maxDistInput then UI.maxDistInput.Text = tostring(SETTINGS.MaxDistance) end
if UI.atkReachInput then UI.atkReachInput.Text = tostring(SETTINGS.AttackReach) end
if UI.atkDelayInput then UI.atkDelayInput.Text = tostring(SETTINGS.AttackCooldown) end
if UI.dodgeBufferInput then UI.dodgeBufferInput.Text = tostring(SETTINGS.DodgeBuffer) end
if UI.wpTriggerInput then UI.wpTriggerInput.Text = tostring(SETTINGS.WaypointTriggerDist) end
if UI.maxNodeDistInput then UI.maxNodeDistInput.Text = tostring(SETTINGS.MaxNodeDistance) end
if UI.wallRayInput then UI.wallRayInput.Text = tostring(SETTINGS.WallRayLength) end
if UI.partySizeInput then UI.partySizeInput.Text = tostring(SETTINGS.TargetPartySize) end
if UI.noEnemyDelayInput then UI.noEnemyDelayInput.Text = tostring(SETTINGS.NoEnemyDelay) end
if UI.customTargetInput then UI.customTargetInput.Text = SETTINGS.CustomTargetName end
if UI.customRangeInput then UI.customRangeInput.Text = tostring(SETTINGS.CustomTargetExtraRange) end
if UI.ignoreEnemyInput then UI.ignoreEnemyInput.Text = SETTINGS.IgnoreEnemyNames end
if UI.eifDelayInput then UI.eifDelayInput.Text = tostring(SETTINGS.EIFSpammerDelay) end
if UI.replayTimeInput then UI.replayTimeInput.Text = SETTINGS.ReplayTime end
if UI.filterInput then UI.filterInput.Text = SETTINGS.IgnoreKeywords end
if UI.joinNameInput then UI.joinNameInput.Text = SETTINGS.JoinPlayerName end
if UI.webhookInput then UI.webhookInput.Text = SETTINGS.Webhook or "" end
if UI.webhookLogoInput then UI.webhookLogoInput.Text = SETTINGS.WebhookLogo or "" end

if UI.autoLobbyRow then
    UI.autoLobbyRow.Text = "Auto Lobby Routine: " .. (SETTINGS.AutoLobbyEnabled and "ON" or "OFF")
    UI.autoLobbyRow.BackgroundColor3 = SETTINGS.AutoLobbyEnabled and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
end
if UI.roleRow then UI.roleRow.Text = "Lobby Role: " .. SETTINGS.LobbyMode:upper() end
if UI.repDiscRow then
    UI.repDiscRow.Text = "Replay on Disconnects: " .. (SETTINGS.ReplayOnDisconnect and "ON" or "OFF")
    UI.repDiscRow.BackgroundColor3 = SETTINGS.ReplayOnDisconnect and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
end
if UI.rejDiscRow then
    UI.rejDiscRow.Text = "Rejoin on Disconnect: " .. (SETTINGS.RejoinOnDisconnect and "ON" or "OFF")
    UI.rejDiscRow.BackgroundColor3 = SETTINGS.RejoinOnDisconnect and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
end

if UI.diffDropdown then UI.diffDropdown:SetValue(SETTINGS.LobbyDifficulty) end
if UI.autoSellToggleBtn then
    UI.autoSellToggleBtn.Text = "Auto Sell: " .. (SETTINGS.AutoSellEnabled and "ON" or "OFF")
    UI.autoSellToggleBtn.BackgroundColor3 = SETTINGS.AutoSellEnabled and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
end
if UI.hcRow then
    UI.hcRow.Text = "Hardcore Mode: " .. (SETTINGS.LobbyHardcore and "ON" or "OFF")
    UI.hcRow.BackgroundColor3 = SETTINGS.LobbyHardcore and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
end
if UI.privRow then
    UI.privRow.Text = "Private Lobby: " .. (SETTINGS.LobbyPrivate and "ON" or "OFF")
    UI.privRow.BackgroundColor3 = SETTINGS.LobbyPrivate and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
end
if UI.waitForPlayersRow then
    UI.waitForPlayersRow.Text = "Wait for Party in Dungeon: " .. (SETTINGS.WaitForPlayers and "ON" or "OFF")
    UI.waitForPlayersRow.BackgroundColor3 = SETTINGS.WaitForPlayers and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
end
if UI.autoDodgeRow then
    UI.autoDodgeRow.Text = "Auto Dodging: " .. (SETTINGS.AutoDodgeEnabled and "ON" or "OFF")
    UI.autoDodgeRow.BackgroundColor3 = SETTINGS.AutoDodgeEnabled and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
end
if UI.modeRow then UI.modeRow.Text = "Gameplay Mode: " .. SETTINGS.GameplayMode end
if UI.applyBlackScreen then UI.applyBlackScreen(SETTINGS.BlackScreen, true) end
if UI.customNameInput then UI.customNameInput.Text = SETTINGS.CustomName or "" end
if UI.partyNameRow then
    UI.partyNameRow.Text = "Rename Party Too: " .. (SETTINGS.RenameParty and "ON" or "OFF")
    UI.partyNameRow.BackgroundColor3 = SETTINGS.RenameParty and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
end
if UI.avatarRow then
    UI.avatarRow.Text = "Logo Avatar: " .. (SETTINGS.LogoAvatar and "ON" or "OFF")
    UI.avatarRow.BackgroundColor3 = SETTINGS.LogoAvatar and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
end
if UI.refreshNames then UI.refreshNames() end
if UI.tradeNameInput then UI.tradeNameInput.Text = SETTINGS.TradeUsername or "" end
if UI.acceptNameInput then UI.acceptNameInput.Text = SETTINGS.AcceptUsername or "" end
if UI.autoAcceptRow then
    UI.autoAcceptRow.Text = "Auto Accept Trade: " .. (SETTINGS.AutoAcceptTrade and "ON" or "OFF")
    UI.autoAcceptRow.BackgroundColor3 = SETTINGS.AutoAcceptTrade and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
end
if UI.autoTradeRow then
    UI.autoTradeRow.Text = "Auto Send Trade: " .. (SETTINGS.AutoTrade and "ON" or "OFF")
    UI.autoTradeRow.BackgroundColor3 = SETTINGS.AutoTrade and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
end

if UI.eifToggleBtn then
    UI.eifToggleBtn.Text = "EIF Spammer: " .. (SETTINGS.EIFSpammerEnabled and "ON" or "OFF")
    UI.eifToggleBtn.BackgroundColor3 = SETTINGS.EIFSpammerEnabled and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
end
if UI.eifSlotBtn then UI.eifSlotBtn.Text = "EIF Slot: " .. SETTINGS.EIFSpammerSlot:upper() end

updateIgnoreKeywords()
updateIgnoreEnemyNames()

if cfg.SelectedMacro then selectedMacroName = cfg.SelectedMacro end
refreshMacroList()
end

local function loadConfigAndAutoExecute()
refreshMacroList()
if not readfile or not isfile or not isfile(CONFIG_FILE) then return end
local readSuccess, fileData = pcall(function() return readfile(CONFIG_FILE) end)
if not readSuccess or not fileData then return end
local success, cfg = pcall(function() return HttpService:JSONDecode(fileData) end)

if success and type(cfg) == "table" then
    applyConfigData(cfg)

    if SETTINGS.Autoplay == true then
        if selectedMacroName ~= "" then loadMacroFromFile(selectedMacroName) end
        isAutoplay = true
        if humanoid then
            if SETTINGS.GameplayMode == "Manual Play" then
                humanoid.AutoRotate = true
                humanoid.WalkSpeed = 16
                if alignOrient then alignOrient.Enabled = false end
            else
                humanoid.WalkSpeed = (SETTINGS.GameplayMode == "Legit Player") and 16 or MOVE_SPEED
                humanoid.AutoRotate = false
                if alignOrient then alignOrient.Enabled = true end
            end
        end
        if UI.runMacroBtn then
            UI.runMacroBtn.Text = "■  STOP AUTOPLAY"
            UI.runMacroBtn.BackgroundColor3 = UI.theme.pink
        end
        if SETTINGS.AutoHideUI and UI.setMinimized then
            task.delay(2, function() if isAutoplay then UI.setMinimized(true) end end)
        end
    end
end
end

-- 6. CHARACTER & HAZARD HANDLERS

local function cleanupPartConnections(obj)
if hazardSignals[obj] then
for _, conn in ipairs(hazardSignals[obj]) do conn:Disconnect() end
hazardSignals[obj] = nil
end
end

function cleanup()
isCleaningUp = true
isAutoplay = false
isRecording = false
isCasting = false
isDodgeBlinking = false

for _, conn in ipairs(connections) do pcall(function() conn:Disconnect() end) end
table.clear(connections)

for obj, _ in pairs(hazardSignals) do cleanupPartConnections(obj) end
table.clear(hazardSignals)
table.clear(activeHazards)
table.clear(hazardTracking)
table.clear(trackedHumanoids)
table.clear(cachedInviswalls)
table.clear(playerCharacters)
table.clear(parsedIgnoreEnemyNames)

for _, nodePart in ipairs(visualNodes) do if nodePart then nodePart:Destroy() end end
table.clear(visualNodes)
table.clear(waypoints)

if UI.avatarHolder then pcall(function() UI.avatarHolder:Destroy() end) end
if UI.avatarTarget and UI.avatarTarget.Parent then pcall(function() UI.avatarTarget.Visible = true end) end
if UI.hudLabels then
    for obj, info in pairs(UI.hudLabels) do
        pcall(function() obj.Text = info.original end)
    end
    table.clear(UI.hudLabels)
end
pcall(function() RunService:Set3dRenderingEnabled(true) end)
if UI.blackGui then UI.blackGui:Destroy() end
if UI.destroyRangeRings then UI.destroyRangeRings() end
if UI.screenGui then UI.screenGui:Destroy() end
if UI.keyGui then UI.keyGui:Destroy() end
if rootPart and rootPart:FindFirstChild("FacingAlign") then rootPart.FacingAlign:Destroy() end
if rootPart and rootPart:FindFirstChild("FacingAttachment") then rootPart.FacingAttachment:Destroy() end

if humanoid then
    humanoid.AutoRotate = true
    humanoid.WalkSpeed = 16
end
_G.TerminateHybridScriptUI = nil
end
_G.TerminateHybridScriptUI = cleanup

-- NAME SPOOF: your username (HUD, nameplate) and optionally your party's names.
-- The custom name can be changed live from the Misc tab.
local function getSpoofName()
    local custom = tostring(SETTINGS.CustomName or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if custom == "" then return SPOOF_NAME end
    return custom
end

_G.HudSpoofHistory = _G.HudSpoofHistory or {}
_G.HudSpoofHistory[getSpoofName():lower()] = true

-- lowercase text a label may show -> the Player it belongs to
local realNames = {}
local function rebuildRealNames()
    table.clear(realNames)
    for _, p in ipairs(Players:GetPlayers()) do
        realNames[p.Name:lower()] = p
        realNames[p.DisplayName:lower()] = p
    end
    -- spoof names left behind by earlier runs belong to you
    realNames["fvnito"] = player
    for name in pairs(_G.HudSpoofHistory) do realNames[name] = player end
end
rebuildRealNames()

UI.hudLabels = {}       -- label -> { owner = Player, original = text, upper = bool }
UI.partyIndex = {}
local nextPartyIndex = 2

local function desiredName(owner)
    if owner == player then return getSpoofName() end
    if SETTINGS.RenameParty then
        if not UI.partyIndex[owner] then
            UI.partyIndex[owner] = nextPartyIndex
            nextPartyIndex = nextPartyIndex + 1
        end
        return getSpoofName() .. " " .. UI.partyIndex[owner]
    end
    return nil
end

local function applyLabel(obj, restore)
    local info = UI.hudLabels[obj]
    if not info or isCleaningUp then return end
    local want = desiredName(info.owner)
    if want then
        if info.upper then want = want:upper() end
        if obj.Text ~= want then obj.Text = want end
    elseif restore and obj.Text ~= info.original then
        obj.Text = info.original
    end
end

local function trackLabel(obj, owner, forced)
    if UI.hudLabels[obj] then return end
    local text = obj.Text
    UI.hudLabels[obj] = {
        owner = owner,
        original = text,
        upper = (not forced) and text ~= "" and text == text:upper() and text:lower() ~= text,
    }
    table.insert(connections, obj:GetPropertyChangedSignal("Text"):Connect(function() applyLabel(obj) end))
    applyLabel(obj)
end

local function checkLabel(obj)
    if UI.hudLabels[obj] or obj.Name == "NCLLogoText" then return end
    local owner = realNames[obj.Text:lower()]
    if owner then trackLabel(obj, owner) end
end

local function spoofHudLabel(obj)
    if not (obj:IsA("TextLabel") or obj:IsA("TextButton")) then return end
    if obj.Name == "NCLLogoText" then return end
    if UI.screenGui and obj:IsDescendantOf(UI.screenGui) then return end
    checkLabel(obj)
    table.insert(connections, obj:GetPropertyChangedSignal("Text"):Connect(function() checkLabel(obj) end))
end

function UI.refreshNames()
    rebuildRealNames()
    for obj in pairs(UI.hudLabels) do
        if obj.Parent then applyLabel(obj, true) else UI.hudLabels[obj] = nil end
    end
end

function UI.applyCustomName(name)
    name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    SETTINGS.CustomName = name
    _G.HudSpoofHistory[getSpoofName():lower()] = true
    UI.refreshNames()
    saveConfig()
    setStatus("Custom name set to: " .. getSpoofName(), true)
end

task.spawn(function()
    local pGui = player:WaitForChild("PlayerGui", 10)
    if not pGui then return end
    for _, obj in ipairs(pGui:GetDescendants()) do spoofHudLabel(obj) end
    table.insert(connections, pGui.DescendantAdded:Connect(spoofHudLabel))
end)

-- name plates above characters
local function plateFor(char, owner)
    if not char then return end
    task.spawn(function()
        local nameplate = char:WaitForChild("playerNameplate", 5)
        local frame = nameplate and nameplate:WaitForChild("Frame", 2)
        local nameLbl = frame and frame:WaitForChild("name", 2)
        if nameLbl then trackLabel(nameLbl, owner, true) end
    end)
end

local function applyFakeName(char)
    plateFor(char, player)
end

local function hookPartyPlates(p)
    if p == player then return end
    if p.Character then plateFor(p.Character, p) end
    table.insert(connections, p.CharacterAdded:Connect(function(c) plateFor(c, p) end))
end
for _, p in ipairs(Players:GetPlayers()) do hookPartyPlates(p) end
table.insert(connections, Players.PlayerAdded:Connect(function(p)
    rebuildRealNames()
    hookPartyPlates(p)
end))

-- AVATAR: replaces your portrait in the HUD (top-left) with the logo
local function scoreAvatarCandidate(obj, label)
    local isView = obj:IsA("ViewportFrame")
    local isImage = obj:IsA("ImageLabel") or obj:IsA("ImageButton")
    if not (isView or isImage) then return nil end
    local a = obj.AbsoluteSize
    if a.X < 40 or a.X > 220 or a.Y < 40 or a.Y > 260 then return nil end
    if isImage then
        local img = obj.Image:lower()
        if not (img:find(tostring(player.UserId), 1, true) or img:find("headshot", 1, true) or img:find("thumb", 1, true) or img:find("avatar", 1, true)) then
            return nil
        end
    end
    -- the portrait sits to the left of the name and on roughly the same row
    local pos = obj.AbsolutePosition
    local lpos, lsize = label.AbsolutePosition, label.AbsoluteSize
    if pos.X + a.X > lpos.X + 40 then return nil end
    if math.abs((pos.Y + a.Y / 2) - (lpos.Y + lsize.Y / 2)) > 130 then return nil end
    return a.X * a.Y
end

local function findAvatarTarget()
    for label, info in pairs(UI.hudLabels) do
        if info.owner == player and label.Parent then
            local screen = label:FindFirstAncestorOfClass("ScreenGui")
            if screen and (not UI.screenGui or not label:IsDescendantOf(UI.screenGui)) then
                local best, bestScore
                for _, obj in ipairs(screen:GetDescendants()) do
                    if not (UI.avatarHolder and obj:IsDescendantOf(UI.avatarHolder)) then
                        local score = scoreAvatarCandidate(obj, label)
                        if score and (not bestScore or score > bestScore) then best, bestScore = obj, score end
                    end
                end
                if best then return best end
            end
        end
    end
    return nil
end

local function restoreAvatar()
    if UI.avatarHolder then UI.avatarHolder:Destroy() end
    UI.avatarHolder = nil
    if UI.avatarTarget and UI.avatarTarget.Parent then UI.avatarTarget.Visible = true end
    UI.avatarTarget = nil
end

local function swapAvatar(target)
    local holder = Instance.new("Frame")
    holder.Name = "NCLAvatar"
    holder.AnchorPoint = target.AnchorPoint
    holder.Position = target.Position
    holder.Size = target.Size
    holder.ZIndex = target.ZIndex + 50
    holder.LayoutOrder = target.LayoutOrder
    holder.BackgroundColor3 = Color3.fromRGB(46, 46, 50)
    holder.BackgroundTransparency = 0
    holder.BorderSizePixel = 0
    holder.Parent = target.Parent
    local holderPad = Instance.new("UIPadding")
    holderPad.PaddingTop = UDim.new(0, 6)
    holderPad.PaddingBottom = UDim.new(0, 6)
    holderPad.PaddingLeft = UDim.new(0, 6)
    holderPad.PaddingRight = UDim.new(0, 6)
    holderPad.Parent = holder
    -- the game HUD may use Global z-index ordering, so the logo needs a z-index above the holder
    createLogoMark(holder, holder.ZIndex + 1)
    target.Visible = false
    table.insert(connections, target:GetPropertyChangedSignal("Visible"):Connect(function()
        if UI.avatarHolder == holder and target.Visible then target.Visible = false end
    end))
    UI.avatarHolder, UI.avatarTarget = holder, target
end

function UI.refreshAvatar()
    -- the black screen shows its own clean layout, so drop the HUD icon swap while it is on
    if SETTINGS.LogoAvatar and not SETTINGS.BlackScreen then
        if not (UI.avatarHolder and UI.avatarHolder.Parent) then
            restoreAvatar()
            local target = findAvatarTarget()
            if target then swapAvatar(target) end
        end
    else
        restoreAvatar()
    end
end

task.spawn(function()
    while not isCleaningUp do
        pcall(UI.refreshAvatar)
        task.wait(2)
    end
end)
local attachment, alignOrient
local function setupCharacterConstraints(newChar)
character = newChar
humanoid = character:WaitForChild("Humanoid", 5)
rootPart = character:WaitForChild("HumanoidRootPart", 5)
if not humanoid or not rootPart then return end

local normalSpeed = 16
local shouldAlign = false

if isAutoplay and SETTINGS.GameplayMode ~= "Manual Play" then
    normalSpeed = (SETTINGS.GameplayMode == "Legit Player") and 16 or MOVE_SPEED
    shouldAlign = true
end

humanoid.WalkSpeed = normalSpeed
humanoid.AutoRotate = not shouldAlign

local oldAlign = rootPart:FindFirstChild("FacingAlign")
local oldAttach = rootPart:FindFirstChild("FacingAttachment")
if oldAlign then oldAlign:Destroy() end
if oldAttach then oldAttach:Destroy() end

attachment = Instance.new("Attachment")
attachment.Name = "FacingAttachment"
attachment.Parent = rootPart
alignOrient = Instance.new("AlignOrientation")
alignOrient.Name = "FacingAlign"
alignOrient.Mode = Enum.OrientationAlignmentMode.OneAttachment
alignOrient.Attachment0 = attachment
alignOrient.Responsiveness = 200
alignOrient.MaxTorque = math.huge
alignOrient.RigidityEnabled = true
alignOrient.CFrame = rootPart.CFrame
alignOrient.Enabled = shouldAlign
alignOrient.Parent = rootPart

traversingManualNodes = false
currentWaypointIndex = 1
activeDodgePoint = nil
isDodgeBlinking = false
hasReturnedToLobby = false
partyWasFull = false
hasReplayedFromTime = false
characterSpawnTime = os.clock()
postDodgeHoldUntil = 0
lastEnemySeenTime = os.clock()
lastStartValueTime = os.clock()
evadingDisplayUntil = 0
rebuildIgnoreList()

local diedConn
diedConn = humanoid.Died:Connect(function()
    traversingManualNodes = false
    currentWaypointIndex = 1
    activeDodgePoint = nil
    isDodgeBlinking = false
    characterSpawnTime = os.clock()
    postDodgeHoldUntil = 0
    setStatus("Status: Died -- nodes reset")
    diedConn:Disconnect()
end)
table.insert(connections, diedConn)
applyFakeName(character)
end
if character then setupCharacterConstraints(character) end
table.insert(connections, player.CharacterAdded:Connect(setupCharacterConstraints))

local function hasSpawnShield()
if not character or not character.Parent then return false end
if (os.clock() - characterSpawnTime) > SPAWN_SHIELD_DURATION then return false end
if character:FindFirstChildOfClass("ForceField") then return true end
for _, child in ipairs(character:GetChildren()) do
if not child:IsA("Accessory") and not child:IsA("Tool") and not child:IsA("Clothing") then
local name = child.Name:lower()
if name:find("spawnshield") or name:find("forcefield") or name:find("invuln") or name:find("immunity") then return true end
end
end
return false
end

-- Target choice: nearest enemy, but enemies behind walls count as 15 studs farther, and the current target keeps an
-- 8 stud bonus so the script does not flip between two enemies at similar range. Rescans every 0.15 s.
local function isUsableTarget(mob)
    if not mob or not mob.Parent or mob == character or isIgnoredEnemy(mob) then return false end
    local hum = mob:FindFirstChildOfClass("Humanoid")
    return hum ~= nil and hum.Health > 0 and mob:FindFirstChild("HumanoidRootPart") ~= nil
end

local function findBestTarget()
    local now = os.clock()
    local current = UI.currentTarget
    if current and not isUsableTarget(current) then current = nil; UI.currentTarget = nil end
    if current and now - (UI.lastTargetScan or 0) < 0.15 then return current end
    UI.lastTargetScan = now

    local origin = rootPart.Position
    local candidates = {}
    for hum, _ in pairs(trackedHumanoids) do
        if hum and hum.Parent and hum.Health > 0 then
            local mob = hum.Parent
            if mob:IsA("Model") and mob ~= character and not Players:GetPlayerFromCharacter(mob) and not isIgnoredEnemy(mob) then
                local mobRoot = mob:FindFirstChild("HumanoidRootPart")
                if mobRoot then table.insert(candidates, { mob = mob, pos = mobRoot.Position }) end
            end
        elseif not hum or not hum.Parent then
            trackedHumanoids[hum] = nil
        end
    end

    -- score = distance, -5 per pack mate within 22 studs (max 4), +6 behind a wall, -8 for the current target.
    -- The pack bonus makes it walk to the group instead of picking off one loose enemy.
    local best, bestScore = nil, math.huge
    for _, c in ipairs(candidates) do
        local dist = (c.pos - origin).Magnitude
        local score = dist
        if dist < 90 then
            local hit = Workspace:Raycast(origin + Vector3.new(0, 1.8, 0), c.pos - origin, raycastParams)
            if hit and hit.Instance and hit.Instance.CanCollide and not hit.Instance:IsDescendantOf(c.mob) then score = score + 6 end
        end
        local mates = 0
        for _, o in ipairs(candidates) do
            if o ~= c and (o.pos - c.pos).Magnitude <= 22 then mates = mates + 1 end
        end
        score = score - math.min(mates, 4) * 5
        if c.mob == current then score = score - 8 end
        if score < bestScore then bestScore = score; best = c.mob end
    end
    UI.currentTarget = best
    return best
end

-- Target attack indicators and spell zones
local HAZARD_KEYWORDS = {
"telegraph", "indicator", "warning", "marker", "aoe", "hazard", "danger",
"hitbox", "damage", "hurt", "cast", "spikes", "blast", "explosion",
"meteor", "zone", "strike", "burst", "slash", "ring", "spell"
}

local function scoreHazardPart(obj)
if not obj:IsA("BasePart") then return 0 end
if isPlayerOrTeammatePart(obj) then return 0 end
if isMobLimb(obj) then return 0 end
if isDecoration(obj) then return 0 end

local score = 0
local name = obj.Name:lower()

-- lightning / beam style attacks: a neon part of any color that appeared during the fight and is long and thin
local born = UI.partBorn and UI.partBorn[obj]
if born and os.clock() - born < 15 and obj.Material == Enum.Material.Neon and obj.Transparency < 1 then
    local sz = obj.Size
    if math.max(sz.X, sz.Y, sz.Z) >= 10 and math.min(sz.X, sz.Y, sz.Z) <= 8 then
        local model = obj:FindFirstAncestorOfClass("Model")
        if not (model and model:FindFirstChildOfClass("Humanoid")) then score = score + 3 end
    end
end

for _, kw in ipairs(HAZARD_KEYWORDS) do 
    if name:find(kw) then score = score + 3; break end 
end

if obj.Material == Enum.Material.Neon then
    score = score + 2
    local col = obj.Color
    -- Bright red, orange, or magenta indicators
    if (col.R > 0.5 and col.G < 0.45) or (col.R > 0.6 and col.B > 0.4 and col.G < 0.3) then 
        score = score + 2 
    end
end

if obj.Transparency > 0 and obj.Transparency < 1 then 
    score = score + 1 
end

if obj:FindFirstChildOfClass("ParticleEmitter") or obj:FindFirstChildOfClass("Fire") then
    if score >= 2 then
        score = score + 2
    end
end

return score
end

local function evaluateAndAddHazardPart(obj)
if not obj:IsA("BasePart") then return end
if obj.Name == "Terrain" or obj.Name == "Baseplate" then return end

local score = scoreHazardPart(obj)
if score >= 3 then 
    activeHazards[obj] = true 
else 
    activeHazards[obj] = nil 
end
end

local function bindHazardEvents(obj)
cleanupPartConnections(obj)
local function onPropChanged() evaluateAndAddHazardPart(obj) end
hazardSignals[obj] = {
obj:GetPropertyChangedSignal("Transparency"):Connect(onPropChanged),
obj:GetPropertyChangedSignal("Color"):Connect(onPropChanged),
obj:GetPropertyChangedSignal("Size"):Connect(onPropChanged)
}
end

local function handleInviswall(obj)
if obj.Name:lower() == "inviswall" and obj:IsA("BasePart") then
cachedInviswalls[obj] = true
if math.max(obj.Size.X, obj.Size.Y, obj.Size.Z) < 80 then
obj.CanCollide = false
obj.Transparency = 1
if not obj:FindFirstChildOfClass("PathfindingModifier") then
local mod = Instance.new("PathfindingModifier")
mod.PassThrough = true
mod.Parent = obj
end
end
end
end

-- attacks that appear DURING the fight (lightning beams etc.): remember when parts were created and track Beam objects.
-- Everything that already exists when the script starts is treated as map scenery and ignored by this.
UI.partBorn = setmetatable({}, { __mode = "k" })
UI.activeBeams = setmetatable({}, { __mode = "k" })

local function onDescendantAdded(child)
if UI.initialScanDone then
    if child:IsA("BasePart") then UI.partBorn[child] = os.clock() end
    if child:IsA("Beam") then UI.activeBeams[child] = true end
end
if child.Name == "Terrain" or child.Name == "Baseplate" or child:IsA("Camera") then return end
handleInviswall(child)
if child:IsA("BasePart") then
evaluateAndAddHazardPart(child); bindHazardEvents(child)
elseif child:IsA("Model") or child:IsA("Folder") then
for _, desc in ipairs(child:GetDescendants()) do
if desc:IsA("BasePart") then handleInviswall(desc); evaluateAndAddHazardPart(desc); bindHazardEvents(desc)
elseif desc:IsA("Humanoid") then trackedHumanoids[desc] = true end
end
end
if child:IsA("Humanoid") then trackedHumanoids[child] = true end
end

table.insert(connections, Workspace.DescendantAdded:Connect(onDescendantAdded))
table.insert(connections, Workspace.DescendantRemoving:Connect(function(child)
cleanupPartConnections(child)
if activeHazards[child] then activeHazards[child] = nil; hazardTracking[child] = nil end
if trackedHumanoids[child] then trackedHumanoids[child] = nil end
if cachedInviswalls[child] then cachedInviswalls[child] = nil end
if child:IsA("Model") or child:IsA("Folder") then
for _, desc in ipairs(child:GetDescendants()) do
cleanupPartConnections(desc)
if activeHazards[desc] then activeHazards[desc] = nil; hazardTracking[desc] = nil end
if trackedHumanoids[desc] then trackedHumanoids[desc] = nil end
end
end
end))
for _, child in ipairs(Workspace:GetChildren()) do onDescendantAdded(child) end
UI.initialScanDone = true

local function getDangerousHazards(playerPos)
local hazards = {}
local now = os.clock()

for part, _ in pairs(activeHazards) do
    if part and part.Parent then
        if part.Transparency < 1 then
            if (part.Position - playerPos).Magnitude > 140 then continue end
            local name = part.Name:lower()
            local isIgnored = false
            for _, kw in ipairs(parsedIgnoreKeywords) do if name:find(kw) then isIgnored = true; break end end

            if not isIgnored and math.max(part.Size.X, part.Size.Y, part.Size.Z) <= 300 then
                local currentPos = part.Position
                local velocity = part.AssemblyLinearVelocity or Vector3.zero

                if hazardTracking[part] then
                    local dt = now - hazardTracking[part].lastTime
                    if dt > 0.01 then
                        velocity = (currentPos - hazardTracking[part].lastPos) / dt
                        hazardTracking[part] = {lastPos = currentPos, lastTime = now, velocity = velocity}
                    else velocity = hazardTracking[part].velocity end
                else
                    hazardTracking[part] = {lastPos = currentPos, lastTime = now, velocity = velocity}
                end

                local shape = "Box"
                if part:IsA("Part") then
                    if part.Shape == Enum.PartType.Ball then shape = "Ball"
                    elseif part.Shape == Enum.PartType.Cylinder then shape = "Cylinder" end
                end

                table.insert(hazards, { cframe = part.CFrame, size = part.Size, name = part.Name, velocity = velocity, shape = shape })
            end
        end
    else
        cleanupPartConnections(part); activeHazards[part] = nil; hazardTracking[part] = nil
    end
end
-- Beam objects created during the fight become a box along the beam (width x 8 tall x length)
for beam in pairs(UI.activeBeams) do
    if not beam.Parent then
        UI.activeBeams[beam] = nil
    elseif beam.Enabled and beam.Attachment0 and beam.Attachment1
        and not isPlayerOrTeammatePart(beam.Attachment0.Parent) and not isPlayerOrTeammatePart(beam.Attachment1.Parent) then
        local a, b = beam.Attachment0.WorldPosition, beam.Attachment1.WorldPosition
        local len = (b - a).Magnitude
        if len > 6 and len < 250 and (a - playerPos).Magnitude < 260 then
            local width = math.max(beam.Width0, beam.Width1, 4)
            table.insert(hazards, { cframe = CFrame.lookAt((a + b) / 2, b), size = Vector3.new(width, 8, len), name = "Beam", velocity = Vector3.zero, shape = "Box" })
        end
    end
end
return hazards
end

-- Flat ground telegraphs (thin, lying horizontally) are measured on the ground plane only, so being a few studs
-- above them (jumping, stairs, tall character) no longer hides the danger. Vertical reach is capped at 9 studs.
local function getDistanceToHazard(localP, hazard)
local s, cf = hazard.size, hazard.cframe
if hazard.shape == "Ball" then return localP.Magnitude - (math.min(s.X, s.Y, s.Z) / 2)
elseif hazard.shape == "Cylinder" then
local radial = math.sqrt(localP.Y^2 + localP.Z^2) - (math.max(s.Y, s.Z) / 2)
local axial = math.abs(localP.X) - (s.X / 2)
if s.X <= 3 and math.abs(cf.RightVector.Y) > 0.7 then -- flat disc: axis (local X) points up
    if axial > 9 then return math.huge end
    return radial
end
return math.max(radial, axial)
else
local ax, sz = { localP.X, localP.Y, localP.Z }, { s.X, s.Y, s.Z }
local axes = { cf.RightVector, cf.UpVector, cf.LookVector }
local thin = 1
for i = 2, 3 do if sz[i] < sz[thin] then thin = i end end
if sz[thin] <= 3 and math.abs(axes[thin].Y) > 0.7 then -- flat slab lying on the ground
    if math.abs(ax[thin]) - sz[thin] / 2 > 9 then return math.huge end
    local d = -math.huge
    for i = 1, 3 do
        if i ~= thin then d = math.max(d, math.abs(ax[i]) - sz[i] / 2) end
    end
    return d
end
return math.max(math.abs(ax[1]) - sz[1] / 2, math.abs(ax[2]) - sz[2] / 2, math.abs(ax[3]) - sz[3] / 2)
end
end

local function isPointInDanger(point, hazards, margin)
local buffer = SETTINGS.DodgeBuffer + (margin or 0)
local minHazardDist = math.huge
for _, hazard in ipairs(hazards) do
local dEdge = getDistanceToHazard(hazard.cframe:PointToObjectSpace(point), hazard)
if dEdge < minHazardDist then minHazardDist = dEdge end
if dEdge <= buffer then return true, hazard.name, hazard, minHazardDist end

    if hazard.velocity.Magnitude > 4 then
        for t = 0.15, 0.75, 0.2 do
            local futurePos = hazard.cframe.Position + (hazard.velocity * t)
            local fdEdge = getDistanceToHazard((hazard.cframe - hazard.cframe.Position + futurePos):PointToObjectSpace(point), hazard)
            if fdEdge < minHazardDist then minHazardDist = fdEdge end
            if fdEdge <= (buffer * 2) then return true, hazard.name .. " (Incoming)", hazard, minHazardDist end
        end
    end
end
return false, nil, nil, minHazardDist
end

local function getGlidedTargetPos(startPos, rawTargetPos)
local moveVector = (rawTargetPos - startPos)
local dist = moveVector.Magnitude
if dist < 0.2 then return rawTargetPos end
local moveDir = Vector3.new(moveVector.X, 0, moveVector.Z).Unit

for _, angle in ipairs({0, math.rad(32), math.rad(-32)}) do
    local rayResult = Workspace:Raycast(startPos, (CFrame.Angles(0, angle, 0) * moveDir) * SETTINGS.WallRayLength, raycastParams)
    if rayResult and rayResult.Instance and rayResult.Instance.CanCollide then
        if math.abs(rayResult.Normal.Y) < 0.7 then
            local slideDir = moveDir - (moveDir:Dot(rayResult.Normal) * rayResult.Normal)
            local flatSlide = Vector3.new(slideDir.X, 0, slideDir.Z)
            if flatSlide.Magnitude > 0.05 then return startPos + (flatSlide.Unit * math.min(dist, 10)) end
        end
    end
end
return rawTargetPos
end

local activePathWaypoints, pathIndex = {}, 1
local lastPathComputeTime = 0
local pathObject = PathfindingService:CreatePath({AgentRadius = 2.5, AgentHeight = 5.0, AgentCanJump = true, AgentCanClimb = false, WaypointSpacing = 10})

local function isValidTeleport(startPos, endPos)
local direction = endPos - startPos
local wallRayResult = Workspace:Raycast(startPos, direction, teleportRayParams)
if wallRayResult and wallRayResult.Instance and wallRayResult.Instance.CanCollide then
local hitModel = wallRayResult.Instance:FindFirstAncestorOfClass("Model")
local isEntity = hitModel and (hitModel:FindFirstChildOfClass("Humanoid") or Players:GetPlayerFromCharacter(hitModel))
if not isEntity then return false end
end
local groundRayResult = Workspace:Raycast(endPos + Vector3.new(0, 3.5, 0), Vector3.new(0, -28.5, 0), teleportRayParams)
if not groundRayResult or not groundRayResult.Instance or not groundRayResult.Instance.CanCollide then return false end
return (endPos.Y - groundRayResult.Position.Y) >= -1.0 and (endPos.Y - groundRayResult.Position.Y) <= 10.0
end

local stuckCheckPos, stuckCheckTime = Vector3.zero, os.clock()
local lastTpDodgeTime = 0

local function executeSafeBlink(destination, facingPos)
if isDodgeBlinking or not rootPart or not humanoid or humanoid.Health <= 0 then return end
isDodgeBlinking = true

rootPart.AssemblyLinearVelocity = Vector3.zero 

local lookTarget = facingPos or destination
rootPart.CFrame = CFrame.new(destination, Vector3.new(lookTarget.X, destination.Y, lookTarget.Z))

task.delay(0.1, function() isDodgeBlinking = false end)
postDodgeHoldUntil = os.clock() + 0.35
end

-- SMARTER DODGING (kept on the UI table to stay under Luau's local limit)

-- true when walking the straight line from fromPos to toPos would run through any of the given hazards
function UI.isPathBlocked(fromPos, toPos, hazards, margin)
    if #hazards == 0 then return false end
    local delta = toPos - fromPos
    local dist = delta.Magnitude
    if dist < 0.5 then return false end
    local steps = math.clamp(math.ceil(dist / 3), 1, 12)
    for i = 1, steps do
        if isPointInDanger(fromPos + delta * (i / steps), hazards, margin) then return true end
    end
    return false
end

-- Picks the best safe spot to dodge to. First pass wants a 2 stud extra safety margin and a route that does not
-- cross other attack zones; if nothing qualifies it relaxes both, then falls back to the "least bad" spot.
function UI.findDodgePoint(playerPos, enemyPos, hazards)
    local idealCombatDist = (SETTINGS.MinDistance + SETTINGS.MaxDistance) * 0.5
    local others = {} -- hazards we are NOT standing in (the route out of the current one is allowed to cross it)
    for _, h in ipairs(hazards) do
        if not isPointInDanger(playerPos, { h }, 0) then table.insert(others, h) end
    end
    local bestExit, bestExitClearance = nil, -math.huge
    local hasEnemy = (enemyPos - playerPos).Magnitude > 0.5
    -- dodging should not drag you out of attack range or into the enemy's face
    local function rangePenalty(pos)
        if not hasEnemy then return 0 end
        local d = (pos - enemyPos).Magnitude
        if d > SETTINGS.AttackReach then return (d - SETTINGS.AttackReach) * 0.5 end
        if d < SETTINGS.MinDistance then return (SETTINGS.MinDistance - d) * 0.4 end
        return 0
    end
    for pass = 1, 2 do
        local margin = (pass == 1) and 2 or 0
        local best, bestScore = nil, math.huge
        for _, dist in ipairs({2, 3.5, 5, 7, 9, 12, 16, 20, 25, 30, 38}) do
            for _, dir in ipairs(DODGE_DIRECTIONS) do
                local candidate = playerPos + dir * dist
                local inDanger, _, _, clearance = isPointInDanger(candidate, hazards, margin)
                if not inDanger then
                    local score = (dist <= 8 and -45 or 0) - math.min(clearance, 12) + dist * 0.35 + math.abs((candidate - enemyPos).Magnitude - idealCombatDist) * 0.04 + rangePenalty(candidate)
                    if score < bestScore and (pass == 2 or not UI.isPathBlocked(playerPos, candidate, others, 0)) and isValidTeleport(playerPos, candidate) then
                        best, bestScore = candidate, score
                    end
                elseif pass == 1 and clearance > bestExitClearance then
                    bestExit, bestExitClearance = candidate, clearance
                end
            end
        end
        if best then return best end
    end
    if bestExit and isValidTeleport(playerPos, bestExit) then return bestExit end
    return nil
end

-- Backpedal spot: straight away from the enemy, or 40 / 80 degrees to either side when a wall or an attack zone is there.
function UI.pickRetreatPos(playerPos, enemyPos, hazards)
    local away = Vector3.new(playerPos.X - enemyPos.X, 0, playerPos.Z - enemyPos.Z)
    if away.Magnitude < 0.1 then away = Vector3.new(1, 0, 0) end
    away = away.Unit
    for _, deg in ipairs({ 0, 40, -40, 80, -80 }) do
        local dir = CFrame.Angles(0, math.rad(deg), 0) * away
        local pos = playerPos + dir * 6
        local wall = Workspace:Raycast(playerPos + Vector3.new(0, 1.5, 0), dir * 7, raycastParams)
        local blocked = wall and wall.Instance and wall.Instance.CanCollide and math.abs(wall.Normal.Y) < 0.7
        if not blocked and not isPointInDanger(pos, hazards, 0) then return pos end
    end
    return playerPos + away * 6
end

-- MoveTo that will not walk you into an attack zone: if the next ~14 studs of the route cross one it waits
-- (max 1.5 s so a stuck/false-positive zone can never freeze the macro), otherwise it just moves.
function UI.moveAvoiding(targetPos, hazards)
    if #hazards > 0 and SETTINGS.AutoDodgeEnabled and SETTINGS.GameplayMode ~= "Ultra Carry Mode" and not hasSpawnShield() then
        local pos = rootPart.Position
        local toTarget = targetPos - pos
        local lookDist = math.min(toTarget.Magnitude, 14)
        if lookDist > 0.5 and UI.isPathBlocked(pos, pos + toTarget.Unit * lookDist, hazards, 0) then
            local now = os.clock()
            if not UI.moveHoldSince then UI.moveHoldSince = now end
            if now - UI.moveHoldSince < 1.5 then
                setStatus("Status: Holding - attack zone ahead")
                humanoid:MoveTo(pos)
                return
            end
        else
            UI.moveHoldSince = nil
        end
    else
        UI.moveHoldSince = nil
    end
    humanoid:MoveTo(targetPos)
end

-- 7. UNIFIED MAIN LOOP

local lastAttackSequenceTime = 0

local function getEffectiveAttackReach(target)
local reach = SETTINGS.AttackReach
if target and SETTINGS.CustomTargetName ~= "" and (SETTINGS.CustomTargetExtraRange > 0) then
if string.find(target.Name:lower(), SETTINGS.CustomTargetName:lower(), 1, true) then
reach = reach + SETTINGS.CustomTargetExtraRange
end
end
return reach
end

local mainConnection = RunService.Heartbeat:Connect(function(deltaTime)
if not isAutoplay then return end

if isInLobby() then
    -- release the facing lock in the lobby so the player can turn freely
    if alignOrient and alignOrient.Enabled then alignOrient.Enabled = false end
    if humanoid and not humanoid.AutoRotate then humanoid.AutoRotate = true end
    UI.hostSeen, UI.hostMissingSince = false, nil
    handleLobbyAutomation()
    return
end

-- FOLLOW HOST: once the host has been in this dungeon, leave to the lobby 3 s after they disappear from the server
if SETTINGS.FollowHost and SETTINGS.JoinPlayerName ~= "" then
    local hostName = SETTINGS.JoinPlayerName:lower()
    local hostHere = false
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Name:lower() == hostName or p.DisplayName:lower() == hostName then hostHere = true; break end
    end
    if hostHere then
        UI.hostSeen, UI.hostMissingSince = true, nil
    elseif UI.hostSeen then
        UI.hostMissingSince = UI.hostMissingSince or os.clock()
        if os.clock() - UI.hostMissingSince >= 3 then
            UI.hostSeen, UI.hostMissingSince = false, nil
            setStatus("Status: Host left - leaving game...", true)
            pcall(function()
                local remotes = ReplicatedStorage:FindFirstChild("remotes")
                safeInvoke(remotes and remotes:FindFirstChild("ReturnToLobbyEvent"))
            end)
            return
        end
    end
end

-- Enforce AutoRotate state on every frame to prevent animation overrides
if SETTINGS.GameplayMode == "Manual Play" then
    if humanoid.AutoRotate == false then humanoid.AutoRotate = true end
    if alignOrient and alignOrient.Enabled then alignOrient.Enabled = false end
else
    -- facing lock is only applied while an enemy is targeted (see aim lock below)
end

local now = os.clock()
local othersInServer = #Players:GetPlayers() - 1
local currentlyWaitingForPlayers = false

if SETTINGS.LobbyMode == "Host" and not SETTINGS.FollowHost and SETTINGS.TargetPartySize > 0 then
    if othersInServer >= SETTINGS.TargetPartySize then partyWasFull = true end
    if othersInServer < SETTINGS.TargetPartySize and not partyWasFull and SETTINGS.WaitForPlayers then
        currentlyWaitingForPlayers = true
    end
    
    if partyWasFull and othersInServer < SETTINGS.TargetPartySize and SETTINGS.ReplayOnDisconnect then
        setStatus("Status: Player disconnected! Replaying...")
        partyWasFull = false
        fireReplayDungeonRemote()
        return
    end
end

if currentlyWaitingForPlayers then
    lastEnemySeenTime = now
    setStatus(string.format("Status: Waiting for players inside match... (%d/%d)", othersInServer, SETTINGS.TargetPartySize))
    return
end

if SETTINGS.LobbyMode == "Host" and not SETTINGS.FollowHost then
    if now - lastStartValueTime > 3.0 then
        lastStartValueTime = now
        pcall(function()
            local remotes = ReplicatedStorage:FindFirstChild("remotes")
            if remotes then
                local changeStartValue = remotes:FindFirstChild("changeStartValue")
                safeInvoke(changeStartValue)
            end
        end)
    end
end

if not humanoid or humanoid.Health <= 0 or not rootPart or isDodgeBlinking or hasReturnedToLobby then return end
local playerPos = rootPart.Position

-- in-game auto sell: every 8 s, sells the rarities ticked in the Auto Sell tab (before the inventory-full check)
if SETTINGS.AutoSellEnabled and now - (UI.lastAutoSell or 0) > 8.0 then
    UI.lastAutoSell = now
    pcall(executeAutoSell, true)
end

if now - lastInvCheckTime > 3.0 then
    lastInvCheckTime = now
    checkInventoryFull()
    if hasReturnedToLobby then return end
end

if SETTINGS.ReplayTime and SETTINGS.ReplayTime ~= "" and not hasReplayedFromTime then
    local timeGui = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("timeLeftGui")
    if timeGui then
        local timeFrame = findNested(timeGui, "Frame", "time")
        if timeFrame and timeFrame:IsA("TextLabel") and timeFrame.Text == SETTINGS.ReplayTime then
            hasReplayedFromTime = true
            setStatus("Status: Time reached! Replaying...")
            fireReplayDungeonRemote()
            return
        end
    end
end

local hazards = getDangerousHazards(playerPos)
local activeTarget = findBestTarget()

-- Continuous Aim Lock on Enemy
if activeTarget and activeTarget:FindFirstChild("HumanoidRootPart") then
    lastEnemySeenTime = now
    local enemyPos = activeTarget.HumanoidRootPart.Position
    local toEnemy = enemyPos - playerPos
    local flatToEnemy = Vector3.new(toEnemy.X, 0, toEnemy.Z)

    if SETTINGS.GameplayMode ~= "Manual Play" and alignOrient and alignOrient.Parent then
        local wasOff = not alignOrient.Enabled
        if wasOff then alignOrient.CFrame = rootPart.CFrame; alignOrient.Enabled = true end
        if humanoid.AutoRotate then humanoid.AutoRotate = false end
        if flatToEnemy.Magnitude > 0.1 then
            local look = CFrame.lookAt(playerPos, Vector3.new(enemyPos.X, playerPos.Y, enemyPos.Z))
            alignOrient.CFrame = look
            if wasOff then rootPart.CFrame = look end -- face the new target immediately
        end
    end
else
    -- no target: hold the current facing instead of a stale/default direction
    if alignOrient and alignOrient.Enabled then alignOrient.Enabled = false end
    if not humanoid.AutoRotate then humanoid.AutoRotate = true end
    if (now - lastEnemySeenTime) >= SETTINGS.NoEnemyDelay then
        setStatus("Status: No enemies found! Replaying...")
        lastEnemySeenTime = now + 9999 
        fireReplayDungeonRemote()
        return
    end
end

-- EIF BUFF SPAMMER
if SETTINGS.EIFSpammerEnabled and not isCasting and (now - lastEifSpamTime >= SETTINGS.EIFSpammerDelay) then
    lastEifSpamTime = now
    local slotKey = (SETTINGS.EIFSpammerSlot:upper() == "E") and Enum.KeyCode.E or Enum.KeyCode.Q
    task.spawn(function()
        VirtualInputManager:SendKeyEvent(true, slotKey, false, game)
        task.wait(0.04)
        VirtualInputManager:SendKeyEvent(false, slotKey, false, game)
    end)
end

-- GET CARRIED MODE
if SETTINGS.GameplayMode == "Get Carried Mode" then
    if (playerPos - stuckCheckPos).Magnitude < 0.75 then
        if now - stuckCheckTime > 5.0 then  
            humanoid.Jump = true
            stuckCheckTime = now 
        end
    else 
        stuckCheckPos = playerPos
        stuckCheckTime = now  
    end
    return 
end

-- COMBAT
if not isCasting and (now - lastAttackSequenceTime >= SETTINGS.AttackCooldown) then
    if activeTarget and activeTarget:FindFirstChild("HumanoidRootPart") then
        local tRoot = activeTarget.HumanoidRootPart
        local distToTarget = (playerPos - tRoot.Position).Magnitude
        local effectiveReach = getEffectiveAttackReach(activeTarget)

        if distToTarget <= effectiveReach then
            local rayResult = Workspace:Raycast(playerPos + Vector3.new(0, 1.8, 0), (tRoot.Position - playerPos), raycastParams)
            if not rayResult or not rayResult.Instance.CanCollide or rayResult.Instance:IsDescendantOf(activeTarget) then
                isCasting = true
                local capturedTarget = activeTarget

                task.spawn(function()
                    local function snapFaceTarget()
                        if SETTINGS.GameplayMode ~= "Manual Play" and capturedTarget and capturedTarget:FindFirstChild("HumanoidRootPart") and rootPart then
                            local tPos = capturedTarget.HumanoidRootPart.Position
                            local lookRot = CFrame.lookAt(rootPart.Position, Vector3.new(tPos.X, rootPart.Position.Y, tPos.Z))
                            if alignOrient and alignOrient.Parent then
                                alignOrient.CFrame = lookRot
                            end
                            -- rotate instantly; the constraint alone applies a physics step later
                            rootPart.CFrame = lookRot
                        end
                    end

                    -- Fire Q if not reserved for Buff Spammer
                    if not (SETTINGS.EIFSpammerEnabled and SETTINGS.EIFSpammerSlot:upper() == "Q") then
                        snapFaceTarget()
                        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Q, false, game)
                        task.wait(0.06)
                        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Q, false, game)
                    end

                    task.wait(math.max(SETTINGS.AttackCooldown, 0.22))

                    -- Fire E if not reserved for Buff Spammer
                    if not (SETTINGS.EIFSpammerEnabled and SETTINGS.EIFSpammerSlot:upper() == "E") then
                        if capturedTarget and capturedTarget:FindFirstChild("HumanoidRootPart") and (rootPart.Position - capturedTarget.HumanoidRootPart.Position).Magnitude <= getEffectiveAttackReach(capturedTarget) then
                            snapFaceTarget()
                            task.wait(0.02)
                            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                            task.wait(0.06)
                            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                        end
                    end

                    lastAttackSequenceTime = os.clock()
                    isCasting = false
                end)
            end
        end
    end
end

-- MANUAL PLAY MODE
if SETTINGS.GameplayMode == "Manual Play" then
    return
end

-- MOVEMENT & DODGING
local currentlyInDanger = false
local detectedHazardName = nil

if SETTINGS.AutoDodgeEnabled and not hasSpawnShield() and SETTINGS.GameplayMode ~= "Ultra Carry Mode" then 
    local inDanger, hazardName = isPointInDanger(playerPos, hazards)
    currentlyInDanger = inDanger
    detectedHazardName = hazardName
else
    activeDodgePoint = nil
end

if currentlyInDanger and detectedHazardName then
    evadingDisplayUntil = now + 3.0
    setStatus("Status: Evading: " .. tostring(detectedHazardName), true)
end

if now < postDodgeHoldUntil and not currentlyInDanger then
    return
end

if currentlyInDanger or (activeDodgePoint and now < dodgeExpiration) then
    if not activeDodgePoint or now >= dodgeExpiration or isPointInDanger(activeDodgePoint, hazards) then
        local enemyPos = activeTarget and activeTarget:FindFirstChild("HumanoidRootPart") and activeTarget.HumanoidRootPart.Position or playerPos
        activeDodgePoint = UI.findDodgePoint(playerPos, enemyPos, hazards)
        dodgeExpiration  = activeDodgePoint and (now + 0.9) or 0
    end

    if activeDodgePoint then
        local toTarget = activeDodgePoint - playerPos
        local dist = toTarget.Magnitude
        if dist < 1.5 then activeDodgePoint = nil; dodgeExpiration = 0; return end

        local allowTeleport = (SETTINGS.GameplayMode ~= "Legit Player") and (SETTINGS.GameplayMode ~= "No TP Auto Play")
        if allowTeleport and (now - lastTpDodgeTime >= 1.5) then
            if dist <= 9 and isValidTeleport(playerPos, activeDodgePoint) then
                lastTpDodgeTime = now
                executeSafeBlink(activeDodgePoint, activeDodgePoint + toTarget)
                activeDodgePoint = nil
            else
                humanoid:MoveTo(getGlidedTargetPos(playerPos, activeDodgePoint))
            end
        else 
            humanoid:MoveTo(getGlidedTargetPos(playerPos, activeDodgePoint))
        end
    end
    return
end

activeDodgePoint = nil

-- Anti-Stuck Detection
if (playerPos - stuckCheckPos).Magnitude < 0.75 then
    if now - stuckCheckTime > 3.0 then 
        humanoid.Jump = true
        stuckCheckTime = now 
        setStatus("Status: Stuck on geometry! Jumping...")
    end
else 
    stuckCheckPos = playerPos
    stuckCheckTime = now  
end

-- Macro Waypoints
if #waypoints > 0 then
    if currentWaypointIndex <= #waypoints then
        local targetNode = waypoints[currentWaypointIndex]
        local flatNodeDist = Vector2.new(playerPos.X - targetNode.X, playerPos.Z - targetNode.Z).Magnitude
        local distToNode = (playerPos - targetNode).Magnitude

        if not traversingManualNodes or distToNode > SETTINGS.MaxNodeDistance then
            local nearIdx = nil
            for i = currentWaypointIndex, #waypoints do
                if (playerPos - waypoints[i]).Magnitude <= SETTINGS.WaypointTriggerDist then nearIdx = i; break end
            end
            if nearIdx then currentWaypointIndex = nearIdx; traversingManualNodes = true else traversingManualNodes = false end
        end

        if traversingManualNodes then
            setStatus(string.format("MACRO ACTIVE: Node %d/%d (%.1f st)", currentWaypointIndex, #waypoints, distToNode))
            if not activeTarget and alignOrient and alignOrient.Parent and alignOrient.Enabled then
                alignOrient.CFrame = CFrame.lookAt(playerPos, Vector3.new(targetNode.X, playerPos.Y, targetNode.Z))
            end
            UI.moveAvoiding(getGlidedTargetPos(playerPos, targetNode), hazards)
            if flatNodeDist <= 3.8 then currentWaypointIndex = currentWaypointIndex + 1 end
            return
        end
    else traversingManualNodes = false end
end

-- Combat Movement & Pathfinding
if activeTarget and activeTarget:FindFirstChild("HumanoidRootPart") then
    local enemyPos = activeTarget.HumanoidRootPart.Position
    local toEnemy = enemyPos - playerPos
    local flatToEnemy = Vector3.new(toEnemy.X, 0, toEnemy.Z)
    local distToEnemy = flatToEnemy.Magnitude
    -- a wall between you and the enemy means you cannot hit it, so standing still there is pointless
    local clearRay = Workspace:Raycast(playerPos + Vector3.new(0, 1.8, 0), toEnemy, raycastParams)
    local clearShot = (not clearRay) or (not clearRay.Instance.CanCollide) or clearRay.Instance:IsDescendantOf(activeTarget)

    if distToEnemy <= SETTINGS.MaxDistance and clearShot then
        table.clear(activePathWaypoints)
        pathIndex = 1

        if distToEnemy < SETTINGS.MinDistance then 
            -- Smoothly backpedal away from target if they get too close
            local retreatPos = UI.pickRetreatPos(playerPos, enemyPos, hazards)
            UI.moveAvoiding(getGlidedTargetPos(playerPos, retreatPos), hazards)
        else
            -- In combat zone: stand ground and cast cleanly
            humanoid:MoveTo(playerPos)
        end
    else
        -- Outside MaxDistance: Advance toward enemy
        local losRay = Workspace:Raycast(playerPos + Vector3.new(0, 1.8, 0), toEnemy, raycastParams)
        local hasLOS = (not losRay) or (losRay.Instance and losRay.Instance:IsDescendantOf(activeTarget))

        if hasLOS then
            table.clear(activePathWaypoints)
            pathIndex = 1
            UI.moveAvoiding(getGlidedTargetPos(playerPos, enemyPos), hazards)
        else
            if now - lastPathComputeTime > 0.8 or #activePathWaypoints == 0 or pathIndex > #activePathWaypoints then
                lastPathComputeTime = now
                local success = pcall(function() pathObject:ComputeAsync(playerPos, enemyPos) end)
                if success and pathObject.Status == Enum.PathStatus.Success then
                    activePathWaypoints = pathObject:GetWaypoints()
                    pathIndex = 2
                else
                    humanoid:MoveTo(getGlidedTargetPos(playerPos, enemyPos))
                end
            end

            if #activePathWaypoints > 0 and pathIndex <= #activePathWaypoints then
                local targetWp = activePathWaypoints[pathIndex]
                local wpPos = targetWp.Position
                local flatWpDist = Vector2.new(playerPos.X - wpPos.X, playerPos.Z - wpPos.Z).Magnitude

                if flatWpDist <= 3.8 then
                    pathIndex = pathIndex + 1
                    if pathIndex <= #activePathWaypoints then
                        targetWp = activePathWaypoints[pathIndex]
                        wpPos = targetWp.Position
                    end
                end

                if pathIndex <= #activePathWaypoints then
                    if targetWp.Action == Enum.PathWaypointAction.Jump then humanoid.Jump = true end
                    UI.moveAvoiding(wpPos, hazards)
                end
            end
        end
    end
end
end)
table.insert(connections, mainConnection)

-- RUN INITIALIZATION

-- AUTO TRADE: sends a trade request to the chosen username every 1 s while the toggle is ON.
-- The game's trade remote is discovered by name (anything called *trade* that looks like a "send/request" remote).
local function findTradeRemotes()
    local found = {}
    for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
        if (obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction")) and obj.Name:lower():find("trade", 1, true) then
            table.insert(found, obj)
        end
    end
    return found
end

local function pickTradeRemote(list)
    local best, bestScore
    for _, r in ipairs(list) do
        local n, s = r.Name:lower(), 0
        for _, kw in ipairs({ "send", "request", "invite", "start", "create", "initiate" }) do if n:find(kw, 1, true) then s = s + 1 end end
        for _, kw in ipairs({ "accept", "decline", "cancel", "confirm", "ready", "add", "remove", "update", "finish", "complete", "show" }) do if n:find(kw, 1, true) then s = s - 2 end end
        if not bestScore or s > bestScore then best, bestScore = r, s end
    end
    if bestScore and bestScore > 0 then return best end
    return nil
end

local function findPlayerByName(query)
    query = tostring(query or ""):lower()
    if query == "" then return nil end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and (p.Name:lower() == query or p.DisplayName:lower() == query) then return p end
    end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and (p.Name:lower():sub(1, #query) == query or p.DisplayName:lower():sub(1, #query) == query) then return p end
    end
    return nil
end

function UI.sendTradeNow(rotate)
    -- one or many usernames, separated by commas, semicolons, spaces or new lines
    local names = {}
    for name in tostring(SETTINGS.TradeUsername or ""):gmatch("[^,;%s]+") do table.insert(names, name) end
    if #names == 0 then return "type a username first" end

    local targets, missing = {}, {}
    for _, name in ipairs(names) do
        local p = findPlayerByName(name)
        if p then table.insert(targets, p) else table.insert(missing, name) end
    end
    if #targets == 0 then return "not in this server: " .. table.concat(missing, ", ") end

    -- auto mode: the game keeps only ONE outgoing request, so each new request cancels the previous one.
    -- Stay on one player for 6 sends (~6 s) so they can accept, then move to the next.
    if rotate then
        UI.tradeTick = (UI.tradeTick or 0) + 1
        targets = { targets[math.floor((UI.tradeTick - 1) / 4) % #targets + 1] }
    end

    local list = findTradeRemotes()
    local remote = pickTradeRemote(list)
    if not remote then
        local names = {}
        for _, r in ipairs(list) do table.insert(names, r:GetFullName() .. " (" .. r.ClassName .. ")") end
        pcall(warn, "[Trade] no send-trade remote found. Trade-related remotes: " .. (#names > 0 and table.concat(names, ", ") or "none"))
        return "no trade remote found (see console)"
    end
    local sent = {}
    for _, target in ipairs(targets) do
        safeInvoke(remote, target)
        table.insert(sent, target.Name)
    end
    local msg = "sent to " .. #sent .. ": " .. table.concat(sent, ", ") .. " via " .. remote.Name
    if #missing > 0 then msg = msg .. " (not in server: " .. table.concat(missing, ", ") .. ")" end
    return msg
end

function UI.startAutoTrade()
    task.spawn(function()
        local lastSent = 0
        while not isCleaningUp do
            if SETTINGS.AutoTrade and SETTINGS.TradeUsername ~= "" and os.clock() - lastSent >= 0.5 then
                lastSent = os.clock()
                local ok, msg = pcall(UI.sendTradeNow, true)
                if UI.tradeStatus and UI.tradeStatus.Parent then
                    UI.tradeStatus.Text = "Trade: " .. tostring(ok and msg or ("error - " .. tostring(msg)))
                end
            end
            task.wait(0.1)
        end
    end)
end

-- finds the on-screen "Accept" button of the trade-request popup and presses it.
-- Returns (clicked, message). Tries the button's own handlers, then a real mouse click, and checks the popup closed.
function UI.clickAcceptButton()
    local pGui = player:FindFirstChild("PlayerGui")
    if not pGui then return false, "no PlayerGui" end
    local function shown(obj)
        local cur = obj
        while cur and cur ~= pGui do
            if cur:IsA("GuiObject") and not cur.Visible then return false end
            if cur:IsA("ScreenGui") and not cur.Enabled then return false end
            cur = cur.Parent
        end
        return obj.AbsoluteSize.X > 0 and obj.AbsoluteSize.Y > 0
    end
    local function findBtn()
        for _, obj in ipairs(pGui:GetDescendants()) do
            if (obj:IsA("TextButton") or obj:IsA("TextLabel")) and obj.Text:lower():match("^%s*accept%s*$")
                and not (UI.screenGui and obj:IsDescendantOf(UI.screenGui)) and shown(obj) then
                return obj
            end
        end
    end
    local btn
    for _ = 1, 20 do
        btn = findBtn()
        if btn then break end
        task.wait(0.1)
    end
    if not btn then return false, "Accept button not found" end
    pcall(warn, "[Trade] Accept button: " .. btn:GetFullName() .. " (" .. btn.ClassName .. ")")

    -- 1) fire the button's own handlers (on it and on its parents, in case a wrapper button owns the click)
    local target = btn
    for _ = 1, 3 do
        if target and target:IsA("GuiButton") then
            pcall(function()
                if getconnections then
                    for _, sig in ipairs({ target.MouseButton1Click, target.Activated, target.MouseButton1Down, target.MouseButton1Up }) do
                        for _, c in ipairs(getconnections(sig)) do c:Fire() end
                    end
                elseif firesignal then
                    firesignal(target.MouseButton1Click)
                    firesignal(target.Activated)
                end
            end)
        end
        target = target and target.Parent
    end
    task.wait(0.4)
    if not shown(btn) then return true, "accepted" end

    -- 2) real mouse click at the button's centre (the game may listen to raw input)
    local ok = pcall(function()
        local gui = btn:FindFirstAncestorOfClass("ScreenGui")
        local inset = (gui and gui.IgnoreGuiInset) and Vector2.zero or game:GetService("GuiService"):GetGuiInset()
        local pos = btn.AbsolutePosition + btn.AbsoluteSize / 2 + inset
        VirtualInputManager:SendMouseMoveEvent(pos.X, pos.Y, game)
        task.wait(0.05)
        VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 0)
        task.wait(0.06)
        VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 0)
    end)
    task.wait(0.4)
    if not shown(btn) then return true, "accepted" end
    return false, ok and "clicked Accept but the popup is still open" or "could not click Accept"
end
-- Reads the gold amount shown on the incoming trade offer (best-effort: looks for a number label whose name or a
-- parent's name mentions "gold" inside the same PlayerGui). Returns nil if no such label could be found.
local function getIncomingTradeGold()
    local pGui = player:FindFirstChild("PlayerGui")
    if not pGui then return nil end
    for _, obj in ipairs(pGui:GetDescendants()) do
        if (obj:IsA("TextLabel") or obj:IsA("TextButton")) and obj.AbsoluteSize.X > 0 and not (UI.screenGui and obj:IsDescendantOf(UI.screenGui)) then
            local value = obj.Text:match("^%s*([%d%.,]+%s*[KMBTkmbt]?)%s*$")
            if value then
                local current = obj
                for _ = 1, 4 do
                    if not current or current == pGui then break end
                    if current.Name:lower():find("gold", 1, true) then
                        local num = tonumber((value:gsub("[^%d%.]", "")))
                        if num then return num end
                    end
                    current = current.Parent
                end
            end
        end
    end
    return nil
end

-- AUTO ACCEPT TRADE: listens to the game's incoming-trade remote(s) and answers "accept" (same pattern as the join-request hook).
function UI.startAutoAccept()
    task.spawn(function()
        local function setAccept(text)
            if UI.acceptStatus and UI.acceptStatus.Parent then UI.acceptStatus.Text = "Accept: " .. text end
        end
        local list = findTradeRemotes()
        local respond
        for _, r in ipairs(list) do
            local n = r.Name:lower()
            if n:find("respond", 1, true) or n:find("accept", 1, true) then
                if not respond or n:find("respond", 1, true) then respond = r end
            end
        end
        local names = {}
        for _, r in ipairs(list) do table.insert(names, r.Name .. " (" .. r.ClassName .. ")") end
        pcall(warn, "[Trade] trade remotes: " .. (#names > 0 and table.concat(names, ", ") or "none"))
        for _, r in ipairs(list) do
            local n = r.Name:lower()
            if r:IsA("RemoteEvent") and (n:find("show", 1, true) or n:find("incoming", 1, true) or n:find("receive", 1, true) or n:find("prompt", 1, true) or n:find("request", 1, true)) and not n:find("send", 1, true) then
                table.insert(connections, r.OnClientEvent:Connect(function(...)
                    if not SETTINGS.AutoAcceptTrade or isCleaningUp then return end
                    local args = {...}
                    -- only accept requests from listed users (any string / Player argument may carry the name)
                    local allowed, who = {}, nil
                    for n in tostring(SETTINGS.AcceptUsername or ""):gmatch("[^,;%s]+") do allowed[n:lower()] = true end
                    for _, a in ipairs(args) do
                        local nm = (typeof(a) == "Instance" and a:IsA("Player")) and a.Name or (type(a) == "string" and a or nil)
                        if nm and allowed[nm:lower()] then who = nm; break end
                        if typeof(a) == "Instance" and a:IsA("Player") and allowed[a.DisplayName:lower()] then who = a.Name; break end
                    end
                    if not who then
                        setAccept("ignored request (not in accept list)")
                        return
                    end
                    pcall(warn, "[Trade] incoming via " .. r.Name .. ": " .. tostring(args[1]) .. ", " .. tostring(args[2]))
                    task.wait(0.3)
                    if SETTINGS.AutoAcceptRequireGold then
                        local offeredGold = getIncomingTradeGold()
                        pcall(warn, "[Trade] offered gold detected: " .. tostring(offeredGold))
                        if offeredGold ~= nil and offeredGold <= 0 then
                            setAccept("skipped trade from " .. who .. " (0 gold offered)")
                            return
                        end
                    end
                    local clicked, info = UI.clickAcceptButton()
                    if clicked then
                        setAccept(info .. " request from " .. who)
                    elseif respond then
                        safeInvoke(respond, args[1], true)
                        setAccept(tostring(info) .. " - also sent accept remote for " .. who)
                    else
                        setAccept(tostring(info) .. " (no respond remote found)")
                    end
                end))
            end
        end
        if #list == 0 then setAccept("no trade remotes found") end
    end)
end

-- AUTO ACCEPT JOIN REQUESTS (backup): when the "... wants to join your raid" popup is on screen and you are the host,
-- press its ACCEPT button. Works even if the game's remote did not reach the hook above.
function UI.startJoinAccept()
    task.spawn(function()
        local lastTry = 0
        while not isCleaningUp do
            task.wait(0.1)
            if isAutoplay and SETTINGS.LobbyMode == "Host" and not SETTINGS.FollowHost and os.clock() - lastTry > 0.5 then
                local pGui = player:FindFirstChild("PlayerGui")
                local found = false
                for _, obj in ipairs(pGui and pGui:GetDescendants() or {}) do
                    if obj:IsA("TextLabel") and obj.Text:lower():find("wants to join", 1, true) and obj.AbsoluteSize.X > 0 then
                        local shown, cur = true, obj
                        while cur and cur ~= pGui do
                            if (cur:IsA("GuiObject") and not cur.Visible) or (cur:IsA("ScreenGui") and not cur.Enabled) then shown = false break end
                            cur = cur.Parent
                        end
                        if shown then found = true; break end
                    end
                end
                if found then
                    lastTry = os.clock()
                    local ok, clicked, info = pcall(UI.clickAcceptButton)
                    pcall(warn, "[Join] popup found, accept -> " .. tostring(ok and clicked) .. " " .. tostring(info))
                end
            end
        end
    end)
end

-- BUILD: puts every free skill point into one stat by pressing that stat's "+" button in the Skills panel
local function readSkillPoints(pGui)
    for _, obj in ipairs(pGui:GetDescendants()) do
        if obj:IsA("TextLabel") then
            local n = obj.Text:match("^%s*[Pp]oints:?%s*([%d,]+)")
            if n then return tonumber((n:gsub(",", ""))) end
        end
    end
    return nil
end

local function isPlusGlyph(s)
    s = tostring(s or ""):gsub("%s", "")
    return s == "+" or s == "＋" or s == "✚" or s == "➕"
end

local function isGreenColor(c)
    return c.G > 0.55 and c.G > c.R + 0.2 and c.G > c.B + 0.2
end

local function findStatButton(pGui, statName)
    local want = statName:lower()
    local bestBtn, bestDist
    local foundLabel = false
    local seen = {}
    for _, label in ipairs(pGui:GetDescendants()) do
        if (label:IsA("TextLabel") or label:IsA("TextButton")) and label.Text:lower():match("^%s*(.-)%s*$") == want
            and not (UI.screenGui and label:IsDescendantOf(UI.screenGui)) then
            foundLabel = true
            local screen = label:FindFirstAncestorOfClass("ScreenGui")
            local lp, ls = label.AbsolutePosition, label.AbsoluteSize
            local lc = lp + ls / 2
            for _, d in ipairs(screen and screen:GetDescendants() or {}) do
                if d ~= label and d:IsA("GuiButton") then
                    local text = d:IsA("TextButton") and d.Text:match("^%s*(.-)%s*$") or ""
                    local childPlus = false
                    for _, c in ipairs(d:GetDescendants()) do
                        if c:IsA("TextLabel") and isPlusGlyph(c.Text) then childPlus = true break end
                    end
                    local isPlus = isPlusGlyph(text) or childPlus
                    local sz = d.AbsoluteSize
                    local greenBtn = (d.BackgroundTransparency < 1 and isGreenColor(d.BackgroundColor3)) or (d:IsA("ImageButton") and isGreenColor(d.ImageColor3))
                    local squareish = greenBtn and text == "" and sz.X > 8 and sz.Y > 8 and sz.X < 110 and sz.Y < 110 and sz.X / sz.Y > 0.6 and sz.X / sz.Y < 1.6
                    if isPlus or squareish then
                        local bc = d.AbsolutePosition + sz / 2
                        -- the + sits below the stat title and within its width
                        if bc.Y >= lc.Y - 5 and bc.Y <= lc.Y + 220 and bc.X >= lp.X - 10 and bc.X <= lp.X + ls.X + 30 then
                            local dist = (bc - lc).Magnitude - (isPlus and 40 or 0)
                            if not bestDist or dist < bestDist then bestBtn, bestDist = d, dist end
                        end
                        table.insert(seen, string.format("%s '%s' (%d,%d) %dx%d %s", d.ClassName, d.Name, bc.X, bc.Y, sz.X, sz.Y, greenBtn and "green" or "not-green"))
                    end
                end
            end
        end
    end
    if bestBtn then
        pcall(warn, "[Build] " .. statName .. " + button: " .. bestBtn:GetFullName())
        return bestBtn
    end
    if #seen > 0 then pcall(warn, "[Build] buttons near '" .. statName .. "': " .. table.concat(seen, " | ")) end
    return nil, foundLabel and ("found '" .. statName .. "' but no + button next to it (see console)") or ("could not find the '" .. statName .. "' row - open the Skills tab once")
end
local function pressGuiButton(btn)
    local fired = false
    pcall(function()
        if getconnections then
            for _, sig in ipairs({ btn.MouseButton1Click, btn.Activated }) do
                for _, c in ipairs(getconnections(sig)) do c:Fire(); fired = true end
            end
        elseif firesignal then
            firesignal(btn.MouseButton1Click); fired = true
        end
    end)
    return fired
end

local function realClickButton(btn)
    pcall(function()
        local gui = btn:FindFirstAncestorOfClass("ScreenGui")
        local inset = (gui and gui.IgnoreGuiInset) and Vector2.zero or game:GetService("GuiService"):GetGuiInset()
        local pos = btn.AbsolutePosition + btn.AbsoluteSize / 2 + inset
        VirtualInputManager:SendMouseMoveEvent(pos.X, pos.Y, game)
        task.wait(0.03)
        VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 0)
        task.wait(0.04)
        VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 0)
    end)
end

function UI.applyBuild(statName, buildName)
    if UI.buildBusy then return end
    UI.buildBusy = true
    local function say(text)
        if UI.buildStatus and UI.buildStatus.Parent then UI.buildStatus.Text = "Build: " .. text end
    end
    task.spawn(function()
        local ok, err = pcall(function()
            local pGui = player:FindFirstChild("PlayerGui")
            local btn, why = findStatButton(pGui, statName)
            if not btn then say(why); return end
            local points = readSkillPoints(pGui)
            if not points then say("could not read the Points label - open the Skills tab once"); return end
            if points <= 0 then say("no free points to spend"); return end
            local startPoints, last, stall, triedReal = points, points, 0, false
            while points > 0 and not isCleaningUp do
                for _ = 1, 10 do
                    pressGuiButton(btn)
                    task.wait(0.03)
                end
                task.wait(0.15)
                points = readSkillPoints(pGui) or points
                if points >= last then stall = stall + 1 else stall = 0 end
                last = points
                if stall == 2 and not triedReal then triedReal = true; realClickButton(btn) end
                if stall >= 4 then break end
                say(string.format("%s - %d points left...", buildName, points))
            end
            if points <= 0 then
                say(string.format("%s done - spent %d points on %s", buildName, startPoints, statName))
            else
                say(string.format("stopped with %d points left - the + button did not respond (open the Skills tab and retry)", points))
                local names = {}
                for _, r in ipairs(ReplicatedStorage:GetDescendants()) do
                    local n = r.Name:lower()
                    if (r:IsA("RemoteEvent") or r:IsA("RemoteFunction")) and (n:find("stat", 1, true) or n:find("skill", 1, true) or n:find("point", 1, true)) then
                        table.insert(names, r:GetFullName())
                    end
                end
                pcall(warn, "[Build] stat-related remotes: " .. (#names > 0 and table.concat(names, ", ") or "none"))
            end
        end)
        if not ok then say("error - " .. tostring(err)) end
        UI.buildBusy = false
    end)
end

-- RESET: presses the red "Reset" button of the Skills panel (the one in the same window as the Points label)
function UI.resetStats()
    if UI.buildBusy then return end
    UI.buildBusy = true
    local function say(text)
        if UI.buildStatus and UI.buildStatus.Parent then UI.buildStatus.Text = "Build: " .. text end
    end
    task.spawn(function()
        local ok, err = pcall(function()
            local pGui = player:FindFirstChild("PlayerGui")
            local pointsLabel
            for _, obj in ipairs(pGui:GetDescendants()) do
                if obj:IsA("TextLabel") and obj.Text:match("^%s*[Pp]oints:?%s*[%d,]+") then pointsLabel = obj break end
            end
            if not pointsLabel then say("could not find the Points label - open the Skills tab once"); return end
            local screen = pointsLabel:FindFirstAncestorOfClass("ScreenGui")
            local before = readSkillPoints(pGui) or 0
            local pc = pointsLabel.AbsolutePosition + pointsLabel.AbsoluteSize / 2
            local btn, bestDist
            for _, d in ipairs(screen:GetDescendants()) do
                if d:IsA("GuiButton") then
                    local text = d:IsA("TextButton") and d.Text or ""
                    if text == "" then
                        for _, c in ipairs(d:GetDescendants()) do
                            if c:IsA("TextLabel") then text = c.Text break end
                        end
                    end
                    if text:lower():match("^%s*reset%s*$") then
                        local dist = (d.AbsolutePosition + d.AbsoluteSize / 2 - pc).Magnitude
                        if not bestDist or dist < bestDist then btn, bestDist = d, dist end
                    end
                end
            end
            if not btn then say("could not find the Reset button next to Points"); return end
            pcall(warn, "[Build] Reset button: " .. btn:GetFullName())
            pressGuiButton(btn)
            task.wait(0.7)
            local after = readSkillPoints(pGui) or before
            if after <= before then
                realClickButton(btn)
                task.wait(0.7)
                after = readSkillPoints(pGui) or before
            end
            if after > before then
                say(string.format("stats reset - %d free points now (was %d)", after, before))
            else
                say("pressed Reset but the points did not change (the game may ask for confirmation)")
            end
        end)
        if not ok then say("error - " .. tostring(err)) end
        UI.buildBusy = false
    end)
end

-- 8. KEY SYSTEM: the menu only builds after a valid key is entered (a saved valid key skips the prompt)
local KEY = {
    Required = true,
    Keys = { "NCLHUB" },                        -- valid keys: edit / add your own
    Url = "",                                   -- optional: link to a text file with one key per line (overrides Keys)
    Discord = DISCORD_INVITE,  -- copied to the clipboard by the Join Discord button
    File = FOLDER_NAME .. "/key.txt",
}

local function keyIsValid(input)
    input = tostring(input or ""):match("^%s*(.-)%s*$")
    if input == "" then return false, "Enter a key first" end
    local list = KEY.Keys
    if KEY.Url ~= "" then
        local body
        local req = getHttpRequest()
        if req then
            local ok, res = pcall(req, { Url = KEY.Url, Method = "GET" })
            if ok and type(res) == "table" then body = res.Body or res.body end
        end
        if type(body) ~= "string" then
            local ok, res = pcall(function() return game:HttpGet(KEY.Url) end)
            if ok then body = res end
        end
        if type(body) ~= "string" then return false, "Could not reach the key server" end
        list = {}
        for line in body:gmatch("[^\r\n]+") do table.insert(list, (line:match("^%s*(.-)%s*$"))) end
    end
    for _, k in ipairs(list) do
        if k == input then return true end
    end
    return false, "Invalid key"
end

local function showKeySystem(onSuccess)
    if not KEY.Required then onSuccess(); return end

    local saved
    pcall(function() if isfile and isfile(KEY.File) then saved = readfile(KEY.File) end end)
    if saved and keyIsValid(saved) then onSuccess(); return end

    local C = {
        bg = Color3.fromRGB(9, 12, 24), panel = Color3.fromRGB(13, 17, 33), field = Color3.fromRGB(10, 13, 26),
        stroke = Color3.fromRGB(38, 46, 96), text = Color3.fromRGB(232, 236, 255), muted = Color3.fromRGB(128, 138, 172),
        purple = Color3.fromRGB(110, 80, 245), blue = Color3.fromRGB(50, 110, 255),
        green = Color3.fromRGB(28, 220, 150), red = Color3.fromRGB(240, 70, 100),
    }
    local function corner(inst, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = inst end
    local function outline(inst, color, t) local s = Instance.new("UIStroke"); s.Color = color or C.stroke; s.Thickness = t or 1; s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = inst; return s end
    local function box(parent, x, y, w, h, color)
        local f = Instance.new("Frame")
        f.Position = UDim2.new(0, x, 0, y); f.Size = UDim2.new(0, w, 0, h)
        f.BackgroundColor3 = color; f.BorderSizePixel = 0; f.Parent = parent
        return f
    end
    local function label(parent, text, size, color, font, x, y, w, h)
        local l = Instance.new("TextLabel")
        l.BackgroundTransparency = 1; l.Text = text; l.TextSize = size; l.TextColor3 = color
        l.Font = font; l.TextXAlignment = Enum.TextXAlignment.Left; l.TextYAlignment = Enum.TextYAlignment.Center
        l.Position = UDim2.new(0, x, 0, y); l.Size = UDim2.new(0, w, 0, h); l.Parent = parent
        return l
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "NCL KEY"; gui.ResetOnSpawn = false; gui.DisplayOrder = 300
    local parent = player:WaitForChild("PlayerGui", 5)
    if gethui then pcall(function() parent = gethui() end) else pcall(function() local t = Instance.new("Folder"); t.Parent = CoreGui; t:Destroy(); parent = CoreGui end) end
    gui.Parent = parent
    UI.keyGui = gui

    local win = box(gui, 0, 0, 720, 340, C.bg)
    win.AnchorPoint = Vector2.new(0.5, 0.5); win.Position = UDim2.new(0.5, 0, 0.5, 0)
    win.Active = true; win.Draggable = true; win.ClipsDescendants = true
    corner(win, 14); outline(win, Color3.fromRGB(70, 80, 210), 1)
    local scale = Instance.new("UIScale")
    local cam = Workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
    local baseScale = math.clamp(math.min(vp.X / 800, vp.Y / 420), 0.5, 1)
    scale.Scale = baseScale; scale.Parent = win

    -- header
    local header = box(win, 14, 11, 692, 66, C.panel); corner(header, 12); outline(header)
    local keyIcon = label(header, "🔑", 30, C.purple, Enum.Font.GothamBold, 16, 0, 44, 66)
    local title = label(header, '<font color="#FFFFFF">Key</font> <font color="#7C6BFF">System</font>', 28, C.text, Enum.Font.GothamBlack, 66, 6, 300, 34)
    title.RichText = true
    label(header, "Enter your key to continue", 13, C.muted, Enum.Font.Gotham, 66, 38, 300, 20)

    local function winBtn(x)
        local b = Instance.new("TextButton")
        b.Position = UDim2.new(0, x, 0, 18); b.Size = UDim2.new(0, 30, 0, 30)
        b.BackgroundColor3 = C.field; b.BorderSizePixel = 0; b.Text = ""; b.Parent = header
        corner(b, 8); outline(b)
        return b
    end
    local function bar(parent, w, h, rot)
        local f = box(parent, 0, 0, w, h, C.text)
        f.AnchorPoint = Vector2.new(0.5, 0.5); f.Position = UDim2.new(0.5, 0, 0.5, 0); f.Rotation = rot or 0
    end
    local minBtn, maxBtn, closeBtn = winBtn(574), winBtn(610), winBtn(646)
    bar(minBtn, 12, 2)
    local maxIcon = box(maxBtn, 0, 0, 11, 11, C.text); maxIcon.AnchorPoint = Vector2.new(0.5, 0.5); maxIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
    maxIcon.BackgroundTransparency = 1; outline(maxIcon, C.text, 2)
    bar(closeBtn, 15, 2, 45); bar(closeBtn, 15, 2, -45)

    local body = box(win, 0, 0, 720, 340, C.bg); body.BackgroundTransparency = 1

    -- left panel: key input, validate button, status card
    local left = box(body, 16, 91, 480, 231, C.panel); corner(left, 12); outline(left)
    local input = Instance.new("TextBox")
    input.Position = UDim2.new(0, 16, 0, 20); input.Size = UDim2.new(0, 448, 0, 44)
    input.BackgroundColor3 = C.field; input.BorderSizePixel = 0; input.ClearTextOnFocus = false
    input.PlaceholderText = "Enter your key..."; input.PlaceholderColor3 = C.muted; input.Text = ""
    input.TextColor3 = C.text; input.Font = Enum.Font.Gotham; input.TextSize = 15
    input.TextXAlignment = Enum.TextXAlignment.Left; input.Parent = left
    corner(input, 10); outline(input)
    local inPad = Instance.new("UIPadding"); inPad.PaddingLeft = UDim.new(0, 48); inPad.PaddingRight = UDim.new(0, 12); inPad.Parent = input
    label(input, "🔑", 16, C.purple, Enum.Font.GothamBold, -34, 0, 24, 44)

    local validate = Instance.new("TextButton")
    validate.Position = UDim2.new(0, 16, 0, 80); validate.Size = UDim2.new(0, 448, 0, 42)
    validate.BackgroundColor3 = Color3.fromRGB(255, 255, 255); validate.BorderSizePixel = 0
    validate.Text = "Validate Key"; validate.TextColor3 = Color3.fromRGB(255, 255, 255)
    validate.Font = Enum.Font.GothamBold; validate.TextSize = 16; validate.AutoButtonColor = true; validate.Parent = left
    corner(validate, 10)
    local vGrad = Instance.new("UIGradient"); vGrad.Color = ColorSequence.new(C.purple, C.blue); vGrad.Parent = validate

    local card = box(left, 16, 136, 448, 72, C.field); corner(card, 10); outline(card)
    local spinner = box(card, 16, 14, 44, 44, C.field); spinner.BackgroundTransparency = 1; corner(spinner, 22)
    local ring = outline(spinner, C.purple, 4)
    local ringGrad = Instance.new("UIGradient")
    ringGrad.Color = ColorSequence.new(C.purple, C.blue)
    ringGrad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.6, 0.1), NumberSequenceKeypoint.new(0.61, 0.85), NumberSequenceKeypoint.new(1, 0.85) })
    ringGrad.Parent = ring
    local statusIcon = label(card, "🔑", 26, C.purple, Enum.Font.GothamBold, 22, 0, 40, 72)
    local statusTitle = label(card, "Ready", 17, C.text, Enum.Font.GothamBold, 76, 12, 350, 26)
    local statusSub = label(card, "Type your key above, then press Validate.", 13, C.muted, Enum.Font.Gotham, 76, 38, 350, 20)
    spinner.Visible = false

    -- right panel: discord
    local right = box(body, 507, 91, 197, 231, C.panel); corner(right, 12); outline(right)
    label(right, "💬", 26, C.purple, Enum.Font.GothamBold, 16, 16, 34, 34)
    label(right, "Discord Server", 16, C.text, Enum.Font.GothamBold, 56, 16, 130, 34)
    local desc = label(right, "Join our Discord for support and updates.", 13, C.muted, Enum.Font.Gotham, 16, 62, 168, 40)
    desc.TextWrapped = true; desc.TextYAlignment = Enum.TextYAlignment.Top
    local discordBtn = Instance.new("TextButton")
    discordBtn.Position = UDim2.new(0, 16, 0, 112); discordBtn.Size = UDim2.new(0, 165, 0, 40)
    discordBtn.BackgroundColor3 = Color3.fromRGB(34, 40, 110); discordBtn.BorderSizePixel = 0
    discordBtn.Text = "Join Discord"; discordBtn.TextColor3 = C.text; discordBtn.Font = Enum.Font.GothamSemibold
    discordBtn.TextSize = 14; discordBtn.Parent = right
    corner(discordBtn, 10); outline(discordBtn, Color3.fromRGB(60, 70, 190))

    -- behaviour
    local busy, closed = false, false
    local spinConn = RunService.RenderStepped:Connect(function(dt)
        if spinner.Visible then ringGrad.Rotation = (ringGrad.Rotation + dt * 300) % 360 end
    end)
    table.insert(connections, spinConn)

    local function setState(kind, head, sub)
        spinner.Visible = (kind == "busy")
        statusIcon.Visible = (kind ~= "busy")
        if kind == "ok" then statusIcon.Text = "✓"; statusIcon.TextColor3 = C.green
        elseif kind == "bad" then statusIcon.Text = "✕"; statusIcon.TextColor3 = C.red
        else statusIcon.Text = "🔑"; statusIcon.TextColor3 = C.purple end
        statusTitle.Text = head; statusSub.Text = sub
    end

    local function submit()
        if busy or closed then return end
        busy = true
        setState("busy", "Validating key...", "Please wait a moment.")
        task.spawn(function()
            task.wait(0.5)
            local ok, err = keyIsValid(input.Text)
            if closed then return end
            if ok then
                pcall(function()
                    if writefile then writefile(KEY.File, (input.Text:match("^%s*(.-)%s*$"))) end
                end)
                setState("ok", "Key valid!", "Loading menu...")
                task.wait(0.6)
                closed = true
                spinConn:Disconnect()
                gui:Destroy()
                UI.keyGui = nil
                onSuccess()
            else
                setState("bad", err or "Invalid key", "Check your key and try again.")
                busy = false
            end
        end)
    end
    validate.MouseButton1Click:Connect(submit)
    input.FocusLost:Connect(function(enter) if enter then submit() end end)

    discordBtn.MouseButton1Click:Connect(function()
        setClipboard(KEY.Discord)
        discordBtn.Text = "Invite copied!"
        task.delay(2, function() if discordBtn.Parent then discordBtn.Text = "Join Discord" end end)
    end)

    local minimized, maximized = false, false
    minBtn.MouseButton1Click:Connect(function()
        minimized = not minimized
        body.Visible = not minimized
        win.Size = UDim2.new(0, 720, 0, minimized and 90 or 340)
    end)
    maxBtn.MouseButton1Click:Connect(function()
        maximized = not maximized
        scale.Scale = maximized and math.min(baseScale * 1.25, 1.4) or baseScale
    end)
    closeBtn.MouseButton1Click:Connect(function() closed = true; cleanup() end)
end

showKeySystem(function()
    buildInterface()
    loadConfigAndAutoExecute()
    UI.startAutoTrade()
    UI.startAutoAccept()
    UI.startJoinAccept()
end)
