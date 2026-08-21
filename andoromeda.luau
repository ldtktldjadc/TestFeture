-- [[ Rscripts Risk Notice ]]
-- This script is not verified by rscripts.net. Deal with caution.
--
-- Stay safe:
--   • Never log in on unofficial Roblox sites or lookalike domains.
--   • Real Roblox links use roblox.com (check the .com ending).
--   • Treat fake Roblox login / "claim reward" pages as phishing.
-- [[ End Rscripts Risk Notice ]]
-- credits: https://discord.gg/sgyTaUrQ3a
local repS = cloneref(game:GetService("ReplicatedStorage"))
local plrs = cloneref(game:GetService("Players"))
local runS = cloneref(game:GetService("RunService"))
local ws = cloneref(game:GetService("Workspace"))
local uis = cloneref(game:GetService("UserInputService"))
local lplr = plrs.LocalPlayer
local util = require(repS.Modules.Utility)
local enum = require(repS.Modules.EnumLibrary)
local FighterController = require(lplr.PlayerScripts.Controllers.FighterController)
local SpectateController = require(lplr.PlayerScripts.Controllers:WaitForChild("SpectateController"))

getgenv().Config = {
    Enabled = true,
    FireRate = 0.0005,
    WeaponSlot = "Primary" -- Options: "Primary", "Secondary", "Melee"
}

local slots = {
    Primary = 1,
    Secondary = 2,
    Melee = 3
}

local function getSlotNumber()
    return slots[getgenv().Config.WeaponSlot] or 3
end

task.spawn(function()
    local localFighter = FighterController.LocalFighter
    while not localFighter do
        task.wait(0.1)
        localFighter = FighterController.LocalFighter
    end
    pcall(function()
        localFighter:EquipItem(getSlotNumber())
    end)
end)

task.spawn(function()
    while true do
        task.wait(1)
        if not getgenv().Config.Enabled then continue end
        local localFighter = FighterController.LocalFighter
        if localFighter then
            pcall(function()
                localFighter:EquipItem(getSlotNumber())
            end)
        end
    end
end)

local lastFire = 0
local deflecting = {}
plrs.PlayerRemoving:Connect(function(player)
    deflecting[player] = nil
end)

local function updateDeflection()
    if not FighterController or not FighterController.Objects then return end
    for _, fighterObj in FighterController.Objects do
        local player = fighterObj.Player
        if not player then continue end
        if not fighterObj.Entity or not fighterObj.Entity:IsAlive() or fighterObj:Get("IsSpectating") then
            deflecting[player] = false
            continue
        end
        local equipped = fighterObj.EquippedItem
        local isKatana = equipped and equipped.ViewModel and equipped.ViewModel.Name == "Katana"
        local isDeflecting = false
        if isKatana then
            isDeflecting = (equipped._attack_cooldown and equipped._attack_cooldown > tick()) or false
        end
        deflecting[player] = isDeflecting
    end
end

local function isEnemy(player)
    if player == lplr then return false end
    local duel = SpectateController.CurrentDuelSubject
    local localDueler = duel and duel:GetDueler(lplr)
    local localTeam = localDueler and localDueler:Get("TeamID") or nil
    if localTeam and duel and duel.Duelers then
        for _, dueler in duel.Duelers do
            if dueler.Player == player then
                local team = dueler:Get("TeamID")
                return team ~= localTeam
            end
        end
    end
    local pTeam = player:GetAttribute("TeamID")
    local lTeam = lplr:GetAttribute("TeamID")
    if pTeam and lTeam then
        return pTeam ~= lTeam
    end
    return true
end

local function getClosestTarget()
    local char = lplr.Character
    if not char then return nil, nil, nil end
    local myRoot = char:FindFirstChild("HumanoidRootPart")
    if not myRoot then return nil, nil, nil end
    local closestPlayer = nil
    local closestRoot = nil
    local closestHead = nil
    local closestDist = 500
    for _, player in plrs:GetPlayers() do
        if not isEnemy(player) then continue end
        local pChar = player.Character
        if not pChar then continue end
        local pRoot = pChar:FindFirstChild("HumanoidRootPart")
        local pHead = pChar:FindFirstChild("Head")
        local pHum = pChar:FindFirstChildWhichIsA("Humanoid")
        if not (pRoot and pHead and pHum and pHum.Health > 0) then continue end
        local dist = (myRoot.Position - pRoot.Position).Magnitude
        if dist < closestDist then
            closestDist = dist
            closestPlayer = player
            closestRoot = pRoot
            closestHead = pHead
        end
    end
    return closestPlayer, closestRoot, closestHead
