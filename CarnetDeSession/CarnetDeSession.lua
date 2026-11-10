-- Carnet de session : temps de jeu, or, expérience et monstres tués depuis la connexion,
-- avec l'historique des sessions précédentes.
-- Compatible Retail (Midnight) et Forever : les deux utilisent la même API.

-- WoW passe deux valeurs à chaque fichier : le nom de l'addon et une table
-- partagée entre ses fichiers (inutile ici, il n'y en a qu'un).
local NOM_ADDON, ns = ...

local PREFIXE = "|cff33ff99Carnet|r : "
local TAILLE_HISTORIQUE = 20 -- sessions gardées par personnage

-- Variables sauvegardées (déclarées dans le .toc) :
--   db      = CarnetDeSessionDB, commune à tout le compte (position, affichage)
--   session = CarnetDeSessionPerso, propre à chaque personnage : la session en cours,
--             et dans session.historique les sessions terminées
local db, session

-- Valeurs gardées en mémoire seulement (perdues à chaque /reload, c'est voulu).
-- niveauXP est le niveau qui va avec xpPrecedente : il sert à voir qu'un niveau a été
-- pris entre deux mises à jour de la barre, même si elle a fini plus haut qu'avant.
local niveau, niveauXP, xpPrecedente, xpMaxPrecedente
local pret = false

-- Depuis Midnight, certaines valeurs de combat sont « secrètes » : un addon peut les
-- transmettre mais pas les lire ni les comparer. issecretvalue dit si c'en est une.
-- Elle n'existe pas sur les vieux clients : dans ce cas rien n'est secret.
local estSecret = issecretvalue or function() return false end

---------------------------------------------------------------------------
-- Mise en forme
---------------------------------------------------------------------------

local function formatDuree(secondes)
  local h = math.floor(secondes / 3600)
  local m = math.floor(secondes % 3600 / 60)
  local s = secondes % 60
  if h > 0 then
    return string.format("%d h %02d min", h, m)
  end
  return string.format("%d min %02d s", m, s)
end

-- Les fonctions de l'API changent de nom d'une version à l'autre : on prend
-- la récente (C_CurrencyInfo) si elle existe, sinon l'ancienne, sinon la nôtre.
local iconesPieces = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString)
  or GetCoinTextureString
  or function(cuivre)
    return string.format("%d po %d pa %d pc",
      math.floor(cuivre / 10000), math.floor(cuivre % 10000 / 100), cuivre % 100)
  end

-- Montant en cuivre -> "+12 or 34 argent 5 cuivre" avec les icônes de pièces.
local function formatOr(cuivre)
  if cuivre == 0 then
    return "0"
  end
  local signe = cuivre > 0 and "|cff40ff40+|r " or "|cffff4040-|r "
  return signe .. iconesPieces(math.abs(cuivre))
end

-- 1234567 -> "1 234 567"
local function formatNombre(n)
  local texte = tostring(math.floor(n))
  local avant
  repeat
    avant = texte
    texte = texte:gsub("^(%d+)(%d%d%d)", "%1 %2")
  until texte == avant
  return texte
end

-- Même règle que pour les pièces : la fonction récente d'abord, sinon l'ancienne.
local function auNiveauMax()
  if IsPlayerAtEffectiveMaxLevel then
    return IsPlayerAtEffectiveMaxLevel()
  end
  return GetMaxLevelForPlayerExpansion ~= nil and UnitLevel("player") >= GetMaxLevelForPlayerExpansion()
end

---------------------------------------------------------------------------
-- La fenêtre
---------------------------------------------------------------------------

-- "BackdropTemplate" donne accès à SetBackdrop (fond + bordure).
local fenetre = CreateFrame("Frame", "CarnetDeSessionFrame", UIParent, "BackdropTemplate")
fenetre:SetSize(230, 121)
fenetre:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
fenetre:SetClampedToScreen(true) -- impossible de la perdre hors de l'écran
fenetre:Hide()

-- Déplacement à la souris (clic gauche maintenu).
fenetre:SetMovable(true)
fenetre:EnableMouse(true)
fenetre:RegisterForDrag("LeftButton")
fenetre:SetScript("OnDragStart", fenetre.StartMoving)
fenetre:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local point, _, pointRelatif, x, y = self:GetPoint()
  db.position = { point, pointRelatif, x, y }
end)

local _, fermer = ns.habiller(fenetre, { titre = "Carnet de session", fermer = true })

