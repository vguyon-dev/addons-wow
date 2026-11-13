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
--     Pêche facilitée en plus (chaque point a son interrupteur) : une seule touche
--     qui lance la ligne, ferre le bouchon et pose l'appât (jamais en combat) ; une
--     fenêtre « Pêche » (compétence, appât, prises, valeur) ; ramassage direct des
--     prises ; rachat d'appâts chez un marchand (coupé au départ, il dépense ton or).
--     Un appui ou un clic de toi = une action du jeu, comme pour tout le reste.
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
  pecheTouche = true,      -- une seule touche : lancer, ferrer, et poser l'appât si besoin (en mode pêche)
  touchePeche = nil,       -- la touche choisie, par exemple « F » ou « SHIFT-F » (aucune au départ)
  pecheAppat = true,       -- la touche pose d'abord l'appât quand la canne n'en a pas
  pecheFenetre = true,     -- la fenêtre « Pêche » s'ouvre et se ferme avec le mode pêche
  pecheRamasser = true,    -- ramasser tout de suite les prises (sans toucher au réglage général)
  rachatPalier = 0,        -- rachat d'appâts chez un marchand : 0 = aucun, 1 = 5, 2 = 10, 3 = 20
  ferrageAvant = nil,      -- réglages du jeu avant le ferrage, pour les remettre
  positionPeche = nil,     -- place de la fenêtre « Pêche »
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
-- Pêche facilitée : calculs purs (appâts, session, réglages du ferrage, touche)
-- ---------------------------------------------------------------------------

-- Les appâts connus, du meilleur au moins bon : numéro d'objet, bonus de compétence
-- de pêche, et compétence demandée pour s'en servir.
ns.APPATS = {
  { id = 6533, bonus = 100, requis = 100 },
  { id = 34861, bonus = 100, requis = 100 },
  { id = 6532, bonus = 75, requis = 100 },
  { id = 7307, bonus = 75, requis = 100 },
  { id = 6530, bonus = 50, requis = 50 },
  { id = 6811, bonus = 50, requis = 50 },
  { id = 6529, bonus = 25, requis = 0 },
}
local APPAT_PAR_ID = {}
for _, a in ipairs(ns.APPATS) do APPAT_PAR_ID[a.id] = a end
function ns.appatConnu(id) return APPAT_PAR_ID[id] end

