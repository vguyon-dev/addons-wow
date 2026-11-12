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
--     l'hôtel des ventes (si Enchères ou Auctionator est là), et le gain par heure.
--     Le Carnet de session peut le montrer dans son cadre (ButinRapide_LignesBilan, ButinRapide_SetBilanCache).
--  5. Touche d'interaction sur les cadavres (option) : le jeu vise tout seul
--     le cadavre le plus proche, une touche l'ouvre. Un appui par cadavre :
--     aucun addon n'a le droit d'ouvrir un cadavre à ta place.
-- Le ramassage suit le réglage du jeu (« Butin automatique ») : Maj inverse,
-- comme d'habitude.
-- ============================================================================

local NOM_ADDON, ns = ...

local DEFAUTS = {
  actif = true,
  minimap = false,         -- icône à part (sinon seulement l'icône commune)
  angleMinimap = 160,
  sacsPleins = true,      -- alerte et bouton quand les sacs sont pleins
  sonSacsPleins = true,   -- un son en plus
  ignorerGris = false,    -- laisser les gris au sol
  ignores = {},           -- [idObjet] = lien : à ne jamais ramasser
  bilan = true,           -- afficher la fenêtre du bilan de farm
  toucheCadavres = false, -- vise tout seul le cadavre le plus proche (touche d'interaction)
  cvarAvant = nil,        -- réglages du jeu d'avant, remis quand on décoche
}

-- ---------------------------------------------------------------------------
-- Touche d'interaction : réglages cachés du jeu (CVars), posés hors combat.
--   SoftTargetInteract      3 = toujours (clavier et manette)
--   SoftTargetInteractArc   2 = tout autour de toi, pas seulement devant
-- ---------------------------------------------------------------------------

local CVARS_CADAVRES = { SoftTargetInteract = "3", SoftTargetInteractArc = "2" }
local lireCVar = (C_CVar and C_CVar.GetCVar) or GetCVar
local poserCVar = (C_CVar and C_CVar.SetCVar) or SetCVar

-- C'est la même touche que la récolte de Métiers auto (« Interagir avec la
-- cible », réglage SoftTargetInteract) : une seule touche pour les filons,
-- les herbes et les cadavres. On ne la coupe jamais si Métiers auto s'en sert.
local function metiersSenSert()
  return type(MetiersAutoDB) == "table" and MetiersAutoDB.actif ~= false and MetiersAutoDB.interaction ~= false
end

local function appliquerCadavres(d, prevenir)
  if not lireCVar or not poserCVar then return end
  if InCombatLockdown() then return end
  local function dire(t) if prevenir and ns.reglages then ns.reglages.dire(t) end end
  if d.toucheCadavres then
    if not d.cvarAvant then
      d.cvarAvant = {}
      for nom in pairs(CVARS_CADAVRES) do
        local ok, v = pcall(lireCVar, nom)
        d.cvarAvant[nom] = ok and v or false
      end
    end
    local manque = false
    for nom, v in pairs(CVARS_CADAVRES) do
      local ok, ancien = pcall(lireCVar, nom)
      if not ok or ancien == nil then manque = true else pcall(poserCVar, nom, v) end
    end
    if manque then
      dire("|cffff4040ce jeu n'a pas la touche d'interaction|r : il faudra cliquer chaque cadavre.")
    elseif prevenir then
      local touche = GetBindingKey and GetBindingKey("INTERACTTARGET")
      if touche then
        dire("cadavres : même touche que la récolte, |cffffffff" .. touche .. "|r, un appui par cadavre.")
      else
        dire("cadavres : donne une touche à « Interagir avec la cible » (Options, Raccourcis), puis un appui par cadavre.")
      end
    end
  elseif d.cvarAvant then
    for nom, v in pairs(d.cvarAvant) do
      if v and not (nom == "SoftTargetInteract" and metiersSenSert()) then pcall(poserCVar, nom, v) end
    end
    d.cvarAvant = nil
    dire("touche d'interaction : réglages du jeu remis comme avant.")
  end
end

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

-- Le nom affiché d'un objet : celui du lien enregistré, sinon celui du jeu
-- (infoFn = GetItemInfo), sinon « objet 123 ».
function ns.nomObjet(id, lien, infoFn)
  local nom = type(lien) == "string" and lien:match("%[(.-)%]")
  if not nom and infoFn then
    local ok, n = pcall(infoFn, id)
    if ok and type(n) == "string" then nom = n end
  end
  return nom or ("objet " .. tostring(id))
end

-- Les lignes de la liste « Objets à ne jamais ramasser » : { texte, lien, retirer },
-- triées par nom. retirer(id) est appelé par la croix d'une ligne.
function ns.lignesIgnores(ignores, infoFn, retirer)
  local l = {}
  for id, lien in pairs(ignores or {}) do
    l[#l + 1] = { id = id, texte = ns.nomObjet(id, lien, infoFn), lien = "item:" .. id,
                  retirer = function() retirer(id) end }
  end
  table.sort(l, function(a, b)
    local x, y = a.texte:lower(), b.texte:lower()
    if x ~= y then return x < y end
    return a.id < b.id
  end)
  return l
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
-- La durée d'un bilan : seulement le temps passé EN JEU. Avant, on comptait depuis le tout premier
-- démarrage, temps hors ligne compris (vu en jeu le 12/11 : « Durée : 8794 min »).
--   joue : secondes de jeu déjà comptées (sessions d'avant) ; debutSession : time() de la connexion.
function ns.dureeJouee(joue, debutSession, maintenant)
  local d = tonumber(joue) or 0
  if debutSession and maintenant and maintenant >= debutSession then d = d + (maintenant - debutSession) end
  return d
end

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
  -- Notre addon Enchères d'abord, sinon Auctionator.
  if Encheres_Prix then
    local p = Encheres_Prix(lien)
    if p then return p end
  end
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
local _, fermerAlerte = ns.habiller(alerte, { fermer = true })
alerte:Hide()
local alerteTexte = alerte:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
alerteTexte:SetPoint("TOPLEFT", 10, -10)
alerteTexte:SetWidth(300)
alerteTexte:SetJustifyH("LEFT")
local boutonJeter = CreateFrame("Button", nil, alerte, "UIPanelButtonTemplate")
boutonJeter:SetSize(300, 24)
boutonJeter:SetPoint("BOTTOM", 0, 10)

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
local _, fermerBilan = ns.habiller(fenetreBilan, { titre = "Bilan de farm", fermer = true })
fermerBilan:SetScript("OnClick", function() ns.reglages.changer("bilan", false) end)
local texteBilan = fenetreBilan:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
texteBilan:SetPoint("TOPLEFT", 10, -28)
texteBilan:SetWidth(230)
texteBilan:SetJustifyH("LEFT")

local debutSession = time and time() or 0 -- l'heure de la connexion (ou du dernier « remettre à zéro »)

local function nouveauBilan()
  perso.debut, perso.argent, perso.objets = time(), 0, {}
  perso.joue, debutSession = 0, time()
end

-- Le bilan calculé, une seule fois pour les deux usages : notre cadre et le Carnet de session
-- (qui peut le montrer dans son propre cadre). Renvoie nil quand il n'y a rien à montrer
-- (bilan coupé, addon coupé, personnage pas encore chargé). Sinon :
--   lignes   = { { libelle, valeur, couleur?, texte }, ... } ; couleur = code hexadécimal « rrggbb » ;
--              texte = la ligne toute faite, telle que notre cadre l'écrit
--   parHeure = le gain par heure en texte (pièces)
--   duree    = la durée en secondes (temps passé en jeu)
local function calculerBilan()
  if not db or not perso or not perso.objets then return nil end
  if not db.bilan or not db.actif then return nil end
  local revente, hv, nombre, liste = 0, 0, 0, {}
  for _, o in pairs(perso.objets) do
    local prix = select(11, infoObjet(o.lien)) or 0
    revente = revente + prix * o.nombre
    hv = hv + (prixHV(o.lien) or prix) * o.nombre
    nombre = nombre + o.nombre
    liste[#liste + 1] = o
  end
  table.sort(liste, function(a, b) return a.nombre > b.nombre end)
  local duree = ns.dureeJouee(perso.joue, debutSession, time())
  local parHeure = texteOr(ns.parHeure(perso.argent + hv, duree))
  local lignes = {}
  local function ajouter(libelle, valeur, couleur, texte)
    local l = { libelle = libelle, valeur = valeur, couleur = couleur }
    if texte then
      l.texte = texte
    else
      l.texte = libelle .. " : " .. (couleur and ("|cff" .. couleur .. valeur .. "|r") or valeur)
    end
    lignes[#lignes + 1] = l
  end
  ajouter("Durée", math.floor(duree / 60) .. " min")
  ajouter("Objets", tostring(nombre))
  ajouter("Or ramassé", texteOr(perso.argent))
  ajouter("Revente marchand", texteOr(revente))
  if Encheres_Prix or Auctionator then ajouter("Hôtel des ventes", texteOr(hv)) end
  ajouter("Par heure", parHeure, "40ff40", "|cff40ff40Par heure : " .. parHeure .. "|r")
  for i = 1, math.min(5, #liste) do
    ajouter(liste[i].lien, "× " .. liste[i].nombre, nil, liste[i].nombre .. " × " .. liste[i].lien)
  end
  return { lignes = lignes, parHeure = parHeure, duree = duree }
end

-- Pour le Carnet de session : les lignes du bilan (voir calculerBilan), ou nil.
function ButinRapide_LignesBilan()
  return calculerBilan()
end

-- Quand le Carnet de session montre le farm dans son cadre, il demande de cacher le nôtre
-- (sans toucher au réglage « bilan »), et de le remontrer quand il n'en a plus besoin.
local bilanCache = false
function ButinRapide_SetBilanCache(cache)
  cache = cache and true or false
  if cache == bilanCache then return end
  bilanCache = cache
  if majBilan then majBilan() end
end

local prevenirEnCours = false

function majBilan()
  if not db or not perso then return end
  local bilan = calculerBilan()
  if not bilan or bilanCache then
    fenetreBilan:Hide()
  else
    local textes = {}
    for i, l in ipairs(bilan.lignes) do textes[i] = l.texte end
    texteBilan:SetText(table.concat(textes, "\n"))
    fenetreBilan:SetHeight(40 + texteBilan:GetStringHeight())
    fenetreBilan:Show()
  end
  -- Le Carnet de session (s'il est là) met son cadre à jour, aussi quand le bilan vient d'être coupé.
  -- Sous pcall : une erreur chez lui ne doit jamais gêner le ramassage.
  if not prevenirEnCours and type(CarnetDeSession_MajFarm) == "function" then
    prevenirEnCours = true
    pcall(CarnetDeSession_MajFarm)
    prevenirEnCours = false
  end
end
C_Timer.NewTicker(30, function() majBilan() end) -- l'or par heure bouge avec le temps

-- ---------------------------------------------------------------------------
-- Réglages
-- ---------------------------------------------------------------------------

-- Le lien d'un objet lâché dans la liste (celui du curseur, sinon celui du jeu).
local function lienDe(id, lien)
  if type(lien) == "string" then return lien end
  local ok, _, l = pcall(infoObjet, id)
  return ok and l or ("objet " .. id)
end

ns.reglages = ns.creerReglages({
  titre = "Butin rapide",
  icone = "Interface\\Icons\\INV_Misc_Bag_10",
  nomDB = "ButinRapideDB",
  defauts = DEFAUTS,
  boutons = {
    { texte = "Nouveau bilan de farm", largeur = 170, aide = "Remet à zéro le bilan de farm de ce personnage (durée, objets, or).",
      action = function() nouveauBilan(); majBilan(); ns.reglages.dire("bilan remis à zéro.") end },
    { texte = "Replacer le bilan", aide = "Remet la fenêtre du bilan à sa place d'origine, au bord gauche de l'écran.",
      action = function()
        db.positionBilan = nil
        fenetreBilan:ClearAllPoints()
        fenetreBilan:SetPoint("LEFT", UIParent, "LEFT", 40, 120)
      end },
  },
  options = {
    { titre = "Ramassage" },
    { cle = "actif", libelle = "Activer Butin rapide",
      aide = "Interrupteur général. Désactive SpeedyAutoLoot pour ne pas avoir les deux." },
    { cle = "ignorerGris", libelle = "Laisser les objets gris au sol",
      aide = "Pratique en farm pour garder de la place. L'or et les objets de quête sont toujours pris." },
    { cle = "toucheCadavres", libelle = "Touche d'interaction sur les cadavres",
      aide = "Même touche que la récolte de Métiers auto (« Interagir avec la cible ») : elle vise aussi le cadavre le plus proche, tout autour de toi. Un appui par cadavre." },
    { titre = "Sacs pleins" },
    { cle = "sacsPleins", libelle = "Alerte avec bouton « jeter le gris le moins cher »",
      aide = "Dit ce qui reste au sol ; un clic fait de la place et ramasse." },
    { cle = "sonSacsPleins", libelle = "Son quand les sacs sont pleins",
      aide = "Pour l'entendre même sans regarder l'écran." },
    { titre = "Affichage" },
    { cle = "bilan", libelle = "Afficher le bilan de farm",
      aide = "Objets, or, valeur et gain par heure de la session de ce personnage." },
    { cle = "minimap", libelle = "Icône à part autour de la minimap",
      aide = "En plus de l'icône commune « Mes addons ». Clic droit : activer ou couper." },
  },
  ongletContenu = "Objets ignorés",
  contenu = function(fenetre, y, r)
    local t = fenetre:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, y - 6)
    t:SetText("Listes")
    y = y - 30
    local maj
    y, maj = ns.creerListe(fenetre, y, {
      titre = "Objets à ne jamais ramasser", hauteur = 5,
      vide = "Aucun : tout est ramassé.",
      lignes = function()
        return ns.lignesIgnores(db and db.ignores, infoObjet, function(id) db.ignores[id] = nil end)
      end,
      deposer = function(id, lien) db.ignores[id] = lienDe(id, lien) end,
      texteDepot = "Glisse ici un objet de ton sac pour ne plus jamais le ramasser",
      vider = function() db.ignores = {} end,
    })
    return y, function() maj() end
  end,
  astuce = "Pour ne plus ramasser un objet : prends-le dans ton sac et lâche-le dans la zone de la liste (ou clique la zone avec l'objet au curseur). Tout s'applique sans /reload.",
  auChargement = function(d)
    db = d
    ButinRapidePerso = ButinRapidePerso or {}
    perso = ButinRapidePerso
    -- Une fois : un bilan d'avant la 0.7.2 n'a pas son temps de jeu ; sa durée était fausse, on repart.
    if not perso.debut or perso.joue == nil then nouveauBilan() end
    debutSession = time()
    -- Le jeu remet parfois ses réglages au démarrage : on repose les nôtres.
    C_Timer.After(2, function() appliquerCadavres(d, false) end)
    if db.positionBilan then
      local p = db.positionBilan
      fenetreBilan:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
      fenetreBilan:SetPoint("LEFT", UIParent, "LEFT", 40, 120)
    end
  end,
  surChangement = function(d)
    -- Coupé pendant qu'une fenêtre de butin est ouverte : on la rend visible.
    if not d.actif then
      if ticker then ticker:Cancel() end
      enCours, derniersSlots = false, nil
      if LootFrame then LootFrame:SetAlpha(1) end
    end
    majBilan()
    if (d.toucheCadavres and true or false) ~= (d.cvarAvant and true or false) then appliquerCadavres(d, true) end
  end,
})

-- ---------------------------------------------------------------------------
-- Événements
-- ---------------------------------------------------------------------------

local argentAvant
local ecouteur = CreateFrame("Frame")
for _, e in ipairs({ "LOOT_READY", "LOOT_CLOSED", "PLAYER_MONEY", "UI_ERROR_MESSAGE", "PLAYER_LOGOUT" }) do
  ecouteur:RegisterEvent(e)
end
ecouteur:SetScript("OnEvent", function(_, evenement, a, b)
  if evenement == "PLAYER_LOGOUT" then
    -- On range le temps de jeu de cette session dans le bilan (déconnexion ou /reload).
    if perso then perso.joue, debutSession = ns.dureeJouee(perso.joue, debutSession, time()), time() end
    return
  end
  if not db or not db.actif then
    -- Coupé : la fenêtre de butin du jeu doit rester visible (alpha remis à 1).
    if evenement == "LOOT_CLOSED" then
      enCours, derniersSlots = false, nil
      if ticker then ticker:Cancel() end
      if LootFrame then LootFrame:SetAlpha(1) end
    end
    return
  end
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
