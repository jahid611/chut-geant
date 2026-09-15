--!strict

--[[
    ExampleService
    Gabarit de service serveur. A dupliquer pour chaque responsabilite du jeu.

    Init()  : preparation interne uniquement. Aucun autre service n'est encore pret.
    Start() : le reste du jeu est charge, les interactions sont autorisees.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local ExampleService = {}

function ExampleService:Init(): ()
    -- Etat interne, connexions differees, tables de donnees.
end

function ExampleService:Start(): ()
    if Config.debug then
        print("[ExampleService] pret")
    end
end

return ExampleService
