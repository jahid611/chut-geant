--!strict

--[[
    ChestFull
    Fenetre « COFFRE PLEIN ! » (maquette docs/mockups/higgsfield/coffre-plein.png), ouverte quand le serveur
    refuse un depot parce que tous les coffres du joueur sont pleins. Propose d'acheter le coffre suivant.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local Modal = require(script.Parent:WaitForChild("Modal"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local ChestFull = {}

function ChestFull.show(gui: Instance, chests: number, capacity: number, price: number, canBuy: boolean): ()
    if Modal.isOpen(gui) then
        return
    end
    local modal = Modal.open(gui, "COFFRE PLEIN !", Theme.PINK, UDim2.fromOffset(640, 700))
    local panel = modal.panel

    Theme.image(
        panel,
        "Illustration",
        "coffrePlein",
        UDim2.fromOffset(320, 250),
        UDim2.new(0.5, 0, 0, 86),
        Vector2.new(0.5, 0)
    )
    local total = chests * capacity
    local line1 = if chests <= 1
        then string.format("Ta boîte à jouets est pleine (%d/%d).", capacity, capacity)
        else string.format("Tes %d boîtes à jouets sont pleines (%d/%d).", chests, total, total)
    Theme.text(
        panel,
        "Ligne1",
        line1,
        UDim2.new(0.9, 0, 0, 38),
        UDim2.new(0.5, 0, 0, 346),
        Theme.WHITE,
        Vector2.new(0.5, 0)
    )
    local line2 = if canBuy
        then string.format("Achète un %de coffre pour garder tes jouets.", chests + 1)
        else "Tu as déjà le maximum de coffres."
    Theme.text(
        panel,
        "Ligne2",
        line2,
        UDim2.new(0.86, 0, 0, 30),
        UDim2.new(0.5, 0, 0, 390),
        Theme.SOFT_TEXT,
        Vector2.new(0.5, 0)
    )

    if canBuy then
        -- apercu : le coffre actuel + le nouveau qui brille
        Theme.image(
            panel,
            "CoffreActuel",
            "articleCoffre",
            UDim2.fromOffset(120, 86),
            UDim2.new(0.5, -110, 0, 432),
            Vector2.new(0.5, 0)
        )
        Theme.text(
            panel,
            "Plus",
            "+",
            UDim2.fromOffset(50, 50),
            UDim2.new(0.5, 0, 0, 450),
            Theme.YELLOW,
            Vector2.new(0.5, 0)
        )
        local glow = Instance.new("Frame")
        glow.Name = "Halo"
        glow.BackgroundColor3 = Theme.YELLOW
        glow.BackgroundTransparency = 0.75
        glow.Size = UDim2.fromOffset(136, 100)
        glow.Position = UDim2.new(0.5, 110, 0, 425)
        glow.AnchorPoint = Vector2.new(0.5, 0)
        glow.Parent = panel
        Theme.corner(glow, 30)
        Theme.image(
            panel,
            "NouveauCoffre",
            "articleCoffre",
            UDim2.fromOffset(120, 86),
            UDim2.new(0.5, 110, 0, 432),
            Vector2.new(0.5, 0)
        )

        local buy = Theme.button(
            panel,
            "Acheter",
            "Acheter – " .. Theme.formatNumber(price),
            Theme.GREEN,
            UDim2.fromOffset(430, 74),
            UDim2.new(0.5, 0, 0, 540),
            Vector2.new(0.5, 0)
        )
        Theme.image(buy, "Icone", "tetine", UDim2.fromOffset(52, 52), UDim2.fromScale(0, 0.5), Vector2.new(0, 0.5))
        buy.Activated:Connect(function()
            buy.Text = "..."
            local ok, success, message = pcall(function()
                return (Remotes.Get("BuyItem") :: RemoteFunction):InvokeServer("Chest")
            end)
            if ok and success == true then
                Theme.toast(gui, if typeof(message) == "string" then message else "Coffre acheté !", Theme.GREEN)
                modal.close()
            else
                Theme.toast(gui, if ok and typeof(message) == "string" then message else "Achat impossible.", Theme.RED)
                buy.Text = "Acheter – " .. Theme.formatNumber(price)
            end
        end)
    end

    local later = Theme.button(
        panel,
        "PlusTard",
        if canBuy then "Plus tard" else "OK",
        Theme.GREY,
        UDim2.fromOffset(320, 54),
        UDim2.new(0.5, 0, 1, -22),
        Vector2.new(0.5, 1)
    )
    later.Activated:Connect(modal.close)
end

return ChestFull
