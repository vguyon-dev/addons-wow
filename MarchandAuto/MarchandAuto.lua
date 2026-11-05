-- ============================================================================
-- Marchand auto : quand tu ouvres un marchand,
--  1. il vend tes objets gris (sauf ceux que tu as demandé de garder) ;
--  2. il répare ton équipement, avec la banque de guilde si tu le veux
--     et si la guilde te le permet, sinon avec ton or ;
--  3. il te dit ce que ça t'a rapporté et coûté.
-- Tout se règle dans une fenêtre (Reglages.lua) : icône de minimap, /ma, ou
-- Échap > Options > AddOns. Maintenir Maj en ouvrant le marchand = pause.
-- ============================================================================

local NOM_ADDON, ns = ...

local DEFAUTS = {
  actif = true,          -- interrupteur général
  vendreGris = true,     -- vendre les objets gris
  reparer = true,        -- réparer l'équipement
  banqueGuilde = true,   -- payer la réparation avec la banque de guilde si possible
  pauseTouches = true,   -- Maj, Ctrl ou Alt enfoncé en ouvrant le marchand = pause
  bilan = true,          -- écrire dans le chat ce qui a été vendu et réparé
  minimap = true,        -- icône autour de la minimap
  angleMinimap = 200,    -- position de l'icône autour de la minimap
  gardes = {},           -- [idObjet] = lien : gris à ne jamais vendre
}

local db

-- C_CurrencyInfo d'abord, avec un repli (règle du dépôt, voir le Carnet).
local function texteOr(cuivre)
  local f = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
  return f and f(cuivre) or (math.floor(cuivre / 10000) .. " po")
end

-- ---------------------------------------------------------------------------
-- Partie « logique pure », testée hors jeu (tests/MarchandAuto_simu.lua).
-- ---------------------------------------------------------------------------

-- Cet objet de sac est-il à vendre ? info : ce que renvoie
-- C_Container.GetContainerItemInfo (quality 0 = gris).
function ns.aVendre(info, gardes)
  if not info or info.quality ~= 0 then return false end
  if info.hasNoValue or info.isLocked then return false end
  return not (info.itemID and gardes[info.itemID])
end

