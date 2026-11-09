-- ============================================================================
-- Montures : une seule touche pour la bonne monture selon l'endroit.
--   - là où on peut voler : une volante ;
--   - dans l'eau : une aquatique (option) ;
--   - ailleurs : une terrestre ;
--   - en groupe : une monture à deux places si tu en as une (option).
-- Au hasard parmi tes favorites (étoiles du journal des montures), ou parmi
-- toutes. Réappuyer te fait descendre. La touche se choisit dans les réglages
-- (ou Échap > Options > Raccourcis), et un bouton déplaçable peut s'afficher.
-- Chaque monture reste un appui de ta part.
-- ============================================================================

local NOM_ADDON, ns = ...

local DEFAUTS = {
  actif = true,
  favorites = true,   -- seulement les favorites
  hasard = true,      -- au hasard (sinon la première)
  aquatique = true,   -- aquatique sous l'eau
  deuxPlaces = false, -- à deux places en groupe
  bouton = true,      -- un bouton à l'écran
  minimap = false,
  angleMinimap = 70,
}

local db

-- ---------------------------------------------------------------------------
-- Partie « logique pure », testée hors jeu (tests/Montures_simu.lua).
-- ---------------------------------------------------------------------------

-- Types de montures du jeu (mountTypeID) : volantes et aquatiques.
local VOLANTES = { [247] = true, [248] = true, [402] = true, [407] = true, [424] = true, [436] = true, [437] = true,
  [444] = true }
local AQUATIQUES = { [231] = true, [232] = true, [254] = true, [407] = true }
-- Montures à deux places ou plus (par leur sort) : mammouths, yak, motos, drake de grès, fusée…
local DEUX_PLACES = { [61425] = true, [61447] = true, [122708] = true, [60424] = true, [55531] = true, [93326] = true,
  [75973] = true, [121820] = true, [264058] = true, [245723] = true, [245725] = true }

function ns.genre(typeMonture)
  if AQUATIQUES[typeMonture] and not VOLANTES[typeMonture] then return "aquatique" end
  if VOLANTES[typeMonture] then return "volante" end
  return "terrestre"
end

