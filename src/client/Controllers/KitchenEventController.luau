--!strict

--[[
    KitchenEventController
    Bandeaux des evenements de la cuisine (KitchenEventService, remote KitchenEvent), visibles seulement quand le joueur
    est dans la cuisine (attribut Piece == "Cuisine"). Les bandeaux du bebe, eux, restent masques dans la cuisine
    (EventController) : les deux ne se chevauchent jamais.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local Sfx = require(script.Parent.Parent.Ui.Sfx)
local Theme = require(script.Parent.Parent.Ui.Theme)

type Text = { title: string, subtitle: string, color: Color3, sound: string? }

local TEXTS: { [string]: { [string]: Text } } = {
    FridgeLight = {
        warn = {
            title = "LE FRIGO S'OUVRE !",
            subtitle = "Sa lumière va balayer le carrelage : cache-toi !",
            color = Theme.BLUE,
            sound = "alarm",
        },
        start = {
            title = "LE FRIGO S'OUVRE !",
            subtitle = "Reste hors de la lumière !",
            color = Theme.BLUE,
        },
    },
    BowlCrash = {
        warn = {
            title = "LA GAMELLE GLISSE !",
            subtitle = "Elle va tomber : le chien va entendre !",
            color = Theme.YELLOW,
            sound = "alarm",
        },
        start = {
            title = "BADABOUM !",
            subtitle = "Le chien a sursauté : fais très attention !",
            color = Theme.YELLOW,
        },
    },
    DogDream = {
        start = {
            title = "LE CHIEN RÊVE...",
            subtitle = "Il aboie en dormant : ce n'est qu'un rêve !",
            color = Theme.MINT,
            sound = "chime",
        },
    },
}

local KitchenEventController = {}

local player = Players.LocalPlayer

function KitchenEventController:Init(): () end

function KitchenEventController:Start(): ()
    local gui = Instance.new("ScreenGui")
    gui.Name = "EvenementsCuisine"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 6
    gui.Parent = player:WaitForChild("PlayerGui")

    local banner: Frame? = nil
    local countdownConnection: RBXScriptConnection? = nil

    local function updateBannerVisibility(): ()
        local menus = player:GetAttribute("MenusOuverts")
        if banner then
            banner.Visible = not (typeof(menus) == "number" and menus > 0) and player:GetAttribute("Piece") == "Cuisine"
        end
    end

    local function clear(): ()
        if countdownConnection then
            countdownConnection:Disconnect()
            countdownConnection = nil
        end
        if banner then
            banner:Destroy()
            banner = nil
        end
    end

    local function show(text: Text, endsAt: number): ()
        clear()
        local holder = Instance.new("Frame")
        holder.Name = "BandeauCuisine"
        holder.BackgroundTransparency = 1
        holder.Size = UDim2.fromOffset(700, 200)
        holder.Position = UDim2.new(0.5, 0, 0, 118)
        holder.AnchorPoint = Vector2.new(0.5, 0)
        holder.Parent = gui
        local scale = Theme.fit(holder, 0.8)
        local target = scale.Scale
        scale.Scale = target * 0.6
        TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = target }):Play()
        banner = holder
        updateBannerVisibility()

        local title = Theme.text(
            holder,
            "Titre",
            text.title,
            UDim2.new(1, 0, 0, 68),
            UDim2.fromScale(0.5, 0),
            text.color,
            Vector2.new(0.5, 0)
        )
        local titleStroke = title:FindFirstChildOfClass("UIStroke")
        if titleStroke then
            titleStroke.Thickness = 4
        end
        Theme.text(
            holder,
            "SousTitre",
            text.subtitle,
            UDim2.new(1, 0, 0, 34),
            UDim2.new(0.5, 0, 0, 70),
            Theme.WHITE,
            Vector2.new(0.5, 0)
        )
        if endsAt > 0 then
            local counter = Theme.text(
                holder,
                "Compteur",
                "",
                UDim2.fromOffset(140, 60),
                UDim2.new(0.5, 0, 0, 108),
                text.color,
                Vector2.new(0.5, 0)
            )
            countdownConnection = RunService.RenderStepped:Connect(function()
                local left = math.ceil(endsAt - workspace:GetServerTimeNow())
                counter.Text = if left > 0 then tostring(left) else ""
            end)
        end
    end

    local menusConnection = player:GetAttributeChangedSignal("MenusOuverts"):Connect(updateBannerVisibility)
    gui.Destroying:Connect(function()
        menusConnection:Disconnect()
        clear()
    end)

    local remote = Remotes.Get("KitchenEvent") :: RemoteEvent
    remote.OnClientEvent:Connect(function(kind: any, phase: any, endsAt: any)
        if typeof(kind) ~= "string" or typeof(phase) ~= "string" then
            return
        end
        if player:GetAttribute("Piece") ~= "Cuisine" then
            clear()
            return
        end
        if phase == "end" then
            clear()
            return
        end
        if phase == "lit" then
            Sfx.play("refuse")
            Theme.toast(gui, "Le frigo t'a éclairé : le chien se réveille !", Theme.RED)
            return
        end
        local byPhase = TEXTS[kind]
        local text = if byPhase then byPhase[phase] else nil
        if text == nil then
            return
        end
        if text.sound then
            Sfx.play(text.sound)
        end
        show(text, if typeof(endsAt) == "number" then endsAt else 0)
    end)

    player:GetAttributeChangedSignal("Piece"):Connect(function()
        if player:GetAttribute("Piece") ~= "Cuisine" then
            clear()
        end
    end)
end

return KitchenEventController
