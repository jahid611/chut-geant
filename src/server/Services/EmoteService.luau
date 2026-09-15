--!strict

--[[
    EmoteService
    Emotes rapides de la roue (touche Z, EmoteController) : communiquer sans chat, pour les jeunes joueurs et pour
    rester discret. Le client envoie l'id de l'emote (remote Emote), le serveur verifie l'id et l'anti-spam puis
    previent tous les clients (bulle au-dessus de la tete et petit geste).
    « Chut ! » ne fait aucun bruit ; les autres ajoutent un tout petit bruit a la jauge si le joueur est dans la
    chambre (NoiseService:Add).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local NoiseService = require(script.Parent:WaitForChild("NoiseService"))

local COOLDOWN_SECONDS = 2
local EMOTE_NOISE = 1
local SILENT_EMOTE = "Shush"

local VALID: { [string]: boolean } = {
    Shush = true,
    Come = true,
    Watch = true,
    Bravo = true,
    Help = true,
    Thanks = true,
}

local EmoteService = {}

local lastEmote: { [Player]: number } = {}

function EmoteService:Init(): () end

function EmoteService:Start(): ()
    local remote = Remotes.Get("Emote") :: RemoteEvent
    remote.OnServerEvent:Connect(function(player: Player, emoteId: any)
        if typeof(emoteId) ~= "string" or not VALID[emoteId] then
            return
        end
        local now = os.clock()
        local last: number? = lastEmote[player]
        if last and now - last < COOLDOWN_SECONDS then
            return
        end
        lastEmote[player] = now
        if emoteId ~= SILENT_EMOTE then
            local character = player.Character
            local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
            if root and root:IsA("BasePart") and NoiseService:IsInRoom(root.Position) then
                NoiseService:Add(EMOTE_NOISE)
            end
        end
        remote:FireAllClients(player.UserId, emoteId)
    end)
    Players.PlayerRemoving:Connect(function(player: Player)
        lastEmote[player] = nil
    end)
end

return EmoteService
