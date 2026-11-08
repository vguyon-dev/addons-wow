-- ============================================================================
-- Alerte rare : un message et un son quand un monstre rare (ou élite, en
-- option) ou un coffre au trésor apparaît près de toi, avec une balise sur la
-- carte pour y aller.
-- COUPÉ AU DÉPART : à activer dans les réglages (/ar options) ou par /ar on.
--
-- Deux façons de le voir arriver :
--  - les « vignettes » du jeu : la petite tête de mort ou l'étoile qui apparaît
--    sur la minimap quand un rare est proche (Retail) ;
--  - les barres de vie au-dessus des monstres : le jeu dit si un monstre est
--    « rare » ou « élite » (sert surtout sur Forever).
-- Chaque monstre n'est annoncé qu'une fois toutes les 5 minutes, jamais en
-- donjon ni en raid.
-- ============================================================================

local NOM_ADDON, ns = ...

local DEFAUTS = {
  actif = false,      -- coupé au départ, à la demande de Valentin
  rares = true,       -- prévenir pour les monstres rares
  coffres = true,     -- prévenir pour les coffres et trésors de la minimap
  elites = false,     -- prévenir aussi pour les élites (hors donjon)
  son = true,         -- jouer un son
  balise = true,      -- poser une balise sur la carte vers le rare
  minimap = false,    -- icône à part (sinon seulement l'icône commune)
  angleMinimap = 80,
}

local db
local estSecret = issecretvalue or function() return false end

-- ---------------------------------------------------------------------------
-- Partie « logique pure », testée hors jeu (tests/AlerteRare_simu.lua).
-- ---------------------------------------------------------------------------

-- Vignette du jeu -> « rare », « élite », « coffre » ou nil. Les noms d'images
-- (atlas) des vignettes de monstre commencent par « VignetteKill », ceux des
-- trésors par « VignetteLoot » (ou contiennent « Treasure »).
function ns.typeVignette(atlas)
  if type(atlas) ~= "string" then return nil end
  if atlas:find("^VignetteLoot") or atlas:lower():find("treasure") then return "coffre" end
  if atlas:find("^VignetteKillElite") then return "élite" end
  if atlas:find("^VignetteKill") then return "rare" end
  return nil
end

-- Classement d'une barre de vie (UnitClassification) -> « rare », « élite » ou nil.
function ns.typeClassement(classement)
  if classement == "rare" or classement == "rareelite" then return "rare" end
  if classement == "elite" or classement == "worldboss" then return "élite" end
  return nil
end

-- Faut-il prévenir ? Pas si ce monstre (clé) a été annoncé il y a moins de
-- 5 minutes. Retient le moment de l'annonce dans « vus ».
function ns.doitPrevenir(cle, typ, reglages, vus, maintenant)
  if not typ or not cle then return false end
  if typ == "élite" and not reglages.elites then return false end
  if typ == "rare" and reglages.rares == false then return false end
  if typ == "coffre" and not reglages.coffres then return false end
  if vus[cle] and maintenant - vus[cle] < 300 then return false end
  vus[cle] = maintenant
  return true
end

-- ---------------------------------------------------------------------------
-- Annonce
-- ---------------------------------------------------------------------------

local vus = {}

local function poserBalise(guidVignette)
  if not db.balise or not guidVignette or not C_VignetteInfo or not C_Map or not C_Map.SetUserWaypoint then return end
  local carte = C_Map.GetBestMapForUnit("player")
  if not carte or estSecret(carte) then return end
  local ok, pos = pcall(C_VignetteInfo.GetVignettePosition, guidVignette, carte)
  if not ok or not pos then return end
  C_Map.SetUserWaypoint(UiMapPoint.CreateFromVector2D(carte, pos))
  if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
end

local function annoncer(nom, typ, guidVignette)
  local couleurs = { rare = "|cff66bbff", ["élite"] = "|cffffd200", coffre = "|cffffaa33" }
  local libelles = { rare = "Rare", ["élite"] = "Élite", coffre = "Coffre" }
  local texte = couleurs[typ] .. libelles[typ] .. " : " .. (nom or "?") .. "|r"
  if RaidNotice_AddMessage and RaidWarningFrame then
    RaidNotice_AddMessage(RaidWarningFrame, texte, ChatTypeInfo and ChatTypeInfo.RAID_WARNING or { r = 1, g = 1, b = 1 })
  end
  ns.reglages.dire(texte .. (guidVignette and db.balise and "  (balise posée sur la carte)" or ""))
  if db.son then PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "master") end
  poserBalise(guidVignette)
