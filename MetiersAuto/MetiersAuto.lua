-- ============================================================================
-- Métiers auto : rendre les métiers de récolte plus confortables.
--
-- Ce qu'un addon N'A PAS le droit de faire : miner, cueillir ou pêcher à ta
-- place. Blizzard bloque tout ce qui lance un sort ou touche un objet du monde
-- sans un appui de ta part, et un programme qui clique pour toi est un bot
-- (interdit, risque de bannissement). Ici, chaque action reste UN appui de toi :
--
--  1. Pêche confort : un « mode pêche » où un double clic droit n'importe où
--     lance la ligne. Pendant ce mode, le son des effets est monté et la musique
--     coupée pour bien entendre le bouchon ; tout revient comme avant après.
--  2. Récolte une touche : la touche « Interagir avec la cible » de Blizzard vise
--     toute seule le filon, l'herbe ou le bouchon le plus proche ; ramassage
--     automatique ; repérage des minerais et herbes remis tout seul.
--  3. Liste de courses : les composants d'une recette, ce que tu as (sacs et
--     banque) et ce qu'il te manque, mis à jour pendant que tu récoltes.
-- ============================================================================

local NOM_ADDON, ns = ...

local DEFAUTS = {
  actif = true,
  minimap = false,         -- icône à part (sinon seulement l'icône commune)
  angleMinimap = 250,
  pecheDoubleClic = true,  -- double clic droit = lancer la ligne (en mode pêche)
  pecheSon = true,         -- son des effets à fond, musique coupée, en mode pêche
  pecheAuto = true,        -- passer en mode pêche dès que tu pêches toi-même
  interaction = true,      -- la touche d'interaction vise filons, herbes et bouchon
  ramassage = true,        -- ramassage automatique du butin
  reperage = true,         -- remettre le repérage des minerais et herbes
  filonPasFini = true,     -- prévenir quand un filon ou une herbe n'est pas fini
  filonSon = true,         -- son et rappel de cette alerte (jamais avec la molette)
  fleche = true,           -- flèche vers le filon ou l'herbe connu le plus proche
  filons = {},             -- endroits récoltés : filons[carte] = { { x, y, nom } }
  courses = {},            -- liste de courses : { { recette = id, nombre = n, nom = "…" } }
  afficherCourses = true,  -- afficher la fenêtre de la liste de courses
  sonAvant = nil,          -- réglages du son avant le mode pêche, pour les remettre
}

local db

-- ---------------------------------------------------------------------------
-- Partie « logique pure », testée hors jeu (tests/MetiersAuto_simu.lua).
-- ---------------------------------------------------------------------------

-- Lit « 5 [lien de recette] » ou « [lien] » : renvoie le nombre et le numéro de recette.
function ns.lireRecette(texte)
  local nombre = tonumber(texte:match("^%s*(%d+)%s")) or 1
  local id = texte:match("enchant:(%d+)") or texte:match("spell:(%d+)")
    or texte:match("^%s*%d+%s+(%d+)%s*$") or texte:match("^%s*(%d+)%s*$")
  return nombre, tonumber(id)
end

-- Distance en mètres entre deux points d'une carte. Les positions de carte vont
-- de 0 à 1 ; largeur et hauteur sont la taille de la carte en mètres.
function ns.distance(x1, y1, x2, y2, largeur, hauteur)
  local dx, dy = (x2 - x1) * largeur, (y2 - y1) * hauteur
  return math.sqrt(dx * dx + dy * dy)
end

-- Ajoute un endroit récolté à la liste d'une carte, sauf s'il y est déjà
-- (même endroit à 15 m près). Renvoie true si c'est un nouvel endroit.
function ns.memoriser(liste, x, y, nom, largeur, hauteur, genre)
  for _, p in ipairs(liste) do
    if ns.distance(p[1], p[2], x, y, largeur, hauteur) < 15 then
      p[3] = nom or p[3]
      p[4] = genre or p[4]
      return false
    end
  end
  liste[#liste + 1] = { x, y, nom, genre }
  if #liste > 400 then table.remove(liste, 1) end -- les plus anciens partent
  return true
end

-- Minerai ou herbe ? D'après ce qui est tombé : métal et pierre (classe 7,
-- sous-classe 7) = minerai, herbe (7, 9) = herbe. Rien de tel (un coffre, un
-- objet de quête) : nil, et l'endroit n'est pas retenu.
function ns.genreDepuisButin(objets)
  for _, o in ipairs(objets or {}) do
    if o.classe == 7 and o.sousClasse == 7 then return "minerai" end
    if o.classe == 7 and o.sousClasse == 9 then return "herbe" end
  end
  return nil
end

-- Pour les endroits notés avant : minerai si le nom le dit, sinon herbe.
local MOTS_MINERAI = { "filon", "gisement", "veine", "depot", "dépôt", "minerai", "vein", "deposit", "ore", "lode" }
function ns.genreDepuisNom(nom)
  local n = tostring(nom or ""):lower()
  for _, m in ipairs(MOTS_MINERAI) do
    if n:find(m, 1, true) then return "minerai" end
  end
  return "herbe"
end

-- Le point connu le plus proche, en sautant ceux à moins de 20 m (celui que tu
-- viens de finir) et ceux récoltés il y a peu (recent[point] = moment).
-- genres : [« minerai » | « herbe »] = vrai pour ce que ton personnage sait
-- récolter (nil = tout).
function ns.plusProche(liste, x, y, largeur, hauteur, recent, maintenant, genres)
  local meilleur, dMin
  for _, p in ipairs(liste) do
    -- Un endroit que ce personnage ne sait pas récolter est sauté (d = -1).
    local d = -1
    if not genres or genres[p[4] or ns.genreDepuisNom(p[3])] then
      d = ns.distance(x, y, p[1], p[2], largeur, hauteur)
    end
    local frais = recent and recent[p] and maintenant - recent[p] < 180
    if d >= 20 and not frais and (not dMin or d < dMin) then meilleur, dMin = p, d end
  end
  return meilleur, dMin
end

-- Angle de la flèche (en radians, sens inverse des aiguilles d'une montre,
-- 0 = tout droit) pour aller de (x, y) vers (cx, cy) quand on regarde vers
-- « orientation » (GetPlayerFacing : 0 = nord, sens inverse des aiguilles).
-- Sur la carte, x va vers l'est et y vers le sud.
function ns.angleFleche(x, y, cx, cy, largeur, hauteur, orientation)
  local est, nord = (cx - x) * largeur, (y - cy) * hauteur
  return math.atan2(-est, nord) - orientation
end

-- Additionne les composants de toutes les recettes de la liste.
-- liste : { { recette, nombre } } ; composants(recette) -> { { ids = {…}, quantite } }
-- Renvoie { { ids, besoin } } (un composant peut exister en plusieurs qualités = plusieurs ids).
function ns.besoins(liste, composants)
  local parCle, ordre = {}, {}
  for _, ligne in ipairs(liste) do
    for _, c in ipairs(composants(ligne.recette) or {}) do
      local cle = table.concat(c.ids, ",")
      if not parCle[cle] then
        parCle[cle] = { ids = c.ids, besoin = 0 }
        ordre[#ordre + 1] = parCle[cle]
      end
      parCle[cle].besoin = parCle[cle].besoin + c.quantite * (ligne.nombre or 1)
    end
  end
  return ordre
end

-- Combien en as-tu, et combien en manque-t-il ? compter(id) -> nombre possédé.
function ns.manque(besoin, compter)
  local a = 0
  for _, id in ipairs(besoin.ids) do a = a + (compter(id) or 0) end
  return a, math.max(0, besoin.besoin - a)
end

-- Les lignes de la liste de courses dans la fenêtre de réglages : { texte, retirer }.
-- courses : db.courses ; retirer(i) est appelé par la croix de la ligne n° i.
function ns.lignesCourses(courses, retirer)
  local lignes = {}
  for i, l in ipairs(courses) do
    lignes[i] = {
      texte = (l.nombre or 1) .. " × " .. tostring(l.nom or l.recette),
      retirer = function() retirer(i) end,
    }
  end
  return lignes
end

-- « N endroits connus ici, M en tout ». ici vaut nil quand la position est inconnue
-- (donjon, ou position cachée par le jeu).
function ns.texteFilons(ici, total)
  if not ici then
    return string.format("Position inconnue ici, %d %s en tout", total, total > 1 and "endroits" or "endroit")
  end
  return string.format("%d %s ici, %d en tout", ici, ici > 1 and "endroits connus" or "endroit connu", total)
end

-- ---------------------------------------------------------------------------
-- Petits outils
-- ---------------------------------------------------------------------------

local function lireCVar(nom) return (C_CVar and C_CVar.GetCVar or GetCVar)(nom) end
local function ecrireCVar(nom, valeur)
  if InCombatLockdown() then return end
  (C_CVar and C_CVar.SetCVar or SetCVar)(nom, valeur)
end
local function nomSort(id)
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
  return GetSpellInfo and (GetSpellInfo(id))
end
local function connu(id)
  return (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and IsSpellKnown(id))
end

-- Le sort de pêche change de numéro selon les versions : on prend le premier connu.
local SORTS_PECHE = { 131474, 7620, 7731, 7732, 18248, 33095, 51294, 88868 }
local PECHE = {}
for _, id in ipairs(SORTS_PECHE) do PECHE[id] = true end
local function sortPeche()
  for _, id in ipairs(SORTS_PECHE) do
    if connu(id) then return nomSort(id) end
  end
end

-- ---------------------------------------------------------------------------
-- 1. Pêche confort
-- ---------------------------------------------------------------------------

local modePeche = false
local derniereActivite = 0

-- Bouton « sécurisé » : seul ce type de bouton a le droit de lancer un sort,
-- et seulement quand TU cliques. Le double clic droit le déclenche.
local lancer = CreateFrame("Button", "MetiersAutoLancer", UIParent, "SecureActionButtonTemplate")
lancer:RegisterForClicks("AnyUp", "AnyDown")
lancer:SetAttribute("type", "spell")
lancer:Hide()
lancer:SetScript("PostClick", function(self)
  if not InCombatLockdown() then ClearOverrideBindings(self) end
end)

-- Son : on note les réglages, on met les effets à fond et on coupe le reste.
local SON = { "Sound_SFXVolume", "Sound_MusicVolume", "Sound_AmbienceVolume" }
local function sonPeche()
  if db.sonAvant then return end
  db.sonAvant = {}
  for _, nom in ipairs(SON) do db.sonAvant[nom] = lireCVar(nom) end
  ecrireCVar("Sound_SFXVolume", "1")
  ecrireCVar("Sound_MusicVolume", "0")
  ecrireCVar("Sound_AmbienceVolume", "0")
end
local function sonNormal()
  if not db.sonAvant then return end
  for nom, valeur in pairs(db.sonAvant) do ecrireCVar(nom, valeur) end
  db.sonAvant = nil
end

local function changerModePeche(actif)
  if actif == modePeche then return end
  if actif and InCombatLockdown() then return end
  modePeche = actif
  if actif then
    local sort = sortPeche()
    if not sort then
      modePeche = false
      return ns.reglages.dire("tu ne connais pas la pêche sur ce personnage.")
    end
    lancer:SetAttribute("spell", sort)
    derniereActivite = GetTime()
    if db.pecheSon then sonPeche() end
    ns.reglages.dire("mode pêche |cff00ff00activé|r : double clic droit pour lancer, clic droit sur le bouchon pour ferrer.")
  else
    sonNormal()
    if not InCombatLockdown() then ClearOverrideBindings(lancer) end
    ns.reglages.dire("mode pêche |cffff4040terminé|r, son remis comme avant.")
  end
  -- La fenêtre de réglages, si elle est ouverte, montre le bon état du bouton.
  if ns.reglages.majFenetre then ns.reglages.majFenetre() end
end

function MetiersAuto_ModePeche() changerModePeche(not modePeche) end
BINDING_HEADER_METIERSAUTO = "Métiers auto"
BINDING_NAME_METIERSAUTO_PECHE = "Mode pêche (activer ou arrêter)"
BINDING_NAME_METIERSAUTO_REGLAGES = "Ouvrir les réglages de Métiers auto"

-- Double clic droit dans le monde : au 2e clic, le clic droit est relié pour un
-- instant au bouton qui lance la pêche (méthode des addons de pêche connus).
local dernierClic = 0
WorldFrame:HookScript("OnMouseDown", function(_, souris)
  if souris ~= "RightButton" or not modePeche or not db.actif or not db.pecheDoubleClic then return end
  if InCombatLockdown() or UnitChannelInfo("player") then return end
  local maintenant = GetTime()
  if maintenant - dernierClic < 0.4 then
    dernierClic = 0
    derniereActivite = maintenant
    SetOverrideBindingClick(lancer, true, "BUTTON2", "MetiersAutoLancer")
  else
    dernierClic = maintenant
  end
end)

-- Le mode pêche s'arrête seul après 60 s sans pêcher, ou en combat.
C_Timer.NewTicker(5, function()
  if modePeche and GetTime() - derniereActivite > 60 and not UnitChannelInfo("player") then
    changerModePeche(false)
  end
end)

-- ---------------------------------------------------------------------------
-- 2. Récolte une touche : interaction, ramassage, repérage
-- ---------------------------------------------------------------------------

-- SoftTargetInteract = 3 : la touche « Interagir avec la cible » vise seule
-- l'objet le plus proche (filon, herbe, bouchon, PNJ).
local function appliquerCVars()
  if not db.actif then return end
  if db.interaction then ecrireCVar("SoftTargetInteract", "3") end
  if db.ramassage then ecrireCVar("autoLootDefault", "1") end
end

-- Repérage : Découverte de minerais (2580), Découverte d'herbes (2383), Recherche de poissons (43308).
local REPERAGES = { [2580] = true, [2383] = true, [43308] = true }
local function remettreReperage()
  if not db.actif or not db.reperage or not C_Minimap or not C_Minimap.GetNumTrackingTypes then return end
  for i = 1, C_Minimap.GetNumTrackingTypes() do
    local info = C_Minimap.GetTrackingInfo(i)
    local idSort, actif
    if type(info) == "table" then
      idSort, actif = info.spellID, info.active
    else
      local _, _, a, _, _, s = C_Minimap.GetTrackingInfo(i)
      idSort, actif = s, a
    end
    if idSort and REPERAGES[idSort] and not actif then C_Minimap.SetTracking(i, true) end
  end
end

-- La touche reliée à une action du jeu ou de l'addon, écrite lisiblement (nil si aucune).
local function texteTouche(action)
  local k = GetBindingKey and GetBindingKey(action)
  if not k or k == "" then return nil end
  -- GetBindingText traduit le code de la touche (« SHIFT-E » devient « Maj-E »,
  -- « BUTTON4 » un bouton de souris). Certaines touches (², <) sortent en « ? »
  -- avec la police du jeu : on garde alors le code brut.
  local texte = GetBindingText and GetBindingText(k, "KEY_") or k
  if not texte or texte == "" or texte:find("?", 1, true) then texte = k end
  return texte
end
local function toucheInteraction() return texteTouche("INTERACTTARGET") end

-- Choisir la touche depuis les réglages : on écoute la prochaine touche
-- appuyée, puis on la relie à « Interagir avec la cible » comme le ferait
-- Échap > Options > Raccourcis. Échap annule. Interdit en combat par le jeu.
local MODIFICATEURS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
  LALT = true, RALT = true, LMETA = true, RMETA = true }
local capture = CreateFrame("Frame", nil, UIParent)
capture:Hide()
capture:EnableKeyboard(true)
capture:SetScript("OnKeyDown", function(self, key)
  if MODIFICATEURS[key] then return end
  self:Hide()
  if key == "ESCAPE" then
    ns.reglages.dire("choix de la touche annulé.")
    if self.apres then self.apres() end
    return
  end
  local combo = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
    .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
  if SetBinding(combo, "INTERACTTARGET") then
    SaveBindings(GetCurrentBindingSet())
    ns.reglages.dire("« Interagir avec la cible » est maintenant sur |cff00ff00" .. (toucheInteraction() or combo) .. "|r.")
  else
    ns.reglages.dire("|cffff4040impossible d'utiliser cette touche.|r")
  end
  if self.apres then self.apres() end
end)

-- Renvoie vrai quand l'écoute de la touche a démarré.
local function choisirTouche(apres)
  if InCombatLockdown() then ns.reglages.dire("|cffff4040pas en combat.|r") return false end
  capture.apres = apres
  capture:Show()
  ns.reglages.dire("appuie sur la touche voulue pour récolter (Échap pour annuler).")
  return true
end

-- « Filon pas fini » : un addon n'a pas le droit de continuer la récolte à ta
-- place (ce serait un bot). Il peut en revanche te PRÉVENIR : après le butin,
-- si l'objet récolté est toujours devant toi, c'est qu'il reste des coups.
local estSecret = issecretvalue or function() return false end
local objetRecolte -- GUID du filon ou de l'herbe dont le butin est ouvert

local function guidSur(unite)
  local g = UnitGUID(unite)
  if estSecret(g) then return nil end
  return g
end

local function surButinOuvert()
  objetRecolte = nil
  if not db.actif or not GetLootSourceInfo then return end
  local g = GetLootSourceInfo(1)
  if not estSecret(g) and g and g:find("^GameObject") then objetRecolte = g end
end

-- ---------------------------------------------------------------------------
-- Filons mémorisés et flèche
-- ---------------------------------------------------------------------------
-- Le jeu ne donne PAS aux addons les points jaunes de la minimap. L'addon retient
-- donc lui-même chaque endroit où tu as récolté : les filons et les herbes
-- réapparaissent aux mêmes endroits, et la flèche te mène au plus proche connu.

local recent = {} -- point -> moment de sa dernière récolte (pour le sauter un moment)

-- Où suis-je ? Renvoie la carte, x, y, largeur et hauteur de la carte en mètres.
-- Rien en donjon, ni si le jeu cache la position (valeurs secrètes).
local function ici()
  if IsInInstance() or not C_Map or not C_Map.GetBestMapForUnit then return nil end
  local carte = C_Map.GetBestMapForUnit("player")
  if not carte or estSecret(carte) then return nil end
  local ok, pos = pcall(C_Map.GetPlayerMapPosition, carte, "player")
  if not ok or not pos then return nil end
  local x, y = pos:GetXY()
  if not x or estSecret(x) or estSecret(y) or (x == 0 and y == 0) then return nil end
  local largeur, hauteur = 1000, 1000
  if C_Map.GetMapWorldSize then
    local okT, l, h = pcall(C_Map.GetMapWorldSize, carte)
    if okT and l and l > 0 and not estSecret(l) then largeur, hauteur = l, h end
  end
  return carte, x, y, largeur, hauteur
end

-- Ce que ce personnage sait récolter, d'après ses métiers (minage 186,
-- herboristerie 182). Les endroits sont gardés pour tout le compte : sans ce
-- filtre, un dépeceur voyait les filons notés par ton mineur.
local genresCache, genresDate = nil, -100
local function genresConnus()
  if GetTime() - genresDate < 5 then return genresCache end
  genresDate = GetTime()
  genresCache = {}
  if GetProfessions and GetProfessionInfo then
    local metiers = { GetProfessions() } -- peut contenir des trous (nil)
    for i = 1, 5 do
      local index = metiers[i]
      if index then
        local skillLine = select(7, GetProfessionInfo(index))
        if skillLine == 186 then genresCache.minerai = true end
        if skillLine == 182 then genresCache.herbe = true end
      end
    end
  end
  return genresCache
