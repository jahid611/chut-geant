--!strict

--[[
    MenuController
    Colonne de boutons ronds a gauche de l'ecran, sous le compteur de tetines, pour les systemes de retention :
    quetes, pass de saison, cadeaux (connexion + roue), collection, Nuits (renaissance), classement.
    Chaque bouton ouvre le module Ui/Menus/<Nom> (fonction open(gui)) ; une pastille rouge s'affiche quand
    l'attribut joueur « Notif_<Nom> » vaut true (recompense a recuperer).
]]

local Players = game:GetService("Players")

local Theme = require(script.Parent.Parent.Ui.Theme)

type Menu = { open: (Instance) -> () }

local MENUS: { { name: string, icon: string, module: ModuleScript } } = {
    { name = "Quetes", icon = "menuQuetes", module = script.Parent.Parent.Ui.Menus.Quests },
    { name = "Pass", icon = "menuPass", module = script.Parent.Parent.Ui.Menus.Pass },
    { name = "Cadeaux", icon = "menuCadeaux", module = script.Parent.Parent.Ui.Menus.Gifts },
    { name = "Collection", icon = "menuCollection", module = script.Parent.Parent.Ui.Menus.Collection },
    { name = "Nuits", icon = "menuNuits", module = script.Parent.Parent.Ui.Menus.Nights },
    { name = "Classement", icon = "menuClassement", module = script.Parent.Parent.Ui.Menus.Leaderboard },
}

local MenuController = {}

function MenuController:Init(): () end

function MenuController:Start(): ()
    local player = Players.LocalPlayer
    local gui = Instance.new("ScreenGui")
    gui.Name = "Menus"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 5
    gui.Parent = player:WaitForChild("PlayerGui")

    local column = Instance.new("Frame")
    column.Name = "Colonne"
    column.BackgroundTransparency = 1
    column.Size = UDim2.fromOffset(110, #MENUS * 104)
    column.Position = UDim2.new(0, 14, 0.5, 40)
    column.AnchorPoint = Vector2.new(0, 0.5)
    column.Parent = gui
    Theme.fit(column, Theme.HUD_FACTOR)
    -- Cachee pendant la vue « Mes jouets » (attribut VueCoffre pose par Ui/ChestView) : la fleche du carrousel
    -- passait par-dessus la colonne.
    local function refreshColumn(): ()
        column.Visible = player:GetAttribute("VueCoffre") ~= true
    end
    player:GetAttributeChangedSignal("VueCoffre"):Connect(refreshColumn)
    refreshColumn()

    for i, menu in MENUS do
        local button = Theme.roundImageButton(
            column,
            menu.name,
            menu.icon,
            UDim2.fromOffset(92, 92),
            UDim2.fromOffset(8, (i - 1) * 104)
        )
        local dot = Instance.new("Frame")
        dot.Name = "Pastille"
        dot.BackgroundColor3 = Theme.RED
        dot.Size = UDim2.fromOffset(24, 24)
        dot.Position = UDim2.new(1, -8, 0, 8)
        dot.AnchorPoint = Vector2.new(0.5, 0.5)
        dot.Visible = false
        dot.Parent = button
        Theme.corner(dot, 12)
        local function refreshDot(): ()
            dot.Visible = player:GetAttribute("Notif_" .. menu.name) == true
        end
        player:GetAttributeChangedSignal("Notif_" .. menu.name):Connect(refreshDot)
        refreshDot()
        button.Activated:Connect(function()
            local ok, result = pcall(require, menu.module)
            if ok then
                (result :: Menu).open(gui)
            else
                warn("[MenuController] " .. menu.name .. " : " .. tostring(result))
            end
        end)
    end
end

return MenuController
