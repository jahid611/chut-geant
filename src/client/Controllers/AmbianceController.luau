--!strict

--[[
    AmbianceController
    Ambiance propre a l'interieur des bases, pour ce joueur seulement.

    Les recettes de scene posent des volumes tagues "InteriorZone" avec l'attribut Ambiance
    (par exemple "Pantoufle"). Quand le personnage du joueur est dans l'un d'eux, l'eclairage,
    la brume, le ciel et l'etalonnage basculent en douceur sur le reglage de cette ambiance ;
    en sortant, l'ambiance de la chambre revient. Les valeurs de la chambre sont relevees au
    demarrage, telles que la recette de la chambre les a posees.
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Zone = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Zone"))

local ZONE_TAG = "InteriorZone"
local CHECK_SECONDS = 0.25
local FADE = TweenInfo.new(0.8, Enum.EasingStyle.Sine)

type Preset = {
    lighting: { [string]: any },
    atmosphere: { [string]: any },
    grade: { [string]: any },
    stars: number,
    celestial: boolean,
    -- Intensite de la lueur « Halo » (BloomEffect pose par la recette de la chambre pour les lampes).
    bloom: number?,
}

-- Fourrure dans le noir : presque aucune lumiere ambiante, brume sombre, pas de lune ni d'etoiles.
-- Seules les lucioles, la sortie et la boite a jouets eclairent (reference de l'utilisateur).
local PRESETS: { [string]: Preset } = {
    Pantoufle = {
        -- Assez de lumiere ambiante pour deviner les dunes (a 10,11,15 puis 28,32,42 l'ecran restait noir),
        -- brume legere pour que le relief se perde au loin sans tout avaler.
        -- 48,54,68 : a l'arrivee apres le fondu l'ecran etait encore presque noir (teste en jeu avec la fourrure rose),
        -- on remonte l'ambiance et on allege la brume pour voir les dunes autour du joueur.
        -- Capture prise 5 s apres l'arrivee : avec ambient 92,78,96 la fourrure est bien eclairee, le joueur meme un peu
        -- surexpose. Les captures noires d'avant etaient prises pendant le fondu au noir et la transition d'ambiance.
        -- On garde ces valeurs, exposition legerement baissee.
        lighting = {
            Ambient = Color3.fromRGB(92, 78, 96),
            OutdoorAmbient = Color3.fromRGB(76, 64, 82),
            Brightness = 0,
            -- 0,45 + lueur 0,08 + lumiere d'arrivee 1,1 : de nouveau trop sombre sur une partie propre ; 0,7 + 0,35 +
            -- 2,6 surexposait le joueur. Reglage intermediaire.
            ExposureCompensation = 0.6,
            EnvironmentDiffuseScale = 0,
            EnvironmentSpecularScale = 0,
        },
        atmosphere = {
            Density = 0.16,
            Offset = 0,
            Color = Color3.fromRGB(22, 26, 34),
            Decay = Color3.fromRGB(10, 12, 18),
            Glare = 0,
            Haze = 0.6,
        },
        grade = {
            Contrast = 0.22,
            Saturation = -0.3,
            Brightness = 0,
            -- teinte neutre : l'ancienne teinte bleue rendait la fourrure rose violette
            TintColor = Color3.fromRGB(240, 232, 238),
        },
        stars = 0,
        celestial = false,
        -- la lueur de la chambre (0,35) faisait ressortir le joueur tout blanc dans la fourrure (teste en jeu)
        bloom = 0.18,
    },
    -- Boite a mouchoirs : piece en carton bleu-gris dans la penombre, lueur froide qui tombe du trou ovale.
    Mouchoirs = {
        -- Reference : piece gris-bleu faiblement mais uniformement eclairee, parois visibles (52,58,70 : tout noir).
        lighting = {
            Ambient = Color3.fromRGB(96, 104, 120),
            OutdoorAmbient = Color3.fromRGB(84, 92, 106),
            Brightness = 0,
            ExposureCompensation = 0.2,
            EnvironmentDiffuseScale = 0,
            EnvironmentSpecularScale = 0,
        },
        atmosphere = {
            -- presque pas de brume : les parois sont a 180-210 studs du joueur et la brume sombre les rendait
            -- entierement noires, trou du plafond compris (teste en jeu)
            Density = 0.015,
            Offset = 0,
            Color = Color3.fromRGB(34, 40, 50),
            Decay = Color3.fromRGB(18, 22, 30),
            Glare = 0,
            Haze = 0.4,
        },
        grade = {
            Contrast = 0.2,
            Saturation = -0.4,
            Brightness = 0,
            TintColor = Color3.fromRGB(205, 215, 230),
        },
        stars = 0,
        celestial = false,
        bloom = 0.15,
    },
    -- Boite a chaussures : carton kraft chaud, papier de soie rose, lumiere doree des trous d'aeration.
    Chaussures = {
        -- 130,105,85 et exposition 0,35 : parois du fond et couvercle noirs (capture interieur-chaussures-avant)
        lighting = {
            Ambient = Color3.fromRGB(150, 122, 98),
            OutdoorAmbient = Color3.fromRGB(128, 104, 84),
            Brightness = 0,
            ExposureCompensation = 0.45,
            EnvironmentDiffuseScale = 0,
            EnvironmentSpecularScale = 0,
        },
        atmosphere = {
            Density = 0.02,
            Offset = 0,
            Color = Color3.fromRGB(60, 45, 35),
            Decay = Color3.fromRGB(30, 22, 16),
            Glare = 0,
            Haze = 0.3,
        },
        grade = {
            Contrast = 0.15,
            Saturation = -0.05,
            Brightness = 0.02,
            TintColor = Color3.fromRGB(255, 238, 220),
        },
        stars = 0,
        celestial = false,
        bloom = 0.2,
    },
    -- Boite de cereales : carton jaune dore, miettes et flocons, lumiere doree par l'ouverture.
    Cereales = {
        lighting = {
            Ambient = Color3.fromRGB(135, 115, 70),
            OutdoorAmbient = Color3.fromRGB(115, 98, 60),
            Brightness = 0,
            ExposureCompensation = 0.3,
            EnvironmentDiffuseScale = 0,
            EnvironmentSpecularScale = 0,
        },
        atmosphere = {
            Density = 0.02,
            Offset = 0,
            Color = Color3.fromRGB(70, 55, 30),
            Decay = Color3.fromRGB(35, 26, 12),
            Glare = 0,
            Haze = 0.3,
        },
        grade = {
            Contrast = 0.15,
            Saturation = 0.05,
            Brightness = 0.02,
            TintColor = Color3.fromRGB(255, 240, 210),
        },
        stars = 0,
        celestial = false,
        bloom = 0.25,
    },
    -- Tiroir : bois clair, chaussettes colorees, lame de lumiere chaude par la fente.
    Tiroir = {
        lighting = {
            Ambient = Color3.fromRGB(120, 100, 80),
            OutdoorAmbient = Color3.fromRGB(100, 84, 68),
            Brightness = 0,
            ExposureCompensation = 0.25,
            EnvironmentDiffuseScale = 0,
            EnvironmentSpecularScale = 0,
        },
        atmosphere = {
            Density = 0.02,
            Offset = 0,
            Color = Color3.fromRGB(50, 40, 32),
            Decay = Color3.fromRGB(24, 18, 14),
            Glare = 0,
            Haze = 0.3,
        },
        grade = {
            Contrast = 0.18,
            Saturation = 0,
            Brightness = 0.02,
            TintColor = Color3.fromRGB(255, 236, 215),
        },
        stars = 0,
        celestial = false,
        bloom = 0.2,
    },
    -- Carton de demenagement : carton brun, papier bulle et polystyrene, lumiere froide de la nuit par les rabats.
    Carton = {
        lighting = {
            Ambient = Color3.fromRGB(105, 105, 120),
            OutdoorAmbient = Color3.fromRGB(90, 92, 108),
            Brightness = 0,
            ExposureCompensation = 0.25,
            EnvironmentDiffuseScale = 0,
            EnvironmentSpecularScale = 0,
        },
        atmosphere = {
            Density = 0.02,
            Offset = 0,
            Color = Color3.fromRGB(40, 44, 56),
            Decay = Color3.fromRGB(20, 22, 30),
            Glare = 0,
            Haze = 0.3,
        },
        grade = {
            Contrast = 0.18,
            Saturation = -0.1,
            Brightness = 0.02,
            TintColor = Color3.fromRGB(225, 230, 245),
        },
        stars = 0,
        celestial = false,
        bloom = 0.18,
    },
}

local AmbianceController = {}

local saved: Preset? = nil
local current: string? = nil

local function capture(): Preset
    local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
    local grade = Lighting:FindFirstChild("Etalonnage")
    local sky = Lighting:FindFirstChildOfClass("Sky")
    local preset: Preset = {
        lighting = {},
        atmosphere = {},
        grade = {},
        stars = if sky then sky.StarCount else 3000,
        celestial = if sky then sky.CelestialBodiesShown else true,
    }
    for key in PRESETS.Pantoufle.lighting do
        preset.lighting[key] = (Lighting :: any)[key]
    end
    if atmosphere then
        for key in PRESETS.Pantoufle.atmosphere do
            preset.atmosphere[key] = (atmosphere :: any)[key]
        end
    end
    if grade and grade:IsA("ColorCorrectionEffect") then
        for key in PRESETS.Pantoufle.grade do
            preset.grade[key] = (grade :: any)[key]
        end
    end
    local halo = Lighting:FindFirstChild("Halo")
    if halo and halo:IsA("BloomEffect") then
        preset.bloom = halo.Intensity
    end
    return preset
end

local function apply(preset: Preset): ()
    TweenService:Create(Lighting, FADE, preset.lighting):Play()
    local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
    if atmosphere and next(preset.atmosphere) then
        TweenService:Create(atmosphere, FADE, preset.atmosphere):Play()
    end
    local grade = Lighting:FindFirstChild("Etalonnage")
    if grade and grade:IsA("ColorCorrectionEffect") and next(preset.grade) then
        TweenService:Create(grade, FADE, preset.grade):Play()
    end
    local sky = Lighting:FindFirstChildOfClass("Sky")
    if sky then
        sky.StarCount = preset.stars
        sky.CelestialBodiesShown = preset.celestial
    end
    local halo = Lighting:FindFirstChild("Halo")
    local bloom = preset.bloom
    if halo and halo:IsA("BloomEffect") and bloom then
        TweenService:Create(halo, FADE, { Intensity = bloom }):Play()
    end
end

local function ambianceAt(position: Vector3): string?
    for _, zone in CollectionService:GetTagged(ZONE_TAG) do
        if zone:IsA("BasePart") and zone:IsDescendantOf(workspace) and Zone.Contains(zone, position) then
            local name = zone:GetAttribute("Ambiance")
            if typeof(name) == "string" and PRESETS[name] then
                return name
            end
        end
    end
    return nil
end

function AmbianceController:Init(): () end

function AmbianceController:Start(): ()
    saved = capture()
    local player = Players.LocalPlayer
    task.spawn(function()
        while true do
            task.wait(CHECK_SECONDS)
            local character = player.Character
            local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
            local wanted = if root and root:IsA("BasePart") then ambianceAt(root.Position) else nil
            if wanted ~= current then
                current = wanted
                local preset: Preset? = if wanted then PRESETS[wanted] else saved
                if preset then
                    apply(preset)
                end
                -- Trace de controle : la lecture de l'eclairage cote client n'est possible que par les journaux.
                local label = wanted or "chambre"
                task.delay(1.2, function()
                    local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
                    print(
                        string.format(
                            "[Ambiance] %s : ambient %s, exposition %.2f, brume %s",
                            label,
                            tostring(Lighting.Ambient),
                            Lighting.ExposureCompensation,
                            if atmosphere then string.format("%.2f", atmosphere.Density) else "aucune"
                        )
                    )
                end)
            end
        end
    end)
end

return AmbianceController