end

local function memoriserIci(genre)
  local carte, x, y, l, h = ici()
  if not carte or not genre then return end
  local nom = UnitName and UnitName("softinteract")
  if estSecret(nom) then nom = nil end
  db.filons[carte] = db.filons[carte] or {}
  local liste = db.filons[carte]
  ns.memoriser(liste, x, y, nom, l, h, genre)
  -- Le point qu'on vient de récolter est « frais » : la flèche le saute 3 minutes.
  for _, q in ipairs(liste) do
    if ns.distance(q[1], q[2], x, y, l, h) < 20 then recent[q] = GetTime() end
  end
end

-- Nombre d'endroits connus sur une carte, et sur toutes les cartes.
local function nbFilons(carte) return carte and db.filons[carte] and #db.filons[carte] or 0 end
local function totalFilons()
  local total = 0
  for _, liste in pairs(db.filons) do total = total + #liste end
  return total
end

-- Oublie les endroits de la carte où tu es. Faux quand la position est inconnue.
local function oublierCarte()
  local carte = ici()
  if not carte then return false end
  db.filons[carte] = nil
  return true
end

local fleche = CreateFrame("Frame", "MetiersAutoFleche", UIParent)
fleche:SetSize(56, 70)
fleche:SetPoint("TOP", UIParent, "TOP", 0, -120)
fleche:SetMovable(true)
fleche:SetClampedToScreen(true)
fleche:EnableMouse(true)
fleche:RegisterForDrag("LeftButton")
fleche:SetScript("OnDragStart", fleche.StartMoving)
fleche:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local point, _, pointRelatif, x, y = self:GetPoint()
  db.positionFleche = { point, pointRelatif, x, y }
