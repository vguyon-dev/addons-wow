-- ============================================================================
-- Butin rapide : notre version de SpeedyAutoLoot, en français et réglable.
--
--  1. Ramasse le butin très vite, sans afficher la fenêtre de butin
--     (elle n'apparaît que s'il reste quelque chose).
--  2. Sacs pleins malin : une alerte dit ce qui reste au sol, et un bouton
--     jette ton objet gris le moins cher pour faire de la place, puis ramasse.
--  3. Ramasser seulement ce que tu veux : ignorer les gris, et une liste
--     d'objets à ne jamais ramasser.
--  4. Bilan de farm : ce que tu as ramassé, sa valeur à la revente et à
--     l'hôtel des ventes (si Auctionator est là), et le gain par heure.
-- Le ramassage suit le réglage du jeu (« Butin automatique ») : Maj inverse,
-- comme d'habitude.
-- ============================================================================

local NOM_ADDON, ns = ...

local DEFAUTS = {
  actif = true,
  minimap = true,
  angleMinimap = 160,
  sacsPleins = true,      -- alerte et bouton quand les sacs sont pleins
  sonSacsPleins = true,   -- un son en plus
  ignorerGris = false,    -- laisser les gris au sol
  ignores = {},           -- [idObjet] = lien : à ne jamais ramasser
  bilan = true,           -- afficher la fenêtre du bilan de farm
}

local db, perso

local infoObjet = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local function texteOr(cuivre)
  local f = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
  return f and f(math.floor(cuivre)) or (math.floor(cuivre / 10000) .. " po")
end

-- ---------------------------------------------------------------------------
-- Partie « logique pure », testée hors jeu (tests/ButinRapide_simu.lua).
-- ---------------------------------------------------------------------------

-- Que faire de ce butin ? b = { argent, qualite, idObjet, verrouille, quete }.
-- Renvoie "prendre", "laisser" (choix du joueur) ou "attendre" (verrouillé,
-- ou au-dessus du seuil de partage du groupe : la fenêtre doit rester).
function ns.decision(b, reglages, ignores, seuil)
  if b.verrouille then return "attendre" end
  if b.argent or b.quete then return "prendre" end
  if seuil and b.qualite and b.qualite >= seuil then return "attendre" end
  if b.idObjet and ignores[b.idObjet] then return "laisser" end
  if reglages.ignorerGris and b.qualite == 0 then return "laisser" end
  return "prendre"
end

-- Parmi les gris des sacs ({ valeur = prix × nombre }), lequel jeter ?
function ns.grisAJeter(gris)
  local choix
  for i, g in ipairs(gris) do
    if not choix or g.valeur < gris[choix].valeur then choix = i end
  end
  return choix
end