-- Qui paie la réparation ? Renvoie "guilde", "perso" ou nil (rien à faire / pas assez d'or).
-- dispoGuilde : ce que la guilde te laisse retirer (-1 = sans limite), nil si pas permis.
function ns.payeur(cout, argent, dispoGuilde, banqueGuilde)
  if not cout or cout <= 0 then return nil end
  if banqueGuilde and dispoGuilde and (dispoGuilde == -1 or dispoGuilde >= cout) then
    return "guilde"
  end
  if argent >= cout then return "perso" end
  return nil
end

-- ---------------------------------------------------------------------------
-- Vente des gris
-- ---------------------------------------------------------------------------

local ouvert = false -- le marchand est-il encore ouvert ?
local DERNIER_SAC = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4

local function vendreGris()
  -- On liste d'abord, puis on vend un objet tous les dixièmes de seconde :
  -- tout vendre d'un coup fait rater des ventes au serveur.
  local liste, total = {}, 0
  for sac = 0, DERNIER_SAC do
    for case = 1, C_Container.GetContainerNumSlots(sac) do
      local info = C_Container.GetContainerItemInfo(sac, case)
      if ns.aVendre(info, db.gardes) then
        local prix = select(11, ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(info.hyperlink)) or 0
        total = total + prix * (info.stackCount or 1)
        liste[#liste + 1] = { sac, case }
      end
    end
  end
  if #liste == 0 then return end
  local i = 0
  local function suivant()
    i = i + 1
    if not ouvert or i > #liste then
      if db.bilan then
        ns.reglages.dire(string.format("%d objet(s) gris vendu(s) : %s", i - 1, texteOr(total)))
      end
      return
    end
    C_Container.UseContainerItem(liste[i][1], liste[i][2])
    C_Timer.After(0.1, suivant)
  end
  suivant()
end

-- ---------------------------------------------------------------------------
-- Réparation
-- ---------------------------------------------------------------------------

local function reparer()
  if not CanMerchantRepair() then return end
  local cout, possible = GetRepairAllCost()
  if not possible then return end
  local dispoGuilde
  if IsInGuild() and CanGuildBankRepair and CanGuildBankRepair() then
    dispoGuilde = GetGuildBankWithdrawMoney()
  end
  local qui = ns.payeur(cout, GetMoney(), dispoGuilde, db.banqueGuilde)
  if qui == "guilde" then
    RepairAllItems(true)
    if db.bilan then ns.reglages.dire("réparé avec la banque de guilde : " .. texteOr(cout)) end
  elseif qui == "perso" then
    RepairAllItems()
    if db.bilan then ns.reglages.dire("réparé : " .. texteOr(cout)) end
  elseif cout and cout > 0 then
    ns.reglages.dire("pas assez d'or pour tout réparer (" .. texteOr(cout) .. ").")
  end
end

-- ---------------------------------------------------------------------------
-- Réglages
-- ---------------------------------------------------------------------------

local function compter(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

ns.reglages = ns.creerReglages({
  titre = "Marchand auto",
  icone = "Interface\\Icons\\INV_Misc_Coin_02",
  nomDB = "MarchandAutoDB",
  defauts = DEFAUTS,
  options = {
    { titre = "Chez le marchand" },
    { cle = "actif", libelle = "Activer Marchand auto",
      aide = "Interrupteur général. Le clic droit sur l'icône fait la même chose." },
    { cle = "vendreGris", libelle = "Vendre les objets gris",
      aide = "Tous les gris de tes sacs, sauf ceux de ta liste « à garder »." },
    { cle = "reparer", libelle = "Réparer l'équipement",
      aide = "Seulement chez les marchands qui savent réparer (enclume dans leur fenêtre)." },
    { cle = "banqueGuilde", libelle = "Payer avec la banque de guilde",
      aide = "Si ta guilde te le permet et qu'il y a assez ; sinon avec ton or." },
    { cle = "pauseTouches", libelle = "Maj, Ctrl ou Alt met en pause",
      aide = "Garde une de ces touches enfoncée en ouvrant le marchand pour tout faire à la main." },
    { titre = "Affichage" },
    { cle = "bilan", libelle = "Écrire le bilan dans le chat",
      aide = "Ce que la vente a rapporté et ce que la réparation a coûté." },
    { cle = "minimap", libelle = "Icône autour de la minimap",
      aide = "Clic gauche : réglages. Clic droit : activer ou couper. Glisser : déplacer." },
  },
  contenu = function(fenetre, y, r)
    local t = fenetre:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, y - 6)
    t:SetText("Gris à garder")
    y = y - 32
    local compteur = fenetre:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    compteur:SetPoint("TOPLEFT", 20, y)
    y = y - 22
    local b = CreateFrame("Button", nil, fenetre, "UIPanelButtonTemplate")
    b:SetSize(160, 24)
    b:SetPoint("TOPLEFT", 16, y)
    b:SetText("Vider la liste")
    b:SetScript("OnClick", function() r.changer("gardes", {}); r.dire("plus aucun gris gardé.") end)
    y = y - 28
    return y, function(d) compteur:SetText("Objets gris gardés : " .. compter(d.gardes)) end
  end,
  astuce = "Garder un gris : tape /ma garder puis Maj+clic sur l'objet. Tout s'applique sans /reload.",
  auChargement = function(d) db = d end,
})

-- ---------------------------------------------------------------------------
-- Événements et commande /ma
-- ---------------------------------------------------------------------------

local ecouteur = CreateFrame("Frame")
ecouteur:RegisterEvent("MERCHANT_SHOW")
ecouteur:RegisterEvent("MERCHANT_CLOSED")
ecouteur:SetScript("OnEvent", function(_, evenement)
  if evenement == "MERCHANT_CLOSED" then ouvert = false return end
  ouvert = true
  if not db or not db.actif then return end
  if db.pauseTouches and (IsShiftKeyDown() or IsControlKeyDown() or IsAltKeyDown()) then return end
  if db.reparer then reparer() end
  if db.vendreGris then vendreGris() end
end)

SLASH_MARCHANDAUTO1 = "/ma"
SLASH_MARCHANDAUTO2 = "/marchandauto"
SlashCmdList.MARCHANDAUTO = function(texte)
  local cmd, reste = strtrim(texte or ""):match("^(%S*)%s*(.-)$")
  cmd = cmd:lower()
  local r = ns.reglages
  if cmd == "" or cmd == "options" or cmd == "reglages" then
    r.ouvrir()
  elseif cmd == "on" or cmd == "off" then
    if (cmd == "on") ~= (db.actif and true or false) then r.basculer() end
  elseif cmd == "garder" then
    local id = tonumber(reste:match("item:(%d+)") or reste)
    if not id then return r.dire("tape /ma garder puis Maj+clic sur l'objet gris.") end
    if db.gardes[id] then db.gardes[id] = nil else db.gardes[id] = reste end
    r.dire(reste .. (db.gardes[id] and " sera gardé." or " sera de nouveau vendu."))
    r.appliquer()
  elseif not r.basculerOption(cmd) then
    r.dire("/ma : ouvrir les réglages     /ma on, /ma off : activer ou couper")
    r.dire("/ma garder <objet> : ne jamais vendre ce gris (Maj+clic sur l'objet)")
  end
end
