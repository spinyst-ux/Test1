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

    -- Belt-and-suspenders: the _G guard above only works when _G survives between runs, which some
    -- executors don't guarantee even across a plain manual re-execute. When it fails, the previous
    -- ScreenGuis never get destroyed and a new copy piles on top of them. So also destroy any leftover
    -- NCL windows by name directly, in every place they might have been parented, before this run builds its own.
    pcall(function()
        local roots = {}
        local pGui = player:FindFirstChild("PlayerGui")
        if pGui then table.insert(roots, pGui) end
        table.insert(roots, CoreGui)
        pcall(function() if gethui then table.insert(roots, gethui()) end end)
        for _, root in ipairs(roots) do
            for _, uiName in ipairs({ "NCL MACRO", "NCL KEY", "DungeonBlackScreen" }) do
                local old = root:FindFirstChild(uiName)
                if old then old:Destroy() end
            end
        end
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
    local FOLDER_NAME = "NCL HUB"
    local CONFIG_FILE = string.format("%s/config_%s.json", FOLDER_NAME, player.Name)
    local SPAWN_SHIELD_DURATION = 5.0
    local MAX_INVENTORY_CAPACITY = 300
    local MAIN_LOBBY_PLACE_ID = 77649408247578
    local DISCORD_INVITE = "https://discord.gg/SuKX7Gc4B4"

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
        DodgeBoostStuds = 6,        -- 0-10 studs of "burst" speed a dodge may spend before slowing to a normal walk
        ShowDodgeBoostBar = true,   -- HUD bar showing how much burst the dodge boost pool has left
        WaypointTriggerDist = 40,
        MaxNodeDistance = 25,
        WallRayLength = 5.5,
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
        RemoveMap = false,
        FpsBoost = false,
        DodgeList = "bonusboss",
        LearnAttacks = true,
        ShowAttackEsp = false,
        LearnedAttacks = {},
        LearnedAnims = {},   -- boss attack animation id -> { d = seconds until it hits, r = reach in studs }
        ShowRangeCircle = false,
        AutoHideUI = false,
        CustomName = "",
        RenameParty = true,
        LogoAvatar = true,
        AutoTrade = false,
        AutoAcceptTrade = false,
        AutoAcceptRequireGold = false,
        AcceptUsername = "",
        TradeUsername = "",
        GameplayMode = "No TP Auto Play",
        ReplayOnDisconnect = true,   -- always on, no toggle in the menu
        RejoinOnDisconnect = true,   -- always on, no toggle in the menu
        ReplayTime = ""
    }

    -- DODGE BOOST STATE: a pool of "burst" studs (see SETTINGS.DodgeBoostStuds) that drains while actively dodging
    -- and refills otherwise. Kept on the UI table like the rest of the dodge helpers below.
    UI.dodgeBoostPool = SETTINGS.DodgeBoostStuds
    UI.dodgeBoostLastPos = nil
    UI.dodgeBoostNormalSpeed = nil

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
    local lastStartValueTime = os.clock()
    local partyWasFull = false
    local hasReplayedFromTime = false
    local hasSentStageLoss = false
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
        UI.hazardIgnoreCache = setmetatable({}, { __mode = "k" }) -- part -> ignored?, rebuilt whenever the keywords change
        table.insert(parsedIgnoreKeywords, "macropathnode")
        if SETTINGS.IgnoreKeywords and SETTINGS.IgnoreKeywords ~= "" then
            for word in string.gmatch(SETTINGS.IgnoreKeywords, "([^,]+)") do
                local cleanWord = word:match("^%s*(.-)%s*$"):lower()
                if cleanWord ~= "" then table.insert(parsedIgnoreKeywords, cleanWord) end
            end
        end
    end
    updateIgnoreKeywords()

    -- ALWAYS-DODGE LIST: attack part names typed in the Setting tab (SETTINGS.DodgeList) plus names learned from damage
    -- (SETTINGS.LearnedAttacks). Parts named like spawn / arena pieces are never attacks, whatever else they match.
    UI.notAttackNames = { "spawnpart", "spawnlocation", "arena", "baseplate" }
    function UI.isNotAttackName(lname)
        for _, n in ipairs(UI.notAttackNames) do
            if lname:find(n, 1, true) then return true end
        end
        return false
    end

    function UI.updateDodgeList()
        UI.parsedDodgeList = {}
        for word in string.gmatch(SETTINGS.DodgeList or "", "([^,]+)") do
            local cleanWord = word:match("^%s*(.-)%s*$"):lower()
            if cleanWord ~= "" then table.insert(UI.parsedDodgeList, cleanWord) end
        end
        UI.listCache = setmetatable({}, { __mode = "k" }) -- part -> "list" / "learned" / false
    end
    UI.updateDodgeList()

    -- "list", "learned" or nil
    function UI.attackListReason(obj)
        local cached = UI.listCache[obj]
        if cached ~= nil then return cached or nil end
        local reason = false
        local lname = obj.Name:lower()
        if not UI.isNotAttackName(lname) then
            if SETTINGS.LearnedAttacks[lname] then
                reason = "learned"
            else
                for _, kw in ipairs(UI.parsedDodgeList) do
                    if lname:find(kw, 1, true) then reason = "list"; break end
                end
            end
        end
        UI.listCache[obj] = reason
        return reason or nil
    end

    function UI.partShape(part)
        if part:IsA("Part") then
            if part.Shape == Enum.PartType.Ball then return "Ball" end
            if part.Shape == Enum.PartType.Cylinder then return "Cylinder" end
        end
        return "Box"
    end

    -- Where a part really is and how big it really looks. Telegraph circles are often a tiny part with a big scaled
    -- SpecialMesh / BlockMesh / CylinderMesh, so Part.Size alone can be many times too small. Mesh-drawn shapes are
    -- measured as boxes (a box always contains the circle or ball drawn inside it).
    function UI.partGeometry(part)
        local cf, size, shape = part.CFrame, part.Size, UI.partShape(part)
        local mesh = part:FindFirstChildWhichIsA("DataModelMesh")
        if mesh then
            local scale = mesh.Scale
            -- a FileMesh ignores Part.Size (its own size times Scale); the other mesh types stretch the part by Scale
            local meshSize = (mesh:IsA("SpecialMesh") and mesh.MeshType == Enum.MeshType.FileMesh) and scale or size * scale
            size = Vector3.new(math.max(size.X, meshSize.X), math.max(size.Y, meshSize.Y), math.max(size.Z, meshSize.Z))
            if mesh.Offset.Magnitude > 0.01 then cf = cf * CFrame.new(mesh.Offset) end
            shape = "Box"
        end
        return cf, size, shape
    end

    -- an invisible part that shows a picture (Decal / Texture / SurfaceGui) is how many games draw ground circles
    function UI.hasVisual(part)
        for _, c in ipairs(part:GetChildren()) do
            if (c:IsA("Decal") and c.Transparency < 1) or (c:IsA("SurfaceGui") and c.Enabled) then return true end
        end
        return false
    end

    function UI.refreshAttackRows()
        local function paint(row, text, on)
            if not row then return end
            row.Text = text .. (on and "ON" or "OFF")
            row.BackgroundColor3 = on and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
        end
        paint(UI.learnAttacksRow, "Learn Attacks From Damage: ", SETTINGS.LearnAttacks)
        paint(UI.attackEspRow, "Show Attack ESP: ", SETTINGS.ShowAttackEsp)
        if UI.forgetLearnedBtn then
            local n = 0
            for _ in pairs(SETTINGS.LearnedAttacks) do n = n + 1 end
            for _ in pairs(SETTINGS.LearnedAnims) do n = n + 1 end
            UI.forgetLearnedBtn.Text = string.format("Forget Learned Attacks (%d)", n)
        end
    end

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

        if not SETTINGS.AutoLobbyEnabled then 
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
    local NCL_LOGO_B64 = "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"
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

    -- Discord logo (128x128 PNG, base64), used for the Discord icon on buttons throughout the UI
    local DISCORD_LOGO_B64 = "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"
    local discordLogoBytes
    local function getDiscordLogoBytes()
        if discordLogoBytes then return discordLogoBytes end
        local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        local lookup = {}
        for i = 1, #chars do lookup[chars:sub(i, i)] = i - 1 end
        local out, bits, nbits = {}, 0, 0
        for i = 1, #DISCORD_LOGO_B64 do
            local v = lookup[DISCORD_LOGO_B64:sub(i, i)]
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
        discordLogoBytes = table.concat(out)
        return discordLogoBytes
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

    -- "05:30" -> 330 (seconds). Returns nil if the text isn't a mm:ss countdown.
    local function parseTimeToSeconds(text)
        local m, s = tostring(text or ""):match("(%d+):(%d+)")
        if m and s then return tonumber(m) * 60 + tonumber(s) end
        return nil
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

    local function buildStatusEmbed(clearTime, title, rewardData, embedColor)
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
            ["title"] = title or ("⚔️ " .. "Dungeon Quest Reborn"),
            ["color"] = embedColor or 5814783,
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

    -- posted once per dungeon attempt when the countdown timer hits 0:00 (see the STAGE LOSS check in the main loop)
    local function sendStageLossWebhook()
        local url = cleanWebhookUrl(SETTINGS.Webhook)
        if url == "" then return end
        local elapsed = os.clock() - runStartTime
        local timeText = string.format("%dm %ds", math.floor(elapsed / 60), math.floor(elapsed % 60))
        runStartTime = os.clock()
        postWebhook(url, buildStatusEmbed(timeText, "💀 STAGE LOSS - Time Ran Out", nil, 15158332), "loss")
    end
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
    DodgeBoostStuds = SETTINGS.DodgeBoostStuds,
    ShowDodgeBoostBar = SETTINGS.ShowDodgeBoostBar,
    WaypointTriggerDist = SETTINGS.WaypointTriggerDist,
    MaxNodeDistance = SETTINGS.MaxNodeDistance,
    WallRayLength = SETTINGS.WallRayLength,
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
    RemoveMap = SETTINGS.RemoveMap,
    FpsBoost = SETTINGS.FpsBoost,
    DodgeList = SETTINGS.DodgeList,
    LearnAttacks = SETTINGS.LearnAttacks,
    ShowAttackEsp = SETTINGS.ShowAttackEsp,
    LearnedAttacks = SETTINGS.LearnedAttacks,
    LearnedAnims = SETTINGS.LearnedAnims,
    ShowRangeCircle = SETTINGS.ShowRangeCircle,
    AutoHideUI = SETTINGS.AutoHideUI,
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

    -- BRAND MARK: small rounded icon with a gradient letter, used for Discord / Linkvertise / LootLab
    -- buttons since real logo images aren't uploaded to the executor workspace (see createLogoMark above).
    local function createBrandMark(parent, letter, colorA, colorB, bg, sizeFraction)
        local box = Instance.new("Frame")
        box.Size = UDim2.new(1, 0, 1, 0)
        box.BackgroundColor3 = bg or Color3.fromRGB(10, 14, 26)
        box.BorderSizePixel = 0
        box.Parent = parent
        local boxCorner = Instance.new("UICorner")
        boxCorner.CornerRadius = UDim.new(0.26, 0)
        boxCorner.Parent = box

        local mark = Instance.new("TextLabel")
        mark.Size = UDim2.new(1, 0, 1, 0)
        mark.BackgroundTransparency = 1
        mark.Text = letter
        mark.Font = Enum.Font.GothamBlack
        mark.TextSize = 16
        mark.ZIndex = box.ZIndex + 1
        mark.TextColor3 = Color3.fromRGB(255, 255, 255)
        mark.Parent = box
        local function fitText()
            local h = box.AbsoluteSize.Y
            if h > 0 then mark.TextSize = math.clamp(math.floor(h * (sizeFraction or 0.5)), 6, 60) end
        end
        box:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitText)
        fitText()
        local gradient = Instance.new("UIGradient")
        gradient.Color = ColorSequence.new(colorA, colorB)
        gradient.Rotation = 45
        gradient.Parent = mark
        return box
    end
    UI.createBrandMark = createBrandMark

    -- DISCORD MARK: the real Discord logo (written once to the executor workspace, then loaded via
    -- getcustomasset), falling back to the gradient "D" brand mark if the executor lacks that API.
    local function createDiscordMark(parent, zIndex)
        -- draw the gradient "D" mark first so something always shows, then try to overlay the
        -- real logo image on top - if getcustomasset fails or returns a broken asset id, the
        -- "D" mark underneath still renders instead of leaving the icon blank
        local base = createBrandMark(parent, "D", Color3.fromRGB(88, 101, 242), Color3.fromRGB(114, 137, 218), Color3.fromRGB(10, 12, 22))
        base.ZIndex = zIndex or 1
        pcall(function()
            if writefile and getcustomasset then
                local path = FOLDER_NAME .. "/discordlogo.png"
                if not (isfile and isfile(path)) then writefile(path, getDiscordLogoBytes()) end
                local asset = getcustomasset(path)
                if asset and tostring(asset) ~= "" then
                    local img = Instance.new("ImageLabel")
                    img.Size = UDim2.new(1, 0, 1, 0)
                    img.BackgroundTransparency = 1
                    img.Image = asset
                    img.ScaleType = Enum.ScaleType.Fit
                    img.ZIndex = base.ZIndex + 2
                    img.Parent = parent
                end
            end
        end)
        return base
    end
    UI.createDiscordMark = createDiscordMark
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

    -- .pill: rounded chip holding the state dot + state text (IDLE / MACRO ACTIVE / RECORDING). The live-state loop
    -- below keeps writing UI.stateDot / UI.stateLabel colours as before; the pill just follows the label colour
    -- (grey idle, green active, red recording). No blinking dot.
    local statePill = Instance.new("Frame")
    statePill.Size = UDim2.new(0, 150, 0, 28)
    statePill.Position = UDim2.new(0, 246, 0, 18)
    statePill.BackgroundColor3 = T.muted
    statePill.BackgroundTransparency = 0.88
    statePill.BorderSizePixel = 0
    statePill.Parent = header
    round(statePill, 14)
    local statePillEdge = stroke(statePill, T.muted, 1)
    statePillEdge.Transparency = 0.6

    UI.stateDot = Instance.new("Frame")
    UI.stateDot.AnchorPoint = Vector2.new(0, 0.5)
    UI.stateDot.Size = UDim2.new(0, 8, 0, 8)
    UI.stateDot.Position = UDim2.new(0, 12, 0.5, 0)
    UI.stateDot.BackgroundColor3 = T.muted
    UI.stateDot.BorderSizePixel = 0
    UI.stateDot.Parent = statePill
    round(UI.stateDot, 4)

    UI.stateLabel = makeText(statePill, "IDLE", 12, T.muted, Enum.Font.GothamBold)
    UI.stateLabel.Size = UDim2.new(1, -36, 1, 0)
    UI.stateLabel.Position = UDim2.new(0, 28, 0, 0)
    do
        local function tintPill()
            statePill.BackgroundColor3 = UI.stateLabel.TextColor3
            statePillEdge.Color = UI.stateLabel.TextColor3
        end
        UI.stateLabel:GetPropertyChangedSignal("TextColor3"):Connect(tintPill)
        tintPill()
    end

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

    UI.fpsQuickBtn = makeWindowButton(580)
    UI.fpsQuickBtn.Font = Enum.Font.GothamBlack
    UI.fpsQuickBtn.TextSize = 9
    UI.fpsQuickBtn.TextColor3 = T.text
    UI.fpsQuickBtn.Text = "FPS"

    UI.autoHideQuickBtn = makeWindowButton(622)
    UI.autoHideQuickBtn.Font = Enum.Font.GothamBold
    UI.autoHideQuickBtn.TextSize = 15
    UI.autoHideQuickBtn.TextColor3 = T.text
    UI.autoHideQuickBtn.Text = "👁"
    statusLabel.Size = UDim2.new(0, 164, 1, 0)

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
                local ok, opts = pcall(getOptionsFunc)
                if not ok or type(opts) ~= "table" or #opts == 0 then
                    opts = {"Easy", "Medium", "Hard", "Insane", "Nightmare"}
                end
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
                    optBtn.ZIndex = 10
                    optBtn.Parent = dropdownContainer
                    round(optBtn, 6)

                    optBtn.MouseButton1Click:Connect(function()
                        currentVal = opt
                        pcall(callback, opt)
                        closeDropdown()
                    end)
                    height = height + 28
                end
                dropdownContainer.Size = UDim2.new(1, 0, 0, math.max(height, 28))
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

    local function getAvailableMaps()
        local maps = {}
        pcall(function()
            local scroll = findNested(player, "PlayerGui", "queueGui", "chooseDungeon", "backgroundFillLeft", "ScrollingFrame")
            if scroll then
                for _, child in ipairs(scroll:GetChildren()) do
                    if (child:IsA("ImageLabel") or child:IsA("ImageButton") or child:IsA("Frame"))
                    and not child.Name:lower():find("layout") and not child.Name:lower():find("padding") then
                        table.insert(maps, child.Name)
                    end
                end
            end
        end)
        if #maps == 0 then return {"Desert Ruins", "Volcanic Chambers", "King's Castle", "Underworld", "Samurai Palace"} end
        return maps
    end

    local function getAvailableDifficulties()
        local diffs = {}
        pcall(function()
            local pGui = player:FindFirstChild("PlayerGui")
            if not pGui then return end
            local qGui = pGui:FindFirstChild("queueGui")
            local cd = qGui and (qGui:FindFirstChild("chooseDungeon") or qGui:FindFirstChild("ChooseDungeon"))
            if not cd then return end

            local rightFill = cd:FindFirstChild("backgroundFillRight") or cd:FindFirstChild("BackgroundFillRight")
            if not rightFill then return end

            local container = rightFill:FindFirstChild("difficultyPanel")
                or rightFill:FindFirstChild("DifficultyPanel")
                or rightFill:FindFirstChild("stagePanel")
                or rightFill:FindFirstChild("StagePanel")
                or rightFill:FindFirstChildWhichIsA("ScrollingFrame")
                or rightFill

            for _, child in ipairs(container:GetChildren()) do
                if child:IsA("GuiObject") and not child:IsA("UIListLayout") and not child:IsA("UIGridLayout") and not child:IsA("UIPadding") and not child:IsA("UIStroke") and not child:IsA("UICorner") then
                    local name = child.Name
                    local lower = name:lower()
                    if not lower:find("panel") and not lower:find("drop") and not lower:find("layout") and not lower:find("template") and not lower:find("padding") then
                        local text = name
                        local lbl = child:FindFirstChildWhichIsA("TextLabel") or (child:IsA("TextLabel") and child) or (child:IsA("TextButton") and child)
                        if lbl and lbl.Text and lbl.Text ~= "" and #lbl.Text < 30 then
                            local lt = lbl.Text:lower()
                            if not lt:find("panel") and not lt:find("drop") and not lt:match("^lvl") and not lt:match("^req") and lt ~= "play" then
                                text = lbl.Text
                            end
                        end
                        local clean = tostring(text):gsub("^%s+", ""):gsub("%s+$", "")
                        if clean ~= "" then
                            table.insert(diffs, clean)
                        end
                    end
                end
            end
        end)

        local cleaned = {}
        local seen = {}
        for _, d in ipairs(diffs) do
            local clean = tostring(d):gsub("^%s+", ""):gsub("%s+$", "")
            local lower = clean:lower()
            if not seen[lower] and not lower:find("panel") and not lower:find("drop") then
                seen[lower] = true
                table.insert(cleaned, clean)
            end
        end

        if #cleaned > 0 then
            return cleaned
        end

        return {"Easy", "Medium", "Hard", "Insane", "Nightmare"}
    end

    -- PAGES
    -- layout follows ncl-macro.html: sidebar (196px) | page (1fr) | right cards (270px), 12px gutters
    local SIDEBAR_W = 140
    local PAGE_X = 162
    local PAGE_W, PAGE_H = 472, 388
    local RIGHT_COL_X = PAGE_X + PAGE_W + 10

    local function createPage(title, subtitle)
        local page = Instance.new("ScrollingFrame")
        page.Size = UDim2.new(0, PAGE_W, 0, PAGE_H)
        page.Position = UDim2.new(0, PAGE_X, 0, 84)
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
    local settingsPage = createPage("Setting", "Combat distance, attacking and dodging.")
    local tradePage = createPage("Auto Trade", "Send and accept trades automatically.")
    local buildPage = createPage("Build", "Instantly spend all your free skill points.")
    local miscPage = createPage("Misc", "Lobby routine, gameplay mode and extras.")
    local joinPage = createPage("Auto Join", "Join a host's lobby and leave when they leave.")

    -- SIDEBAR (.sidebar in ncl-macro.html): vertical menu card on the left, Discord button pinned
    -- to its bottom. Colors taken straight from the :root palette of the reference design.
    local NAV_BLUE    = Color3.fromRGB(79, 124, 255)   -- --blue
    local NAV_VIOLET  = Color3.fromRGB(139, 92, 246)   -- --violet
    local NAV_EDGE    = Color3.fromRGB(124, 92, 255)   -- .nav-item.active border
    local NAV_ICON_ON = Color3.fromRGB(147, 170, 255)  -- .nav-item.active svg

    local sidebar = Instance.new("Frame")
    sidebar.Size = UDim2.new(0, SIDEBAR_W, 0, 444)
    sidebar.Position = UDim2.new(0, 12, 0, 84)
    sidebar.BackgroundColor3 = T.panel
    sidebar.BorderSizePixel = 0
    sidebar.Parent = body
    round(sidebar, 14)
    stroke(sidebar)

    local sidebarPad = Instance.new("UIPadding")
    sidebarPad.PaddingTop = UDim.new(0, 8)
    sidebarPad.PaddingBottom = UDim.new(0, 8)
    sidebarPad.PaddingLeft = UDim.new(0, 8)
    sidebarPad.PaddingRight = UDim.new(0, 8)
    sidebarPad.Parent = sidebar

    -- TABS (vertically scrollable: drag/swipe up-down when there are more tabs than fit)
    local tabBar = Instance.new("ScrollingFrame")
    tabBar.Size = UDim2.new(1, 0, 1, -48)
    tabBar.BackgroundTransparency = 1
    tabBar.BorderSizePixel = 0
    tabBar.ScrollingDirection = Enum.ScrollingDirection.Y
    tabBar.ScrollBarThickness = 3
    tabBar.ScrollBarImageColor3 = T.accent2
    tabBar.ScrollBarImageTransparency = 0.4
    tabBar.CanvasSize = UDim2.new(0, 0, 0, 0)
    tabBar.AutomaticCanvasSize = Enum.AutomaticSize.Y
    tabBar.Parent = sidebar

    local tabPad = Instance.new("UIPadding")
    tabPad.PaddingTop = UDim.new(0, 2)
    tabPad.PaddingBottom = UDim.new(0, 2)
    tabPad.PaddingRight = UDim.new(0, 2)
    tabPad.Parent = tabBar

    local tabLayout = Instance.new("UIListLayout")
    tabLayout.FillDirection = Enum.FillDirection.Vertical
    tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
    tabLayout.Padding = UDim.new(0, 4)
    tabLayout.Parent = tabBar

    -- NAV ICONS: the reference uses stroked SVGs, so these are drawn from plain Frames
    -- (bars, rounded boxes, rotated bars) - always render, and recolor like a `stroke: currentColor`.
    local function iconPart(box, x, y, w, h, opts)
        opts = opts or {}
        local p = Instance.new("Frame")
        p.Size = UDim2.new(0, w, 0, h)
        p.Position = UDim2.new(0, x, 0, y)
        p.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        p.BorderSizePixel = 0
        p.Rotation = opts.rot or 0
        p.Parent = box
        if opts.radius then round(p, opts.radius) end
        if opts.hollow then
            p.BackgroundTransparency = 1
            stroke(p, Color3.fromRGB(255, 255, 255), opts.hollow)
        end
        return p
    end

    local function paintIcon(box, color)
        for _, part in ipairs(box:GetDescendants()) do
            if part:IsA("Frame") then part.BackgroundColor3 = color end
            if part:IsA("UIStroke") then part.Color = color end
        end
    end

    -- every icon is drawn inside an 18x18 box, same as the 18px svg in the design
    local navIcons = {
        ["Macro"] = function(b)            -- rounded square + play chevron
            iconPart(b, 1, 1, 16, 16, { radius = 5, hollow = 1.5 })
            iconPart(b, 5, 6, 7, 2, { radius = 1, rot = 45 })
            iconPart(b, 5, 11, 7, 2, { radius = 1, rot = -45 })
        end,
        ["Webhook"] = function(b)          -- bell
            iconPart(b, 4, 3, 10, 10, { radius = 5, hollow = 1.5 })
            iconPart(b, 2, 12, 14, 2, { radius = 1 })
            iconPart(b, 7, 15, 4, 3, { radius = 2 })
        end,
        ["Auto Sell"] = function(b)        -- price tag
            iconPart(b, 4, 4, 11, 11, { radius = 3, hollow = 1.5, rot = 45 })
            iconPart(b, 6, 6, 3, 3, { radius = 2 })
        end,
        ["Setting"] = function(b)          -- sliders
            iconPart(b, 2, 4, 14, 2, { radius = 1 })
            iconPart(b, 11, 2, 6, 6, { radius = 3, hollow = 1.5 })
            iconPart(b, 2, 9, 14, 2, { radius = 1 })
            iconPart(b, 4, 7, 6, 6, { radius = 3, hollow = 1.5 })
            iconPart(b, 2, 14, 14, 2, { radius = 1 })
            iconPart(b, 9, 12, 6, 6, { radius = 3, hollow = 1.5 })
        end,
        ["Auto Trade"] = function(b)       -- swap arrows
            iconPart(b, 3, 5, 12, 2, { radius = 1 })
            iconPart(b, 11, 3, 5, 2, { radius = 1, rot = 45 })
            iconPart(b, 11, 7, 5, 2, { radius = 1, rot = -45 })
            iconPart(b, 3, 11, 12, 2, { radius = 1 })
            iconPart(b, 2, 9, 5, 2, { radius = 1, rot = -45 })
            iconPart(b, 2, 13, 5, 2, { radius = 1, rot = 45 })
        end,
        ["Auto Join"] = function(b)        -- person
            iconPart(b, 6, 2, 6, 6, { radius = 3, hollow = 1.5 })
            iconPart(b, 3, 10, 12, 7, { radius = 4, hollow = 1.5 })
        end,
        ["Build"] = function(b)            -- arrow up on a base
            iconPart(b, 8, 3, 2, 10, { radius = 1 })
            iconPart(b, 5, 4, 5, 2, { radius = 1, rot = -45 })
            iconPart(b, 8, 4, 5, 2, { radius = 1, rot = 45 })
            iconPart(b, 5, 15, 8, 2, { radius = 1 })
        end,
        ["Misc"] = function(b)             -- three dots
            iconPart(b, 3, 8, 3, 3, { radius = 2 })
            iconPart(b, 8, 8, 3, 3, { radius = 2 })
            iconPart(b, 13, 8, 3, 3, { radius = 2 })
        end,
    }

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
        btn.Size = UDim2.new(1, 0, 0, 40)
        -- white base so the UIGradient below shows its own colors; switchTab() keeps driving
        -- BackgroundTransparency (0 = active, 1 = idle, .85 = hover) exactly like before
        btn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        btn.BackgroundTransparency = 1
        btn.Text = text
        btn.TextColor3 = T.muted
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 13
        btn.BorderSizePixel = 0
        btn.TextSize = 12
        btn.TextTransparency = 1  -- the visible caption is the label below, kept in sync
        btn.AutoButtonColor = false
        btn.Parent = tabBar
        round(btn, 10)

        -- .nav-item.active background: linear-gradient(90deg, rgba(79,124,255,.26), rgba(139,92,246,.10))
        local navGrad = Instance.new("UIGradient")
        navGrad.Rotation = 0
        navGrad.Color = ColorSequence.new(NAV_BLUE, NAV_VIOLET)
        navGrad.Transparency = NumberSequence.new(0.74, 0.90)
        navGrad.Parent = btn

        local edge = stroke(btn, NAV_EDGE, 1)
        edge.Transparency = 1

        -- .nav-item.active::before - the left indicator strip
        local bar = Instance.new("Frame")
        bar.Size = UDim2.new(0, 3, 1, -12)
        bar.Position = UDim2.new(0, 0, 0, 6)
        bar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        bar.BorderSizePixel = 0
        bar.Visible = false
        bar.Parent = btn
        round(bar, 2)
        local barGrad = Instance.new("UIGradient")
        barGrad.Rotation = 90
        barGrad.Color = ColorSequence.new(NAV_BLUE, NAV_VIOLET)
        barGrad.Parent = bar
        local barGlow = Instance.new("UIStroke")
        barGlow.Color = NAV_VIOLET
        barGlow.Thickness = 2
        barGlow.Transparency = 0.6
        barGlow.Parent = bar

        -- icon + label row (the flex row of .nav-item, gap 12px)
        local content = Instance.new("Frame")
        content.Size = UDim2.new(1, -13, 1, 0)
        content.Position = UDim2.new(0, 13, 0, 0)
        content.BackgroundTransparency = 1
        content.Parent = btn

        local contentLayout = Instance.new("UIListLayout")
        contentLayout.FillDirection = Enum.FillDirection.Horizontal
        contentLayout.VerticalAlignment = Enum.VerticalAlignment.Center
        contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
        contentLayout.Padding = UDim.new(0, 9)
        contentLayout.Parent = content

        local iconBox = Instance.new("Frame")
        iconBox.Size = UDim2.new(0, 18, 0, 18)
        iconBox.BackgroundTransparency = 1
        iconBox.LayoutOrder = 1
        iconBox.Parent = content
        if navIcons[text] then navIcons[text](iconBox) end

        local label = makeText(content, text, 13, T.muted, Enum.Font.GothamBold)
        label.Size = UDim2.new(1, -27, 1, 0)  -- rest of the row after the 18px icon + 9px gap
        label.LayoutOrder = 2
        label.TextTruncate = Enum.TextTruncate.AtEnd

        -- switchTab() and the hover handlers only touch TextColor3 / BackgroundTransparency /
        -- bar.Visible, so the extra sidebar styling follows those instead of being set directly
        btn:GetPropertyChangedSignal("TextColor3"):Connect(function()
            label.TextColor3 = btn.TextColor3
        end)
        local function syncActive()
            local active = bar.Visible
            edge.Transparency = active and 0.62 or 1
            paintIcon(iconBox, active and NAV_ICON_ON or T.muted)
        end
        bar:GetPropertyChangedSignal("Visible"):Connect(syncActive)
        syncActive()

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
    -- Static look of the .recbar card in ncl-all-tabs.html: big record button + macro name on top, four small tool
    -- buttons below. The MACRO PATHS timeline and the progress panel are NOT built (they need data this script
    -- does not have yet). Every button/input keeps its old variable name and handler.
    local MACRO_EDGE = Color3.fromRGB(35, 40, 72)     -- --border
    local MACRO_FIELD = Color3.fromRGB(9, 11, 23)     -- .inp #090b17
    local MACRO_TOOL = Color3.fromRGB(24, 28, 54)     -- --surface-2

    local recCard = Instance.new("Frame")
    recCard.Size = UDim2.new(1, 0, 0, 114)
    recCard.BackgroundColor3 = Color3.fromRGB(17, 20, 42)   -- --surface
    recCard.BorderSizePixel = 0
    recCard.Parent = macroPage
    round(recCard, 14)
    stroke(recCard, MACRO_EDGE, 1)
    local recPad = Instance.new("UIPadding")
    recPad.PaddingTop = UDim.new(0, 12)
    recPad.PaddingBottom = UDim.new(0, 12)
    recPad.PaddingLeft = UDim.new(0, 14)
    recPad.PaddingRight = UDim.new(0, 14)
    recPad.Parent = recCard
    local recLayout = Instance.new("UIListLayout")
    recLayout.Padding = UDim.new(0, 10)
    recLayout.SortOrder = Enum.SortOrder.LayoutOrder
    recLayout.Parent = recCard

    -- One big record button that swaps between "Start Recording" (blue) and "Stop Recording" (red). They are still the
    -- two old buttons with their old click handlers; only one is visible at a time (UI.refreshRecInfo below).
    local macroRowA = MakeRow(recCard, 46)
    local recordBtn = MakeButton("Start Recording", Color3.fromRGB(79, 124, 255), macroRowA)   -- .rec-btn
    recordBtn.Size = rowSize(0.42, 2)
    local stopRecordBtn = MakeButton("Stop Recording", Color3.fromRGB(233, 55, 95), macroRowA) -- .rec-btn.on
    stopRecordBtn.Size = rowSize(0.42, 2)
    stopRecordBtn.Visible = false
    for _, b in ipairs({ recordBtn, stopRecordBtn }) do
        b.Font = Enum.Font.GothamBold
        b.TextSize = 13
        local c = b:FindFirstChildOfClass("UICorner")
        if c then c.CornerRadius = UDim.new(0, 12) end
        -- .rec-btn .dot: white dot left of the caption (the padding moves the caption right, so the dot sits at -8)
        local btnPad = Instance.new("UIPadding")
        btnPad.PaddingLeft = UDim.new(0, 22)
        btnPad.Parent = b
        local btnDot = Instance.new("Frame")
        btnDot.AnchorPoint = Vector2.new(0, 0.5)
        btnDot.Position = UDim2.new(0, -8, 0.5, 0)
        btnDot.Size = UDim2.new(0, 12, 0, 12)
        btnDot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        btnDot.BorderSizePixel = 0
        btnDot.Parent = b
        round(btnDot, 6)
    end
    local stopGlow = stroke(stopRecordBtn, Color3.fromRGB(139, 92, 246), 2)   -- violet ring around the active button
    stopGlow.Transparency = 0.3

    -- .rec-info: macro name (still the dropdown button UI.macroDropBtn, click = pick a macro) + a small status line
    local recInfo = Instance.new("Frame")
    recInfo.Size = rowSize(0.58, 2)
    recInfo.BackgroundTransparency = 1
    recInfo.Parent = macroRowA
    UI.macroDropBtn = Instance.new("TextButton")
    UI.macroDropBtn.Position = UDim2.new(0, 0, 0, 3)
    UI.macroDropBtn.Size = UDim2.new(1, 0, 0, 22)
    UI.macroDropBtn.BackgroundTransparency = 1
    UI.macroDropBtn.TextColor3 = T.muted
    UI.macroDropBtn.Font = Enum.Font.GothamBold
    UI.macroDropBtn.TextSize = 15
    UI.macroDropBtn.TextXAlignment = Enum.TextXAlignment.Left
    UI.macroDropBtn.TextTruncate = Enum.TextTruncate.AtEnd
    UI.macroDropBtn.Text = "  Select a macro...   ▼"
    UI.macroDropBtn.BorderSizePixel = 0
    UI.macroDropBtn.Parent = recInfo
    UI.recSubLabel = makeText(recInfo, "0 paths · ready to run", 12, T.muted, Enum.Font.Gotham)
    UI.recSubLabel.Position = UDim2.new(0, 8, 0, 27)
    UI.recSubLabel.Size = UDim2.new(1, -8, 0, 16)
    UI.recSubLabel.TextTruncate = Enum.TextTruncate.AtEnd

    -- display only: reads isRecording / #waypoints, never writes them
    function UI.refreshRecInfo()
        local rec = isRecording
        recordBtn.Visible = not rec
        stopRecordBtn.Visible = rec
        if rec then
            UI.recSubLabel.Text = "Recording your actions..."
        else
            local n = #waypoints
            UI.recSubLabel.Text = string.format("%d %s · ready to run", n, n == 1 and "path" or "paths")
        end
    end
    -- the click handlers further down flip isRecording, so refresh one tick later; the state pill text is a backup
    recordBtn.MouseButton1Click:Connect(function() task.defer(UI.refreshRecInfo) end)
    stopRecordBtn.MouseButton1Click:Connect(function() task.defer(UI.refreshRecInfo) end)
    UI.stateLabel:GetPropertyChangedSignal("Text"):Connect(UI.refreshRecInfo)

    local macroRowB = MakeRow(recCard, 34)
    -- TODO: ganti karakter teks ini ke ImageLabel dengan rbxassetid (icons-png/128px/tool-*.png belum di-upload)
    local addWaypointBtn = MakeButton("+  Path", MACRO_TOOL, macroRowB)
    local exportBtn = MakeButton("↓  Export", MACRO_TOOL, macroRowB)
    local importBtn = MakeButton("↑  Import", MACRO_TOOL, macroRowB)
    local clearWaypointsBtn = MakeButton("🗑  Clear", MACRO_TOOL, macroRowB)
    for _, b in ipairs({ addWaypointBtn, exportBtn, importBtn, clearWaypointsBtn }) do   -- .tool
        b.Size = rowSize(0.25, 4)
        b.TextColor3 = T.muted
        b.TextSize = 12
        local c = b:FindFirstChildOfClass("UICorner")
        if c then c.CornerRadius = UDim.new(0, 9) end
        stroke(b, MACRO_EDGE, 1)
    end

    local macroRowC = MakeRow(macroPage, 38)
    local nameInput = MakeInput("Macro name (e.g. Run1)", macroRowC)
    nameInput.Size = rowSize(0.6, 3)
    local saveBtn = MakeButton("Save", Color3.fromRGB(19, 156, 98), macroRowC)      -- .b.green
    saveBtn.Size = rowSize(0.2, 3)
    local deleteBtn = MakeButton("Delete", Color3.fromRGB(194, 31, 74), macroRowC)  -- .b.red
    deleteBtn.Size = rowSize(0.2, 3)
    for _, b in ipairs({ saveBtn, deleteBtn }) do
        b.Font = Enum.Font.GothamBold
        local c = b:FindFirstChildOfClass("UICorner")
        if c then c.CornerRadius = UDim.new(0, 10) end
    end

    local importInput = MakeInput("Paste JSON to import...", macroPage)
    importInput.Size = UDim2.new(1, 0, 0, 38)
    for _, box in ipairs({ nameInput, importInput }) do   -- .inp
        box.BackgroundColor3 = MACRO_FIELD
        local c = box:FindFirstChildOfClass("UICorner")
        if c then c.CornerRadius = UDim.new(0, 10) end
        local s = box:FindFirstChildOfClass("UIStroke")
        if s then s.Color = MACRO_EDGE end
    end

    -- floating macro list (opened by the dropdown button, lives above everything)
    -- The popup is a dark rounded card with a violet edge. Its rows are still created by refreshMacroList() (same click
    -- handlers); ChildAdded below only restyles them (taller rounded rows, hover, check mark on the selected macro).
    local macroScroll = Instance.new("ScrollingFrame")
    macroScroll.Size = UDim2.new(0, 340, 0, 130)
    macroScroll.BackgroundColor3 = Color3.fromRGB(13, 16, 36)
    macroScroll.BorderSizePixel = 0
    macroScroll.ScrollBarThickness = 3
    macroScroll.ScrollBarImageColor3 = NAV_VIOLET
    macroScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    macroScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    macroScroll.ZIndex = 50
    macroScroll.Visible = false
    macroScroll.Parent = mainFrame
    round(macroScroll, 12)
    local macroScrollEdge = stroke(macroScroll, NAV_EDGE, 1)
    macroScrollEdge.Transparency = 0.35
    local macroScrollPad = Instance.new("UIPadding")
    macroScrollPad.PaddingTop = UDim.new(0, 6)
    macroScrollPad.PaddingBottom = UDim.new(0, 6)
    macroScrollPad.PaddingLeft = UDim.new(0, 6)
    macroScrollPad.PaddingRight = UDim.new(0, 8)
    macroScrollPad.Parent = macroScroll
    local UIListLayoutList = Instance.new("UIListLayout")
    UIListLayoutList.Parent = macroScroll
    UIListLayoutList.Padding = UDim.new(0, 4)
    UI.macroScroll = macroScroll

    local macroEmpty = makeText(macroScroll, "No saved macros yet", 12, T.muted, Enum.Font.Gotham)
    macroEmpty.Size = UDim2.new(1, 0, 0, 32)
    macroEmpty.ZIndex = 51
    macroEmpty.Visible = false

    macroScroll.ChildAdded:Connect(function(item)
        if not item:IsA("TextButton") then return end
        task.defer(function()   -- refreshMacroList() adds the UICorner right after parenting, so wait one step
            if not item.Parent then return end
            local selected = item.BackgroundColor3 == Color3.fromRGB(72, 92, 235)
            local rest = selected and Color3.fromRGB(44, 42, 104) or Color3.fromRGB(21, 25, 50)
            local hover = Color3.fromRGB(33, 39, 80)
            item.Size = UDim2.new(1, 0, 0, 32)
            item.BackgroundColor3 = rest
            item.AutoButtonColor = false
            item.Font = selected and Enum.Font.GothamBold or Enum.Font.Gotham
            item.TextSize = 13
            item.TextColor3 = selected and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(190, 196, 230)
            local itemCorner = item:FindFirstChildOfClass("UICorner")
            if itemCorner then itemCorner.CornerRadius = UDim.new(0, 8) end
            if selected then
                stroke(item, NAV_EDGE, 1)
                local check = makeText(item, "✓", 14, NAV_ICON_ON, Enum.Font.GothamBold, Enum.TextXAlignment.Right)
                check.AnchorPoint = Vector2.new(1, 0.5)
                check.Position = UDim2.new(1, -10, 0.5, 0)
                check.Size = UDim2.new(0, 18, 0, 18)
                check.ZIndex = 52
            end
            local function fade(color)
                pcall(function()
                    game:GetService("TweenService"):Create(item, TweenInfo.new(0.15), { BackgroundColor3 = color }):Play()
                end)
            end
            item.MouseEnter:Connect(function() if not selected then fade(hover) end end)
            item.MouseLeave:Connect(function() if not selected then fade(rest) end end)
        end)
    end)

    UI.macroDropBtn.MouseButton1Click:Connect(function()
        if macroScroll.Visible then
            macroScroll.Visible = false
            return
        end
        refreshMacroList()
        local n = 0
        for _, child in ipairs(macroScroll:GetChildren()) do
            if child:IsA("TextButton") then n = n + 1 end
        end
        macroEmpty.Visible = (n == 0)
        local scale = uiScale.Scale
        -- opens under the record row, as wide as the card, tall enough for the rows (max ~5 visible, then it scrolls)
        local cardPos = recCard.AbsolutePosition - mainFrame.AbsolutePosition
        local rowBottom = recInfo.AbsolutePosition.Y + recInfo.AbsoluteSize.Y - mainFrame.AbsolutePosition.Y
        local rows = math.max(n, 1)
        local height = math.min(rows * 32 + (rows - 1) * 4 + 12, 196)
        macroScroll.Position = UDim2.new(0, cardPos.X / scale, 0, rowBottom / scale + 8)
        macroScroll.Size = UDim2.new(0, recCard.AbsoluteSize.X / scale, 0, height)
        task.defer(function() macroScroll.Visible = true end)   -- after the rows were restyled, so no flash of the old look
    end)

    -- WEBHOOK TAB
    MakeSectionLabel("Webhook URL", webhookPage)
    UI.webhookInput = MakeInput("Paste Webhook URL...", webhookPage)
    UI.webhookInput.Text = SETTINGS.Webhook or ""
    UI.webhookInput.Size = UDim2.new(1, 0, 0, 38)                     -- .inp height 38
    UI.webhookInput.BackgroundColor3 = Color3.fromRGB(9, 11, 23)      -- .inp #090b17
    do
        local inCorner = UI.webhookInput:FindFirstChildOfClass("UICorner")
        if inCorner then inCorner.CornerRadius = UDim.new(0, 10) end
        local inStroke = UI.webhookInput:FindFirstChildOfClass("UIStroke")
        if inStroke then inStroke.Color = Color3.fromRGB(35, 40, 72) end
    end
    local webhookTestBtn = MakeButton("Send Test Message", Color3.fromRGB(79, 124, 255), webhookPage) -- .b.blue.wide.tall
    webhookTestBtn.Size = UDim2.new(1, 0, 0, 46)
    webhookTestBtn.Font = Enum.Font.GothamBold
    do
        local btnCorner = webhookTestBtn:FindFirstChildOfClass("UICorner")
        if btnCorner then btnCorner.CornerRadius = UDim.new(0, 10) end
    end
    webhookTestBtn.MouseButton1Click:Connect(function()
        SETTINGS.Webhook = UI.webhookInput.Text
        saveConfig()
        UI.sendTestWebhook(SETTINGS.Webhook)
    end)

    -- .status-line: dark rounded box, small dot + result text. UI.webhookResult stays the same TextLabel
    -- (postWebhook writes its .Text); the dot follows that text (green once a send succeeded).
    local WEBHOOK_DOT_IDLE = Color3.fromRGB(90, 96, 144)
    local resultBox = Instance.new("Frame")
    resultBox.Size = UDim2.new(1, 0, 0, 44)
    resultBox.BackgroundColor3 = Color3.fromRGB(10, 13, 28)           -- .status-line #0a0d1c
    resultBox.BorderSizePixel = 0
    resultBox.Parent = webhookPage
    round(resultBox, 10)
    stroke(resultBox, Color3.fromRGB(35, 40, 72), 1)

    local resultDot = Instance.new("Frame")
    resultDot.AnchorPoint = Vector2.new(0, 0.5)
    resultDot.Position = UDim2.new(0, 13, 0.5, 0)
    resultDot.Size = UDim2.new(0, 8, 0, 8)
    resultDot.BackgroundColor3 = WEBHOOK_DOT_IDLE
    resultDot.BorderSizePixel = 0
    resultDot.Parent = resultBox
    round(resultDot, 4)

    UI.webhookResult = makeText(resultBox, "Result: nothing sent yet.", 12, T.muted, Enum.Font.Gotham)
    UI.webhookResult.Position = UDim2.new(0, 30, 0, 0)
    UI.webhookResult.Size = UDim2.new(1, -43, 1, 0)
    UI.webhookResult.TextWrapped = true
    UI.webhookResult.TextYAlignment = Enum.TextYAlignment.Center
    UI.webhookResult:GetPropertyChangedSignal("Text"):Connect(function()
        resultDot.BackgroundColor3 = UI.webhookResult.Text:find("Sent OK", 1, true) and T.green or WEBHOOK_DOT_IDLE
    end)
    local webhookNote = makeText(webhookPage, "After each match a message with the run time, gold and items received is posted to this URL.", 12, T.muted, Enum.Font.Gotham)
    webhookNote.Size = UDim2.new(1, 0, 0, 34)
    webhookNote.TextWrapped = true
    webhookNote.TextYAlignment = Enum.TextYAlignment.Top

    -- SETTING TAB
    MakeSectionLabel("Distances", settingsPage)
    UI.minDistInput = MakeSettingRow("Min Combat Dist (Run Away):", SETTINGS.MinDistance, settingsPage)
    UI.maxDistInput = MakeSettingRow("Max Combat Dist (Kite):", SETTINGS.MaxDistance, settingsPage)
    UI.atkReachInput = MakeSettingRow("Attack Reach (Max Fire Dist):", SETTINGS.AttackReach, settingsPage)
    UI.dodgeBufferInput = MakeSettingRow("Dodge Buffer (Margin):", SETTINGS.DodgeBuffer, settingsPage)
    UI.dodgeBoostInput = MakeSettingRow("Dodge Boost (Burst Studs):", SETTINGS.DodgeBoostStuds, settingsPage)

    -- .fr2 rows: bold title + small hint on the left, right-aligned number field with a "studs" unit on the right.
    -- The TextBox returned by MakeSettingRow is kept as is (same object, same FocusLost handlers below); only its
    -- look changes and a second label is added under the title.
    for _, def in ipairs({
        { UI.minDistInput, "Keep away from enemy", "Back off when an enemy gets closer than this" },
        { UI.maxDistInput, "Stay within range", "Move closer if the enemy is farther than this" },
        { UI.atkReachInput, "Start attacking at", "Only attack when the enemy is within this distance" },
        { UI.dodgeBufferInput, "Dodge safety margin", "Extra space to keep when dodging attacks" },
        { UI.dodgeBoostInput, "Dodge burst (0-10)", "Studs a dodge may burst ahead before slowing to a walk" },
    }) do
        local box, title, hint = def[1], def[2], def[3]
        local rowFrame = box.Parent
        rowFrame.Size = UDim2.new(1, 0, 0, 48)

        local titleLbl = rowFrame:FindFirstChildOfClass("TextLabel")
        titleLbl.Text = title
        titleLbl.Font = Enum.Font.GothamSemibold
        titleLbl.TextSize = 13
        titleLbl.Position = UDim2.new(0, 0, 0, 2)
        titleLbl.Size = UDim2.new(1, -148, 0, 18)

        local hintLbl = makeText(rowFrame, hint, 11, T.muted, Enum.Font.Gotham)
        hintLbl.Position = UDim2.new(0, 0, 0, 20)
        hintLbl.Size = UDim2.new(1, -148, 0, 26)
        hintLbl.TextWrapped = true
        hintLbl.TextYAlignment = Enum.TextYAlignment.Top

        box.AnchorPoint = Vector2.new(1, 0.5)
        box.Position = UDim2.new(1, 0, 0.5, 0)
        box.Size = UDim2.new(0, 132, 0, 38)
        box.BackgroundColor3 = Color3.fromRGB(9, 11, 23)     -- .inp #090b17
        box.TextColor3 = T.text
        box.Font = Enum.Font.Gotham
        box.TextXAlignment = Enum.TextXAlignment.Right
        local boxCorner = box:FindFirstChildOfClass("UICorner")
        if boxCorner then boxCorner.CornerRadius = UDim.new(0, 10) end
        local boxEdge = box:FindFirstChildOfClass("UIStroke")
        if boxEdge then boxEdge.Color = Color3.fromRGB(35, 40, 72) end
        local boxPad = Instance.new("UIPadding")
        boxPad.PaddingLeft = UDim.new(0, 10)
        boxPad.PaddingRight = UDim.new(0, 54)
        boxPad.Parent = box

        -- "studs" sits on top of the field's right edge (a sibling of the box, so the box's padding does not move it)
        local unitLbl = makeText(rowFrame, "studs", 11, Color3.fromRGB(90, 96, 144), Enum.Font.GothamBold, Enum.TextXAlignment.Right)
        unitLbl.AnchorPoint = Vector2.new(1, 0.5)
        unitLbl.Position = UDim2.new(1, -12, 0.5, 0)
        unitLbl.Size = UDim2.new(0, 40, 0, 14)
        unitLbl.ZIndex = box.ZIndex + 1
    end

    UI.dodgeBoostBarRow = MakeToggle("Dodge Boost Bar: " .. (SETTINGS.ShowDodgeBoostBar and "ON" or "OFF"), SETTINGS.ShowDodgeBoostBar, settingsPage)
    UI.dodgeBoostBarRow.Size = UDim2.new(1, 0, 0, 42)
    UI.dodgeBoostBarRow.MouseButton1Click:Connect(function()
        SETTINGS.ShowDodgeBoostBar = not SETTINGS.ShowDodgeBoostBar
        UI.dodgeBoostBarRow.Text = "Dodge Boost Bar: " .. (SETTINGS.ShowDodgeBoostBar and "ON" or "OFF")
        UI.dodgeBoostBarRow.BackgroundColor3 = SETTINGS.ShowDodgeBoostBar and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
        if not SETTINGS.ShowDodgeBoostBar and UI.hideDodgeBoostBar then UI.hideDodgeBoostBar() end
        saveConfig()
    end)
    local dodgeBoostNote = makeText(settingsPage, "A bar above your ability keys showing how much burst the dodge has left. Burns as you dodge, refills a few seconds after you stop.", 12, T.muted, Enum.Font.Gotham)
    dodgeBoostNote.Size = UDim2.new(1, 0, 0, 32)
    dodgeBoostNote.TextWrapped = true
    dodgeBoostNote.TextYAlignment = Enum.TextYAlignment.Top

    -- RANGE CIRCLES: rings on the ground around you (red = Min run-away, yellow = Max kite, green = Attack reach)
    UI.rangeCircleRow = MakeToggle("Show Range Circle: " .. (SETTINGS.ShowRangeCircle and "ON" or "OFF"), SETTINGS.ShowRangeCircle, settingsPage)
    UI.rangeCircleRow.Size = UDim2.new(1, 0, 0, 42)
    UI.rangeCircleRow.MouseButton1Click:Connect(function()
        SETTINGS.ShowRangeCircle = not SETTINGS.ShowRangeCircle
        UI.rangeCircleRow.Text = "Show Range Circle: " .. (SETTINGS.ShowRangeCircle and "ON" or "OFF")
        UI.rangeCircleRow.BackgroundColor3 = SETTINGS.ShowRangeCircle and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
        saveConfig()
    end)
    local rangeNote = makeText(settingsPage, "Draws 3 rings on the ground: red = keep-away, yellow = stay-within, green = attack range.", 12, T.muted, Enum.Font.Gotham)
    rangeNote.Size = UDim2.new(1, 0, 0, 32)
    rangeNote.TextWrapped = true
    rangeNote.TextYAlignment = Enum.TextYAlignment.Top

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

    MakeSectionLabel("Ignore these parts (never dodged)", settingsPage)
    UI.filterInput = MakeInput("e.g. ring1, ring2, safezone", settingsPage)
    UI.filterInput.Size = UDim2.new(1, 0, 0, 38)                      -- .inp height 38
    UI.filterInput.BackgroundColor3 = Color3.fromRGB(9, 11, 23)       -- .inp #090b17
    do
        local c = UI.filterInput:FindFirstChildOfClass("UICorner")
        if c then c.CornerRadius = UDim.new(0, 10) end
        local s = UI.filterInput:FindFirstChildOfClass("UIStroke")
        if s then s.Color = Color3.fromRGB(35, 40, 72) end
    end
    local hazardNote = makeText(settingsPage, "Parts with these words in their name are IGNORED by auto dodge. Put attack names in \"Always dodge\" below instead.", 12, T.muted, Enum.Font.Gotham)
    hazardNote.Size = UDim2.new(1, 0, 0, 32)
    hazardNote.TextWrapped = true
    hazardNote.TextYAlignment = Enum.TextYAlignment.Top

    -- ATTACK PREDICTION: always-dodge names, learning from damage, and the attack ESP overlay
    do
        MakeSectionLabel("Always dodge (attack names)", settingsPage)
        UI.dodgeListInput = MakeInput("e.g. bonusboss, fireball", settingsPage)
        UI.dodgeListInput.Text = SETTINGS.DodgeList or ""
        UI.dodgeListInput.Size = UDim2.new(1, 0, 0, 38)
        UI.dodgeListInput.BackgroundColor3 = Color3.fromRGB(9, 11, 23)
        local c = UI.dodgeListInput:FindFirstChildOfClass("UICorner")
        if c then c.CornerRadius = UDim.new(0, 10) end
        local s = UI.dodgeListInput:FindFirstChildOfClass("UIStroke")
        if s then s.Color = Color3.fromRGB(35, 40, 72) end
        UI.dodgeListInput.FocusLost:Connect(function()
            if isCleaningUp then return end
            SETTINGS.DodgeList = UI.dodgeListInput.Text
            if UI.onDodgeListChanged then UI.onDodgeListChanged() end
            saveConfig()
            setStatus("Dodge list updated!")
        end)
        local listNote = makeText(settingsPage, "Parts with these words in their name are always dodged, even invisible hitboxes. Spawn and arena parts never count as attacks.", 12, T.muted, Enum.Font.Gotham)
        listNote.Size = UDim2.new(1, 0, 0, 32)
        listNote.TextWrapped = true
        listNote.TextYAlignment = Enum.TextYAlignment.Top

        UI.learnAttacksRow = MakeToggle("Learn Attacks From Damage: " .. (SETTINGS.LearnAttacks and "ON" or "OFF"), SETTINGS.LearnAttacks, settingsPage)
        UI.learnAttacksRow.Size = UDim2.new(1, 0, 0, 42)
        UI.learnAttacksRow.MouseButton1Click:Connect(function()
            SETTINGS.LearnAttacks = not SETTINGS.LearnAttacks
            UI.refreshAttackRows()
            saveConfig()
        end)
        UI.forgetLearnedBtn = MakeButton("Forget Learned Attacks (0)", Color3.fromRGB(200, 90, 60), settingsPage)
        UI.forgetLearnedBtn.MouseButton1Click:Connect(function()
            if UI.forgetLearnedAttacks then UI.forgetLearnedAttacks() end
        end)
        local learnNote = makeText(settingsPage, "Remembers what hits you - the attack parts and the boss wind-up animation - and dodges it before it lands next time. A one-shot counts right away. Saved between runs.", 12, T.muted, Enum.Font.Gotham)
        learnNote.Size = UDim2.new(1, 0, 0, 32)
        learnNote.TextWrapped = true
        learnNote.TextYAlignment = Enum.TextYAlignment.Top

        UI.attackEspRow = MakeToggle("Show Attack ESP: " .. (SETTINGS.ShowAttackEsp and "ON" or "OFF"), SETTINGS.ShowAttackEsp, settingsPage)
        UI.attackEspRow.Size = UDim2.new(1, 0, 0, 42)
        UI.attackEspRow.MouseButton1Click:Connect(function()
            SETTINGS.ShowAttackEsp = not SETTINGS.ShowAttackEsp
            UI.refreshAttackRows()
            saveConfig()
        end)
        local espNote = makeText(settingsPage, "Labels every attack auto dodge sees (orange = dodge list, pink = learned, yellow = auto) and marks the SAFE SPOT it moves to.", 12, T.muted, Enum.Font.Gotham)
        espNote.Size = UDim2.new(1, 0, 0, 32)
        espNote.TextWrapped = true
        espNote.TextYAlignment = Enum.TextYAlignment.Top
        UI.refreshAttackRows()
    end

    -- CONFIG IMPORT / EXPORT UI
    MakeSectionLabel("Backup & share settings", settingsPage)
    local configExportBtn = MakeButton("Copy my settings", Color3.fromRGB(77, 52, 201), settingsPage) -- .b.violet.wide.tall
    configExportBtn.Size = UDim2.new(1, 0, 0, 46)
    configExportBtn.Font = Enum.Font.GothamBold
    do
        local c = configExportBtn:FindFirstChildOfClass("UICorner")
        if c then c.CornerRadius = UDim.new(0, 10) end
    end

    local configImportRow = MakeRow(settingsPage, 38)
    local configImportInput = MakeInput("Paste settings from a friend...", configImportRow)
    configImportInput.Size = rowSize(0.78, 2)
    configImportInput.BackgroundColor3 = Color3.fromRGB(9, 11, 23)
    do
        local c = configImportInput:FindFirstChildOfClass("UICorner")
        if c then c.CornerRadius = UDim.new(0, 10) end
        local s = configImportInput:FindFirstChildOfClass("UIStroke")
        if s then s.Color = Color3.fromRGB(35, 40, 72) end
    end
    local configImportBtn = MakeButton("Import", Color3.fromRGB(79, 124, 255), configImportRow) -- .b.blue
    configImportBtn.Size = rowSize(0.22, 2)
    configImportBtn.Font = Enum.Font.GothamBold
    do
        local c = configImportBtn:FindFirstChildOfClass("UICorner")
        if c then c.CornerRadius = UDim.new(0, 10) end
    end

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


    UI.requireGoldRow = MakeToggle("Skip Trade if Gold is 0: " .. (SETTINGS.AutoAcceptRequireGold and "ON" or "OFF"), SETTINGS.AutoAcceptRequireGold, tradePage)
    -- on screen it belongs to the Auto accept section (created first in code, so it is placed with LayoutOrder)
    UI.requireGoldRow.LayoutOrder = 8
    UI.requireGoldRow.Size = UDim2.new(1, 0, 0, 42)
    UI.requireGoldRow.MouseButton1Click:Connect(function()
        SETTINGS.AutoAcceptRequireGold = not SETTINGS.AutoAcceptRequireGold
        UI.requireGoldRow.Text = "Skip Trade if Gold is 0: " .. (SETTINGS.AutoAcceptRequireGold and "ON" or "OFF")
        UI.requireGoldRow.BackgroundColor3 = SETTINGS.AutoAcceptRequireGold and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
        saveConfig()
    end)

    MakeSectionLabel("Auto send trade", tradePage).LayoutOrder = 1
    local tradeRow = MakeRow(tradePage, 60)
    tradeRow.LayoutOrder = 2
    UI.tradeNameInput = MakeInput("Usernames (commas, spaces or new lines - no limit)...", tradeRow)
    UI.tradeNameInput.MultiLine = true
    UI.tradeNameInput.TextWrapped = true
    UI.tradeNameInput.TextYAlignment = Enum.TextYAlignment.Top
    UI.tradeNameInput.ClipsDescendants = true
    UI.tradeNameInput.Text = SETTINGS.TradeUsername or ""
    UI.tradeNameInput.Size = rowSize(0.78, 2)
    local tradeNowBtn = MakeButton("Send Now", Color3.fromRGB(79, 124, 255), tradeRow) -- .b.blue, same height as the field
    tradeNowBtn.Size = rowSize(0.22, 2)
    tradeNowBtn.Font = Enum.Font.GothamBold
    UI.autoTradeRow = MakeToggle("Auto Send Trade: " .. (SETTINGS.AutoTrade and "ON" or "OFF"), SETTINGS.AutoTrade, tradePage)
    UI.autoTradeRow.LayoutOrder = 3
    UI.autoTradeRow.Size = UDim2.new(1, 0, 0, 42)
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

    MakeSectionLabel("Auto accept trade (only these users)", tradePage).LayoutOrder = 5
    UI.acceptNameInput = MakeInput("Usernames to accept (commas, spaces or new lines)...", tradePage)
    UI.acceptNameInput.LayoutOrder = 6
    UI.acceptNameInput.Size = UDim2.new(1, 0, 0, 60)
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
    UI.autoAcceptRow.LayoutOrder = 7
    UI.autoAcceptRow.Size = UDim2.new(1, 0, 0, 42)
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

    -- Look of the tab (ncl-all-tabs.html): the two name fields are .inp textareas, the two status labels sit in
    -- .status-line boxes (dark rounded box + small dot). The labels stay the same TextLabels (UI.tradeStatus /
    -- UI.acceptStatus) so the trade logic keeps writing to their .Text; the dot turns green on success text.
    for _, box in ipairs({ UI.tradeNameInput, UI.acceptNameInput }) do
        box.BackgroundColor3 = Color3.fromRGB(9, 11, 23)     -- .inp #090b17
        local boxCorner = box:FindFirstChildOfClass("UICorner")
        if boxCorner then boxCorner.CornerRadius = UDim.new(0, 10) end
        local boxEdge = box:FindFirstChildOfClass("UIStroke")
        if boxEdge then boxEdge.Color = Color3.fromRGB(35, 40, 72) end
        local boxPad = box:FindFirstChildOfClass("UIPadding")
        if boxPad then boxPad.PaddingTop = UDim.new(0, 10) end
    end
    for _, def in ipairs({
        { UI.tradeStatus, 4, "sent to " },
        { UI.acceptStatus, 9, "Accept: accepted" },
    }) do
        local statusLbl, order, okText = def[1], def[2], def[3]
        local statusBox = Instance.new("Frame")
        statusBox.LayoutOrder = order
        statusBox.Size = UDim2.new(1, 0, 0, 44)
        statusBox.BackgroundColor3 = Color3.fromRGB(10, 13, 28)    -- .status-line #0a0d1c
        statusBox.BorderSizePixel = 0
        statusBox.Parent = tradePage
        round(statusBox, 10)
        stroke(statusBox, Color3.fromRGB(35, 40, 72), 1)

        local statusDot = Instance.new("Frame")
        statusDot.AnchorPoint = Vector2.new(0, 0.5)
        statusDot.Position = UDim2.new(0, 13, 0.5, 0)
        statusDot.Size = UDim2.new(0, 8, 0, 8)
        statusDot.BackgroundColor3 = Color3.fromRGB(90, 96, 144)
        statusDot.BorderSizePixel = 0
        statusDot.Parent = statusBox
        round(statusDot, 4)

        statusLbl.Parent = statusBox
        statusLbl.Position = UDim2.new(0, 30, 0, 0)
        statusLbl.Size = UDim2.new(1, -43, 1, 0)
        statusLbl.TextYAlignment = Enum.TextYAlignment.Center
        statusLbl:GetPropertyChangedSignal("Text"):Connect(function()
            statusDot.BackgroundColor3 = statusLbl.Text:find(okText, 1, true) and T.green or Color3.fromRGB(90, 96, 144)
        end)
    end

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
    MakeSectionLabel("Performance", miscPage).LayoutOrder = 105
    UI.fpsRow = MakeToggle("FPS Boost: " .. ((SETTINGS.RemoveMap or SETTINGS.FpsBoost) and "ON" or "OFF"), SETTINGS.RemoveMap or SETTINGS.FpsBoost, miscPage)
    UI.fpsRow.LayoutOrder = 106
    UI.fpsRow.Size = UDim2.new(1, 0, 0, 42)
    local fpsBadge = Instance.new("Frame")
    fpsBadge.Name = "FPSLogo"
    fpsBadge.Position = UDim2.new(0, 10, 0.5, -11)
    fpsBadge.Size = UDim2.new(0, 34, 0, 22)
    fpsBadge.BackgroundColor3 = Color3.fromRGB(12, 18, 36)
    fpsBadge.BorderSizePixel = 0
    fpsBadge.ZIndex = 3
    fpsBadge.Parent = UI.fpsRow
    round(fpsBadge, 5)
    stroke(fpsBadge, Color3.fromRGB(79, 124, 255), 1)
    local fpsBadgeText = makeText(fpsBadge, "FPS", 10, Color3.fromRGB(160, 195, 255), Enum.Font.GothamBlack, Enum.TextXAlignment.Center)
    fpsBadgeText.Size = UDim2.new(1, 0, 1, 0)
    fpsBadgeText.ZIndex = 4
    local fpsTextPad = Instance.new("UIPadding")
    fpsTextPad.PaddingLeft = UDim.new(0, 52)
    fpsTextPad.Parent = UI.fpsRow
    local fpsNote = makeText(miscPage, "Hides map scenery and reduces visual effects while keeping attack hazards visible to auto-dodge.", 12, T.muted, Enum.Font.Gotham)
    fpsNote.LayoutOrder = 107
    fpsNote.Size = UDim2.new(1, 0, 0, 34)
    fpsNote.TextWrapped = true
    fpsNote.TextYAlignment = Enum.TextYAlignment.Top
    UI.followHostRow =MakeToggle("Follow Host: " .. (SETTINGS.FollowHost and "ON" or "OFF"), SETTINGS.FollowHost, joinPage)
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
    local autoCreateNote = makeText(joinPage, "ON (Host role): creates a lobby with the Map Name and Difficulty below, then auto-starts it.", 12, T.muted, Enum.Font.Gotham)
    autoCreateNote.Size = UDim2.new(1, 0, 0, 30)
    autoCreateNote.TextWrapped = true
    autoCreateNote.TextYAlignment = Enum.TextYAlignment.Top

    UI.mapDropdown = MakeDropdownRow("Map Name:", getAvailableMaps, SETTINGS.LobbyMap, joinPage, function(val)
        SETTINGS.LobbyMap = val
        saveConfig()
    end)

    UI.diffDropdown = MakeDropdownRow("Difficulty:", getAvailableDifficulties, SETTINGS.LobbyDifficulty, joinPage, function(val)
        SETTINGS.LobbyDifficulty = val
        saveConfig()
    end)

    UI.waitForPlayersRow = MakeToggle("Wait for Party in Dungeon: " .. (SETTINGS.WaitForPlayers and "ON" or "OFF"), SETTINGS.WaitForPlayers, joinPage)
    UI.hcRow = MakeToggle("Hardcore Mode: OFF", false, joinPage)
    UI.privRow = MakeToggle("Private Lobby: OFF", false, joinPage)
    UI.modeRow = MakeButton("Gameplay Mode: " .. SETTINGS.GameplayMode, Color3.fromRGB(58, 80, 200), miscPage)
    UI.autoDodgeRow = MakeToggle("Auto Dodging: " .. (SETTINGS.AutoDodgeEnabled and "ON" or "OFF"), SETTINGS.AutoDodgeEnabled, miscPage)

    UI.eifToggleBtn = MakeToggle("EIF Spammer: " .. (SETTINGS.EIFSpammerEnabled and "ON" or "OFF"), SETTINGS.EIFSpammerEnabled, miscPage)
    UI.eifSlotBtn = MakeButton("EIF Slot: " .. SETTINGS.EIFSpammerSlot:upper(), Color3.fromRGB(58, 80, 200), miscPage)
    UI.eifDelayInput = MakeSettingRow("EIF Spam Delay (s):", SETTINGS.EIFSpammerDelay, miscPage)

    -- AUTO-SELL TAB (.sc cards from ncl-all-tabs.html: one card per category,
    -- six rarity pills laid out 3 columns x 2 rows, tinted with the rarity colour when active)
    UI.autoSellToggleBtn = MakeToggle("Auto Sell: OFF", false, sellPage)
    UI.autoSellToggleBtn.Size = UDim2.new(1, 0, 0, 38)
    local sellNowBtn = MakeButton("Sell Matching Items Now", Color3.fromRGB(190, 105, 30), sellPage)
    sellNowBtn.Size = UDim2.new(1, 0, 0, 38)

    MakeSectionLabel("What to Sell", sellPage)

    local SELL = {
        card    = Color3.fromRGB(24, 28, 54),   -- --surface-2
        edge    = Color3.fromRGB(35, 40, 72),   -- --border
        pill    = Color3.fromRGB(13, 16, 36),   -- .rp background
        pillOff = Color3.fromRGB(90, 96, 144),  -- --dim
    }
    local RARITY_TINT = {
        common    = Color3.fromRGB(174, 180, 216),
        uncommon  = Color3.fromRGB(94, 224, 138),
        rare      = Color3.fromRGB(91, 155, 255),
        epic      = Color3.fromRGB(185, 140, 255),
        legendary = Color3.fromRGB(255, 181, 71),
        ultimate  = Color3.fromRGB(255, 93, 143),
    }

    local function setupCategoryRaritySection(catKey, catDisplayName)
        local card = Instance.new("Frame")
        card.Size = UDim2.new(1, 0, 0, 150)
        card.BackgroundColor3 = SELL.card
        card.BorderSizePixel = 0
        card.Parent = sellPage
        round(card, 14)
        stroke(card, SELL.edge, 1)

        local cardPad = Instance.new("UIPadding")
        cardPad.PaddingTop = UDim.new(0, 12)
        cardPad.PaddingBottom = UDim.new(0, 12)
        cardPad.PaddingLeft = UDim.new(0, 14)
        cardPad.PaddingRight = UDim.new(0, 14)
        cardPad.Parent = card

        local cardName = makeText(card, catDisplayName, 14, T.text, Enum.Font.GothamBold)
        cardName.Size = UDim2.new(1, 0, 0, 18)

        -- kept only so updateCategoryDropdownTitle() still has a .Text to write into; the
        -- "[Click to Configure]" header is gone from the card layout.
        local headerBtn = makeText(card, "", 11, T.muted)
        headerBtn.Size = UDim2.new(0, 0, 0, 0)
        headerBtn.Visible = false

        local container = Instance.new("Frame")
        container.Size = UDim2.new(1, 0, 0, 98)
        container.Position = UDim2.new(0, 0, 0, 28)
        container.BackgroundTransparency = 1
        container.Parent = card

        local grid = Instance.new("UIGridLayout")
        grid.Parent = container
        grid.SortOrder = Enum.SortOrder.LayoutOrder
        grid.CellSize = UDim2.new(1 / 3, -7, 0, 44)
        grid.CellPadding = UDim2.new(0, 10, 0, 10)

        local buttons = {}
        for i, rarity in ipairs(RARITY_ORDER) do
            local tint = RARITY_TINT[rarity]
            local label = rarity:sub(1, 1):upper() .. rarity:sub(2)

            local rBtn = MakeButton(label, SELL.pill, container)
            rBtn.LayoutOrder = i
            rBtn.Font = Enum.Font.GothamBold
            rBtn.TextSize = 13
            local corner = rBtn:FindFirstChildOfClass("UICorner")
            if corner then corner.CornerRadius = UDim.new(0, 10) end
            local edge = stroke(rBtn, SELL.edge, 1)
            buttons[rarity] = rBtn

            -- repaint straight from SETTINGS, so the config loader further down (which writes
            -- rBtn.Text / rBtn.BackgroundColor3 directly) still lands on the right look.
            local painting = false
            local function paint()
                if painting then return end
                painting = true
                local on = SETTINGS.AutoSellConfig[catKey] and SETTINGS.AutoSellConfig[catKey][rarity]
                rBtn.Text = on and (label .. "  ✓") or label
                rBtn.TextColor3 = on and tint or SELL.pillOff
                rBtn.BackgroundColor3 = on and tint:Lerp(SELL.pill, 0.84) or SELL.pill
                edge.Color = on and tint:Lerp(SELL.card, 0.35) or SELL.edge
                painting = false
            end
            paint()
            rBtn:GetPropertyChangedSignal("Text"):Connect(paint)
            rBtn:GetPropertyChangedSignal("BackgroundColor3"):Connect(paint)

            rBtn.MouseButton1Click:Connect(function()
                SETTINGS.AutoSellConfig[catKey][rarity] = not SETTINGS.AutoSellConfig[catKey][rarity]
                paint()
                updateCategoryDropdownTitle(catKey)
                saveConfig()
            end)
        end

        UI.catSections[catKey] = {
            headerBtn = headerBtn,
            container = container,
            buttons = buttons,
            displayName = catDisplayName
        }
        updateCategoryDropdownTitle(catKey)
    end

    setupCategoryRaritySection("weapon", "Weapons")
    setupCategoryRaritySection("chest", "Armor")
    setupCategoryRaritySection("helmet", "Helmets")
    setupCategoryRaritySection("ability", "Abilities")

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
    bottomBar.Position = UDim2.new(0, PAGE_X, 0, 482)
    bottomBar.BackgroundTransparency = 1
    bottomBar.Parent = body

    local runMacroBtn = MakeButton("RUN SCRIPT (Autoplay)", T.accent, bottomBar)
    runMacroBtn.Size = UDim2.new(1, 0, 1, 0)
    runMacroBtn.TextSize = 14
    runMacroBtn.Font = Enum.Font.GothamBold
    UI.runMacroBtn = runMacroBtn

    -- .btn-discord: sits at the bottom of the sidebar in the reference design
    local terminateBtn = MakeButton("DISCORD", Color3.fromRGB(26, 31, 67), sidebar)   -- .side-bottom: rgba(88,101,242,.14) on the card
    terminateBtn.TextColor3 = Color3.fromRGB(199, 203, 255)                                -- #c7cbff
    terminateBtn.Font = Enum.Font.GothamBold
    terminateBtn.TextXAlignment = Enum.TextXAlignment.Center
    terminateBtn.AnchorPoint = Vector2.new(0, 1)
    terminateBtn.Size = UDim2.new(1, 0, 0, 38)
    terminateBtn.Position = UDim2.new(0, 0, 1, 0)
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

    local nodeCard = createCard("Path", 84, 202)

    local curLabel = makeText(nodeCard, "Current Path", 12, T.muted, Enum.Font.Gotham)
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

    local totalLabel = makeText(nodeCard, "Total Paths", 12, T.muted, Enum.Font.Gotham)
    totalLabel.Size = UDim2.new(0, 110, 0, 16)
    totalLabel.Position = UDim2.new(0, 16, 0, 146)
    UI.nodeTotalLabel = makeText(nodeCard, "0", 16, Color3.fromRGB(60, 225, 205), Enum.Font.GothamBold, Enum.TextXAlignment.Right)
    UI.nodeTotalLabel.Size = UDim2.new(0, 100, 0, 20)
    UI.nodeTotalLabel.Position = UDim2.new(0, 128, 0, 144)
    -- the live-state loop rewrites this label whenever the path count changes -> refresh the Macro tab's "N paths" line
    UI.nodeTotalLabel:GetPropertyChangedSignal("Text"):Connect(UI.refreshRecInfo)
    UI.refreshRecInfo()

    -- KEY VALID TIMER: how long the current key stays valid, set by fetchKeyExpiry() in the key screen
    -- (global NCL_KeyExpiresAt - unix timestamp, 0 = lifetime, nil = unknown/not reported by the key
    -- server). Lives in the Path card so it's visible on the same page as the rest of the run status.
    -- Refreshed every 30s since minute-level granularity is enough for a countdown like this.
    UI.keyValidLabel = makeText(nodeCard, "KEY VALID (--)", 13, T.green, Enum.Font.GothamBold, Enum.TextXAlignment.Left)
    UI.keyValidLabel.Size = UDim2.new(1, -32, 0, 18)
    UI.keyValidLabel.Position = UDim2.new(0, 16, 0, 172)
    task.spawn(function()
        while not isCleaningUp and UI.keyValidLabel.Parent do
            local expiresAt = NCL_KeyExpiresAt
            if expiresAt == nil then
                UI.keyValidLabel.Text = "KEY VALID (--)"
                UI.keyValidLabel.TextColor3 = T.muted
            elseif expiresAt == 0 then
                UI.keyValidLabel.Text = "KEY VALID (Lifetime)"
                UI.keyValidLabel.TextColor3 = T.green
            else
                local remaining = math.floor(expiresAt - os.time())
                if remaining <= 0 then
                    UI.keyValidLabel.Text = "KEY EXPIRED"
                    UI.keyValidLabel.TextColor3 = T.pink
                else
                    local days = math.floor(remaining / 86400)
                    local hours = math.floor((remaining % 86400) / 3600)
                    local mins = math.floor((remaining % 3600) / 60)
                    local txt = days > 0 and string.format("%dd %dh", days, hours) or (hours > 0 and string.format("%dh %dm", hours, mins) or string.format("%dm", mins))
                    UI.keyValidLabel.Text = "KEY VALID (" .. txt .. ")"
                    UI.keyValidLabel.TextColor3 = (remaining < 86400) and T.orange or T.green
                end
            end
            task.wait(30)
        end
    end)

    local clearCard = createCard("Clear Path", 298, 230)

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

    local clearAllBtn = MakeButton("Clear All Paths", T.accent, clearCard)
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
                stateText, stateColor = "RECORDING", Color3.fromRGB(255, 72, 103)   -- .pill.rec red (was T.orange)
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

    UI.dodgeBufferInput.FocusLost:Connect(function() applySetting(UI.dodgeBufferInput, "DodgeBuffer") end)
    UI.dodgeBoostInput.FocusLost:Connect(function()
        if isCleaningUp then return end
        local val = tonumber(UI.dodgeBoostInput.Text)
        if val then
            SETTINGS.DodgeBoostStuds = math.clamp(val, 0, 10)
            UI.dodgeBoostInput.Text = tostring(SETTINGS.DodgeBoostStuds)
            UI.dodgeBoostPool = math.min(UI.dodgeBoostPool, SETTINGS.DodgeBoostStuds)
            saveConfig()
            setStatus("Dodge Boost updated to " .. tostring(SETTINGS.DodgeBoostStuds))
        else
            UI.dodgeBoostInput.Text = tostring(SETTINGS.DodgeBoostStuds)
        end
    end)
    UI.partySizeInput.FocusLost:Connect(function() applySetting(UI.partySizeInput, "TargetPartySize") end)

    UI.roleRow.MouseButton1Click:Connect(function()
        SETTINGS.LobbyMode = (SETTINGS.LobbyMode == "Host") and "Join" or "Host"
        UI.roleRow.Text = "Lobby Role: " .. SETTINGS.LobbyMode:upper()
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
    table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
        if processed or isCleaningUp then return end
        if input.KeyCode == BLACKSCREEN_KEY then applyBlackScreen(not SETTINGS.BlackScreen) end
    end))
    UI.fpsRow.MouseButton1Click:Connect(function()
        if UI.applyPerformance then UI.applyPerformance(not (SETTINGS.RemoveMap or SETTINGS.FpsBoost)) end
    end)
    UI.fpsQuickBtn.MouseButton1Click:Connect(function()
        if UI.applyPerformance then UI.applyPerformance(not (SETTINGS.RemoveMap or SETTINGS.FpsBoost)) end
    end)

    UI.autoDodgeRow.MouseButton1Click:Connect(function()
        SETTINGS.AutoDodgeEnabled = not SETTINGS.AutoDodgeEnabled
        UI.autoDodgeRow.Text = "Auto Dodging: " .. (SETTINGS.AutoDodgeEnabled and "ON" or "OFF")
        UI.autoDodgeRow.BackgroundColor3 = SETTINGS.AutoDodgeEnabled and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
        saveConfig()
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

        if isAutoplay then
            UI.dodgeBoostPool = SETTINGS.DodgeBoostStuds
            UI.dodgeBoostLastPos, UI.dodgeBoostNormalSpeed = nil, nil
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
        terminateBtn.Text = "COPIED!"
        task.delay(1.5, function() if terminateBtn.Parent then terminateBtn.Text = "DISCORD" end end)
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
    SETTINGS.DodgeBoostStuds = cfg.DodgeBoostStuds or SETTINGS.DodgeBoostStuds
    if cfg.ShowDodgeBoostBar ~= nil then SETTINGS.ShowDodgeBoostBar = cfg.ShowDodgeBoostBar end
    SETTINGS.WaypointTriggerDist = cfg.WaypointTriggerDist or SETTINGS.WaypointTriggerDist
    SETTINGS.MaxNodeDistance = cfg.MaxNodeDistance or SETTINGS.MaxNodeDistance
    SETTINGS.WallRayLength = cfg.WallRayLength or SETTINGS.WallRayLength
    SETTINGS.Webhook = cfg.Webhook or ""
    if cfg.WebhookLogo ~= nil then SETTINGS.WebhookLogo = tostring(cfg.WebhookLogo) end
    SETTINGS.IgnoreKeywords = cfg.IgnoreKeywords or SETTINGS.IgnoreKeywords

    SETTINGS.AutoLobbyEnabled = true -- always on; a saved/imported config cannot turn it off
    if cfg.LobbyMode then SETTINGS.LobbyMode = cfg.LobbyMode end
    if cfg.JoinPlayerName then SETTINGS.JoinPlayerName = cfg.JoinPlayerName end
    SETTINGS.LobbyMap = cfg.LobbyMap or SETTINGS.LobbyMap
    SETTINGS.LobbyDifficulty = cfg.LobbyDifficulty or SETTINGS.LobbyDifficulty
    if tostring(SETTINGS.LobbyDifficulty):lower():find("panel") then
        SETTINGS.LobbyDifficulty = "Easy"
    end
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
    if cfg.RemoveMap ~= nil then SETTINGS.RemoveMap = cfg.RemoveMap end
    if cfg.FpsBoost ~= nil then SETTINGS.FpsBoost = cfg.FpsBoost end
    if cfg.DodgeList ~= nil then SETTINGS.DodgeList = tostring(cfg.DodgeList) end
    if cfg.LearnAttacks ~= nil then SETTINGS.LearnAttacks = cfg.LearnAttacks end
    if cfg.ShowAttackEsp ~= nil then SETTINGS.ShowAttackEsp = cfg.ShowAttackEsp end
    if type(cfg.LearnedAttacks) == "table" then
        SETTINGS.LearnedAttacks = {}
        for k, v in pairs(cfg.LearnedAttacks) do
            if v and type(k) == "string" then SETTINGS.LearnedAttacks[k:lower()] = true end
        end
    end
    if type(cfg.LearnedAnims) == "table" then
        SETTINGS.LearnedAnims = {}
        for id, v in pairs(cfg.LearnedAnims) do
            if type(id) == "string" and type(v) == "table" and tonumber(v.d) and tonumber(v.r) then
                SETTINGS.LearnedAnims[id] = { d = math.clamp(tonumber(v.d), 0.15, 3), r = math.clamp(tonumber(v.r), 8, 40) }
            end
        end
    end
    if UI.dodgeListInput then UI.dodgeListInput.Text = SETTINGS.DodgeList end
    UI.refreshAttackRows()
    if UI.onDodgeListChanged then UI.onDodgeListChanged() end
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
    SETTINGS.ReplayOnDisconnect = true -- always on
    SETTINGS.RejoinOnDisconnect = true -- always on
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
    if UI.dodgeBufferInput then UI.dodgeBufferInput.Text = tostring(SETTINGS.DodgeBuffer) end
    if UI.dodgeBoostInput then UI.dodgeBoostInput.Text = tostring(SETTINGS.DodgeBoostStuds) end
    if UI.dodgeBoostBarRow then
        UI.dodgeBoostBarRow.Text = "Dodge Boost Bar: " .. (SETTINGS.ShowDodgeBoostBar and "ON" or "OFF")
        UI.dodgeBoostBarRow.BackgroundColor3 = SETTINGS.ShowDodgeBoostBar and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
    end
    if UI.partySizeInput then UI.partySizeInput.Text = tostring(SETTINGS.TargetPartySize) end
    if UI.eifDelayInput then UI.eifDelayInput.Text = tostring(SETTINGS.EIFSpammerDelay) end
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

    if UI.mapDropdown then UI.mapDropdown:SetValue(SETTINGS.LobbyMap) end
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
    if UI.applyPerformance then UI.applyPerformance(SETTINGS.RemoveMap or SETTINGS.FpsBoost, true) end
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
            UI.dodgeBoostPool = SETTINGS.DodgeBoostStuds
            UI.dodgeBoostLastPos, UI.dodgeBoostNormalSpeed = nil, nil
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
    if UI.restoreMap then pcall(UI.restoreMap) end
    if UI.restoreFps then pcall(UI.restoreFps) end
    if UI.restoreDecals then pcall(UI.restoreDecals) end
    if UI.espFolder then pcall(function() UI.espFolder:Destroy() end) end
    if UI.safeSpotAtt then pcall(function() UI.safeSpotAtt:Destroy() end) end
    if UI.blackGui then UI.blackGui:Destroy() end
    if UI.dodgeBoostGui then pcall(function() UI.dodgeBoostGui:Destroy() end) end
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
    hasSentStageLoss = false
    characterSpawnTime = os.clock()
    postDodgeHoldUntil = 0
    lastStartValueTime = os.clock()
    evadingDisplayUntil = 0
    UI.dodgeBoostPool = SETTINGS.DodgeBoostStuds
    UI.dodgeBoostLastPos = nil
    UI.dodgeBoostNormalSpeed = nil
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
    if UI.isNotAttackName(obj.Name:lower()) then return 0 end
    -- names on the dodge list or learned from damage are attacks however they look (unless part of a mob's body)
    if UI.attackListReason(obj) then
        local model = obj:FindFirstAncestorOfClass("Model")
        if not (model and model:FindFirstChildOfClass("Humanoid")) then return 10 end
    end
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

    -- glowing effect materials count whatever their color (ice / frost telegraphs are blue or white, not red)
    if obj.Material == Enum.Material.Neon or obj.Material == Enum.Material.ForceField then
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

    if born and os.clock() - born < 15 then
        -- an invisible part showing a picture (Decal / SurfaceGui) that appeared mid-fight is a drawn ground telegraph
        if obj.Transparency >= 0.95 and UI.hasVisual(obj) then score = score + 3 end
        -- a big, non-solid, anchored part that appeared mid-fight is almost always an attack effect
        if obj.Anchored and not obj.CanCollide then
            local _, gsize = UI.partGeometry(obj)
            if math.max(gsize.X, gsize.Y, gsize.Z) >= 6 then score = score + 1 end
        end
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
    -- a mesh or picture is often added to a part a moment after it spawned: re-score that part right away (a scaled mesh
    -- makes it bigger, a Decal / SurfaceGui on an invisible part makes it a drawn telegraph). For fresh parts, also re-score
    -- when the mesh is scaled (growing circles) or the picture fades in.
    if child:IsA("DataModelMesh") or child:IsA("Decal") or child:IsA("SurfaceGui") then
        local p = child.Parent
        if p and p:IsA("BasePart") then
            evaluateAndAddHazardPart(p)
            if UI.partBorn[p] and hazardSignals[p] and not child:IsA("SurfaceGui") then
                local prop = child:IsA("DataModelMesh") and "Scale" or "Transparency"
                table.insert(hazardSignals[p], child:GetPropertyChangedSignal(prop):Connect(function() evaluateAndAddHazardPart(p) end))
            end
        end
        return
    end
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

    -- REMOVE MAP / FPS BOOST
    -- Only map scenery is touched. Anything the dodge scanner could treat as an attack (neon parts, hazard keywords,
    -- hazard score >= 3), characters, mobs, inviswalls and macro nodes are left alone, and CanCollide is never
    -- changed, so floors still hold you up with Remove Map on and auto dodge keeps seeing every telegraph.
    -- Every change is remembered and put back when the toggle goes OFF or the script is closed.
    UI.mapSaved = setmetatable({}, { __mode = "k" })    -- part -> original Transparency (Remove Map)
    UI.partFxSaved = setmetatable({}, { __mode = "k" }) -- part -> { Material, Reflectance, CastShadow } (FPS Boost)
    UI.decalSaved = setmetatable({}, { __mode = "k" })  -- decal/texture -> original Transparency (either toggle)
    UI.effectSaved = setmetatable({}, { __mode = "k" }) -- particles / trails / post effects we switched off
    UI.sceneryQueue = {}
    UI.sceneryScanId = 0

    function UI.isMapScenery(obj)
        if not obj:IsA("BasePart") or obj:IsA("Terrain") or not obj.Anchored then return false end
        if obj.Material == Enum.Material.Neon then return false end
        local name = obj.Name:lower()
        if name == "inviswall" or name:find("macropathnode", 1, true) then return false end
        if Workspace.CurrentCamera and obj:IsDescendantOf(Workspace.CurrentCamera) then return false end
        local model = obj:FindFirstAncestorOfClass("Model")
        if model and (model:FindFirstChildOfClass("Humanoid") or Players:GetPlayerFromCharacter(model)) then return false end
        return scoreHazardPart(obj) < 3
    end

    function UI.hideDecals(part)
        for _, d in ipairs(part:GetChildren()) do
            if d:IsA("Decal") and UI.decalSaved[d] == nil and d.Transparency < 1 then -- Texture is a Decal subclass
                UI.decalSaved[d] = d.Transparency
                d.Transparency = 1
            end
        end
    end

    function UI.processScenery(obj)
        if not obj.Parent or not UI.isMapScenery(obj) then return end
        if SETTINGS.RemoveMap and UI.mapSaved[obj] == nil and obj.Transparency < 1 then
            UI.mapSaved[obj] = obj.Transparency
            obj.Transparency = 1
        end
        if SETTINGS.FpsBoost and UI.partFxSaved[obj] == nil then
            UI.partFxSaved[obj] = { obj.Material, obj.Reflectance, obj.CastShadow }
            obj.Material = Enum.Material.SmoothPlastic
            obj.Reflectance = 0
            obj.CastShadow = false
        end
        UI.hideDecals(obj)
    end

    -- pure visuals: the dodge scanner only checks whether these exist, never whether they are enabled
    function UI.disableEffect(obj)
        if UI.effectSaved[obj] then return end
        if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Smoke") or obj:IsA("Fire")
            or obj:IsA("Sparkles") or obj:IsA("PostEffect") then
            if obj.Enabled then UI.effectSaved[obj] = true; obj.Enabled = false end
        end
    end

    -- walks the whole workspace in chunks of 2000 so turning a toggle on never freezes the game
    function UI.scanScenery()
        UI.sceneryScanId = UI.sceneryScanId + 1
        local myId = UI.sceneryScanId
        task.spawn(function()
            for i, obj in ipairs(Workspace:GetDescendants()) do
                if myId ~= UI.sceneryScanId or isCleaningUp then return end
                if obj:IsA("BasePart") then
                    local born = UI.partBorn[obj]
                    if born and os.clock() - born < 5 then
                        table.insert(UI.sceneryQueue, { obj, born })
                    else
                        pcall(UI.processScenery, obj)
                    end
                elseif SETTINGS.FpsBoost then
                    pcall(UI.disableEffect, obj)
                end
                if i % 2000 == 0 then task.wait() end
            end
        end)
    end

    table.insert(connections, Workspace.DescendantAdded:Connect(function(obj)
        if not (SETTINGS.RemoveMap or SETTINGS.FpsBoost) then return end
        if obj:IsA("BasePart") then
            -- new parts wait 5 s first: attacks are short-lived and must stay visible to the dodge scanner
            table.insert(UI.sceneryQueue, { obj, os.clock() })
        elseif SETTINGS.FpsBoost then
            task.defer(pcall, UI.disableEffect, obj)
        end
    end))

    task.spawn(function()
        while not isCleaningUp do
            task.wait(1)
            if #UI.sceneryQueue > 0 then
                local now, keep = os.clock(), {}
                for _, e in ipairs(UI.sceneryQueue) do
                    if e[1].Parent then
                        if now - e[2] < 5 then
                            table.insert(keep, e)
                        elseif SETTINGS.RemoveMap or SETTINGS.FpsBoost then
                            pcall(UI.processScenery, e[1])
                        end
                    end
                end
                UI.sceneryQueue = keep
            end
        end
    end)

    function UI.applyLightingBoost(on)
        local Lighting = game:GetService("Lighting")
        local terrain = Workspace:FindFirstChildOfClass("Terrain")
        if on then
            if not UI.lightSaved then
                UI.lightSaved = { GlobalShadows = Lighting.GlobalShadows, FogEnd = Lighting.FogEnd }
                pcall(function() UI.lightSaved.Quality = settings().Rendering.QualityLevel end)
                if terrain then
                    UI.lightSaved.Water = { terrain.WaterWaveSize, terrain.WaterWaveSpeed, terrain.WaterReflectance, terrain.WaterTransparency }
                end
            end
            pcall(function() Lighting.GlobalShadows = false; Lighting.FogEnd = 1e9 end)
            pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
            pcall(function()
                if terrain then
                    terrain.WaterWaveSize, terrain.WaterWaveSpeed, terrain.WaterReflectance, terrain.WaterTransparency = 0, 0, 0, 0
                end
            end)
            for _, fx in ipairs(Lighting:GetDescendants()) do pcall(UI.disableEffect, fx) end
            pcall(function() if setfpscap then setfpscap(999) end end)
        else
            local s = UI.lightSaved
            if s then
                pcall(function() Lighting.GlobalShadows = s.GlobalShadows; Lighting.FogEnd = s.FogEnd end)
                pcall(function() if s.Quality then settings().Rendering.QualityLevel = s.Quality end end)
                pcall(function()
                    if terrain and s.Water then
                        terrain.WaterWaveSize, terrain.WaterWaveSpeed, terrain.WaterReflectance, terrain.WaterTransparency = unpack(s.Water)
                    end
                end)
                UI.lightSaved = nil
                pcall(function() if setfpscap then setfpscap(60) end end)
            end
        end
    end

    -- only undo our own change: if the game has changed a value since, the game's value stays
    function UI.restoreDecals()
        for d, t in pairs(UI.decalSaved) do
            if d.Parent and d.Transparency == 1 then pcall(function() d.Transparency = t end) end
        end
        table.clear(UI.decalSaved)
    end

    function UI.restoreMap()
        for part, t in pairs(UI.mapSaved) do
            if part.Parent and part.Transparency == 1 then pcall(function() part.Transparency = t end) end
        end
        table.clear(UI.mapSaved)
        if not SETTINGS.FpsBoost then UI.restoreDecals() end
    end

    function UI.restoreFps()
        for part, s in pairs(UI.partFxSaved) do
            if part.Parent then pcall(function() part.Material, part.Reflectance, part.CastShadow = s[1], s[2], s[3] end) end
        end
        table.clear(UI.partFxSaved)
        for fx in pairs(UI.effectSaved) do
            if fx.Parent then pcall(function() fx.Enabled = true end) end
        end
        table.clear(UI.effectSaved)
        UI.applyLightingBoost(false)
        if not SETTINGS.RemoveMap then UI.restoreDecals() end
    end

    function UI.refreshPerfRows()
        local enabled = SETTINGS.RemoveMap or SETTINGS.FpsBoost
        if UI.fpsRow then
            UI.fpsRow.Text = "FPS: " .. (enabled and "ON" or "OFF")
            UI.fpsRow.BackgroundColor3 = enabled and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(28, 34, 62)
        end
        if UI.fpsQuickBtn then
            UI.fpsQuickBtn.BackgroundColor3 = enabled and Color3.fromRGB(40, 150, 70) or UI.theme.field
        end
    end

    function UI.applyPerformance(enabled, skipSave)
        local was = SETTINGS.RemoveMap or SETTINGS.FpsBoost
        enabled = enabled and true or false
        SETTINGS.RemoveMap, SETTINGS.FpsBoost = enabled, enabled
        UI.refreshPerfRows()
        if enabled then
            UI.applyLightingBoost(true)
            UI.scanScenery()
        elseif was then
            UI.restoreMap()
            UI.restoreFps()
        end
        UI.refreshPerfRows()
        if not skipSave then
            saveConfig()
            setStatus(enabled and "Status: FPS ON" or "Status: FPS OFF", true)
        end
    end

    local function getDangerousHazards(playerPos)
    local hazards = {}
    local now = os.clock()

    for part, _ in pairs(activeHazards) do
        if part and part.Parent then
            local listed = UI.attackListReason(part)
            -- listed attacks count even fully invisible (hidden hitboxes), and so does an invisible part that shows a
            -- picture (Decal / SurfaceGui ground circle)
            if part.Transparency < 1 or listed or UI.hasVisual(part) then
                -- real size and center: a scaled mesh can make the visible circle many times bigger than Part.Size
                local cf, size, shape = UI.partGeometry(part)
                if (cf.Position - playerPos).Magnitude - size.Magnitude / 2 > 140 then continue end
                -- an effect welded to you or a teammate moves with you and can never be escaped: it is not an attack
                local assemblyRoot = part.AssemblyRootPart
                if assemblyRoot and assemblyRoot ~= part and assemblyRoot.Parent and playerCharacters[assemblyRoot.Parent] then continue end
                local isIgnored = UI.hazardIgnoreCache[part]
                if isIgnored == nil then
                    local name = part.Name:lower()
                    isIgnored = false
                    for _, kw in ipairs(parsedIgnoreKeywords) do if name:find(kw, 1, true) then isIgnored = true; break end end
                    UI.hazardIgnoreCache[part] = isIgnored
                end

                if not isIgnored and math.max(size.X, size.Y, size.Z) <= 300 then
                    local currentPos, currentSize = cf.Position, size
                    local track = hazardTracking[part]
                    local velocity, growth

                    if track then
                        local dt = now - track.lastTime
                        if dt > 0.01 then
                            local moved = currentPos - track.lastPos
                            -- a jump of 30+ studs in one step is the part being repositioned, not flying at us
                            track.velocity = (moved.Magnitude > 30) and Vector3.zero or moved / dt
                            -- expanding rings / filling telegraphs: only growth counts, capped so a one-off resize is not read as a 1000 stud/s blast
                            local g = (currentSize - track.lastSize) / dt
                            track.growth = Vector3.new(math.clamp(g.X, 0, 60), math.clamp(g.Y, 0, 60), math.clamp(g.Z, 0, 60))
                            track.lastPos, track.lastSize, track.lastTime = currentPos, currentSize, now
                        end
                        velocity, growth = track.velocity, track.growth
                    else
                        velocity, growth = part.AssemblyLinearVelocity or Vector3.zero, Vector3.zero
                        hazardTracking[part] = { lastPos = currentPos, lastSize = currentSize, lastTime = now, velocity = velocity, growth = growth }
                    end

                    local born = UI.partBorn[part]
                    table.insert(hazards, {
                        cframe = cf, size = currentSize, name = part.Name, velocity = velocity, growth = growth,
                        shape = shape, part = part, reason = listed or "auto",
                        -- big zones get extra room: the server's hit area is often a bit wider than the circle you see
                        pad = math.min(math.max(currentSize.X, currentSize.Y, currentSize.Z) * 0.06, 3),
                        -- when it will hurt: a fresh telegraph usually fires about 1 s after it appears; older zones are live
                        fireAt = born and (born + 1.0) or nil,
                    })
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
    -- learned boss attack animations: a flat circle around the boss, live from the wind-up until just after it lands
    -- (drawn at your own height so tall bosses still count)
    for i = #UI.predictions, 1, -1 do
        local pr = UI.predictions[i]
        if now > pr.untilT or not pr.root.Parent then
            table.remove(UI.predictions, i)
        else
            local c = pr.root.Position
            table.insert(hazards, {
                cframe = CFrame.new(c.X, playerPos.Y, c.Z) * CFrame.Angles(0, 0, math.pi / 2),
                size = Vector3.new(1, pr.radius * 2, pr.radius * 2), shape = "Cylinder", velocity = Vector3.zero,
                name = pr.name .. " attack (predicted)", reason = "predicted", predicted = true,
                root = pr.root, radius = pr.radius, hitAt = pr.hitAt, fireAt = pr.hitAt,
            })
        end
    end
    -- how far each zone can reach (size + 1 s of movement + growth): lets far zones be skipped cheaply
    for _, h in ipairs(hazards) do
        h.reach = h.size.Magnitude / 2 + h.velocity.Magnitude + (h.growth and math.min(h.growth.Magnitude * 0.6, 40) or 0)
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
    -- box (written without temporary tables: this runs thousands of times per dodge plan)
    local dx, dy, dz = math.abs(localP.X) - s.X / 2, math.abs(localP.Y) - s.Y / 2, math.abs(localP.Z) - s.Z / 2
    local thinSize, thinUp, thinD, d1, d2
    if s.X <= s.Y and s.X <= s.Z then thinSize, thinUp, thinD, d1, d2 = s.X, cf.RightVector.Y, dx, dy, dz
    elseif s.Y <= s.Z then thinSize, thinUp, thinD, d1, d2 = s.Y, cf.UpVector.Y, dy, dx, dz
    else thinSize, thinUp, thinD, d1, d2 = s.Z, cf.LookVector.Y, dz, dx, dy end
    if thinSize <= 3 and math.abs(thinUp) > 0.7 then -- flat slab lying on the ground
        if thinD > 9 then return math.huge end
        return math.max(d1, d2)
    end
    return math.max(dx, dy, dz)
    end
    end

    -- One zone against one point. Returns:
    --   inDanger  - the point is inside the zone now or on its predicted path (Dodge Buffer + the zone's padding + extra)
    --   clearance - studs from the point to the zone's edge (now or along its predicted path; negative = inside)
    --   eta       - seconds until the zone can hurt this point (0 = now / already live; math.huge when not in danger)
    --   suffix    - " (Incoming)" / " (Expanding)" for the status line
    -- travelT (optional, 5th arg): how long it will actually take to be at `point` (a walk/blink ETA). When given,
    -- the projectile and growth predictions look ahead that far instead of their normal ~0.6-1 s window, so a zone
    -- that will have grown into / arrived at this spot by the time you get here is still flagged, not only one that
    -- is already close right now. Omitting it (every call site outside the dodge-spot safety check below) keeps the
    -- exact old behavior.
    function UI.hazardDanger(h, point, extra, now, travelT)
        local buffer = SETTINGS.DodgeBuffer + (extra or 0) + (h.pad or 0)
        local cf = h.cframe
        local center = cf.Position
        local nowT = now or os.clock()
        -- far outside anything the zone can reach within a second (or within travelT, if longer): skip the exact math
        local centerDist = (point - center).Magnitude
        local reach = h.reach or h.size.Magnitude / 2
        local farSlack = buffer + SETTINGS.DodgeBuffer + 1 + math.max((travelT or 0) - 1, 0) * 40
        if centerDist - reach > farSlack then return false, centerDist - reach, math.huge, nil end

        local v = h.velocity
        local moving = v and v.Magnitude > 4
        local dEdge = getDistanceToHazard(cf:PointToObjectSpace(point), h)
        local clearance = dEdge
        if dEdge <= buffer then
            -- a projectile on top of you hits now; a standing zone hurts when it fires (see fireAt)
            return true, clearance, (not moving and h.fireAt) and math.max(h.fireAt - nowT, 0) or 0, nil
        end

        if moving then
            -- fixed steps plus the exact moment the projectile passes closest to this point (within the window), so a
            -- fast orb can not slip between two samples; its path gets one extra Dodge Buffer of room
            local window = math.max(1, travelT or 0)
            local tClosest = math.clamp((point - center):Dot(v) / v:Dot(v), 0, window)
            local rot = cf - center
            local hitT
            for i = 1, 5 do
                local t = (i < 5) and (0.15 + (i - 1) * 0.2) or tClosest
                local fdEdge = getDistanceToHazard((rot + (center + v * t)):PointToObjectSpace(point), h)
                if fdEdge < clearance then clearance = fdEdge end
                if fdEdge <= buffer + SETTINGS.DodgeBuffer and (not hitT or t < hitT) then hitT = t end
            end
            if window > 1 then
                -- a few more samples further out in time so a projectile that is not close yet, but will be by the
                -- time we actually get there, is still caught
                local steps = math.min(math.ceil(window), 5)
                for i = 1, steps do
                    local t = 1 + i * (window - 1) / steps
                    local fdEdge = getDistanceToHazard((rot + (center + v * t)):PointToObjectSpace(point), h)
                    if fdEdge < clearance then clearance = fdEdge end
                    if fdEdge <= buffer + SETTINGS.DodgeBuffer and (not hitT or t < hitT) then hitT = t end
                end
            end
            if hitT then return true, clearance, hitT, " (Incoming)" end
        end

        local g = h.growth
        if g and g.Magnitude > 2 then
            -- expanding zone: its edge moves out at about half the size growth; danger when it reaches us within the
            -- window (normally 0.6 s; a little longer when it will take a while to actually walk here). Growth rate is
            -- extrapolated from a short recent sample, so stretching the window out over several seconds for a distant
            -- candidate would turn small measurement noise into huge, unjustified rejections - capped at 1.5 s.
            local window = math.min(math.max(0.6, travelT or 0), 1.5)
            local rate = math.min(math.max(g.X, g.Y, g.Z) / 2, 40 / 0.6)
            local edgeLater = dEdge - rate * window
            if edgeLater < clearance then clearance = edgeLater end
            if rate > 0.5 then
                local eta = (dEdge - buffer) / rate
                if eta <= window then return true, clearance, math.max(eta, 0), " (Expanding)" end
            end
        end
        return false, clearance, math.huge, nil
    end

    local function isPointInDanger(point, hazards, margin)
    local now = os.clock()
    local minHazardDist = math.huge
    for _, hazard in ipairs(hazards) do
        local inDanger, clearance, _, suffix = UI.hazardDanger(hazard, point, margin, now)
        if clearance < minHazardDist then minHazardDist = clearance end
        if inDanger then return true, hazard.name .. (suffix or ""), hazard, minHazardDist end
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

    -- floor under a spot (same ground rule as a blink), without the wall check
    function UI.hasGround(pos)
        local hit = Workspace:Raycast(pos + Vector3.new(0, 3.5, 0), Vector3.new(0, -28.5, 0), teleportRayParams)
        if not hit or not hit.Instance.CanCollide then return false end
        local drop = pos.Y - hit.Position.Y
        return drop >= -1.0 and drop <= 10.0
    end

    -- DODGE SPOT PICKER
    -- Every spot on 16 directions x 14 distances (2 - 40 studs) gets a cost; the lowest one that is reachable wins:
    --   * zones you stand in now: how many seconds AFTER a zone fires you would get out of it going this way (walking
    --     time uses your real WalkSpeed, so a frost slow counts), or a big cost when this way does not get you out at all.
    --     A zone that fires sooner weighs more, so the most urgent attack is always escaped first.
    --   * other zones still covering the spot, and zones the straight route walks through (weighted by how soon they fire)
    --   * then travel time, room to spare, staying in attack range, and small tie-breakers
    -- The destination keeps 2.5 studs more room than the trigger distance, so you do not stop right on the edge.
    -- Walls, ledges and invisible arena walls are checked best-first on the sorted list.
    UI.dodgeRings = { 2, 3.5, 5, 7, 9, 11, 13, 16, 19, 22, 26, 30, 35, 40 }

    function UI.findDodgePoint(playerPos, enemyPos, hazards, keepPoint)
        local now = os.clock()
        -- only zones that can reach a candidate matter; in bullet-hell phases this skips most of the work
        local near = {}
        local reachLimit = 40 + (SETTINGS.DodgeBuffer + 3) * 2 + 3
        for _, h in ipairs(hazards) do
            if (h.cframe.Position - playerPos).Magnitude - (h.reach or h.size.Magnitude / 2) <= reachLimit then table.insert(near, h) end
        end
        -- zones covering you right now, and when each of them fires
        local coverEta, soonest = {}, math.huge
        for i, h in ipairs(near) do
            local inDanger, _, eta = UI.hazardDanger(h, playerPos, 0, now)
            if inDanger then
                coverEta[i] = eta
                if eta < soonest then soonest = eta end
            end
        end
        local speed = math.max(humanoid and humanoid.WalkSpeed or 16, 4)
        local canBlink = SETTINGS.GameplayMode ~= "Legit Player" and SETTINGS.GameplayMode ~= "No TP Auto Play" and now - lastTpDodgeTime >= 1.5
        local hasEnemy = (enemyPos - playerPos).Magnitude > 0.5
        local idealCombatDist = (SETTINGS.MinDistance + SETTINGS.MaxDistance) * 0.5
        local lastDir = (UI.lastDodgeDir and now - (UI.lastDodgeTime or 0) < 1.5) and UI.lastDodgeDir or nil
        local badSpot = (UI.badDodgeSpot and now < (UI.badDodgeUntil or 0)) and UI.badDodgeSpot or nil
        local extra = 2.5
        -- a projectile's path is only dangerous if you are there when it passes, so crossing or ending up on one costs
        -- less than a standing zone that is certain to fire
        local isMoving = {}
        for i, h in ipairs(near) do isMoving[i] = h.velocity.Magnitude > 4 end

        local list = {}
        for _, dir in ipairs(DODGE_DIRECTIONS) do
            local exitAt, crossed, crossCost, prevDist = {}, {}, 0, 0
            for _, dist in ipairs(UI.dodgeRings) do
                local pos = playerPos + dir * dist
                local quick = canBlink and dist <= 9
                local travelT = quick and 0.05 or dist / speed
                local cost, clearance, newly = 0, math.huge, nil
                -- hazards this candidate is (loosely) flagged against: cheap to collect (no extra hazardDanger calls),
                -- and left nil when there are none, so most far-away candidates cost nothing extra at all. The real
                -- Dodge-Buffer safety recheck only runs later, lazily, for the handful of candidates actually
                -- considered once the list is sorted by cost - not for all of them up front.
                local risky
                for i, h in ipairs(near) do
                    -- the extra room is for standing zones; projectile paths already get a whole extra Dodge Buffer
                    local inDanger, clr, eta = UI.hazardDanger(h, pos, isMoving[i] and 0 or extra, now)
                    if clr < clearance then clearance = clr end
                    if inDanger then
                        risky = risky or {}
                        risky[#risky + 1] = { h = h, moving = isMoving[i], eta = eta }
                    end
                    local coverT = coverEta[i]
                    if coverT then
                        -- exactly where this way gets out of the zone (trigger distance, to a quarter stud): the fixed
                        -- distances alone would make a slower way out look as fast as the fastest one
                        if not exitAt[i] and not UI.hazardDanger(h, pos, 0, now) then
                            local lo, hi = prevDist, dist
                            for _ = 1, 5 do
                                local mid = (lo + hi) / 2
                                if UI.hazardDanger(h, playerPos + dir * mid, 0, now) then lo = mid else hi = mid end
                            end
                            exitAt[i] = hi
                        end
                        -- when would we be free of this zone going this way: on the way here, or - if the spot is still
                        -- inside it - after walking the rest of the way out from the spot
                        local tFree
                        if exitAt[i] then
                            tFree = quick and 0.05 or exitAt[i] / speed
                            if inDanger then cost = cost + 2 end      -- out, but closer to its edge than we like
                        else
                            local depth = SETTINGS.DodgeBuffer + (h.pad or 0) - clr
                            tFree = (quick and 0.05 or dist / speed) + math.max(depth, 0) / speed
                        end
                        -- slack = time left over once free of it. Free AFTER it fires costs 40 per second; time-to-free is
                        -- weighted by urgency, so the quickest way out of the zone that fires soonest wins; and a spot
                        -- still inside the zone costs more the tighter its slack (a later zone can be left later, but not
                        -- by walking so deep into it that there is no time left to get out)
                        local slack = coverT - tFree
                        if slack < 0 then cost = cost + math.min(-slack * 40, 40) end
                        cost = cost + tFree * 10 / (0.3 + coverT)
                        if not exitAt[i] then cost = cost + 8 / (0.3 + math.max(slack, 0)) end
                    elseif inDanger then
                        local tHere = quick and 0.05 or dist / speed
                        if isMoving[i] then
                            -- a projectile only matters if it passes this spot while you are there: ending up here counts
                            -- unless it has already gone by when you arrive, crossing counts only if you meet it
                            if eta + 0.4 >= tHere then cost = cost + 3 / (0.3 + eta) end
                            if not crossed[i] and math.abs(eta - tHere) < 0.4 then
                                newly = newly or {}
                                newly[i] = 1.5 / (0.3 + eta)
                            end
                        else
                            cost = cost + 6 / (0.3 + eta)                        -- ending up in another zone
                            if not crossed[i] then
                                newly = newly or {}
                                newly[i] = 4 / (0.3 + eta)
                            end
                        end
                    end
                end
                -- room to spare only counts outside zones (being inside one is already costed above)
                cost = cost + crossCost + (quick and 0.05 or dist / speed) * 3 - math.clamp(clearance, 0, 8) * 0.3
                if hasEnemy then
                    -- dodging should not drag you far out of attack range or into the enemy's face
                    local d = (pos - enemyPos).Magnitude
                    if d > SETTINGS.AttackReach then cost = cost + (d - SETTINGS.AttackReach) * 0.15 end
                    if d < SETTINGS.MinDistance then cost = cost + (SETTINGS.MinDistance - d) * 0.12 end
                    cost = cost + math.abs(d - idealCombatDist) * 0.02
                end
                -- tie-breakers: do not flip-flop between two exits (only when nothing is about to fire), keep the
                -- current plan when it is still as good, and avoid a spot we just got stuck walking to
                if lastDir and soonest > 0.8 and dir:Dot(lastDir) < -0.3 then cost = cost + 1.5 end
                if keepPoint and (pos - keepPoint).Magnitude < 4 then cost = cost - 1 end
                if badSpot and (pos - badSpot).Magnitude < 4 then cost = cost + 30 end
                table.insert(list, { pos = pos, score = cost, risky = risky, travelT = travelT })
                -- zones first met at this distance are walked through by every spot further out this way
                if newly then
                    for i, c in pairs(newly) do
                        crossed[i] = true
                        crossCost = crossCost + c
                    end
                end
                prevDist = dist
            end
        end
        table.sort(list, function(a, b) return a.score < b.score end)

        -- invisible arena walls (made walk-through elsewhere so the bot does not get stuck) still mark the edge of the
        -- safe area: never dodge past one
        local wallParams
        local walls = {}
        for w in pairs(cachedInviswalls) do
            if w.Parent then table.insert(walls, w) end
        end
        if #walls > 0 then
            wallParams = RaycastParams.new()
            wallParams.FilterType = Enum.RaycastFilterType.Include
            wallParams.FilterDescendantsInstances = walls
        end
        local function pastArenaWall(pos)
            return wallParams ~= nil and Workspace:Raycast(playerPos, pos - playerPos, wallParams) ~= nil
        end
        local function pick(pos)
            UI.lastDodgeDir = Vector3.new(pos.X - playerPos.X, 0, pos.Z - playerPos.Z).Unit
            UI.lastDodgeTime = now
            UI.safeSpot, UI.safeSpotUntil = pos, now + 1
            return pos
        end
        -- a spot that the real Dodge Buffer would still call dangerous is never returned just because it scored
        -- lowest: overlapping zones can cover the whole 40-stud grid, and picking one of those "least bad" spots is
        -- how you end up standing between two AOEs. A genuinely safe spot always wins over a merely cheap one.
        -- The real recheck (a second UI.hazardDanger call) only runs here, lazily, for candidates this loop actually
        -- reaches while scanning cheapest-first, and only against the hazards that candidate was flagged against -
        -- not for all 224 candidates x all hazards up front. Whichever passes first is both the cheapest AND verified
        -- safe, since the list is already sorted by cost.
        local function isSafe(c)
            if c.safeCache ~= nil then return c.safeCache end
            local ok = true
            if c.risky then
                for _, r in ipairs(c.risky) do
                    if r.moving then
                        -- already computed with the real buffer (extra 0) during scoring; only still unsafe if the
                        -- projectile is relevant by the time we would actually be here
                        if r.eta + 0.4 >= c.travelT then ok = false; break end
                    elseif UI.hazardDanger(r.h, c.pos, 0, now, c.travelT) then
                        ok = false; break
                    end
                end
            end
            c.safeCache = ok
            return ok
        end
        for n, c in ipairs(list) do
            if n > 64 then break end
            if isSafe(c) and not pastArenaWall(c.pos) and isValidTeleport(playerPos, c.pos) then return pick(c.pos) end
        end
        for n, c in ipairs(list) do
            if n > 64 then break end
            if isSafe(c) and not pastArenaWall(c.pos) and UI.hasGround(c.pos) then return pick(c.pos) end
        end
        -- nothing safe inside 40 studs (everything in range is inside one zone or another): push further out along
        -- any direction that is actually clear, instead of settling for a spot the grid already flagged as unsafe
        if #near > 0 then
            for _, extraDist in ipairs({ 50, 65, 80, 100 }) do
                for _, dir in ipairs(DODGE_DIRECTIONS) do
                    local pos = playerPos + dir * extraDist
                    local travelT = extraDist / speed
                    local ok = true
                    for _, h in ipairs(near) do
                        if UI.hazardDanger(h, pos, 0, now, travelT) then ok = false; break end
                    end
                    if ok and not pastArenaWall(pos) and (isValidTeleport(playerPos, pos) or UI.hasGround(pos)) then
                        return pick(pos)
                    end
                end
            end
        end
        -- truly nothing safe anywhere nearby (arena fully overlapped): fall back to the least-bad spot found rather
        -- than not moving at all while standing inside the overlap
        for n, c in ipairs(list) do
            if n > 48 then break end
            if not pastArenaWall(c.pos) and isValidTeleport(playerPos, c.pos) then return pick(c.pos) end
        end
        for n, c in ipairs(list) do
            if n > 48 then break end
            if not pastArenaWall(c.pos) and UI.hasGround(c.pos) then return pick(c.pos) end
        end
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

    -- RE-SCAN: re-scores every part in the workspace (in chunks) after the dodge list or learned list changes
    function UI.rescanAllHazards()
        UI.listCache = setmetatable({}, { __mode = "k" })
        UI.hazardRescanId = (UI.hazardRescanId or 0) + 1
        local myId = UI.hazardRescanId
        task.spawn(function()
            for i, obj in ipairs(Workspace:GetDescendants()) do
                if myId ~= UI.hazardRescanId or isCleaningUp then return end
                if obj:IsA("BasePart") then pcall(evaluateAndAddHazardPart, obj) end
                if i % 3000 == 0 then task.wait() end
            end
        end)
    end

    function UI.onDodgeListChanged()
        UI.updateDodgeList()
        UI.rescanAllHazards()
    end

    -- PREDICT ATTACKS BY LEARNING WHAT HURTS YOU
    -- 1) Attack parts. Every 0.2 s the parts spawned during the fight that touch you are noted as "touch episodes" (one
    --    episode = one continuous stretch of touching). When you take damage, every name you touched in the last 2.5 s
    --    gets a hit - so the ground telegraph you stood in BEFORE the hit is learned, not only the impact effect. A name
    --    with 3+ hits that hurts on most episodes (hits >= 60% of episodes) is learned and dodged the moment it spawns
    --    from then on, even as an invisible hitbox. Long harmless contact (your own aura) keeps adding episodes, so it never
    --    reaches that ratio. A heavy hit (40%+ of max HP, or a one-shot) counts as 3 hits, so a one-shot is learned at once.
    -- 2) Boss animations. The wind-up animation a boss plays before an attack is what gives it away when there is no
    --    telegraph at all. Each non-looping animation a nearby mob starts is noted; when you take damage 0.1 - 3 s later it
    --    gets a hit (a heavy hit counts 2). With 2+ hits on at least half of its plays it is learned with the delay until
    --    the hit and its reach, and from then on starting that animation puts a "predicted" zone around the boss that the
    --    dodge escapes before the hit lands. Being hit anyway widens the zone / shortens the delay.
    -- Damage is caught by Humanoid.HealthChanged (see UI.hookDamage), so even the hit that kills you is recorded.
    -- Wrong guesses can be cleared with "Forget Learned Attacks" in the Setting tab.
    UI.attackStats = {}      -- lower-case part name -> { hits, seen }
    UI.touchEpisodes = {}    -- lower-case part name -> { last, counted, hit }
    UI.animStats = {}        -- animation id -> { hits, plays, maxDist, minDelay }
    UI.animEvents = {}       -- recent mob animation starts { id, root, t }
    UI.predictions = UI.predictions or {}   -- live predicted zones (read by getDangerousHazards)

    function UI.partTouching(part, pos, margin)
        local cf, size, shape = UI.partGeometry(part)
        return getDistanceToHazard(cf:PointToObjectSpace(pos), { cframe = cf, size = size, shape = shape }) <= margin
    end

    function UI.learnAttack(lname)
        SETTINGS.LearnedAttacks[lname] = true
        UI.attackStats[lname] = nil
        UI.listCache = setmetatable({}, { __mode = "k" })
        for part in pairs(UI.partBorn) do
            if part.Parent and part.Name:lower() == lname then pcall(evaluateAndAddHazardPart, part) end
        end
        UI.refreshAttackRows()
        setStatus("Status: Learned new attack - " .. lname, true)
        saveConfig()
    end

    function UI.forgetLearnedAttacks()
        table.clear(SETTINGS.LearnedAttacks)
        table.clear(SETTINGS.LearnedAnims)
        table.clear(UI.attackStats)
        table.clear(UI.touchEpisodes)
        table.clear(UI.animStats)
        table.clear(UI.predictions)
        UI.rescanAllHazards()
        UI.refreshAttackRows()
        setStatus("Status: Learned attacks cleared", true)
        saveConfig()
    end

    -- samples which spawned parts touch you (every 0.2 s, or right away when forced by a damage event)
    function UI.learnTick(pos, force)
        local now = os.clock()
        if not force and now - (UI.lastLearnSample or 0) < 0.2 then return end
        UI.lastLearnSample = now
        local touching = {}
        for part, born in pairs(UI.partBorn) do
            if not part.Parent or now - born > 20 then
                UI.partBorn[part] = nil -- only the last 20 s of spawns matter; keeps this loop small
            else
                local cf, size, shape = UI.partGeometry(part)
                local half = size.Magnitude / 2
                if half <= 90 and (cf.Position - pos).Magnitude - half <= 3 then
                    local lname = part.Name:lower()
                    if not touching[lname] and not SETTINGS.LearnedAttacks[lname] and not UI.isNotAttackName(lname)
                        and not lname:find("macropathnode", 1, true) and not isPlayerOrTeammatePart(part) and not isMobLimb(part)
                        and getDistanceToHazard(cf:PointToObjectSpace(pos), { cframe = cf, size = size, shape = shape }) <= 2 then
                        local model = part:FindFirstAncestorOfClass("Model")
                        if not (model and model:FindFirstChildOfClass("Humanoid")) then touching[lname] = true end
                    end
                end
            end
        end
        for lname in pairs(touching) do
            local st = UI.attackStats[lname]
            if not st then st = { hits = 0, seen = 0 }; UI.attackStats[lname] = st end
            local ep = UI.touchEpisodes[lname]
            if not ep or now - ep.last > 0.6 then
                UI.touchEpisodes[lname] = { last = now, counted = now, hit = false }
                st.seen = st.seen + 1
            else
                ep.last = now
                -- every 2 s of continuous contact counts as another episode, so a harmless aura piles up "seen"
                if now - ep.counted >= 2 then ep.counted = now; st.seen = st.seen + 1 end
            end
        end
        for lname, ep in pairs(UI.touchEpisodes) do
            if now - ep.last > 10 then UI.touchEpisodes[lname] = nil end
        end
    end

    -- a mob started an animation near you (non-looping only: walk / idle loops are never attacks)
    function UI.onMobAnimation(hum, track)
        if isCleaningUp or not rootPart or track.Looped then return end
        local anim = track.Animation
        local id = anim and anim.AnimationId
        if not id or id == "" then return end
        local mob = hum.Parent
        local mobRoot = mob and (mob:FindFirstChild("HumanoidRootPart") or (mob:IsA("Model") and mob.PrimaryPart))
        if not mobRoot then return end
        local now = os.clock()
        local offset = mobRoot.Position - rootPart.Position
        local dist = Vector3.new(offset.X, 0, offset.Z).Magnitude
        if dist > 80 then return end
        while UI.animEvents[1] and now - UI.animEvents[1].t > 4 do table.remove(UI.animEvents, 1) end
        table.insert(UI.animEvents, { id = id, root = mobRoot, t = now })
        if dist <= 60 then
            local st = UI.animStats[id]
            if not st then st = { hits = 0, plays = 0 }; UI.animStats[id] = st end
            st.plays = st.plays + 1
        end
        local learned = SETTINGS.LearnedAnims[id]
        if learned then
            table.insert(UI.predictions, {
                root = mobRoot, name = mob.Name, hitAt = now + learned.d, untilT = now + learned.d + 0.5, radius = learned.r,
            })
        end
    end

    function UI.learnFromAnims(pos, now, heavy)
        -- the latest start of each animation in the 0.1 - 3 s before the hit
        local latest = {}
        for _, ev in ipairs(UI.animEvents) do
            local age = now - ev.t
            if age >= 0.1 and age <= 3 and ev.root.Parent and (not latest[ev.id] or ev.t > latest[ev.id].t) then
                latest[ev.id] = ev
            end
        end
        for id, ev in pairs(latest) do
            local st = UI.animStats[id]
            if not st then st = { hits = 0, plays = 1 }; UI.animStats[id] = st end
            local offset = ev.root.Position - pos
            local dist = Vector3.new(offset.X, 0, offset.Z).Magnitude
            local delay = now - ev.t
            st.hits = st.hits + (heavy and 2 or 1)
            st.maxDist = math.max(st.maxDist or 0, dist)
            st.minDelay = math.min(st.minDelay or math.huge, delay)
            local learned = SETTINGS.LearnedAnims[id]
            if learned then
                -- hit anyway inside its window: widen the zone and expect it sooner next time
                if delay <= learned.d + 0.6 then
                    local r = math.clamp(math.max(learned.r, dist + 4), 8, 40)
                    local d = math.clamp(math.min(learned.d, delay - 0.1), 0.15, 3)
                    if r ~= learned.r or d ~= learned.d then
                        learned.r, learned.d = r, d
                        saveConfig()
                    end
                end
            elseif st.hits >= 2 and st.hits >= st.plays * 0.5 then
                SETTINGS.LearnedAnims[id] = {
                    d = math.clamp(st.minDelay - 0.1, 0.15, 3),
                    r = math.clamp(st.maxDist + 4, 8, 40),
                }
                UI.refreshAttackRows()
                setStatus("Status: Learned a boss attack animation - it is dodged before it lands now", true)
                saveConfig()
            end
        end
    end

    function UI.onDamaged(lost, maxHp, fatal)
        if not rootPart then return end
        local now = os.clock()
        local pos = rootPart.Position
        local heavy = fatal or (maxHp and maxHp > 0 and lost >= maxHp * 0.4)
        UI.learnTick(pos, true) -- note what is touching you at the moment of the hit too
        local w = heavy and 3 or 1
        for lname, ep in pairs(UI.touchEpisodes) do
            if not ep.hit and now - ep.last <= 2.5 then
                ep.hit = true
                local st = UI.attackStats[lname]
                if st then
                    st.hits = st.hits + w
                    if not SETTINGS.LearnedAttacks[lname] and st.hits >= 3 and st.hits >= st.seen * 0.6 then UI.learnAttack(lname) end
                end
            end
        end
        UI.learnFromAnims(pos, now, heavy)
    end

    -- HealthChanged fires even for the hit that kills you (the main loop stops running at 0 HP, so it could never see it)
    UI.damageHooked = setmetatable({}, { __mode = "k" })
    function UI.hookDamage(hum)
        if not hum or UI.damageHooked[hum] then return end
        UI.damageHooked[hum] = true
        local last = hum.Health
        table.insert(connections, hum.HealthChanged:Connect(function(hp)
            local lost = last - hp
            last = hp
            if lost > 0.001 and isAutoplay and SETTINGS.LearnAttacks and not isInLobby() then
                pcall(UI.onDamaged, lost, hum.MaxHealth, hp <= 0)
            end
        end))
    end
    UI.hookDamage(humanoid)
    table.insert(connections, player.CharacterAdded:Connect(function(char)
        task.spawn(function() UI.hookDamage(char:WaitForChild("Humanoid", 5)) end)
    end))

    -- listen to every mob's Animator (checked once a second, so new mobs and late Animators are picked up)
    UI.animHooked = setmetatable({}, { __mode = "k" })
    UI.animConns = {}
    function UI.hookMobAnimator(hum)
        if UI.animHooked[hum] or not hum.Parent then return end
        if Players:GetPlayerFromCharacter(hum.Parent) then UI.animHooked[hum] = true; return end
        local animator = hum:FindFirstChildOfClass("Animator")
        if not animator then return end
        UI.animHooked[hum] = true
        table.insert(UI.animConns, animator.AnimationPlayed:Connect(function(track) pcall(UI.onMobAnimation, hum, track) end))
    end
    task.spawn(function()
        while not isCleaningUp do
            for hum in pairs(trackedHumanoids) do pcall(UI.hookMobAnimator, hum) end
            for i = #UI.animConns, 1, -1 do
                if not UI.animConns[i].Connected then table.remove(UI.animConns, i) end
            end
            task.wait(1)
        end
        for _, conn in ipairs(UI.animConns) do pcall(function() conn:Disconnect() end) end
    end)

    -- DODGE HELPERS FOR THE MAIN LOOP

    -- DODGE BOOST: a "burst" budget (SETTINGS.DodgeBoostStuds studs, UI.dodgeBoostPool tracks what is left) that
    -- drains by however far the character actually travels while chasing activeDodgePoint, and refills over
    -- DODGE_BOOST_REFILL_TIME seconds once it is not dodging. While the pool still has studs left, WalkSpeed is
    -- boosted so the dodge visibly bursts ahead; the instant it hits 0 it drops back to the normal speed for the
    -- rest of that dodge - "burst, then walk", same idea as the reference "Dodge Budget" this was modeled on.
    -- This only changes how fast the character moves to a dodge point already chosen elsewhere; it never
    -- influences which point gets picked (UI.findDodgePoint / UI.hazardDanger / getDangerousHazards are untouched).
    local DODGE_BOOST_MULT = 1.7
    local DODGE_BOOST_REFILL_TIME = 3.5

    -- called once per frame that is NOT actively dodging, so the pool climbs back to full a few seconds later
    function UI.regenDodgeBoost(deltaTime)
        if UI.dodgeBoostPool < SETTINGS.DodgeBoostStuds then
            UI.dodgeBoostPool = math.min(SETTINGS.DodgeBoostStuds, UI.dodgeBoostPool + SETTINGS.DodgeBoostStuds * (deltaTime / DODGE_BOOST_REFILL_TIME))
        end
        UI.dodgeBoostLastPos = nil
    end

    -- called every frame the character is actively walking towards activeDodgePoint: burns the pool by the studs
    -- actually covered since the previous frame (not an assumed speed), and sets WalkSpeed for this frame's
    -- upcoming MoveTo/blink call - boosted while the pool has studs left, the normal speed once it is empty.
    function UI.applyDodgeBoost(pos)
        if not humanoid then return end
        if not UI.dodgeBoostNormalSpeed then UI.dodgeBoostNormalSpeed = humanoid.WalkSpeed end
        if UI.dodgeBoostLastPos then
            local moved = (pos - UI.dodgeBoostLastPos).Magnitude
            if moved < 30 then -- a bigger jump is a blink landing here, already charged separately below
                UI.dodgeBoostPool = math.max(0, UI.dodgeBoostPool - moved)
            end
        end
        UI.dodgeBoostLastPos = pos
        if SETTINGS.DodgeBoostStuds > 0 and UI.dodgeBoostPool > 0 then
            humanoid.WalkSpeed = UI.dodgeBoostNormalSpeed * DODGE_BOOST_MULT
        else
            humanoid.WalkSpeed = UI.dodgeBoostNormalSpeed
        end
    end

    -- a blink covers `studs` instantly: spend it from the same pool right away, since there is no gradual frame
    -- delta to measure it from the way a walked dodge has
    function UI.consumeDodgeBoost(studs)
        UI.dodgeBoostPool = math.max(0, UI.dodgeBoostPool - studs)
    end

    -- the dodge just ended (activeDodgePoint became nil): restore whatever WalkSpeed was active before boosting
    function UI.endDodgeBoost()
        if UI.dodgeBoostNormalSpeed and humanoid then
            humanoid.WalkSpeed = UI.dodgeBoostNormalSpeed
        end
        UI.dodgeBoostNormalSpeed = nil
        UI.dodgeBoostLastPos = nil
    end

    -- DODGE BOOST BAR: small HUD readout above the ability keys, shown only while it is actually usable (built
    -- lazily and hidden/destroyed the same way UI.blackGui / UI.rangeRings are elsewhere in this file)
    function UI.ensureDodgeBoostBar()
        if UI.dodgeBoostGui and UI.dodgeBoostGui.Parent then return end
        local T = UI.theme
        local gui = Instance.new("ScreenGui")
        gui.Name = "NCLDodgeBoostBar"
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.DisplayOrder = 90
        gui.Parent = (UI.screenGui and UI.screenGui.Parent) or player:WaitForChild("PlayerGui")

        local frame = Instance.new("Frame")
        frame.AnchorPoint = Vector2.new(0.5, 1)
        frame.Position = UDim2.new(0.5, 0, 1, -160) -- just above where most games put the Q/E ability icons
        frame.Size = UDim2.new(0, 220, 0, 42)
        frame.BackgroundColor3 = T.panel
        frame.BackgroundTransparency = 0.15
        frame.BorderSizePixel = 0
        frame.Parent = gui
        local frameCorner = Instance.new("UICorner"); frameCorner.CornerRadius = UDim.new(0, 8); frameCorner.Parent = frame
        local frameStroke = Instance.new("UIStroke"); frameStroke.Color = T.stroke; frameStroke.Thickness = 1; frameStroke.Parent = frame

        local lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1
        lbl.Size = UDim2.new(1, -12, 0, 16)
        lbl.Position = UDim2.new(0, 6, 0, 4)
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 11
        lbl.TextColor3 = T.text
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Text = "DODGE BOOST"
        lbl.Parent = frame

        local track = Instance.new("Frame")
        track.Position = UDim2.new(0, 6, 0, 22)
        track.Size = UDim2.new(1, -12, 0, 10)
        track.BackgroundColor3 = T.field
        track.BorderSizePixel = 0
        track.Parent = frame
        local trackCorner = Instance.new("UICorner"); trackCorner.CornerRadius = UDim.new(0, 5); trackCorner.Parent = track

        local fill = Instance.new("Frame")
        fill.Size = UDim2.new(1, 0, 1, 0)
        fill.BackgroundColor3 = T.green
        fill.BorderSizePixel = 0
        fill.Parent = track
        local fillCorner = Instance.new("UICorner"); fillCorner.CornerRadius = UDim.new(0, 5); fillCorner.Parent = fill

        UI.dodgeBoostGui, UI.dodgeBoostLabel, UI.dodgeBoostFill = gui, lbl, fill
    end

    function UI.hideDodgeBoostBar()
        if UI.dodgeBoostGui then UI.dodgeBoostGui.Enabled = false end
    end

    function UI.refreshDodgeBoostBar()
        if not (SETTINGS.ShowDodgeBoostBar and isAutoplay and not isInLobby()) then
            UI.hideDodgeBoostBar()
            return
        end
        UI.ensureDodgeBoostBar()
        UI.dodgeBoostGui.Enabled = true
        UI.dodgeBoostLabel.Text = string.format("DODGE BOOST %.1f STUDS", UI.dodgeBoostPool)
        local frac = SETTINGS.DodgeBoostStuds > 0 and math.clamp(UI.dodgeBoostPool / SETTINGS.DodgeBoostStuds, 0, 1) or 0
        UI.dodgeBoostFill.Size = UDim2.new(frac, 0, 1, 0)
        UI.dodgeBoostFill.BackgroundColor3 = (frac > 0.01) and UI.theme.green or Color3.fromRGB(120, 128, 150)
    end

    task.spawn(function()
        while not isCleaningUp do
            pcall(UI.refreshDodgeBoostBar)
            task.wait(0.1)
        end
        if UI.dodgeBoostGui then pcall(function() UI.dodgeBoostGui:Destroy() end) end
    end)

    -- new casts wait during the first 1.2 s of an evasion: a key press can start a cast animation that interrupts the
    -- escape, and aiming snaps the character around. After 1.2 s it attacks again, so a false alarm can not stop it for good.
    function UI.holdCasts(now)
        return UI.evadeSince ~= nil and now - UI.evadeSince < 1.2
    end

    -- how many zones cover this spot right now (Dodge Buffer, no extra room)
    function UI.countCovering(pos, hazards)
        local now, n = os.clock(), 0
        for _, h in ipairs(hazards) do
            if UI.hazardDanger(h, pos, 0, now) then n = n + 1 end
        end
        return n
    end

    -- true when the straight walk from fromPos to toPos runs through a zone you are not already standing in
    function UI.routeBlocked(fromPos, toPos, hazards)
        local delta = toPos - fromPos
        local dist = delta.Magnitude
        if dist < 1 then return false end
        local now = os.clock()
        local steps = math.clamp(math.ceil(dist / 3), 1, 14)
        for _, h in ipairs(hazards) do
            if not UI.hazardDanger(h, fromPos, 0, now) then
                for i = 1, steps do
                    if UI.hazardDanger(h, fromPos + delta * (i / steps), 0, now) then return true end
                end
            end
        end
        return false
    end

    -- ATTACK ESP: labels every attack the dodge logic currently sees (orange = dodge list, pink = learned,
    -- yellow = auto-detected) with a box around it, and marks the SAFE SPOT it is moving to.
    UI.espItems = {}
    UI.espColors = {
        list = Color3.fromRGB(255, 120, 60),
        learned = Color3.fromRGB(255, 80, 200),
        auto = Color3.fromRGB(255, 220, 70),
        predicted = Color3.fromRGB(80, 200, 255),
    }
    UI.espTags = {
        list = "DODGE (on dodge list)", learned = "DODGE (learned)", auto = "DODGE (auto-detected)",
        predicted = "PREDICTED ATTACK (learned animation)",
    }

    function UI.espContainer()
        if UI.espFolder and UI.espFolder.Parent then return UI.espFolder end
        local folder = Instance.new("Folder")
        folder.Name = "NCL ESP"
        folder.Parent = (UI.screenGui and UI.screenGui.Parent) or CoreGui
        UI.espFolder = folder
        return folder
    end

    function UI.makeEspLabel(adornee, color, text)
        local gui = Instance.new("BillboardGui")
        gui.Adornee = adornee
        gui.AlwaysOnTop = true
        gui.LightInfluence = 0
        gui.MaxDistance = 300
        gui.Size = UDim2.new(0, 220, 0, 30)
        gui.StudsOffset = Vector3.new(0, 1.5, 0)
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 11
        lbl.TextColor3 = color
        lbl.TextStrokeTransparency = 0.3
        lbl.Text = text
        lbl.Parent = gui
        gui.Parent = UI.espContainer()
        return gui, lbl
    end

    function UI.destroyEspItem(item)
        pcall(function() item.gui:Destroy() end)
        if item.box then pcall(function() item.box:Destroy() end) end
    end

    function UI.clearAttackEsp()
        for key, item in pairs(UI.espItems) do
            UI.destroyEspItem(item)
            UI.espItems[key] = nil
        end
        if UI.safeSpotGui then UI.safeSpotGui.Enabled = false end
    end

    function UI.updateAttackEsp()
        if not SETTINGS.ShowAttackEsp or not isAutoplay or isInLobby() then UI.clearAttackEsp(); return end
        local shown, count, now = {}, 0, os.clock()
        for _, h in ipairs(UI.lastHazards or {}) do
            -- attack parts get a label + box; predicted boss attacks get a label on the boss
            local key = h.part or h.root
            if key and key.Parent and not shown[key] and count < 60 then
                shown[key] = true
                count = count + 1
                local item = UI.espItems[key]
                if not item or item.reason ~= h.reason then
                    if item then UI.destroyEspItem(item) end
                    local color = UI.espColors[h.reason] or UI.espColors.auto
                    local gui, lbl = UI.makeEspLabel(key, color, h.name .. "\n" .. (UI.espTags[h.reason] or UI.espTags.auto))
                    local box
                    if h.part then
                        box = Instance.new("SelectionBox")
                        box.Adornee = h.part
                        box.Color3 = color
                        box.LineThickness = 0.04
                        box.SurfaceTransparency = 1
                        box.Parent = UI.espContainer()
                    end
                    item = { gui = gui, lbl = lbl, box = box, reason = h.reason }
                    UI.espItems[key] = item
                end
                if h.predicted then
                    item.lbl.Text = string.format("%s\nPREDICTED ATTACK  reach %d studs  hits in %.1fs", h.name, h.radius, math.max(h.hitAt - now, 0))
                end
            end
        end
        for key, item in pairs(UI.espItems) do
            if not shown[key] then
                UI.destroyEspItem(item)
                UI.espItems[key] = nil
            end
        end
        -- the safe spot is a floating label on an attachment in Terrain (not a part, so the hazard scanner never sees it)
        if UI.safeSpot and os.clock() < (UI.safeSpotUntil or 0) then
            if not (UI.safeSpotAtt and UI.safeSpotAtt.Parent) then
                UI.safeSpotAtt = Instance.new("Attachment")
                UI.safeSpotAtt.Name = "NCLSafeSpot"
                UI.safeSpotAtt.Parent = Workspace.Terrain
                if UI.safeSpotGui then pcall(function() UI.safeSpotGui:Destroy() end) end
                UI.safeSpotGui = UI.makeEspLabel(UI.safeSpotAtt, Color3.fromRGB(70, 255, 130), "SAFE SPOT")
                UI.safeSpotGui.StudsOffset = Vector3.zero
            end
            UI.safeSpotAtt.WorldPosition = UI.safeSpot
            UI.safeSpotGui.Enabled = true
        elseif UI.safeSpotGui then
            UI.safeSpotGui.Enabled = false
        end
    end

    task.spawn(function()
        while not isCleaningUp do
            pcall(UI.updateAttackEsp)
            task.wait(0.15)
        end
        pcall(UI.clearAttackEsp)
    end)

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

    -- STAGE LOSS: fires once per dungeon attempt when the countdown timer hits 0:00
    if not hasSentStageLoss then
        local timeGui = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("timeLeftGui")
        local timeFrame = timeGui and findNested(timeGui, "Frame", "time")
        if timeFrame and timeFrame:IsA("TextLabel") then
            local secs = parseTimeToSeconds(timeFrame.Text)
            if secs ~= nil and secs <= 0 then
                hasSentStageLoss = true
                setStatus("Status: Time ran out - Stage Loss!", true)
                pcall(warn, "[Webhook] time hit zero (\"" .. tostring(timeFrame.Text) .. "\") - sending STAGE LOSS webhook")
                sendStageLossWebhook()
            end
        end
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
    UI.lastHazards = hazards
    -- note which spawned parts touch you (the damage itself is caught by UI.hookDamage, even a one-shot)
    if SETTINGS.LearnAttacks then pcall(UI.learnTick, playerPos) end
    local activeTarget = findBestTarget()

    -- Continuous Aim Lock on Enemy
    if activeTarget and activeTarget:FindFirstChild("HumanoidRootPart") then
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

    -- COMBAT (no new cast during the first moments of an evasion, see UI.holdCasts)
    if not isCasting and (now - lastAttackSequenceTime >= SETTINGS.AttackCooldown) and not UI.holdCasts(now) then
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

                        -- Fire E if not reserved for Buff Spammer (and not if an evasion started since Q)
                        if not (SETTINGS.EIFSpammerEnabled and SETTINGS.EIFSpammerSlot:upper() == "E") and not UI.holdCasts(os.clock()) then
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
    -- remembered for UI.holdCasts (new casts wait during the first moments of an evasion)
    if currentlyInDanger then UI.evadeSince = UI.evadeSince or now else UI.evadeSince = nil end

    if currentlyInDanger and detectedHazardName then
        evadingDisplayUntil = now + 3.0
        setStatus("Status: Evading: " .. tostring(detectedHazardName), true)
    end

    if now < postDodgeHoldUntil and not currentlyInDanger then
        return
    end

    if currentlyInDanger or (activeDodgePoint and now < dodgeExpiration) then
        -- Re-plan when there is no spot yet, the spot stopped being safe, or - while in danger - the plan is 0.5 s old,
        -- one more zone now covers you, or the straight route to the spot now runs through a zone you are not standing in.
        -- (When no spot was found, it retries every 0.2 s instead of every frame.)
        local replan = false
        if not activeDodgePoint then
            replan = now - (UI.planFailedAt or 0) >= 0.2
        elseif isPointInDanger(activeDodgePoint, hazards) then
            replan = true
        elseif currentlyInDanger then
            replan = now - (UI.planTime or 0) >= 0.5 or UI.countCovering(playerPos, hazards) > (UI.planCovering or 0)
                or UI.routeBlocked(playerPos, activeDodgePoint, hazards)
        end
        if replan then
            local enemyPos = activeTarget and activeTarget:FindFirstChild("HumanoidRootPart") and activeTarget.HumanoidRootPart.Position or playerPos
            activeDodgePoint = UI.findDodgePoint(playerPos, enemyPos, hazards, activeDodgePoint)
            -- keep walking to the spot for up to 1.2 s even after leaving the danger, so you do not stop right at the edge
            dodgeExpiration  = activeDodgePoint and (now + 1.2) or 0
            UI.planTime, UI.planCovering = now, UI.countCovering(playerPos, hazards)
            if not activeDodgePoint then UI.planFailedAt = now end
            UI.dodgeProgressPos, UI.dodgeProgressTime = playerPos, now
        end

        if activeDodgePoint then
            local toTarget = activeDodgePoint - playerPos
            local dist = toTarget.Magnitude
            if dist < 1.5 then
                activeDodgePoint = nil; dodgeExpiration = 0
                UI.endDodgeBoost()
                return
            end

            -- Blocked on the way out (wall, ledge, mob body): jump, mark the spot bad for 1.5 s and re-pick next frame.
            -- Being slowed, frozen or rooted (low WalkSpeed / anchored) is not a blocked route: re-picking every 0.4 s there
            -- kept sending you a new, wrong way, so the timer just waits until you can move again.
            local walkSpeed = humanoid.WalkSpeed
            if walkSpeed < 8 or rootPart.Anchored then
                UI.dodgeProgressPos, UI.dodgeProgressTime = playerPos, now
            elseif not UI.dodgeProgressPos or (playerPos - UI.dodgeProgressPos).Magnitude > math.max(1, walkSpeed * 0.1) then
                UI.dodgeProgressPos, UI.dodgeProgressTime = playerPos, now
            elseif now - UI.dodgeProgressTime > 0.5 then
                UI.badDodgeSpot, UI.badDodgeUntil = activeDodgePoint, now + 1.5
                humanoid.Jump = true
                activeDodgePoint, dodgeExpiration, UI.dodgeProgressPos = nil, 0, nil
                UI.endDodgeBoost()
                return
            end

            -- DODGE BOOST: charges the pool for the studs actually covered since last frame and sets WalkSpeed for
            -- the movement call right below - boosted while the pool still has studs, normal once it is spent. Only
            -- affects travel speed to the point chosen above, never the point itself.
            UI.applyDodgeBoost(playerPos)

            local allowTeleport = (SETTINGS.GameplayMode ~= "Legit Player") and (SETTINGS.GameplayMode ~= "No TP Auto Play")
            if allowTeleport and (now - lastTpDodgeTime >= 1.5) then
                if dist <= 9 and isValidTeleport(playerPos, activeDodgePoint) then
                    lastTpDodgeTime = now
                    UI.consumeDodgeBoost(dist) -- a blink covers `dist` studs instantly, charged the same pool
                    executeSafeBlink(activeDodgePoint, activeDodgePoint + toTarget)
                    activeDodgePoint = nil
                    UI.endDodgeBoost()
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
    UI.endDodgeBoost()
    UI.regenDodgeBoost(deltaTime)

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
                setStatus(string.format("MACRO ACTIVE: Path %d/%d (%.1f st)", currentWaypointIndex, #waypoints, distToNode))
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
    -- Reads the gold amount shown on the incoming trade offer. The game shows it as a single label reading e.g.
    -- "0 Gold" or "1,234 Gold" (not a bare number), so we match that directly. Returns nil if no such label is found.
    local function getIncomingTradeGold()
        local pGui = player:FindFirstChild("PlayerGui")
        if not pGui then return nil end
        for _, obj in ipairs(pGui:GetDescendants()) do
            if (obj:IsA("TextLabel") or obj:IsA("TextButton")) and obj.AbsoluteSize.X > 0 and not (UI.screenGui and obj:IsDescendantOf(UI.screenGui)) then
                local value = obj.Text:match("^%s*([%d,%.]+%s*[KMBTkmbt]?)%s*[Gg]old%s*$")
                if value then
                    local num = tonumber((value:gsub("[^%d%.]", "")))
                    if num then return num end
                end
            end
        end
        return nil
    end

    -- finds the on-screen "Decline"/"Cancel" button of the trade window and presses it (used to auto-cancel 0-gold offers).
    -- Mirrors UI.clickAcceptButton's click strategy (fire the button's own handlers, then a real mouse click).
    function UI.clickDeclineButton()
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
        local wanted = { decline = true, cancel = true, reject = true, close = true }
        local function findBtn()
            for _, obj in ipairs(pGui:GetDescendants()) do
                if (obj:IsA("TextButton") or obj:IsA("TextLabel")) and not (UI.screenGui and obj:IsDescendantOf(UI.screenGui)) then
                    local t = obj.Text:lower():match("^%s*(.-)%s*$")
                    if wanted[t] and shown(obj) then return obj end
                end
            end
        end
        local btn
        for _ = 1, 20 do
            btn = findBtn()
            if btn then break end
            task.wait(0.1)
        end
        if not btn then return false, "Decline/Cancel button not found" end
        pcall(warn, "[Trade] Decline button: " .. btn:GetFullName() .. " (" .. btn.ClassName .. ")")

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
        if not shown(btn) then return true, "declined" end

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
        if not shown(btn) then return true, "declined" end
        return false, ok and "clicked Decline but the popup is still open" or "could not click Decline"
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
                                local declined, dInfo = UI.clickDeclineButton()
                                setAccept((declined and "cancelled" or ("could not cancel - " .. tostring(dInfo))) .. " trade from " .. who .. " (0 gold offered)")
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
        ScriptId = "bf8b052cd5bb75acc78f35c970e99c86", -- your Luarmor project's script ID (same one used in your loadstring URL)
        Discord = DISCORD_INVITE,  -- copied to the clipboard by the Join Discord button
        File = FOLDER_NAME .. "/key.txt",
        GetKeyUrlLinkvertise = "https://ads.luarmor.net/get_key?for=NCL_HUB-UmSUNONLKyZI",
        GetKeyUrlLootLab = "", -- TODO: isi link Get Key LootLab kamu di sini
    }

    -- Luarmor SDK: fetched once and reused, so keys stay in sync with the Luarmor dashboard instead of a hardcoded list
    local luarmorApi
    local function getLuarmorApi()
        if luarmorApi then return luarmorApi end
        local ok, result = pcall(function()
            local sdk = loadstring(game:HttpGet("https://sdkapi-public.luarmor.net/library.lua"))()
            sdk.script_id = KEY.ScriptId
            return sdk
        end)
        if ok then luarmorApi = result end
        return luarmorApi
    end

    local function keyIsValid(input)
        input = tostring(input or ""):match("^%s*(.-)%s*$")
        if input == "" then return false, "Enter a key first" end

        local api = getLuarmorApi()
        if not api then return false, "Could not reach the key server" end

        local ok, status = pcall(api.check_key, input)
        if not ok or type(status) ~= "table" then return false, "Could not reach the key server" end

        if status.code == "KEY_VALID" then
            return true
        elseif status.code == "KEY_HWID_LOCKED" then
            return false, "Key linked to a different device - reset it via our Discord"
        elseif status.code == "KEY_INCORRECT" then
            return false, "Key is wrong or deleted"
        else
            return false, tostring(status.message or status.code or "Invalid key")
        end
    end

    -- KEY EXPIRY: best-effort lookup of how long the current key is valid for, used by the countdown on
    -- the key screen and in the sidebar (see NCL_KeyExpiresAt below). Luarmor's public SDK does not
    -- document a stable field name for this, so a handful of common ones are checked; if none are present
    -- the timer stays blank instead of showing a made-up number. Returns nil (unknown), 0 (lifetime key,
    -- never expires) or a unix timestamp.
    local function fetchKeyExpiry(key)
        local api = getLuarmorApi()
        if not api or not api.get_user_data then return nil end
        local ok, data = pcall(api.get_user_data, key)
        if not ok or type(data) ~= "table" then return nil end
        local d = data.data or data
        local expiry = d.auth_expire or d.authExpire or d.expires_at or d.expiresAt or d.expiry or d.key_expire or d.keyExpire
        if type(expiry) == "number" then return expiry end
        return nil
    end

    -- set (globally, no `local`) once a key is accepted, so Luarmor's own runtime can read it after
    -- LRM_INIT_SCRIPT returns; keyAccepted is what the blocking wait loop below watches
    local keyAccepted = false

    local function showKeySystem()
        if not KEY.Required then keyAccepted = true; return end

        local saved
        pcall(function() if isfile and isfile(KEY.File) then saved = readfile(KEY.File) end end)
        if saved and keyIsValid(saved) then
            script_key = saved
            NCL_KeyExpiresAt = fetchKeyExpiry(saved)
            keyAccepted = true
            return
        end

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

        local win = box(gui, 0, 0, 720, 390, C.bg)
        win.AnchorPoint = Vector2.new(0.5, 0.5); win.Position = UDim2.new(0.5, 0, 0.5, 0)
        win.Active = true; win.Draggable = true; win.ClipsDescendants = true
        corner(win, 14); outline(win, Color3.fromRGB(70, 80, 210), 1)
        local scale = Instance.new("UIScale")
        local cam = Workspace.CurrentCamera
        local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
        local baseScale = math.clamp(math.min(vp.X / 800, vp.Y / 470), 0.5, 1)
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

        local body = box(win, 0, 0, 720, 390, C.bg); body.BackgroundTransparency = 1

        -- left panel: key input, validate button, status card
        local left = box(body, 16, 91, 480, 281, C.panel); corner(left, 12); outline(left)
        local input = Instance.new("TextBox")
        input.Position = UDim2.new(0, 16, 0, 20); input.Size = UDim2.new(0, 448, 0, 44)
        input.BackgroundColor3 = C.field; input.BorderSizePixel = 0; input.ClearTextOnFocus = false
        input.PlaceholderText = "Enter your key..."; input.PlaceholderColor3 = C.muted; input.Text = ""
        input.TextColor3 = C.text; input.Font = Enum.Font.Gotham; input.TextSize = 15
        input.TextXAlignment = Enum.TextXAlignment.Left; input.Parent = left
        corner(input, 10); outline(input)
        local inPad = Instance.new("UIPadding"); inPad.PaddingLeft = UDim.new(0, 48); inPad.PaddingRight = UDim.new(0, 12); inPad.Parent = input
        label(input, "🔑", 16, C.purple, Enum.Font.GothamBold, -34, 0, 24, 44)

        -- the gradient lives on a separate background frame behind the button, not on the button itself -
        -- a UIGradient parented directly to a TextButton also recolors its Text, which made "VALIDATE KEY" invisible
        local validateBg = Instance.new("Frame")
        validateBg.Position = UDim2.new(0, 16, 0, 80); validateBg.Size = UDim2.new(0, 448, 0, 42)
        validateBg.BackgroundColor3 = Color3.fromRGB(255, 255, 255); validateBg.BorderSizePixel = 0
        validateBg.ZIndex = 1; validateBg.Parent = left
        corner(validateBg, 10)
        local vGrad = Instance.new("UIGradient"); vGrad.Color = ColorSequence.new(C.purple, C.blue); vGrad.Parent = validateBg

        local validate = Instance.new("TextButton")
        validate.Position = UDim2.new(0, 16, 0, 80); validate.Size = UDim2.new(0, 448, 0, 42)
        validate.BackgroundTransparency = 1; validate.BorderSizePixel = 0
        validate.Text = "VALIDATE KEY"; validate.TextColor3 = Color3.fromRGB(255, 255, 255)
        validate.Font = Enum.Font.GothamBold; validate.TextSize = 16; validate.AutoButtonColor = true; validate.Parent = left
        validate.ZIndex = 2

        local function makeGetKeyBtn(x, text)
            local btn = Instance.new("TextButton")
            btn.Position = UDim2.new(0, x, 0, 132); btn.Size = UDim2.new(0, 216, 0, 42)
            btn.BackgroundColor3 = C.field; btn.BorderSizePixel = 0
            btn.Text = "🔗  " .. text; btn.TextColor3 = C.text; btn.TextXAlignment = Enum.TextXAlignment.Left
            btn.Font = Enum.Font.GothamSemibold; btn.TextSize = 14; btn.AutoButtonColor = true; btn.Parent = left
            corner(btn, 10); outline(btn, Color3.fromRGB(60, 70, 190))
            local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0, 12); pad.Parent = btn
            return btn
        end

        local getKeyLVBtn = makeGetKeyBtn(16, "Get Key (Linkvertise)")
        local getKeyLLBtn = makeGetKeyBtn(248, "Get Key (LootLab)")

        local card = box(left, 16, 186, 448, 72, C.field); corner(card, 10); outline(card)
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
        local right = box(body, 507, 91, 197, 281, C.panel); corner(right, 12); outline(right)
        local discordIconBox = Instance.new("Frame")
        discordIconBox.Position = UDim2.new(0, 16, 0, 16); discordIconBox.Size = UDim2.new(0, 34, 0, 34)
        discordIconBox.BackgroundTransparency = 1; discordIconBox.Parent = right
        createDiscordMark(discordIconBox)
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
                    local finalKey = input.Text:match("^%s*(.-)%s*$")
                    pcall(function()
                        if writefile then writefile(KEY.File, finalKey) end
                    end)
                    NCL_KeyExpiresAt = fetchKeyExpiry(finalKey)
                    local expiryText = (NCL_KeyExpiresAt == nil and "Loading menu...")
                        or (NCL_KeyExpiresAt == 0 and "Lifetime key - loading menu...")
                        or ("Expires " .. os.date("%Y-%m-%d", NCL_KeyExpiresAt) .. " - loading menu...")
                    setState("ok", "Key valid!", expiryText)
                    task.wait(0.9)
                    closed = true
                    spinConn:Disconnect()
                    gui:Destroy()
                    UI.keyGui = nil
                    script_key = finalKey
                    keyAccepted = true
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

        local function openGetKeyUrl(url, missingMsg)
            url = tostring(url or ""):match("^%s*(.-)%s*$")
            if url == "" then
                setState("bad", "No Get Key link set", missingMsg)
                return
            end

            -- try to open the link directly through whatever the executor exposes
            local opened = false
            pcall(function()
                local opener = openurl or (universal and universal.openurl)
                if type(opener) == "function" then
                    opener(url)
                    opened = true
                end
            end)

            if opened then
                setState("ok", "Opened in browser", "Grab your key from the page that just opened.")
            else
                setClipboard(url)
                setState("ok", "Link copied! Paste it in your browser.", url)
            end
        end

        getKeyLVBtn.MouseButton1Click:Connect(function()
            openGetKeyUrl(KEY.GetKeyUrlLinkvertise, "Ask the script owner to fill in KEY.GetKeyUrlLinkvertise.")
        end)
        getKeyLLBtn.MouseButton1Click:Connect(function()
            openGetKeyUrl(KEY.GetKeyUrlLootLab, "Ask the script owner to fill in KEY.GetKeyUrlLootLab.")
        end)

        local minimized, maximized = false, false
        minBtn.MouseButton1Click:Connect(function()
            minimized = not minimized
            body.Visible = not minimized
            win.Size = UDim2.new(0, 720, 0, minimized and 90 or 390)
        end)
        maxBtn.MouseButton1Click:Connect(function()
            maximized = not maximized
            scale.Scale = maximized and math.min(baseScale * 1.25, 1.4) or baseScale
        end)
        closeBtn.MouseButton1Click:Connect(function() closed = true; cleanup() end)
    end

    -- Runs the key UI and blocks until a key is accepted, then sets the global script_key so Luarmor's
    -- own runtime can pick it up. When run raw (e.g. testing in an executor) LRM_INIT_SCRIPT does not
    -- exist, so it falls back to the normal showKeySystem() defined above, which can freely reference
    -- everything else in this file since the whole script just runs top-to-bottom as usual.
    --
    -- IMPORTANT: once obfuscated/protected through Luarmor, LRM_INIT_SCRIPT's function is extracted by
    -- Luarmor and executed completely on its own, BEFORE the rest of this script exists - it shares no
    -- scope with anything declared elsewhere in the file. Calling showKeySystem() from in there fails with
    -- "attempt to call a nil value" because that function hasn't been defined yet from Luarmor's point of
    -- view. So this branch is a fully self-contained duplicate: its own services, its own Luarmor check_key
    -- call, its own copy of the UI - nothing here reaches outside this function.
    if LRM_INIT_SCRIPT then
        LRM_INIT_SCRIPT(function()
            local Players = game:GetService("Players")
            local player = Players.LocalPlayer or Players.PlayerAdded:Wait()
            local CoreGui = game:GetService("CoreGui")
            local Workspace = game:GetService("Workspace")
            local RunService = game:GetService("RunService")
            local setClipboard = setclipboard or toclipboard or function() end

            local SCRIPT_ID = "bf8b052cd5bb75acc78f35c970e99c86" -- same Luarmor project ID as KEY.ScriptId above
            local DISCORD_INVITE = "https://discord.gg/sGJ3brqcJu"
            local KEY_FOLDER = "dungeonmacros"
            local KEY_FILE = KEY_FOLDER .. "/key.txt"
            local GET_KEY_URL_LINKVERTISE = "https://ads.luarmor.net/get_key?for=NCL_HUB-UmSUNONLKyZI"
            local GET_KEY_URL_LOOTLAB = "" -- TODO: isi link Get Key LootLab kamu di sini

            local function createBrandMark(parent, letter, colorA, colorB, bg, sizeFraction)
                local box = Instance.new("Frame")
                box.Size = UDim2.new(1, 0, 1, 0)
                box.BackgroundColor3 = bg or Color3.fromRGB(10, 14, 26)
                box.BorderSizePixel = 0
                box.Parent = parent
                local boxCorner = Instance.new("UICorner")
                boxCorner.CornerRadius = UDim.new(0.26, 0)
                boxCorner.Parent = box
                local mark = Instance.new("TextLabel")
                mark.Size = UDim2.new(1, 0, 1, 0)
                mark.BackgroundTransparency = 1
                mark.Text = letter
                mark.Font = Enum.Font.GothamBlack
                mark.TextSize = 16
                mark.ZIndex = box.ZIndex + 1
                mark.TextColor3 = Color3.fromRGB(255, 255, 255)
                mark.Parent = box
                local function fitText()
                    local h = box.AbsoluteSize.Y
                    if h > 0 then mark.TextSize = math.clamp(math.floor(h * (sizeFraction or 0.5)), 6, 60) end
                end
                box:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitText)
                fitText()
                local gradient = Instance.new("UIGradient")
                gradient.Color = ColorSequence.new(colorA, colorB)
                gradient.Rotation = 45
                gradient.Parent = mark
                return box
            end

            local DISCORD_LOGO_B64 = "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"
            local discordLogoBytes
            local function getDiscordLogoBytes()
                if discordLogoBytes then return discordLogoBytes end
                local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
                local lookup = {}
                for i = 1, #chars do lookup[chars:sub(i, i)] = i - 1 end
                local out, bits, nbits = {}, 0, 0
                for i = 1, #DISCORD_LOGO_B64 do
                    local v = lookup[DISCORD_LOGO_B64:sub(i, i)]
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
                discordLogoBytes = table.concat(out)
                return discordLogoBytes
            end
            local function createDiscordMark(parent, zIndex)
                -- draw the gradient "D" mark first so something always shows, then try to overlay the
                -- real logo image on top - if getcustomasset fails or returns a broken asset id, the
                -- "D" mark underneath still renders instead of leaving the icon blank
                local base = createBrandMark(parent, "D", Color3.fromRGB(88, 101, 242), Color3.fromRGB(114, 137, 218), Color3.fromRGB(10, 12, 22))
                base.ZIndex = zIndex or 1
                pcall(function()
                    if writefile and getcustomasset then
                        local path = KEY_FOLDER .. "/discordlogo.png"
                        if not (isfile and isfile(path)) then writefile(path, getDiscordLogoBytes()) end
                        local asset = getcustomasset(path)
                        if asset and tostring(asset) ~= "" then
                            local img = Instance.new("ImageLabel")
                            img.Size = UDim2.new(1, 0, 1, 0)
                            img.BackgroundTransparency = 1
                            img.Image = asset
                            img.ScaleType = Enum.ScaleType.Fit
                            img.ZIndex = base.ZIndex + 2
                            img.Parent = parent
                        end
                    end
                end)
                return base
            end

            pcall(function() if isfolder and makefolder and not isfolder(KEY_FOLDER) then makefolder(KEY_FOLDER) end end)

            local luarmorApi
            local function getLuarmorApi()
                if luarmorApi then return luarmorApi end
                local ok, result = pcall(function()
                    local sdk = loadstring(game:HttpGet("https://sdkapi-public.luarmor.net/library.lua"))()
                    sdk.script_id = SCRIPT_ID
                    return sdk
                end)
                if ok then luarmorApi = result end
                return luarmorApi
            end

            local function keyIsValid(input)
                input = tostring(input or ""):match("^%s*(.-)%s*$")
                if input == "" then return false, "Enter a key first" end
                local api = getLuarmorApi()
                if not api then return false, "Could not reach the key server" end
                local ok, status = pcall(api.check_key, input)
                if not ok or type(status) ~= "table" then return false, "Could not reach the key server" end
                if status.code == "KEY_VALID" then
                    return true
                elseif status.code == "KEY_HWID_LOCKED" then
                    return false, "Key linked to a different device - reset it via our Discord"
                elseif status.code == "KEY_INCORRECT" then
                    return false, "Key is wrong or deleted"
                else
                    return false, tostring(status.message or status.code or "Invalid key")
                end
            end

            local function fetchKeyExpiry(key)
                local api = getLuarmorApi()
                if not api or not api.get_user_data then return nil end
                local ok, data = pcall(api.get_user_data, key)
                if not ok or type(data) ~= "table" then return nil end
                local d = data.data or data
                local expiry = d.auth_expire or d.authExpire or d.expires_at or d.expiresAt or d.expiry or d.key_expire or d.keyExpire
                if type(expiry) == "number" then return expiry end
                return nil
            end

            local keyAccepted = false

            local saved
            pcall(function() if isfile and isfile(KEY_FILE) then saved = readfile(KEY_FILE) end end)
            if saved and keyIsValid(saved) then
                script_key = saved
                NCL_KeyExpiresAt = fetchKeyExpiry(saved)
                keyAccepted = true
            end

            if not keyAccepted then
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
                local guiParent = player:WaitForChild("PlayerGui", 5)
                if gethui then pcall(function() guiParent = gethui() end) else pcall(function() local t = Instance.new("Folder"); t.Parent = CoreGui; t:Destroy(); guiParent = CoreGui end) end
                gui.Parent = guiParent

                local win = box(gui, 0, 0, 720, 390, C.bg)
                win.AnchorPoint = Vector2.new(0.5, 0.5); win.Position = UDim2.new(0.5, 0, 0.5, 0)
                win.Active = true; win.Draggable = true; win.ClipsDescendants = true
                corner(win, 14); outline(win, Color3.fromRGB(70, 80, 210), 1)
                local scale = Instance.new("UIScale")
                local cam = Workspace.CurrentCamera
                local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
                local baseScale = math.clamp(math.min(vp.X / 800, vp.Y / 470), 0.5, 1)
                scale.Scale = baseScale; scale.Parent = win

                -- header
                local header = box(win, 14, 11, 692, 66, C.panel); corner(header, 12); outline(header)
                label(header, "🔑", 30, C.purple, Enum.Font.GothamBold, 16, 0, 44, 66)
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

                local body = box(win, 0, 0, 720, 390, C.bg); body.BackgroundTransparency = 1

                -- left panel: key input, validate button, status card
                local left = box(body, 16, 91, 480, 281, C.panel); corner(left, 12); outline(left)
                local input = Instance.new("TextBox")
                input.Position = UDim2.new(0, 16, 0, 20); input.Size = UDim2.new(0, 448, 0, 44)
                input.BackgroundColor3 = C.field; input.BorderSizePixel = 0; input.ClearTextOnFocus = false
                input.PlaceholderText = "Enter your key..."; input.PlaceholderColor3 = C.muted; input.Text = ""
                input.TextColor3 = C.text; input.Font = Enum.Font.Gotham; input.TextSize = 15
                input.TextXAlignment = Enum.TextXAlignment.Left; input.Parent = left
                corner(input, 10); outline(input)
                local inPad = Instance.new("UIPadding"); inPad.PaddingLeft = UDim.new(0, 48); inPad.PaddingRight = UDim.new(0, 12); inPad.Parent = input
                label(input, "🔑", 16, C.purple, Enum.Font.GothamBold, -34, 0, 24, 44)

                -- the gradient lives on a separate background frame behind the button, not on the button itself -
                -- a UIGradient parented directly to a TextButton also recolors its Text, which made "VALIDATE KEY" invisible
                local validateBg = Instance.new("Frame")
                validateBg.Position = UDim2.new(0, 16, 0, 80); validateBg.Size = UDim2.new(0, 448, 0, 42)
                validateBg.BackgroundColor3 = Color3.fromRGB(255, 255, 255); validateBg.BorderSizePixel = 0
                validateBg.ZIndex = 1; validateBg.Parent = left
                corner(validateBg, 10)
                local vGrad = Instance.new("UIGradient"); vGrad.Color = ColorSequence.new(C.purple, C.blue); vGrad.Parent = validateBg

                local validate = Instance.new("TextButton")
                validate.Position = UDim2.new(0, 16, 0, 80); validate.Size = UDim2.new(0, 448, 0, 42)
                validate.BackgroundTransparency = 1; validate.BorderSizePixel = 0
                validate.Text = "VALIDATE KEY"; validate.TextColor3 = Color3.fromRGB(255, 255, 255)
                validate.Font = Enum.Font.GothamBold; validate.TextSize = 16; validate.AutoButtonColor = true; validate.Parent = left
                validate.ZIndex = 2

                local function makeGetKeyBtn(x, text)
                    local btn = Instance.new("TextButton")
                    btn.Position = UDim2.new(0, x, 0, 132); btn.Size = UDim2.new(0, 216, 0, 42)
                    btn.BackgroundColor3 = C.field; btn.BorderSizePixel = 0
                    btn.Text = "🔗  " .. text; btn.TextColor3 = C.text; btn.TextXAlignment = Enum.TextXAlignment.Left
                    btn.Font = Enum.Font.GothamSemibold; btn.TextSize = 14; btn.AutoButtonColor = true; btn.Parent = left
                    corner(btn, 10); outline(btn, Color3.fromRGB(60, 70, 190))
                    local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0, 12); pad.Parent = btn
                    return btn
                end

                local getKeyLVBtn = makeGetKeyBtn(16, "Get Key (Linkvertise)")
                local getKeyLLBtn = makeGetKeyBtn(248, "Get Key (LootLab)")

                local card = box(left, 16, 186, 448, 72, C.field); corner(card, 10); outline(card)
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
                local right = box(body, 507, 91, 197, 281, C.panel); corner(right, 12); outline(right)
                local discordIconBox = Instance.new("Frame")
                discordIconBox.Position = UDim2.new(0, 16, 0, 16); discordIconBox.Size = UDim2.new(0, 34, 0, 34)
                discordIconBox.BackgroundTransparency = 1; discordIconBox.Parent = right
                createDiscordMark(discordIconBox)
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
                            local finalKey = input.Text:match("^%s*(.-)%s*$")
                            pcall(function()
                                if writefile then writefile(KEY_FILE, finalKey) end
                            end)
                            NCL_KeyExpiresAt = fetchKeyExpiry(finalKey)
                            local expiryText = (NCL_KeyExpiresAt == nil and "Loading menu...")
                                or (NCL_KeyExpiresAt == 0 and "Lifetime key - loading menu...")
                                or ("Expires " .. os.date("%Y-%m-%d", NCL_KeyExpiresAt) .. " - loading menu...")
                            setState("ok", "Key valid!", expiryText)
                            task.wait(0.9)
                            closed = true
                            spinConn:Disconnect()
                            gui:Destroy()
                            script_key = finalKey
                            keyAccepted = true
                        else
                            setState("bad", err or "Invalid key", "Check your key and try again.")
                            busy = false
                        end
                    end)
                end
                validate.MouseButton1Click:Connect(submit)
                input.FocusLost:Connect(function(enter) if enter then submit() end end)

                discordBtn.MouseButton1Click:Connect(function()
                    setClipboard(DISCORD_INVITE)
                    discordBtn.Text = "Invite copied!"
                    task.delay(2, function() if discordBtn.Parent then discordBtn.Text = "Join Discord" end end)
                end)

                local function openGetKeyUrl(url, missingMsg)
                    url = tostring(url or ""):match("^%s*(.-)%s*$")
                    if url == "" then
                        setState("bad", "No Get Key link set", missingMsg)
                        return
                    end
                    local opened = false
                    pcall(function()
                        local opener = openurl or (universal and universal.openurl)
                        if type(opener) == "function" then
                            opener(url)
                            opened = true
                        end
                    end)
                    if opened then
                        setState("ok", "Opened in browser", "Grab your key from the page that just opened.")
                    else
                        setClipboard(url)
                        setState("ok", "Link copied! Paste it in your browser.", url)
                    end
                end

                getKeyLVBtn.MouseButton1Click:Connect(function()
                    openGetKeyUrl(GET_KEY_URL_LINKVERTISE, "Ask the script owner to fill in the Linkvertise Get Key link.")
                end)
                getKeyLLBtn.MouseButton1Click:Connect(function()
                    openGetKeyUrl(GET_KEY_URL_LOOTLAB, "Ask the script owner to fill in the LootLab Get Key link.")
                end)

                local minimized, maximized = false, false
                minBtn.MouseButton1Click:Connect(function()
                    minimized = not minimized
                    body.Visible = not minimized
                    win.Size = UDim2.new(0, 720, 0, minimized and 90 or 390)
                end)
                maxBtn.MouseButton1Click:Connect(function()
                    maximized = not maximized
                    scale.Scale = maximized and math.min(baseScale * 1.25, 1.4) or baseScale
                end)
                closeBtn.MouseButton1Click:Connect(function()
                    closed = true
                    spinConn:Disconnect()
                    gui:Destroy()
                    pcall(function() player:Kick("Key entry cancelled.") end)
                end)
            end

            while not keyAccepted do task.wait() end
        end)
    else
        showKeySystem()
        while not keyAccepted do task.wait() end
    end

    buildInterface()
    loadConfigAndAutoExecute()
    UI.startAutoTrade()
    UI.startAutoAccept()
    UI.startJoinAccept()
