--!strict

--[[
    SettingsController
    Applique chez ce joueur les reglages du menu Parametres (attributs publies par SettingsService), des la
    connexion, meme si le menu n'est jamais ouvert :
    - ReglageMusique / ReglageEffets : volume des groupes de sons « Musique » et « Effets » (Ui/Sfx) ;
    - ReglageNoms : affiche ou cache localement les noms, niveaux et titres au-dessus de la tete de tous les joueurs,
      le sien compris (BillboardGui NiveauJoueur de LevelService, TitreNuit de NightsService) ;
    - EffetsReduits : simple attribut, lu par les controleurs qui gerent des particules.
]]

local Players = game:GetService("Players")

local Sfx = require(script.Parent.Parent.Ui.Sfx)

local HIDEABLE: { [string]: boolean } = {
    NiveauJoueur = true,
    TitreNuit = true,
}

local SettingsController = {}

local player = Players.LocalPlayer

local function number(value: any, default: number): number
    return if typeof(value) == "number" then value else default
end

local function showNames(): boolean
    return player:GetAttribute("ReglageNoms") ~= false
end

local function applyVolumes(): ()
    Sfx.group("Musique").Volume = number(player:GetAttribute("ReglageMusique"), 1)
    Sfx.group("Effets").Volume = number(player:GetAttribute("ReglageEffets"), 1)
end

local function applyTo(instance: Instance): ()
    if instance:IsA("BillboardGui") and HIDEABLE[instance.Name] then
        instance.Enabled = showNames()
    end
end

local function applyCharacter(character: Model): ()
    for _, descendant in character:GetDescendants() do
        applyTo(descendant)
    end
end

-- Le joueur lui-meme compris : de pres, sa propre etiquette « Niv. / titre » masquait la vue (test du 16/09).
local function applyAllNames(): ()
    for _, other in Players:GetPlayers() do
        if other.Character then
            applyCharacter(other.Character)
        end
    end
end

local function watchPlayer(other: Player): ()
    local function onCharacter(character: Model): ()
        applyCharacter(character)
        character.DescendantAdded:Connect(applyTo)
    end
    other.CharacterAdded:Connect(onCharacter)
    if other.Character then
        onCharacter(other.Character)
    end
end

function SettingsController:Init(): () end

function SettingsController:Start(): ()
    applyVolumes()
    player:GetAttributeChangedSignal("ReglageMusique"):Connect(applyVolumes)
    player:GetAttributeChangedSignal("ReglageEffets"):Connect(applyVolumes)
    player:GetAttributeChangedSignal("ReglageNoms"):Connect(applyAllNames)
    Players.PlayerAdded:Connect(watchPlayer)
    for _, other in Players:GetPlayers() do
        watchPlayer(other)
    end
end

return SettingsController
