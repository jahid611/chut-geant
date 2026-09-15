--!strict

--[[
    Sfx
    Petits sons d'interface et d'action (demande utilisateur du 15/09 : « des bruits pour tout »). Sons publics de la
    bibliotheque Roblox, createurs verifies (Pro Sound Effects surtout), volumes doux : rien ne doit casser les
    oreilles. Un Sound reutilise par nom dans SoundService (pas de fuite), petit anti-spam par son, legere variation
    de hauteur pour ne pas lasser.

        Sfx.play("click")
        Sfx.play("tick", { speed = 1.3, volume = 0.2 })
]]

local SoundService = game:GetService("SoundService")

type Def = { id: string, volume: number, pitch: number, spread: number, gap: number }

-- id | volume | hauteur de base | variation +/- | delai minimal entre deux lectures (s)
local SOUNDS: { [string]: Def } = {
    -- « ui-simple-button-click » (AmbientSorcery, verifie)
    click = { id = "rbxassetid://88442833509532", volume = 0.35, pitch = 1, spread = 0.05, gap = 0.05 },
    -- « Cartoon Jump Sound [HQ] - BOING » (Dizzota, verifie) : attrape, boing comique
    caught = { id = "rbxassetid://2772396665", volume = 0.45, pitch = 1, spread = 0.08, gap = 0.4 },
    -- « Synth Air Whoosh Cheesy Karate Style Swishes » (Pro Sound Effects) : whoosh qui accompagne l'attrape
    caughtWhoosh = { id = "rbxassetid://9126046540", volume = 0.3, pitch = 1.1, spread = 0.05, gap = 0.4 },
    -- « bubble pop sound effect » (Molly_Greenie, verifie) : ramasser un jouet
    pickup = { id = "rbxassetid://132948338000932", volume = 0.4, pitch = 1.05, spread = 0.1, gap = 0.1 },
    -- « Swish Sweeteners Short Hissing Whooshes » (Pro Sound Effects) : lancer
    throw = { id = "rbxassetid://9126015450", volume = 0.45, pitch = 1, spread = 0.08, gap = 0.1 },
    -- « Thermos Set Down 6 » (Pro Sound Effects) : poser, petit toc
    drop = { id = "rbxassetid://9119999925", volume = 0.4, pitch = 1.1, spread = 0.08, gap = 0.1 },
    -- « Wood Door Open Soft Close 1 » (Pro Sound Effects) : entrer dans sa base
    baseEnter = { id = "rbxassetid://9120839581", volume = 0.35, pitch = 1.15, spread = 0.03, gap = 0.5 },
    -- « Door Soft Closes With No Latch 2 » (Pro Sound Effects) : sortir de sa base
    baseExit = { id = "rbxassetid://9114154826", volume = 0.35, pitch = 1.1, spread = 0.03, gap = 0.5 },
    -- « Coin Throws 2 » (Pro Sound Effects) : jouet depose dans le coffre
    deposit = { id = "rbxassetid://9113849583", volume = 0.4, pitch = 1.1, spread = 0.06, gap = 0.15 },
    -- « Cash Register Cha Ching - Sound Effect (HD) » (maxjay_jay, verifie) : achat reussi
    purchase = { id = "rbxassetid://101396758527961", volume = 0.35, pitch = 1, spread = 0, gap = 0.2 },
    -- refus d'achat : le clic joue grave et doux
    refuse = { id = "rbxassetid://88442833509532", volume = 0.3, pitch = 0.55, spread = 0, gap = 0.2 },
    -- « Locking Wrench 8 » (Pro Sound Effects) : cliquetis de la roue
    tick = { id = "rbxassetid://9116321214", volume = 0.18, pitch = 1.6, spread = 0.05, gap = 0.03 },
    -- « Power_Up » (thienbao2109, verifie) : petite fanfare a l'arret de la roue
    fanfare = { id = "rbxassetid://3406813517", volume = 0.35, pitch = 1, spread = 0, gap = 0.5 },
    -- « Wolf Howl Two Versions 1 » (Pro Sound Effects) : pleine lune
    howl = { id = "rbxassetid://9120790529", volume = 0.35, pitch = 1, spread = 0, gap = 5 },
    -- « Alert Alarm » (therealrandomnova) : un voleur dans sa base (StealController)
    alarm = { id = "rbxassetid://5603534974", volume = 0.35, pitch = 1, spread = 0, gap = 3 },

    -- Armes (WeaponController) : sons Pro Sound Effects verifies (get_asset_details, createur verifie, gratuits)
    -- coup dans le vide : le whoosh du lancer, plus aigu
    weaponSwing = { id = "rbxassetid://9126015450", volume = 0.35, pitch = 1.25, spread = 0.1, gap = 0.1 },
    -- « Rubber Raft Slapping Punching 4 » : bonk de la batte et de l'epee
    weaponBonk = { id = "rbxassetid://9118736388", volume = 0.45, pitch = 1, spread = 0.08, gap = 0.1 },
    -- « Napkin Flap 1 » : claque de la tapette et du chausson
    weaponSwat = { id = "rbxassetid://9117056216", volume = 0.45, pitch = 1.1, spread = 0.08, gap = 0.1 },
    -- oreiller : le bonk en caoutchouc, grave et doux
    weaponPillow = { id = "rbxassetid://9118736388", volume = 0.3, pitch = 0.6, spread = 0.05, gap = 0.1 },
    -- « Squeeze Toy Squeaky Rubber With Noisemaker H » : marteau qui couine
    weaponSqueak = { id = "rbxassetid://9125994773", volume = 0.45, pitch = 1, spread = 0.1, gap = 0.1 },
    -- « Puddle Stomps Small Water Splashes 9 » : pistolet a eau
    weaponSplash = { id = "rbxassetid://9117947034", volume = 0.4, pitch = 1.1, spread = 0.08, gap = 0.1 },
    -- etincelle de la baguette : la petite fanfare « Power_Up », tres aigue et courte
    weaponSparkle = { id = "rbxassetid://3406813517", volume = 0.25, pitch = 1.8, spread = 0.05, gap = 0.1 },

    -- Evenements de la chambre (EventController, nuit du 15-16/09), createurs verifies, gratuits :
    -- « Thunder Distant Rumble 2 (SFX) » (ProSoundEffects) : grondement avant l'eclair
    thunder = { id = "rbxassetid://9120018695", volume = 0.45, pitch = 1, spread = 0.08, gap = 0.5 },
    -- « Close Lightning Impact » (camcool12354) : l'eclair
    lightning = { id = "rbxassetid://4961088919", volume = 0.4, pitch = 1, spread = 0.06, gap = 0.5 },
    -- « Sneeze Sound effect (Male) » : l'etagere eternue (pluie de jouets), aigu pour faire rire
    sneeze = { id = "rbxassetid://70958899410442", volume = 0.4, pitch = 1.35, spread = 0.05, gap = 1 },
    -- « cartoon bubble pop » : un jouet qui tombe du ciel
    toyPop = { id = "rbxassetid://109359226723492", volume = 0.25, pitch = 1, spread = 0.15, gap = 0.12 },
    -- « FFPS - Twinkle » (ElianMaster87) : jouet dore geant
    chime = { id = "rbxassetid://106443875576213", volume = 0.4, pitch = 1, spread = 0, gap = 1 },
    -- « electricity_power_down_01 » (KyloDawg1) : panne de veilleuse
    powerDown = { id = "rbxassetid://135847326073354", volume = 0.35, pitch = 1, spread = 0, gap = 1 },
    -- « Cat Meow » (addisonpunL) : le chat de la maison
    meow = { id = "rbxassetid://136138461897866", volume = 0.45, pitch = 1, spread = 0.1, gap = 0.6 },
    -- « Doll Squeaks 7 (SFX) » (ProSoundEffects, verifie) : un jouet vivant s'enfuit en bondissant (LivingToyService
    -- joue le meme son en 3D sur le jouet)
    livingToy = { id = "rbxassetid://9114123168", volume = 0.4, pitch = 1.1, spread = 0.15, gap = 0.3 },

    -- Combo de discretion (ComboController), createurs verifies, gratuits :
    -- « bling_big_diamond_pickup » (thienbao2109) : le combo monte
    comboUp = { id = "rbxassetid://4612374036", volume = 0.35, pitch = 1, spread = 0.03, gap = 0.3 },
    -- « Plastic Crack 10 (SFX) » (ProSoundEffects) : le combo casse
    comboBreak = { id = "rbxassetid://9117458686", volume = 0.3, pitch = 1.1, spread = 0.05, gap = 0.5 },

    -- Recompense de retour et defis (WelcomeBackController, ChallengeController), ProSoundEffects verifie, gratuits :
    -- « Cardboard Carton 1 (SFX) » : le coffre cadeau s'ouvre (carton qui s'ouvre, aigu)
    giftOpen = { id = "rbxassetid://9113721446", volume = 0.45, pitch = 1.15, spread = 0.03, gap = 0.5 },
    -- « Pealess Whistle Referee Fox 40 1 (SFX) » : coup de sifflet au depart d'un defi
    challengeStart = { id = "rbxassetid://9117257939", volume = 0.3, pitch = 1.1, spread = 0, gap = 1 },
}