end)
fleche:Hide()
local image = fleche:CreateTexture(nil, "ARTWORK")
image:SetSize(42, 42)
image:SetPoint("TOP")
image:SetTexture("Interface\\Minimap\\MiniMap-QuestArrow")
local legende = fleche:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
legende:SetPoint("TOP", image, "BOTTOM", 0, -2)
legende:SetWidth(180)

-- La flèche à sa place : celle que tu as choisie en la glissant, sinon celle d'origine.
local function placerFleche()
  fleche:ClearAllPoints()
  local p = db.positionFleche
  if p then fleche:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  else fleche:SetPoint("TOP", UIParent, "TOP", 0, -120) end
end

-- Un petit moteur invisible recalcule la flèche 10 fois par seconde. La flèche
-- elle-même n'apparaît que s'il y a un endroit connu sur la carte où tu es.
local moteur = CreateFrame("Frame")
local attente = 0
moteur:SetScript("OnUpdate", function(_, ecoule)
  attente = attente + ecoule
  if attente < 0.1 then return end
  attente = 0
  if not db or not db.actif or not db.fleche or InCombatLockdown() then fleche:Hide() return end
  local carte, x, y, l, h = ici()
  local orientation = GetPlayerFacing and GetPlayerFacing()
  local liste = carte and db.filons[carte]
  local p, d
  if liste and orientation and not estSecret(orientation) then
    p, d = ns.plusProche(liste, x, y, l, h, recent, GetTime(), genresConnus())
  end
  if not p then fleche:Hide() return end
  image:SetRotation(ns.angleFleche(x, y, p[1], p[2], l, h, orientation))
  legende:SetText((p[3] or "Endroit connu") .. "\n" .. math.floor(d + 0.5) .. " m")
  fleche:Show()
end)