-- Le bonus que le jeu annonce pour un appât posé sur la canne (numéro de l'enchantement).
ns.BONUS_APPAT_POSE = { [263] = 25, [264] = 50, [265] = 75, [266] = 100 }
function ns.bonusAppatPose(idEnchant) return ns.BONUS_APPAT_POSE[idEnchant] end

-- Les appâts des sacs, selon la compétence : renvoie ceux qu'on peut poser (le
-- meilleur d'abord) et ceux que la compétence ne permet pas encore.
-- compter(id) -> nombre dans les sacs.
function ns.appatsDesSacs(competence, compter)
  local utilisables, bloques = {}, {}
  competence = tonumber(competence) or 0
  for _, a in ipairs(ns.APPATS) do
    local n = compter(a.id) or 0
    if n > 0 then
      local ligne = { id = a.id, bonus = a.bonus, nombre = n, requis = a.requis }
      if competence >= a.requis then utilisables[#utilisables + 1] = ligne
      else bloques[#bloques + 1] = ligne end
    end
  end
  return utilisables, bloques
end

-- Le meilleur appât à poser (ou nil), et le meilleur que la compétence refuse encore.
function ns.meilleurAppat(competence, compter)
  local utilisables, bloques = ns.appatsDesSacs(competence, compter)
  return utilisables[1], bloques[1]
end

-- Les trois choix du rachat d'appâts, après « aucun » : 5, 10 ou 20.
ns.PALIERS_RACHAT = { 0, 5, 10, 20 }
function ns.nombreRachat(palier)
  return ns.PALIERS_RACHAT[math.floor(tonumber(palier) or 0) + 1] or 0
end
function ns.texteRachat(palier)
  local n = ns.nombreRachat(palier)
  return n == 0 and "Aucun" or ("jusqu'à " .. n)
end
-- Le palier d'un nombre tapé (0, 5, 10 ou 20), ou nil.
function ns.palierDeNombre(n)
  for i, v in ipairs(ns.PALIERS_RACHAT) do
    if v == n then return i - 1 end
  end
  return nil
end

-- Parmi les offres d'un marchand { index, id, prix, lot, utilisable }, l'appât à
-- racheter : le meilleur que la compétence permet, au meilleur prix à bonus égal.
function ns.choisirAppatMarchand(offres, competence)
  competence = tonumber(competence)
  if not competence then return nil end
  local meilleur, bonusMeilleur, unitaireMeilleur
  for _, o in ipairs(offres or {}) do
    local a = ns.appatConnu(o.id)
    local prix = tonumber(o.prix)
    if a and a.requis <= competence and o.utilisable ~= false and prix then
      local unitaire = prix / math.max(1, tonumber(o.lot) or 1)
      if not meilleur or a.bonus > bonusMeilleur or (a.bonus == bonusMeilleur and unitaire < unitaireMeilleur) then
        meilleur, bonusMeilleur, unitaireMeilleur = o, a.bonus, unitaire
      end
    end
  end
  return meilleur
end

-- Combien en racheter pour en avoir « voulu » ? prix : cuivre pour un lot de « lot »
-- pièces ; orDispo : cuivre du joueur ; stock : nombre en vente (nil ou -1 = illimité).
-- Renvoie le nombre, son coût en cuivre, et vrai quand le manque d'or ou de stock
-- l'a réduit.
function ns.nombreARacheter(voulu, possede, prix, lot, orDispo, stock)
  voulu = math.max(0, math.floor(tonumber(voulu) or 0))
  local brut = voulu - (tonumber(possede) or 0)
  prix = tonumber(prix)
  if brut <= 0 or not prix then return 0, 0, false end
  local unitaire = prix / math.max(1, tonumber(lot) or 1)
  local n = brut
  if unitaire > 0 and orDispo then n = math.min(n, math.floor(orDispo / unitaire)) end
  if stock and stock >= 0 then n = math.min(n, stock) end
  n = math.max(0, n)
  return n, math.ceil(unitaire * n), n < brut
end

-- Le temps restant d'un appât, écrit pour le joueur. nil = aucun appât posé.
function ns.texteTempsRestant(secondes)
  if type(secondes) ~= "number" then return "aucun appât posé" end
  secondes = math.floor(secondes)
  if secondes <= 0 then return "plus d'appât" end
  if secondes < 60 then return secondes .. " s" end
  return string.format("%d min %02d s", math.floor(secondes / 60), secondes % 60)
end

-- Faut-il prévenir que l'appât va finir ? Une fois par appât, sous la minute.
function ns.doitAlerterAppat(secondes, dejaAlerte)
  return type(secondes) == "number" and secondes > 0 and secondes <= 60 and not dejaAlerte
end

-- De l'argent en cuivre, écrit « 3 po 20 pa 5 pc » (po = or, pa = argent, pc = cuivre).
function ns.texteArgent(cuivre)
  cuivre = math.max(0, math.floor(tonumber(cuivre) or 0))
  local po, pa, pc = math.floor(cuivre / 10000), math.floor(cuivre / 100) % 100, cuivre % 100
  local t = {}
  if po > 0 then t[#t + 1] = po .. " po" end
  if pa > 0 then t[#t + 1] = pa .. " pa" end
  if pc > 0 or #t == 0 then t[#t + 1] = pc .. " pc" end
  return table.concat(t, " ")
end

-- La compétence de pêche, écrite « Pêche : 97 / 150 ».
function ns.texteCompetence(rang, maxi)
  if type(rang) ~= "number" then return "Pêche : pas apprise" end
  if type(maxi) ~= "number" then return "Pêche : " .. rang end
  return string.format("Pêche : %d / %d", rang, maxi)
end
function ns.texteBonusAppat(bonus)
  return type(bonus) == "number" and bonus > 0 and ("appât +" .. bonus) or ""
end

-- La session de pêche : lancers, prises, poissons échappés, temps passé à pêcher,
-- et ce qui a été pêché (objets[id] = nombre, ordre = les plus récents d'abord).
function ns.nouvelleSession()
  return { lancers = 0, prises = 0, echappes = 0, actif = 0, dernier = nil, objets = {}, ordre = {} }
end
-- Un lancer : le temps entre deux lancers compte comme du temps de pêche, sauf après une pause de plus de 90 s.
function ns.compterLancer(s, maintenant)
  if s.dernier and maintenant - s.dernier < 90 then s.actif = s.actif + (maintenant - s.dernier) end
  s.dernier = maintenant
  s.lancers = s.lancers + 1
end
-- Une prise : objets = { { id, nombre } } (peut être vide : de l'or, par exemple).
function ns.compterPrise(s, objets)
  s.prises = s.prises + 1
  for _, o in ipairs(objets or {}) do
    if not s.objets[o.id] then
      s.objets[o.id] = 0
      table.insert(s.ordre, 1, o.id)
    end
    s.objets[o.id] = s.objets[o.id] + (o.nombre or 1)
  end
end
function ns.compterEchappe(s) s.echappes = s.echappes + 1 end
-- Prises par heure, ou nil tant qu'il y en a trop peu (moins de 3, ou moins d'une minute de pêche).
function ns.prisesParHeure(s, maintenant)
  local t = s.actif
  if s.dernier and maintenant - s.dernier < 90 then t = t + (maintenant - s.dernier) end
  if s.prises < 3 or t < 60 then return nil end
  return s.prises / t * 3600
end
function ns.textePrisesParHeure(v)
  return v and string.format("%d", math.floor(v + 0.5)) or "-"
end
-- Valeur de revente de la session. prixDe(id) -> cuivre pour un objet (nil si inconnu).
function ns.valeurSession(s, prixDe)
  local total = 0
  for id, n in pairs(s.objets) do total = total + n * (prixDe(id) or 0) end
  return total
end
-- Les dernières prises à montrer dans la fenêtre : { { id, nombre } }, au plus « max ».
function ns.prisesAffichees(s, max)
  local liste = {}
  for i = 1, math.min(max, #s.ordre) do
    liste[i] = { id = s.ordre[i], nombre = s.objets[s.ordre[i]] }
  end
  return liste
end

-- Ce que fait la touche de pêche, selon la situation :
-- arret (mode pêche coupé), combat, ferrer (ligne à l'eau), appat (canne sans appât), lancer.
function ns.etatPeche(modePeche, enCombat, ligneAEau, besoinAppat)
  if not modePeche then return "arret" end
  if enCombat then return "combat" end
  if ligneAEau then return "ferrer" end
  if besoinAppat then return "appat" end
  return "lancer"
end

-- La phrase qui dit au joueur quoi faire. touche : la touche écrite lisiblement, ou nil.
function ns.texteAction(etat, touche)
  if etat == "arret" then return "Mode pêche arrêté : relance-le pour utiliser la touche." end
  if etat == "combat" then return "En combat : la touche reprend son rôle normal." end
  if not touche then return "Choisis une touche de pêche avec le bouton ci-dessous." end
  if etat == "ferrer" then return "Ligne à l'eau : appuie sur " .. touche .. " au plouf pour ferrer." end
  if etat == "appat" then return "Appuie sur " .. touche .. " pour poser l'appât." end
  return "Appuie sur " .. touche .. " pour lancer la ligne."
end

-- La touche appuyée, écrite comme le jeu l'attend pour une liaison : ALT-CTRL-SHIFT-F.
function ns.comboTouche(touche, alt, ctrl, maj)
  return (alt and "ALT-" or "") .. (ctrl and "CTRL-" or "") .. (maj and "SHIFT-" or "") .. touche
end

-- Une touche tapée dans une commande (« shift-f ») : le code du jeu, ou nil si ça n'a pas de sens.
function ns.toucheValide(texte)
  local t = tostring(texte or ""):gsub("%s+", ""):upper()
  if t == "" or #t > 30 or not t:match("^[%w%-_]+$") then return nil end
  if t:sub(-1) == "-" or t:sub(1, 1) == "-" then return nil end
  return t
end

-- Les réglages du jeu qui permettent à la touche d'interaction de viser le bouchon
-- (dans toutes les directions, à distance de lancer). Ils sont NOTÉS avant d'être
-- changés et REMIS à la fin : un autre addon qui les laissait changés avait cassé le
-- lancement de sorts sur soi.
ns.NOMS_FERRAGE = { "SoftTargetInteract", "SoftTargetInteractArc", "SoftTargetInteractRange",
  "SoftTargetIconGameObject", "SoftTargetIconInteract" }
ns.REGLAGES_FERRAGE = { SoftTargetInteract = "3", SoftTargetInteractArc = "2", SoftTargetInteractRange = "30",
  SoftTargetIconGameObject = "1", SoftTargetIconInteract = "1" }
-- Note la valeur actuelle de chaque réglage que le jeu connaît. lire(nom) -> texte ou nil.
function ns.garderValeurs(noms, lire)
  local gardees = {}
  for _, nom in ipairs(noms) do
    local v = lire(nom)
    if v ~= nil then gardees[nom] = tostring(v) end
  end
  return gardees
end
-- Remet les valeurs notées. Renvoie combien ont été remises.
function ns.remettreValeurs(gardees, noms, ecrire)
  local n = 0
  for _, nom in ipairs(noms) do
    if gardees[nom] ~= nil then
      ecrire(nom, gardees[nom])
      n = n + 1
    end
  end
  return n
end

-- Le message « Ton poisson s'est échappé » : a1 et a2 sont les deux premiers arguments
-- de l'évènement (le texte est l'un ou l'autre selon la version du jeu).
function ns.estMessageEchappe(a1, a2, attendu)
  return type(attendu) == "string" and (a1 == attendu or a2 == attendu)
end

-- ---------------------------------------------------------------------------
-- Petits outils
-- ---------------------------------------------------------------------------

local function lireCVar(nom) return (C_CVar and C_CVar.GetCVar or GetCVar)(nom) end
local function ecrireCVar(nom, valeur)
  if InCombatLockdown() then return end
  (C_CVar and C_CVar.SetCVar or SetCVar)(nom, valeur)
end
-- Les mêmes, mais sans jamais faire d'erreur : un réglage inconnu de cette version
-- du jeu est simplement ignoré (lecture : nil).
local function lireCVarSur(nom)
  local ok, v = pcall(lireCVar, nom)
  if ok then return v end
  return nil
end
local function ecrireCVarSur(nom, valeur)
  if InCombatLockdown() then return end
  pcall(ecrireCVar, nom, valeur)
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

-- Une touche reliée, écrite lisiblement (nil si vide). GetBindingText traduit le code de
-- la touche (« SHIFT-E » devient « Maj-E », « BUTTON4 » un bouton de souris). Certaines
-- touches (², <) sortent en « ? » avec la police du jeu : on garde alors le code brut.
local function texteCombo(k)
  if not k or k == "" then return nil end
  local texte = GetBindingText and GetBindingText(k, "KEY_") or k
  if type(texte) ~= "string" or texte == "" or texte:find("?", 1, true) then texte = k end
  return texte
end

-- Les valeurs « secrètes » que le jeu cache parfois aux addons : on ne les lit pas.
local estSecret = issecretvalue or function() return false end

local function nomObjet(id)
  local nom = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id))
  return nom or ("objet " .. id)
end

-- ---------------------------------------------------------------------------
-- 1. Pêche confort : mode pêche, une seule touche, fenêtre, ramassage, appâts
-- ---------------------------------------------------------------------------

local modePeche = false
local derniereActivite = 0
local ligneAEau = false       -- la ligne est à l'eau (le sort de pêche est en cours)
local session = ns.nouvelleSession()
local appatPoseA = -100       -- moment du dernier appui pour poser un appât
local appatAlerte = false     -- l'alerte « l'appât va finir » a déjà été donnée pour cet appât
local butinPecheVu = false    -- le butin de pêche ouvert a déjà été compté
local toucheEnAttente = false -- la touche sera reliée ou retirée à la fin du combat
local ferrageEnAttente = false
local fenetreEnAttente = nil  -- vrai ou faux : montrer ou cacher la fenêtre Pêche à la fin du combat
local appliquee = nil         -- ce qui est relié à la touche en ce moment
local texteAppatPose = nil    -- la dernière macro donnée aux boutons d'appât
local majPeche                -- la mise à jour de la fenêtre Pêche, définie plus bas
local appatClic               -- le bouton « Poser l'appât » de la fenêtre
local choisirTouche           -- l'écoute d'une touche, définie dans la partie « Récolte »

-- Bouton « sécurisé » : seul ce type de bouton a le droit de lancer un sort,
-- et seulement quand TU cliques (ou appuies sur la touche). Le double clic droit
-- et la touche de pêche le déclenchent.
local lancer = CreateFrame("Button", "MetiersAutoLancer", UIParent, "SecureActionButtonTemplate")
lancer:RegisterForClicks("AnyUp", "AnyDown")
lancer:SetAttribute("type", "spell")
lancer:Hide()
lancer:SetScript("PostClick", function(self)
  derniereActivite = GetTime()
  if not InCombatLockdown() then ClearOverrideBindings(self) end
end)

-- Le même genre de bouton pour poser l'appât : une macro qui utilise l'appât puis le
-- pose sur la canne (emplacement 16). Un appui = une action. Il reste caché : c'est la
-- touche de pêche qui le déclenche.
local appatCle = CreateFrame("Button", "MetiersAutoAppat", UIParent, "SecureActionButtonTemplate")
appatCle:RegisterForClicks("AnyUp", "AnyDown")
appatCle:SetAttribute("type", "macro")
appatCle:Hide()

-- Le propriétaire des liaisons de la touche de pêche. C'est un cadre « sécurisé » : au
-- début d'un combat il retire lui-même la touche, même en plein combat, donc la touche
-- reprend son rôle normal tout de suite. Sans ce type de cadre, on se contente de
-- retirer la touche dès qu'on le peut.
local proprio
do
  local ok, cadre = pcall(CreateFrame, "Frame", "MetiersAutoTouche", UIParent, "SecureHandlerStateTemplate")
  if ok and cadre then
    proprio = cadre
    if RegisterStateDriver then
      pcall(function()
        proprio:SetAttribute("_onstate-combat", [[ if newstate == "1" then self:ClearBindings() end ]])
        RegisterStateDriver(proprio, "combat", "[combat] 1; 0")
      end)
    end
  else
    proprio = CreateFrame("Frame", "MetiersAutoTouche", UIParent)
  end
end

-- ----- ce que le jeu sait de la pêche (chaque appel est protégé : l'addon reste utilisable si l'un manque)

-- Un canal est-il en cours chez le joueur ? (la ligne à l'eau est un canal)
local function canalEnCours()
  if not UnitChannelInfo then return false end
  local ok, nom = pcall(UnitChannelInfo, "player")
  if not ok then return false end
  return nom and true or false
end

-- Une canne à pêche est-elle en main droite (classe 2, sous-classe 20) ?
local function canneEquipee()
  if not GetInventoryItemID then return false end
  local id = GetInventoryItemID("player", 16)
  if not id or estSecret(id) then return false end
  local info = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not info then return false end
  local ok, _, _, _, _, _, classe, sousClasse = pcall(info, id)
  return ok and classe == 2 and sousClasse == 20
end

-- L'appât posé sur la canne : vrai ou faux, le temps restant en secondes (ou nil), et le
-- numéro de l'enchantement (pour connaître son bonus).
local function appatPose()
  if not GetWeaponEnchantInfo then return false end
  local ok, a, expiration, _, idEnchant = pcall(GetWeaponEnchantInfo)
  if not ok or a ~= true then return false end
  local secondes
  if type(expiration) == "number" and not estSecret(expiration) then secondes = math.floor(expiration / 1000) end
  return true, secondes, type(idEnchant) == "number" and idEnchant or nil
end

-- La compétence de pêche : rang, maximum, bonus d'équipement (ou nil si elle n'est pas apprise).
local function competencePeche()
  if GetProfessions and GetProfessionInfo then
    local metiers = { GetProfessions() } -- métier 1, métier 2, archéologie, pêche, cuisine (trous possibles)
    local index = metiers[4]
    if index then
      local _, _, rang, maxi, _, _, _, modif = GetProfessionInfo(index)
      if type(rang) == "number" and not estSecret(rang) then
        return rang, type(maxi) == "number" and maxi or rang, type(modif) == "number" and modif or 0
      end
    end
  end
  if GetNumSkillLines and GetSkillLineInfo then
    local nomPeche = nomSort(7620)
    for i = 1, GetNumSkillLines() do
      local nom, entete, _, rang, _, modif, maxi = GetSkillLineInfo(i)
      if not entete and nom == nomPeche and type(rang) == "number" then
        return rang, type(maxi) == "number" and maxi or rang, type(modif) == "number" and modif or 0
      end
    end
  end
  return nil
end

local function dansSacs(id)
  return (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id)) or (GetItemCount and GetItemCount(id)) or 0
end

-- Le meilleur appât des sacs que la compétence permet (ou nil), puis le meilleur qu'elle refuse encore.
local function meilleurAppatSacs()
  local rang = competencePeche()
  return ns.meilleurAppat(rang or 0, dansSacs)
end

local function iconeObjet(id)
  local info = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not info then return nil end
  local ok, _, _, _, _, icone = pcall(info, id)
  return ok and icone or nil
end

-- Prix de revente d'un objet, en cuivre (0 si le jeu ne le connaît pas encore).
local function prixVente(id)
  local lire = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not lire then return 0 end
  local ok, _, _, _, _, _, _, _, _, _, _, prix = pcall(lire, id)
  return ok and type(prix) == "number" and prix or 0
end

-- Faut-il poser un appât avant de lancer ? Seulement avec une canne, sans appât déjà
-- posé, avec un appât utilisable dans les sacs, et pas juste après un appui.
local function besoinAppat()
  if not db.pecheAppat or GetTime() - appatPoseA < 3 then return false end
  if not canneEquipee() or appatPose() then return false end
  return meilleurAppatSacs() ~= nil
end

local function etatActuel()
  local combat = InCombatLockdown() and true or false
  local besoin = modePeche and not combat and not ligneAEau and besoinAppat()
  return ns.etatPeche(modePeche, combat, ligneAEau, besoin)
end

-- ----- les réglages du jeu qui permettent de ferrer : notés avant, remis après

-- À la première ligne à l'eau : on note les valeurs d'origine (une seule fois, même après
-- un plantage : elles restent dans la base) puis on les change.
local function preparerFerrage()
  if db.ferrageAvant or InCombatLockdown() then return end
  db.ferrageAvant = ns.garderValeurs(ns.NOMS_FERRAGE, lireCVarSur)
  for _, nom in ipairs(ns.NOMS_FERRAGE) do
    if db.ferrageAvant[nom] ~= nil then ecrireCVarSur(nom, ns.REGLAGES_FERRAGE[nom]) end
  end
end
-- Remet les valeurs d'origine. En combat, on attend la fin du combat.
local function remettreFerrage()
  if not db or not db.ferrageAvant then return end
  if InCombatLockdown() then ferrageEnAttente = true return end
  ns.remettreValeurs(db.ferrageAvant, ns.NOMS_FERRAGE, ecrireCVarSur)
  db.ferrageAvant = nil
  ferrageEnAttente = false
end

-- ----- la touche unique

-- Relie (ou retire) la touche de pêche selon la situation :
--   ligne à l'eau : la touche ferre (« Interagir avec la cible » vise le bouchon) ;
--   canne sans appât : elle pose l'appât ; sinon : elle lance la ligne.
-- Hors mode pêche et en combat, aucune liaison : la touche reprend son rôle normal.
local function appliquerTouche(force)
  if not db then return end
  if InCombatLockdown() then toucheEnAttente = true return end
  toucheEnAttente = false
  local etat = etatActuel()
  local touche = db.actif and db.pecheTouche and db.touchePeche or nil
  if etat == "arret" or etat == "combat" then touche = nil end
  local cle = touche and (etat .. "|" .. touche) or nil
  if not force and cle == appliquee then return end
  ClearOverrideBindings(proprio)
  appliquee = cle
  if not touche then return end
  if etat == "ferrer" then
    preparerFerrage()
    SetOverrideBinding(proprio, true, touche, "INTERACTTARGET")
  elseif etat == "appat" then
    SetOverrideBindingClick(proprio, true, touche, "MetiersAutoAppat")
  else
    SetOverrideBindingClick(proprio, true, touche, "MetiersAutoLancer")
  end
end

-- Donne aux boutons d'appât la macro du meilleur appât des sacs (impossible en combat).
local function majAppat()
  if not db then return end
  if InCombatLockdown() then return end
  local meilleur = meilleurAppatSacs()
  local texte = meilleur and ("/use item:" .. meilleur.id .. "\n/use 16") or ""
  if texte == texteAppatPose then return end
  texteAppatPose = texte
  appatCle:SetAttribute("macrotext", texte)
  if appatClic then appatClic:SetAttribute("macrotext", texte) end
end

-- Après un appui sur un bouton d'appât : la touche lance la ligne pendant quelques
-- secondes (le jeu met un instant à voir l'appât), puis tout est revu.
local function apresAppat()
  appatPoseA = GetTime()
  derniereActivite = appatPoseA
  appliquerTouche()
  C_Timer.After(0.6, function() majAppat() if majPeche then majPeche() end end)
  C_Timer.After(3.2, function() appliquerTouche() end)
end
appatCle:SetScript("PostClick", apresAppat)

-- ----- le son (réglages notés avant, remis après)

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
  -- En combat le jeu refuse l'écriture : on garde les valeurs et on les remet à la fin du combat.
  if InCombatLockdown and InCombatLockdown() then return end
  for nom, valeur in pairs(db.sonAvant) do ecrireCVar(nom, valeur) end
  db.sonAvant = nil
end

-- ----- la fenêtre « Pêche »

local W = {}
local fenetrePeche = CreateFrame("Frame", "MetiersAutoPeche", UIParent, "BackdropTemplate")
fenetrePeche:SetSize(300, 330)
fenetrePeche:SetMovable(true)
fenetrePeche:SetClampedToScreen(true)
fenetrePeche:EnableMouse(true)
fenetrePeche:RegisterForDrag("LeftButton")
local deplacePeche = false
-- Elle contient un bouton sécurisé : on ne la déplace pas, on ne la montre pas et on ne
-- la cache pas en plein combat.
fenetrePeche:SetScript("OnDragStart", function(self)
  if InCombatLockdown() then return end
  deplacePeche = true
  self:StartMoving()
end)
fenetrePeche:SetScript("OnDragStop", function(self)
  if not deplacePeche then return end
  deplacePeche = false
  self:StopMovingOrSizing()
  local point, _, pointRelatif, x, y = self:GetPoint()
  db.positionPeche = { point, pointRelatif, x, y }
end)
local _, fermerPeche = ns.habiller(fenetrePeche, { titre = "Pêche", fermer = true })
fenetrePeche:Hide()

local function texteP(x, y, largeur, gabarit)
  local fs = fenetrePeche:CreateFontString(nil, "OVERLAY", gabarit or "GameFontHighlightSmall")
  fs:SetPoint("TOPLEFT", x, y)
  if largeur then fs:SetWidth(largeur) end
  fs:SetJustifyH("LEFT")
  return fs
end
local function bulle(cadre, titre, aide)
  cadre:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(titre)
    GameTooltip:AddLine(aide, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  cadre:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Compétence et sa barre
W.competence = texteP(14, -38, 130, "GameFontNormal")
W.bonus = texteP(150, -39, 136, "GameFontHighlightSmall")
W.bonus:SetJustifyH("RIGHT")
W.barre = CreateFrame("StatusBar", nil, fenetrePeche)
W.barre:SetSize(272, 10)
W.barre:SetPoint("TOPLEFT", 14, -58)
W.barre:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
W.barre:SetStatusBarColor(0.86, 0.68, 0.32)
local fondBarre = W.barre:CreateTexture(nil, "BACKGROUND")
fondBarre:SetAllPoints()
fondBarre:SetColorTexture(0, 0, 0, 0.5)

-- Appât : son icône, son nom, le temps qui lui reste, et le bouton qui le pose
W.appatIcone = fenetrePeche:CreateTexture(nil, "ARTWORK")
W.appatIcone:SetSize(32, 32)
W.appatIcone:SetPoint("TOPLEFT", 14, -78)
W.appatIcone:SetTexCoord(0.08, 0.92, 0.08, 0.92)
W.appatNom = texteP(54, -80, 232, "GameFontHighlight")
W.appatNom:SetWordWrap(false)
W.appatTemps = texteP(54, -97, 232, "GameFontHighlightSmall")
W.appatTemps:SetWordWrap(false)
do
  local ok, bouton = pcall(CreateFrame, "Button", "MetiersAutoAppatClic", fenetrePeche,
    "UIPanelButtonTemplate,SecureActionButtonTemplate")
  if not ok or not bouton then
    ok, bouton = pcall(CreateFrame, "Button", "MetiersAutoAppatClic", fenetrePeche, "SecureActionButtonTemplate")
  end
  appatClic = bouton
end
appatClic:SetSize(150, 22)
appatClic:SetPoint("TOPLEFT", 14, -118)
appatClic:RegisterForClicks("AnyUp", "AnyDown")
appatClic:SetAttribute("type", "macro")
if appatClic.SetText then appatClic:SetText("Poser l'appât") end
appatClic:SetScript("PostClick", apresAppat)
bulle(appatClic, "Poser l'appât", "Un clic pose le meilleur appât de tes sacs sur ta canne (celui que ta compétence permet).")

-- Les compteurs de la session
W.compteurs = {}
local colonnes = { { "lancers", "Lancers" }, { "prises", "Prises" }, { "echappes", "Échappés" }, { "heure", "Par heure" } }
for i, c in ipairs(colonnes) do
  local largeur = 68
  local centre = 14 + largeur * (i - 0.5)
  local valeur = fenetrePeche:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  valeur:SetPoint("TOP", fenetrePeche, "TOPLEFT", centre, -156)
  local legende = fenetrePeche:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  legende:SetPoint("TOP", valeur, "BOTTOM", 0, -2)
  legende:SetText(c[2])
  W.compteurs[c[1]] = valeur
end
W.valeur = texteP(14, -200, 272, "GameFontHighlightSmall")

-- La liste des prises de la session : une icône par objet, avec le nombre
W.cases = {}
for i = 1, 8 do
  local c = CreateFrame("Frame", nil, fenetrePeche)
  c:SetSize(30, 30)
  c:SetPoint("TOPLEFT", 14 + (i - 1) * 34, -222)
  c.icone = c:CreateTexture(nil, "ARTWORK")
  c.icone:SetAllPoints()
  c.icone:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  c.nombre = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  c.nombre:SetPoint("BOTTOMRIGHT", -1, 1)
  c:EnableMouse(true)
  c:SetScript("OnEnter", function(self)
    if not self.id then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.id) else GameTooltip:SetHyperlink("item:" .. self.id) end
    GameTooltip:AddLine("Pêché pendant cette session : " .. (session.objets[self.id] or 0), 0.5, 0.85, 0.55)
    GameTooltip:Show()
  end)
  c:SetScript("OnLeave", function() GameTooltip:Hide() end)
  W.cases[i] = c
end
W.vide = texteP(14, -230, 272, "GameFontDisableSmall")
W.vide:SetText("Tes prises apparaissent ici.")

-- Ce que fait la touche, et les boutons du bas
W.action = texteP(14, -264, 272, "GameFontNormalSmall")
W.toucheBtn = ns.creerBouton(fenetrePeche, "Choisir la touche",
  "Appuie ensuite sur la touche voulue : elle lance la ligne, ferre le bouchon et pose l'appât, en mode pêche seulement. Échap annule. Impossible en combat.",
  function()
    if choisirTouche(function() W.ecoute = false if majPeche then majPeche() end end, "peche") then
      W.ecoute = true
      W.toucheBtn:SetText("Appuie sur une touche…")
    end
  end, 150)
W.toucheBtn:SetPoint("TOPLEFT", 14, -296)
W.razBtn = ns.creerBouton(fenetrePeche, "Remise à zéro",
  "Remet à zéro les lancers, les prises et la valeur de la session.",
  function() session = ns.nouvelleSession() if majPeche then majPeche() end end, 110)
W.razBtn:SetPoint("TOPLEFT", 176, -296)

-- La fenêtre à sa place : celle que tu as choisie, sinon celle d'origine.
local function placerPeche()
  if InCombatLockdown() then return end
  fenetrePeche:ClearAllPoints()
  local p = db.positionPeche
  if p then fenetrePeche:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  else fenetrePeche:SetPoint("LEFT", UIParent, "LEFT", 60, 40) end
end

-- Montre ou cache la fenêtre. En combat, on attend la fin du combat.
local function montrerFenetrePeche(voulu)
  if InCombatLockdown() then fenetreEnAttente = voulu return end
  fenetreEnAttente = nil
  if voulu then
    placerPeche()
    fenetrePeche:Show()
    if majPeche then majPeche() end
  else
    fenetrePeche:Hide()
  end
end
fermerPeche:SetScript("OnClick", function()
  if InCombatLockdown() then
    ns.reglages.dire("|cffff4040pas en combat.|r")
  else
    fenetrePeche:Hide()
  end
end)

-- Ouvre ou ferme la fenêtre à la main (bouton des réglages, commande /metiers fenetre).
function MetiersAuto_FenetrePeche()
  if not db then return end
  montrerFenetrePeche(not fenetrePeche:IsShown())
end

majPeche = function()
  if not db or not fenetrePeche:IsShown() then return end
  local maintenant = GetTime()
  local etat = etatActuel()

  -- compétence de pêche
  local rang, maxi = competencePeche()
  W.competence:SetText(ns.texteCompetence(rang, maxi))
  W.barre:SetMinMaxValues(0, math.max(1, maxi or 1))
  W.barre:SetValue(rang or 0)

  -- appât : celui de la canne, sinon le meilleur des sacs
  local posee, secondes, idEnchant = appatPose()
  local meilleur, bloque = meilleurAppatSacs()
  W.bonus:SetText(ns.texteBonusAppat(posee and ns.bonusAppatPose(idEnchant) or nil))
  local icone = "Interface\\Icons\\INV_Misc_Orb_03"
  if posee then
    local bonus = ns.bonusAppatPose(idEnchant)
    W.appatNom:SetText("Appât posé" .. (bonus and (" (+" .. bonus .. ")") or ""))
    W.appatTemps:SetText("Temps restant : " .. (secondes and ns.texteTempsRestant(secondes) or "inconnu"))
    local bientot = secondes and secondes <= 60
    W.appatTemps:SetTextColor(bientot and 1 or 0.5, bientot and 0.35 or 0.9, bientot and 0.3 or 0.5)
    icone = "Interface\\Icons\\Trade_Fishing"
  else
    W.appatTemps:SetTextColor(0.7, 0.7, 0.7)
    if meilleur then
      W.appatNom:SetText(nomObjet(meilleur.id) .. " (+" .. meilleur.bonus .. ")")
      W.appatTemps:SetText("Aucun appât posé, " .. meilleur.nombre .. " dans tes sacs")
      icone = iconeObjet(meilleur.id) or icone
    elseif bloque then
      W.appatNom:SetText("Pas d'appât utilisable")
      W.appatTemps:SetText(nomObjet(bloque.id) .. " demande Pêche " .. bloque.requis)
    else
      W.appatNom:SetText("Pas d'appât dans tes sacs")
      W.appatTemps:SetText("Aucun appât posé")
    end
  end
  W.appatIcone:SetTexture(icone)
  if W.appatIcone.SetDesaturated then W.appatIcone:SetDesaturated(not posee and not meilleur) end
  local peutPoser = meilleur ~= nil and not posee and canneEquipee()
  appatClic:SetAlpha(peutPoser and 1 or 0.5)

  -- la session
  W.compteurs.lancers:SetText(tostring(session.lancers))
  W.compteurs.prises:SetText(tostring(session.prises))
  W.compteurs.echappes:SetText(tostring(session.echappes))
  W.compteurs.heure:SetText(ns.textePrisesParHeure(ns.prisesParHeure(session, maintenant)))
  W.valeur:SetText("Valeur de revente : " .. ns.texteArgent(ns.valeurSession(session, prixVente)))
  local liste = ns.prisesAffichees(session, #W.cases)
  for i, c in ipairs(W.cases) do
    local p = liste[i]
    c.id = p and p.id or nil
    if p then
      c.icone:SetTexture(iconeObjet(p.id))
      c.nombre:SetText(p.nombre > 1 and tostring(p.nombre) or "")
      c:Show()
    else
      c:Hide()
    end
  end
  W.vide:SetShown(#liste == 0)

  -- ce que fait la touche
  if modePeche and not db.pecheTouche then
    W.action:SetText("La touche unique est coupée (réglages, onglet Pêche).")
  else
    W.action:SetText(ns.texteAction(etat, texteCombo(db.touchePeche)))
  end
  if not W.ecoute then W.toucheBtn:SetText(db.touchePeche and "Changer la touche" or "Choisir la touche") end
end

local acc = 0
fenetrePeche:SetScript("OnUpdate", function(_, ecoule)
  acc = acc + ecoule
  if acc < 0.25 then return end
  acc = 0
  majPeche()
end)

-- Prévient une fois quand l'appât va finir (moins d'une minute).
local function verifierAppat()
  if not db or not db.actif or not db.pecheFenetre or not modePeche then return end
  local posee, secondes = appatPose()
  if not posee then appatAlerte = false return end
  if ns.doitAlerterAppat(secondes, appatAlerte) then
    appatAlerte = true
    ns.reglages.dire("ton appât va bientôt finir (moins d'une minute).")
    if PlaySound then pcall(PlaySound, SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "master") end
  elseif secondes and secondes > 60 then
    appatAlerte = false
  end
end

-- ----- ramassage direct des prises, et compte de la session

-- Ce qui est dans le butin de pêche ouvert : { { id, nombre } } (l'or n'a pas de lien d'objet).
local function lireButinPeche()
  local objets = {}
  for i = 1, (GetNumLootItems and GetNumLootItems() or 0) do
    local lien = GetLootSlotLink and GetLootSlotLink(i)
    if type(lien) == "string" and not estSecret(lien) then
      local id = tonumber(lien:match("item:(%d+)"))
      if id then
        local quantite = GetLootSlotInfo and select(3, GetLootSlotInfo(i))
        if type(quantite) ~= "number" or estSecret(quantite) then quantite = 1 end
        objets[#objets + 1] = { id = id, nombre = quantite }
      end
    end
  end
  return objets
end

-- Un butin de pêche vient de s'ouvrir : on le compte (une fois), puis, si l'option est
-- cochée, on prend tout. Le réglage général de ramassage du joueur n'est pas touché.
local function surButinPeche()
  if butinPecheVu or not db.actif then return end
  if not (IsFishingLoot and IsFishingLoot()) then return end
  butinPecheVu = true
  derniereActivite = GetTime()
  ns.compterPrise(session, lireButinPeche())
  if db.pecheRamasser and GetNumLootItems and LootSlot then
    for i = (GetNumLootItems() or 0), 1, -1 do pcall(LootSlot, i) end
  end
  if majPeche then majPeche() end
end

-- ----- rachat d'appâts chez un marchand

-- Prix (cuivre), taille du lot, utilisable, stock et « autre monnaie » d'un article du marchand.
local function infoMarchand(i)
  if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
    local ok, t = pcall(C_MerchantFrame.GetItemInfo, i)
    if ok and type(t) == "table" then
      return t.price, t.stackCount, t.isUsable, t.numAvailable, t.hasExtendedCost
    end
  end
  if GetMerchantItemInfo then
    local ok, _, _, prix, lot, dispo, _, utilisable, etendu = pcall(GetMerchantItemInfo, i)
    if ok then return prix, lot, utilisable, dispo, etendu end
  end
  return nil
end

-- À l'ouverture d'un marchand qui vend des appâts : on rachète le meilleur que la
-- compétence permet, jusqu'au nombre voulu (réglage coupé au départ). Ce qui est
-- acheté et le prix sont dits dans le chat.
local function racheterAppats()
  if not db or not db.actif then return end
  local voulu = ns.nombreRachat(db.rachatPalier)
  if voulu <= 0 then return end
  if not (GetMerchantNumItems and GetMerchantItemLink and BuyMerchantItem) then return end
  local rang = competencePeche()
  if not rang then return end
  local offres = {}
  for i = 1, (GetMerchantNumItems() or 0) do
    local lien = GetMerchantItemLink(i)
    local id = type(lien) == "string" and not estSecret(lien) and tonumber(lien:match("item:(%d+)")) or nil
    if id and ns.appatConnu(id) then
      local prix, lot, utilisable, dispo, etendu = infoMarchand(i)
      offres[#offres + 1] = { index = i, id = id, prix = prix, lot = lot, stock = dispo,
        utilisable = (utilisable ~= false) and not etendu }
    end
  end
  local choix = ns.choisirAppatMarchand(offres, rang)
  if not choix then return end
  local n, cout, reduit = ns.nombreARacheter(voulu, dansSacs(choix.id), choix.prix, choix.lot,
    GetMoney and GetMoney() or nil, choix.stock)
  if n <= 0 then
    if reduit and choix.stock ~= 0 then ns.reglages.dire("pas assez d'or pour racheter des appâts.") end
    return
  end
  -- On n'achète pas plus qu'une pile à la fois.
  local parPile = GetMerchantItemMaxStack and GetMerchantItemMaxStack(choix.index) or n
  if type(parPile) ~= "number" or parPile < 1 then parPile = n end
  local reste, achete = n, 0
  for _ = 1, 10 do
    if reste <= 0 then break end
    local k = math.min(reste, parPile)
    local ok = pcall(BuyMerchantItem, choix.index, k)
    if not ok then break end
    reste, achete = reste - k, achete + k
  end
  if achete > 0 then
    ns.reglages.dire("racheté " .. achete .. " × " .. nomObjet(choix.id) .. " pour "
      .. ns.texteArgent(math.ceil(cout / n * achete)) .. ". Réglable dans l'onglet Pêche.")
  end
end

-- Faut-il prévenir qu'aucune canne n'est équipée ? Seulement là où le jeu en exige une (pas sur Retail,
-- interface 100000 et plus). objet : ce qui est en main ; infos : la fonction du jeu qui décrit un objet.
function ns.canneManque(interface, objet, infos)
  if type(interface) ~= "number" or interface >= 100000 then return false end
  if not objet then return true end
  if type(infos) ~= "function" then return false end
  local _, _, _, _, _, classe, sous = infos(objet)
  return not (classe == 2 and sous == 20)
end

-- ----- le mode pêche

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
    appatAlerte = false
    if db.pecheSon then sonPeche() end
    -- Addon Tenues (facultatif) : met la tenue Pêche avec le mode pêche.
    if Tenues_ModePeche then pcall(Tenues_ModePeche, true) end
    -- Sans canne équipée, le jeu refuse le lancer sans toujours le dire à l'écran : on le dit nous-mêmes
    -- (après une seconde et demie, le temps que la tenue Pêche soit mise).
    if C_Timer and C_Timer.After then
      C_Timer.After(1.5, function()
        if modePeche and ns.canneManque(GetBuildInfo and select(4, GetBuildInfo()) or nil, GetInventoryItemID and GetInventoryItemID("player", 16),
            (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant) then
          ns.reglages.dire("|cffff4040aucune canne à pêche équipée|r : le jeu refuse de lancer la ligne. Équipe ta canne, ou enregistre une tenue « Pêche » avec /tenue.")
        end
      end)
    end
    local touche = db.pecheTouche and texteCombo(db.touchePeche) or nil
    ns.reglages.dire("mode pêche |cff00ff00activé|r : double clic droit pour lancer, clic droit sur le bouchon pour ferrer"
      .. (touche and (", ou la touche |cff00ff00" .. touche .. "|r pour tout faire.") or "."))
    majAppat()
    if db.pecheFenetre then montrerFenetrePeche(true) end
  else
    sonNormal()
    if not InCombatLockdown() then ClearOverrideBindings(lancer) end
    remettreFerrage()
    -- Addon Tenues (facultatif) : remet la tenue d'avant la pêche.
    if Tenues_ModePeche then pcall(Tenues_ModePeche, false) end
    ns.reglages.dire("mode pêche |cffff4040terminé|r, son remis comme avant.")
    montrerFenetrePeche(false)
  end
  appliquerTouche()
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

-- Toutes les 2 secondes en mode pêche : l'appât qui va finir, et la touche revue
-- (elle ne change que si la situation a changé).
C_Timer.NewTicker(2, function()
  if not modePeche or not db then return end
  verifierAppat()
  -- Si le jeu n'a pas signalé la fin du lancer, on relit l'état réel : la touche ne reste pas sur « ferrer ».
  local enCours = canalEnCours()
  if ligneAEau and not enCours then ligneAEau = false end
  appliquerTouche()
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
  return texteCombo(GetBindingKey and GetBindingKey(action))
end
local function toucheInteraction() return texteTouche("INTERACTTARGET") end

-- Choisir la touche depuis les réglages : on écoute la prochaine touche
-- appuyée. Pour la récolte, on la relie à « Interagir avec la cible » comme le
-- ferait Échap > Options > Raccourcis ; pour la pêche, on la garde dans nos
-- réglages (elle n'est reliée qu'en mode pêche). Échap annule. Interdit en combat.
local MODIFICATEURS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
  LALT = true, RALT = true, LMETA = true, RMETA = true }
local capture = CreateFrame("Frame", nil, UIParent)
capture:Hide()
capture:EnableKeyboard(true)
if capture.SetPropagateKeyboardInput then capture:SetPropagateKeyboardInput(false) end
capture:SetScript("OnKeyDown", function(self, key)
  if MODIFICATEURS[key] then return end
  self:Hide()
  local cible = self.cible
  self.cible = nil
  if key == "ESCAPE" then
    ns.reglages.dire("choix de la touche annulé.")
    if self.apres then self.apres() end
    return
  end
  local combo = ns.comboTouche(key, IsAltKeyDown(), IsControlKeyDown(), IsShiftKeyDown())
  if cible == "peche" then
    db.touchePeche = combo
    ns.reglages.appliquer()
    ns.reglages.dire("touche de pêche : |cff00ff00" .. (texteCombo(combo) or combo)
      .. "|r. Elle sert en mode pêche, hors combat.")
  elseif SetBinding(combo, "INTERACTTARGET") then
    SaveBindings(GetCurrentBindingSet())
    ns.reglages.dire("« Interagir avec la cible » est maintenant sur |cff00ff00" .. (toucheInteraction() or combo) .. "|r.")
  else
    ns.reglages.dire("|cffff4040impossible d'utiliser cette touche.|r")
  end
  if self.apres then self.apres() end
end)

-- Renvoie vrai quand l'écoute de la touche a démarré. cible : « peche » pour la
-- touche de pêche, rien pour la touche de récolte.
choisirTouche = function(apres, cible)
  if InCombatLockdown() then ns.reglages.dire("|cffff4040pas en combat.|r") return false end
  capture.apres = apres
  capture.cible = cible
  capture:Show()
  ns.reglages.dire("appuie sur la touche voulue pour " .. (cible == "peche" and "pêcher" or "récolter")
    .. " (Échap pour annuler).")
  return true
end

-- « Filon pas fini » : un addon n'a pas le droit de continuer la récolte à ta
-- place (ce serait un bot). Il peut en revanche te PRÉVENIR : après le butin,
-- si l'objet récolté est toujours devant toi, c'est qu'il reste des coups.
local objetRecolte -- GUID du filon ou de l'herbe dont le butin est ouvert

local function guidSur(unite)
  local g = UnitGUID(unite)
  if estSecret(g) then return nil end
  return g
end

local function surButinOuvert()
  objetRecolte = nil
  if not db.actif or not GetLootSourceInfo then return end
  if IsFishingLoot and IsFishingLoot() then return end -- le bouchon n'est pas un filon
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

-- Remet la flèche, la liste de courses et la fenêtre Pêche à leur place d'origine. Faux en combat.
local function replacerFenetres()
  if InCombatLockdown() then return false end
  db.positionFleche, db.positionCourses, db.positionPeche = nil, nil, nil
  placerFleche()
  placerCourses()
  placerPeche()
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
      aide = "En plus de l'icône commune « Mes addons ». Clic droit : activer ou couper." },
    { titre = "Pêche" },
    { cle = "pecheDoubleClic", libelle = "Double clic droit pour lancer la ligne",
      aide = "Seulement en mode pêche. Pour ferrer : clic droit sur le bouchon." },
    { cle = "pecheAuto", libelle = "Mode pêche dès que tu pêches toi-même",
      aide = "Il s'arrête seul après 60 secondes sans pêcher, ou en combat." },
    { cle = "pecheSon", libelle = "Bien entendre le bouchon",
      aide = "En mode pêche : effets sonores à fond, musique et ambiance coupées. Tout revient comme avant à la fin." },
    { cle = "pecheTouche", libelle = "Une seule touche pour pêcher",
      aide = "En mode pêche et hors combat : la touche lance la ligne, puis ferre le bouchon. Elle se choisit dans l'onglet Outils. En combat, ou hors mode pêche, elle reprend son rôle normal. Les réglages du jeu changés pour ferrer sont remis à la fin." },
    { cle = "pecheAppat", libelle = "La touche pose d'abord l'appât", dependDe = "pecheTouche",
      aide = "Si ta canne n'a pas d'appât, un appui pose le meilleur appât de tes sacs que ta compétence permet, puis les appuis suivants lancent la ligne." },
    { cle = "pecheFenetre", libelle = "Fenêtre Pêche avec le mode pêche",
      aide = "Compétence, appât et temps restant, lancers, prises, prises par heure, valeur de revente et liste des prises. Elle s'ouvre et se ferme avec le mode pêche. Déplace-la en la glissant." },
    { cle = "pecheRamasser", libelle = "Ramasser tout de suite les prises",
      aide = "Le butin de pêche va directement dans tes sacs. Ton réglage général de ramassage n'est pas touché." },
    { cle = "rachatPalier", type = "nombre", libelle = "Racheter des appâts chez un marchand",
      min = 0, max = 3, pas = 1, format = ns.texteRachat,
      aide = "COUPÉ au départ : cela dépense ton or. Chez un marchand qui vend des appâts, rachète le meilleur que ta compétence permet jusqu'à ce nombre, et dit dans le chat ce qui a été acheté et pour combien." },
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

    -- La touche unique de pêche et la fenêtre Pêche.
    local toucheUnique = texteFixe(20, y - 5, 230)
    local b4
    b4 = ns.creerBouton(fenetre, "Choisir la touche de pêche",
      "Appuie ensuite sur la touche voulue : en mode pêche et hors combat, elle lance la ligne, ferre le bouchon et pose l'appât. Échap annule. Impossible en combat.",
      function()
        if choisirTouche(function() maj() end, "peche") then b4:SetText("Appuie sur une touche…") end
      end, 190)
    b4:SetPoint("TOPLEFT", 254, y)
    y = y - 34
    local b5 = ns.creerBouton(fenetre, "Montrer ou cacher la fenêtre Pêche",
      "Ouvre la fenêtre Pêche à la main, par exemple pour la placer. Elle s'ouvre aussi toute seule avec le mode pêche.",
      function() MetiersAuto_FenetrePeche() end, 250)
    b5:SetPoint("TOPLEFT", 16, y)
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
    local b3 = ns.creerBouton(fenetre, "Replacer les fenêtres",
      "Remet la flèche, la liste de courses et la fenêtre Pêche à leur place d'origine, par exemple si l'une est sortie de l'écran.",
      function()
        if replacerFenetres() then r.dire("flèche, liste de courses et fenêtre Pêche remises à leur place.")
        else r.dire("|cffff4040pas en combat.|r") end
      end, 220)
    b3:SetPoint("TOPLEFT", 16, y)
    y = y - 34

    -- La liste de courses : on y retire une ligne ou tout ; l'ajout se fait en jeu.
    local aide = fenetre:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    aide:SetPoint("TOPLEFT", 20, y - 2)
    aide:SetWidth(380)
    aide:SetJustifyH("LEFT")
    aide:SetText("Pour ajouter une recette : ouvre ton métier, tape /metiers courses 5 (5 = le nombre à fabriquer), puis Maj+clic sur la recette.")
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
      local ku = texteCombo(db.touchePeche)
      toucheUnique:SetText("Touche de pêche : " .. (ku and ("|cff00ff00" .. ku .. "|r") or "|cffff4040aucune|r"))
      b4:SetText(ku and "Changer la touche de pêche" or "Choisir la touche de pêche")
      local carte = ici()
      filons:SetText(ns.texteFilons(carte and nbFilons(carte) or nil, totalFilons()))
      if carte and nbFilons(carte) > 0 then b2:Enable() else b2:Disable() end
      majListe()
    end
    return y, maj
  end,
  astuce = "Tout s'applique tout de suite, sans /reload. Le raccourci du mode pêche se choisit dans Échap > Options > Raccourcis ; la touche unique de pêche, dans l'onglet Outils. Commande : /metiers.",
  auChargement = function(d)
    db = d
    -- Un mode pêche coupé par une déconnexion : on remet le son d'avant, et les
    -- réglages du jeu changés pour ferrer.
    sonNormal()
    remettreFerrage()
    placerCourses()
    placerFleche()
    placerPeche()
  end,
  surChangement = function(d)
    if not d.actif and modePeche then changerModePeche(false) end
    if modePeche then
      if d.pecheSon then sonPeche() else sonNormal() end
      if not d.pecheFenetre then montrerFenetrePeche(false) end
    end
    appliquerCVars()
    remettreReperage()
    majCourses()
    majAppat()
    appliquerTouche()
    if majPeche then majPeche() end
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
-- Les évènements de la pêche facilitée : un nom inconnu de cette version du jeu est ignoré.
for _, e in ipairs({ "PLAYER_REGEN_ENABLED", "LOOT_READY", "UI_ERROR_MESSAGE", "UI_INFO_MESSAGE",
                     "MERCHANT_SHOW", "PLAYER_EQUIPMENT_CHANGED", "SKILL_LINES_CHANGED", "PLAYER_LOGOUT" }) do
  pcall(ecouteur.RegisterEvent, ecouteur, e)
end
for _, e in ipairs({ "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_INVENTORY_CHANGED" }) do
  pcall(ecouteur.RegisterUnitEvent, ecouteur, e, "player")
end

-- Le sort qui vient de partir ou de s'arrêter est-il la pêche ? Une valeur cachée par le
-- jeu ne se lit pas : en mode pêche, on la prend pour la pêche.
local function estSortPeche(idSort)
  if idSort == nil then return false end
  if estSecret(idSort) then return modePeche end
  return PECHE[idSort] == true
end

ecouteur:SetScript("OnEvent", function(_, evenement, a1, a2, a3)
  if not db then return end
  if evenement == "PLAYER_REGEN_DISABLED" then
    appliquee = nil -- la touche vient d'être retirée par le cadre sécurisé
    if modePeche then changerModePeche(false) end
  elseif evenement == "PLAYER_REGEN_ENABLED" then
    -- Tout ce qui attendait la fin du combat.
    if db.ferrageAvant and not modePeche then remettreFerrage() end
    if db.sonAvant and not modePeche then sonNormal() end
    majAppat()
    appliquerTouche(true)
    if fenetreEnAttente ~= nil then montrerFenetrePeche(fenetreEnAttente) end
  elseif evenement == "UNIT_SPELLCAST_CHANNEL_START" then
    if a1 == "player" and estSortPeche(a3) then
      derniereActivite = GetTime()
      ligneAEau = true
      if db.actif then ns.compterLancer(session, GetTime()) end
      if db.actif and db.pecheAuto and not modePeche then changerModePeche(true) end
      appliquerTouche()
      if majPeche then majPeche() end
    end
  elseif evenement == "UNIT_SPELLCAST_CHANNEL_STOP" then
    if a1 == "player" and estSortPeche(a3) then
      derniereActivite = GetTime()
      ligneAEau = false
      appliquerTouche()
      if majPeche then majPeche() end
    end
  elseif evenement == "LOOT_READY" then
    surButinPeche()
  elseif evenement == "LOOT_OPENED" then
    surButinOuvert()
    surButinRecolte()
    surButinPeche()
  elseif evenement == "LOOT_CLOSED" then
    butinPecheVu = false
    surButinFerme()
  elseif evenement == "UI_ERROR_MESSAGE" or evenement == "UI_INFO_MESSAGE" then
    if db.actif and ns.estMessageEchappe(a1, a2, ERR_FISH_ESCAPED) then
      ns.compterEchappe(session)
      if majPeche then majPeche() end
    end
  elseif evenement == "MERCHANT_SHOW" then
    C_Timer.After(0.3, function() pcall(racheterAppats) end)
  elseif evenement == "UNIT_INVENTORY_CHANGED" or evenement == "PLAYER_EQUIPMENT_CHANGED"
      or evenement == "SKILL_LINES_CHANGED" then
    majAppat()
    appliquerTouche()
    if majPeche then majPeche() end
  elseif evenement == "PLAYER_LOGOUT" then
    remettreFerrage()
  elseif evenement == "BAG_UPDATE_DELAYED" or evenement == "GET_ITEM_INFO_RECEIVED" then
    if #db.courses > 0 then majCourses() end
    if evenement == "BAG_UPDATE_DELAYED" then
      majAppat()
      appliquerTouche()
      if majPeche then majPeche() end
    end
  else
    appliquerCVars()
    remettreReperage()
    if evenement == "PLAYER_ENTERING_WORLD" then
      ligneAEau = canalEnCours()
      majCourses()
      majAppat()
    end
  end
end)

-- ---------------------------------------------------------------------------
-- Commande /metiers
-- ---------------------------------------------------------------------------

-- Pas « /mt » : le jeu garde /mt pour « tank principal » et passe avant nous (vu en jeu le 13/11).
SLASH_METIERSAUTO1 = "/metiers"
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
  elseif cmd == "touche" then
    if reste == "" then
      local k = texteCombo(db.touchePeche)
      return r.dire(k and ("touche de pêche : " .. k .. ". /metiers touche aucune : la retirer.")
        or "aucune touche de pêche. Tape par exemple /metiers touche F, ou utilise le bouton de l'onglet Outils.")
    end
    if reste:lower() == "aucune" then
      db.touchePeche = nil
      r.appliquer()
      return r.dire("touche de pêche retirée.")
    end
    local t = ns.toucheValide(reste)
    if not t then return r.dire("touche non reconnue : tape par exemple /metiers touche F ou /metiers touche SHIFT-F.") end
    db.touchePeche = t
    r.appliquer()
    r.dire("touche de pêche : |cff00ff00" .. (texteCombo(t) or t) .. "|r. Elle sert en mode pêche, hors combat.")
  elseif cmd == "fenetre" or cmd == "fenêtre" then
    MetiersAuto_FenetrePeche()
  elseif cmd == "session" then
    if reste:lower() == "vider" then
      session = ns.nouvelleSession()
      if majPeche then majPeche() end
      return r.dire("session de pêche remise à zéro.")
    end
    r.dire(string.format("session de pêche : %d lancers, %d prises, %d échappés, %s par heure, valeur de revente %s. /metiers session vider : remettre à zéro.",
      session.lancers, session.prises, session.echappes, ns.textePrisesParHeure(ns.prisesParHeure(session, GetTime())),
      ns.texteArgent(ns.valeurSession(session, prixVente))))
  elseif cmd == "appats" or cmd == "appâts" then
    local palier = ns.palierDeNombre(tonumber(reste))
    if reste == "" then
      return r.dire("rachat d'appâts : " .. ns.texteRachat(db.rachatPalier):lower() .. ". /metiers appats 0, 5, 10 ou 20.")
    end
    if not palier then return r.dire("choisis 0 (aucun), 5, 10 ou 20 : /metiers appats 5.") end
    r.changer("rachatPalier", palier)
    r.dire("rachat d'appâts chez les marchands : " .. ns.texteRachat(palier):lower() .. ".")
  elseif cmd == "filons" then
    if reste:lower() == "oublier" then
      return r.dire(oublierCarte() and "endroits oubliés pour cette carte."
        or "position inconnue ici (donjon, ou position cachée par le jeu).")
    end
    local cartes = 0
    for _ in pairs(db.filons) do cartes = cartes + 1 end
    local carte = ici()
    r.dire(string.format("%s, sur %d cartes. /metiers filons oublier : vider cette carte.",
      ns.texteFilons(carte and nbFilons(carte) or nil, totalFilons()), cartes))
  elseif cmd == "courses" then
    if reste:lower() == "vider" then
      r.changer("courses", {})
      return r.dire("liste de courses vidée.")
    end
    local nombre, recette = ns.lireRecette(reste)
    if not recette then
      return r.dire("ouvre ton métier, tape /metiers courses 5 puis Maj+clic sur la recette.")
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
    r.dire("/metiers : réglages     /metiers peche : mode pêche     /metiers on, /metiers off")
    r.dire("/metiers touche F : la touche unique de pêche (/metiers touche aucune)     /metiers fenetre : fenêtre Pêche")
    r.dire("/metiers session : bilan de la pêche (/metiers session vider)     /metiers appats 0, 5, 10 ou 20 : rachat d'appâts")
    r.dire("/metiers courses 5 <recette> : ajouter (Maj+clic sur la recette)     /metiers courses vider")
    r.dire("/metiers filons : endroits de récolte connus     /metiers filons oublier")
  end
end