export type Options = { volume: number?, speed: number? }

local Sfx = {}

local sounds: { [string]: Sound } = {}
local lastPlayed: { [string]: number } = {}
local random = Random.new()

-- Groupes de sons regles dans le menu Parametres : « Musique » et « Effets » (volume de 0 a 1).
local function soundGroup(groupName: string): SoundGroup
    local existing = SoundService:FindFirstChild(groupName)
    if existing and existing:IsA("SoundGroup") then
        return existing
    end
    local group = Instance.new("SoundGroup")
    group.Name = groupName
    group.Volume = 1
    group.Parent = SoundService
    return group
end

local function soundFor(name: string, def: Def): Sound
    local existing = sounds[name]
    if existing and existing.Parent then
        return existing
    end
    local sound = Instance.new("Sound")
    sound.Name = "Sfx_" .. name
    sound.SoundId = def.id
    sound.Volume = def.volume
    sound.SoundGroup = soundGroup("Effets")
    sound.Parent = SoundService
    sounds[name] = sound
    return sound
end

-- Groupe de sons par nom (« Musique » ou « Effets »), cree au besoin.
function Sfx.group(groupName: string): SoundGroup
    return soundGroup(groupName)
end

-- Joue un son par son nom (ignore les noms inconnus et les appels trop rapproches).
function Sfx.play(name: string, options: Options?): ()
    local def: Def? = SOUNDS[name]
    if def == nil then
        return
    end
    local now = os.clock()
    local last: number? = lastPlayed[name]
    if last and now - last < def.gap then
        return
    end
    lastPlayed[name] = now
    local sound = soundFor(name, def)
    sound.Volume = if options and options.volume then options.volume else def.volume
    local speed = if options and options.speed then options.speed else def.pitch
    sound.PlaybackSpeed = speed + random:NextNumber(-def.spread, def.spread)
    sound.TimePosition = 0
    sound:Play()
end

return Sfx
