-- PalletSystem.lua
-- Oblige les productions (ProductionPoint) et les batiments d'animaux (Husbandry)
-- a consommer une unite du fillType EMPTYPALLET avant de pouvoir faire apparaitre
-- une palette pleine. L'EMPTYPALLET doit etre fourni par un mod separe (fillType +
-- palette-conteneur), livre a l'emplacement de spawn natif (spawnPlaces) de la
-- production/husbandry ciblee.
--
-- Principe :
--   PalletSpawner:getOrSpawnPallet() cherche d'abord une palette existante non
--   pleine dans sa zone de spawn ; si aucune n'est trouvee, il appelle
--   PalletSpawner:spawnPallet() qui cree une palette pleine a partir de rien.
--   On intercepte cette derniere fonction pour exiger la consommation d'une
--   unite d'EMPTYPALLET avant d'autoriser la creation.

PalletSystemMod = {}

-- Nom du fillType a definir dans ton mod "fabricant" de palettes vides.
PalletSystemMod.EMPTY_PALLET_FILLTYPE_NAME = "EMPTYPALLET"

PalletSystemMod.foundStockPallet = nil
PalletSystemMod.cachedEmptyPalletFillTypeId = nil
PalletSystemMod.warnedSpawners = {} -- warnedSpawners[spawner][fillTypeId] = true

-- ============================================================
-- Reglages (interrupteur global + activation par batiment), persistes
-- dans un fichier XML du dossier de sauvegarde.
-- ============================================================
PalletSystemMod.settings = {
    enabledHusbandry = false,   -- desactive par defaut : obligation pour les batiments d'animaux
    enabledProduction = false,  -- desactive par defaut : obligation pour les usines (ProductionPoint)
    disabledIds = {},      -- disabledIds[palletSystemId] = true -> ce batiment est exclu de l'obligation
    numbering = {},        -- numbering[palletSystemId] = numero court (stable, persiste)
    numberToId = {},       -- numberToId[numero] = palletSystemId (table inverse, pour psToggleSpawner)
    nextNumber = 1,
}
PalletSystemMod.settingsLoaded = false
PalletSystemMod.knownSpawners = {} -- id -> spawner, pour psList
PalletSystemMod.placeablesEntries = nil -- cache du placeables.xml de la sauvegarde (charge une fois)

-- Schema XML requis par XMLFile.create/load (meme pattern que schema:register
-- utilise partout ailleurs dans le moteur, ex. PalletSpawner.registerXMLPaths).
PalletSystemMod.xmlSchema = XMLSchema.new("palletSystem")
PalletSystemMod.xmlSchema:register(XMLValueType.BOOL, "palletSystem#enabledHusbandry", "Obligation active pour les batiments d'animaux", false)
PalletSystemMod.xmlSchema:register(XMLValueType.BOOL, "palletSystem#enabledProduction", "Obligation active pour les usines", false)
PalletSystemMod.xmlSchema:register(XMLValueType.STRING, "palletSystem.disabled.entry(?)#id", "Identifiant du batiment desactive")
PalletSystemMod.xmlSchema:register(XMLValueType.STRING, "palletSystem.numbering.entry(?)#id", "Identifiant interne du batiment")
PalletSystemMod.xmlSchema:register(XMLValueType.INT, "palletSystem.numbering.entry(?)#number", "Numero court associe a ce batiment")
PalletSystemMod.xmlSchema:register(XMLValueType.STRING, "palletSystem.numbering.entry(?)#name", "Nom du batiment (indicatif, non relu au chargement)")
PalletSystemMod.xmlSchema:register(XMLValueType.STRING, "palletSystem.numbering.entry(?)#type", "Type husbandry/production (indicatif, non relu au chargement)")
PalletSystemMod.xmlSchema:register(XMLValueType.STRING, "palletSystem.numbering.entry(?)#status", "Statut actif/desactive au moment de la sauvegarde (indicatif, non relu au chargement)")

-- Schema minimal pour lire le placeables.xml DE LA SAUVEGARDE (fichier du jeu,
-- pas le notre) : on ne lit que filename/position/farmId sur chaque <placeable>.
PalletSystemMod.placeablesXmlSchema = XMLSchema.new("psPlaceables")
PalletSystemMod.placeablesXmlSchema:register(XMLValueType.STRING, "placeables.placeable(?)#filename", "")
PalletSystemMod.placeablesXmlSchema:register(XMLValueType.STRING, "placeables.placeable(?)#position", "")
PalletSystemMod.placeablesXmlSchema:register(XMLValueType.INT, "placeables.placeable(?)#farmId", "")


---Chemin du fichier de reglages. Stocke dans modSettings/ (zone dediee aux
-- reglages de mods) plutot que directement dans le dossier de la sauvegarde :
-- confirme par test en jeu, le processus de sauvegarde manuelle regenere le
-- dossier savegameX et supprime tout fichier custom qui s'y trouverait. Un
-- fichier distinct par sauvegarde est conserve en utilisant le nom du dossier
-- (savegame4, savegame5...) comme identifiant, pour garder des reglages
-- separes par partie malgre le changement d'emplacement.
-- @return string|nil path
local function getSettingsFilePath()
    if g_currentMission == nil or g_currentMission.missionInfo == nil
        or g_currentMission.missionInfo.savegameDirectory == nil then
        return nil
    end

    local savegameFolderName = g_currentMission.missionInfo.savegameDirectory:match("([^/\\]+)[/\\]?$")
    if savegameFolderName == nil then
        return nil
    end

    local folder = getUserProfileAppPath() .. "modSettings/FS25_PalletSystem"
    createFolder(folder)

    return folder .. "/" .. savegameFolderName .. ".xml"
