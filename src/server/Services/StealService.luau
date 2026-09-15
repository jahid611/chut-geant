--!strict

--[[
    StealService
    Vol entre joueurs : dans la base d'un autre joueur, un ProximityPrompt « Voler » (maintenir HOLD_SECONDS) sur
    chacun de ses coffres fait prendre UN jouet de ce coffre (tirage pondere vers les communs, BaseService). Le voleur
    le porte comme un jouet de la chambre (CarryService:CarryStolen) et le depose dans SA base pour le garder.

    - Refus : victime avec moins de MIN_VICTIM_TOYS jouets, base verrouillee (BaseLockService), victime arrivee il y a
      moins de VICTIM_GRACE secondes, voleur qui a vole il y a moins de THIEF_COOLDOWN secondes, mains pleines.
    - Jouet lache sans etre depose (pose, lance, attrape, touche par une arme, deconnexion) : il retourne a la victime
      (crochet CarryService:SetStolenReturnHook) ; coffres pleins, elle recoit sa valeur en tetines.
    - Alarme : la victime recoit StealNotice "robbed" (bandeau, son, fleche vers son coffre) ; le voleur est surligne
      en rouge pour tous, avec « VOLEUR » au-dessus de la tete, tant qu'il porte le jouet vole.
    - Reussite : stats stolenFromPlayers (voleur) et robbed (victime), XP de vol via PassService.
    Tests sans deuxieme joueur : StealService:TestSteal(player, chestIndex) (vol dans sa propre base).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Toys = require(Shared:WaitForChild("Toys"))

local BaseLockService = require(script.Parent:WaitForChild("BaseLockService"))
local BaseService = require(script.Parent:WaitForChild("BaseService"))
local CarryService = require(script.Parent:WaitForChild("CarryService"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local PassService = require(script.Parent:WaitForChild("PassService"))
local ToySpawnService = require(script.Parent:WaitForChild("ToySpawnService"))

local PROMPT_NAME = "PromptVol"
local ANCHOR_NAME = "PointVol"
local HOLD_SECONDS = 1.5
local THIEF_COOLDOWN = 20
local VICTIM_GRACE = 60
local MIN_VICTIM_TOYS = 2
local STEAL_XP = 30
-- Coffres pleins au retour : la victime recoit ce nombre de secondes de revenu du jouet.
local REFUND_SECONDS = 120
local HIGHLIGHT_NAME = "SurlignageVoleur"
local TAG_NAME = "NomVoleur"

type OwnedToy = { id: string, mutation: string? }
type Steal = { thief: Player, victimUserId: number, toy: OwnedToy, returned: boolean }

local StealService = {}

local joinedAt: { [Player]: number } = {}
local lastSteal: { [Player]: number } = {}
local active: { [Instance]: Steal } = {}
-- Mode test : on peut voler dans sa propre base, sans delai d'arrivee.
local testMode = false

local function notify(player: Player, kind: string, a: any?, b: any?): ()
    local remote = Remotes.Get("StealNotice") :: RemoteEvent
    remote:FireClient(player, kind, a, b)
end

local function stealsBy(thief: Player): number
    local count = 0
    for _, steal in active do
        if steal.thief == thief then
            count += 1
        end
    end
    return count
end

-- Surlignage rouge et « VOLEUR » au-dessus de la tete, visibles par tous.
local function setThiefMark(thief: Player, on: boolean): ()
    local character = thief.Character
    if character == nil then
        return
    end
    local highlight = character:FindFirstChild(HIGHLIGHT_NAME)
    local tag = character:FindFirstChild(TAG_NAME)
    if not on then
        if highlight then
            highlight:Destroy()
        end
        if tag then
            tag:Destroy()
        end
        return
    end
    if highlight == nil then
        local h = Instance.new("Highlight")
        h.Name = HIGHLIGHT_NAME
        h.FillColor = Color3.fromRGB(245, 60, 70)
        h.FillTransparency = 0.65
        h.OutlineColor = Color3.fromRGB(255, 90, 90)
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        h.Parent = character
    end
    local head = character:FindFirstChild("Head")
    if tag == nil and head and head:IsA("BasePart") then
        local board = Instance.new("BillboardGui")
        board.Name = TAG_NAME
        board.Adornee = head
        board.Size = UDim2.fromOffset(220, 44)
        board.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
        board.AlwaysOnTop = true
        board.MaxDistance = 250
        board.LightInfluence = 0
        board.Parent = character
        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Size = UDim2.fromScale(1, 1)
        label.Font = Enum.Font.FredokaOne
        label.TextScaled = true
        label.TextColor3 = Color3.fromRGB(255, 90, 90)
        label.TextStrokeColor3 = Color3.fromRGB(40, 10, 20)
        label.TextStrokeTransparency = 0
        label.Text = "VOLEUR : " .. thief.DisplayName
        label.Parent = board
    end
end

local function refundValue(toy: OwnedToy): number
    local def = Toys.Get(toy.id)
    return if def then Toys.Income(toy.id, toy.mutation) * REFUND_SECONDS else 0
end

-- Jouet vole lache sans etre depose : il retourne a sa victime.
local function giveBack(toy: Instance): ()
    local steal: Steal? = active[toy]
    if steal == nil then
        return
    end
    steal.returned = true
    local victim = Players:GetPlayerByUserId(steal.victimUserId)
    if victim then
        if BaseService:GiveBackToy(victim, steal.toy) then
            if victim ~= steal.thief then
                notify(victim, "returned")
            end
        else
            BaseService:AddCash(victim, refundValue(steal.toy))
            notify(victim, "notice", "Coffres pleins : ton jouet t'est rendu en tétines.")
        end
    end
    if steal.thief.Parent then
        notify(steal.thief, "dropped")
    end
end

local function refuse(thief: Player, message: string): ()
    notify(thief, "refused", message)
end

local function trySteal(thief: Player, chest: Model): ()
    local ownerId = chest:GetAttribute("OwnerUserId")
    local chestIndex = chest:GetAttribute("Index")
    if typeof(ownerId) ~= "number" or typeof(chestIndex) ~= "number" then
        return
    end
    local victim = Players:GetPlayerByUserId(ownerId)
    if victim == nil then
        refuse(thief, "Cette base est vide.")
        return
    end
    local selfTest = testMode and victim == thief
    if victim == thief and not selfTest then
        return
    end
    local now = os.clock()
    local last: number? = lastSteal[thief]
    if last and now - last < THIEF_COOLDOWN then
        refuse(thief, string.format("Attends %d s avant de voler encore.", math.ceil(THIEF_COOLDOWN - (now - last))))
        return
    end
    if not selfTest and now - (joinedAt[victim] or now) < VICTIM_GRACE then
        refuse(thief, "Ce joueur vient d'arriver : laisse-lui une minute.")
        return
    end
    if BaseLockService:IsLocked(victim) then
        refuse(thief, "Base verrouillée !")
        return
    end
    if BaseService:GetToyCount(victim) < MIN_VICTIM_TOYS then
        refuse(thief, "Presque rien à voler ici.")
        return
    end
    if CarryService:GetCarried(thief) ~= nil then
        refuse(thief, "Tes mains sont pleines.")
        return
    end
    local count = chest:GetAttribute("Count")
    if typeof(count) ~= "number" or count <= 0 then
        refuse(thief, "Ce coffre est vide.")
        return
    end
    local character = thief.Character
    local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
    if root == nil or not root:IsA("BasePart") then
        return
    end

    local taken = BaseService:TakeToyFromChest(victim, chestIndex)
    if taken == nil then
        return
    end
    local model = ToySpawnService:CloneTemplate(taken.id)
    if model == nil or not model:IsA("Model") then
        if model then
            model:Destroy()
        end
        BaseService:GiveBackToy(victim, taken)
        return
    end
    model.Name = taken.id
    model:SetAttribute("ToyId", taken.id)
    model:SetAttribute("Mutation", taken.mutation)
    model:SetAttribute("StolenFromUserId", victim.UserId)
    ToySpawnService:ApplyMutationLook(model, taken.mutation)
    model:PivotTo(root.CFrame * CFrame.new(0, 4, -3))
    for _, descendant in model:GetDescendants() do
        if descendant:IsA("BasePart") then
            descendant.Anchored = true
        end
    end
    model.Parent = workspace:FindFirstChild("ToysLive") or workspace
    CollectionService:AddTag(model, "Toy")

    local steal: Steal = { thief = thief, victimUserId = victim.UserId, toy = taken, returned = false }
    active[model] = steal
    if not CarryService:CarryStolen(thief, model) then
        active[model] = nil
        BaseService:GiveBackToy(victim, taken)
        model:Destroy()
        return
    end
    lastSteal[thief] = now
    setThiefMark(thief, true)

    -- Le jouet disparait quand il est depose (base ou tipi : vol reussi) ou rendu (giveBack).
    model.AncestryChanged:Connect(function()
        if model.Parent ~= nil then
            return
        end
        local finished: Steal? = active[model]
        active[model] = nil
        if finished == nil then
            return
        end
        if stealsBy(thief) == 0 then
            setThiefMark(thief, false)
        end
        if finished.returned or thief.Parent == nil then
            return
        end
        DataService:AddStat(thief, "stolenFromPlayers", 1)
        PassService:AddXp(thief, STEAL_XP, "vol")
        notify(thief, "success", STEAL_XP)
        local robbed = Players:GetPlayerByUserId(finished.victimUserId)
        if robbed and robbed ~= thief then
            notify(robbed, "lost", thief.DisplayName)
        end
    end)

    notify(thief, "stealing", victim.DisplayName)
    if victim ~= thief then
        notify(victim, "robbed", thief.DisplayName, chest:GetPivot().Position)
    end
end

-- Bouton « Voler » sur un coffre (modele Coffre<n> d'un dossier Base_<UserId>).
local function setupChest(instance: Instance): ()
    if not instance:IsA("Model") or string.match(instance.Name, "^Coffre%d+$") == nil then
        return
    end
    if instance:FindFirstChild(ANCHOR_NAME) then
        return
    end
    local chest = instance
    local cavity = chest:GetAttribute("CavityCFrame")
    local size = chest:GetAttribute("Size")
    local anchor = Instance.new("Part")
    anchor.Name = ANCHOR_NAME
    anchor.Size = Vector3.new(1, 1, 1)
    anchor.Transparency = 1
    anchor.Anchored = true
    anchor.CanCollide = false
    anchor.CanQuery = false
    anchor.CanTouch = false
    anchor.CFrame = if typeof(cavity) == "CFrame" then cavity else chest:GetPivot()
    anchor.Parent = chest
    local owner = Players:GetPlayerByUserId(tonumber(chest:GetAttribute("OwnerUserId")) or 0)
    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = PROMPT_NAME
    prompt.ActionText = "Voler"
    prompt.ObjectText = if owner then "Coffre de " .. owner.DisplayName else "Coffre"
    prompt.HoldDuration = HOLD_SECONDS
    prompt.MaxActivationDistance = if typeof(size) == "number" then math.max(12, size * 0.55) else 12
    prompt.RequiresLineOfSight = false
    prompt.Parent = anchor
    prompt.Triggered:Connect(function(player: Player)
        trySteal(player, chest)
    end)
end

--[[
    Tests en jeu sans deuxieme joueur : active le mode test (voler dans sa propre base, sans delai d'arrivee ni
    recharge) et simule le bouton « Voler » sur son coffre n° chestIndex. Rend un court compte rendu.
]]
function StealService:TestSteal(player: Player, chestIndex: number?): string
    testMode = true
    lastSteal[player] = nil
    local root = workspace:FindFirstChild("BaseChests")
    local folder = if root then root:FindFirstChild("Base_" .. player.UserId) else nil
    local chest = if folder then folder:FindFirstChild("Coffre" .. (chestIndex or 1)) else nil
    if chest == nil or not chest:IsA("Model") then
        return "pas de coffre"
    end
    local before = BaseService:GetToyCount(player)
    trySteal(player, chest)
    return string.format(
        "jouets avant %d, apres %d, porte %s",
        before,
        BaseService:GetToyCount(player),
        tostring(player:GetAttribute("CarriedToyId"))
    )
end

function StealService:Init(): () end

function StealService:Start(): ()
    CarryService:SetStolenReturnHook(giveBack)

    local now = os.clock()
    for _, player in Players:GetPlayers() do
        joinedAt[player] = now
    end
    Players.PlayerAdded:Connect(function(player: Player)
        joinedAt[player] = os.clock()
    end)
    Players.PlayerRemoving:Connect(function(player: Player)
        joinedAt[player] = nil
        lastSteal[player] = nil
    end)

    -- BaseChests est cree par BaseService:Start, qui peut demarrer apres ce service : on attend sans bloquer Main.
    task.spawn(function()
        local root = workspace:WaitForChild("BaseChests")
        for _, descendant in root:GetDescendants() do
            setupChest(descendant)
        end
        root.DescendantAdded:Connect(setupChest)
    end)
end

return StealService
