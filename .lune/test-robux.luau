--!strict

-- Exécute le vrai gestionnaire avec des services simulés ; aucun achat ni DataStore réel.
local Products = require("../src/shared/RobuxProducts")
local fs = require("@lune/fs")
local luau = require("@lune/luau")

for _, path in
    {
        "src/server/Services/DataService.luau",
        "src/client/Ui/Shop.luau",
        "src/shared/Catalog.luau",
    }
do
    assert(typeof(luau.load(fs.readFile(path))) == "function", "Syntaxe invalide : " .. path)
end
assert(#Products.Packs == 4 and Products.ByProductId(0) == nil)
for i, amount in { 2500, 10000, 30000, 100000 } do
    assert(Products.Packs[i].cash == amount and Products.Packs[i].productId == 0)
end

local source = fs.readFile("src/server/Services/RobuxShopService.luau")
local pack = Products.Packs[1]
local marketplace: any = {}
local players: any = {}
local attributes: { [string]: number } = { Cash = 500 }
local player: any = { Parent = players }
function player:GetAttribute(key: string): number?
    return attributes[key]
end
function player:SetAttribute(key: string, value: number): ()
    attributes[key] = value
end
local present = true
function players:GetPlayerByUserId(id: number): any
    return if present and id == 1 then player else nil
end
local removing: (any) -> () = function() end
players.PlayerRemoving = {
    Connect = function(_, callback)
        removing = callback
    end,
}

local profile: any = { cash = 500, stats = {}, robuxReceipts = {} }
local loaded, saveable, saveOk = true, true, true
local durable: any = nil
local saveHook: (() -> ())? = nil
local data: any = {}
function data:Get(): any
    return if loaded then profile else nil
end
function data:CanSave(): boolean
    return loaded and saveable
end
function data:Save(): boolean
    local hook = saveHook
    if hook then
        saveHook = nil
        hook()
    end
    if not saveOk then
        return false
    end
    durable = {
        cash = profile.cash,
        stats = table.clone(profile.stats),
        robuxReceipts = table.clone(profile.robuxReceipts),
    }
    return true
end
function data:AddStat(_, key: string, amount: number): ()
    profile.stats[key] = (profile.stats[key] or 0) + amount
end
local base: any = {}
function base:AddCash(_, amount: number): ()
    profile.cash += amount
    attributes.Cash = profile.cash
end

local folder: any = {}
function folder:WaitForChild(name: string): any
    return if name == "Shared" then folder else name
end
local services: any = { MarketplaceService = marketplace, Players = players, ReplicatedStorage = folder }
local dependencies: any = {
    BaseService = base,
    DataService = data,
    RobuxProducts = {
        ByProductId = function(id: number)
            return if id == 42 then pack else nil
        end,
    },
}
local function start(): ()
    local service = luau.load(source, {
        environment = {
            game = {
                GetService = function(_, name)
                    return services[name]
                end,
            },
            script = { Parent = folder },
            require = function(name)
                return dependencies[name]
            end,
            Enum = { ProductPurchaseDecision = { NotProcessedYet = "attente", PurchaseGranted = "accordé" } },
            print = function() end,
            warn = function() end,
        },
    })()
    service:Init()
    service:Start()
end
local function receipt(id: string, productId: number?): string
    return marketplace.ProcessReceipt({ ProductId = productId or 42, PlayerId = 1, PurchaseId = id })
end
start()
assert(receipt("inconnu", 99) == "attente")
assert(receipt("désactivé", 0) == "attente")
present = false
assert(receipt("absent") == "attente")
present, loaded = true, false
assert(receipt("chargement") == "attente")
loaded, saveable = true, false
assert(receipt("secours") == "attente")
saveable = true
attributes.Cash = nil
assert(receipt("solde absent") == "attente")
attributes.Cash = 500
assert(receipt("") == "attente")
assert(profile.cash == 500 and #profile.robuxReceipts == 0)

-- Deux callbacks pendant la sauvegarde : un seul crédit, confirmation après persistance seulement.
saveHook = function()
    assert(attributes.RobuxTetinesCreditees == nil)
    assert(receipt("premier") == "attente")
    assert(receipt("concurrent") == "attente")
end
assert(receipt("premier") == "accordé")
assert(profile.cash == 3000 and durable.cash == 3000 and profile.stats.robuxPurchases == 1)
assert(attributes.RobuxTetinesCreditees == 2500)
assert(receipt("premier") == "accordé" and profile.cash == 3000)

-- Panne puis dépense en jeu : ne pas rembourser/annuler la dépense lors du réessai.
saveOk = false
assert(receipt("panne") == "attente" and profile.cash == 5500)
assert(receipt("panne") == "attente" and profile.cash == 5500)
assert(receipt("suivant") == "attente" and #profile.robuxReceipts == 2)
assert(attributes.RobuxTetinesCreditees == 2500)
base:AddCash(player, -100)
saveOk = true
assert(receipt("panne") == "accordé" and profile.cash == 5400)
assert(durable.cash == 5400 and durable.stats.robuxPurchases == 2)
assert(attributes.RobuxTetinesCreditees == 5000)

-- Nouvelle instance du gestionnaire à partir du profil persisté : le reçu est reconnu.
removing(player)
profile = durable
start()
assert(receipt("panne") == "accordé" and profile.cash == 5400)
assert(profile.stats.robuxPurchases == 2)
for i = 1, 105 do
    assert(receipt("série" .. i) == "accordé")
end
assert(#profile.robuxReceipts == 100 and #durable.robuxReceipts == 100)
local finalCash = profile.cash
assert(receipt("série105") == "accordé" and profile.cash == finalCash)
assert(profile.stats.robuxPurchases == 107)
print("Robux : tests simulés réussis (gardes, doublons, concurrence, panne, reprise, persistance et borne 100).")