local function verifierFilon(essai)
  local g = objetRecolte
  if not db.filonPasFini then return end
  if not g or UnitCastingInfo("player") or UnitChannelInfo("player") then return end
  if guidSur("softinteract") ~= g then return end -- l'objet a disparu : récolte finie
  -- Récolte à la molette : tu roules de toute façon, donc l'alerte reste
  -- discrète (pas de son, pas de rappel).
  local brute = GetBindingKey and GetBindingKey("INTERACTTARGET")
  local molette = brute and brute:find("MOUSEWHEEL") ~= nil
  local k = toucheInteraction()
  local texte = molette and "Pas fini !"
    or ("Pas fini ! Appuie encore" .. (k and (" sur " .. k) or "") .. " pour finir la récolte.")
  if RaidNotice_AddMessage and RaidWarningFrame then
    RaidNotice_AddMessage(RaidWarningFrame, texte, ChatTypeInfo and ChatTypeInfo.RAID_WARNING or { r = 1, g = 0.5, b = 0 })
  end
  if molette or not db.filonSon then return end
  PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "master")
  -- Un rappel 4 secondes plus tard si tu n'as toujours rien fait.
  if essai == 1 then C_Timer.After(4, function() verifierFilon(2) end) end
end

local function surButinRecolte()
  -- Seulement un objet du monde (filon, herbe), pas un monstre ni la pêche, et
  -- seulement si le butin contient du minerai ou une herbe (pas un coffre).
  if not objetRecolte or modePeche then return end
  local objets = {}
  for i = 1, (GetNumLootItems and GetNumLootItems() or 0) do
    local lien = GetLootSlotLink and GetLootSlotLink(i)
    local infos = lien and ((C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant)
    if infos then
      local _, _, _, _, _, classe, sousClasse = infos(lien)
      objets[#objets + 1] = { classe = classe, sousClasse = sousClasse }
    end
  end
  memoriserIci(ns.genreDepuisButin(objets))
end

local function surButinFerme()
  if objetRecolte then C_Timer.After(0.6, function() verifierFilon(1) end) end
end

-- ---------------------------------------------------------------------------
-- 3. Liste de courses
-- ---------------------------------------------------------------------------

-- Composants obligatoires d'une recette, lus dans le jeu.
local function composants(recette)
  if not C_TradeSkillUI or not C_TradeSkillUI.GetRecipeSchematic then return nil end
  local ok, schema = pcall(C_TradeSkillUI.GetRecipeSchematic, recette, false)
  if not ok or not schema or not schema.reagentSlotSchematics then return nil end
  local liste = {}
  for _, slot in ipairs(schema.reagentSlotSchematics) do
    if slot.required ~= false and slot.reagents and #slot.reagents > 0 then
      local ids = {}
      for _, r in ipairs(slot.reagents) do
        if r.itemID then ids[#ids + 1] = r.itemID end
      end
      if #ids > 0 then liste[#liste + 1] = { ids = ids, quantite = slot.quantityRequired or 1 } end
    end
  end
  return liste, schema.name
end

local function possede(id)
  if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id, true, false, true) end
  return GetItemCount(id, true)
end

local function nomObjet(id)
  local nom = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id))
  return nom or ("objet " .. id)
