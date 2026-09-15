--!strict

-- `lune run test-rounds` : règles de production, temps déterministe, aucun service Roblox simulé.
local Rules = require("../src/shared/RoundRules")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local tuning = luau.load(fs.readFile("src/shared/Tuning.luau"), {
    environment = { Vector3 = roblox.Vector3, Color3 = roblox.Color3 },
})()

assert(tuning.ROUND_ACTIVE_SECONDS == 300)
for players = 1, 8 do
    assert(Rules.Goal(players, tuning) == 6 + (players - 1) * 4)
end
local state = Rules.New(1, 100, tuning.ROUND_ACTIVE_SECONDS, 1, tuning)
assert(not Rules.Deposit(state, 1, 99, 10, "Avant", "room"))
assert(Rules.Deposit(state, 1, 100, 10, "Premier", "room"))
assert(not Rules.Deposit(state, 1, 101, 10, "Premier", "stolen"))
assert(not Rules.Deposit(state, 1, 101, 10, "Premier", "saved"))
assert(not Rules.Deposit(state, 1, 101, 10, "Premier", "returned"))
assert(not Rules.Deposit(state, 1, 101, 10, "Premier", nil))
assert(not Rules.Deposit(state, 0, 101, 10, "Premier", "room"))
-- Arrivée tardive puis reconnexion : même entrée par UserId, objectif inchangé.
assert(Rules.Deposit(state, 1, 200, 20, "Arrivée", "room"))
assert(Rules.Deposit(state, 1, 250, 10, "Reconnexion", "room"))
assert(state.entries[10].count == 2 and state.goal == 6)
assert(Rules.Deposit(state, 1, 399.999, 20, "Arrivée", "room"))
assert(not Rules.Deposit(state, 1, 400, 20, "Trop tard", "room"))
assert(not Rules.Deposit(state, 1, 401, 20, "Trop tard", "room"))
local rows = Rules.Rank(state)
assert(#rows == 2 and rows[1].userId == 10 and rows[2].userId == 20)
assert(not Rules.Close(state, 1, 399.999))
assert(not Rules.Close(state, 0, 400))
assert(Rules.Close(state, 1, 400) and not state.won)
assert(not Rules.Close(state, 1, 400))
assert(not Rules.Deposit(state, 1, 300, 20, "Fermée", "room"))
assert(state.total == 4)

local winning = Rules.New(2, 500, 300, 1, tuning)
for _ = 1, 14 do
    assert(Rules.Deposit(winning, 2, 550, 10, "Solo", "room"))
end
-- Objectif dépassé : ni clôture anticipée ni arrêt du compteur de contribution.
assert(winning.total == 14 and winning.endsAt == 800 and not winning.closed)
assert(not Rules.Close(winning, 2, 799))
assert(Rules.Close(winning, 2, 800) and winning.won)
assert(not Rules.Deposit(winning, 1, 550, 10, "Ancienne manche", "room"))

local function reward(count: number, won: boolean, cash: number, xp: number): ()
    local actualCash, actualXp = Rules.Reward(count, won, tuning)
    assert(actualCash == cash and actualXp == xp)
end
reward(0, false, 0, 0)
reward(0, true, 0, 0)
reward(6, false, 600, 30)
reward(6, true, 1500, 80)
reward(12, true, 2700, 140)
reward(14, true, 2700, 140)
reward(1000, false, 1200, 60)
reward(-1, true, 0, 0)

local nextRound = Rules.New(3, 900, 300, 8, tuning)
assert(nextRound.total == 0 and next(nextRound.entries) == nil and nextRound.goal == 34)
assert(not Rules.Close(nextRound, 2, 1300))
assert(not Rules.Deposit(nextRound, 2, 901, 10, "Ancien callback", "room"))
print("Manches : objectifs 1–8, échéances, provenance, reconnexion, rangs, clôture unique et primes vérifiés.")
print("Cycle des services, paiements, portage, abandon serveur vide et interface : à vérifier dans Studio.")
