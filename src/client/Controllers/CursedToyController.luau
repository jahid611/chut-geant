--!strict

--[[
    CursedToyController
    Message au depot d'un jouet maudit (CursedToyService : attributs BonusMaudit et BonusMauditN du joueur).
]]

local Players = game:GetService("Players")

local Sfx = require(script.Parent.Parent.Ui.Sfx)
local Theme = require(script.Parent.Parent.Ui.Theme)

local CursedToyController = {}

local player = Players.LocalPlayer

function CursedToyController:Init(): () end

function CursedToyController:Start(): ()
    local gui = Instance.new("ScreenGui")
    gui.Name = "JouetMaudit"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 7
    gui.Parent = player:WaitForChild("PlayerGui")

    player:GetAttributeChangedSignal("BonusMauditN"):Connect(function()
        local bonus = player:GetAttribute("BonusMaudit")
        local amount = if typeof(bonus) == "number" then bonus else 0
        Sfx.play("fanfare")
        Theme.toast(gui, string.format("Jouet maudit déposé ! +%d tétines", amount), Theme.PINK)
    end)
end

return CursedToyController
