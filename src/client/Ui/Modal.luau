--!strict

--[[
    Modal
    Fenetre centrale des menus (boutique, coffre plein) : fond assombri et flou, panneau qui apparait
    en rebondissant, titre et bouton de fermeture. Une seule fenetre a la fois (enfant « Modal »).
]]

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent:WaitForChild("Theme"))

export type Modal = {
    root: Frame,
    panel: Frame,
    close: () -> (),
}

local Modal = {}

function Modal.isOpen(gui: Instance): boolean
    return gui:FindFirstChild("Modal") ~= nil
end

function Modal.open(gui: Instance, title: string, titleColor: Color3, size: UDim2): Modal
    local root = Instance.new("Frame")
    root.Name = "Modal"
    root.Size = UDim2.fromScale(1, 1)
    root.BackgroundColor3 = Color3.new(0, 0, 0)
    root.BackgroundTransparency = 1
    root.Active = true
    root.Parent = gui
    -- Nombre de menus ouverts, en attribut du joueur local : la barre de pouvoirs et les aides se cachent tant
    -- qu'un menu est ouvert (elles passaient par-dessus les menus, captures du 15/09).
    local Players = game:GetService("Players")
    local localPlayer = Players.LocalPlayer
    local function addOpen(delta: number): ()
        local count = localPlayer:GetAttribute("MenusOuverts")
        localPlayer:SetAttribute("MenusOuverts", math.max((if typeof(count) == "number" then count else 0) + delta, 0))
    end
    addOpen(1)
    root.Destroying:Connect(function()
        addOpen(-1)
    end)
    TweenService:Create(root, TweenInfo.new(0.2), { BackgroundTransparency = 0.45 }):Play()

    local blur = Instance.new("BlurEffect")
    blur.Name = "FlouMenu"
    blur.Size = 0
    blur.Parent = Lighting
    TweenService:Create(blur, TweenInfo.new(0.2), { Size = 14 }):Play()

    local panel = Theme.panel(root, "Panneau", size, UDim2.fromScale(0.5, 0.53), Vector2.new(0.5, 0.5))
    -- Le panneau tient toujours dans l'ecran (92 % au plus) : un menu ne deborde jamais de la fenetre.
    local scale = Theme.fitInside(panel, Vector2.new(size.X.Offset, size.Y.Offset), 0.92)
    local target = scale.Scale
    scale.Scale = target * 0.82
    TweenService:Create(scale, TweenInfo.new(0.28, Enum.EasingStyle.Back), { Scale = target }):Play()

    Theme.text(
        panel,
        "Titre",
        title,
        -- 60 % de large : a 70 % « COFFRE PLEIN ! » touchait le bouton de fermeture (teste en jeu)
        UDim2.new(0.6, 0, 0, 66),
        UDim2.new(0.5, 0, 0, 14),
        titleColor,
        Vector2.new(0.5, 0)
    )
    local closeButton = Theme.button(
        panel,
        "Fermer",
        "X",
        Theme.PINK,
        UDim2.fromOffset(62, 62),
        UDim2.new(1, -16, 0, 16),
        Vector2.new(1, 0)
    )

    local closed = false
    local function close(): ()
        if closed then
            return
        end
        closed = true
        TweenService:Create(blur, TweenInfo.new(0.15), { Size = 0 }):Play()
        TweenService:Create(root, TweenInfo.new(0.15), { BackgroundTransparency = 1 }):Play()
        TweenService:Create(scale, TweenInfo.new(0.15), { Scale = target * 0.85 }):Play()
        task.delay(0.16, function()
            blur:Destroy()
            root:Destroy()
        end)
    end
    closeButton.Activated:Connect(close)

    return { root = root, panel = panel, close = close }
end

-- Zone de contenu du panneau, sous le titre : tout ce qui y est pose est coupe a son bord (jamais de debordement).
function Modal.body(modal: Modal, top: number?, bottom: number?): Frame
    local t = top or 92
    local b = bottom or 20
    local frame = Instance.new("Frame")
    frame.Name = "Corps"
    frame.BackgroundTransparency = 1
    frame.Size = UDim2.new(1, -40, 1, -(t + b))
    frame.Position = UDim2.new(0.5, 0, 0, t)
    frame.AnchorPoint = Vector2.new(0.5, 0)
    frame.ClipsDescendants = true
    frame.Parent = modal.panel
    return frame
end

return Modal