end


---Charge les reglages depuis le fichier XML de la sauvegarde (une fois par
-- session). Ne se marque "charge" que si le chemin de sauvegarde est
-- effectivement disponible, pour pouvoir reessayer plus tard sinon (evite
-- de rester bloque sur les valeurs par defaut si appele trop tot, ce qui
-- ecraserait ensuite les reglages reels avec des valeurs vides).
local function loadSettings()
    if PalletSystemMod.settingsLoaded then
        return
    end

    local path = getSettingsFilePath()
    if path == nil then
        return -- sauvegarde pas encore prete, on retentera au prochain appel
    end

    PalletSystemMod.settingsLoaded = true -- a partir d'ici, le chemin est valide

    if not fileExists(path) then
        return -- pas de reglages existants pour cette sauvegarde, defauts conserves
    end

    local xmlFile = XMLFile.load("psSettings", path, PalletSystemMod.xmlSchema)
    if xmlFile == nil then
        return
    end

    PalletSystemMod.settings.enabledHusbandry = xmlFile:getValue("palletSystem#enabledHusbandry", false)
    PalletSystemMod.settings.enabledProduction = xmlFile:getValue("palletSystem#enabledProduction", false)

    PalletSystemMod.settings.disabledIds = {}
    for _, entryKey in xmlFile:iterator("palletSystem.disabled.entry") do
        local id = xmlFile:getValue(entryKey .. "#id")
        if id ~= nil then
            PalletSystemMod.settings.disabledIds[id] = true
        end
    end

    PalletSystemMod.settings.numbering = {}
    PalletSystemMod.settings.numberToId = {}
    local maxNumber = 0
    for _, entryKey in xmlFile:iterator("palletSystem.numbering.entry") do
        local id = xmlFile:getValue(entryKey .. "#id")
        local number = xmlFile:getValue(entryKey .. "#number")
        if id ~= nil and number ~= nil then
            PalletSystemMod.settings.numbering[id] = number
            PalletSystemMod.settings.numberToId[number] = id
            if number > maxNumber then
                maxNumber = number
            end
        end
    end
    PalletSystemMod.settings.nextNumber = maxNumber + 1

    xmlFile:delete()

    print(string.format("  PalletSystem : reglages charges (husbandry=%s, production=%s)",
        tostring(PalletSystemMod.settings.enabledHusbandry), tostring(PalletSystemMod.settings.enabledProduction)))
end


---Resout le nom d'affichage boutique d'un batiment a partir de son fichier XML,
-- via le store manager (deja resolu/traduit par le jeu, pas besoin de reparser
-- de XML nous-memes).
-- @param table spawner instance de PalletSpawner
-- @return string name
local function getFriendlyName(spawner)
    local filename = spawner.palletSystemFilename
    if filename ~= nil and g_storeManager ~= nil then
        local storeItem = g_storeManager:getItemByXMLFilename(filename)
        if storeItem ~= nil and storeItem.name ~= nil then
            return storeItem.name
        end
    end
    return filename or "?"
end


---Sauvegarde les reglages actuels dans le fichier XML de la sauvegarde.
local function saveSettings()
    local path = getSettingsFilePath()
    if path == nil then
        print("  [PS-save-debug] echec : chemin de sauvegarde indisponible (savegameDirectory non pret)")
        return
    end

    local xmlFile = XMLFile.create("psSettings", path, "palletSystem", PalletSystemMod.xmlSchema)
    if xmlFile == nil then
        print(string.format("  [PS-save-debug] echec : XMLFile.create a renvoye nil pour '%s'", path))
        return
    end

    xmlFile:setValue("palletSystem#enabledHusbandry", PalletSystemMod.settings.enabledHusbandry)
    xmlFile:setValue("palletSystem#enabledProduction", PalletSystemMod.settings.enabledProduction)

    local i = 0
    for id, isDisabled in pairs(PalletSystemMod.settings.disabledIds) do
        if isDisabled then
            local entryKey = string.format("palletSystem.disabled.entry(%d)", i)
            xmlFile:setValue(entryKey .. "#id", id)
            i = i + 1
        end
    end

    local j = 0
    for id, number in pairs(PalletSystemMod.settings.numbering) do
        local entryKey = string.format("palletSystem.numbering.entry(%d)", j)
        xmlFile:setValue(entryKey .. "#id", id)
        xmlFile:setValue(entryKey .. "#number", number)

        -- Infos indicatives uniquement (non relues au chargement), pour que
        -- le fichier soit lisible directement sans passer par psList.
        local spawner = PalletSystemMod.knownSpawners[id]
        if spawner ~= nil then
            xmlFile:setValue(entryKey .. "#name", getFriendlyName(spawner))
            xmlFile:setValue(entryKey .. "#type", spawner.palletSystemType or "?")

            local typeEnabled = spawner.palletSystemType == "husbandry"
                and PalletSystemMod.settings.enabledHusbandry or PalletSystemMod.settings.enabledProduction
            local isDisabledIndividually = PalletSystemMod.settings.disabledIds[id] == true
            local status
            if typeEnabled and not isDisabledIndividually then
                status = "actif"
            elseif isDisabledIndividually then
                status = "desactive (batiment)"
            else
                status = "desactive (type)"
            end
            xmlFile:setValue(entryKey .. "#status", status)
        end

        j = j + 1
    end

    xmlFile:save()
    xmlFile:delete()

    print(string.format("  [PS-save-debug] ecriture terminee vers '%s' -- fichier present sur disque = %s",
        path, tostring(fileExists(path))))
