-- ============================================================================
-- Sacs rangés : les objets utiles aux quêtes.
--
-- Le jeu ne marque « objet de quête » que les objets faits pour une quête (classe 12).
-- Une étoffe, une herbe ou un objet divers demandé par une quête n'a aucune marque.
-- Ce fichier le dit :
--   - dans la bulle de l'objet : « Quête : titre (3/10) » pour les quêtes de ton journal,
--     et, avec l'addon Quêtes disponibles (WoW Forever), les quêtes que tu peux prendre
--     qui demandent cet objet ;
--   - sur la case du sac par catégories : un compteur « 3/10 », un « ! » ou une bordure ;
--   - en option, l'objet va dans la section Quête tant qu'il sert à une quête du journal.
--
-- Comment on sait qu'un objet sert : le journal donne le texte de chaque objectif,
-- « Étoffe de lin : 3/10 » (ou « 3/10 Étoffe de lin »). On enlève le compte et on compare
-- au nom de l'objet, dans la langue du jeu des deux côtés.
--
-- Le fichier a deux parties : la logique pure (testée hors jeu, tests/SacsRanges_simu.lua),
-- puis ce qui parle au jeu.
-- ============================================================================

local _, ns = ...

-- ---------------------------------------------------------------------------
-- Logique pure
-- ---------------------------------------------------------------------------

-- Le nom d'un objectif sans son compte, en minuscules : « Étoffe de lin : 3/10 » -> « étoffe de lin ».
-- Les lettres accentuées ne passent pas par lower() en Lua 5.1 : les deux côtés gardent les mêmes,
-- puisqu'ils viennent du même jeu.
function ns.cleNomQuete(texte)
  if type(texte) ~= "string" then return nil end
  -- L'espace insécable (\194\160) du français, avant « : », compte comme un espace.
  local nom = texte:gsub("\194\160", " "):gsub("%d+%s*/%s*%d+", "", 1)
  nom = nom:gsub("^[%s%-:]+", ""):gsub("[%s:%.]+$", "")
  if nom == "" then return nil end
  return nom:lower()
end

-- L'index des objectifs « objet » du journal : { [clé du nom] = { { id, titre, fait, total, fini } } }.
-- journal : { { id, titre, objectifs = { { texte, type, fait, total, fini } } } }.
-- Un objectif d'un autre genre (monstre, objet du décor, réputation) n'y est pas ; un genre inconnu y est.
function ns.indexObjetsJournal(journal)
  local index = {}
  for _, q in ipairs(type(journal) == "table" and journal or {}) do
    for _, o in ipairs(type(q.objectifs) == "table" and q.objectifs or {}) do
      if o.type == nil or o.type == "item" then
        local cle = ns.cleNomQuete(o.texte)
        if cle then
          local a, b = tostring(o.texte):match("(%d+)%s*/%s*(%d+)")
          local fait, total = tonumber(o.fait) or tonumber(a), tonumber(o.total) or tonumber(b)
          index[cle] = index[cle] or {}
          local l = index[cle]
          l[#l + 1] = { id = q.id, titre = q.titre or ("Quête " .. tostring(q.id)), fait = fait, total = total,
                        fini = o.fini == true or (fait ~= nil and total ~= nil and total > 0 and fait >= total) }
        end
      end
    end
  end
  return index
end

-- Les quêtes du journal qui demandent l'objet « nom » (nom dans la langue du jeu), par nom exact.
-- Pas de recherche approximative : « Peau de loup » trouverait l'objectif « Peau de loup épaisse »,
-- un autre objet (constat de relecture du 18/11).
function ns.quetesJournalPour(nom, index)
  if type(nom) ~= "string" or nom == "" or type(index) ~= "table" then return {} end
  return index[ns.cleNomQuete(nom) or ""] or {}
end

