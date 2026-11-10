-- ============================================================================
-- Rapport d'erreurs : garde les erreurs Lua (et les petits journaux des addons)
-- et les envoie à celui qui les analyse, par messages d'addon invisibles.
--
-- Deux rôles, réglés dans la fenêtre de réglages (/re options) :
--  - « Envoyer mes erreurs » (coché au départ) : chez tes amis. Leurs erreurs
--    partent vers un joueur qui a coché « Recevoir », dès qu'il est en ligne et
--    joignable : dans ton groupe, dans ta guilde ou dans ta liste d'amis.
--  - « Recevoir les erreurs des autres » (décoché au départ) : chez Valentin.
--    Les erreurs reçues sont rangées par joueur dans RapportErreursDB, que
--    l'on relit hors du jeu après un /reload.
-- Par défaut, seules les erreurs des « Addons de Valentin » partent.
-- Commandes : /re (le panneau), /re options, /re demander <joueur>, /re test,
-- /re etat, /re effacer, /re <réglage> (coche ou décoche : envoyer, recevoir…).
-- Un addon peut écrire dans le journal : RapportErreurs_Noter("MonAddon", "texte").
-- ============================================================================

local NOM_ADDON, ns = ...
local PREFIXE = "RapportErreurs" -- 16 caractères au plus, imposé par le jeu
local TAILLE = 220               -- octets de texte par message (le jeu en accepte 255)
local MAX_ERREURS, MAX_JOURNAL, MAX_RECUES = 60, 200, 60
local CATEGORIE = "Addons de Valentin"

local DEFAUTS = {
  actif = true,
  envoyer = true,      -- envoyer mes erreurs à ceux qui reçoivent
  recevoir = false,    -- recevoir les erreurs des autres (Valentin)
  toutes = false,      -- envoyer aussi les erreurs des autres addons
  annoncer = true,     -- un message dans le chat à chaque erreur reçue
  minimap = false,
  angleMinimap = 200,
  erreurs = {},        -- mes erreurs
  journal = {},        -- lignes écrites par les addons (RapportErreurs_Noter)
  recues = {},         -- [joueur] = { infos = texte, erreurs = { … } }
}

local db
local dernierRecevoir -- pour voir quand « recevoir » change en jeu
local estSecret = issecretvalue or function() return false end
local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata

-- ---------------------------------------------------------------------------
-- Partie « logique pure », testée hors jeu (tests/RapportErreurs_simu.lua).
-- ---------------------------------------------------------------------------

-- Échappe un texte pour qu'il tienne sur une ligne sans tabulation : les
-- champs d'un message sont séparés par des tabulations.
function ns.echapper(t)
  return (tostring(t or ""):gsub("\\", "\\\\"):gsub("\n", "\\n"):gsub("\t", "\\t"):gsub("\r", ""))
end

function ns.dechapper(t)
  return (t:gsub("\\(.)", function(c)
    if c == "n" then return "\n" elseif c == "t" then return "\t" end
    return c
  end))
end

-- Une liste de champs <-> une ligne.
function ns.encoder(champs)
  local t = {}
  for i, c in ipairs(champs) do t[i] = ns.echapper(c) end
  return table.concat(t, "\t")
end

