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

local function toucheInteraction()
  local k = GetBindingKey and GetBindingKey("INTERACTTARGET")
  if not k or k == "" then return nil end
  -- GetBindingText traduit le code de la touche (« SHIFT-E » devient « Maj-E »,
  -- « BUTTON4 » un bouton de souris). Certaines touches (², <) sortent en « ? »
  -- avec la police du jeu : on garde alors le code brut.
  local texte = GetBindingText and GetBindingText(k, "KEY_") or k
  if not texte or texte == "" or texte:find("?", 1, true) then texte = k end
  return texte
end

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
  if key == "ESCAPE" then ns.reglages.dire("choix de la touche annulé.") return end
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

local function choisirTouche(apres)
  if InCombatLockdown() then ns.reglages.dire("|cffff4040pas en combat.|r") return end
  capture.apres = apres
  capture:Show()
  ns.reglages.dire("appuie sur la touche voulue pour récolter (Échap pour annuler).")
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
  if not db.actif or not db.filonPasFini or not GetLootSourceInfo then return end
  local g = GetLootSourceInfo(1)
  if not estSecret(g) and g and g:find("^GameObject") then objetRecolte = g end
end

local function verifierFilon(essai)
  local g = objetRecolte
  if not g or UnitCastingInfo("player") or UnitChannelInfo("player") then return end
  if guidSur("softinteract") ~= g then return end -- l'objet a disparu : récolte finie
  local k = toucheInteraction()
  local texte = "Pas fini ! Appuie encore" .. (k and (" sur " .. k) or "") .. " pour finir la récolte."
  if RaidNotice_AddMessage and RaidWarningFrame then
    RaidNotice_AddMessage(RaidWarningFrame, texte, ChatTypeInfo and ChatTypeInfo.RAID_WARNING or { r = 1, g = 0.5, b = 0 })
  end
  PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "master")
  -- Un rappel 4 secondes plus tard si tu n'as toujours rien fait.
  if essai == 1 then C_Timer.After(4, function() verifierFilon(2) end) end
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
fenetreCourses:SetBackdrop({
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
fenetreCourses:SetBackdropColor(0, 0, 0, 0.75)
local titreCourses = fenetreCourses:CreateFontString(nil, "OVERLAY", "GameFontNormal")
titreCourses:SetPoint("TOPLEFT", 10, -8)
titreCourses:SetText("Liste de courses")
local fermer = CreateFrame("Button", nil, fenetreCourses, "UIPanelCloseButton")
fermer:SetSize(22, 22)
fermer:SetPoint("TOPRIGHT", -2, -2)
fermer:SetScript("OnClick", function() ns.reglages.changer("afficherCourses", false) end)
local lignes = {}

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
    { titre = "Pêche" },
    { cle = "pecheDoubleClic", libelle = "Double clic droit pour lancer la ligne",
      aide = "Seulement en mode pêche. Pour ferrer : clic droit sur le bouchon." },
    { cle = "pecheAuto", libelle = "Mode pêche dès que tu pêches toi-même",
      aide = "Il s'arrête seul après 60 secondes sans pêcher, ou en combat." },
    { cle = "pecheSon", libelle = "Bien entendre le bouchon",
      aide = "En mode pêche : effets sonores à fond, musique et ambiance coupées." },
    { titre = "Récolte" },
    { cle = "interaction", libelle = "Une touche pour récolter",
      aide = "« Interagir avec la cible » vise seule filon, herbe ou bouchon. Appuie autant de fois que le filon le demande." },
    { cle = "ramassage", libelle = "Ramassage automatique du butin",
      aide = "Le butin va directement dans tes sacs." },
    { cle = "reperage", libelle = "Remettre le repérage des minerais et herbes",
      aide = "Après une mort ou une reconnexion, sur la minimap." },
    { cle = "filonPasFini", libelle = "Prévenir quand un filon n'est pas fini",
      aide = "Message et son s'il reste des coups à donner, pour qu'un autre joueur ne le finisse pas." },
    { titre = "Artisanat" },
    { cle = "afficherCourses", libelle = "Afficher la liste de courses",
      aide = "Ajouter une recette : /mt courses 5 puis Maj+clic sur la recette." },
    { cle = "minimap", libelle = "Icône à part autour de la minimap",
      aide = "En plus de l'icône commune des addons de Valentin. Clic droit : activer ou couper." },
  },
  contenu = function(fenetre, y, r)
    local t = fenetre:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, y - 6)
    t:SetText("Touches et liste")
    y = y - 32
    local touche = fenetre:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    touche:SetPoint("TOPLEFT", 20, y - 5)
    touche:SetWidth(240)
    touche:SetJustifyH("LEFT")
    local maj -- fonction de mise à jour, définie plus bas
    local b0 = CreateFrame("Button", nil, fenetre, "UIPanelButtonTemplate")
    b0:SetSize(150, 24)
    b0:SetPoint("TOPLEFT", 254, y)
    b0:SetText("Choisir la touche")
    b0:SetScript("OnClick", function()
      b0:SetText("Appuie sur une touche…")
      choisirTouche(function() maj() end)
    end)
    y = y - 34
    local b1 = CreateFrame("Button", nil, fenetre, "UIPanelButtonTemplate")
    b1:SetSize(190, 24)
    b1:SetPoint("TOPLEFT", 16, y)
    b1:SetScript("OnClick", function() MetiersAuto_ModePeche(); r.appliquer() end)
    local b2 = CreateFrame("Button", nil, fenetre, "UIPanelButtonTemplate")
    b2:SetSize(190, 24)
    b2:SetPoint("TOPLEFT", 214, y)
    b2:SetText("Vider la liste de courses")
    b2:SetScript("OnClick", function() r.changer("courses", {}); r.dire("liste de courses vidée.") end)
    y = y - 28
    maj = function()
      local k = toucheInteraction()
      touche:SetText("Touche pour récolter : " .. (k and ("|cff00ff00" .. k .. "|r") or "|cffff4040aucune|r"))
      b0:SetText(k and "Changer la touche" or "Choisir la touche")
      b1:SetText(modePeche and "Arrêter le mode pêche" or "Démarrer le mode pêche")
    end
    return y, maj
  end,
  astuce = "Tout s'applique tout de suite, sans /reload. Commande : /mt.",
  auChargement = function(d)
    db = d
    -- Un mode pêche coupé par une déconnexion : on remet le son d'avant.
    sonNormal()
    if db.positionCourses then
      local p = db.positionCourses
      fenetreCourses:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
      fenetreCourses:SetPoint("RIGHT", UIParent, "RIGHT", -60, 80)
    end
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
  end
end
