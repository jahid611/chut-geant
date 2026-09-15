--!strict

--[[
    Main.server
    Point d'entree serveur unique.

    Charge chaque module de src/server/Services, appelle Init() sur tous,
    puis Start() sur tous. Cet ordre garantit qu'un service peut compter sur
    l'existence des autres dans son Start(), mais jamais dans son Init().
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

export type Service = {
    Init: ((Service) -> ())?,
    Start: ((Service) -> ())?,
}

local function loadServices(): { [string]: Service }
    local services: { [string]: Service } = {}
    local container = ServerScriptService:FindFirstChild("Server")
    if container == nil then
        return services
    end

    local folder = container:FindFirstChild("Services")
    if folder == nil then
        return services
    end

    for _, child in folder:GetChildren() do
        if child:IsA("ModuleScript") then
            local ok, result = pcall(require, child)
            if ok then
                services[child.Name] = result
            else
                warn(string.format("[Main] could not load %s: %s", child.Name, tostring(result)))
            end
        end
    end
    return services
end

local function callPhase(services: { [string]: Service }, phase: "Init" | "Start"): ()
    for name, service in services do
        local method = service[phase]
        if typeof(method) == "function" then
            -- Chaque phase tourne dans son propre fil : un service qui attend (WaitForChild...) ne bloque plus le
            -- demarrage des suivants (un blocage de StealService avait empeche le chargement des profils).
            local thread = task.spawn(function()
                local ok, err = pcall(method, service)
                if not ok then
                    warn(string.format("[Main] %s.%s a echoue : %s", name, phase, tostring(err)))
                end
            end)
            if coroutine.status(thread) ~= "dead" then
                warn(
                    string.format("[Main] %s.%s attend encore, les services suivants demarrent quand meme", name, phase)
                )
            end
        end
    end
end

Remotes.Init()

local services = loadServices()
callPhase(services, "Init")
callPhase(services, "Start")

print(string.format("[Rojo OK] server started, %s v%s", Config.name, Config.version))
