--!strict

--[[
    TentService
    Le tipi achete (decor DecorTent, pose par CosmeticService dans workspace.BaseChests.Base_<UserId>.Decors) est un
    petit rangement (demande utilisateur du 15/09) : 3 jouets au plus, seulement des jouets legers (1 porteur).

    - Depot : le joueur entre dans le tipi ou se tient juste devant (boite du tipi elargie de REACH studs) avec un
      jouet leger dans les mains : CarryService (SetDepositHook) le lui laisse avant le depot en coffre, donc jamais
      les deux. Le jouet du sac a dos passe ensuite dans les mains et peut suivre s'il reste de la place.
    - Jouet lourd ou tipi plein : message court au joueur (attribut TipiMessage, TentController), au plus toutes les
      MESSAGE_SECONDS.
    - Les jouets du tipi sont sauvegardes (profil tentToys), affiches a l'interieur sur 3 emplacements, rapportent
      leur revenu comme en coffre (BaseService:AddIncomeSource) et comptent comme voles (quetes, collection, XP).
    - Nuit (renaissance) : le tipi est vide, comme les coffres.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Toys = require(Shared:WaitForChild("Toys"))

local BaseService = require(script.Parent:WaitForChild("BaseService"))
local CarryService = require(script.Parent:WaitForChild("CarryService"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local ToySpawnService = require(script.Parent:WaitForChild("ToySpawnService"))

local CAPACITY = 3
local REACH = 6
local MESSAGE_SECONDS = 4
local DISPLAY_FOLDER = "JouetsTipi"
local CHECK_SECONDS = 0.25

local TentService = {}

local lastMessage: { [Player]: number } = {}
local lastNights: { [Player]: number } = {}

local function tentOf(player: Player): Model?
    local root = workspace:FindFirstChild("BaseChests")
    local base = if root then root:FindFirstChild("Base_" .. player.UserId) else nil
    local decors = if base then base:FindFirstChild("Decors") else nil
    local tent = if decors then decors:FindFirstChild("DecorTent") else nil
    return if tent and tent:IsA("Model") then tent else nil
end

local function message(player: Player, text: string): ()
    local now = os.clock()
    local last: number? = lastMessage[player]
    if last and now - last < MESSAGE_SECONDS then
        return
    end
    lastMessage[player] = now
    -- compteur en tete : deux messages identiques de suite declenchent quand meme le changement d'attribut
    player:SetAttribute("TipiMessage", string.format("%d|%s", math.floor(now * 1000), text))
end

-- Pose les jouets du profil a l'interieur du tipi, sur 3 emplacements alignes face a son ouverture.
local function refreshDisplay(player: Player, tent: Model): ()
    local profile = DataService:Get(player)
    if profile == nil then
        return
    end
    local folder = tent:FindFirstChild(DISPLAY_FOLDER)
    if folder and #folder:GetChildren() == #profile.tentToys then
        return
    end
    if folder then
        folder:Destroy()
    end
    local holder = Instance.new("Folder")
    holder.Name = DISPLAY_FOLDER
    holder.Parent = tent
    local box, size = tent:GetBoundingBox()
    local width = math.min(size.X, size.Z)
    local toySize = width * 0.24
    local floorY = box.Position.Y - size.Y / 2
    local right = Vector3.new(box.RightVector.X, 0, box.RightVector.Z)
    right = if right.Magnitude > 0.01 then right.Unit else Vector3.new(1, 0, 0)
    local look = Vector3.new(box.LookVector.X, 0, box.LookVector.Z)
    look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
    for index, entry in profile.tentToys do
        local model = ToySpawnService:CloneTemplate(entry.id)
        if model == nil then
            continue
        end
        if not model:IsA("Model") then
            model:Destroy()
            continue
        end
        model.Name = entry.id
        ToySpawnService:ApplyMutationLook(model, entry.mutation)
        local _, raw = model:GetBoundingBox()
        model:ScaleTo(model:GetScale() * (toySize / math.max(raw.X, raw.Y, raw.Z, 0.1)))
        local _, scaled = model:GetBoundingBox()
        local slot = box.Position + right * (index - 2) * width * 0.26 + look * width * 0.08
        local target = CFrame.lookAt(
            Vector3.new(slot.X, floorY + scaled.Y / 2 + 0.2, slot.Z),
            Vector3.new(slot.X, floorY + scaled.Y / 2 + 0.2, slot.Z) + look
        )
        local center = model:GetBoundingBox()
        model:PivotTo(target * center:ToObjectSpace(model:GetPivot()))
        for _, descendant in model:GetDescendants() do
            if descendant:IsA("BasePart") then
                descendant.Anchored = true
                descendant.CanCollide = false
                descendant.CanQuery = false
                descendant.CanTouch = false
            end
        end
        model.Parent = holder
    end
end

-- Le joueur se tient-il dans le tipi ou juste devant ?
local function nearTent(tent: Model, position: Vector3): boolean
    local box, size = tent:GetBoundingBox()
    local localPos = box:PointToObjectSpace(position)
    return math.abs(localPos.X) <= size.X / 2 + REACH
        and math.abs(localPos.Z) <= size.Z / 2 + REACH
        and localPos.Y >= -size.Y / 2 - 4
        and localPos.Y <= size.Y / 2 + 4
end

-- Crochet de depot de CarryService : vrai si le tipi prend le jouet des mains.
local function tryStore(player: Player, toy: Instance, position: Vector3): boolean
    local tent = tentOf(player)
    local profile = DataService:Get(player)
    if tent == nil or profile == nil or not nearTent(tent, position) then
        return false
    end
    local toyId = toy:GetAttribute("ToyId")
    local def = if typeof(toyId) == "string" then Toys.Get(toyId) else nil
    if def == nil then
        return false
    end
    if def.carriers > 1 then
        message(player, "Trop gros pour le tipi !")
        return false
    end
    if #profile.tentToys >= CAPACITY then
        message(player, "Le tipi est plein (3 jouets)")
        return false
    end
    local mutationId = toy:GetAttribute("Mutation")
    local mutation = if typeof(mutationId) == "string" and Toys.GetMutation(mutationId) then mutationId else nil
    table.insert(profile.tentToys, { id = def.id, mutation = mutation })
    refreshDisplay(player, tent)
    BaseService:RefreshIncome(player)
    local source = if toy:GetAttribute("StolenFromUserId") ~= nil then "stolen" else "room"
    BaseService:NotifyDeposited(player, def.id, mutation, source)
    message(player, string.format("Rangé dans le tipi (%d/%d)", #profile.tentToys, CAPACITY))
    return true
end

local function tentIncome(player: Player): number
    local profile = DataService:Get(player)
    if profile == nil then
        return 0
    end
    local total = 0
    for _, entry in profile.tentToys do
        total += Toys.Income(entry.id, entry.mutation)
    end
    return total
end

function TentService:Init(): () end

function TentService:Start(): ()
    BaseService:AddIncomeSource(tentIncome)
    CarryService:SetDepositHook(tryStore)

    Players.PlayerRemoving:Connect(function(player: Player)
        lastMessage[player] = nil
        lastNights[player] = nil
    end)

    task.spawn(function()
        while true do
            task.wait(CHECK_SECONDS)
            for _, player in Players:GetPlayers() do
                local profile = DataService:Get(player)
                if profile == nil then
                    continue
                end
                -- Nuit : le tipi est vide comme les coffres
                local previous: number? = lastNights[player]
                if previous ~= nil and profile.nights > previous and #profile.tentToys > 0 then
                    table.clear(profile.tentToys)
                    BaseService:RefreshIncome(player)
                end
                lastNights[player] = profile.nights
                local tent = tentOf(player)
                if tent then
                    refreshDisplay(player, tent)
                end
            end
        end
    end)
end

return TentService