end


---Determine si l'obligation de palette s'applique a ce spawner precis
-- (en tenant compte de son type : husbandry ou production).
-- @param table spawner instance de PalletSpawner
-- @return boolean applies
local function isRequirementActiveFor(spawner)
    loadSettings()

    local typeEnabled
    if spawner.palletSystemType == "husbandry" then
        typeEnabled = PalletSystemMod.settings.enabledHusbandry
    else
        typeEnabled = PalletSystemMod.settings.enabledProduction
    end

    if not typeEnabled then
        return false
    end

    local id = spawner.palletSystemId
    if id ~= nil and PalletSystemMod.settings.disabledIds[id] then
        return false
    end

    return true
end


---Attribue (ou recupere) un numero court et stable pour un identifiant de batiment donne.
-- Le numero est persiste dans le fichier de reglages, donc reste identique
-- d'une session a l'autre pour le meme batiment.
-- @param string id identifiant interne (fichier + position)
-- @return integer number
local function getOrAssignNumber(id)
    loadSettings()

    local number = PalletSystemMod.settings.numbering[id]
    if number == nil then
        number = PalletSystemMod.settings.nextNumber
        PalletSystemMod.settings.nextNumber = number + 1
        PalletSystemMod.settings.numbering[id] = number
        PalletSystemMod.settings.numberToId[number] = id
        saveSettings()
    end

    return number
end


