-- ============================================================================
-- Fenêtres déplaçables : toutes les grandes fenêtres du jeu se déplacent à la souris et
-- GARDENT leur place d'une ouverture à l'autre et d'une session à l'autre.
--
--   Glisser la barre de titre (bouton gauche) : déplacer la fenêtre
--   Ctrl + molette sur la barre de titre      : changer sa taille (de 50 à 150 %, par pas de 5 %)
--   Clic droit sur la barre de titre          : remettre à sa place d'origine, taille normale,
--                                               ne plus gérer cette fenêtre
--   /fen : les réglages    /fen reset : tout remettre    /fen etat : l'état    /fen aide
--
-- Comment ça marche, en deux mots. Pour chaque fenêtre de la liste (ns.FENETRES), l'addon pose
-- une POIGNÉE : un cadre à nous, transparent, collé sur la barre de titre de la fenêtre. C'est
-- la poignée qui reçoit la souris ; elle déplace la fenêtre avec StartMoving. On n'écrit JAMAIS
-- un champ d'un cadre du jeu (« cadre.champ = … » contaminerait le jeu, et il refuserait ensuite
-- d'ouvrir la carte ou un panneau en combat : ADDON_ACTION_FORBIDDEN). On n'appelle que des
-- méthodes (SetMovable, SetPoint, SetScale, HookScript, hooksecurefunc) et on tient nos
-- drapeaux dans des tables à nous.
--
-- Le gestionnaire de panneaux du jeu (Blizzard_UIParentPanelManager) replace les fenêtres à
-- chaque ouverture et à chaque ouverture d'une autre fenêtre (UpdateUIPanelPositions). Donc on
-- remet notre place : tout de suite quand la fenêtre s'affiche (le jeu a déjà posé la sienne
-- juste avant), et à l'image suivante après chaque SetPoint du jeu (hooksecurefunc), avec un
-- drapeau anti-boucle pour ne pas réagir à nos propres SetPoint.
--
-- En combat, une fenêtre « protégée » ne se touche pas (le jeu refuserait : ADDON_ACTION_BLOCKED).
-- On note « à refaire » et on le fait à la fin du combat.
--
-- Le fichier a deux parties : la logique pure (testée hors jeu, tests/Fenetres_simu.lua) puis
-- tout ce qui parle au jeu.
-- ============================================================================

local NOM_ADDON, ns = ...

local DEFAUTS = {
  actif = true,
  memoriser = true,   -- garder la place (et la taille) de chaque fenêtre
  dansEcran = true,   -- garder les fenêtres dans l'écran (décocher pour les poser sur un second écran)
  secondEcran = false, -- fenêtre du jeu étirée sur deux écrans : le jeu sur l'un, les fenêtres sur l'autre
  mondeAGauche = false, -- second écran : le jeu sur l'écran de gauche (sinon celui de droite)
  molette = true,     -- Ctrl + molette change la taille
  fenetres = {},      -- [nom du cadre] = { x, y, echelle } : ce qu'on a gardé
  ignorees = {},      -- [nom du cadre] = true : fenêtres que le joueur ne veut plus voir gérées
}

-- ---------------------------------------------------------------------------
-- Partie « logique pure » : aucune fonction du jeu, donc testable hors jeu.
-- ---------------------------------------------------------------------------

-- Les fenêtres visées. Un nom absent du jeu est simplement ignoré.
--   nom   : le nom global du cadre
--   titre : le nom affiché dans les messages et les listes
--   addon : l'addon du jeu qui crée le cadre quand il est chargé à la demande (nil : toujours là)
--   g, d, h : marges de la poignée (pixels). g = à gauche (le portrait), d = à droite (la croix
--             et parfois un bouton agrandir), h = hauteur. Par défaut 58, 26 et 22, ce qui colle
--             à la barre de titre des fenêtres à portrait de Blizzard (PortraitFrameTemplate :
--             titre entre x = 58 et x = -24, hauteur 20). Réglées à la main pour les autres.
--   sauf  : fonction facultative ; si elle rend vrai, on ne remet pas notre place (la carte du
--           monde agrandie se place toute seule en haut au centre).
-- « VÉRIFIÉ » = le nom est dans le code de l'interface de Forever (branche forever de wow-ui-source).
-- « supposé » = vu seulement dans d'autres versions du jeu ou jamais vu : à contrôler en jeu avec
-- le diagnostic (FenetresDB.diagnostic.introuvables).
ns.FENETRES = {
  { nom = "CharacterFrame", titre = "Personnage" },                                        -- VÉRIFIÉ (UIPanels_Game)
  { nom = "PlayerSpellsFrame", titre = "Grimoire et talents", addon = "Blizzard_PlayerSpells", d = 56 }, -- VÉRIFIÉ
  { nom = "SpellBookFrame", titre = "Grimoire (ancien)" },                                 -- supposé : seulement dans Vanilla et Cata
  { nom = "ClassTalentFrame", titre = "Talents (ancien)", addon = "Blizzard_ClassTalentUI" },  -- supposé : absent de Forever
  { nom = "PlayerTalentFrame", titre = "Talents (très ancien)", addon = "Blizzard_TalentUI" }, -- supposé : absent de Forever
  { nom = "WorldMapFrame", titre = "Carte et journal des quêtes", d = 80, sauf = function(f)   -- VÉRIFIÉ (Blizzard_WorldMap)
      return f.IsMaximized ~= nil and f:IsMaximized() and true or false
    end },
  { nom = "QuestFrame", titre = "Quête (personnage)" },                                    -- VÉRIFIÉ
  { nom = "GossipFrame", titre = "Discussion (personnage)" },                              -- VÉRIFIÉ
  { nom = "MerchantFrame", titre = "Marchand" },                                           -- VÉRIFIÉ
  { nom = "MailFrame", titre = "Courrier" },                                               -- VÉRIFIÉ (Blizzard_MailFrame)
  { nom = "OpenMailFrame", titre = "Lettre ouverte" },                                     -- VÉRIFIÉ
  { nom = "BankFrame", titre = "Banque" },                                                 -- VÉRIFIÉ
  { nom = "GuildBankFrame", titre = "Banque de guilde", addon = "Blizzard_GuildBankUI", g = 30, d = 30 }, -- VÉRIFIÉ
  { nom = "AuctionHouseFrame", titre = "Hôtel des ventes", addon = "Blizzard_AuctionHouseUI" }, -- VÉRIFIÉ
  { nom = "AuctionFrame", titre = "Hôtel des ventes (ancien)", addon = "Blizzard_AuctionUI" },  -- supposé : absent de Forever
  { nom = "ClassTrainerFrame", titre = "Maître de classe ou de métier", addon = "Blizzard_TrainerUI" }, -- VÉRIFIÉ
  { nom = "ProfessionsFrame", titre = "Métiers", addon = "Blizzard_Professions", d = 56 }, -- VÉRIFIÉ
  { nom = "TradeSkillFrame", titre = "Métiers (ancien)", addon = "Blizzard_TradeSkillUI" },    -- supposé : absent de Forever
  { nom = "ProfessionsBookFrame", titre = "Livre des métiers", addon = "Blizzard_ProfessionsBook" }, -- supposé : exclu du type de jeu Forever d'après le .xml
  { nom = "FriendsFrame", titre = "Amis" },                                                -- VÉRIFIÉ (Blizzard_FriendsFrame)
  { nom = "CommunitiesFrame", titre = "Communautés et guilde", addon = "Blizzard_Communities", d = 56 }, -- VÉRIFIÉ
  { nom = "GuildFrame", titre = "Guilde (ancien)", addon = "Blizzard_GuildUI" },           -- supposé : absent de Forever
  { nom = "GuildControlUI", titre = "Contrôle de la guilde", addon = "Blizzard_GuildControlUI" }, -- VÉRIFIÉ
  { nom = "PVEFrame", titre = "Recherche de groupe", addon = nil },                        -- supposé : Blizzard_GroupFinder l'exclut du type de jeu Forever
  { nom = "LFGParentFrame", titre = "Recherche de groupe (ancien)", addon = "Blizzard_GroupFinder_VanillaStyle" }, -- supposé : nom non relu dans le code, chargé selon le type de jeu
  { nom = "CollectionsJournal", titre = "Collections", addon = "Blizzard_Collections" },   -- VÉRIFIÉ
  { nom = "AchievementFrame", titre = "Hauts faits", addon = "Blizzard_AchievementUI", g = 40, d = 40, h = 28 }, -- VÉRIFIÉ le nom ; marges supposées
  { nom = "EncounterJournal", titre = "Guide des donjons", addon = "Blizzard_EncounterJournal" }, -- VÉRIFIÉ
  { nom = "InspectFrame", titre = "Inspection", addon = "Blizzard_InspectUI" },            -- VÉRIFIÉ
  { nom = "TradeFrame", titre = "Échange" },                                               -- VÉRIFIÉ
  { nom = "ItemTextFrame", titre = "Texte d'objet" },                                      -- VÉRIFIÉ
  { nom = "TaxiFrame", titre = "Maître de vol", g = 30, d = 30 },                          -- VÉRIFIÉ
  { nom = "FlightMapFrame", titre = "Carte de vol", addon = "Blizzard_FlightMap", d = 56 }, -- VÉRIFIÉ ; marges supposées
  { nom = "MacroFrame", titre = "Macros", addon = "Blizzard_MacroUI" },                    -- VÉRIFIÉ
  { nom = "AddonList", titre = "Liste des addons" },                                       -- VÉRIFIÉ (Blizzard_AddOnList)
  { nom = "SettingsPanel", titre = "Options du jeu", addon = "Blizzard_Settings_Shared", g = 30 }, -- VÉRIFIÉ
  { nom = "GameMenuFrame", titre = "Menu du jeu", g = 20, d = 20, h = 30 },                -- VÉRIFIÉ le nom ; marges supposées
  { nom = "DressUpFrame", titre = "Essayage", d = 56 },                                    -- VÉRIFIÉ
  { nom = "StableFrame", titre = "Écurie", addon = "Blizzard_StableUI" },                  -- VÉRIFIÉ
  { nom = "HelpFrame", titre = "Aide", g = 30 },                                           -- VÉRIFIÉ
  { nom = "CalendarFrame", titre = "Calendrier", addon = "Blizzard_Calendar", g = 40, d = 40 }, -- VÉRIFIÉ le nom ; marges supposées
  { nom = "LootFrame", titre = "Butin" },                                                  -- VÉRIFIÉ (cadre géré aussi par le mode édition)
  { nom = "ItemSocketingFrame", titre = "Sertissage", addon = "Blizzard_ItemSocketingUI" }, -- VÉRIFIÉ
  { nom = "TabardFrame", titre = "Tabard de guilde" },                                     -- VÉRIFIÉ
  { nom = "PetitionFrame", titre = "Pétition de guilde" },                                 -- VÉRIFIÉ
  { nom = "GuildRegistrarFrame", titre = "Maître de guilde" },                             -- VÉRIFIÉ
  { nom = "ArchaeologyFrame", titre = "Archéologie", addon = "Blizzard_ArchaeologyUI" },   -- VÉRIFIÉ
  { nom = "BlackMarketFrame", titre = "Marché noir", addon = "Blizzard_BlackMarketUI" },   -- VÉRIFIÉ
  { nom = "ItemUpgradeFrame", titre = "Amélioration d'objet", addon = "Blizzard_ItemUpgradeUI" }, -- VÉRIFIÉ
  { nom = "TransmogFrame", titre = "Transmogrification", addon = "Blizzard_Transmog" },    -- VÉRIFIÉ
  { nom = "ClickBindingFrame", titre = "Assignation des clics", addon = "Blizzard_ClickBindingUI" }, -- VÉRIFIÉ
  { nom = "ExpansionLandingPage", titre = "Page de l'extension", addon = "Blizzard_ExpansionLandingPage", d = 56 }, -- VÉRIFIÉ
}

