--!strict

--[[
    ToyCollectionService
    Collection des jouets et mutations deja voles (pas « CollectionService », nom deja pris par Roblox).

    - Un jouet (ou une mutation) est decouvert la premiere fois qu'il est depose dans un coffre
      (BaseService.ToyDeposited) : recompense en tetines (Progression.COLLECTION_*_REWARD).
    - Sets : tous les jouets d'une rarete = +5 % de revenu permanent ; les trois mutations = +10 %
      (BaseService:AddIncomeMultiplier).
    - Profil : profile.collection[toyId] = true, profile.collection["mutation:<id>"] = true.
    - Publie en attributs du joueur pour le menu Collection : CollectionToys et CollectionMutations (ids separes
      par des virgules), CollectionBonus (fraction), Notif_Collection (pastille) ; remote CollectionState a chaque
      decouverte : { items = { { name, rarity, reward } }, sets = { rarete complete... } } pour les annonces.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Progression = require(Shared:WaitForChild("Progression"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Toys = require(Shared:WaitForChild("Toys"))

local BaseService = require(script.Parent:WaitForChild("BaseService"))
local DataService = require(script.Parent:WaitForChild("DataService"))

local MUTATION_PREFIX = "mutation:"

type Discovery = { name: string, rarity: string, reward: number }

local ToyCollectionService = {}

-- (player: Player, rarity: string) premiere decouverte d'un jouet (sa rarete) ou d'une mutation ("Mutation").
local discovered = Instance.new("BindableEvent")
ToyCollectionService.Discovered = discovered.Event

-- Sets complets du joueur : raretes dont tous les jouets sont decouverts, plus « Mutations ».
function ToyCollectionService:GetCompletedSets(player: Player): { string }
    local done: { string } = {}
    local profile = DataService:Get(player)
    if profile == nil then
        return done
    end
    for _, rarity in Progression.RARITY_ORDER do
        local any, complete = false, true
        for _, toy in Toys.All() do
            if toy.rarity == rarity then
                any = true
                if not profile.collection[toy.id] then
                    complete = false
                end
            end
        end
        if any and complete then
            table.insert(done, rarity)
        end
    end
    local mutations = true
    for _, id in Progression.MUTATION_IDS do
        if not profile.collection[MUTATION_PREFIX .. id] then
            mutations = false
        end
    end
    if mutations then
        table.insert(done, "Mutations")
    end
    return done
end

-- Bonus de revenu de la collection (fraction : 0,15 = +15 %).
function ToyCollectionService:GetBonus(player: Player): number
    local bonus = 0
    for _, set in ToyCollectionService:GetCompletedSets(player) do
        bonus += if set == "Mutations"
            then Progression.COLLECTION_MUTATION_SET_BONUS
            else Progression.COLLECTION_SET_BONUS
    end
    return bonus
end

local function publish(player: Player): ()
    local profile = DataService:Get(player)
    if profile == nil then
        return
    end
    local toys: { string } = {}
    local mutations: { string } = {}
    for key, found in profile.collection do
        if found then
            if string.sub(key, 1, #MUTATION_PREFIX) == MUTATION_PREFIX then
                table.insert(mutations, string.sub(key, #MUTATION_PREFIX + 1))
            else
                table.insert(toys, key)
            end
        end
    end
    player:SetAttribute("CollectionToys", table.concat(toys, ","))
    player:SetAttribute("CollectionMutations", table.concat(mutations, ","))
    player:SetAttribute("CollectionBonus", ToyCollectionService:GetBonus(player))
end

local function discover(player: Player, toyId: string, mutationId: string?): ()
    local profile = DataService:Get(player)
    if profile == nil then
        return
    end
    local setsBefore = #ToyCollectionService:GetCompletedSets(player)
    local found: { Discovery } = {}

    local def = Toys.Get(toyId)
    if def and not profile.collection[toyId] then
        profile.collection[toyId] = true
        local reward = Progression.COLLECTION_DISCOVERY_REWARD[def.rarity] or 0
        BaseService:AddCash(player, reward)
        table.insert(found, { name = def.displayName, rarity = def.rarity :: string, reward = reward })
    end
    local mutation = if mutationId then Toys.GetMutation(mutationId) else nil
    if mutation and not profile.collection[MUTATION_PREFIX .. mutation.id] then
        profile.collection[MUTATION_PREFIX .. mutation.id] = true
        BaseService:AddCash(player, Progression.COLLECTION_MUTATION_REWARD)
        table.insert(found, {
            name = "Mutation " .. mutation.displayName,
            rarity = "Mutation",
            reward = Progression.COLLECTION_MUTATION_REWARD,
        })
    end
    if #found == 0 then
        return
    end

    local sets = ToyCollectionService:GetCompletedSets(player)
    local newSets: { string } = {}
    if #sets > setsBefore then
        newSets = sets
    end
    publish(player)
    BaseService:RefreshIncome(player)
    player:SetAttribute("Notif_Collection", true)
    local remote = Remotes.Get("CollectionState") :: RemoteEvent
    remote:FireClient(player, { items = found, sets = newSets })
    for _, item in found do
        discovered:Fire(player, item.rarity)
    end
end

function ToyCollectionService:Init(): () end

function ToyCollectionService:Start(): ()
    BaseService:AddIncomeMultiplier(function(player: Player): number
        return 1 + ToyCollectionService:GetBonus(player)
    end)
    BaseService.ToyDeposited:Connect(function(player: Player, toyId: string, mutationId: string?)
        discover(player, toyId, mutationId)
    end)

    local function onPlayer(player: Player): ()
        if DataService:WaitForProfile(player) then
            publish(player)
            BaseService:RefreshIncome(player)
        end
    end
    Players.PlayerAdded:Connect(onPlayer)
    for _, player in Players:GetPlayers() do
        task.spawn(onPlayer, player)
    end
end

return ToyCollectionService