function ns.decoder(ligne)
  local champs = {}
  for c in (ligne .. "\t"):gmatch("(.-)\t") do champs[#champs + 1] = ns.dechapper(c) end
  return champs
end

-- Coupe un texte en morceaux de n octets au plus, sans couper une lettre
-- accentuée en deux (un octet 10xxxxxx continue la lettre précédente).
function ns.decouper(texte, n)
  local morceaux, i = {}, 1
  while i <= #texte do
    local fin = math.min(i + n - 1, #texte)
    while fin < #texte and fin > i do
      local b = texte:byte(fin + 1)
      if b < 0x80 or b >= 0xC0 then break end
      fin = fin - 1
    end
    morceaux[#morceaux + 1] = texte:sub(i, fin)
    i = fin + 1
  end
  if #morceaux == 0 then morceaux[1] = "" end
  return morceaux
end

-- Recolle les morceaux reçus. Renvoie le texte entier quand tout est arrivé.
function ns.nouveauRecolleur()
  local enCours = {} -- [auteur .. id] = { total, recus, morceaux }
  return function(auteur, id, rang, total, morceau)
    local cle = auteur .. "#" .. id
    local e = enCours[cle]
    if not e then e = { total = total, recus = 0, morceaux = {} } enCours[cle] = e end
    if not e.morceaux[rang] then e.morceaux[rang] = morceau; e.recus = e.recus + 1 end
    if e.recus < e.total then return nil end
    enCours[cle] = nil
    return table.concat(e.morceaux, "", 1, e.total)
  end
end

-- L'addon en cause : le premier « AddOns/<Nom>/ » du message, sinon de la pile.
function ns.addonDe(message, pile)
  return (message or ""):match("AddOns[/\\]([^/\\]+)[/\\]")
      or (pile or ""):match("AddOns[/\\]([^/\\]+)[/\\]")
end

-- Range une erreur dans une liste : même message = même erreur, on compte.
-- Renvoie l'entrée et true si elle est nouvelle.
function ns.ranger(liste, e, maxi)
  for _, x in ipairs(liste) do
    if x.message == e.message then
      x.nombre = (x.nombre or 1) + (e.nombre or 1)
      x.derniere = e.derniere or x.derniere
      x.envoyee = false
      return x, false
    end
  end
  e.nombre = e.nombre or 1
  table.insert(liste, 1, e)
  while #liste > maxi do table.remove(liste) end
  return e, true
end

-- Nombre d'erreurs pas encore envoyées.
function ns.compterEnAttente(erreurs)
  local n = 0
  for _, e in ipairs(erreurs or {}) do if not e.envoyee then n = n + 1 end end
  return n
end

-- La ligne d'état en direct : qui reçoit, combien d'erreurs attendent.
-- destinataires : { [joueur] = true }
function ns.texteEtat(destinataires, enAttente)
  local noms = {}
  for nom in pairs(destinataires or {}) do noms[#noms + 1] = nom end
  table.sort(noms)
  return "Destinataires connus : " .. (#noms > 0 and table.concat(noms, ", ") or "aucun")
    .. "\nErreurs pas encore envoyées : " .. enAttente
end

-- ---------------------------------------------------------------------------
-- Capture des erreurs
-- ---------------------------------------------------------------------------

-- Nos addons : la catégorie ou l'auteur du .toc, sinon cette liste de secours
-- (une version du jeu peut ne pas lire le champ « Category »).
local nosAddons = { AlerteRare = true, ButinRapide = true, CarnetDeSession = true, LivresBiblio = true,
  MarchandAuto = true, MetiersAuto = true, QuetesAuto = true, QuetesDuGroupe = true,
  RapportErreurs = true, SacsRanges = true }
local function estANous(addon)
  if not addon or addon == "?" then return false end
  if nosAddons[addon] == nil then
    local lire = GetMeta or function() end
    local ok1, cat = pcall(lire, addon, "Category")
    local ok2, auteur = pcall(lire, addon, "Author")
    nosAddons[addon] = (ok1 and cat == CATEGORIE) or (ok2 and auteur == "Valentin") or false
  end
  return nosAddons[addon]
end

local function versionDe(addon)
  if not addon or not GetMeta then return "?" end
  local ok, v = pcall(GetMeta, addon, "Version")
  return ok and v or "?"
end

local envoyerEnAttente, annoncer -- définis plus bas
local dansNoter = false

local function noter(message, pile, genre)
  if not db or not db.actif or dansNoter then return end
  if estSecret(message) or estSecret(pile) then return end
  dansNoter = true
  pcall(function()
    message = tostring(message or "?")
    local addon = ns.addonDe(message, pile)
    local maintenant = time()
    ns.ranger(db.erreurs, {
      message = message:sub(1, 1500),
      pile = tostring(pile or ""):sub(1, 2500),
      genre = genre or "erreur",
      addon = addon or "?",
      version = versionDe(addon),
      premiere = maintenant,
      derniere = maintenant,
    }, MAX_ERREURS)
    if envoyerEnAttente then C_Timer.After(1, envoyerEnAttente) end
  end)
  dansNoter = false
end

-- On se place devant le gestionnaire d'erreurs existant (celui du jeu ou de
-- BugGrabber), qui continue d'être appelé ensuite : on ne cache rien.
local ancienGestionnaire = geterrorhandler and geterrorhandler()
if seterrorhandler and ancienGestionnaire then
  seterrorhandler(function(message, ...)
    noter(message, debugstack and debugstack(3) or "", "erreur")
    return ancienGestionnaire(message, ...)
  end)
end

-- Journal ouvert aux autres addons.
function RapportErreurs_Noter(addon, texte)
  if not db or not db.actif then return end
  table.insert(db.journal, 1, { heure = time(), addon = tostring(addon), texte = tostring(texte):sub(1, 500) })
  while #db.journal > MAX_JOURNAL do table.remove(db.journal) end
end

-- ---------------------------------------------------------------------------
-- Qui joindre
-- ---------------------------------------------------------------------------

local destinataires = {} -- [joueur] = true : ont dit « je reçois » pendant cette session

local function enLigne(nom)
  if UnitInParty and (UnitInParty(nom) or UnitInRaid(nom)) then return true end
  if C_FriendList and C_FriendList.GetFriendInfo then
    local info = C_FriendList.GetFriendInfo(nom)
    if info and info.connected then return true end
  end
  if IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
    for i = 1, GetNumGuildMembers() do
      local n, _, _, _, _, _, _, _, connecte = GetGuildRosterInfo(i)
      if n and Ambiguate(n, "none") == nom and connecte then return true end
    end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- Envoi : une file, un message toutes les 0,2 s, jamais en combat.
-- ---------------------------------------------------------------------------

local file, envoiEnCours, compteur = {}, false, 0

local function viderFile()
  if #file == 0 then envoiEnCours = false return end
  if InCombatLockdown() then C_Timer.After(2, viderFile) return end
  local m = table.remove(file, 1)
  pcall(C_ChatInfo.SendAddonMessage, PREFIXE, m.texte, m.canal, m.cible)
  C_Timer.After(0.2, viderFile)
end

local function poster(texte, canal, cible)
  file[#file + 1] = { texte = texte, canal = canal, cible = cible }
  if not envoiEnCours then envoiEnCours = true; viderFile() end
end

-- Un long texte part en morceaux : « M <id> <rang> <total> <morceau> ».
local function posterLong(genre, champs, cible)
  compteur = compteur + 1
  local id = genre .. (time() % 100000) .. "." .. compteur
  local morceaux = ns.decouper(ns.encoder(champs), TAILLE)
  for i, m in ipairs(morceaux) do
    poster("M\t" .. id .. "\t" .. i .. "\t" .. #morceaux .. "\t" .. m, "WHISPER", cible)
  end
end

local function infosPerso()
  local v, build = GetBuildInfo()
  local _, classe = UnitClass("player")
  local lignes = {
    "Jeu : " .. tostring(v) .. " (" .. tostring(build) .. ")",
    "Personnage : " .. UnitName("player") .. "-" .. (GetRealmName() or "?") .. ", " .. tostring(classe)
      .. " niveau " .. tostring(UnitLevel("player")),
  }
  local nb = (C_AddOns and C_AddOns.GetNumAddOns or GetNumAddOns)()
  local nos, autres = {}, {}
  for i = 1, nb do
    local nom = (C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo)(i)
    local charge = (C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded)(i)
    if charge then
      if estANous(nom) then nos[#nos + 1] = nom .. " " .. versionDe(nom) else autres[#autres + 1] = nom end
    end
  end
  lignes[#lignes + 1] = "Nos addons : " .. table.concat(nos, ", ")
  lignes[#lignes + 1] = "Autres addons chargés : " .. table.concat(autres, ", ")
  return table.concat(lignes, "\n")
end

local function envoyerErreur(e, cible)
  posterLong("E", { e.addon, e.version, e.genre, e.nombre, e.premiere, e.derniere, e.message, e.pile }, cible)
end

-- Les erreurs pas encore envoyées partent vers chaque destinataire joignable.
local derniereRelance = 0
envoyerEnAttente = function()
  if not db or not db.actif or not db.envoyer then return end
  -- Personne de connu pour recevoir : on se réannonce (au plus toutes les 30 s).
  -- Cas typique : celui qui reçoit a coché l'option après notre annonce de connexion.
  if next(destinataires) == nil and time() - derniereRelance >= 30 then
    derniereRelance = time()
    annoncer()
  end
  for nom in pairs(destinataires) do
    if enLigne(nom) then
      for _, e in ipairs(db.erreurs) do
        if not e.envoyee and (db.toutes or estANous(e.addon)) then
          envoyerErreur(e, nom)
          e.envoyee = true
        end
      end
    else
      destinataires[nom] = nil
    end
  end
end

-- Sur demande : tout ce qu'on a, envoyé ou pas, plus les infos et le journal.
local function envoyerTout(cible)
  posterLong("I", { infosPerso() }, cible)
  for _, e in ipairs(db.erreurs) do envoyerErreur(e, cible) end
  local lignes = {}
  for i = math.min(#db.journal, 40), 1, -1 do
    local j = db.journal[i]
    lignes[#lignes + 1] = date("%d/%m %H:%M", j.heure) .. " [" .. j.addon .. "] " .. j.texte
  end
  if #lignes > 0 then posterLong("J", { table.concat(lignes, "\n") }, cible) end
end

-- Annonce : « R » = je reçois, « S » = j'envoie. Dans le groupe et la guilde.
annoncer = function()
  if not db or not db.actif then return end
  local message = db.recevoir and "R" or (db.envoyer and "S")
  if not message then return end
  if IsInRaid() then poster(message, "RAID") elseif IsInGroup() then poster(message, "PARTY") end
  if IsInGuild() then poster(message, "GUILD") end
end

-- ---------------------------------------------------------------------------
-- Réception
-- ---------------------------------------------------------------------------

local recoller = ns.nouveauRecolleur()
local rafraichir -- défini avec le panneau

local function dossierDe(nom)
  db.recues[nom] = db.recues[nom] or { erreurs = {} }
  return db.recues[nom]
end

local function surTexteLong(nom, id, champs)
  local genre = id:sub(1, 1)
  local dossier = dossierDe(nom)
  if genre == "E" then
    local e, nouvelle = ns.ranger(dossier.erreurs, {
      addon = champs[1], version = champs[2], genre = champs[3], nombre = tonumber(champs[4]) or 1,
      premiere = tonumber(champs[5]), derniere = tonumber(champs[6]), message = champs[7], pile = champs[8],
      recue = time(),
    }, MAX_RECUES)
    e.envoyee = nil
    if nouvelle and db.annoncer then
      ns.reglages.dire("erreur reçue de |cffffffff" .. nom .. "|r (" .. tostring(champs[1]) .. ") : /re pour la voir.")
    end
  elseif genre == "I" then
    dossier.infos, dossier.majInfos = champs[1], time()
  elseif genre == "J" then
    dossier.journal, dossier.majJournal = champs[1], time()
  end
  if rafraichir then rafraichir() end
end

local function surMessage(prefixe, texte, canal, auteur)
  if prefixe ~= PREFIXE or not db or not db.actif then return end
  if estSecret(texte) or estSecret(auteur) then return end
  local nom = Ambiguate(auteur, "none")
  if nom == UnitName("player") then return end
  if texte == "R" then
    -- Un joueur qui reçoit vient d'arriver : on lui dit qu'on existe, puis on envoie.
    destinataires[nom] = true
    if db.envoyer and canal ~= "WHISPER" then poster("S", "WHISPER", nom) end
    C_Timer.After(1, envoyerEnAttente)
  elseif texte == "S" then
    -- Un joueur qui envoie : s'il ne nous connaît pas encore, on se présente.
    if db.recevoir and canal ~= "WHISPER" then poster("R", "WHISPER", nom) end
  elseif texte == "D" then
    if destinataires[nom] and db.envoyer then envoyerTout(nom) end
  elseif texte:sub(1, 2) == "M\t" and db.recevoir then
    local id, rang, total, morceau = texte:match("^M\t([^\t]+)\t(%d+)\t(%d+)\t(.*)$")
    if not id then return end
    local entier = recoller(nom, id, tonumber(rang), tonumber(total), morceau)
    if entier then surTexteLong(nom, id, ns.decoder(entier)) end
  end
end

-- ---------------------------------------------------------------------------
-- Le panneau : tout le texte dans une zone que l'on peut copier (Ctrl+A, Ctrl+C).
-- ---------------------------------------------------------------------------

local panneau = CreateFrame("Frame", "RapportErreursPanneau", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
panneau:SetSize(620, 460)
panneau:SetPoint("CENTER")
panneau:SetMovable(true)
panneau:EnableMouse(true)
panneau:RegisterForDrag("LeftButton")
panneau:SetScript("OnDragStart", panneau.StartMoving)
panneau:SetScript("OnDragStop", panneau.StopMovingOrSizing)
panneau:SetFrameStrata("DIALOG")
panneau:Hide()
tinsert(UISpecialFrames, "RapportErreursPanneau")
ns.habiller(panneau, { titre = "Rapport d'erreurs", fermer = true })

local defile = CreateFrame("ScrollFrame", nil, panneau, "UIPanelScrollFrameTemplate")
defile:SetPoint("TOPLEFT", 12, -30)
defile:SetPoint("BOTTOMRIGHT", -32, 12)
local zone = CreateFrame("EditBox", nil, defile)
zone:SetMultiLine(true)
zone:SetAutoFocus(false)
zone:SetFontObject(ChatFontNormal)
zone:SetWidth(570)
zone:SetScript("OnEscapePressed", function() panneau:Hide() end)
local texteAffiche = ""
zone:SetScript("OnTextChanged", function(self, parUtilisateur)
  if parUtilisateur then self:SetText(texteAffiche) end -- on peut sélectionner et copier, pas modifier
end)
defile:SetScrollChild(zone)

local function heure(t) return t and date("%d/%m %H:%M", t) or "?" end

local function texteErreurs(liste, lignes)
  for _, e in ipairs(liste) do
    lignes[#lignes + 1] = string.format("-- %s ×%d  %s %s  (%s)", heure(e.derniere), e.nombre or 1,
      tostring(e.addon), tostring(e.version), tostring(e.genre))
    lignes[#lignes + 1] = e.message or ""
    if e.pile and e.pile ~= "" then lignes[#lignes + 1] = e.pile end
    lignes[#lignes + 1] = ""
  end
end

rafraichir = function()
  if not panneau:IsShown() or not db then return end
  local l = {}
  l[#l + 1] = "=== Mes erreurs (" .. #db.erreurs .. ") ==="
  if #db.erreurs == 0 then l[#l + 1] = "Aucune." end
  texteErreurs(db.erreurs, l)
  for nom, d in pairs(db.recues) do
    l[#l + 1] = "=== Reçues de " .. nom .. " (" .. #d.erreurs .. ") ==="
    if d.infos then l[#l + 1] = d.infos end
    texteErreurs(d.erreurs, l)
    if d.journal then l[#l + 1] = "Journal de " .. nom .. " :\n" .. d.journal .. "\n" end
  end
  if #db.journal > 0 then
    l[#l + 1] = "=== Mon journal (20 dernières lignes) ==="
    for i = 1, math.min(20, #db.journal) do
      local j = db.journal[i]
      l[#l + 1] = heure(j.heure) .. " [" .. j.addon .. "] " .. j.texte
    end
  end
  texteAffiche = table.concat(l, "\n")
  zone:SetText(texteAffiche)
end
panneau:SetScript("OnShow", rafraichir)

local function basculerPanneau() panneau:SetShown(not panneau:IsShown()) end

-- ---------------------------------------------------------------------------
-- Les actions : partagées par les boutons de la fenêtre et les commandes /re.
-- ---------------------------------------------------------------------------

local function erreurDEssai()
  ns.reglages.dire("erreur d'essai : elle doit apparaître dans /re (et chez celui qui reçoit).")
  C_Timer.After(0.1, function() error("erreur d'essai (/re test)") end)
end

-- Où en est l'envoi, puis on se réannonce.
local function etat()
  local r = ns.reglages
  r.dire(string.format("envoyer : %s, recevoir : %s, groupe : %s.", db.envoyer and "oui" or "non",
    db.recevoir and "oui" or "non", IsInGroup() and "oui" or "non"))
  r.dire((ns.texteEtat(destinataires, ns.compterEnAttente(db.erreurs)):gsub("\n", " ; ")) .. ".")
  annoncer()
end

local function demanderRapport(arg)
  local r = ns.reglages
  arg = strtrim(arg or "")
  if arg == "" then return r.dire("écris d'abord le nom du joueur.") end
  if not db.recevoir then
    return r.dire("coche d'abord « Recevoir les erreurs des autres » dans les réglages.")
  end
  local nom = arg:sub(1, 1):upper() .. arg:sub(2)
  poster("R", "WHISPER", nom)
  C_Timer.After(1, function() poster("D", "WHISPER", nom) end)
  r.dire("demande envoyée à " .. nom .. " ; son rapport arrive dans /re.")
end

local function toutEffacer()
  wipe(db.erreurs); wipe(db.journal); wipe(db.recues)
  ns.reglages.dire("tout est effacé.")
  rafraichir()
  if ns.reglages.majFenetre then ns.reglages.majFenetre() end
end

if StaticPopupDialogs then
  StaticPopupDialogs["RAPPORTERREURS_EFFACER"] = {
    text = "Rapport d'erreurs : effacer toutes tes erreurs, ton journal et les rapports reçus ?\nCe ne peut pas être annulé.",
    button1 = YES or "Oui", button2 = NO or "Non",
    OnAccept = toutEffacer,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  }
end

-- ---------------------------------------------------------------------------
-- Réglages (Reglages.lua)
-- ---------------------------------------------------------------------------

ns.reglages = ns.creerReglages({
  titre = "Rapport d'erreurs",
  icone = "Interface\\Icons\\INV_Misc_Note_02",
  nomDB = "RapportErreursDB",
  defauts = DEFAUTS,
  ouvrirHub = basculerPanneau, texteHub = "Voir le rapport",
  boutons = {
    { texte = "Envoyer une erreur d'essai", largeur = 170,
      aide = "Fabrique une fausse erreur : elle doit apparaître dans le rapport et chez celui qui reçoit (comme /re test).",
      action = erreurDEssai },
    { texte = "Se réannoncer", largeur = 110,
      aide = "Dit à ton groupe et à ta guilde si tu envoies ou si tu reçois, et affiche où en est l'envoi (comme /re etat).",
      action = etat },
    { texte = "Tout effacer", largeur = 100,
      aide = "Efface tes erreurs, ton journal et les rapports reçus, après confirmation.",
      action = function() StaticPopup_Show("RAPPORTERREURS_EFFACER") end },
  },
  options = {
    { titre = "Rapport" },
    { cle = "actif", libelle = "Activer Rapport d'erreurs",
      aide = "Coupé : plus aucune erreur gardée, envoyée ni reçue, et le journal des addons n'écrit plus." },
    { titre = "Envoyer" },
    { cle = "envoyer", libelle = "Envoyer mes erreurs",
      aide = "À un joueur qui a coché « Recevoir », dès qu'il est dans ton groupe, ta guilde ou ta liste d'amis et en ligne." },
    { cle = "toutes", libelle = "Aussi les erreurs des autres addons", dependDe = "envoyer",
      aide = "Coupé : seules les erreurs des Addons de Valentin partent." },
    { titre = "Recevoir" },
    { cle = "recevoir", libelle = "Recevoir les erreurs des autres",
      aide = "Pour celui qui analyse les erreurs. Elles sont gardées par joueur, lisibles avec /re." },
    { cle = "annoncer", libelle = "Prévenir dans le chat à chaque erreur reçue", dependDe = "recevoir",
      aide = "Un message avec le nom du joueur et de l'addon en cause, à la première fois qu'une erreur arrive." },
    { titre = "Icône" },
    { cle = "minimap", libelle = "Icône à part autour de la minimap",
      aide = "En plus de l'icône commune des addons de Valentin." },
  },
  ongletContenu = "En direct",
  contenu = function(f, y, r)
    local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, y - 6)
    t:SetText("En direct")
    y = y - 30
    local ligne = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ligne:SetPoint("TOPLEFT", 20, y)
    ligne:SetWidth(380)
    ligne:SetJustifyH("LEFT")
    -- Trois lignes au plus : une longue liste de noms ne recouvre pas la suite.
    if ligne.SetMaxLines then ligne:SetMaxLines(3) end
    y = y - 50

    local etiquette = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    etiquette:SetPoint("TOPLEFT", 20, y)
    etiquette:SetText("Demander le rapport d'un joueur")
    y = y - 20
    local champ = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    champ:SetSize(150, 20)
    champ:SetPoint("TOPLEFT", 26, y)
    champ:SetAutoFocus(false)
    champ:SetMaxLetters(24)
    local demander = ns.creerBouton(f, "Demander son rapport",
      "Lui demande tout ce qu'il a gardé (comme /re demander). Il faut avoir coché « Recevoir ».",
      function() demanderRapport(champ:GetText()) end, 170)
    demander:SetPoint("LEFT", champ, "RIGHT", 10, 0)
    champ:SetScript("OnEnterPressed", function(self) self:ClearFocus(); demanderRapport(self:GetText()) end)
    champ:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    y = y - 30

    local function maj()
      if not db then return end
      ligne:SetText(ns.texteEtat(destinataires, ns.compterEnAttente(db.erreurs)))
      if db.recevoir and db.actif then demander:Enable() else demander:Disable() end
    end
    -- L'état bouge sans cesse (un destinataire arrive, une erreur part) : mise à jour chaque seconde.
    local depuis = 0
    f:SetScript("OnUpdate", function(_, dt)
      depuis = depuis + dt
      if depuis >= 1 then depuis = 0; maj() end
    end)
    return y, maj
  end,
  astuce = "Le rapport : /re, le bouton en haut ou Maj+clic dans l'icône commune.",
  auChargement = function(d)
    db = d
    dernierRecevoir = d.recevoir
    -- Réglage « recevoir » coché ou décoché : on prévient les autres tout de suite.
    C_Timer.After(5, annoncer)
  end,
  surChangement = function(d)
    -- « Recevoir » coché ou décoché en jeu : on prévient les autres tout de suite,
    -- sans attendre la prochaine connexion.
    if d.recevoir ~= dernierRecevoir then
      dernierRecevoir = d.recevoir
      annoncer()
    end
  end,
})

-- ---------------------------------------------------------------------------
-- Événements et commande /re
-- ---------------------------------------------------------------------------

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
  C_ChatInfo.RegisterAddonMessagePrefix(PREFIXE)
end

local ecouteur = CreateFrame("Frame")
for _, ev in ipairs({ "CHAT_MSG_ADDON", "GROUP_JOINED", "PLAYER_ENTERING_WORLD",
  "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "LUA_WARNING" }) do
  pcall(ecouteur.RegisterEvent, ecouteur, ev) -- un événement absent d'une version ne bloque pas les autres
end
ecouteur:SetScript("OnEvent", function(_, evenement, ...)
  if evenement == "CHAT_MSG_ADDON" then
    surMessage(...)
  elseif evenement == "ADDON_ACTION_BLOCKED" or evenement == "ADDON_ACTION_FORBIDDEN" then
    local addon, fonction = ...
    noter("[" .. evenement .. "] Interface/AddOns/" .. tostring(addon) .. "/ a appelé la fonction protégée "
      .. tostring(fonction), debugstack and debugstack(2) or "", "bloqué")
  elseif evenement == "LUA_WARNING" then
    local a, b = ...
    noter(b or a, "", "avertissement")
  else
    C_Timer.After(3, annoncer)
  end
end)

SLASH_RAPPORTERREURS1 = "/re"
SLASH_RAPPORTERREURS2 = "/rapporterreurs"
SlashCmdList.RAPPORTERREURS = function(message)
  local cmd, arg = strtrim(message or ""):match("^(%S*)%s*(.-)$")
  cmd = (cmd or ""):lower()
  local r = ns.reglages
  if cmd == "" then
    basculerPanneau()
  elseif cmd == "options" or cmd == "reglages" then
    r.ouvrir()
  elseif cmd == "demander" and arg ~= "" then
    demanderRapport(arg)
  elseif cmd == "test" then
    erreurDEssai()
  elseif cmd == "etat" or cmd == "état" then
    etat()
  elseif cmd == "effacer" then
    toutEffacer()
  elseif cmd == "on" or cmd == "off" then
    if (cmd == "on") ~= (db.actif and true or false) then r.basculer() end
  elseif not r.basculerOption(cmd) then
    r.dire("/re : le panneau   /re options   /re demander <joueur>   /re test   /re etat   /re effacer")
  end
end