local function nb(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- La clé sous laquelle une fenêtre est rangée dans la sauvegarde : son nom de cadre, s'il est valide
-- (lettres, chiffres et soulignés), sinon nil.
function ns.cleFenetre(nom)
  if type(nom) ~= "string" then return nil end
  nom = nom:gsub("^%s+", ""):gsub("%s+$", "")
  if nom == "" or nom:find("[^%w_]") then return nil end
  return nom
end

-- Les marges de la poignée d'une fenêtre : gauche, droite, hauteur.
function ns.margesDe(entree)
  entree = type(entree) == "table" and entree or {}
  local function valeur(v, defaut) if nb(v) and v >= 0 then return v end return defaut end
  return valeur(entree.g, 58), valeur(entree.d, 26), valeur(entree.h, 22)
end

-- La place d'une fenêtre à partir de ce que le jeu en dit (GetLeft et GetTop sont dans l'échelle
-- de la fenêtre). On la range en unités de l'écran (UIParent), mesurée depuis son coin haut gauche :
--   { point = "TOPLEFT", x, y }   avec y négatif vers le bas, comme le gestionnaire de panneaux.
-- Les deux échelles sont les échelles EFFECTIVES (GetEffectiveScale). largeurParent est lu et
-- contrôlé mais pas encore utilisé : il est là pour l'étape des seconds écrans.
function ns.pointDepuis(gauche, haut, echelleFenetre, echelleParent, largeurParent, hauteurParent)
  if not (nb(gauche) and nb(haut) and nb(hauteurParent) and nb(largeurParent)) then return nil end
  local ef = nb(echelleFenetre) and echelleFenetre or 1
  local ep = nb(echelleParent) and echelleParent or 1
  if ef <= 0 or ep <= 0 then return nil end
  local k = ef / ep
  return { point = "TOPLEFT", x = gauche * k, y = haut * k - hauteurParent }
end

-- L'inverse : le décalage à donner à SetPoint("TOPLEFT", UIParent, "TOPLEFT", ox, oy) pour une place
-- en unités de l'écran. Le décalage d'un SetPoint est dans l'échelle de la fenêtre.
function ns.decalageDepuis(x, y, echelleFenetre, echelleParent)
  local ef = nb(echelleFenetre) and echelleFenetre > 0 and echelleFenetre or 1
  local ep = nb(echelleParent) and echelleParent > 0 and echelleParent or 1
  local k = ef / ep
  return x / k, y / k
end

-- Ramène une place dans l'écran (utile quand la résolution a changé). x et y : coin haut gauche, mesuré
-- depuis le coin haut gauche de l'écran (y négatif vers le bas) ; largeur, hauteur et écran : en unités
-- de l'écran. Une fenêtre plus grande que l'écran est collée en haut à gauche.
-- Second écran : la fenêtre du jeu couvre deux écrans côte à côte (au moins 2,9 fois plus large que haute).
function ns.deuxEcrans(largeur, hauteur)
  return type(largeur) == "number" and type(hauteur) == "number" and hauteur > 0 and largeur / hauteur >= 2.9
end

-- Second écran : les bornes d'une fenêtre. L'interface (UIParent) n'occupe qu'un écran ; l'autre est à
-- gauche (le jeu à droite) ou à droite (le jeu à gauche). Rend x, y bornés sur les DEUX écrans.
function ns.bornerDeux(x, y, largeur, hauteur, largeurEcran, hauteurEcran, mondeAGauche)
  if mondeAGauche then
    return ns.borner(x, y, largeur, hauteur, largeurEcran * 2, hauteurEcran)
  end
  local bx, by = ns.borner(x + largeurEcran, y, largeur, hauteur, largeurEcran * 2, hauteurEcran)
  return bx - largeurEcran, by
end

function ns.borner(x, y, largeur, hauteur, largeurEcran, hauteurEcran)
  if not (nb(x) and nb(y)) then return x, y end
  if not (nb(largeur) and nb(hauteur) and nb(largeurEcran) and nb(hauteurEcran)) then return x, y end
  local maxX = math.max(largeurEcran - largeur, 0)
  local minY = math.min(-(hauteurEcran - hauteur), 0)
  if x < 0 then x = 0 elseif x > maxX then x = maxX end
  if y > 0 then y = 0 elseif y < minY then y = minY end
  return x, y
