--!strict

--[[
    ToyPreviewService
    Apercus 3D des jouets pour la collection (demande utilisateur : de vraies images de jouets). Seuls 15 jouets ont
    une image televersee ; les autres montraient une pastille avec leur initiale.

    Le client ne voit pas ServerStorage. A la demande (remote ToyPreview, quand la collection affiche un jouet sans
    image), copie legere de ServerStorage.ToyModels.<id> dans ReplicatedStorage.ApercusJouets.<id>
    (ShopService.LightCopy : scripts, sons, lumieres et particules retires, pieces ancrees et inertes). Chaque copie
    reste en cache pour tous : un modele n'est replique qu'une fois, et seulement quand quelqu'un ouvre la collection,
    au lieu de 130 modeles envoyes a l'arrivee de chaque joueur.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Toys = require(Shared:WaitForChild("Toys"))

local ShopService = require(script.Parent:WaitForChild("ShopService"))

local FOLDER_NAME = "ApercusJouets"
-- La collection demande tous ses jouets sans image d'un coup a l'ouverture : la limite couvre la collection entiere.
local WINDOW_SECONDS = 10
local MAX_PER_WINDOW = 200
local MAX_ID_LENGTH = 64

local ToyPreviewService = {}

local requests: { [Player]: { count: number, since: number } } = {}

local function previewFolder(): Folder
    local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
    if existing and existing:IsA("Folder") then
        return existing
    end
    local created = Instance.new("Folder")
    created.Name = FOLDER_NAME
    created.Parent = ReplicatedStorage
    return created
end

local function allowed(player: Player): boolean
    local now = os.clock()
    local entry = requests[player]
    if entry == nil or now - entry.since > WINDOW_SECONDS then
        requests[player] = { count = 1, since = now }
        return true
    end
    entry.count += 1
    return entry.count <= MAX_PER_WINDOW
end

-- Prepare l'apercu d'un jouet ; vrai s'il est disponible dans ReplicatedStorage.ApercusJouets.
function ToyPreviewService:Ensure(toyId: string): boolean
    if Toys.Get(toyId) == nil then
        return false
    end
    local folder = previewFolder()
    if folder:FindFirstChild(toyId) then
        return true
    end
    local models = ServerStorage:FindFirstChild("ToyModels")
    local source = if models then models:FindFirstChild(toyId) else nil
    if source == nil then
        return false
    end
    local ok, copy = pcall(ShopService.LightCopy, source)
    if not ok or copy == nil then
        return false
    end
    copy.Parent = folder
    return true
end

function ToyPreviewService:Init(): () end

function ToyPreviewService:Start(): ()
    local remote = Remotes.Get("ToyPreview") :: RemoteFunction
    remote.OnServerInvoke = function(player: Player, toyId: any)
        if typeof(toyId) ~= "string" or #toyId > MAX_ID_LENGTH or not allowed(player) then
            return false
        end
        return ToyPreviewService:Ensure(toyId)
    end
    Players.PlayerRemoving:Connect(function(player: Player)
        requests[player] = nil
    end)
end

return ToyPreviewService