end

local fenetreCourses = CreateFrame("Frame", "MetiersAutoCourses", UIParent, "BackdropTemplate")
fenetreCourses:SetSize(260, 40)
fenetreCourses:SetMovable(true)
fenetreCourses:SetClampedToScreen(true)
fenetreCourses:EnableMouse(true)
fenetreCourses:RegisterForDrag("LeftButton")
fenetreCourses:SetScript("OnDragStart", fenetreCourses.StartMoving)
fenetreCourses:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local point, _, pointRelatif, x, y = self:GetPoint()
  db.positionCourses = { point, pointRelatif, x, y }
end)
local _, fermer = ns.habiller(fenetreCourses, { titre = "Liste de courses", fermer = true })
fermer:SetScript("OnClick", function() ns.reglages.changer("afficherCourses", false) end)
local lignes = {}

-- La fenêtre de la liste à sa place : celle que tu as choisie, sinon celle d'origine.
local function placerCourses()
  fenetreCourses:ClearAllPoints()
  local p = db.positionCourses
  if p then fenetreCourses:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  else fenetreCourses:SetPoint("RIGHT", UIParent, "RIGHT", -60, 80) end
end

-- Remet la flèche et la liste de courses à leur place d'origine. Faux en combat.
local function replacerFenetres()
  if InCombatLockdown() then return false end
  db.positionFleche, db.positionCourses = nil, nil
  placerFleche()
  placerCourses()
  return true
