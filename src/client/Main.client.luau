--!strict

--[[
    Main.client
    Point d'entree client unique.

    Charge chaque module de Controllers, appelle Init() sur tous, puis Start()
    sur tous, dans le meme ordre que le serveur.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

export type Controller = {
    Init: ((Controller) -> ())?,
    Start: ((Controller) -> ())?,
}

local function loadControllers(): { [string]: Controller }
    local controllers: { [string]: Controller } = {}
    local folder = script.Parent:FindFirstChild("Controllers")
    if folder == nil then
        return controllers
    end
    for _, child in folder:GetChildren() do
        if child:IsA("ModuleScript") then
            local ok, result = pcall(require, child)
            if ok then
                controllers[child.Name] = result
            else
                warn(string.format("[Main] could not load %s: %s", child.Name, tostring(result)))
            end
        end
    end
    return controllers
end

local function callPhase(controllers: { [string]: Controller }, phase: "Init" | "Start"): ()
    for name, controller in controllers do
        local method = controller[phase]
        if typeof(method) == "function" then
            local ok, err = pcall(method, controller)
            if not ok then
                warn(string.format("[Main] %s.%s a echoue : %s", name, phase, tostring(err)))
            end
        end
    end
end

local controllers = loadControllers()
callPhase(controllers, "Init")
callPhase(controllers, "Start")

print(string.format("[Rojo OK] client started, %s v%s", Config.name, Config.version))