-- Gain par heure (0 avant une minute de farm, pour ne pas afficher n'importe quoi).
function ns.parHeure(valeur, secondes)
  if secondes < 60 then return 0 end
  return valeur * 3600 / secondes
end

-- ---------------------------------------------------------------------------
-- Place dans les sacs
-- ---------------------------------------------------------------------------

local DERNIER_SAC = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
local SAC_COMPOSANTS = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag

local function placePour(lien, quantite)
  -- Champs 8 (taille de pile) et 17 (composant d'artisanat) de GetItemInfo.
  local pile, _, _, _, _, _, _, _, _, composant = select(8, infoObjet(lien))
  if not pile then return true end -- infos pas encore là : on tente
  local possede = (C_Item and C_Item.GetItemCount or GetItemCount)(lien)
  if pile > 1 and possede > 0 and ((pile - possede % pile) % pile) >= quantite then return true end
  local famille = C_Item and C_Item.GetItemFamily and C_Item.GetItemFamily(lien)
  for sac = 0, DERNIER_SAC do
    local libres, familleSac = C_Container.GetContainerNumFreeSlots(sac)
    if libres > 0 then
      if sac == SAC_COMPOSANTS then
        if composant then return true end
      elseif not familleSac or familleSac == 0 or (famille and bit.band(famille, familleSac) > 0) then
        return true
      end
    end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- Bilan de farm (par personnage)
-- ---------------------------------------------------------------------------

local function prixHV(lien)
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if not api or not api.GetAuctionPriceByItemLink then return nil end
  local ok, prix = pcall(api.GetAuctionPriceByItemLink, NOM_ADDON, lien)
  return ok and prix or nil
end

local majBilan -- défini plus bas

local function noterObjet(lien, quantite)
  if not perso then return end
  local id = tonumber(lien:match("item:(%d+)"))
  if not id then return end
  local o = perso.objets[id] or { lien = lien, nombre = 0 }
  o.nombre = o.nombre + (quantite or 1)
  perso.objets[id] = o
  if majBilan then majBilan() end
end

-- ---------------------------------------------------------------------------
-- Alerte « sacs pleins »
-- ---------------------------------------------------------------------------

local alerte = CreateFrame("Frame", "ButinRapideAlerte", UIParent, "BackdropTemplate")
alerte:SetSize(320, 96)
alerte:SetPoint("TOP", 0, -140)
alerte:SetFrameStrata("DIALOG")
alerte:SetBackdrop({
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
alerte:SetBackdropColor(0.25, 0, 0, 0.9)
alerte:Hide()
local alerteTexte = alerte:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
alerteTexte:SetPoint("TOPLEFT", 10, -10)
alerteTexte:SetWidth(300)
alerteTexte:SetJustifyH("LEFT")
local boutonJeter = CreateFrame("Button", nil, alerte, "UIPanelButtonTemplate")
boutonJeter:SetSize(300, 24)
boutonJeter:SetPoint("BOTTOM", 0, 10)
local fermerAlerte = CreateFrame("Button", nil, alerte, "UIPanelCloseButton")
fermerAlerte:SetSize(22, 22)
fermerAlerte:SetPoint("TOPRIGHT", -2, -2)

local restes = {} -- liens laissés au sol faute de place
local grisChoisi  -- { sac, case, lien, valeur }

local function chercherGris()
  local gris = {}
  for sac = 0, DERNIER_SAC do
    for case = 1, C_Container.GetContainerNumSlots(sac) do
      local i = C_Container.GetContainerItemInfo(sac, case)
      -- Seulement les gris (qualité 0). Jamais un composant d'artisanat (classe 7
      -- ou marqué « composant »), ni un objet de quête, même gris.
      if i and i.quality == 0 and not i.isLocked then
        -- Champs 11 (prix), 12 (classe) et 17 (composant) de GetItemInfo.
        local prix, classe, _, _, _, _, composant = select(11, infoObjet(i.hyperlink))
        local q = C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(sac, case)
        local deQuete = q and (q.isQuestItem or q.questID)
        if classe ~= 7 and not composant and not deQuete then
          gris[#gris + 1] = { sac = sac, case = case, lien = i.hyperlink, valeur = (prix or 0) * (i.stackCount or 1) }
        end
      end
    end
  end
  local n = ns.grisAJeter(gris)
  return n and gris[n]
end

local function montrerAlerte()
  if not db.sacsPleins or #restes == 0 then return end
  grisChoisi = chercherGris()
  alerteTexte:SetText("|cffff6060Sacs pleins !|r Reste au sol : " .. table.concat(restes, ", "))
  if grisChoisi then
    boutonJeter:SetText("Jeter " .. grisChoisi.lien .. " (" .. texteOr(grisChoisi.valeur) .. ")")
    boutonJeter:Enable()
  else
    boutonJeter:SetText("Aucun objet gris à jeter")
    boutonJeter:Disable()
  end
  alerte:Show()
  if db.sonSacsPleins then PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "master") end
end

-- ---------------------------------------------------------------------------
-- Ramassage
-- ---------------------------------------------------------------------------

local enCours, ticker, resteQuelqueChose = false, nil, false
local derniersSlots

local function ramasserSlot(slot)
  local typ = GetLootSlotType(slot)
  if not typ or typ == 0 then return end -- vide
  local _, _, quantite, _, qualite, verrouille, quete = GetLootSlotInfo(slot)
  local lien = GetLootSlotLink(slot)
  local seuil = IsInGroup() and GetLootThreshold and GetLootThreshold() or nil
  local b = {
    argent = typ == 2 or nil, -- 2 = argent (Enum.LootSlotType.Money)
    quete = quete, qualite = qualite, verrouille = verrouille,
    idObjet = lien and tonumber(lien:match("item:(%d+)")),
  }
  local d = ns.decision(b, db, db.ignores, seuil)
  if d == "attendre" then resteQuelqueChose = true return end
  if d == "laisser" then return end
  if lien and typ == 1 and not quete and not placePour(lien, quantite) then
    restes[#restes + 1] = lien
    resteQuelqueChose = true
    return
  end
  LootSlot(slot)
  if lien and typ == 1 then noterObjet(lien, quantite) end
end

local function toutRamasser()
  if ticker then ticker:Cancel() end
  local n = GetNumLootItems()
  local slot = n
  resteQuelqueChose = false
  wipe(restes)
  -- Un objet tous les 3 centièmes de seconde : assez vite, sans rater de case.
  ticker = C_Timer.NewTicker(0.03, function(t)
    if slot >= 1 then
      ramasserSlot(slot)
      slot = slot - 1
    else
      t:Cancel()
      if resteQuelqueChose then
        LootFrame:SetAlpha(1) -- il reste quelque chose : on montre la fenêtre
        montrerAlerte()
      end
    end
  end, n + 1)
end

boutonJeter:SetScript("OnClick", function()
  if not grisChoisi or InCombatLockdown() then return end
  C_Container.PickupContainerItem(grisChoisi.sac, grisChoisi.case)
  DeleteCursorItem()
  ns.reglages.dire(grisChoisi.lien .. " jeté pour faire de la place.")
  alerte:Hide()
  -- Le butin est toujours ouvert ? On réessaie de tout ramasser.
  C_Timer.After(0.2, function() if enCours then toutRamasser() end end)
end)
fermerAlerte:SetScript("OnClick", function() alerte:Hide() end)

-- ---------------------------------------------------------------------------
-- Fenêtre du bilan de farm
-- ---------------------------------------------------------------------------

local fenetreBilan = CreateFrame("Frame", "ButinRapideBilan", UIParent, "BackdropTemplate")
fenetreBilan:SetSize(250, 60)
fenetreBilan:SetMovable(true)
fenetreBilan:SetClampedToScreen(true)
fenetreBilan:EnableMouse(true)
fenetreBilan:RegisterForDrag("LeftButton")
fenetreBilan:SetScript("OnDragStart", fenetreBilan.StartMoving)
fenetreBilan:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local point, _, pointRelatif, x, y = self:GetPoint()
  db.positionBilan = { point, pointRelatif, x, y }
end)
fenetreBilan:SetBackdrop({
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
fenetreBilan:SetBackdropColor(0, 0, 0, 0.75)
local titreBilan = fenetreBilan:CreateFontString(nil, "OVERLAY", "GameFontNormal")
titreBilan:SetPoint("TOPLEFT", 10, -8)
titreBilan:SetText("Bilan de farm")
local fermerBilan = CreateFrame("Button", nil, fenetreBilan, "UIPanelCloseButton")
fermerBilan:SetSize(22, 22)
fermerBilan:SetPoint("TOPRIGHT", -2, -2)
fermerBilan:SetScript("OnClick", function() ns.reglages.changer("bilan", false) end)
local texteBilan = fenetreBilan:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
texteBilan:SetPoint("TOPLEFT", 10, -28)
texteBilan:SetWidth(230)
texteBilan:SetJustifyH("LEFT")

local function nouveauBilan()
  perso.debut, perso.argent, perso.objets = time(), 0, {}
end

function majBilan()
  if not db or not perso then return end
  if not db.bilan or not db.actif then fenetreBilan:Hide() return end
  local revente, hv, nombre, liste = 0, 0, 0, {}
  for _, o in pairs(perso.objets) do
    local prix = select(11, infoObjet(o.lien)) or 0
    revente = revente + prix * o.nombre
    hv = hv + (prixHV(o.lien) or prix) * o.nombre
    nombre = nombre + o.nombre
    liste[#liste + 1] = o
  end
  table.sort(liste, function(a, b) return a.nombre > b.nombre end)
  local duree = time() - perso.debut
  local lignes = {
    string.format("Durée : %d min     Objets : %d", math.floor(duree / 60), nombre),
    "Or ramassé : " .. texteOr(perso.argent),
    "Revente marchand : " .. texteOr(revente),
  }
  if Auctionator then lignes[#lignes + 1] = "Hôtel des ventes : " .. texteOr(hv) end
  lignes[#lignes + 1] = "|cff40ff40Par heure : " .. texteOr(ns.parHeure(perso.argent + hv, duree)) .. "|r"
  for i = 1, math.min(5, #liste) do
    lignes[#lignes + 1] = liste[i].nombre .. " × " .. liste[i].lien
  end
  texteBilan:SetText(table.concat(lignes, "\n"))
  fenetreBilan:SetHeight(40 + texteBilan:GetStringHeight())
  fenetreBilan:Show()
end
C_Timer.NewTicker(30, function() majBilan() end) -- l'or par heure bouge avec le temps

-- ---------------------------------------------------------------------------
-- Réglages
-- ---------------------------------------------------------------------------

local function compter(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

ns.reglages = ns.creerReglages({
  titre = "Butin rapide",
  icone = "Interface\\Icons\\INV_Misc_Bag_10",
  nomDB = "ButinRapideDB",
  defauts = DEFAUTS,
  options = {
    { titre = "Ramassage" },
    { cle = "actif", libelle = "Activer Butin rapide",
      aide = "Interrupteur général. Désactive SpeedyAutoLoot pour ne pas avoir les deux." },
    { cle = "ignorerGris", libelle = "Laisser les objets gris au sol",
      aide = "Pratique en farm pour garder de la place. L'or et les objets de quête sont toujours pris." },
    { titre = "Sacs pleins" },
    { cle = "sacsPleins", libelle = "Alerte avec bouton « jeter le gris le moins cher »",
      aide = "Dit ce qui reste au sol ; un clic fait de la place et ramasse." },
    { cle = "sonSacsPleins", libelle = "Son quand les sacs sont pleins",
      aide = "Pour l'entendre même sans regarder l'écran." },
    { titre = "Affichage" },
    { cle = "bilan", libelle = "Afficher le bilan de farm",
      aide = "Objets, or, valeur et gain par heure de la session de ce personnage." },
    { cle = "minimap", libelle = "Icône autour de la minimap",
      aide = "Clic gauche : réglages. Clic droit : activer ou couper. Glisser : déplacer." },
  },
  contenu = function(fenetre, y, r)
    local t = fenetre:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, y - 6)
    t:SetText("Listes")
    y = y - 32
    local compteur = fenetre:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    compteur:SetPoint("TOPLEFT", 20, y)
    y = y - 22
    local b1 = CreateFrame("Button", nil, fenetre, "UIPanelButtonTemplate")
    b1:SetSize(190, 24)
    b1:SetPoint("TOPLEFT", 16, y)
    b1:SetText("Vider « à ne pas ramasser »")
    b1:SetScript("OnClick", function() r.changer("ignores", {}); r.dire("liste vidée.") end)
    local b2 = CreateFrame("Button", nil, fenetre, "UIPanelButtonTemplate")
    b2:SetSize(190, 24)
    b2:SetPoint("TOPLEFT", 214, y)
    b2:SetText("Nouveau bilan de farm")
    b2:SetScript("OnClick", function() nouveauBilan(); majBilan(); r.dire("bilan remis à zéro.") end)
    y = y - 28
    return y, function(d) compteur:SetText("Objets à ne jamais ramasser : " .. compter(d.ignores)) end
  end,
  astuce = "Ne plus ramasser un objet : /br ignorer puis Maj+clic sur l'objet. Tout s'applique sans /reload.",
  auChargement = function(d)
    db = d
    ButinRapidePerso = ButinRapidePerso or {}
    perso = ButinRapidePerso
    if not perso.debut then nouveauBilan() end
    if db.positionBilan then
      local p = db.positionBilan
      fenetreBilan:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
      fenetreBilan:SetPoint("LEFT", UIParent, "LEFT", 40, 120)
    end
  end,
  surChangement = function() majBilan() end,
})

-- ---------------------------------------------------------------------------
-- Événements
-- ---------------------------------------------------------------------------

local argentAvant
local ecouteur = CreateFrame("Frame")
for _, e in ipairs({ "LOOT_READY", "LOOT_CLOSED", "PLAYER_MONEY", "UI_ERROR_MESSAGE" }) do
  ecouteur:RegisterEvent(e)
end
ecouteur:SetScript("OnEvent", function(_, evenement, a, b)
  if not db or not db.actif then return end
  if evenement == "LOOT_READY" then
    -- Le jeu dit s'il faut ramasser seul : réglage « Butin automatique », Maj inverse.
    local auto = a
    if auto == nil then auto = GetCVarBool("autoLootDefault") ~= IsModifiedClick("AUTOLOOTTOGGLE") end
    local n = GetNumLootItems()
    if not auto or n == 0 or (enCours and derniersSlots == n) then return end
    enCours, derniersSlots = true, n
    argentAvant = GetMoney()
    LootFrame:SetAlpha(0) -- fenêtre invisible pendant le ramassage rapide
    toutRamasser()
  elseif evenement == "LOOT_CLOSED" then
    enCours, derniersSlots = false, nil
    if ticker then ticker:Cancel() end
    LootFrame:SetAlpha(1)
  elseif evenement == "PLAYER_MONEY" then
    if enCours and argentAvant and perso then
      local gain = GetMoney() - argentAvant
      if gain > 0 then perso.argent = perso.argent + gain end
      argentAvant = GetMoney()
      majBilan()
    end
  elseif evenement == "UI_ERROR_MESSAGE" then
    if enCours and b == ERR_INV_FULL and #restes == 0 then
      restes[1] = "des objets"
      LootFrame:SetAlpha(1)
      montrerAlerte()
    end
  end
end)

-- ---------------------------------------------------------------------------
-- Commande /br
-- ---------------------------------------------------------------------------

SLASH_BUTINRAPIDE1 = "/br"
SLASH_BUTINRAPIDE2 = "/butinrapide"
SlashCmdList.BUTINRAPIDE = function(texte)
  local cmd, reste = strtrim(texte or ""):match("^(%S*)%s*(.-)$")
  cmd = cmd:lower()
  local r = ns.reglages
  if cmd == "" or cmd == "options" or cmd == "reglages" then
    r.ouvrir()
  elseif cmd == "on" or cmd == "off" then
    if (cmd == "on") ~= (db.actif and true or false) then r.basculer() end
  elseif cmd == "ignorer" then
    local id = tonumber(reste:match("item:(%d+)") or reste)
    if not id then return r.dire("tape /br ignorer puis Maj+clic sur l'objet.") end
    if db.ignores[id] then db.ignores[id] = nil else db.ignores[id] = reste end
    r.dire(reste .. (db.ignores[id] and " ne sera plus ramassé." or " sera de nouveau ramassé."))
    r.appliquer()
  elseif cmd == "bilan" then
    nouveauBilan(); majBilan(); r.dire("bilan remis à zéro.")
  elseif not r.basculerOption(cmd) then
    r.dire("/br : réglages     /br on, /br off     /br bilan : nouveau bilan")
    r.dire("/br ignorer <objet> : ne plus ramasser cet objet (Maj+clic sur l'objet)")
  end
end