-- Une ligne = un libellé à gauche et une valeur à droite.
local lignes = {}
local function ajouterLigne(libelle)
  local index = #lignes + 1
  local y = -30 - (index - 1) * 17
  local gauche = fenetre:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  gauche:SetPoint("TOPLEFT", 12, y)
  gauche:SetText(libelle)
  local droite = fenetre:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  droite:SetPoint("TOPRIGHT", -12, y)
  droite:SetJustifyH("RIGHT")
  lignes[index] = droite
  return droite
end

local valeurTemps = ajouterLigne("Temps de jeu")
local valeurOr = ajouterLigne("Or")
local valeurNiveaux = ajouterLigne("Niveaux pris")
local valeurXP = ajouterLigne("Expérience")
local valeurMonstres = ajouterLigne("Monstres tués")

local function rafraichir()
  if not pret or not fenetre:IsShown() then
    return
  end
  local ecoule = time() - session.debut
  valeurTemps:SetText(formatDuree(ecoule))
  valeurOr:SetText(formatOr(GetMoney() - session.orDepart))
  valeurNiveaux:SetText(tostring(niveau - session.niveauDepart))

  if session.xpGagnee == 0 and auNiveauMax() then
    valeurXP:SetText("|cffaaaaaaniveau max|r")
  else
    local texteXP = formatNombre(session.xpGagnee)
    if ecoule >= 60 and session.xpGagnee > 0 then
      texteXP = texteXP .. string.format("  |cffaaaaaa(%s/h)|r", formatNombre(session.xpGagnee * 3600 / ecoule))
    end
    valeurXP:SetText(texteXP)
  end

  valeurMonstres:SetText(formatNombre(session.monstres))
end

fenetre:SetScript("OnShow", rafraichir)

local reglages -- la fenêtre de réglages commune (Reglages.lua), créée plus bas

-- Passe par les réglages pour que la case « Afficher la fenêtre » suive.
local function afficher(visible)
  if visible and not db.actif then
    print(PREFIXE .. "le carnet est coupé : active-le dans ses réglages.")
    return
  end
  reglages.changer("affiche", visible)
end

fermer:SetScript("OnClick", function()
  afficher(false)
  print(PREFIXE .. "fenêtre masquée, /carnet pour la rouvrir.")
end)

---------------------------------------------------------------------------
-- La session et l'historique
---------------------------------------------------------------------------

-- Note l'état de fin de la session en cours. Appelé à la déconnexion (et au /reload),
-- car c'est à ce moment que WoW écrit les variables sauvegardées sur le disque.
local function noterFin()
  session.fin = time()
  session.orFin = GetMoney()
  -- À la déconnexion, UnitLevel a déjà rendu un niveau périmé (test Forever du 05/11) :
  -- le niveau suivi par l'addon fait foi.
  session.niveauFin = math.max(UnitLevel("player"), niveau or 0)
end

-- Range la session terminée en tête de l'historique. Les sessions de moins
-- d'une minute (un passage éclair, une session jamais finie) sont ignorées.
local function archiver()
  if not session.debut or not session.fin or session.fin - session.debut < 60 then
    return
  end
  table.insert(session.historique, 1, {
    debut = session.debut,
    duree = session.fin - session.debut,
    orGagne = session.orFin - session.orDepart,
    xp = session.xpGagnee,
    niveaux = session.niveauFin - session.niveauDepart,
    monstres = session.monstres or 0,
  })
  while #session.historique > TAILLE_HISTORIQUE do
    table.remove(session.historique)
  end
end

local function nouvelleSession()
  session.debut = time()
  session.fin = nil
  session.orDepart = GetMoney()
  session.niveauDepart = UnitLevel("player")
  session.xpGagnee = 0
  session.monstres = 0
end