end

-- La taille suivante (échelle du cadre, 1 = 100 %) : un pas de 5 %, de 50 à 150 %.
-- sens > 0 : plus grand ; sinon plus petit. Une valeur à 97 % monte à 100 % ou descend à 95 %.
function ns.echelleSuivante(actuelle, sens)
  local p = nb(actuelle) and math.floor(actuelle * 100 + 0.5) or 100
  if (tonumber(sens) or 0) > 0 then
    p = math.floor(p / 5) * 5 + 5
  else
    p = math.ceil(p / 5) * 5 - 5
  end
  if p < 50 then p = 50 elseif p > 150 then p = 150 end
  return p / 100
end

-- Une place lue dans la sauvegarde, nettoyée : { x, y, echelle } (chacun facultatif) ou nil.
function ns.lirePlace(t)
  if type(t) ~= "table" then return nil end
  local p = {}
  if nb(t.x) and nb(t.y) and math.abs(t.x) <= 20000 and math.abs(t.y) <= 20000 then p.x, p.y = t.x, t.y end
  if nb(t.echelle) and t.echelle >= 0.5 and t.echelle <= 1.5 then p.echelle = t.echelle end
  if p.x == nil and p.echelle == nil then return nil end
  return p
end

-- La même place sans sa position, ou sans sa taille (nil quand il ne reste rien).
function ns.sansPosition(place)
  local p = ns.lirePlace(place)
  if not p or not p.echelle then return nil end
  return { echelle = p.echelle }
end
function ns.sansEchelle(place)
  local p = ns.lirePlace(place)
  if not p or p.x == nil then return nil end
  return { x = p.x, y = p.y }
end

