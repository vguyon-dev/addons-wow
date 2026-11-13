-- ============================================================================
-- Confort : les petites corvées faites pour toi.
--   Accepter tout seul : les invocations et résurrections de ton groupe (jamais
--   en combat), les invitations de groupe de tes amis et de ta guilde.
--   Refuser tout seul : les duels (sauf ceux de tes amis), les chartes.
--   Écran : masquer les griffons de la barre d'action, masquer les dégâts
--   affichés sur ton personnage, éloigner la caméra au maximum, garder le
--   scintillement des objets de quête à ramasser (Forever).
-- Ce sont des réponses aux fenêtres du jeu, permises aux addons.
-- ============================================================================

local NOM_ADDON, ns = ...

local DEFAUTS = {
  actif = true,
  invocations = true,
  resurrections = true,
  invitations = true,
  duels = true,
  chartes = true,
  griffons = false,
  degatsSurMoi = false,
  camera = true,
  scintillement = true, -- objets de quête à ramasser : garder leur scintillement (Forever)
  avant = {},        -- réglages du jeu d'avant, remis quand on décoche
  minimap = false,
  angleMinimap = 340,
}

local db

-- ---------------------------------------------------------------------------
-- Partie « logique pure », testée hors jeu (tests/Confort_simu.lua).
-- ---------------------------------------------------------------------------

-- « Jack-Sacreforge » et « Jack » désignent le même joueur de ton royaume.
function ns.memeJoueur(a, b)
  if not a or not b then return false end
  local function court(n) return (tostring(n):match("^([^%-]+)") or n):lower() end
  return a:lower() == b:lower() or court(a) == court(b)
end

-- Faut-il accepter ? (qui = nom, liste = noms du groupe, enCombat)
function ns.accepterDuGroupe(qui, groupe, enCombat)
  if enCombat or not qui then return false end
  for _, n in ipairs(groupe or {}) do
    if ns.memeJoueur(n, qui) then return true end
  end
  return false
end

-- Le scintillement des objets de quête à ramasser (Forever) tient à un réglage du jeu, que les préréglages
-- graphiques remettent à zéro : on le repose quand l'un de ces réglages change.
ns.CVAR_SCINTILLEMENT = "outlineModeShowLootEffectWhenDisabled"
local SURVEILLES = { graphicsquality = true, raidgraphicsquality = true, [ns.CVAR_SCINTILLEMENT:lower()] = true }
function ns.reglageSurveille(nom)
  return type(nom) == "string" and SURVEILLES[nom:lower()] == true
end

if not CreateFrame then return end -- hors jeu : la suite ne sert qu'en jeu

-- ---------------------------------------------------------------------------
-- Qui est qui
-- ---------------------------------------------------------------------------