local function afficherHistorique()
  if #session.historique == 0 then
    print(PREFIXE .. "aucune session terminée pour ce personnage.")
    return
  end
  print(PREFIXE .. "dernières sessions :")
  for i = 1, math.min(10, #session.historique) do
    local s = session.historique[i]
    print(string.format("  %s  %s  %s  %s XP  %d monstres",
      date("%d/%m %H:%M", s.debut), formatDuree(s.duree), formatOr(s.orGagne),
      formatNombre(s.xp), s.monstres))
  end
end

---------------------------------------------------------------------------
-- Les événements
---------------------------------------------------------------------------

-- Chaque événement appelle la fonction du même nom dans cette table.
local evenements = {}

-- Appelé par Reglages.lua quand les variables sauvegardées sont lues.
local function charger(d)
  db = d
  CarnetDeSessionPerso = CarnetDeSessionPerso or {}
  session = CarnetDeSessionPerso
  -- Champs ajoutés en v0.2 : une session de la v0.1 ne les a pas encore.
  session.historique = session.historique or {}
  session.monstres = session.monstres or 0
  session.xpGagnee = session.xpGagnee or 0

  if db.position then
    local point, pointRelatif, x, y = unpack(db.position)
    fenetre:ClearAllPoints()
    fenetre:SetPoint(point, UIParent, pointRelatif, x, y)
  end
end

-- Se déclenche à la connexion, à chaque /reload et à chaque écran de chargement.
function evenements.PLAYER_ENTERING_WORLD(connexion, rechargement)
  if pret then
    return
  end
  -- Nouvelle connexion : on range l'ancienne session et on repart de zéro.
  -- Simple /reload : on garde la session.
  if connexion or not session.debut then
    archiver()
    nouvelleSession()
  end
  niveau = UnitLevel("player")
  niveauXP, xpPrecedente, xpMaxPrecedente = niveau, UnitXP("player"), UnitXPMax("player")
  pret = true

  fenetre:SetShown(db.actif and db.affiche)
  C_Timer.NewTicker(1, rafraichir) -- le temps de jeu avance chaque seconde
end

function evenements.PLAYER_LOGOUT()
  noterFin()
end

function evenements.PLAYER_XP_UPDATE(unite)
  if unite ~= "player" or not pret then
    return
  end
  -- Coupé : on ne compte pas, mais on suit la barre pour repartir juste à la réactivation.
  if not db.actif then
    xpPrecedente, xpMaxPrecedente = UnitXP("player"), UnitXPMax("player")
    niveauXP = math.max(UnitLevel("player"), niveau)
    niveau = math.max(niveau, niveauXP)
    return
  end
  -- UnitLevel peut encore donner l'ancien niveau juste après un passage de niveau :
  -- on prend aussi celui reçu par PLAYER_LEVEL_UP, et une barre qui redescend
  -- veut dire, elle aussi, qu'un niveau a été pris.
  local xp, xpMax = UnitXP("player"), UnitXPMax("player")
  local nv = math.max(UnitLevel("player"), niveau)
  if nv == niveauXP and xp >= xpPrecedente then
    session.xpGagnee = session.xpGagnee + (xp - xpPrecedente)
  elseif nv <= niveauXP + 1 then
    -- Un niveau pris : la fin de l'ancienne barre, plus le début de la nouvelle.
    session.xpGagnee = session.xpGagnee + (xpMaxPrecedente - xpPrecedente) + xp
    nv = niveauXP + 1
  end
  -- Plusieurs niveaux d'un coup : on ne devine pas, on repart de la barre actuelle.
  xpPrecedente, xpMaxPrecedente, niveauXP = xp, xpMax, nv
  niveau = math.max(niveau, nv) -- au cas où PLAYER_LEVEL_UP ne serait pas arrivé
  rafraichir()
end

function evenements.PLAYER_LEVEL_UP(nouveauNiveau)
  if not pret then
    return
  end
  niveau = math.max(niveau, nouveauNiveau)
  if not db.actif then
    return
  end
  print(PREFIXE .. string.format("niveau %d atteint !", nouveauNiveau))
  rafraichir()
end

function evenements.PLAYER_MONEY()
  rafraichir()
end

-- Un ennemi tué par toi ou ton groupe. Midnight a retiré le journal de combat
-- complet aux addons, mais cet événement reste. On ne compte que les créatures :
-- un joueur tué en JcJ a un identifiant qui commence par "Player".
-- Si l'identifiant est secret, on ne peut pas le lire : on compte quand même.
function evenements.PARTY_KILL(_, cibleGUID)
  if not pret or not db.actif then
    return
  end
  -- estSecret passe en premier : même un simple test « cibleGUID and » lit la valeur.
  if not estSecret(cibleGUID) and cibleGUID and not cibleGUID:find("^Creature") and not cibleGUID:find("^Vehicle") then
    return
  end
  session.monstres = session.monstres + 1
  rafraichir()
end

local ecouteur = CreateFrame("Frame")
for nom in pairs(evenements) do
  ecouteur:RegisterEvent(nom)
end
ecouteur:SetScript("OnEvent", function(_, evenement, ...)
  local f = evenements[evenement]
  if f then f(...) end
end)

---------------------------------------------------------------------------
-- Les réglages (fenêtre commune de Reglages.lua, menu « Addons de Valentin »)
---------------------------------------------------------------------------

local function remettreAZero()
  -- La session en cours part dans l'historique avant la remise à zéro.
  noterFin()
  archiver()
  nouvelleSession()
  niveau = UnitLevel("player")
  niveauXP, xpPrecedente, xpMaxPrecedente = niveau, UnitXP("player"), UnitXPMax("player")
  rafraichir()
  if reglages.majFenetre then reglages.majFenetre() end
  print(PREFIXE .. "session remise à zéro.")
end

local function recentrer()
  db.position = nil
  fenetre:ClearAllPoints()
  fenetre:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
  afficher(true)
end

reglages = ns.creerReglages({
  titre = "Carnet de session",
  icone = "Interface\\Icons\\INV_Misc_Book_09",
  nomDB = "CarnetDeSessionDB",
  defauts = { actif = true, affiche = true, minimap = false },
  options = {
    { cle = "actif", libelle = "Activer Carnet de session",
      aide = "Compte le temps de jeu, l'or, l'expérience et les monstres tués de la session." },
    { cle = "affiche", libelle = "Afficher la fenêtre du carnet",
      aide = "Elle se déplace à la souris ; « Recentrer » la remet au milieu de l'écran." },
    { cle = "minimap", libelle = "Icône à part autour de la minimap",
      aide = "En plus de la ligne dans l'icône commune des addons de Valentin." },
  },
  boutons = {
    { texte = "Remettre à zéro", aide = "Range la session en cours dans l'historique et repart de zéro.",
      action = remettreAZero },
    { texte = "Recentrer", aide = "Replace la fenêtre du carnet au milieu de l'écran.", action = recentrer },
  },
  -- Les dernières sessions de ce personnage, directement dans la fenêtre.
  ongletContenu = "Sessions",
  contenu = function(f, y)
    local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, y - 6)
    t:SetText("Dernières sessions")
    local liste = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    liste:SetPoint("TOPLEFT", 16, y - 34)
    liste:SetWidth(410)
    liste:SetJustifyH("LEFT")
    -- Une session par ligne, jamais coupée en deux (sinon elle déborderait).
    if liste.SetWordWrap then liste:SetWordWrap(false) end
    local function maj()
      if not session or #session.historique == 0 then
        liste:SetText("|cff888888Aucune session terminée pour ce personnage.|r")
        return
      end
      local l = {}
      for i = 1, math.min(5, #session.historique) do
        local s = session.historique[i]
        l[#l + 1] = string.format("%s  %s  %s  %s XP  %d tués", date("%d/%m %H:%M", s.debut),
          formatDuree(s.duree), formatOr(s.orGagne), formatNombre(s.xp), s.monstres)
      end
      liste:SetText(table.concat(l, "\n"))
    end
    return y - 34 - 5 * 14 - 6, maj
  end,
  auChargement = charger,
  surChangement = function(d)
    if pret then fenetre:SetShown(d.actif and d.affiche) end
  end,
})

---------------------------------------------------------------------------
-- La commande /carnet
---------------------------------------------------------------------------

SLASH_CARNETDESESSION1 = "/carnet"
SlashCmdList.CARNETDESESSION = function(message)
  local commande = strtrim(message or ""):lower()
  if commande == "" then
    afficher(not fenetre:IsShown())
  elseif commande == "options" or commande == "reglages" then
    reglages.ouvrir()
  elseif commande == "raz" then
    remettreAZero()
  elseif commande == "historique" then
    afficherHistorique()
  elseif commande == "centre" then
    recentrer()
  elseif commande == "debug" then
    -- Montre les deux chiffres que l'addon soustrait, pour comparer avec ton sac.
    print(PREFIXE .. "or actuel : " .. iconesPieces(GetMoney()))
    print(PREFIXE .. "or au début de la session : " .. iconesPieces(session.orDepart))
    print(PREFIXE .. "session commencée à " .. date("%H:%M:%S", session.debut))
  else
    print(PREFIXE .. "commandes :")
    print("  /carnet : afficher ou masquer la fenêtre")
    print("  /carnet options : les réglages (activer ou couper le carnet)")
    print("  /carnet raz : ranger la session dans l'historique et repartir de zéro")
    print("  /carnet historique : les 10 dernières sessions de ce personnage")
    print("  /carnet centre : replacer la fenêtre au centre")
    print("  /carnet debug : afficher l'or de départ et l'or actuel")
  end
end