-- Les lignes à ajouter dans la bulle : { { texte, r, g, b } }.
--   journal : les quêtes du journal (ns.quetesJournalPour) ; prendre : { { titre, niveau, r, g, b } } (Quêtes disponibles) ;
--   detail : une ligne par quête ; maj : la touche Maj est enfoncée (montre le détail même sans « detail »).
local JAUNE, VERT, BLEU, GRIS = { 1, 0.82, 0 }, { 0.12, 1, 0 }, { 0.56, 0.72, 1 }, { 0.6, 0.6, 0.6 }
function ns.lignesBulleQuetes(journal, prendre, detail, maj)
  journal, prendre = journal or {}, prendre or {}
  local lignes = {}
  local function ligne(texte, c) lignes[#lignes + 1] = { texte = texte, r = c[1], g = c[2], b = c[3] } end
  if #journal == 0 and #prendre == 0 then return lignes end
  if not detail and not maj then
    local n = #journal + #prendre
    if #journal > 0 then
      ligne("Sert à " .. n .. " quête" .. (n > 1 and "s" or "") ..
        (#prendre > 0 and (" (dont " .. #prendre .. " à prendre)") or ""), JAUNE)
    else
      ligne("Demandé par " .. n .. " quête" .. (n > 1 and "s" or "") .. " à prendre", BLEU)
    end
    ligne("Maj : voir les quêtes", GRIS)
    return lignes
  end
  for _, q in ipairs(journal) do
    local compte = (q.fait and q.total and q.total > 0) and (" (" .. q.fait .. "/" .. q.total .. ")") or ""
    ligne("Quête : " .. tostring(q.titre) .. compte, q.fini and VERT or JAUNE)
  end
  if #prendre > 0 then
    ligne(#prendre > 1 and ("Demandé par " .. #prendre .. " quêtes à prendre :") or "Demandé par 1 quête à prendre :", BLEU)
    local MAX = 5
    for i, q in ipairs(prendre) do
      if i > MAX then ligne("  et " .. (#prendre - MAX) .. " autre" .. (#prendre - MAX > 1 and "s" or ""), BLEU) break end
      local niv = (tonumber(q.niveau) or 0) > 0 and ("[" .. q.niveau .. "] ") or ""
      ligne("  " .. niv .. tostring(q.titre), q.r and { q.r, q.g, q.b } or BLEU)
    end
  end
  return lignes
end

-- La marque d'une case : { texte, r, g, b, bord } ou nil. forme : 1 compteur, 2 « ! », 3 bordure.
-- Jaune pour une quête du journal (elle passe avant), bleue pour une quête seulement à prendre.
function ns.marqueQuete(journal, prendre, forme)
  journal, prendre = journal or {}, prendre or {}
  if #journal == 0 and #prendre == 0 then return nil end
  local c = #journal > 0 and JAUNE or BLEU
  forme = tonumber(forme) or 1
  if forme == 3 then return { bord = true, r = c[1], g = c[2], b = c[3] } end
  if forme == 2 then return { texte = #journal > 0 and "!" or "?", r = c[1], g = c[2], b = c[3] } end
  if #journal > 0 then
    -- La première quête pas finie donne le compte ; toutes finies : la première.
    local q = journal[1]
    for _, x in ipairs(journal) do if not x.fini then q = x break end end
    if q.fait and q.total and q.total > 0 then
      local fini = true
      for _, x in ipairs(journal) do if not x.fini then fini = false end end
      local v = fini and VERT or JAUNE
      return { texte = q.fait .. "/" .. q.total, r = v[1], g = v[2], b = v[3] }
    end
    return { texte = "!", r = c[1], g = c[2], b = c[3] }
  end
  return { texte = "+" .. #prendre, r = c[1], g = c[2], b = c[3] }
end

-- La phrase « pourquoi c'est rangé ici » d'un objet rangé dans Quête parce qu'il sert.
function ns.texteRangementQuete(journal)
  if not journal or #journal == 0 then return nil end
  if #journal == 1 then return "sert à la quête « " .. tostring(journal[1].titre) .. " »" end
  return "sert à " .. #journal .. " quêtes de ton journal"
end

-- ---------------------------------------------------------------------------
-- Partie jeu (rien ci-dessous ne tourne hors jeu)
-- ---------------------------------------------------------------------------

if not CreateFrame then return end

local function lisible(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

local function sur(f, ...)
  if type(f) ~= "function" then return end
  local ok, a, b, c, d = pcall(f, ...)
  if ok then return a, b, c, d end
end

-- L'index du journal, refait au plus une fois par seconde (un butin change un compte), ou dès qu'une quête
-- est prise, rendue ou mise à jour.
local index, indexTemps = nil, -10
local function lireIndex()
  local t = (GetTime and GetTime()) or 0
  if index and t - indexTemps < 1 then return index end
  local ql = C_QuestLog
  local journal = {}
  if type(ql) == "table" and type(ql.GetNumQuestLogEntries) == "function" and type(ql.GetInfo) == "function" then
    local n = lisible(sur(ql.GetNumQuestLogEntries))
    for i = 1, math.min(tonumber(n) or 0, 100) do
      local info = sur(ql.GetInfo, i)
      if type(info) == "table" and not lisible(info.isHeader) then
        local id = lisible(info.questID)
        if type(id) == "number" and id > 0 then
          local brut = type(ql.GetQuestObjectives) == "function" and sur(ql.GetQuestObjectives, id) or nil
          local objectifs = {}
          for _, o in ipairs(type(brut) == "table" and brut or {}) do
            if type(o) == "table" then
              objectifs[#objectifs + 1] = { texte = lisible(o.text), type = lisible(o.type), fini = lisible(o.finished) == true,
                fait = tonumber((lisible(o.numFulfilled))), total = tonumber((lisible(o.numRequired))) }
            end
          end
          local titre = lisible(info.title)
          journal[#journal + 1] = { id = id, titre = type(titre) == "string" and titre ~= "" and titre or nil, objectifs = objectifs }
        end
      end
    end
  end
  index, indexTemps = ns.indexObjetsJournal(journal), t
  return index
end
function ns.oublierIndexQuetes() index = nil end

local function nomObjet(id)
  if not id then return nil end
  local nom
  if C_Item and C_Item.GetItemInfo then nom = sur(C_Item.GetItemInfo, id) else nom = sur(GetItemInfo, id) end
  if type(nom) ~= "string" and C_Item and C_Item.GetItemNameByID then nom = sur(C_Item.GetItemNameByID, id) end
  return type(nom) == "string" and nom or nil
end

-- Les quêtes du journal qui demandent cet objet (sans regarder les réglages : sert aussi aux autres addons).
function ns.quetesJournalObjet(id, nom)
  nom = nom or nomObjet(id)
  if not nom then return {} end
  return ns.quetesJournalPour(nom, lireIndex())
end

-- Ce que montrent la bulle et la case, selon les réglages : journal, prendre.
function ns.quetesObjet(id, nom)
  local db = ns.db
  if not db or db.actif == false or not id then return {}, {} end
  local journal, prendre = {}, {}
  if db.quetesBulles ~= false or db.quetesMarque ~= false or db.quetesSection then
    journal = ns.quetesJournalObjet(id, nom)
  end
  if db.quetesPrendre ~= false and type(QuetesDispo_QuetesPourObjet) == "function" then
    local ok, l = pcall(QuetesDispo_QuetesPourObjet, id)
    if ok and type(l) == "table" then prendre = l end
  end
  return journal, prendre
end

-- Pour les autres addons (Marchand auto, Butin rapide) : la première quête du journal qui demande cet objet,
-- ou nil. nom est facultatif.
function SacsRanges_ObjetSertQuete(id, nom)
  local l = ns.quetesJournalObjet(id, nom)
  return l[1] and l[1].titre or nil, #l
end

-- La bulle d'un objet, partout (sacs, banque, butin, marchand, lien dans la discussion).
local function idDeBulle(tip, data)
  local id = type(data) == "table" and lisible(data.id) or nil
  if type(id) == "number" then return id end
  if tip and tip.GetItem then
    local _, lien = tip:GetItem()
    lien = lisible(lien)
    if type(lien) == "string" then return tonumber(lien:match("item:(%d+)")) end
  end
  return nil
end

local function ajouterQuetes(tip, data)
  local db = ns.db
  if not db or db.actif == false or db.quetesBulles == false then return end
  if not tip or not tip.AddLine then return end
  local id = idDeBulle(tip, data)
  if not id then return end
  local journal, prendre = ns.quetesObjet(id)
  local maj = IsShiftKeyDown and IsShiftKeyDown() or false
  local lignes = ns.lignesBulleQuetes(journal, prendre, db.quetesDetail ~= false, maj)
  if #lignes == 0 then return end
  tip:AddLine(" ")
  for _, l in ipairs(lignes) do tip:AddLine(l.texte, l.r, l.g, l.b, true) end
  if tip.Show then tip:Show() end
end
local function ajouterQuetesProtege(tip, data) pcall(ajouterQuetes, tip, data) end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ajouterQuetesProtege)
elseif GameTooltip and GameTooltip.HookScript then
  GameTooltip:HookScript("OnTooltipSetItem", ajouterQuetesProtege)
  if ItemRefTooltip and ItemRefTooltip.HookScript then ItemRefTooltip:HookScript("OnTooltipSetItem", ajouterQuetesProtege) end
end

-- La marque sur une case de la vue par catégories (appelée par Vue.lua à chaque remplissage).
function ns.marquerCase(b, id, nom)
  if not b then return end
  local m
  local db = ns.db
  if db and db.actif ~= false and db.quetesMarque ~= false and id then
    local journal, prendre = ns.quetesObjet(id, nom)
    m = ns.marqueQuete(journal, prendre, db.quetesForme)
  end
  if not m then
    if b.queteTexte then b.queteTexte:Hide() end
    if b.queteBord then b.queteBord:Hide() end
    return
  end
  if m.bord then
    if not b.queteBord then
      b.queteBord = b:CreateTexture(nil, "OVERLAY", nil, 6)
      b.queteBord:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
      b.queteBord:SetBlendMode("ADD")
      b.queteBord:SetPoint("CENTER")
      b.queteBord:SetSize((b:GetWidth() or 37) * 1.8, (b:GetHeight() or 37) * 1.8)
    end
    b.queteBord:SetVertexColor(m.r, m.g, m.b)
    b.queteBord:Show()
    if b.queteTexte then b.queteTexte:Hide() end
  else
    if not b.queteTexte then
      b.queteTexte = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
      b.queteTexte:SetPoint("TOPRIGHT", -2, -2)
    end
    b.queteTexte:SetText(m.texte)
    b.queteTexte:SetTextColor(m.r, m.g, m.b)
    b.queteTexte:Show()
    if b.queteBord then b.queteBord:Hide() end
  end
end

-- Le journal a changé : on relit, et la vue se redessine (un compte a bougé).
local ecouteur = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN" }) do
  pcall(ecouteur.RegisterEvent, ecouteur, e)
end
local prevu = false
ecouteur:SetScript("OnEvent", function()
  index = nil
  -- Seule la vue par catégories montre des marques ; la bulle relit le journal toute seule.
  if prevu or not (ns.db and ns.db.vueCategories) or not (C_Timer and C_Timer.After) then return end
  prevu = true
  C_Timer.After(0.3, function()
    prevu = false
    if ns.vueRafraichir then pcall(ns.vueRafraichir) end
  end)
end)
