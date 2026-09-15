--!strict

--[[
    TutorialService
    Tutoriel des nouveaux joueurs (retention des premieres minutes), etapes dans Shared/Tutorial.
    Serveur autoritaire : progression dans le profil (DataService, champ tutorial = { step, done }), publiee en
    attributs du joueur :
    - TutorialStep   : etape en cours (1 a Tutorial.FINAL_STEP), nil si fini ou passe ;
    - TutorialDone   : true quand le tutoriel est fini ou passe ;
    - TutorialTarget : Vector3 vise par la fleche 3D (jouet puis base), nil sinon.

    Le jeu n'est jamais bloque : chaque etape avance quand l'action est faite, meme dans le desordre (voler ou
    deposer un jouet avant la fin de l'approche saute les etapes, un achat fait plus tot valide l'etape boutique).
    Remote TutorialAction : "next" (etapes d'information) ou "skip" (passer le tutoriel).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Toys = require(Shared:WaitForChild("Toys"))
local Tutorial = require(Shared:WaitForChild("Tutorial"))

local BaseService = require(script.Parent:WaitForChild("BaseService"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local ShopService = require(script.Parent:WaitForChild("ShopService"))
local ToySpawnService = require(script.Parent:WaitForChild("ToySpawnService"))

local POLL_SECONDS = 0.5

local TutorialService = {}

type State = { step: number, done: boolean, bonusGiven: boolean?, purchased: boolean? }

local targetToy: { [Player]: Model } = {}
local stepToken: { [Player]: number } = {}

local function stateOf(player: Player): State?
    local profile = DataService:Get(player)
    if profile == nil then
        return nil
    end
    local tutorial = profile.tutorial
    if typeof(tutorial) ~= "table" or typeof(tutorial.step) ~= "number" then
        profile.tutorial = { step = 1, done = false }
    end
    return profile.tutorial
end

local function rootOf(player: Player): BasePart?
    local character = player.Character
    local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
    return if root and root:IsA("BasePart") then root else nil
end

local function finish(player: Player, state: State, rewarded: boolean): ()
    state.done = true
    targetToy[player] = nil
    player:SetAttribute("TutorialTarget", nil)
    player:SetAttribute("TutorialDone", true)
    if rewarded then
        -- Tutoriel rejoue depuis le menu Parametres (stats.tutorialReplays) : pas de seconde recompense.
        local profile = DataService:Get(player)
        if profile == nil or (profile.stats.tutorialReplays or 0) == 0 then
            BaseService:AddCash(player, Tutorial.REWARD_CASH)
            if
                ShopService:Owns(player, Tutorial.REWARD_ITEM) or not ShopService:Grant(player, Tutorial.REWARD_ITEM)
            then
                BaseService:AddCash(player, Tutorial.REWARD_ITEM_FALLBACK_CASH)
            end
        end
    else
        player:SetAttribute("TutorialStep", nil)
    end
    DataService:Save(player)
end

local setStep: (Player, number) -> ()

setStep = function(player: Player, step: number): ()
    local state = stateOf(player)
    if state == nil or state.done then
        return
    end
    step = math.clamp(step, 1, Tutorial.FINAL_STEP)
    if step < state.step then
        return
    end
    state.step = step
    stepToken[player] = (stepToken[player] or 0) + 1
    local token = stepToken[player]

    -- Etape boutique : deja achete plus tot -> etape suivante ; sinon petit coup de pouce en tetines, une fois.
    if step == 5 then
        if state.purchased then
            setStep(player, 6)
            return
        end
        if not state.bonusGiven then
            state.bonusGiven = true
            BaseService:AddCash(player, Tutorial.SHOP_BONUS)
        end
    end

    local def = Tutorial.STEPS[step]
    if def == nil or (def.target ~= "toy" and def.target ~= "base") then
        player:SetAttribute("TutorialTarget", nil)
    end
    player:SetAttribute("TutorialStep", step)

    if step == Tutorial.FINAL_STEP then
        -- recompense donnee tout de suite ; la bulle de fin reste jusqu'au clic du joueur
        finish(player, state, true)
        return
    end
    -- Etapes d'information : avancent seules si le joueur ne clique pas.
    if def and def.manual then
        task.delay(Tutorial.AUTO_NEXT_SECONDS, function()
            local current = stateOf(player)
            if player.Parent and current and not current.done and stepToken[player] == token then
                setStep(player, step + 1)
            end
        end)
    end
end

local function available(toy: Model): boolean
    local toyId = toy:GetAttribute("ToyId")
    local def = if typeof(toyId) == "string" then Toys.Get(toyId) else nil
    return toy:IsDescendantOf(workspace)
        and CollectionService:HasTag(toy, "Toy")
        and toy:GetAttribute("CarrierUserId") == nil
        and toy:GetAttribute("AspireParUserId") == nil
        and toy:GetAttribute("Temporaire") ~= true
        and def ~= nil
        and def.kitchenOnly ~= true
        and def.carriers == 1
end

-- Privilégie les points d'accueil de cette base ; sinon garde le choix historique parmi les jouets libres.
local function pickToy(player: Player): Model?
    local current: Model? = targetToy[player]
    local live = workspace:FindFirstChild("ToysLive")
    local base = BaseService:GetBase(player)
    local root = rootOf(player)
    local outside = if base then ToySpawnService:GetWelcomeOrigin(base) else nil
    local origin = outside or (if base then base.Position elseif root then root.Position else nil)
    if live == nil or origin == nil then
        return nil
    end
    local best: Model? = nil
    local bestScore = math.huge
    local welcome: Model? = nil
    local welcomeScore = math.huge
    for _, toy in live:GetChildren() do
        if not toy:IsA("Model") or not available(toy) then
            continue
        end
        local toyId = toy:GetAttribute("ToyId")
        local def = if typeof(toyId) == "string" then Toys.Get(toyId) else nil
        if def and def.carriers > 1 then
            continue
        end
        local score = (toy:GetPivot().Position - origin).Magnitude
        if base and ToySpawnService:GetWelcomeBase(toy) == base and score < welcomeScore then
            welcome, welcomeScore = toy, score
        end
        if def and def.rarity ~= "Common" then
            score += 150
        end
        if score < bestScore then
            best, bestScore = toy, score
        end
    end
    if welcome then
        best = welcome
    elseif current and available(current) then
        best = current
    end
    targetToy[player] = best :: any
    return best
end

local function poll(player: Player): ()
    local state = stateOf(player)
    if state == nil or state.done then
        return
    end
    if player:GetAttribute("CarriedToyId") ~= nil and state.step <= 2 then
        setStep(player, 3)
        return
    end
    if state.step <= 2 then
        local toy = pickToy(player)
        local root = rootOf(player)
        if toy then
            local position = toy:GetPivot().Position
            player:SetAttribute("TutorialTarget", position)
            if state.step == 1 and root and (root.Position - position).Magnitude <= Tutorial.NEAR_TOY then
                setStep(player, 2)
            end
        else
            player:SetAttribute("TutorialTarget", nil)
        end
    elseif state.step == 3 then
        local base = BaseService:GetBase(player)
        player:SetAttribute("TutorialTarget", if base then base.Position else nil)
    end
end

local function onPlayer(player: Player, restart: boolean?): ()
    local profile = DataService:WaitForProfile(player)
    if profile == nil or player.Parent == nil then
        return
    end
    local state = stateOf(player)
    if state == nil then
        return
    end
    if state.done then
        player:SetAttribute("TutorialDone", true)
        return
    end
    -- Joueur qui a deja des jouets (ancien profil) : on commence apres le premier depot.
    local start = state.step
    if start < 4 and #profile.toys > 0 and not restart then
        start = 4
    end
    player:SetAttribute("TutorialDone", false)
    state.step = 0
    setStep(player, math.max(start, 1))
    task.spawn(function()
        while player.Parent do
            local current = stateOf(player)
            if current == nil or current.done then
                break
            end
            poll(player)
            task.wait(POLL_SECONDS)
        end
    end)
end

function TutorialService:Init(): () end

function TutorialService:Start(): ()
    BaseService.ToyDeposited:Connect(function(player: Player)
        local state = stateOf(player)
        if state and not state.done and state.step <= 3 then
            setStep(player, 4)
        end
    end)
    ShopService.Purchased:Connect(function(player: Player)
        local state = stateOf(player)
        if state == nil or state.done then
            return
        end
        if state.step == 5 then
            setStep(player, 6)
        elseif state.step < 5 then
            state.purchased = true
        end
    end)

    local remote = Remotes.Get("TutorialAction") :: RemoteEvent
    remote.OnServerEvent:Connect(function(player: Player, action: any)
        local state = stateOf(player)
        if state == nil then
            return
        end
        if action == "skip" and not state.done then
            finish(player, state, false)
        elseif action == "next" and not state.done then
            local def = Tutorial.STEPS[state.step]
            if def and def.manual then
                setStep(player, state.step + 1)
            end
        elseif action == "close" and state.done then
            player:SetAttribute("TutorialStep", nil)
        elseif action == "restart" and state.done then
            -- Rejouer le tutoriel (menu Parametres) : repart de la premiere etape, sans nouvelle recompense ni
            -- nouveau coup de pouce en tetines (bonusGiven garde).
            DataService:AddStat(player, "tutorialReplays", 1)
            state.done = false
            state.step = 1
            state.purchased = nil
            state.bonusGiven = true
            task.spawn(onPlayer, player, true)
        end
    end)

    Players.PlayerAdded:Connect(onPlayer)
    for _, player in Players:GetPlayers() do
        task.spawn(onPlayer, player)
    end
    Players.PlayerRemoving:Connect(function(player: Player)
        targetToy[player] = nil
        stepToken[player] = nil
    end)
end

return TutorialService