end

local function actifIci()
  return db and db.actif and not IsInInstance()
end

local function surVignettes()
  if not actifIci() or not C_VignetteInfo or not C_VignetteInfo.GetVignettes then return end
  for _, guid in ipairs(C_VignetteInfo.GetVignettes() or {}) do
    local info = C_VignetteInfo.GetVignetteInfo(guid)
    if info and info.onMinimap ~= false and not estSecret(info.atlasName) then
      local typ = ns.typeVignette(info.atlasName)
      if ns.doitPrevenir(info.objectGUID or guid, typ, db, vus, GetTime()) then
        annoncer(info.name, typ, guid)
      end
    end
  end
end

local function surBarreDeVie(unite)
  if not actifIci() or UnitIsDead(unite) or UnitIsPlayer(unite) then return end
  local classement = UnitClassification(unite)
  local guid = UnitGUID(unite)
  if estSecret(classement) or estSecret(guid) then return end
  local typ = ns.typeClassement(classement)
  if ns.doitPrevenir(guid, typ, db, vus, GetTime()) then annoncer(UnitName(unite), typ) end
end

-- ---------------------------------------------------------------------------
-- Réglages (Reglages.lua)
-- ---------------------------------------------------------------------------

ns.reglages = ns.creerReglages({
  titre = "Alerte rare",
  icone = "Interface\\Icons\\Ability_Hunter_MasterMarksman",
  nomDB = "AlerteRareDB",
  defauts = DEFAUTS,
  options = {
    { titre = "Alerte" },
    { cle = "actif", libelle = "Activer Alerte rare",
      aide = "Coupé au départ. Jamais en donjon ni en raid." },
    { cle = "rares", libelle = "Monstres rares",
      aide = "La tête de mort ou l'étoile de la minimap, ou une barre de vie « rare »." },
    { cle = "coffres", libelle = "Coffres et trésors",
      aide = "Le coffre qui apparaît sur la minimap quand un trésor est proche." },
    { cle = "elites", libelle = "Prévenir aussi pour les élites",
      aide = "Peut être bavard dans certaines zones." },
    { cle = "son", libelle = "Jouer un son",
      aide = "Le même son qu'une alerte de raid." },
    { cle = "balise", libelle = "Poser une balise sur la carte",
      aide = "Vers le rare repéré sur la minimap, avec la flèche du jeu pour y aller." },
    { titre = "Affichage" },
    { cle = "minimap", libelle = "Icône à part autour de la minimap",
      aide = "En plus de l'icône commune des addons de Valentin. Clic droit : activer ou couper." },
  },
  astuce = "Chaque monstre ou coffre n'est annoncé qu'une fois toutes les 5 minutes. Commande : /ar.",
  auChargement = function(d) db = d end,
})

-- ---------------------------------------------------------------------------
-- Événements et commande /ar
-- ---------------------------------------------------------------------------

local ecouteur = CreateFrame("Frame")
for _, e in ipairs({ "VIGNETTES_UPDATED", "VIGNETTE_MINIMAP_UPDATED", "NAME_PLATE_UNIT_ADDED" }) do
  pcall(ecouteur.RegisterEvent, ecouteur, e) -- un événement absent sur Forever ne bloque rien
end
ecouteur:SetScript("OnEvent", function(_, evenement, unite)
  if evenement == "NAME_PLATE_UNIT_ADDED" then surBarreDeVie(unite) else surVignettes() end
end)

SLASH_ALERTERARE1 = "/ar"
SLASH_ALERTERARE2 = "/alerterare"
SlashCmdList.ALERTERARE = function(message)
  local cmd = strtrim(message or ""):lower()
  local r = ns.reglages
  if cmd == "" or cmd == "options" or cmd == "reglages" then
    r.ouvrir()
  elseif cmd == "on" or cmd == "off" then
    if (cmd == "on") ~= (db.actif and true or false) then r.basculer() end
  elseif not r.basculerOption(cmd) then
    r.dire("/ar : les réglages     /ar on, /ar off")
  end
end
