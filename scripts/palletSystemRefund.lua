-- PalletSystemRefund.lua
-- Rembourse le joueur quand une palette pleine est obtenue via
-- PalletSystem (palette fournie par le joueur), a la place du spawn
-- automatique gratuit du jeu de base.
--
-- S'accroche sur PalletSystem.lua via des hooks optionnels sur la table
-- globale PalletSystemMod (onFreshPalletSpawned, onExistingPalletFillChanged) :
-- aucune dependance dans l'autre sens, PalletSystem.lua fonctionne seul
-- si ce fichier est absent.
--
-- Le remboursement n'est PAS verse en temps reel : il s'accumule par ferme
-- pendant la journee, puis est verse en un seul versement groupe au
-- changement de jour in-game, comme les frais de fonctionnement generaux
-- (entretien, interets d'emprunt).
--
-- Ne concerne QUE les usines (ProductionPoint) : les batiments d'animaux
-- (husbandry) sont explicitement exclus.

PalletSystemRefund = {}

-- Montant rembourse par palette PLEINE, par fillType de sortie (nom du
-- fillType tel qu'expose par g_fillTypeManager, generalement en MAJUSCULES).
-- "default" s'applique a tout fillType non liste ici.
PalletSystemRefund.savingsPerPallet = {
    default = 150,
    -- HONEY = 220,
}

-- Cumul en attente de versement, par ferme. Remis a zero a chaque changement
-- de jour une fois le versement effectue. Purement en memoire (non
-- persiste) : un cumul non encore verse est perdu si la partie est
-- rechargee avant le changement de jour -- limite acceptee pour l'instant,
-- a revoir si besoin de le sauvegarder dans palletSystem.xml.
PalletSystemRefund.pendingSavings = {} -- pendingSavings[farmId] = montant

-- Securite anti double-comptage (table a cles faibles : pas de fuite
-- memoire si la palette est detruite/vendue).
PalletSystemRefund.refundedPallets = setmetatable({}, {__mode = "k"})

PalletSystemRefund.dayChangeListenerRegistered = false


local function getSavingsAmount(fillTypeId)
    local fillType = g_fillTypeManager:getFillTypeByIndex(fillTypeId)
    local name = fillType ~= nil and fillType.name or nil

    if name ~= nil and PalletSystemRefund.savingsPerPallet[name] ~= nil then
        return PalletSystemRefund.savingsPerPallet[name]
    end

    return PalletSystemRefund.savingsPerPallet.default or 0
end


---Accumule le montant dans le cumul de la ferme concernee (pas de versement
-- immediat). Cote serveur uniquement.
local function accumulateRefund(farmId, fillTypeId)
    if g_server == nil or farmId == nil then
        return
    end

    local amount = getSavingsAmount(fillTypeId)
    if amount <= 0 then
        return
    end

    PalletSystemRefund.pendingSavings[farmId] = (PalletSystemRefund.pendingSavings[farmId] or 0) + amount
end


-- Palette generee deja pleine (spawn direct ou PSC) : accumulation immediate,
-- versement differe au changement de jour.
function PalletSystemMod.onFreshPalletSpawned(spawner, pallet, fillTypeId, farmId)
    if spawner.palletSystemType ~= "production" then
        return -- husbandry exclu du remboursement
    end

    if pallet ~= nil then
        if PalletSystemRefund.refundedPallets[pallet] then
            return
        end
        PalletSystemRefund.refundedPallets[pallet] = true
    end

    accumulateRefund(farmId, fillTypeId)
end


-- Palette existante en cours de remplissage : accumulation uniquement au
-- moment ou elle atteint sa capacite max.
function PalletSystemMod.onExistingPalletFillChanged(spawner, pallet, fillTypeId, farmId)
    if spawner.palletSystemType ~= "production" then
        return -- husbandry exclu du remboursement
    end

    if pallet == nil or pallet.spec_pallet == nil or PalletSystemRefund.refundedPallets[pallet] then
        return
    end

    local fillUnitIndex = pallet.spec_pallet.fillUnitIndex
    local fillLevel = pallet:getFillUnitFillLevel(fillUnitIndex)
    local capacity = pallet:getFillUnitCapacity(fillUnitIndex)

    if capacity == nil or capacity <= 0 or fillLevel < capacity then
        return -- pas encore pleine : rien a faire
    end

    PalletSystemRefund.refundedPallets[pallet] = true
    accumulateRefund(farmId, fillTypeId)
end


---Versement groupe de tous les cumuls en attente, un par ferme, puis remise
-- a zero. Appele au changement de jour in-game.
function PalletSystemRefund:dayChanged()
    if g_server == nil then
        return
    end

    for farmId, amount in pairs(PalletSystemRefund.pendingSavings) do
        if amount > 0 then
            g_currentMission:addMoney(amount, farmId, MoneyType.OTHER, true, true)
        end
    end

    PalletSystemRefund.pendingSavings = {}
end


---Enregistrement du listener de changement de jour. Fait au chargement de
-- la mission (comme Mission00.load pour l'UI dans PalletSystem.lua),
-- pour etre sur que g_currentMission.environment existe deja.
local function registerDayChangeListener()
    if PalletSystemRefund.dayChangeListenerRegistered then
        return
    end

    if g_currentMission == nil or g_currentMission.environment == nil
        or g_currentMission.environment.addDayChangeListener == nil then
        return -- pas encore pret, on retentera au prochain appel
    end

    g_currentMission.environment:addDayChangeListener(PalletSystemRefund)
    PalletSystemRefund.dayChangeListenerRegistered = true

    print("  PalletSystemRefund : versement en fin de journee active")
end

Mission00.load = Utils.appendedFunction(Mission00.load, registerDayChangeListener)


print("  PalletSystemRefund : module de remise charge")