end

local function majCourses()
  local liste = db.courses
  if not db.afficherCourses or #liste == 0 then fenetreCourses:Hide() return end
  local besoins = ns.besoins(liste, function(r) return (composants(r)) end)
  local recettes = {}
  for _, l in ipairs(liste) do recettes[#recettes + 1] = (l.nombre or 1) .. " × " .. (l.nom or l.recette) end
  local textes = { "|cffaaaaaa" .. table.concat(recettes, ", ") .. "|r" }
  local toutReuni = true
  for _, b in ipairs(besoins) do
    local a, manque = ns.manque(b, possede)
    if manque > 0 then toutReuni = false end
    textes[#textes + 1] = string.format("%s%s : %d / %d|r", manque > 0 and "|cffffa040" or "|cff40ff40",
      nomObjet(b.ids[1]), a, b.besoin)
  end
  if toutReuni then textes[#textes + 1] = "|cff40ff40Tout est réuni !|r" end
  for i, texte in ipairs(textes) do
    if not lignes[i] then
      lignes[i] = fenetreCourses:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      lignes[i]:SetPoint("TOPLEFT", 10, -12 - 16 * i)
      lignes[i]:SetWidth(240)
      lignes[i]:SetJustifyH("LEFT")
    end
    lignes[i]:SetText(texte)
    lignes[i]:Show()
  end
  for i = #textes + 1, #lignes do lignes[i]:Hide() end
  fenetreCourses:SetHeight(36 + 16 * #textes)
  fenetreCourses:Show()
end

-- ---------------------------------------------------------------------------
-- Réglages (fenêtre, icône de minimap : Reglages.lua)
-- ---------------------------------------------------------------------------

ns.reglages = ns.creerReglages({
  titre = "Métiers auto",
  icone = "Interface\\Icons\\Trade_Fishing",
  nomDB = "MetiersAutoDB",
  defauts = DEFAUTS,
  options = {
    { titre = "Général" },
    { cle = "actif", libelle = "Activer Métiers auto",
      aide = "Interrupteur général. Le clic droit sur l'icône fait la même chose." },
    { cle = "minimap", libelle = "Icône à part autour de la minimap",
      aide = "En plus de l'icône commune des addons de Valentin. Clic droit : activer ou couper." },
    { titre = "Pêche" },
    { cle = "pecheDoubleClic", libelle = "Double clic droit pour lancer la ligne",
      aide = "Seulement en mode pêche. Pour ferrer : clic droit sur le bouchon." },
    { cle = "pecheAuto", libelle = "Mode pêche dès que tu pêches toi-même",
      aide = "Il s'arrête seul après 60 secondes sans pêcher, ou en combat." },
    { cle = "pecheSon", libelle = "Bien entendre le bouchon",
      aide = "En mode pêche : effets sonores à fond, musique et ambiance coupées. Tout revient comme avant à la fin." },
    { titre = "Récolte" },
    { cle = "interaction", libelle = "Une touche pour récolter",
      aide = "« Interagir avec la cible » vise seule filon, herbe ou bouchon. Appuie autant de fois que le filon le demande. La touche se choisit plus bas." },
    { cle = "ramassage", libelle = "Ramassage automatique du butin",
      aide = "Le butin va directement dans tes sacs." },
    { cle = "reperage", libelle = "Remettre le repérage des minerais et herbes",
      aide = "Après une mort ou une reconnexion, sur la minimap." },
    { cle = "filonPasFini", libelle = "Prévenir quand un filon n'est pas fini",
      aide = "Message et son s'il reste des coups à donner, pour qu'un autre joueur ne le finisse pas." },
    { cle = "filonSon", libelle = "Son et rappel de cette alerte", dependDe = "filonPasFini",
      aide = "Jamais si ta touche de récolte est la molette : l'alerte reste discrète." },
    { cle = "fleche", libelle = "Flèche vers le filon ou l'herbe connu le plus proche",
      aide = "L'addon retient chaque endroit où tu récoltes (le nombre est plus bas). Déplace la flèche en la glissant." },
    { titre = "Artisanat" },
    { cle = "afficherCourses", libelle = "Afficher la liste de courses",
      aide = "La fenêtre à l'écran avec les composants des recettes de la liste et ce qu'il te manque. Déplace-la en la glissant." },
  },
  -- Zone « Touches et outils » : les touches, le mode pêche, les endroits connus,
  -- la place des fenêtres et la liste de courses.
  ongletContenu = "Outils",
  contenu = function(fenetre, y, r)
    local function texteFixe(x, haut, largeur)
      local fs = fenetre:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      fs:SetPoint("TOPLEFT", x, haut)
      fs:SetWidth(largeur)
      fs:SetJustifyH("LEFT")
      return fs
    end
    local t = fenetre:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, y - 6)
    t:SetText("Touches et outils")
    y = y - 32
    local maj, majListe -- fonctions de mise à jour, définies plus bas

    -- La touche de récolte et le bouton pour la choisir.
    local touche = texteFixe(20, y - 5, 230)
    local b0
    b0 = ns.creerBouton(fenetre, "Choisir la touche",
      "Appuie ensuite sur la touche voulue : elle devient « Interagir avec la cible ». Échap annule. Impossible en combat.",
      function()
        if choisirTouche(function() maj() end) then b0:SetText("Appuie sur une touche…") end
      end, 150)
    b0:SetPoint("TOPLEFT", 254, y)
    y = y - 34

    -- Le mode pêche et son raccourci.
    local b1 = ns.creerBouton(fenetre, "Démarrer le mode pêche",
      "Double clic droit pour lancer la ligne, clic droit sur le bouchon pour ferrer. S'arrête seul après 60 secondes sans pêcher.",
      function() MetiersAuto_ModePeche(); r.appliquer() end, 190)
    b1:SetPoint("TOPLEFT", 16, y)
    local touchePeche = texteFixe(214, y - 5, 200)
    y = y - 34

    -- Les endroits retenus pour la flèche.
    local filons = texteFixe(20, y - 5, 230)
    local b2 = ns.creerBouton(fenetre, "Oublier cette carte",
      "Efface les endroits retenus sur la carte où tu es. Les autres cartes ne changent pas.",
      function()
        if oublierCarte() then r.dire("endroits oubliés pour cette carte.")
        else r.dire("position inconnue ici (donjon, ou position cachée par le jeu).") end
        r.majFenetre()
      end, 150)
    b2:SetPoint("TOPLEFT", 254, y)
    y = y - 34

    -- La place de la flèche et de la liste.
    local b3 = ns.creerBouton(fenetre, "Replacer la flèche et la liste",
      "Remet la flèche et la liste de courses à leur place d'origine, par exemple si l'une est sortie de l'écran.",
      function()
        if replacerFenetres() then r.dire("flèche et liste de courses remises à leur place.")
        else r.dire("|cffff4040pas en combat.|r") end
      end, 220)
    b3:SetPoint("TOPLEFT", 16, y)
    y = y - 34

    -- La liste de courses : on y retire une ligne ou tout ; l'ajout se fait en jeu.
    local aide = fenetre:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    aide:SetPoint("TOPLEFT", 20, y - 2)
    aide:SetWidth(380)
    aide:SetJustifyH("LEFT")
    aide:SetText("Pour ajouter une recette : ouvre ton métier, tape /mt courses 5 (5 = le nombre à fabriquer), puis Maj+clic sur la recette.")
    local hAide = aide.GetStringHeight and aide:GetStringHeight()
    y = y - 6 - math.max(type(hAide) == "number" and hAide or 0, 24)
    y, majListe = ns.creerListe(fenetre, y, {
      titre = "Liste de courses",
      vide = "Aucune recette dans la liste.",
      hauteur = 5,
      lignes = function()
        return ns.lignesCourses(db.courses, function(i) table.remove(db.courses, i); r.appliquer() end)
      end,
      vider = function() r.changer("courses", {}); r.dire("liste de courses vidée.") end,
    })

    maj = function()
      local k = toucheInteraction()
      touche:SetText("Touche pour récolter : " .. (k and ("|cff00ff00" .. k .. "|r") or "|cffff4040aucune|r"))
      b0:SetText(k and "Changer la touche" or "Choisir la touche")
      b1:SetText(modePeche and "Arrêter le mode pêche" or "Démarrer le mode pêche")
      local kp = texteTouche("METIERSAUTO_PECHE")
      touchePeche:SetText("Raccourci : " .. (kp and ("|cff00ff00" .. kp .. "|r") or "|cffff4040aucun|r"))
      local carte = ici()
      filons:SetText(ns.texteFilons(carte and nbFilons(carte) or nil, totalFilons()))
      if carte and nbFilons(carte) > 0 then b2:Enable() else b2:Disable() end
      majListe()
    end
    return y, maj
  end,
  astuce = "Tout s'applique tout de suite, sans /reload. Le raccourci du mode pêche se choisit dans Échap > Options > Raccourcis. Commande : /mt.",
  auChargement = function(d)
    db = d
    -- Un mode pêche coupé par une déconnexion : on remet le son d'avant.
    sonNormal()
    placerCourses()
    placerFleche()
  end,
  surChangement = function(d)
    if not d.actif and modePeche then changerModePeche(false) end
    if modePeche then
      if d.pecheSon then sonPeche() else sonNormal() end
    end
    appliquerCVars()
    remettreReperage()
    majCourses()
  end,
})

-- ---------------------------------------------------------------------------
-- Événements
-- ---------------------------------------------------------------------------

local ecouteur = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_UNGHOST", "PLAYER_ALIVE", "PLAYER_REGEN_DISABLED",
                     "UNIT_SPELLCAST_CHANNEL_START", "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED",
                     "LOOT_OPENED", "LOOT_CLOSED" }) do
  ecouteur:RegisterEvent(e)