---Lit le placeables.xml DE LA SAUVEGARDE en cours (liste de tous les batiments
-- places, avec leur fichier XML, leur position et leur ferme proprietaire).
-- Mis en cache pour la session (le fichier ne change pas pendant qu'on joue).
-- @return table entries liste de {filename=, x=, y=, z=, farmId=}
local function loadPlaceablesEntries()
    if PalletSystemMod.placeablesEntries ~= nil then
        return PalletSystemMod.placeablesEntries
    end

    PalletSystemMod.placeablesEntries = {}

    if g_currentMission == nil or g_currentMission.missionInfo == nil
        or g_currentMission.missionInfo.savegameDirectory == nil then
        return PalletSystemMod.placeablesEntries
    end

    local path = g_currentMission.missionInfo.savegameDirectory .. "/placeables.xml"
    if not fileExists(path) then
        return PalletSystemMod.placeablesEntries
    end

    local xmlFile = XMLFile.load("psPlaceables", path, PalletSystemMod.placeablesXmlSchema)
    if xmlFile == nil then
        return PalletSystemMod.placeablesEntries
    end

    for _, key in xmlFile:iterator("placeables.placeable") do
        local filename = xmlFile:getValue(key .. "#filename")
        local posStr = xmlFile:getValue(key .. "#position")
        local farmId = xmlFile:getValue(key .. "#farmId")

        if filename ~= nil and posStr ~= nil and farmId ~= nil then
            local xStr, yStr, zStr = posStr:match("^(%S+)%s+(%S+)%s+(%S+)$")
            local x, y, z = tonumber(xStr), tonumber(yStr), tonumber(zStr)
            if x ~= nil then
                table.insert(PalletSystemMod.placeablesEntries,
                    {filename = filename, x = x, y = y, z = z, farmId = farmId})
            end
        end
    end

    xmlFile:delete()

    return PalletSystemMod.placeablesEntries
end


---Determine le farmId proprietaire d'un spawner en le recoupant avec le
-- placeables.xml de la sauvegarde : on cherche, parmi les batiments du meme
-- fichier XML, celui dont la position est la plus proche de la zone de spawn.
-- @param table spawner instance de PalletSpawner
-- @return integer|nil farmId
local function resolveFarmIdFromPlaceablesXml(spawner)
    local filename = spawner.palletSystemFilename
    if filename == nil or spawner.spawnPlaces == nil or spawner.spawnPlaces[1] == nil then
        return nil
    end

    local refX = spawner.spawnPlaces[1].startX
    local refY = spawner.spawnPlaces[1].startY
    local refZ = spawner.spawnPlaces[1].startZ

    local entries = loadPlaceablesEntries()
    local best, bestDistSq = nil, math.huge

    for _, entry in ipairs(entries) do
        if entry.filename == filename then
            local dx, dy, dz = entry.x - refX, entry.y - refY, entry.z - refZ
            local distSq = dx * dx + dy * dy + dz * dz
            if distSq < bestDistSq then
                bestDistSq = distSq
                best = entry
            end
        end
    end

    if best ~= nil then
        return best.farmId
    end

    return nil
end


-- ============================================================
-- Overwrite de PalletSpawner:load
-- ============================================================
-- Calcule un identifiant stable par batiment (fichier XML + position
-- approximative), utilise pour l'activation/desactivation individuelle et
-- pour la commande console psList.

PalletSystemMod.originalPalletSpawnerLoad = PalletSpawner.load

function PalletSpawner:load(components, xmlFile, key, customEnv, i3dMappings)
    local ok = PalletSystemMod.originalPalletSpawnerLoad(self, components, xmlFile, key, customEnv, i3dMappings)

    if ok then
        local filename = "unknown"
        if xmlFile ~= nil and xmlFile.getFilename ~= nil then
            filename = xmlFile:getFilename() or filename
        end

        local posKey = "0_0_0"
        if self.spawnPlaces ~= nil and self.spawnPlaces[1] ~= nil then
            local p = self.spawnPlaces[1]
            posKey = string.format("%d_%d_%d", math.floor(p.startX or 0), math.floor(p.startY or 0), math.floor(p.startZ or 0))
        end

        self.palletSystemFilename = filename
        self.palletSystemId = filename .. "#" .. posKey
        self.palletSystemFarmId = resolveFarmIdFromPlaceablesXml(self)

        -- Detection du type (husbandry vs production) via le chemin XML utilise
        -- pour charger ce spawner. Heuristique par mot-cle : pas de confirmation
        -- 100% certaine du chemin exact cote husbandry (registerXMLPaths non
        -- disponible), a verifier au test -> si mal categorise, le voir dans psList.
        if key ~= nil and key:lower():find("husbandry") then
            self.palletSystemType = "husbandry"
        else
            self.palletSystemType = "production"
        end

        -- IMPORTANT : renseigner knownSpawners AVANT getOrAssignNumber, car ce
        -- dernier peut declencher une sauvegarde immediate (nouveau batiment) qui
        -- a besoin de retrouver ce spawner pour ecrire nom/type/statut indicatifs.
        PalletSystemMod.knownSpawners[self.palletSystemId] = self
        self.palletSystemNumber = getOrAssignNumber(self.palletSystemId)
    end

    return ok
end


---Recupere (et met en cache) l'index du fillType EMPTYPALLET.
-- @return integer|nil fillTypeId
local function getEmptyPalletFillTypeId()
    if PalletSystemMod.cachedEmptyPalletFillTypeId ~= nil then
        return PalletSystemMod.cachedEmptyPalletFillTypeId
    end

    if g_fillTypeManager == nil then
        return nil
    end

    local fillTypeId = g_fillTypeManager:getFillTypeIndexByName(PalletSystemMod.EMPTY_PALLET_FILLTYPE_NAME)
    if fillTypeId ~= nil then
        PalletSystemMod.cachedEmptyPalletFillTypeId = fillTypeId
    end

    return fillTypeId
end


---Callback d'overlapBox : retient la premiere palette-conteneur d'EMPTYPALLET
-- avec du contenu trouvee dans la zone scannee.
-- IMPORTANT : declaree avec ':' (et non '.') pour recevoir correctement
-- (self, node) comme overlapBox les fournit.
-- @param integer node id du noeud detecte
function PalletSystemMod:onFindStockPallet(node)
    local object = g_currentMission.nodeToObject[node]
    if object == nil or object.isa == nil or not object:isa(Vehicle) or not object.isPallet then
        return
    end

    local emptyPalletId = getEmptyPalletFillTypeId()
    if emptyPalletId == nil then
        return
    end

    local fillUnitIndex = object.spec_pallet.fillUnitIndex
    if object:getFillUnitFillType(fillUnitIndex) == emptyPalletId
        and object:getFillUnitFillLevel(fillUnitIndex) > 0 then
        self.foundStockPallet = object
        return false -- arrete le scan, on a trouve
    end
end


---Cherche une palette-conteneur d'EMPTYPALLET dans la zone de spawn du
-- palletSpawner donne, et lui retire une unite si trouvee.
-- @param table spawner instance de PalletSpawner
-- @param integer fillTypeId fillType de sortie concerne (miel, oeufs, pain, ...)
-- @param integer farmId ferme proprietaire de la production/husbandry
-- @return boolean success true si une unite a bien ete consommee
local function tryConsumeEmptyPalletUnit(spawner, fillTypeId, farmId)
    local emptyPalletId = getEmptyPalletFillTypeId()
    if emptyPalletId == nil then
        -- Le fillType EMPTYPALLET n'existe pas (mod fabricant absent/non charge) :
        -- on ne bloque pas la production dans ce cas, sinon plus rien ne
        -- fonctionnerait tant que ce mod annexe n'est pas installe.
        return true
    end

    PalletSystemMod.foundStockPallet = nil

    local spawnPlaces = spawner.fillTypeToSpawnPlaces[fillTypeId] or spawner.spawnPlaces
    for i = 1, #spawnPlaces do
        local place = spawnPlaces[i]
        local x = place.startX + place.width / 2 * place.dirX
        local y = place.startY + place.width / 2 * place.dirY
        local z = place.startZ + place.width / 2 * place.dirZ
        overlapBox(x, y, z, place.rotX, place.rotY, place.rotZ, place.width / 2, 1, 1,
            "onFindStockPallet", PalletSystemMod,
            CollisionFlag.VEHICLE + CollisionFlag.DYNAMIC_OBJECT, true, true, false, true)
    end

    local stock = PalletSystemMod.foundStockPallet
    if stock == nil then
        return false
    end

    local fillUnitIndex = stock.spec_pallet.fillUnitIndex
    local delta = stock:addFillUnitFillLevel(farmId, fillUnitIndex, -1, emptyPalletId, ToolType.UNDEFINED)

    return delta ~= 0
end


---Affiche une notification in-game (une seule fois par couple spawner+fillType
-- tant que le probleme n'est pas resolu, pour ne pas spammer).
-- @param table spawner instance de PalletSpawner concernee
-- @param integer fillTypeId fillType de sortie bloque
local function showBlockedNotification(spawner, fillTypeId)
    PalletSystemMod.warnedSpawners[spawner] = PalletSystemMod.warnedSpawners[spawner] or {}
    if PalletSystemMod.warnedSpawners[spawner][fillTypeId] then
        return
    end
    PalletSystemMod.warnedSpawners[spawner][fillTypeId] = true

    if g_currentMission == nil then
        return
    end

    local fillType = g_fillTypeManager:getFillTypeByIndex(fillTypeId)
    local fillTypeTitle = fillType ~= nil and fillType.title or "?"

    local text = string.format(
        g_i18n:hasText("ps_ingameNotification_palletRequired")
            and g_i18n:getText("ps_ingameNotification_palletRequired")
            or "Palette vide requise pour produire : %s",
        fillTypeTitle)

    g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, text)
end


-- ============================================================
-- Overwrite de PalletSpawner:spawnPallet
-- ============================================================
-- Appele uniquement quand getOrSpawnPallet n'a trouve AUCUNE palette
-- existante non pleine dans la zone de spawn : c'est le moment ou le jeu
-- s'appreterait a creer une palette pleine a partir de rien.

PalletSystemMod.originalSpawnPallet = PalletSpawner.spawnPallet

function PalletSpawner:spawnPallet(farmId, fillTypeId, callback, callbackTarget)
    self.palletSystemFarmId = farmId

    if not isRequirementActiveFor(self) then
        PalletSystemMod.originalSpawnPallet(self, farmId, fillTypeId, callback, callbackTarget)
        return
    end

    -- La consommation ne doit se decider que sur le serveur (source de verite
    -- pour l'etat des fillLevels). Sur un client distant, on laisse faire
    -- le comportement d'origine ; le serveur est de toute facon seul maitre
    -- de la file de spawn (spawnQueue).
    if g_server == nil then
        PalletSystemMod.originalSpawnPallet(self, farmId, fillTypeId, callback, callbackTarget)
        return
    end

    if tryConsumeEmptyPalletUnit(self, fillTypeId, farmId) then
        if PalletSystemMod.warnedSpawners[self] then
            PalletSystemMod.warnedSpawners[self][fillTypeId] = nil
        end
        PalletSystemMod.originalSpawnPallet(self, farmId, fillTypeId, callback, callbackTarget)
    else
        showBlockedNotification(self, fillTypeId)
        callback(callbackTarget, nil, PalletSpawner.RESULT_NO_SPACE, fillTypeId)
    end
end


-- ============================================================
-- Overwrite de PalletSpawner:getOrSpawnPallet
-- ============================================================
-- Uniquement pour reinitialiser l'avertissement des qu'une palette existante
-- (donc non vide) est retrouvee, signe que le joueur a livre du stock.

PalletSystemMod.originalGetOrSpawnPallet = PalletSpawner.getOrSpawnPallet

function PalletSpawner:getOrSpawnPallet(farmId, fillTypeId, callback, callbackTarget)
    self.palletSystemFarmId = farmId

    PalletSystemMod.originalGetOrSpawnPallet(self, farmId, fillTypeId, callback, callbackTarget)

    if self.foundExistingPallet ~= nil then
        if PalletSystemMod.warnedSpawners[self] then
            PalletSystemMod.warnedSpawners[self][fillTypeId] = nil
        end
    end
end


print("  PalletSystem : mod charge (fillType requis = " .. PalletSystemMod.EMPTY_PALLET_FILLTYPE_NAME .. ")")


-- ============================================================
-- Commandes console
-- ============================================================

---psToggleHusbandry [0|1] : active/desactive l'obligation pour les batiments d'animaux. Sans argument, bascule.
function PalletSystemMod:consoleToggleHusbandry(arg)
    if arg ~= nil and arg ~= "" and arg ~= "0" and arg ~= "1" then
        return "Usage : psToggleHusbandry [0|1] -- sans argument, bascule l'etat actuel. Pour un batiment precis, utilise psToggleSpawner <numero> [0|1]."
    end

    loadSettings()

    if arg == "0" then
        self.settings.enabledHusbandry = false
    elseif arg == "1" then
        self.settings.enabledHusbandry = true
    else
        self.settings.enabledHusbandry = not self.settings.enabledHusbandry
    end

    saveSettings()
    return string.format("Palettes obligatoires (animaux) : %s", self.settings.enabledHusbandry and "ACTIVE" or "DESACTIVE")
end
addConsoleCommand("psToggleHusbandry", "Active/desactive l'obligation de palette pour les batiments d'animaux (0/1, ou bascule si vide)", "consoleToggleHusbandry", PalletSystemMod)


---psToggleProduction [0|1] : active/desactive l'obligation pour les usines. Sans argument, bascule.
function PalletSystemMod:consoleToggleProduction(arg)
    if arg ~= nil and arg ~= "" and arg ~= "0" and arg ~= "1" then
        return "Usage : psToggleProduction [0|1] -- sans argument, bascule l'etat actuel. Pour un batiment precis, utilise psToggleSpawner <numero> [0|1]."
    end

    loadSettings()

    if arg == "0" then
        self.settings.enabledProduction = false
    elseif arg == "1" then
        self.settings.enabledProduction = true
    else
        self.settings.enabledProduction = not self.settings.enabledProduction
    end

    saveSettings()
    return string.format("Palettes obligatoires (usines) : %s", self.settings.enabledProduction and "ACTIVE" or "DESACTIVE")
end
addConsoleCommand("psToggleProduction", "Active/desactive l'obligation de palette pour les usines (0/1, ou bascule si vide)", "consoleToggleProduction", PalletSystemMod)


---psList [farmId] : liste les productions/husbandries detectees, avec leur nom,
-- leur type, leur ferme proprietaire, leur etat REEL (= interrupteur du type
-- concerne ET pas desactive individuellement), et l'identifiant a utiliser
-- avec psToggleSpawner.
-- Sans argument, affiche tous les batiments toutes fermes confondues.
function PalletSystemMod:consoleListSpawners(farmIdFilter)
    loadSettings()
    farmIdFilter = tonumber(farmIdFilter)

    local lines = {
        string.format("PalletSystem - animaux = %s, usines = %s",
            self.settings.enabledHusbandry and "ACTIVE" or "DESACTIVE",
            self.settings.enabledProduction and "ACTIVE" or "DESACTIVE")
    }
    local count = 0

    for id, spawner in pairs(self.knownSpawners) do
        local farmId = spawner.palletSystemFarmId
        if farmIdFilter == nil or farmId == farmIdFilter then
            count = count + 1

            local typeLabel = spawner.palletSystemType == "husbandry" and "animaux" or "usine"
            local typeEnabled = spawner.palletSystemType == "husbandry"
                and self.settings.enabledHusbandry or self.settings.enabledProduction
            local isDisabledIndividually = self.settings.disabledIds[id] == true
            local isActive = typeEnabled and not isDisabledIndividually

            local state
            if isActive then
                state = "actif"
            elseif isDisabledIndividually then
                state = "DESACTIVE (batiment)"
            else
                state = "DESACTIVE (type " .. typeLabel .. ")"
            end

            local name = getFriendlyName(spawner)
            local farmLabel = farmId ~= nil and tostring(farmId) or "inconnue (non trouvee dans placeables.xml)"

            table.insert(lines, string.format("  #%d [%s] %s - %s (ferme %s)", spawner.palletSystemNumber, state, name, typeLabel, farmLabel))
        end
    end

    if count == 0 then
        table.insert(lines, "  (aucun batiment trouve" .. (farmIdFilter ~= nil and (" pour la ferme " .. farmIdFilter) or "") .. ")")
    end

    return table.concat(lines, "\n")
end
addConsoleCommand("psList", "Liste les productions/husbandries detectees (psList [farmId] pour filtrer)", "consoleListSpawners", PalletSystemMod)


---psToggleSpawner <numero> [0|1] : active/desactive l'obligation pour un batiment precis (numero via psList).
function PalletSystemMod:consoleToggleSpawner(numberArg, arg)
    local number = tonumber(numberArg)
    if number == nil then
        return "Usage : psToggleSpawner <numero> [0|1] -- utilise psList pour voir les numeros"
    end

    loadSettings()

    local id = self.settings.numberToId[number]
    if id == nil then
        return string.format("Aucun batiment avec le numero %d (utilise psList pour voir les numeros valides)", number)
    end

    local isCurrentlyDisabled = self.settings.disabledIds[id] == true
    local shouldDisable
    if arg == "0" then
        shouldDisable = false
    elseif arg == "1" then
        shouldDisable = true
    else
        shouldDisable = not isCurrentlyDisabled
    end

    self.settings.disabledIds[id] = shouldDisable or nil
    saveSettings()

    return string.format("Batiment #%d : %s", number, shouldDisable and "DESACTIVE (pas d'obligation de palette)" or "ACTIF (obligation de palette)")
end
addConsoleCommand("psToggleSpawner", "Active/desactive l'obligation pour un batiment precis (numero via psList)", "consoleToggleSpawner", PalletSystemMod)


---psCheckFile : verifie a la demande si le fichier de reglages existe reellement
-- sur disque, avec son chemin complet. Utile pour tester juste apres avoir
-- sauvegarde manuellement dans le jeu (Echap > Sauvegarder).
function PalletSystemMod:consoleCheckFile()
    local path = getSettingsFilePath()
    if path == nil then
        return "savegameDirectory indisponible pour l'instant"
    end
    return string.format("Chemin attendu : %s\nExiste sur disque : %s", path, tostring(fileExists(path)))
end
addConsoleCommand("psCheckFile", "Verifie si palletSystem.xml existe reellement sur disque", "consoleCheckFile", PalletSystemMod)


-- ============================================================
-- Section dans l'onglet Reglages du jeu (deux cases a cocher)
-- ============================================================
-- Pattern repris d'un mod tiers fonctionnel (Field Gulls / BirdSettings) :
-- on clone un controle existant (multiVolumeVoiceBox) et un en-tete de
-- section existant, plutot que de construire une interface from scratch.
-- Le reglage par batiment individuel reste gere via psToggleSpawner (liste
-- dynamique, peu adaptee a des lignes de menu fixes).

PalletSystemUI = {}
PalletSystemUI.CONTROLS = {}


---Assigne recursivement un focusId a un element et ses enfants (necessaire
-- car clone() copie les focusId d'origine, qui doivent rester uniques).
-- @param table element element GUI
local function updatePalletSystemFocusIds(element)
    if element == nil then
        return
    end
    element.focusId = FocusManager:serveAutoFocusId()
    for _, child in pairs(element.elements) do
        updatePalletSystemFocusIds(child)
    end
end


---Callback commun aux deux cases a cocher.
-- @param table self cible (PalletSystemUI, via menuMultiOption.target)
-- @param integer state 1=desactive, 2=active
-- @param table menuOption l'element qui a declenche le changement (fourni par le moteur)
function PalletSystemUI.onToggleHusbandryChanged(self, state)
    PalletSystemMod.settings.enabledHusbandry = (state == 2)
    saveSettings()
end


---Callback pour la case usines.
function PalletSystemUI.onToggleProductionChanged(self, state)
    PalletSystemMod.settings.enabledProduction = (state == 2)
    saveSettings()
end


---Cree une ligne de case a cocher (clone de multiVolumeVoiceBox) et l'insere
-- dans la page Reglages.
-- @param table settingsPage page Reglages du jeu
-- @param string idSuffix suffixe unique pour les id d'element
-- @param string labelText texte affiche a cote de la case
-- @param string tooltipText texte d'infobulle
-- @param string callbackName nom du callback (methode de PalletSystemUI)
-- @param boolean initialState valeur actuelle (true=active)
-- @return table menuMultiOption l'element cree
local function createToggleRow(settingsPage, idSuffix, labelText, tooltipText, callbackName, initialState)
    local originalBox = settingsPage.multiVolumeVoiceBox
    local menuOptionBox = originalBox:clone(settingsPage.gameSettingsLayout)
    menuOptionBox.id = "palletSystem" .. idSuffix .. "Box"

    local menuMultiOption = menuOptionBox.elements[1]
    menuMultiOption.id = "palletSystem" .. idSuffix
    menuMultiOption.target = PalletSystemUI

    menuMultiOption:setCallback("onClickCallback", callbackName)
    menuMultiOption:setDisabled(false)

    local toolTip = menuMultiOption.elements[1]
    toolTip:setText(tooltipText)

    local labelElement = menuOptionBox.elements[2]
    labelElement:setText(labelText)

    menuMultiOption:setTexts({g_i18n:getText("ui_off"), g_i18n:getText("ui_on")})
    menuMultiOption:setState(initialState and 2 or 1)

    updatePalletSystemFocusIds(menuOptionBox)
    table.insert(settingsPage.controlsList, menuOptionBox)

    return menuMultiOption
end


---Construit et insere la section (en-tete + deux cases) dans l'onglet
-- Reglages du jeu. Accroche sur Mission00.load, comme le mod de reference.
function PalletSystemUI.addSettingsToMenu()
    loadSettings()

    local inGameMenu = g_gui.screenControllers[InGameMenu]
    if inGameMenu == nil or inGameMenu.pageSettings == nil then
        print("  PalletSystem : page Reglages introuvable, section non ajoutee")
        return
    end

    local settingsPage = inGameMenu.pageSettings
    if settingsPage.multiVolumeVoiceBox == nil or settingsPage.gameSettingsLayout == nil then
        print("  PalletSystem : structure de la page Reglages inattendue (multiVolumeVoiceBox introuvable), section non ajoutee")
        return
    end

    -- Le nom est necessaire, sinon le FocusManager ignore les controles dont
    -- la cible n'est pas reconnue.
    PalletSystemUI.CONTROLS.name = settingsPage.name

    -- En-tete de section : on cherche un element "sectionHeader" existant a
    -- cloner (meme pattern que BirdSettings) ; sinon on en cree un via le
    -- profil natif fs25_settingsSectionHeader.
    local sectionTitle = nil
    for _, elem in ipairs(settingsPage.gameSettingsLayout.elements) do
        if elem.name == "sectionHeader" then
            sectionTitle = elem:clone(settingsPage.gameSettingsLayout)
            break
        end
    end

    if sectionTitle then
        sectionTitle:setText("Palettes obligatoires")
    else
        sectionTitle = TextElement.new()
        sectionTitle:applyProfile("fs25_settingsSectionHeader", true)
        sectionTitle:setText("Palettes obligatoires")
        sectionTitle.name = "sectionHeader"
        settingsPage.gameSettingsLayout:addElement(sectionTitle)
    end
    sectionTitle.focusId = FocusManager:serveAutoFocusId()
    table.insert(settingsPage.controlsList, sectionTitle)
    PalletSystemUI.CONTROLS.sectionHeader = sectionTitle

    -- Case 1 : animaux (husbandry)
    local husbandryToggle = createToggleRow(settingsPage, "EnabledHusbandry",
        "Palettes obligatoires - Animaux",
        "Oblige a fournir des palettes vides pour obtenir les produits des batiments d'animaux (laine, oeufs, miel...).",
        "onToggleHusbandryChanged",
        PalletSystemMod.settings.enabledHusbandry)
    PalletSystemUI.CONTROLS.toggleHusbandry = husbandryToggle

    -- Case 2 : usines (production)
    local productionToggle = createToggleRow(settingsPage, "EnabledProduction",
        "Palettes obligatoires - Usines",
        "Oblige a fournir des palettes vides pour obtenir les produits des usines de transformation.",
        "onToggleProductionChanged",
        PalletSystemMod.settings.enabledProduction)
    PalletSystemUI.CONTROLS.toggleProduction = productionToggle

    settingsPage.gameSettingsLayout:invalidateLayout()

    print("  PalletSystem : section ajoutee a l'onglet Reglages")
end


-- Enregistrement aupres du FocusManager pour la navigation clavier/manette,
-- uniquement quand la page Reglages s'ouvre.
FocusManager.setGui = Utils.appendedFunction(FocusManager.setGui, function(_, gui)
    if gui == "ingameMenuSettings" then
        for _, control in pairs(PalletSystemUI.CONTROLS) do
            if type(control) == "table" and control.focusId ~= nil then
                if not FocusManager.currentFocusData.idToElementMapping[control.focusId] then
                    FocusManager:loadElementFromCustomValues(control, nil, nil, false, false)
                end
            end
        end

        local inGameMenu = g_gui.screenControllers[InGameMenu]
        if inGameMenu ~= nil and inGameMenu.pageSettings ~= nil then
            inGameMenu.pageSettings.gameSettingsLayout:invalidateLayout()
        end
    end
end)


-- Ajout de la section au chargement de la mission.
Mission00.load = Utils.appendedFunction(Mission00.load, PalletSystemUI.addSettingsToMenu)


-- Rafraichit l'etat affiche des deux cases a chaque ouverture de l'onglet
-- Reglages, au cas ou les valeurs auraient change entre-temps via console
-- (psToggleHusbandry / psToggleProduction) plutot que via le menu lui-meme.
InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(InGameMenuSettingsFrame.onFrameOpen, function()
    loadSettings()

    if PalletSystemUI.CONTROLS.toggleHusbandry ~= nil then
        PalletSystemUI.CONTROLS.toggleHusbandry:setState(PalletSystemMod.settings.enabledHusbandry and 2 or 1)
    end
    if PalletSystemUI.CONTROLS.toggleProduction ~= nil then
        PalletSystemUI.CONTROLS.toggleProduction:setState(PalletSystemMod.settings.enabledProduction and 2 or 1)
    end
end)


-- ============================================================
-- Compatibilite FS25_ProductionStorageControl (spawn manuel de palettes)
-- ============================================================
-- PSC contourne entierement PalletSpawner:spawnPallet/getOrSpawnPallet : il
-- construit lui-meme les entrees de spawnQueue via ProductionPoint:ReceiveSpawnEvent
-- (declenche par le dialogue "spawn manuel" cote client, execute cote serveur).
-- Notre hook natif ne se declenche donc jamais dans ce cas -> hook separe ici.
--
-- Detection automatique de PSC (pas de dependance XML necessaire) : si la
-- fonction ProductionPoint.ReceiveSpawnEvent n'existe pas, ce bloc entier ne
-- s'active pas et le mod fonctionne normalement sans PSC.
if ProductionPoint ~= nil and ProductionPoint.ReceiveSpawnEvent ~= nil then
    local originalReceiveSpawnEvent = ProductionPoint.ReceiveSpawnEvent

    ---Intercepte le spawn manuel PSC. types consideres comme "palette" (donc
    -- soumis a l'obligation) : 1=palette standard, 4/5=palette plants d'arbres,
    -- 6=palette specifique a un mod. Les balles (2/3) ne sont PAS concernees
    -- (aucune palette physique n'entre en jeu pour une balle).
    function ProductionPoint:ReceiveSpawnEvent(ownerFarmId, fillTypeIndex, pendingLiters, width, height, length, capacity, type, customEnvironment, treeId, amount, color1, color2, color3)
        local isPalletType = (type == 1 or type == 4 or type == 5 or type == 6)

        if not isPalletType or self.palletSpawner == nil or g_server == nil
            or not isRequirementActiveFor(self.palletSpawner) then
            originalReceiveSpawnEvent(self, ownerFarmId, fillTypeIndex, pendingLiters, width, height, length, capacity, type, customEnvironment, treeId, amount, color1, color2, color3)
            return
        end

        -- Consomme jusqu'a "amount" palettes vides (le joueur peut demander
        -- plusieurs unites en un seul spawn manuel). Realisation partielle si
        -- le stock d'EMPTYPALLET ne suffit pas pour la totalite.
        local achievable = 0
        for _ = 1, amount do
            if tryConsumeEmptyPalletUnit(self.palletSpawner, fillTypeIndex, ownerFarmId) then
                achievable = achievable + 1
            else
                break
            end
        end

        if achievable == 0 then
            showBlockedNotification(self.palletSpawner, fillTypeIndex)
            return -- rien a spawn, l'original n'est pas appele du tout
        end

        if PalletSystemMod.warnedSpawners[self.palletSpawner] then
            PalletSystemMod.warnedSpawners[self.palletSpawner][fillTypeIndex] = nil
        end

        originalReceiveSpawnEvent(self, ownerFarmId, fillTypeIndex, pendingLiters, width, height, length, capacity, type, customEnvironment, treeId, achievable, color1, color2, color3)
    end

    print("  PalletSystem : compatibilite FS25_ProductionStorageControl activee")
end


-- ============================================================
-- DIAGNOSTIC TEMPORAIRE : inspection de la structure ProductionPoint.productions
-- ============================================================
-- Objectif : verifier si un champ de cout (type costsPerActiveMonth, vu tel
-- quel dans PlaceableFactory.lua) existe aussi sur le vrai ProductionPoint,
-- meme sans acces aux fonctions :load()/:update() qui l'utilisent (elles sont
-- vides dans toutes les sources obtenues jusqu'ici). Hook sur ProductionPoint:updateInfo
-- (methode de classe standard, donc patchable comme PalletSpawner, contrairement
-- a PlaceableProductionPoint:updateInfo qui est une fonction de specialisation
-- a la chaine potentiellement figee au chargement du jeu).
-- A RETIRER une fois le diagnostic termine.
PalletSystemMod.costDebugDone = setmetatable({}, {__mode = "k"})

if ProductionPoint ~= nil and ProductionPoint.updateInfo ~= nil then
    local originalUpdateInfo = ProductionPoint.updateInfo

    function ProductionPoint:updateInfo(infoTable)
        if not PalletSystemMod.costDebugDone[self] and self.productions ~= nil then
            PalletSystemMod.costDebugDone[self] = true

            print("  [PS-cost-debug] ==== Structure de ProductionPoint.productions ====")
            for i, production in ipairs(self.productions) do
                print(string.format("  [PS-cost-debug] production #%d :", i))
                for k, v in pairs(production) do
                    local vType = type(v)
                    if vType == "number" or vType == "string" or vType == "boolean" then
                        print(string.format("  [PS-cost-debug]     %s = %s (%s)", tostring(k), tostring(v), vType))
                    else
                        print(string.format("  [PS-cost-debug]     %s = <%s>", tostring(k), vType))
                    end
                end
            end
            print("  [PS-cost-debug] ==== Fin ====")
        end

        originalUpdateInfo(self, infoTable)
    end

    print("  PalletSystem : diagnostic cout ProductionPoint active (temporaire)")
end