-- Choisit la monture.
--   montures : { { id, nom, utilisable, favorite, type, sort } }
--   lieu     : { vol = peut voler ici, eau = sous l'eau, groupe = en groupe }
--   options  : { favorites, hasard, aquatique, deuxPlaces }
--   tirage   : fonction(n) -> 1..n (math.random en jeu)
-- Renvoie la monture choisie, ou nil.
function ns.choisir(montures, lieu, options, tirage)
  local candidates = {}
  for _, m in ipairs(montures) do
    if m.utilisable and (not options.favorites or m.favorite) then candidates[#candidates + 1] = m end
  end
  -- Aucune favorite utilisable ici : on prend toutes celles qui le sont.
  if #candidates == 0 and options.favorites then
    for _, m in ipairs(montures) do if m.utilisable then candidates[#candidates + 1] = m end end
  end
  if #candidates == 0 then return nil end

  local function parmi(filtre)
    local l = {}
    for _, m in ipairs(candidates) do if filtre(m) then l[#l + 1] = m end end
    return l
  end
  local listes = {}
  if options.deuxPlaces and lieu.groupe then
    listes[#listes + 1] = parmi(function(m) return DEUX_PLACES[m.sort] and (lieu.vol or ns.genre(m.type) ~= "volante") end)
  end
  if options.aquatique and lieu.eau then listes[#listes + 1] = parmi(function(m) return ns.genre(m.type) == "aquatique" end) end
  if lieu.vol then listes[#listes + 1] = parmi(function(m) return ns.genre(m.type) == "volante" end) end
  listes[#listes + 1] = parmi(function(m) return ns.genre(m.type) == "terrestre" end)
  listes[#listes + 1] = candidates
  for _, l in ipairs(listes) do
    if #l > 0 then
      if options.hasard then return l[tirage(#l)] end
      table.sort(l, function(a, b) return (a.nom or "") < (b.nom or "") end)
      return l[1]
    end
  end
end

if not CreateFrame or not C_MountJournal then return end -- hors jeu (ou sans journal des montures)

-- ---------------------------------------------------------------------------
-- En jeu
-- ---------------------------------------------------------------------------

local function lireMontures()
  local liste = {}
  for _, id in ipairs(C_MountJournal.GetMountIDs() or {}) do
    local nom, sort, _, _, utilisable, _, favorite, _, _, cachee, possedee = C_MountJournal.GetMountInfoByID(id)
    if possedee and not cachee then
      local _, _, _, _, typeMonture = C_MountJournal.GetMountInfoExtraByID(id)
      liste[#liste + 1] = { id = id, nom = nom, sort = sort, utilisable = utilisable, favorite = favorite, type = typeMonture }
    end
  end
  return liste
end

function Montures_Monter()
  if not db or not db.actif then return end
  if IsMounted() then
    if C_MountJournal.Dismount then C_MountJournal.Dismount() else Dismount() end
    return
  end
  if UnitOnTaxi and UnitOnTaxi("player") then return end
  if InCombatLockdown() then ns.reglages.dire("pas de monture en combat.") return end
  local lieu = {
    vol = IsFlyableArea and IsFlyableArea() or false,
    eau = (IsSubmerged and IsSubmerged()) or (IsSwimming and IsSwimming()) or false,
    groupe = IsInGroup and IsInGroup() or false,
  }
  local m = ns.choisir(lireMontures(), lieu, db, math.random)
  if not m then
    ns.reglages.dire(#lireMontures() == 0 and "tu n'as pas encore de monture." or "aucune monture utilisable ici.")
    return
  end
  C_MountJournal.SummonByID(m.id)
end

BINDING_HEADER_MONTURES = "Montures"
BINDING_NAME_MONTURES_MONTER = "Monter (la bonne monture) ou descendre"

-- Le bouton à l'écran.
local bouton = CreateFrame("Button", "MonturesBouton", UIParent)
bouton:SetSize(44, 44)
bouton:SetPoint("CENTER", UIParent, "CENTER", 300, -200)
bouton:SetMovable(true)
bouton:SetClampedToScreen(true)
bouton:RegisterForDrag("LeftButton")
bouton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
bouton:SetScript("OnDragStart", bouton.StartMoving)
bouton:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local p, _, rp, x, y = self:GetPoint()
  db.positionBouton = { p, rp, x, y }
end)
local icone = bouton:CreateTexture(nil, "ARTWORK")
icone:SetAllPoints()
icone:SetTexture("Interface\\Icons\\Ability_Mount_RidingHorse")
bouton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
bouton:SetScript("OnClick", function(_, souris)
  if souris == "RightButton" then ns.reglages.montrer() else Montures_Monter() end
end)
bouton:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  GameTooltip:AddLine("Montures")
  GameTooltip:AddLine("Clic : la bonne monture (ou descendre)\nClic droit : réglages\nGlisser : déplacer", 1, 1, 1)
  GameTooltip:Show()
end)
bouton:SetScript("OnLeave", function() GameTooltip:Hide() end)
bouton:Hide()

local function placerBouton()
  bouton:ClearAllPoints()
  local p = db.positionBouton
  if p then bouton:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else bouton:SetPoint("CENTER", UIParent, "CENTER", 300, -200) end
  -- Pas encore de monture : pas de bouton (il apparaîtra avec la première).
  bouton:SetShown(db.actif and db.bouton and #lireMontures() > 0)
end

-- Choisir la touche : on écoute la touche suivante (Échap annule).
local capture = CreateFrame("Frame", nil, UIParent)
capture:SetAllPoints()
capture:EnableKeyboard(true)
capture:SetFrameStrata("FULLSCREEN_DIALOG")
capture:Hide()
local MODIFS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true }
capture:SetScript("OnKeyDown", function(self, touche)
  if MODIFS[touche] then return end
  self:Hide()
  if touche == "ESCAPE" then ns.reglages.dire("touche inchangée.") ns.reglages.majFenetre() return end
  local combo = (IsShiftKeyDown() and "SHIFT-" or "") .. (IsControlKeyDown() and "CTRL-" or "") .. (IsAltKeyDown() and "ALT-" or "") .. touche
  local ancienne = GetBindingKey("MONTURES_MONTER")
  if ancienne then SetBinding(ancienne) end
  SetBinding(combo, "MONTURES_MONTER")
  SaveBindings(GetCurrentBindingSet())
  ns.reglages.dire("touche des montures : " .. (GetBindingText and GetBindingText(combo) or combo))
  ns.reglages.majFenetre()
end)

local function texteTouche()
  local k = GetBindingKey("MONTURES_MONTER")
  return k and (GetBindingText and GetBindingText(k) or k) or nil
end

-- ---------------------------------------------------------------------------
-- Réglages
-- ---------------------------------------------------------------------------

ns.reglages = ns.creerReglages({
  titre = "Montures",
  icone = "Interface\\Icons\\Ability_Mount_RidingHorse",
  nomDB = "MonturesDB",
  defauts = DEFAUTS,
  options = {
    { titre = "Montures" },
    { cle = "actif", libelle = "Activer Montures",
      aide = "Une touche (ou le bouton) : volante là où on peut voler, aquatique dans l'eau, terrestre ailleurs. Réappuyer : descendre." },
    { titre = "Parmi lesquelles ?" },
    { cle = "favorites", libelle = "Seulement mes montures favorites",
      aide = "Les étoiles du journal des montures. S'il n'y en a aucune d'utilisable ici, toutes celles que tu connais." },
    { cle = "hasard", libelle = "Au hasard parmi elles", aide = "Décoché : toujours la première par ordre alphabétique." },
    { titre = "En plus" },
    { cle = "aquatique", libelle = "Monture aquatique sous l'eau", aide = "Sinon une volante ou terrestre, même en nageant." },
    { cle = "deuxPlaces", libelle = "Monture à deux places en groupe",
      aide = "Mammouth, yak, moto, drake de grès… pour emmener ton frère quand il n'a pas encore de monture." },
    { cle = "bouton", libelle = "Un bouton à l'écran en plus de la touche",
      aide = "Clic : monter. Clic droit : réglages. Glisser : déplacer." },
    { titre = "Icône" },
    { cle = "minimap", libelle = "Icône à part autour de la minimap",
      aide = "En plus de la ligne dans l'icône commune des addons de Valentin." },
  },
  boutons = {
    { texte = "Choisir la touche", aide = "Appuie ensuite sur la touche voulue. Échap annule. Impossible en combat.", action = function()
      if InCombatLockdown() then ns.reglages.dire("pas en combat.") return end
      capture:Show()
      ns.reglages.dire("appuie sur la touche voulue (Échap annule)…")
    end },
    { texte = "Monter maintenant", aide = "La même chose que la touche.", action = function() Montures_Monter() end },
    { texte = "Replacer le bouton", aide = "Remet le bouton à sa place d'origine.", action = function()
      db.positionBouton = nil; placerBouton()
    end },
  },
  contenu = function(f, y)
    local t = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t:SetPoint("TOPLEFT", 20, y - 4)
    return y - 26, function()
      local k = texteTouche()
      t:SetText("Touche : " .. (k and ("|cff00ff00" .. k .. "|r") or "|cffff4040aucune|r (bouton « Choisir la touche »)"))
    end
  end,
  auChargement = function(d) db = d end,
  surChangement = function() placerBouton() end,
})

-- Une nouvelle monture apprise : le bouton peut apparaître.
local ecouteurMontures = CreateFrame("Frame")
for _, e in ipairs({ "NEW_MOUNT_ADDED", "COMPANION_LEARNED", "PLAYER_ENTERING_WORLD" }) do
  pcall(ecouteurMontures.RegisterEvent, ecouteurMontures, e)
end
ecouteurMontures:SetScript("OnEvent", function() if db then placerBouton() end end)

SLASH_MONTURES1 = "/montures"
SLASH_MONTURES2 = "/monture"
SlashCmdList.MONTURES = function(message)
  local c = strtrim(message or ""):lower()
  if c == "" then Montures_Monter()
  elseif c == "on" or c == "off" then
    if (c == "on") ~= (db.actif and true or false) then ns.reglages.basculer() end
  elseif c == "options" or c == "reglages" then ns.reglages.montrer()
  elseif not ns.reglages.basculerOption(c) then
    ns.reglages.dire("/montures : monter ou descendre ; /montures options ; /montures on | off")
  end
end
