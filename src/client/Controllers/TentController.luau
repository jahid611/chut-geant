--!strict

--[[
    TentController
    Affiche les messages courts du tipi (attribut joueur TipiMessage = "compteur|texte" pose par TentService) :
    jouet range, jouet trop gros, tipi plein.
]]

local Players = game:GetService("Players")

local Theme = require(script.Parent.Parent.Ui.Theme)

local TentController = {}

function TentController:Init(): () end

function TentController:Start(): ()
    local player = Players.LocalPlayer
    local gui = Instance.new("ScreenGui")
    gui.Name = "Tipi"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 7
    gui.Parent = player:WaitForChild("PlayerGui")
    player:GetAttributeChangedSignal("TipiMessage"):Connect(function()
        local value = player:GetAttribute("TipiMessage")
        if typeof(value) ~= "string" then
            return
        end
        local text = string.match(value, "^%d+|(.*)$") or value
        local color = if string.find(text, "Rangé", 1, true) then Theme.GREEN else Theme.YELLOW
        Theme.toast(gui, text, color)
    end)
end

return TentController