-- La ligne d'une liste : « Personnage : déplacée, taille 110 % ».
function ns.texteLigne(titre, place)
  local p = ns.lirePlace(place)
  local morceaux = {}
  if p and p.x ~= nil then morceaux[#morceaux + 1] = "déplacée" end
  if p and p.echelle then morceaux[#morceaux + 1] = "taille " .. math.floor(p.echelle * 100 + 0.5) .. " %" end
  if #morceaux == 0 then return tostring(titre or "?") end
  return tostring(titre or "?") .. " : " .. table.concat(morceaux, ", ")
end

if not CreateFrame then return end -- hors jeu : la suite ne sert qu'en jeu

-- ---------------------------------------------------------------------------
-- Les fonctions du jeu, toutes protégées : si l'une manque sur une version, la fonction
-- concernée est simplement absente, jamais une erreur.
-- ---------------------------------------------------------------------------

local db

-- Appelle f sous pcall ; rend ses résultats, ou rien si elle manque ou plante.
local function sur(f, ...)
  if type(f) ~= "function" then return end
  local ok, a, b, c, d = pcall(f, ...)
  if ok then return a, b, c, d end
end

local function enCombat() return InCombatLockdown and InCombatLockdown() and true or false end

-- La couche (strate) juste au-dessus d'une autre, sans dépasser celle des dialogues plein écran.
local STRATES = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG" }
function ns.strateAuDessus(strate)
  for i, s in ipairs(STRATES) do
    if s == strate then return STRATES[math.min(i + 1, #STRATES)] end
  end
  return "HIGH"
end

local function dire(texte)
  if ns.reglages and ns.reglages.dire then ns.reglages.dire(texte) else print("|cffffd200Fenêtres déplaçables|r : " .. texte) end
end

-- Le cadre ne peut-il pas être touché maintenant ? Vrai en combat pour une fenêtre protégée (ou quand
-- on ne sait pas : on préfère ne rien tenter). Hors combat, jamais.
local function estBloque(fenetre)
  if not enCombat() then return false end
  if type(fenetre.IsProtected) ~= "function" then return true end
  local ok, protege = pcall(fenetre.IsProtected, fenetre)
  if not ok then return true end
  return protege and true or false
end

-- ----- l'état de chaque fenêtre suivie. Tout est tenu ICI, jamais dans le cadre du jeu.
--   suivi[cle]          : l'enregistrement de la fenêtre (voir creerRec)
--   parFenetre[cadre]   : le même, retrouvé depuis le cadre (clés faibles : rien n'est retenu en trop)
local suivi = {}
local parFenetre = setmetatable({}, { __mode = "k" })
local refusCombat = {}      -- [cle] = nombre de refus en combat (écrit dans le diagnostic)
local messageCombatDit = false

-- La fenêtre est-elle gérée en ce moment ?
local function gere(rec)
  return db ~= nil and db.actif and not (db.ignorees and db.ignorees[rec.cle]) and true or false
end

local function placeGardee(cle)
  if not (db and db.fenetres) then return nil end
  return ns.lirePlace(db.fenetres[cle])
end

local function garderPlace(rec, place)
  if not (db and db.fenetres) then return end
  db.fenetres[rec.cle] = ns.lirePlace(place) -- nil efface
end

-- Pendant une action sur toutes les fenêtres, on ne redessine la page de réglages qu'à la fin.
local groupe = false
local function rafraichirReglages()
  if groupe then return end
  if ns.reglages and ns.reglages.majFenetre then pcall(ns.reglages.majFenetre) end
end

-- Un refus en combat : compté, et un seul message par combat.
local function refuserEnCombat(rec, action)
  refusCombat[rec.cle] = (refusCombat[rec.cle] or 0) + 1
  if not messageCombatDit then
    messageCombatDit = true
    dire("cette fenêtre ne peut pas être " .. action .. " en combat.")
  end
end

-- ----- lire et poser une place

-- Où est la fenêtre en ce moment, en unités de l'écran ? ({ point, x, y } ou nil)
local function lirePoint(rec)
  local f = rec.fenetre
  local ok, res = pcall(function()
    local gauche, haut = f:GetLeft(), f:GetTop()
    if not (nb(gauche) and nb(haut)) then return nil end
    return ns.pointDepuis(gauche, haut, f:GetEffectiveScale(), UIParent:GetEffectiveScale(),
      UIParent:GetWidth(), UIParent:GetHeight())
  end)
  if ok then return res end
end

-- Pose la fenêtre à une place : { x, y, echelle } (la taille est facultative). Le drapeau « occupé »
-- empêche notre crochet de réagir à nos propres SetPoint. Rend vrai si tout s'est bien passé.
local function poser(rec, place)
  local f = rec.fenetre
  rec.occupe = true
  local ok = pcall(function()
    if place.echelle then
      local actuelle = f:GetScale()
      if not nb(actuelle) or math.abs(actuelle - place.echelle) > 0.001 then f:SetScale(place.echelle) end
    end
    if place.x == nil then return end
    local ef, ep = f:GetEffectiveScale(), UIParent:GetEffectiveScale()
    local x, y = place.x, place.y
    if db and db.dansEcran then
      local k = (nb(ef) and nb(ep) and ep > 0) and ef / ep or 1
      if ns.secondEcranActif then
        x, y = ns.bornerDeux(x, y, f:GetWidth() * k, f:GetHeight() * k, UIParent:GetWidth(), UIParent:GetHeight(),
          db.mondeAGauche)
      else
        x, y = ns.borner(x, y, f:GetWidth() * k, f:GetHeight() * k, UIParent:GetWidth(), UIParent:GetHeight())
      end
    end
    local ox, oy = ns.decalageDepuis(x, y, ef, ep)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", ox, oy)
  end)
  rec.occupe = false
  return ok
end

-- Remet notre place gardée (position et taille). Appelée à l'ouverture de la fenêtre et à l'image
-- qui suit chaque SetPoint du jeu.
local function reappliquer(rec)
  if not (gere(rec) and db.memoriser) or rec.deplace then return end
  local place = placeGardee(rec.cle)
  if not place then return end
  local f = rec.fenetre
  if rec.entree.sauf and sur(rec.entree.sauf, f) then return end
  if estBloque(f) then
    -- Compté une seule fois par « à refaire » (le jeu peut replacer la fenêtre plusieurs fois d'affilée).
    if not rec.arefaire then refusCombat[rec.cle] = (refusCombat[rec.cle] or 0) + 1 end
    rec.arefaire = true
    return
  end
  rec.arefaire = false
  if place.x ~= nil then
    poser(rec, place)
  elseif place.echelle then
    -- Seulement une taille gardée : on garde l'endroit que le jeu a choisi, avec la taille voulue.
    local actuelle = sur(f.GetScale, f)
    if not nb(actuelle) or math.abs(actuelle - place.echelle) > 0.001 then
      local pt = lirePoint(rec)
      sur(f.SetScale, f, place.echelle)
      if pt then poser(rec, { x = pt.x, y = pt.y }) end
    end
  end
end

-- À l'image suivante (une seule fois, même si le jeu appelle SetPoint dix fois d'affilée).
local function planifier(rec)
  if rec.planifie then return end
  rec.planifie = true
  if not (C_Timer and C_Timer.After) then rec.planifie = false return end
  C_Timer.After(0, function()
    rec.planifie = false
    reappliquer(rec)
  end)
end

-- ----- l'état d'origine du cadre, pour le rendre tel qu'on l'a trouvé

local function capturer(rec)
  local f = rec.fenetre
  rec.original = {
    movable = sur(f.IsMovable, f) and true or false,
    clamped = sur(f.IsClampedToScreen, f) and true or false,
    echelle = sur(f.GetScale, f),
  }
end

-- Rend la fenêtre mobile et fixe son comportement « dans l'écran » (une seule fois par réglage).
local function prendre(rec)
  local f = rec.fenetre
  if estBloque(f) then rec.aprendre = true return end
  rec.aprendre = false
  sur(f.SetMovable, f, true)
  sur(f.SetClampedToScreen, f, db and db.dansEcran and true or false)
  rec.pris = true
end

-- Les points que le jeu a posés (depuis le dernier ClearAllPoints du jeu) : la place « d'origine ».
local function rendreAuJeu(rec)
  local f = rec.fenetre
  if #rec.pointsJeu == 0 or estBloque(f) then return false end
  rec.occupe = true
  pcall(function()
    f:ClearAllPoints()
    for _, p in ipairs(rec.pointsJeu) do f:SetPoint(unpack(p, 1, p.n)) end
  end)
  rec.occupe = false
  return true
end

-- On arrête de gérer la fenêtre : mobilité et « dans l'écran » comme avant, taille d'origine, et la
-- place que le jeu avait choisie. Bloqué en combat : à la fin du combat.
local function restaurer(rec)
  if not rec.pris then return end
  local f = rec.fenetre
  if estBloque(f) then rec.arestaurer = true return end
  rec.arestaurer = false
  local o = rec.original or {}
  sur(f.SetMovable, f, o.movable and true or false)
  sur(f.SetClampedToScreen, f, o.clamped and true or false)
  local actuelle = sur(f.GetScale, f)
  if nb(o.echelle) and nb(actuelle) and math.abs(actuelle - o.echelle) > 0.001 then sur(f.SetScale, f, o.echelle) end
  rec.pris = false
  rendreAuJeu(rec)
end

-- ----- la poignée

local function majPoignee(rec)
  local p, f = rec.poignee, rec.fenetre
  if not p then return end
  if not gere(rec) then p:Hide() return end
  -- La poignée va sur la couche JUSTE AU-DESSUS de la fenêtre. Vu en jeu sur Forever (12/11) : sur la
  -- même couche, même avec un niveau bien plus haut, la souris restait à la fenêtre du jeu (aucun
  -- survol, aucun glisser ; seule la molette passait). Un cadre sur la couche suivante la reçoit.
  local strate = sur(f.GetFrameStrata, f)
  if strate then sur(p.SetFrameStrata, p, ns.strateAuDessus(strate)) end
  local niveau = sur(f.GetFrameLevel, f)
  if nb(niveau) then sur(p.SetFrameLevel, p, math.min(niveau + 600, 9990)) end
  -- La poignée a l'échelle de la fenêtre : ses marges (portrait, croix) suivent la taille de la fenêtre.
  local echelle = sur(f.GetScale, f)
  if nb(echelle) and echelle > 0 then sur(p.SetScale, p, echelle) end
  local visible = sur(f.IsVisible or f.IsShown, f)
  if visible then p:Show() else p:Hide() end
end

-- ----- le glisser
-- On demande d'abord au jeu de faire suivre la souris (StartMoving). En jeu sur Forever (12/11), la
-- taille changeait mais la fenêtre ne bougeait pas : le jeu ignorait StartMoving sur ses fenêtres.
-- Donc on surveille : si la souris a bougé et pas la fenêtre, on passe au glisser « à la main » :
-- à chaque image, on pose nous-mêmes la fenêtre sous la souris (SetPoint, comme pour la taille).
local function deplacerSousSouris(rec)
  local g, f = rec.glisse, rec.fenetre
  if not g or estBloque(f) or not GetCursorPosition then return end
  local cx, cy = GetCursorPosition()
  local ef, ep = sur(f.GetEffectiveScale, f), sur(UIParent.GetEffectiveScale, UIParent)
  if not (nb(cx) and nb(cy) and nb(ef) and nb(ep) and ef > 0) then return end
  local gauche, haut = g.gauche + (cx - g.cx) / ef, g.haut + (cy - g.cy) / ef
  local pt = ns.pointDepuis(gauche, haut, ef, ep, UIParent:GetWidth(), UIParent:GetHeight())
  if not pt then return end
  local ox, oy = ns.decalageDepuis(pt.x, pt.y, ef, ep)
  rec.occupe = true
  pcall(function()
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", ox, oy)
  end)
  rec.occupe = false
end

local function suivreSouris(rec)
  local g, f = rec.glisse, rec.fenetre
  if not g then return end
  if rec.trace then rec.trace.images = (rec.trace.images or 0) + 1 end
  if g.manuel then deplacerSousSouris(rec) return end
  if not GetCursorPosition then return end
  local cx, cy = GetCursorPosition()
  local ef = sur(f.GetEffectiveScale, f)
  if not (nb(cx) and nb(cy) and nb(ef) and ef > 0) then return end
  -- La souris a bougé de plus de 3 points, et la fenêtre est restée où elle était : le jeu ne la fait
  -- pas suivre, on prend le relais.
  if math.abs(cx - g.cx) / ef + math.abs(cy - g.cy) / ef > 3 then
    local gauche, haut = sur(f.GetLeft, f), sur(f.GetTop, f)
    if nb(gauche) and nb(haut) and math.abs(gauche - g.gauche) < 0.5 and math.abs(haut - g.haut) < 0.5 then
      g.manuel = true
      sur(f.StopMovingOrSizing, f)
      ns.glisserManuel = (ns.glisserManuel or 0) + 1
      deplacerSousSouris(rec)
    end
  end
end

-- Trace des glissers (diagnostic, 12/11 : la fenêtre du personnage ne bougeait pas en jeu). Les
-- 5 dernières vont dans FenetresDB.traces ; un glisser qui n'a rien déplacé est dit dans le chat.
local function pos(f)
  local l, t = sur(f.GetLeft, f), sur(f.GetTop, f)
  if nb(l) and nb(t) then return string.format("%.0f,%.0f", l, t) end
  return "?"
end
local function noterTrace(rec, texte)
  if not db then return end
  db.traces = type(db.traces) == "table" and db.traces or {}
  table.insert(db.traces, 1, (date and date("%H:%M:%S") or "") .. " " .. rec.cle .. " : " .. texte)
  while #db.traces > 5 do table.remove(db.traces) end
end

local function finirDeplacement(rec)
  if not rec.deplace then return end
  local trace = rec.trace
  rec.trace = nil
  rec.deplace = false
  local g = rec.glisse
  rec.glisse = nil
  if rec.poignee then rec.poignee:SetScript("OnUpdate", nil) end
  local f = rec.fenetre
  -- Un combat a pu commencer pendant le glisser : sur une fenêtre protégée on ne touche plus à rien
  -- (le jeu refuserait). On le note, et on remettra notre place à la fin du combat.
  if estBloque(f) then
    rec.arefaire = true
    refusCombat[rec.cle] = (refusCombat[rec.cle] or 0) + 1
    return
  end
  if g and g.manuel then
    -- Glisser à la main : une dernière pose sous la souris, puis on lit la place comme d'habitude.
    rec.glisse = g
    deplacerSousSouris(rec)
    rec.glisse = nil
  else
    sur(f.StopMovingOrSizing, f)
  end
  sur(f.SetUserPlaced, f, false) -- pour que le jeu n'écrive pas la place dans son propre fichier
  if not (db and db.memoriser) then return end
  local pt = lirePoint(rec)
  if not pt then return end
  local avant = placeGardee(rec.cle)
  local place = { x = pt.x, y = pt.y, echelle = avant and avant.echelle or nil }
  garderPlace(rec, place)
  poser(rec, place) -- remet une ancre propre (coin haut gauche de l'écran)
  rafraichirReglages()
  if trace then
    trace.lache = pos(f)
    trace.mode = (g and g.manuel) and "main" or "jeu"
    local function finTrace()
      trace.apres = pos(f)
      local texte = string.format("départ %s, lâché %s, 0,5 s après %s, mode %s, StartMoving %s, images suivies %d",
        trace.depart, trace.lache, trace.apres, trace.mode, trace.start, trace.images or 0)
      noterTrace(rec, texte)
      if trace.apres == trace.depart then
        dire("|cffff8040la fenêtre « " .. rec.entree.titre .. " » n'a pas bougé.|r Fais /reload puis dis-le : " ..
          "le détail est gardé pour comprendre (" .. texte .. ").")
      end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.5, function() pcall(finTrace) end) else pcall(finTrace) end
  end
end

local function debutDeplacement(rec)
  if not gere(rec) then return end
  local f = rec.fenetre
  if estBloque(f) then refuserEnCombat(rec, "déplacée") return end
  if not rec.pris then prendre(rec) end
  sur(f.SetMovable, f, true)
  sur(f.Raise, f) -- la poignée n'est pas un enfant de la fenêtre : on la passe nous-mêmes devant
  majPoignee(rec) -- Raise a changé les niveaux : la poignée reste devant
  rec.deplace = true
  -- Le point de départ, pour le glisser à la main si le jeu ne fait pas suivre la fenêtre.
  local cx, cy
  if GetCursorPosition then cx, cy = GetCursorPosition() end
  local gauche, haut = sur(f.GetLeft, f), sur(f.GetTop, f)
  if nb(cx) and nb(cy) and nb(gauche) and nb(haut) then
    rec.glisse = { cx = cx, cy = cy, gauche = gauche, haut = haut, manuel = false }
    if rec.poignee then rec.poignee:SetScript("OnUpdate", function() suivreSouris(rec) end) end
  end
  rec.trace = { depart = pos(f), images = 0 }
  local okStart, erreurStart = pcall(f.StartMoving, f)
  rec.trace.start = okStart and "accepté" or ("refusé : " .. tostring(erreurStart))
  if not rec.glisse then rec.trace.start = rec.trace.start .. " (pas de point de départ : souris ou place illisible)" end
end

-- Change la taille d'un cran, en gardant le coin haut gauche où il est.
local function changerTaille(rec, sens)
  local f = rec.fenetre
  if estBloque(f) then refuserEnCombat(rec, "redimensionnée") return end
  local actuelle = sur(f.GetScale, f)
  if not nb(actuelle) then return end
  local nouvelle = ns.echelleSuivante(actuelle, sens)
  if math.abs(nouvelle - actuelle) < 0.001 then return end
  local pt = lirePoint(rec)
  sur(f.SetScale, f, nouvelle)
  local place = pt and { x = pt.x, y = pt.y, echelle = nouvelle } or { echelle = nouvelle }
  if pt then poser(rec, place) end
  if db and db.memoriser then garderPlace(rec, place) end
  rafraichirReglages()
end

-- Rend sa taille d'origine (celle qu'avait le cadre quand on l'a trouvé), sans bouger son coin haut gauche.
local function tailleNormale(rec)
  local f = rec.fenetre
  if estBloque(f) then refuserEnCombat(rec, "redimensionnée") return end
  local origine = rec.original and rec.original.echelle
  if nb(origine) then
    local pt = lirePoint(rec)
    sur(f.SetScale, f, origine)
    if pt then poser(rec, { x = pt.x, y = pt.y }) end
  end
  garderPlace(rec, ns.sansEchelle(placeGardee(rec.cle)))
  rafraichirReglages()
end

-- « Place d'origine » : on oublie notre point et le jeu reprend la main. On replace la fenêtre là où le
-- jeu l'avait mise la dernière fois (ses derniers SetPoint) ; sans cette information, elle la retrouvera
-- à sa prochaine ouverture. Jamais de ShowUIPanel : en combat, il serait refusé.
local function placeOrigine(rec)
  local f = rec.fenetre
  if estBloque(f) then refuserEnCombat(rec, "remise à sa place") return end
  garderPlace(rec, ns.sansPosition(placeGardee(rec.cle)))
  if not rendreAuJeu(rec) then
    dire(rec.entree.titre .. " retrouvera sa place d'origine à sa prochaine ouverture.")
  end
  rafraichirReglages()
end

local synchroniser

local function nePlusGerer(rec)
  if db and db.ignorees then db.ignorees[rec.cle] = true end
  garderPlace(rec, nil)
  synchroniser(rec)
  rafraichirReglages()
end

-- ----- le menu du clic droit, fait main (pas UIDropDownMenu, qui contamine le jeu)

local rideau, menu
local lignesMenu = {}

local function creerMenu()
  if menu then return end
  rideau = CreateFrame("Button", nil, UIParent)
  rideau:SetAllPoints(UIParent)
  rideau:SetFrameStrata("FULLSCREEN_DIALOG")
  rideau:RegisterForClicks("AnyUp")
  rideau:Hide()
  menu = CreateFrame("Frame", "FenetresMenu", UIParent)
  menu:SetFrameStrata("FULLSCREEN_DIALOG")
  menu:SetFrameLevel(rideau:GetFrameLevel() + 5)
  menu:EnableMouse(true)
  menu:SetSize(250, 40)
  ns.habiller(menu)
  menu:Hide()
  if UISpecialFrames then table.insert(UISpecialFrames, "FenetresMenu") end
  rideau:SetScript("OnClick", function() menu:Hide() end)
  menu:SetScript("OnHide", function() rideau:Hide() end)
end

local function ligneMenu(i)
  local b = lignesMenu[i]
  if b then return b end
  b = CreateFrame("Button", nil, menu)
  b:SetHeight(20)
  b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  b.texte = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  b.texte:SetPoint("LEFT", b, "LEFT", 8, 0)
  b.texte:SetJustifyH("LEFT")
  b:SetScript("OnClick", function(self)
    local action = self.action
    menu:Hide()
    if action then action() end
  end)
  lignesMenu[i] = b
  return b
end

-- entrees : { { texte, action, titre = vrai (en-tête, pas cliquable) } }
local function afficherMenu(entrees)
  creerMenu()
  local y = 8
  for i, e in ipairs(entrees) do
    local b = ligneMenu(i)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", menu, "TOPLEFT", 6, -y)
    b:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -6, -y)
    b.action = (not e.titre) and e.action or nil
    b:EnableMouse(not e.titre)
    b.texte:SetText(e.texte)
    if e.titre then b.texte:SetTextColor(1, 0.82, 0.3) else b.texte:SetTextColor(1, 1, 1) end
    b:Show()
    y = y + 20
  end
  for i = #entrees + 1, #lignesMenu do lignesMenu[i]:Hide() end
  menu:SetHeight(y + 8)
  local x, h = 0, 0
  if GetCursorPosition then x, h = GetCursorPosition() end
  local e = (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
  menu:ClearAllPoints()
  menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (x or 0) / e - 10, (h or 0) / e + 10)
  menu:SetClampedToScreen(true)
  rideau:Show()
  menu:Show()
end

local function menuFenetre(rec)
  afficherMenu({
    { texte = rec.entree.titre, titre = true },
    { texte = "Remettre à sa place d'origine", action = function() placeOrigine(rec) end },
    { texte = "Taille normale", action = function() tailleNormale(rec) end },
    { texte = "Ne plus gérer cette fenêtre", action = function() nePlusGerer(rec) end },
  })
end

-- ----- la création de la poignée et des crochets

local function infobulle(rec, self)
  if not GameTooltip then return end
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  GameTooltip:AddLine(rec.entree.titre, 1, 0.82, 0)
  local f = rec.fenetre
  local echelle = sur(f.GetScale, f)
  if nb(echelle) then
    GameTooltip:AddLine("Taille : " .. math.floor(echelle * 100 + 0.5) .. " %", 0.8, 0.8, 0.8)
  end
  GameTooltip:AddLine("Glisser : déplacer la fenêtre\nCtrl + molette : sa taille\nClic droit : menu", 1, 1, 1)
  GameTooltip:Show()
end

local function creerPoignee(rec)
  local f = rec.fenetre
  local g, d, h = ns.margesDe(rec.entree)
  local p = CreateFrame("Button", nil, UIParent)
  p:SetPoint("TOPLEFT", f, "TOPLEFT", g, 0)
  p:SetPoint("TOPRIGHT", f, "TOPRIGHT", -d, 0)
  p:SetHeight(h)
  p:EnableMouse(true)
  p:EnableMouseWheel(true)
  p:RegisterForDrag("LeftButton")
  p:RegisterForClicks("RightButtonUp")
  local lueur = p:CreateTexture(nil, "HIGHLIGHT")
  lueur:SetAllPoints()
  lueur:SetColorTexture(1, 1, 1, 0.07)
  p:SetScript("OnDragStart", function() debutDeplacement(rec) end)
  -- Glisser fait par nous, à partir de l'appui du bouton gauche : en jeu sur Forever (12/11), ni le
  -- glisser du jeu (OnDragStart) ni StartMoving ne déplaçaient la fenêtre du personnage, alors qu'un
  -- SetPoint la place bien. Donc : appui -> dès que la souris a bougé de 3 points, on pose nous-mêmes
  -- la fenêtre sous la souris à chaque image ; relâché -> place gardée. Rien ne dépend du jeu.
  p:SetScript("OnMouseDown", function(self, bouton)
    if bouton ~= "LeftButton" or rec.deplace or not gere(rec) then return end
    local f = rec.fenetre
    if estBloque(f) then refuserEnCombat(rec, "déplacée") return end
    if not GetCursorPosition then return end
    local cx, cy = GetCursorPosition()
    local gauche, haut = sur(f.GetLeft, f), sur(f.GetTop, f)
    if not (nb(cx) and nb(cy) and nb(gauche) and nb(haut)) then return end
    rec.appui = { cx = cx, cy = cy, gauche = gauche, haut = haut }
    self:SetScript("OnUpdate", function()
      local a = rec.appui
      if not a then return end
      -- Bouton relâché sans que l'on ait vu le OnMouseUp : on s'arrête proprement.
      if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
        rec.appui = nil
        if rec.deplace and rec.glisse and rec.glisse.manuel then finirDeplacement(rec) else self:SetScript("OnUpdate", nil) end
        return
      end
      if rec.deplace then
        if rec.glisse and rec.glisse.manuel then
          if rec.trace then rec.trace.images = (rec.trace.images or 0) + 1 end
          deplacerSousSouris(rec)
        end
        return
      end
      local x, y = GetCursorPosition()
      local ef = sur(f.GetEffectiveScale, f)
      if not (nb(x) and nb(y) and nb(ef) and ef > 0) then return end
      if math.abs(x - a.cx) / ef + math.abs(y - a.cy) / ef <= 3 then return end
      -- Le glisser commence : à nous.
      if estBloque(f) then rec.appui = nil self:SetScript("OnUpdate", nil) refuserEnCombat(rec, "déplacée") return end
      if not rec.pris then prendre(rec) end
      sur(f.Raise, f)
      majPoignee(rec)
      rec.deplace = true
      rec.glisse = { cx = a.cx, cy = a.cy, gauche = a.gauche, haut = a.haut, manuel = true }
      rec.trace = { depart = pos(f), images = 0, start = "non demandé (glisser fait par l'addon)" }
      deplacerSousSouris(rec)
    end)
  end)
  p:SetScript("OnMouseUp", function(self, bouton)
    if bouton ~= "LeftButton" then return end
    rec.appui = nil
    if rec.deplace and rec.glisse and rec.glisse.manuel then
      finirDeplacement(rec)
    elseif not rec.deplace then
      self:SetScript("OnUpdate", nil)
    end
  end)
  p:SetScript("OnDragStop", function() finirDeplacement(rec) end)
  p:SetScript("OnClick", function(_, bouton)
    if bouton == "RightButton" and gere(rec) then menuFenetre(rec) end
  end)
  p:SetScript("OnMouseWheel", function(self, sens)
    if not (gere(rec) and db.molette) then return end
    if not (IsControlKeyDown and IsControlKeyDown()) then return end
    changerTaille(rec, sens)
    infobulle(rec, self)
  end)
  p:SetScript("OnEnter", function(self) infobulle(rec, self) end)
  p:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  p:Hide()
  rec.poignee = p
end

-- Ce que le jeu fait à la fenêtre (crochets : leur code tourne APRÈS la fonction du jeu et ne la
-- change pas).
local function surSetPoint(rec, ...)
  if rec.occupe then return end -- c'est nous
  -- On note ce que le jeu pose : c'est sa « place d'origine ».
  -- Un nouveau SetPoint sur la même ancre remplace l'ancien (comme dans le jeu).
  local n = select("#", ...)
  local nouveau, ancre = { n = n, ... }, (...)
  local place
  for i, p in ipairs(rec.pointsJeu) do
    if p[1] == ancre then place = i break end
  end
  if place then rec.pointsJeu[place] = nouveau
  elseif #rec.pointsJeu < 8 then rec.pointsJeu[#rec.pointsJeu + 1] = nouveau end
  if not gere(rec) or rec.deplace then return end
  planifier(rec)
end

local function surClearAllPoints(rec)
  if rec.occupe then return end
  rec.pointsJeu = {}
end

local function surMontre(rec)
  if not gere(rec) then return end
  majPoignee(rec)
  reappliquer(rec) -- le jeu vient de poser sa place juste avant d'afficher : on remet la nôtre tout de suite
  -- et encore à l'image suivante, au cas où le jeu replace après (inutile si le combat nous a déjà arrêtés)
  if not rec.arefaire then planifier(rec) end
end

local function surCache(rec)
  if rec.poignee then rec.poignee:Hide() end
  if rec.deplace then finirDeplacement(rec) end
end

local function installerCrochets(rec)
  local f = rec.fenetre
  if hooksecurefunc then
    pcall(hooksecurefunc, f, "SetPoint", function(_, ...) surSetPoint(rec, ...) end)
    pcall(hooksecurefunc, f, "ClearAllPoints", function() surClearAllPoints(rec) end)
    -- Quand le jeu passe la fenêtre devant (Raise), ou change sa taille, la poignée suit : sinon elle
    -- resterait sous la fenêtre, ou garderait de mauvaises marges.
    pcall(hooksecurefunc, f, "Raise", function() majPoignee(rec) end)
    pcall(hooksecurefunc, f, "SetScale", function() majPoignee(rec) end)
  end
  -- Un clic dans une fenêtre « toplevel » la relève sans passer par Raise : on remet la poignée devant.
  pcall(f.HookScript, f, "OnMouseDown", function() majPoignee(rec) end)
  pcall(f.HookScript, f, "OnShow", function() surMontre(rec) end)
  pcall(f.HookScript, f, "OnHide", function() surCache(rec) end)
end

-- Le cadre existe-t-il, et est-ce bien un cadre qu'on sait suivre ?
local function trouver(entree)
  local f = _G[entree.nom]
  if type(f) ~= "table" then return nil end
  if type(f.SetPoint) ~= "function" or type(f.HookScript) ~= "function" or type(f.IsShown) ~= "function" then return nil end
  if type(f.IsForbidden) == "function" then
    local ok, interdit = pcall(f.IsForbidden, f)
    if not ok or interdit then return nil end
  end
  return f
end

local function creerRec(entree, f)
  -- Si une création précédente a échoué à moitié, on reprend le même enregistrement : les crochets
  -- déjà posés ne le sont pas deux fois.
  local rec = parFenetre[f] or { cle = ns.cleFenetre(entree.nom), entree = entree, fenetre = f, pointsJeu = {},
                occupe = false, planifie = false, deplace = false, pris = false }
  parFenetre[f] = rec
  suivi[rec.cle] = rec
  if not rec.original then capturer(rec) end
  if not rec.poignee then creerPoignee(rec) end
  if not rec.crochets then
    rec.crochets = true
    installerCrochets(rec)
  end
  return rec
end

-- Met la fenêtre en accord avec les réglages : poignée, mobilité, « dans l'écran ».
function synchroniser(rec)
  if gere(rec) then
    prendre(rec)
    majPoignee(rec)
    if sur(rec.fenetre.IsShown, rec.fenetre) then planifier(rec) end
  else
    if rec.poignee then rec.poignee:Hide() end
    restaurer(rec)
  end
end

-- Cherche les fenêtres pas encore suivies et règle toutes celles qui le sont.
local function scanner()
  if not db then return end
  for _, entree in ipairs(ns.FENETRES) do
    local cle = ns.cleFenetre(entree.nom)
    if cle and not suivi[cle] and db.actif and not (db.ignorees and db.ignorees[cle]) then
      local f = trouver(entree)
      if f then
        local ok = pcall(creerRec, entree, f)
        if not ok then suivi[cle] = nil end -- à moitié faite : on la refera au prochain passage (parFenetre garde ce qui est déjà posé)
      end
    end
  end
  for _, rec in pairs(suivi) do synchroniser(rec) end
end

-- ----- actions sur toutes les fenêtres (réglages, commande /fen reset)

local function cles(t)
  local liste = {}
  for cle in pairs(t or {}) do liste[#liste + 1] = cle end
  table.sort(liste)
  return liste
end

local function titreDe(cle)
  for _, e in ipairs(ns.FENETRES) do
    if e.nom == cle then return e.titre end
  end
  return cle
end

-- Oublie la place et la taille d'une fenêtre (même si elle n'est pas chargée cette session).
local function remettreUne(cle)
  local rec = suivi[cle]
  if rec then
    placeOrigine(rec)
    tailleNormale(rec)
    garderPlace(rec, nil)
  elseif db and db.fenetres then
    db.fenetres[cle] = nil
  end
end

local function toutRemettre()
  if not db then return 0 end
  local liste = cles(db.fenetres)
  groupe = true
  for _, cle in ipairs(liste) do pcall(remettreUne, cle) end
  groupe = false
  rafraichirReglages()
  return #liste
end

-- La fenêtre exclue revient dans la liste des fenêtres gérées.
local function regerer(cle)
  if not (db and db.ignorees) then return end
  db.ignorees[cle] = nil
  scanner()
  rafraichirReglages()
end

local function lignesPlacees()
  local lignes = {}
  if not (db and db.fenetres) then return lignes end
  for _, cle in ipairs(cles(db.fenetres)) do
    local place = ns.lirePlace(db.fenetres[cle])
    if place then
      lignes[#lignes + 1] = { texte = ns.texteLigne(titreDe(cle), place), retirer = function() remettreUne(cle) end }
    end
  end
  return lignes
end

local function lignesIgnorees()
  local lignes = {}
  if not (db and db.ignorees) then return lignes end
  for _, cle in ipairs(cles(db.ignorees)) do
    if db.ignorees[cle] then
      lignes[#lignes + 1] = { texte = titreDe(cle), retirer = function() regerer(cle) end }
    end
  end
  return lignes
end

-- ---------------------------------------------------------------------------
-- Réglages
-- ---------------------------------------------------------------------------

ns.reglages = ns.creerReglages({
  titre = "Fenêtres déplaçables",
  icone = "Interface\\Icons\\INV_Misc_Gear_01",
  nomDB = "FenetresDB",
  defauts = DEFAUTS,
  options = {
    { titre = "Fenêtres" },
    { cle = "actif", libelle = "Activer les fenêtres déplaçables",
      aide = "Une poignée invisible sur la barre de titre de chaque grande fenêtre du jeu. Coupé : les poignées disparaissent et les fenêtres reprennent leur comportement d'origine." },
    { cle = "memoriser", libelle = "Garder la place de chaque fenêtre",
      aide = "La fenêtre revient là où tu l'as laissée, à chaque ouverture et à chaque session. Décoché : elle suit la souris mais retrouve sa place d'origine à la prochaine ouverture." },
    { cle = "dansEcran", libelle = "Garder les fenêtres dans l'écran",
      aide = "Une fenêtre ne peut pas sortir de l'écran, et une place gardée hors de l'écran (résolution changée) est ramenée dedans. À décocher pour poser des fenêtres sur un second écran." },
    { cle = "secondEcran", libelle = "Le jeu sur un écran, les fenêtres sur l'autre",
      aide = "Pour une fenêtre du jeu étirée sur deux écrans (outils\\second-ecran.ps1 le fait) : le monde et toute l'interface restent sur un écran, l'autre est libre ; glisse-y les fenêtres. Sans effet si la fenêtre du jeu ne couvre qu'un écran. Jamais appliqué en plein combat : à la fin du combat." },
    { cle = "mondeAGauche", libelle = "Le jeu sur l'écran de gauche", dependDe = "secondEcran",
      aide = "Décoché : le jeu sur l'écran de droite, les fenêtres à gauche." },
    { cle = "molette", libelle = "Ctrl + molette change la taille",
      aide = "Sur la barre de titre d'une fenêtre : de 50 à 150 %, par pas de 5 %. La taille est gardée comme la place." },
  },
  boutons = {
    { texte = "Tout remettre à sa place d'origine", largeur = 240,
      aide = "Oublie toutes les places et les tailles gardées : les fenêtres reprennent leur place d'origine.",
      action = function()
        local n = toutRemettre()
        dire(n > 0 and (n .. " fenêtre(s) remise(s) à leur place d'origine.") or "aucune fenêtre n'avait été déplacée.")
      end },
  },
  ongletContenu = "Fenêtres déplacées",
  contenu = function(fenetre, y)
    local t = fenetre:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, y - 6)
    t:SetText("Fenêtres déplacées")
    y = y - 30
    local maj1, maj2
    y, maj1 = ns.creerListe(fenetre, y, {
      titre = "Déplacées ou redimensionnées (la croix remet la fenêtre à sa place d'origine)", hauteur = 7,
      vide = "Aucune fenêtre déplacée.",
      lignes = lignesPlacees,
      vider = function() toutRemettre() end,
    })
    y, maj2 = ns.creerListe(fenetre, y - 6, {
      titre = "Fenêtres que tu ne veux plus voir gérées (la croix les remet dans la liste)", hauteur = 3,
      vide = "Aucune.",
      lignes = lignesIgnorees,
    })
    return y, function() maj1(); maj2() end
  end,
  astuce = "Glisse la barre de titre d'une fenêtre pour la déplacer. Ctrl + molette dessus : sa taille. Clic droit dessus : remettre à sa place, taille normale, ne plus gérer. /fen etat montre ce qui est géré.",
  auChargement = function(d)
    db = d
    db.fenetres = type(db.fenetres) == "table" and db.fenetres or {}
    db.ignorees = type(db.ignorees) == "table" and db.ignorees or {}
    scanner()
  end,
  surChangement = function()
    if not db then return end
    scanner()
    if ns.appliquerSecondEcran then ns.appliquerSecondEcran() end
  end,
})

-- ---------------------------------------------------------------------------
-- Événements
-- ---------------------------------------------------------------------------

-- Pour régler la table ns.FENETRES sur Forever en lisant la sauvegarde : ce qui est trouvé, ce qui ne l'est
-- pas, ce qui est déplacé, et les refus en combat.
local function noterDiagnostic()
  if not db then return end
  local d = { date = date and date("%Y-%m-%d %H:%M") or "", trouvees = {}, introuvables = {}, deplacees = {},
              ignorees = {}, refusCombat = {} }
  for _, entree in ipairs(ns.FENETRES) do
    if trouver(entree) then
      d.trouvees[#d.trouvees + 1] = entree.nom
    else
      d.introuvables[#d.introuvables + 1] = entree.nom .. (entree.addon and (" (" .. entree.addon .. ")") or "")
    end
  end
  for _, cle in ipairs(cles(db.fenetres)) do
    local p = ns.lirePlace(db.fenetres[cle])
    if p then
      d.deplacees[#d.deplacees + 1] = string.format("%s : TOPLEFT x=%s y=%s taille=%s", cle,
        p.x and string.format("%.1f", p.x) or "-", p.y and string.format("%.1f", p.y) or "-", tostring(p.echelle or "-"))
    end
  end
  for _, cle in ipairs(cles(db.ignorees)) do
    if db.ignorees[cle] then d.ignorees[#d.ignorees + 1] = cle end
  end
  for _, cle in ipairs(cles(refusCombat)) do d.refusCombat[cle] = refusCombat[cle] end
  db.diagnostic = d
end

-- ----- second écran : le monde (WorldFrame) et l'interface (UIParent) sur une seule moitié de la fenêtre.
-- Vu en jeu le 12/11 : hors combat, le jeu accepte ces deux SetPoint (ils sont refusés en combat).
local secondAFaire = false
local function appliquerSecondEcran()
  if not db then return end
  if InCombatLockdown and InCombatLockdown() then secondAFaire = true return end
  secondAFaire = false
  local largeur, hauteur
  if GetPhysicalScreenSize then largeur, hauteur = GetPhysicalScreenSize() end
  local voulu = db.actif and db.secondEcran and ns.deuxEcrans(largeur, hauteur)
  if voulu then
    local ok = pcall(function()
      UIParent:ClearAllPoints()
      if db.mondeAGauche then
        UIParent:SetPoint("TOPLEFT", nil, "TOPLEFT", 0, 0)
        UIParent:SetPoint("BOTTOMRIGHT", nil, "BOTTOM", 0, 0)
      else
        UIParent:SetPoint("TOPLEFT", nil, "TOP", 0, 0)
        UIParent:SetPoint("BOTTOMRIGHT", nil, "BOTTOMRIGHT", 0, 0)
      end
      WorldFrame:ClearAllPoints()
      WorldFrame:SetAllPoints(UIParent)
    end)
    ns.secondEcranActif = ok
  elseif ns.secondEcranActif then
    pcall(function()
      UIParent:ClearAllPoints()
      UIParent:SetAllPoints()
      WorldFrame:ClearAllPoints()
      WorldFrame:SetAllPoints()
    end)
    ns.secondEcranActif = false
  end
end
ns.appliquerSecondEcran = appliquerSecondEcran

-- Le combat est fini : on fait ce qu'on avait dû remettre à plus tard.
local function rattraper()
  messageCombatDit = false
  if secondAFaire then appliquerSecondEcran() end
  for _, rec in pairs(suivi) do
    if rec.arestaurer then restaurer(rec) end
    if rec.aprendre and gere(rec) then prendre(rec) end
    if rec.arefaire then planifier(rec) end
    if gere(rec) and rec.poignee then majPoignee(rec) end
  end
end

local ecouteur = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_LOGOUT",
                     "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED" }) do
  pcall(ecouteur.RegisterEvent, ecouteur, e)
end

ecouteur:SetScript("OnEvent", function(_, evenement, nom)
  if not db then return end
  if evenement == "PLAYER_LOGOUT" then
    pcall(noterDiagnostic)
  elseif evenement == "PLAYER_REGEN_ENABLED" then
    pcall(rattraper)
  elseif evenement == "ADDON_LOADED" then
    -- Un addon du jeu chargé à la demande vient peut-être de créer une de nos fenêtres.
    if type(nom) == "string" and nom:sub(1, 9) == "Blizzard_" then pcall(scanner) end
  elseif evenement == "PLAYER_ENTERING_WORLD" then
    pcall(scanner)
    pcall(appliquerSecondEcran)
    if C_Timer and C_Timer.After then C_Timer.After(2, function() pcall(scanner) end) end
  else
    pcall(appliquerSecondEcran) -- la fenêtre du jeu a peut-être été étirée (ou ramenée) entre-temps
    -- La résolution ou l'échelle de l'interface a changé : on replace les fenêtres ouvertes.
    for _, rec in pairs(suivi) do
      if gere(rec) and sur(rec.fenetre.IsShown, rec.fenetre) then planifier(rec) end
    end
  end
end)

-- ---------------------------------------------------------------------------
-- Commandes
-- ---------------------------------------------------------------------------

local function commandeEtat()
  if not db then return end
  local suivies, ouvertes, deplacees, bloquees = 0, 0, 0, 0
  for _, rec in pairs(suivi) do
    if gere(rec) then
      suivies = suivies + 1
      if sur(rec.fenetre.IsShown, rec.fenetre) then ouvertes = ouvertes + 1 end
      if rec.arefaire or rec.aprendre or rec.arestaurer then bloquees = bloquees + 1 end
    end
  end
  for _ in pairs(db.fenetres or {}) do deplacees = deplacees + 1 end
  local ignorees = #cles(db.ignorees)
  dire(string.format("%s. %d fenêtre(s) suivie(s) sur %d connues, %d ouverte(s) en ce moment.",
    db.actif and "activé" or "coupé", suivies, #ns.FENETRES, ouvertes))
  dire(string.format("%d place(s) gardée(s), %d fenêtre(s) exclue(s), %d à refaire après le combat. Gardée dans l'écran : %s.",
    deplacees, ignorees, bloquees, db.dansEcran and "oui" or "non"))
end

local function commande(texte)
  local c = strtrim(texte or ""):lower()
  if c == "" or c == "options" or c == "reglages" then
    ns.reglages.ouvrir()
  elseif c == "reset" or c == "remettre" then
    local n = toutRemettre()
    dire(n > 0 and (n .. " fenêtre(s) remise(s) à leur place d'origine.") or "aucune fenêtre n'avait été déplacée.")
  elseif c == "etat" then
    commandeEtat()
  elseif c == "on" or c == "off" then
    if db and (c == "on") ~= (db.actif and true or false) then ns.reglages.basculer() end
  elseif c == "second" or c == "second on" or c == "second off" or c == "second gauche" or c == "second droite" then
    if not db then return end
    if c == "second gauche" or c == "second droite" then
      ns.reglages.changer("mondeAGauche", c == "second gauche")
      ns.reglages.changer("secondEcran", true)
    elseif c == "second" then
      ns.reglages.changer("secondEcran", not db.secondEcran)
    else
      ns.reglages.changer("secondEcran", c == "second on")
    end
    appliquerSecondEcran()
    local largeur, hauteur
    if GetPhysicalScreenSize then largeur, hauteur = GetPhysicalScreenSize() end
    if db.secondEcran and not ns.deuxEcrans(largeur, hauteur) then
      dire("second écran coché, mais la fenêtre du jeu ne couvre qu'un écran : lance outils\\second-ecran.ps1.")
    else
      dire("second écran : " .. (db.secondEcran and ("le jeu sur l'écran de " .. (db.mondeAGauche and "gauche" or "droite")) or "coupé") .. ".")
    end
  elseif c == "aide" or c == "help" or c == "?" then
    dire("/fen : les réglages     /fen reset : tout remettre à sa place d'origine     /fen etat : l'état")
    dire("/fen second : le jeu sur un écran, les fenêtres sur l'autre (second on, second off, second gauche, second droite)")
    dire("Glisser la barre de titre : déplacer. Ctrl + molette : la taille. Clic droit : menu de la fenêtre.")
  elseif not ns.reglages.basculerOption(c) then
    dire("commande inconnue. /fen aide donne la liste.")
  end
end

SLASH_FENETRES1 = "/fen"
SLASH_FENETRES2 = "/fenetres"
SlashCmdList.FENETRES = commande
