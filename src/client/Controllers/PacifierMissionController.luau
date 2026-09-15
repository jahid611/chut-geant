--!strict

--[[
    PacifierMissionController
    Mission du jour « Vole la tetine du bebe » cote joueur (PacifierMissionService) :
    - refus (« seulement pendant un reveil », « deja volee aujourd'hui ») : son de refus et message jaune ;
    - reussite : fanfare et message vert avec les recompenses (et la trainee exclusive la premiere fois) ;
    - un autre joueur la vole : message bleu pour tout le serveur ;
    - panneau « MISSION » au-dessus de la tetine cache pour ce joueur s'il l'a deja reussie aujourd'hui
      (attribut TetineFaite).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local Sfx = require(script.Parent.Parent.Ui.Sfx)
local Theme = require(script.Parent.Parent.Ui.Theme)

local SIGN_NAME = "PanneauTetine"

local PacifierMissionController = {}

local player = Players.LocalPlayer

local function formatNumber(value: number): string
    local digits = tostring(math.floor(math.abs(value)))
    local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1 ")))
    return (string.gsub(grouped, "^ ", ""))
end

local function refreshSign(sign: Instance): ()
    if sign:IsA("BillboardGui") and sign.Name == SIGN_NAME then
        local done = player:GetAttribute("TetineFaite") == true
        local parent = sign.Parent
        local carried = parent ~= nil and parent:GetAttribute("CarrierUserId") ~= nil
        sign.Enabled = not done and not carried
    end
end

local function refreshAllSigns(): ()
    local live = Workspace:FindFirstChild("ToysLive")
    if live == nil then
        return
    end
    for _, descendant in live:GetDescendants() do
        refreshSign(descendant)
    end
end

function PacifierMissionController:Init(): () end

function PacifierMissionController:Start(): ()
    local gui = Instance.new("ScreenGui")
    gui.Name = "MissionTetine"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 7
    gui.Parent = player:WaitForChild("PlayerGui")

    local remote = Remotes.Get("PacifierMission") :: RemoteEvent
    remote.OnClientEvent:Connect(function(kind: any, a: any, b: any)
        if kind == "refused" then
            Sfx.play("refuse")
            Theme.toast(gui, if typeof(a) == "string" then a else "Pas maintenant !", Theme.YELLOW)
        elseif kind == "win" then
            Sfx.play("fanfare")
            local cash = if typeof(a) == "table" and typeof(a.cash) == "number" then a.cash else 0
            local xp = if typeof(a) == "table" and typeof(a.xp) == "number" then a.xp else 0
            local text = string.format("Tétine volée ! +%s tétines, +%d XP", formatNumber(cash), xp)
            if typeof(a) == "table" and a.cosmetic ~= nil then
                text ..= " et la traînée exclusive !"
            end
            Theme.toast(gui, text, Theme.GREEN)
        elseif kind == "stolen" then
            if b ~= player.UserId then
                local name = if typeof(a) == "string" then a else "Quelqu'un"
                Theme.toast(gui, name .. " a volé la tétine du bébé !", Theme.BLUE)
            end
        end
    end)

    player:GetAttributeChangedSignal("TetineFaite"):Connect(refreshAllSigns)
    task.spawn(function()
        local live = Workspace:WaitForChild("ToysLive", 30)
        if live == nil then
            return
        end
        live.DescendantAdded:Connect(function(descendant: Instance)
            if descendant:IsA("BillboardGui") and descendant.Name == SIGN_NAME then
                -- le serveur le cache pendant le portage : on relit apres chaque changement
                local sign = descendant
                sign:GetPropertyChangedSignal("Enabled"):Connect(function()
                    if player:GetAttribute("TetineFaite") == true and sign.Enabled then
                        sign.Enabled = false
                    end
                end)
                task.defer(refreshSign, sign)
            end
        end)
        refreshAllSigns()
    end)
end

return PacifierMissionController
