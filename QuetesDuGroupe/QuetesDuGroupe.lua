-- ============================================================================
-- Quêtes du groupe : quand vous êtes groupés, un panneau montre les quêtes de
-- chacun et où il en est. Trois parties par joueur du groupe :
--  - en commun : la quête, ta progression et la sienne ;
--  - lui seulement : des quêtes que tu pourrais aller prendre ;
--  - toi seulement : des quêtes que tu pourrais lui partager.
-- Il faut que l'autre ait aussi l'addon : les journaux de quêtes s'échangent
-- par messages d'addon, invisibles dans le chat.
-- Commande : /qg (le panneau), /qg options (les réglages).
-- ============================================================================

local NOM_ADDON, ns = ...
local PREFIXE = "QuetesDuGroupe" -- 16 caractères au plus, imposé par le jeu
local SEP = "~"               -- séparateur des champs d'un message

local DEFAUTS = {
  actif = true,          -- échanger les quêtes avec le groupe
  afficherAuto = true,   -- ouvrir le panneau quand un joueur du groupe avec l'addon arrive
  minimap = false,       -- icône à part (sinon seulement l'icône commune)
  angleMinimap = 160,
}

local db
local estSecret = issecretvalue or function() return false end

-- ---------------------------------------------------------------------------
-- Partie « logique pure », testée hors jeu (tests/QuetesDuGroupe_simu.lua).
-- ---------------------------------------------------------------------------

-- Coupe un texte à n octets sans laisser une lettre accentuée à moitié.
local function couper(texte, n)
  texte = tostring(texte or ""):gsub(SEP, "-")
  if #texte <= n then return texte end
  return (texte:sub(1, n):gsub("[\128-\255]+$", ""))
end

-- Progression d'une quête : "3/8,1/1" (une paire par objectif), "fini" si finie.
function ns.progression(objectifs, finie)
  if finie then return "fini" end
  local t = {}
  for _, o in ipairs(objectifs or {}) do
    if o.numRequired and o.numRequired > 0 then
      t[#t + 1] = (o.numFulfilled or 0) .. "/" .. o.numRequired
    end
  end
  return table.concat(t, ",")
end

-- Messages échangés (un message = une ligne de moins de 255 octets) :
--   "P~niveau~zone~nombre"  : qui je suis, puis « nombre » quêtes suivent ;
--   "Q~id~titre~progression" : une quête ;
--   "?"                       : « renvoyez-moi vos quêtes ».
function ns.messageProfil(niveau, zone, nombre)
  return table.concat({ "P", niveau or 0, couper(zone, 60), nombre or 0 }, SEP)
end

function ns.messageQuete(q)
  return table.concat({ "Q", q.id, couper(q.titre, 90), couper(q.prog, 90) }, SEP)
end

function ns.lireMessage(texte)
  if texte == "?" then return { type = "?" } end
  local champs = {}
  for c in (texte .. SEP):gmatch("(.-)" .. SEP) do champs[#champs + 1] = c end
  if champs[1] == "P" then
    return { type = "P", niveau = tonumber(champs[2]) or 0, zone = champs[3] or "", nombre = tonumber(champs[4]) or 0 }
  elseif champs[1] == "Q" and tonumber(champs[2]) then
    return { type = "Q", id = tonumber(champs[2]), titre = champs[3] or "", prog = champs[4] or "" }
  end
end

-- Compare tes quêtes ({ [id] = { titre, prog } }) à celles d'un frère.
-- Renvoie trois listes triées par titre : commun, luiSeul, moiSeul.
function ns.comparer(miennes, siennes)
  local commun, luiSeul, moiSeul = {}, {}, {}
  for id, q in pairs(siennes) do
    if miennes[id] then
      commun[#commun + 1] = { id = id, titre = q.titre, moi = miennes[id].prog, lui = q.prog }
    else
      luiSeul[#luiSeul + 1] = { id = id, titre = q.titre, lui = q.prog }
    end
  end
  for id, q in pairs(miennes) do
    if not siennes[id] then moiSeul[#moiSeul + 1] = { id = id, titre = q.titre, moi = q.prog } end
  end
  local function parTitre(a, b) return a.titre < b.titre end
  table.sort(commun, parTitre); table.sort(luiSeul, parTitre); table.sort(moiSeul, parTitre)
  return commun, luiSeul, moiSeul
end

-- ---------------------------------------------------------------------------
-- Mon journal de quêtes
-- ---------------------------------------------------------------------------

local function mesQuetes()
  local t = {}
  local q = C_QuestLog
  if not (q and q.GetNumQuestLogEntries and q.GetInfo) then return t end
  for i = 1, q.GetNumQuestLogEntries() do
    local info = q.GetInfo(i)
    if info and not info.isHeader and not info.isHidden and info.questID and info.questID > 0 then
      local id = info.questID
      local finie = q.IsComplete and q.IsComplete(id)
      t[id] = { titre = info.title or ("Quête " .. id),
                prog = ns.progression(q.GetQuestObjectives and q.GetQuestObjectives(id), finie) }
    end
  end
  return t
end

-- ---------------------------------------------------------------------------
-- Envoi : une file de messages, un toutes les 0,15 s (le jeu limite le débit).
-- ---------------------------------------------------------------------------

local file, envoiEnCours = {}, false
local dernierEnvoi = "" -- pour ne pas renvoyer une liste qui n'a pas changé

local function canal()
  if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
  if IsInRaid() then return "RAID" end
  if IsInGroup() then return "PARTY" end
end

local function viderFile()
  local c = canal()
  if #file == 0 or not c then file = {}; envoiEnCours = false return end
  local msg = table.remove(file, 1)
  pcall(C_ChatInfo.SendAddonMessage, PREFIXE, msg, c)
  C_Timer.After(0.15, viderFile)
end

local function envoyer(messages)
  for _, m in ipairs(messages) do file[#file + 1] = m end
  if not envoiEnCours then envoiEnCours = true; viderFile() end
end

local function partagerMesQuetes(force)
  if not db or not db.actif or not canal() then return end
  if InCombatLockdown() then return end -- en combat, on attend la prochaine mise à jour
  local liste = {}
  for id, q in pairs(mesQuetes()) do liste[#liste + 1] = ns.messageQuete({ id = id, titre = q.titre, prog = q.prog }) end
  table.sort(liste)
  local resume = table.concat(liste, "\n")
  if resume == dernierEnvoi and not force then return end
  dernierEnvoi = resume
  local messages = { ns.messageProfil(UnitLevel("player"), GetZoneText(), #liste) }
  for _, m in ipairs(liste) do messages[#messages + 1] = m end
  envoyer(messages)
end

-- Plusieurs mises à jour du journal en rafale : un seul envoi, 2 s après.
local envoiPrevu = false
local function prevoirEnvoi()
  if envoiPrevu then return end
  envoiPrevu = true
  C_Timer.After(2, function() envoiPrevu = false; partagerMesQuetes() end)
end

-- ---------------------------------------------------------------------------
-- Réception
-- ---------------------------------------------------------------------------

local freres = {} -- [nom] = { niveau, zone, quetes = { [id] = { titre, prog } } }
local rafraichir -- défini avec le panneau

local function surMessage(prefixe, texte, _, auteur)
  if prefixe ~= PREFIXE or not db or not db.actif then return end
  if estSecret(texte) or estSecret(auteur) then return end
  local nom = Ambiguate(auteur, "none")
  if nom == UnitName("player") then return end
  local m = ns.lireMessage(texte)
  if not m then return end
  if m.type == "?" then
    partagerMesQuetes(true)
  elseif m.type == "P" then
    local nouveau = not freres[nom]
    freres[nom] = { niveau = m.niveau, zone = m.zone, quetes = {} }
    if nouveau and db.afficherAuto and ns.panneau and not ns.panneau:IsShown() then ns.panneau:Show() end
  elseif m.type == "Q" and freres[nom] then
    freres[nom].quetes[m.id] = { titre = m.titre, prog = m.prog }
  end
  rafraichir()
end

-- Ceux qui ont quitté le groupe disparaissent du panneau.
local function nettoyer()
  for nom in pairs(freres) do
    if not (UnitInParty(nom) or UnitInRaid(nom)) then freres[nom] = nil end
  end
end

-- ---------------------------------------------------------------------------
-- Le panneau
-- ---------------------------------------------------------------------------

local panneau = CreateFrame("Frame", "QuetesDuGroupePanneau", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
ns.panneau = panneau
panneau:SetSize(380, 420)
panneau:SetPoint("LEFT", UIParent, "LEFT", 40, 0)
panneau:SetMovable(true)
panneau:SetClampedToScreen(true)
panneau:EnableMouse(true)
panneau:RegisterForDrag("LeftButton")
panneau:SetScript("OnDragStart", panneau.StartMoving)
panneau:SetScript("OnDragStop", panneau.StopMovingOrSizing)
panneau:Hide()
tinsert(UISpecialFrames, panneau:GetName())
ns.habiller(panneau, { titre = "Quêtes du groupe", fermer = true })

local defile = CreateFrame("ScrollFrame", nil, panneau, "UIPanelScrollFrameTemplate")
defile:SetPoint("TOPLEFT", 12, -30)
defile:SetPoint("BOTTOMRIGHT", -30, 12)
local contenu = CreateFrame("Frame", nil, defile)
contenu:SetSize(330, 10)
defile:SetScrollChild(contenu)
local texte = contenu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
texte:SetPoint("TOPLEFT")
texte:SetWidth(330)
texte:SetJustifyH("LEFT")
texte:SetSpacing(2)

local function lignePour(q, moiAussi)
  local l = "  " .. q.titre
  if moiAussi then
    return l .. "  |cffaaaaaa(toi " .. (q.moi ~= "" and q.moi or "-") .. " · lui " .. (q.lui ~= "" and q.lui or "-") .. ")|r"
  end
  local p = q.lui or q.moi
  return l .. ((p and p ~= "") and ("  |cffaaaaaa(" .. p .. ")|r") or "")
end

rafraichir = function()
  if not panneau:IsShown() then return end
  nettoyer()
  local t = {}
  local miennes = mesQuetes()
  for nom, f in pairs(freres) do
    local commun, luiSeul, moiSeul = ns.comparer(miennes, f.quetes)
    t[#t + 1] = string.format("|cffffd200%s|r  (niveau %d, %s)", nom, f.niveau, f.zone)
    t[#t + 1] = "|cff00ff00En commun (" .. #commun .. ")|r"
    for _, q in ipairs(commun) do t[#t + 1] = lignePour(q, true) end
    t[#t + 1] = "|cff66bbffLui seulement (" .. #luiSeul .. ")|r : à aller prendre ?"
    for _, q in ipairs(luiSeul) do t[#t + 1] = lignePour(q) end
    t[#t + 1] = "|cffff9933Toi seulement (" .. #moiSeul .. ")|r : à lui partager ?"
    for _, q in ipairs(moiSeul) do t[#t + 1] = lignePour(q) end
    t[#t + 1] = " "
  end
  if #t == 0 then
    if not canal() then
      t[1] = "Tu n'es pas en groupe."
    else
      t[1] = "Personne dans le groupe n'a encore envoyé ses quêtes."
      t[2] = "Il faut que l'autre ait aussi installé Quêtes du groupe."
    end
  end
  texte:SetText(table.concat(t, "\n"))
  contenu:SetHeight(texte:GetStringHeight() + 10)
end
panneau:SetScript("OnShow", function() rafraichir() end)

local function basculerPanneau()
  panneau:SetShown(not panneau:IsShown())
  if panneau:IsShown() and canal() and db and db.actif then envoyer({ "?" }) end
end

-- ---------------------------------------------------------------------------
-- Réglages (Reglages.lua) : le clic dans l'icône commune ouvre le panneau.
-- ---------------------------------------------------------------------------

ns.reglages = ns.creerReglages({
  titre = "Quêtes du groupe",
  icone = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend",
  nomDB = "QuetesDuGroupeDB",
  defauts = DEFAUTS,
  ouvrirHub = basculerPanneau, texteHub = "Quêtes du groupe",
  options = {
    { titre = "En groupe" },
    { cle = "actif", libelle = "Échanger les quêtes avec le groupe",
      aide = "Coupé : tu n'envoies plus tes quêtes et tu ignores celles des autres." },
    { cle = "afficherAuto", libelle = "Ouvrir le panneau tout seul",
      aide = "Quand un joueur du groupe qui a l'addon envoie ses quêtes pour la première fois." },
    { titre = "Affichage" },
    { cle = "minimap", libelle = "Icône à part autour de la minimap",
      aide = "En plus de l'icône commune « Mes addons ». Clic droit : activer ou couper." },
  },
  astuce = "Le panneau : /qg, le bouton en haut de cette fenêtre ou Maj+clic sur la ligne de l'icône commune.",
  auChargement = function(d) db = d end,
})

-- ---------------------------------------------------------------------------
-- Événements et commande /qg
-- ---------------------------------------------------------------------------

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
  C_ChatInfo.RegisterAddonMessagePrefix(PREFIXE)
end

-- Ancien nom : cet addon s'appelait « EntreFreres ». Si l'ancien dossier est
-- encore là (copie à la main, ou WowUp qui ne l'a pas retiré), on le coupe pour
-- ne pas avoir deux panneaux : il sera vraiment parti au prochain /reload.
local GetInfoAddon = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
local CouperAddon = (C_AddOns and C_AddOns.DisableAddOn) or DisableAddOn
if GetInfoAddon and CouperAddon and GetInfoAddon("EntreFreres") then
  local charge = (C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded)("EntreFreres")
  CouperAddon("EntreFreres")
  if charge then
    C_Timer.After(5, function()
      print("|cff33ff99Quêtes du groupe|r : l'ancien addon « EntreFreres » est remplacé par celui-ci. "
        .. "Il est coupé ; fais /reload, puis tu peux supprimer son dossier.")
    end)
  end
end

local ecouteur = CreateFrame("Frame")
ecouteur:RegisterEvent("CHAT_MSG_ADDON")
ecouteur:RegisterEvent("QUEST_LOG_UPDATE")
ecouteur:RegisterEvent("GROUP_ROSTER_UPDATE")
ecouteur:RegisterEvent("PLAYER_ENTERING_WORLD")
ecouteur:RegisterEvent("PLAYER_REGEN_ENABLED")
ecouteur:SetScript("OnEvent", function(_, evenement, ...)
  if evenement == "CHAT_MSG_ADDON" then
    surMessage(...)
  elseif evenement == "GROUP_ROSTER_UPDATE" or evenement == "PLAYER_ENTERING_WORLD" then
    -- Nouveau groupe ou nouvelle zone : on renvoie tout et on demande aux autres.
    dernierEnvoi = ""
    if db and db.actif and canal() then envoyer({ "?" }) end
    prevoirEnvoi()
    rafraichir()
  else
    prevoirEnvoi()
    rafraichir()
  end
end)

SLASH_QUETESDUGROUPE1 = "/qg"
SLASH_QUETESDUGROUPE2 = "/quetesdugroupe"
SlashCmdList.QUETESDUGROUPE = function(message)
  local cmd = strtrim(message or ""):lower()
  local r = ns.reglages
  if cmd == "" then
    basculerPanneau()
  elseif cmd == "options" or cmd == "reglages" then
    r.ouvrir()
  elseif cmd == "on" or cmd == "off" then
    if (cmd == "on") ~= (db.actif and true or false) then r.basculer() end
  elseif not r.basculerOption(cmd) then
    r.dire("/qg : le panneau     /qg options : les réglages     /qg on, /qg off")
  end
end