end
ecouteur:SetScript("OnEvent", function(_, evenement, unite, _, idSort)
  if not db then return end
  if evenement == "PLAYER_REGEN_DISABLED" then
    if modePeche then changerModePeche(false) end
  elseif evenement == "UNIT_SPELLCAST_CHANNEL_START" then
    if unite == "player" and PECHE[idSort] then
      derniereActivite = GetTime()
      if db.actif and db.pecheAuto and not modePeche then changerModePeche(true) end
    end
  elseif evenement == "LOOT_OPENED" then
    surButinOuvert()
    surButinRecolte()
  elseif evenement == "LOOT_CLOSED" then
    surButinFerme()
  elseif evenement == "BAG_UPDATE_DELAYED" or evenement == "GET_ITEM_INFO_RECEIVED" then
    if #db.courses > 0 then majCourses() end
  else
    appliquerCVars()
    remettreReperage()
    if evenement == "PLAYER_ENTERING_WORLD" then majCourses() end
  end
end)

-- ---------------------------------------------------------------------------
-- Commande /mt
-- ---------------------------------------------------------------------------

SLASH_METIERSAUTO1 = "/mt"
SLASH_METIERSAUTO2 = "/metiersauto"
SlashCmdList.METIERSAUTO = function(texte)
  local cmd, reste = strtrim(texte or ""):match("^(%S*)%s*(.-)$")
  cmd = cmd:lower()
  local r = ns.reglages
  if cmd == "" or cmd == "options" or cmd == "reglages" then
    r.ouvrir()
  elseif cmd == "peche" or cmd == "pêche" then
    MetiersAuto_ModePeche()
  elseif cmd == "on" or cmd == "off" then
    if (cmd == "on") ~= (db.actif and true or false) then r.basculer() end
  elseif cmd == "filons" then
    if reste:lower() == "oublier" then
      return r.dire(oublierCarte() and "endroits oubliés pour cette carte."
        or "position inconnue ici (donjon, ou position cachée par le jeu).")
    end
    local cartes = 0
    for _ in pairs(db.filons) do cartes = cartes + 1 end
    local carte = ici()
    r.dire(string.format("%s, sur %d cartes. /mt filons oublier : vider cette carte.",
      ns.texteFilons(carte and nbFilons(carte) or nil, totalFilons()), cartes))
  elseif cmd == "courses" then
    if reste:lower() == "vider" then
      r.changer("courses", {})
      return r.dire("liste de courses vidée.")
    end
    local nombre, recette = ns.lireRecette(reste)
    if not recette then
      return r.dire("ouvre ton métier, tape /mt courses 5 puis Maj+clic sur la recette.")
    end
    local liste, nom = composants(recette)
    if not liste then
      return r.dire("recette introuvable : ouvre d'abord la fenêtre de ton métier.")
    end
    table.insert(db.courses, { recette = recette, nombre = nombre, nom = nom })
    db.afficherCourses = true
    r.appliquer()
    r.dire("ajouté à la liste de courses : " .. nombre .. " × " .. (nom or recette) .. ".")
  elseif not r.basculerOption(cmd) then
    r.dire("/mt : réglages     /mt peche : mode pêche     /mt on, /mt off")
    r.dire("/mt courses 5 <recette> : ajouter (Maj+clic sur la recette)     /mt courses vider")
    r.dire("/mt filons : endroits de récolte connus     /mt filons oublier")
  end
end