end

local function hasKnifeViewModel(targetPlayer)
    if not targetPlayer then return false end
    local viewModels = ws:FindFirstChild("ViewModels")
    if not viewModels then return false end
    local targetName = targetPlayer.Name
    for _, model in viewModels:GetChildren() do
        if model:IsA("Model") 
           and string.find(model.Name, targetName, 1, true) 
           and string.find(model.Name, "Knife", 1, true) then
            return true
        end
    end
    return false
end

runS.Heartbeat:Connect(function()
    updateDeflection()

    local myRoot = lplr.Character and lplr.Character:FindFirstChild("HumanoidRootPart")
    if not myRoot then return end

    -- 各種状態取得
    local item = nil
    local isReloading = false
    if FighterController and FighterController.LocalFighter then
        item = FighterController.LocalFighter.EquippedItem
        if item then
            pcall(function()
                isReloading = item:IsAnimationPlaying("Reload")
                    or item:IsAnimationPlaying("EmptyReload")
                    or (item:Get("Ammo") == 0)
                    or (tick() < (item._reload_cooldown or 0))
            end)
        end
    end

    local targetPlayer, targetRoot, targetHead = getClosestTarget()

    local myFF = false
    local targetFF = false
    if lplr.Character then
        myFF = lplr.Character:FindFirstChildOfClass("ForceField") ~= nil
    end
    if targetPlayer and targetPlayer.Character then
        targetFF = targetPlayer.Character:FindFirstChildOfClass("ForceField") ~= nil
    end

    -- AttackModeの条件を全て満たす場合のみAttack、それ以外はVoidSpam
    local canAttack = getgenv().Config.Enabled
        and (not isReloading)
        and (not myFF)
        and (not targetFF)
        and targetPlayer ~= nil
        and targetRoot ~= nil
        and targetHead ~= nil
        and (not deflecting[targetPlayer])
        and item ~= nil

    local desyncCF
    if canAttack then
        -- AttackMode: ターゲットの後ろにTP
        local desyncPos
        if hasKnifeViewModel(targetPlayer) then
            desyncPos = (targetRoot.CFrame * CFrame.new(0, 6, 0)).Position
        else
            desyncPos = (targetRoot.CFrame * CFrame.new(0, 1, 2)).Position
        end
        desyncCF = CFrame.lookAt(desyncPos, targetHead.Position)
    else
        -- VoidSpam: ランダムな超遠距離にTP
        local randomDir = Vector3.new(
            math.random(-100, 100),
            math.random(-100, 100),
            math.random(-100, 100)
        ).Unit
        local cam = ws.CurrentCamera
        local camPos = cam and cam.CFrame.Position or Vector3.new(0, 0, 0)
        desyncCF = CFrame.new(camPos + randomDir * 7000000000000)
    end

    -- TP適用 (Desync)
    local oldCF     = myRoot.CFrame
    local oldVel    = myRoot.Velocity
    local oldRotVel = myRoot.RotVelocity
    myRoot.CFrame = desyncCF
    runS:BindToRenderStep("__restore", 101, function()
        if myRoot then
            myRoot.CFrame    = oldCF
            myRoot.Velocity  = oldVel
            myRoot.RotVelocity = oldRotVel
        end
        runS:UnbindFromRenderStep("__restore")
    end)

    -- AttackModeのみ射撃
    if not canAttack then return end
    if tick() - lastFire < getgenv().Config.FireRate then return end
    lastFire = tick()

    local originPos = desyncCF.Position
    local targetPos = targetHead.Position
    local aimCF    = CFrame.lookAt(originPos, targetPos)
    local targetCF = targetHead.CFrame
    local randomOffset = Vector3.new(
        (math.random() - 0.5) * 0.1,
        (math.random() - 0.5) * 0.1,
        (math.random() - 0.5) * 0.1
    )
    local aimedPos = targetPos + randomOffset
    local objSpaceHeadOffset = targetHead.CFrame:ToObjectSpace(CFrame.new(aimedPos))
    local cameradata = {}
    cameradata[utf8.char(1)] = {
        [utf8.char(0)] = util:EncodeCFrame(aimCF),
        [utf8.char(1)] = util:EncodeCFrame(targetCF),
        [utf8.char(2)] = targetHead,
        [utf8.char(3)] = util:EncodeCFrame(objSpaceHeadOffset)
    }
    repS.Remotes.Replication.Fighter.UseItem:FireServer(
        item:Get("ObjectID"),
        enum:ToEnum("StartShooting"),
        cameradata,
        nil
    )
end)