local function nomsDuGroupe()
  local l = {}
  local n = GetNumGroupMembers and GetNumGroupMembers() or 0
  local prefixe = IsInRaid and IsInRaid() and "raid" or "party"
  for i = 1, n do
    local nom, royaume = UnitName(prefixe .. i)
    if nom then l[#l + 1] = royaume and royaume ~= "" and (nom .. "-" .. royaume) or nom end
  end
  return l
end

local function estAmi(nom, guid)
  if guid and C_FriendList and C_FriendList.IsFriend and C_FriendList.IsFriend(guid) then return true end
  if guid and C_BattleNet and C_BattleNet.GetAccountInfoByGUID and C_BattleNet.GetAccountInfoByGUID(guid) then return true end
  if nom and C_FriendList and C_FriendList.GetFriendInfo then
    local info = C_FriendList.GetFriendInfo(nom)
    if info then return true end
  end
  return false
end

local function estDeLaGuilde(guid)
  return guid and IsGuildMember and IsGuildMember(guid) or false
end

local function dire(t) ns.reglages.dire(t) end

-- ---------------------------------------------------------------------------
-- Réponses aux fenêtres du jeu
-- ---------------------------------------------------------------------------

local evenements = {}

function evenements.CONFIRM_SUMMON()
  if not db.invocations or not C_SummonInfo then return end
  local qui = C_SummonInfo.GetSummonConfirmSummoner()
  if not ns.accepterDuGroupe(qui, nomsDuGroupe(), InCombatLockdown()) then return end
  -- Un court délai : la fenêtre du jeu doit être prête.
  C_Timer.After(0.5, function()
    if C_SummonInfo.GetSummonConfirmTimeLeft and C_SummonInfo.GetSummonConfirmTimeLeft() > 0 and not InCombatLockdown() then
      C_SummonInfo.ConfirmSummon()
      StaticPopup_Hide("CONFIRM_SUMMON")
      dire("invocation de " .. qui .. " acceptée.")
    end
  end)
end

function evenements.RESURRECT_REQUEST(qui)
  if not db.resurrections then return end
  if not ns.accepterDuGroupe(qui, nomsDuGroupe(), InCombatLockdown()) then return end
  AcceptResurrect()
  for _, f in ipairs({ "RESURRECT", "RESURRECT_NO_SICKNESS", "RESURRECT_NO_TIMER" }) do StaticPopup_Hide(f) end
  dire("résurrection de " .. qui .. " acceptée.")
end

function evenements.PARTY_INVITE_REQUEST(qui, _, _, _, _, _, guid)
  if not db.invitations then return end
  if not (estAmi(qui, guid) or estDeLaGuilde(guid)) then return end
  AcceptGroup()
  StaticPopup_Hide("PARTY_INVITE")
  dire("invitation de " .. tostring(qui) .. " acceptée.")
end

function evenements.DUEL_REQUESTED(qui)
  if not db.duels or estAmi(qui) then return end
  CancelDuel()
  StaticPopup_Hide("DUEL_REQUESTED")
  dire("duel de " .. tostring(qui) .. " refusé.")
end

function evenements.PETITION_SHOW()
  if not db.chartes then return end
  -- On ne ferme que la charte qu'on te tend, pas celle que tu fais signer.
  if CanSignPetition and CanSignPetition() then
    ClosePetition()
    dire("charte refusée.")
  end
end

-- ---------------------------------------------------------------------------
-- L'écran (réglages du jeu, gardés puis remis comme avant)
-- ---------------------------------------------------------------------------

local function cvar(nom, valeur, actif)
  if not C_CVar or not C_CVar.GetCVar or InCombatLockdown() then return end
  local ok, actuel = pcall(C_CVar.GetCVar, nom)
  if not ok or actuel == nil then return end -- ce réglage n'existe pas sur cette version du jeu
  if actif then
    if actuel == valeur then return end
    if db.avant[nom] == nil then db.avant[nom] = C_CVar.GetCVar(nom) end
    C_CVar.SetCVar(nom, valeur)
  elseif db.avant[nom] ~= nil then
    C_CVar.SetCVar(nom, db.avant[nom])
    db.avant[nom] = nil
  end
end

local function griffons(cacher)
  local barres = { MainMenuBar, MainActionBar }
  for _, b in ipairs(barres) do
    local fins = b and b.EndCaps
    if fins then fins:SetShown(not cacher) end
  end
  for _, nom in ipairs({ "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap" }) do
    if _G[nom] then _G[nom]:SetShown(not cacher) end
  end
end

local function appliquerEcran()
  local a = db.actif
  cvar("cameraDistanceMaxZoomFactor", "2.6", a and db.camera)
  cvar("enableFloatingCombatText", "0", a and db.degatsSurMoi)
  local avait = db.avant[ns.CVAR_SCINTILLEMENT] ~= nil
  cvar(ns.CVAR_SCINTILLEMENT, "1", a and db.scintillement)
  if avait and db.avant[ns.CVAR_SCINTILLEMENT] == nil and not InCombatLockdown() then
    ns.reglages.dire("scintillement des objets de quête coupé : il disparaît au prochain lancement du jeu (un /reload ne suffit pas).")
  end
  if not InCombatLockdown() then griffons(a and db.griffons) end
end

-- ---------------------------------------------------------------------------
-- Réglages
-- ---------------------------------------------------------------------------

ns.reglages = ns.creerReglages({
  titre = "Confort",
  icone = "Interface\\Icons\\Spell_Nature_Sleep", -- l'oreiller (INV_Misc_Pillow_01) ne s'affichait pas sur Forever
  nomDB = "ConfortDB",
  defauts = DEFAUTS,
  options = {
    { titre = "Confort" },
    { cle = "actif", libelle = "Activer Confort", aide = "Les petites corvées faites pour toi, case par case." },
    { titre = "Accepter tout seul" },
    { cle = "invocations", libelle = "Les invocations de ton groupe", aide = "Jamais en combat. Un message dit qui t'a invoqué." },
    { cle = "resurrections", libelle = "Les résurrections de ton groupe", aide = "Jamais en combat." },
    { cle = "invitations", libelle = "Les invitations de groupe de tes amis et de ta guilde", aide = "Jamais celles d'un inconnu." },
    { titre = "Refuser tout seul" },
    { cle = "duels", libelle = "Les duels", aide = "Sauf ceux de tes amis." },
    { cle = "chartes", libelle = "Les chartes de guilde et d'arène qu'on te tend" },
    { titre = "Écran" },
    { cle = "griffons", libelle = "Masquer les griffons de la barre d'action" },
    { cle = "degatsSurMoi", libelle = "Masquer les dégâts affichés sur ton personnage",
      aide = "Réglage du jeu, remis comme avant si tu décoches." },
    { cle = "camera", libelle = "Caméra plus loin", aide = "La distance maximale que le jeu permet. Remise comme avant si tu décoches." },
    { cle = "scintillement", libelle = "Garder le scintillement des objets de quête",
      aide = "Sur Forever : les objets de quête à ramasser brillent, même après un changement de qualité graphique (le jeu coupe ce réglage tout seul). Ton réglage de contour n'est pas touché. Si tu décoches, l'effet part au prochain lancement du jeu." },
    { titre = "Icône" },
    { cle = "minimap", libelle = "Icône à part autour de la minimap",
      aide = "En plus de la ligne dans l'icône commune « Mes addons »." },
  },
  auChargement = function(d) db = d end,
  surChangement = function() appliquerEcran() end,
})

local ecouteur = CreateFrame("Frame")
for nom in pairs(evenements) do pcall(ecouteur.RegisterEvent, ecouteur, nom) end
ecouteur:RegisterEvent("PLAYER_ENTERING_WORLD")
ecouteur:RegisterEvent("PLAYER_REGEN_ENABLED")
pcall(ecouteur.RegisterEvent, ecouteur, "CVAR_UPDATE")
ecouteur:SetScript("OnEvent", function(_, evenement, ...)
  if not db then return end
  if evenement == "PLAYER_ENTERING_WORLD" or evenement == "PLAYER_REGEN_ENABLED" then appliquerEcran() return end
  if evenement == "CVAR_UPDATE" then
    -- Un préréglage graphique vient de changer : on repose le scintillement une seconde plus tard.
    if db.actif and db.scintillement and ns.reglageSurveille((...)) and C_Timer and C_Timer.After then
      C_Timer.After(1, function() if db and not InCombatLockdown() then appliquerEcran() end end)
    end
    return
  end
  if not db.actif then return end
  local f = evenements[evenement]
  if f then pcall(f, ...) end
end)

SLASH_CONFORT1 = "/confort"
SlashCmdList.CONFORT = function(message)
  local c = strtrim(message or ""):lower()
  if c == "on" or c == "off" then
    if (c == "on") ~= (db.actif and true or false) then ns.reglages.basculer() end
  elseif c == "" or c == "options" or c == "reglages" then ns.reglages.montrer()
  elseif not ns.reglages.basculerOption(c) then ns.reglages.dire("/confort : réglages ; /confort on | off") end
end
