--!strict

--[[
    CosmeticController
    Contour arc-en-ciel des coffres (cosmetique OutlineRainbow) : CosmeticService pose un Highlight
    « ContourCosmetique » avec l'attribut Rainbow ; ici sa couleur tourne en continu (changement local, fluide).
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local OUTLINE_NAME = "ContourCosmetique"
local RESCAN_SECONDS = 1

local CosmeticController = {}

function CosmeticController:Init(): () end

function CosmeticController:Start(): ()
    local rainbow: { Highlight } = {}
    local lastScan = -math.huge
    RunService.Heartbeat:Connect(function()
        local now = os.clock()
        if now - lastScan >= RESCAN_SECONDS then
            lastScan = now
            table.clear(rainbow)
            local root = Workspace:FindFirstChild("BaseChests")
            if root then
                for _, descendant in root:GetDescendants() do
                    if
                        descendant:IsA("Highlight")
                        and descendant.Name == OUTLINE_NAME
                        and descendant:GetAttribute("Rainbow") == true
                    then
                        table.insert(rainbow, descendant)
                    end
                end
            end
        end
        if #rainbow == 0 then
            return
        end
        local color = Color3.fromHSV((now * 0.25) % 1, 0.75, 1)
        for _, highlight in rainbow do
            highlight.OutlineColor = color
        end
    end)
end

return CosmeticController
