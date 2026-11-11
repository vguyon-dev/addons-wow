-- ============================================================================
-- Reglages.lua : LA fenêtre de réglages de tous les addons de Valentin.
--
-- Fichier COMMUN : la même copie se trouve dans chaque addon du dépôt
-- (QuetesAuto, MarchandAuto…). Si tu le modifies, recopie-le dans les autres
-- (un test vérifie qu'ils sont identiques).
--
-- Une seule fenêtre « Addons de Valentin » (créée par le premier addon chargé) :
--   - à gauche, la liste des addons avec un point vert (activé) ou rouge (coupé) ;
--     clic = ses réglages, clic droit = activer ou couper, Maj+clic = son panneau ;
--   - à droite, la page de l'addon : interrupteur général, un onglet par
--     section, des interrupteurs et des curseurs, les boutons d'action en bas ;
--   - en haut, une recherche qui trouve un réglage dans tous les addons.
--   - tout en haut de la liste, « Quoi de neuf » : une page (pas un addon : ni point ni
--     interrupteur) qui montre ns.NOUVEAUTES. Chaque addon garde dans sa sauvegarde la date
--     de la dernière nouveauté vue (db.nouveautesVues) ; s'il y en a une plus récente, un
--     seul message au chat à la connexion et une pastille dorée sur l'entrée, jusqu'à
--     l'ouverture de la page. Pour annoncer du neuf : une entrée EN TÊTE de ns.NOUVEAUTES,
--     avec la date du jour.
--   - sous « Quoi de neuf », « Partager mes réglages » : un texte à copier (tous les réglages des
--     addons chargés, seulement les clés de p.options, interrupteurs et nombres, au format
--     « VA1;Addon:cle=valeur,… ») et un champ où coller celui d'un ami (bouton « Appliquer », qui
--     passe par r.changer) ;
--   - en haut de la page de chaque addon, l'interrupteur « Réglages propres à ce personnage » :
--     la table sauvegardée garde db.compte (réglages communs) et db.parPerso["Nom-Royaume"]
--     (réglages propres) à côté de ses clés à plat (db.cle, que les addons lisent comme avant) ;
--     au chargement, db reçoit les valeurs du bon profil, et chaque r.appliquer les y réécrit.
--     Seules les clés déclarées dans p.options sont concernées (pas les positions ni les listes).
--
-- Utilisation, dans le fichier principal de l'addon :
--   local reglages = ns.creerReglages({
--     titre = "Mon addon",                      -- nom affiché
--     icone = "Interface\\Icons\\…",
--     nomDB = "MonAddonDB",                     -- SavedVariables du .toc
--     defauts = { actif = true, … },            -- valeurs de départ
--     options = {
--       { titre = "Section" },                                 -- un onglet
--       { cle = "x", libelle = "…", aide = "…" },              -- interrupteur
--       { cle = "x", libelle = "…", dependDe = "y" },          -- grisé si y est coupé
--       { cle = "x", libelle = "…", dependDe = "!y" },         -- grisé si y est activé
--       { cle = "x", libelle = "…", dispo = fonction },        -- grisé si la fonction rend faux
--       { cle = "n", type = "nombre", libelle = "…", min = 0, max = 20, pas = 1 }, -- curseur
--     },
--     boutons = { { texte = "…", aide = "…", action = fonction }, … }, -- en bas de la page
--     ouvrirHub = fonction, texteHub = "…",     -- le panneau de l'addon : un bouton en bas
--                                               -- de la page et Maj+clic dans la liste
--     contenu = function(f, y, r) … return y, maj end, -- facultatif : un onglet en plus
--     ongletContenu = "Listes",                 -- le nom de cet onglet (« Détails » sinon)
--     astuce = "texte sous le premier onglet",  -- facultatif
--     auChargement = function(db) … end,        -- quand les réglages sont lus
--     surChangement = function(db) … end,       -- après chaque changement
--   })
-- Quand l'addon a une option « actif », les autres sont grisées tant qu'il est
-- coupé (sauf « minimap » et les options marquées toujours = true).
-- Tout s'applique tout de suite, sans /reload.
--
-- ns.creerListe(parent, y, spec) : une liste d'objets éditable (retrait d'une
-- ligne, dépôt d'un objet du sac), à utiliser dans contenu().
-- ============================================================================

local NOM_ADDON, ns = ...

local function nombre(v, defaut) return type(v) == "number" and v or defaut end

local LARGEUR, HAUTEUR, COTE, PAGE = 790, 570, 200, 540
local FOND = { bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } }

-- ============================================================ l'habillage commun
-- Le visuel « sombre et doré » de toutes les fenêtres propres aux addons.

local HABILLAGE = {
  fond = { 0.07, 0.06, 0.045, 0.96 },
  bordure = { 0.80, 0.63, 0.30, 1 },
  couleurTitre = { 1, 0.82, 0.30 },
}

-- Ce que ns.habiller va appliquer, options facultatives comprises (fonction pure,
-- testée hors jeu). options : titre = "…", fermer = vrai, trait = faux pour
-- sans filet doré sous le titre, fond = { r, v, b, a }, bordure = { r, v, b, a }.
function ns.styleHabillage(options)
  options = type(options) == "table" and options or {}
  local function couleur(c, defaut, avecAlpha)
    if type(c) ~= "table" then c = defaut end
    local r, v, b = nombre(c[1], defaut[1]), nombre(c[2], defaut[2]), nombre(c[3], defaut[3])
    if avecAlpha then return { r, v, b, nombre(c[4], defaut[4] or 1) } end
    return { r, v, b }
  end
  local titre = type(options.titre) == "string" and options.titre ~= "" and options.titre or nil
  return {
    fond = couleur(options.fond, HABILLAGE.fond, true),
    bordure = couleur(options.bordure, HABILLAGE.bordure, true),
    couleurTitre = couleur(options.couleurTitre, HABILLAGE.couleurTitre, false),
    titre = titre,
    fermer = options.fermer and true or false,
    trait = titre ~= nil and options.trait ~= false,
  }
end

-- Habille un cadre : fond sombre, bordure dorée et, si on les demande, un titre doré
-- et une croix de fermeture. Un cadre sans SetBackdrop (créé sans BackdropTemplate)
-- reçoit un enfant BackdropTemplate en fond. Renvoie le titre et la croix (ou nil) :
-- l'appelant peut donner son propre OnClick à la croix.
-- Rien d'autre n'est touché : ni position, ni scripts, ni taille.
function ns.habiller(cadre, options)
  if not cadre then return end
  local s = ns.styleHabillage(options)

  local cible = cadre
  if not cadre.SetBackdrop then
    cible = cadre.fondHabille
    if not cible and BackdropTemplateMixin then
      local ok, enfant = pcall(CreateFrame, "Frame", nil, cadre, "BackdropTemplate")
      if ok and enfant then
        enfant:SetAllPoints(cadre)
        local niveau = cadre.GetFrameLevel and cadre:GetFrameLevel() or 1
        enfant:SetFrameLevel(math.max(niveau - 1, 0))
        enfant:EnableMouse(false)
        cadre.fondHabille = enfant
        cible = enfant
      end
    end
  end
  if cible and cible.SetBackdrop then
    cible:SetBackdrop(FOND)
    cible:SetBackdropColor(s.fond[1], s.fond[2], s.fond[3], s.fond[4])
    cible:SetBackdropBorderColor(s.bordure[1], s.bordure[2], s.bordure[3], s.bordure[4])
  end

  local titre, fermer
  if s.titre then
    titre = cadre.titreHabille
    if not titre then
      titre = cadre:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
      titre:SetPoint("TOPLEFT", 12, -8)
      cadre.titreHabille = titre
    end
    titre:SetText(s.titre)
    titre:SetTextColor(s.couleurTitre[1], s.couleurTitre[2], s.couleurTitre[3])
    if s.trait and not cadre.traitHabille then
      local trait = cadre:CreateTexture(nil, "ARTWORK")
      trait:SetColorTexture(s.bordure[1], s.bordure[2], s.bordure[3], 0.6)
      trait:SetPoint("TOPLEFT", 6, -27)
      trait:SetPoint("TOPRIGHT", -6, -27)
      trait:SetHeight(1)
      cadre.traitHabille = trait
    end
  end
  if s.fermer then
    fermer = cadre.fermerHabille
    if not fermer then
      fermer = CreateFrame("Button", nil, cadre, "UIPanelCloseButton")
      fermer:SetSize(22, 22)
      fermer:SetPoint("TOPRIGHT", -2, -2)
      fermer:SetScript("OnClick", function() cadre:Hide() end)
      cadre.fermerHabille = fermer
    end
  end
  return titre, fermer
end

-- Recherche sans accents ni majuscules.
local ACCENTS = { ["à"] = "a", ["â"] = "a", ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e", ["î"] = "i",
  ["ï"] = "i", ["ô"] = "o", ["ù"] = "u", ["û"] = "u", ["ç"] = "c", ["É"] = "e", ["À"] = "a", ["Ê"] = "e",
  ["È"] = "e", ["Ç"] = "c", ["Î"] = "i", ["Ô"] = "o", ["Â"] = "a", ["Ù"] = "u", ["Û"] = "u", ["œ"] = "oe" }
local function simple(t)
  t = tostring(t or "")
  for a, b in pairs(ACCENTS) do t = t:gsub(a, b) end
  return t:lower()
end
ns.simpleRecherche = simple

-- Les réglages qui contiennent le texte cherché.
--   entrees : { { titre, recherche = { { libelle, aide, section, onglet } } } }
-- Renvoie { { entree, item } } (fonction pure, testée hors jeu).
function ns.chercherReglages(entrees, texte)
  local q = simple(texte)
  local resultats = {}
  if q == "" then return resultats end
  for _, e in ipairs(entrees) do
    for _, item in ipairs(e.recherche or {}) do
      if simple(item.libelle .. " " .. (item.aide or "") .. " " .. e.titre):find(q, 1, true) then
        resultats[#resultats + 1] = { entree = e, item = item }
      end
    end
  end
  return resultats
end


-- ============================================================ quoi de neuf
-- Les nouveautés, les plus récentes d'abord. Une date par entrée (AAAA-MM-JJ) :
-- chaque addon retient dans sa sauvegarde la date de la dernière nouveauté vue.
-- Pour annoncer quelque chose de nouveau, ajouter une entrée EN TÊTE avec la date du jour
-- (une date plus récente que toutes les autres, sinon rien n'est annoncé).
ns.NOUVEAUTES = {
  { date = "2026-11-11", titre = "Deux nouveaux addons : Dialogues de quête et Tenues", lignes = {
    "Dialogues de quête : quand tu parles à un PNJ, un bandeau en bas de l'écran remplace la fenêtre du jeu, avec le portrait du PNJ et son texte par morceaux. Espace avance ou accepte, les chiffres choisissent une réponse ou une récompense, Échap ferme. Réglages : /dial.",
    "Si le bandeau a un souci, la fenêtre du jeu reprend la main toute seule. Le bouton « Fenêtre du jeu » te la rend quand tu veux. Pense à désactiver Immersion si tu l'utilises.",
    "Tenues : enregistre ce que tu portes sous un nom (combat, pêche, ville), puis change de tenue d'un clic ou d'une touche. Ouvre la fenêtre avec /tenue. En combat, la tenue est mise à la fin du combat.",
    "Métiers auto met ta tenue « Pêche » quand tu actives le mode pêche, et remet la précédente quand tu le coupes.",
  } },
  { date = "2026-11-10", titre = "Nouvel addon : Suivi des quêtes", lignes = {
    "Suivi des quêtes remplace le suivi des objectifs du jeu par un panneau rangé en sections : À rendre (tout en haut), Principal, Général, Donjons et groupe, Classe, Métiers, JcJ, Journalières et répétables. Réglages : /sq.",
    "Chaque section se replie. Dans une section, les quêtes de ta zone passent d'abord, puis les plus proches. Clic gauche : choisir la quête (le GPS la suit). Maj + clic : ne plus la suivre.",
    "Clic droit sur une quête : la ranger toi-même dans une autre section, et ce choix est gardé. Les objets de quête à utiliser ont leur bouton à gauche du panneau.",
  } },
  { date = "2026-11-10", titre = "Nouvel addon : Conseiller", lignes = {
    "Conseiller lit ta classe, ta spécialisation, ta race, ton niveau et ta situation (seul, en groupe, donjon ou raid) et te conseille. Ouvre-le avec /conseil ou /cs.",
    "Talents : la spécialisation conseillée et pourquoi, et ce qu'il manque à ton groupe (tank ou soigneur). Rotation : un contour bleu sur ta barre d'action marque le prochain sort à lancer (Chasseur et Paladin pour commencer).",
    "Équipement : l'ordre des statistiques de ta spécialisation. Métiers : trois propositions pour ta classe et ce qu'il te reste à faire. Race : tes capacités de race utiles.",
  } },
  { date = "2026-11-10", titre = "Huit améliorations d'un coup", lignes = {
    "Tous les addons ont le même visuel sombre et doré : fond sombre, bordure dorée, titre doré.",
    "Marchand auto peut vendre en plus l'équipement lié que ta classe ne peut pas porter. Jamais un objet épique, jamais un objet de ta liste à garder. Option coupée au départ.",
    "Sacs rangés : la banque aussi se range par catégories, dans une seconde fenêtre à gauche du sac.",
    "Enchères : quand tu déposes un objet à vendre, un prix conseillé s'affiche et un bouton le met dans le champ du jeu. C'est toujours toi qui valides la vente.",
    "Courrier : des destinataires rapides (tes autres personnages, tes derniers destinataires) et un bilan dans le chat à la fin d'une récupération.",
    "GPS : tu peux envoyer tes balises à ton groupe, et accepter celles de ton groupe.",
    "Cette page « Quoi de neuf » : quand il y a du nouveau, un message le dit une seule fois dans le chat, et un point doré reste sur « Quoi de neuf » tant que tu n'as pas ouvert la page.",
    "Partager tes réglages : sous « Quoi de neuf », la page « Partager mes réglages » donne un texte à copier pour un ami, et un champ pour coller celui qu'on t'envoie. Les listes (objets ignorés, balises, courses) ne sont pas partagées.",
    "Réglages propres à chaque personnage : en haut de la page de chaque addon, un interrupteur « Réglages propres à ce personnage ». Activé, ce personnage a ses réglages (copiés depuis les réglages actuels) et les autres ne changent pas. Coupé, il retrouve ceux du compte.",
  } },
  { date = "2026-11-10", titre = "Une seule fenêtre de réglages", lignes = {
    "Les réglages des 21 addons sont dans une seule fenêtre, « Addons de Valentin », ouverte par l'engrenage autour de la minimap ou par la commande de chaque addon.",
    "À gauche, la liste des addons avec un point vert (activé) ou rouge (coupé). Un clic droit active ou coupe un addon.",
    "À droite, les réglages de l'addon choisi, rangés en onglets, avec des interrupteurs et des curseurs.",
    "En haut, une recherche trouve un réglage dans tous les addons, même sans les accents.",
  } },
  { date = "2026-11-09", titre = "Trois nouveaux addons", lignes = {
    "Montures : une seule touche pour monter la bonne monture (volante, aquatique ou terrestre). Réappuie pour descendre.",
    "Confort : accepte tout seul les invocations, les résurrections et les invitations de tes amis et de ta guilde, refuse les duels, et masque ce qui gêne l'écran.",
    "Familier du chasseur : une alerte avec le bon bouton quand le familier a faim, est mort ou n'est pas appelé.",
  } },
  { date = "2026-11-09", titre = "Barres de vie et GPS", lignes = {
    "Barres de vie : un grand « ! » et ta progression (par exemple 2/6) au-dessus des monstres de tes quêtes, avec l'icône de l'objet à ramasser.",
    "GPS : la flèche est plus grosse, sa taille se règle, et sans balise elle suit la quête suivie ou l'épingle posée sur la carte.",
  } },
  { date = "2026-11-08", titre = "Sac rangé par catégories et conseils d'équipement", lignes = {
    "Sacs rangés peut remplacer tes sacs par une seule fenêtre en sections : équipement, consommables, composants, métiers, quêtes, divers, ce que tu ne peux pas porter, et ce qui est à vendre.",
    "La bulle de chaque objet dit pourquoi il est rangé là, et une flèche rouge marque l'équipement moins bon que ce que tu portes.",
    "Conseils d'équipement : les objets meilleurs pour ta spécialisation passent en tête avec une flèche verte et la raison, et une ligne verte s'ajoute dans les bulles d'objets.",
  } },
  { date = "2026-11-08", titre = "GPS, Courrier et Enchères", lignes = {
    "GPS : des balises avec /way, ou Ctrl + clic droit sur la carte, et une flèche avec la distance et le temps restant.",
    "Courrier : « Tout récupérer », « Or seulement » ou les courriers cochés, sans jamais payer un contre-remboursement.",
    "Enchères : le relevé des prix, les prix dans les bulles d'objets et une liste de courses.",
  } },
}

local function dateNouveaute(d) return type(d) == "string" and d:match("^%d%d%d%d%-%d%d%-%d%d$") ~= nil end

-- La date de la nouveauté la plus récente (nil s'il n'y en a pas).
function ns.derniereNouveaute(liste)
  local derniere
  for _, n in ipairs(type(liste) == "table" and liste or {}) do
    if type(n) == "table" and dateNouveaute(n.date) and (not derniere or n.date > derniere) then derniere = n.date end
  end
  return derniere
end

-- Y a-t-il une nouveauté plus récente que la dernière date vue ? Une date absente ou
-- abîmée veut dire « rien vu » : tout est nouveau.
function ns.ilYADuNeuf(liste, vue)
  local derniere = ns.derniereNouveaute(liste)
  if not derniere then return false end
  if not dateNouveaute(vue) then return true end
  return derniere > vue
end

-- « 2026-11-10 » devient « 10/11/2026 ».
function ns.dateLisible(d)
  if not dateNouveaute(d) then return tostring(d or "") end
  return d:sub(9, 10) .. "/" .. d:sub(6, 7) .. "/" .. d:sub(1, 4)
end

-- La plus ancienne date vue parmi une liste de dates : les addons sans date valide sont ignorés,
-- nil si aucune n'est connue (alors tout est marqué « nouveau »).
function ns.plusAncienneDate(dates)
  local ancienne
  for _, v in ipairs(type(dates) == "table" and dates or {}) do
    if dateNouveaute(v) and (not ancienne or v < ancienne) then ancienne = v end
  end
  return ancienne
end

-- Le texte de la page : un titre doré par nouveauté, ses lignes en dessous.
-- Avec « vue », ce qui est plus récent que cette date est marqué « nouveau ».
-- Sans date vue (ou date abîmée), tout est marqué « nouveau ».
function ns.texteNouveautes(liste, vue)
  local morceaux = {}
  local vueOk = dateNouveaute(vue)
  for _, n in ipairs(type(liste) == "table" and liste or {}) do
    if type(n) == "table" and dateNouveaute(n.date) then
      local marque = (not vueOk or n.date > vue) and "  |cff3ddc3d[nouveau]|r" or ""
      local bloc = { "|cffffd200" .. tostring(n.titre or "") .. "|r  |cff888888" .. ns.dateLisible(n.date) .. "|r" .. marque }
      for _, ligne in ipairs(type(n.lignes) == "table" and n.lignes or {}) do bloc[#bloc + 1] = "- " .. tostring(ligne) end
      morceaux[#morceaux + 1] = table.concat(bloc, "\n")
    end
  end
  if #morceaux == 0 then return "Rien de nouveau pour l'instant." end
  return table.concat(morceaux, "\n\n")
end

-- ============================================================ partage et profils des réglages
-- Tout ce qui suit est de la logique pure (testée hors jeu) : le texte à partager avec un ami
-- et les réglages propres à chaque personnage. Seules les clés déclarées dans p.options
-- comptent, avec des valeurs booléennes ou des nombres : jamais les positions ni les listes.

local function valeurSimple(v)
  return type(v) == "boolean" or (type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge)
end
ns.valeurSimple = valeurSimple

-- Les clés déclarées dans la liste d'options d'un addon, dans l'ordre et sans doublon.
function ns.clesReglages(options)
  local cles, vues = {}, {}
  for _, opt in ipairs(type(options) == "table" and options or {}) do
    if type(opt) == "table" and type(opt.cle) == "string" and opt.cle ~= "" and not vues[opt.cle] then
      vues[opt.cle] = true
      cles[#cles + 1] = opt.cle
    end
  end
  return cles
end

-- Une copie des valeurs simples de ces clés : { cle = valeur }.
function ns.copierReglages(source, cles)
  local copie = {}
  if type(source) ~= "table" then return copie end
  for _, cle in ipairs(cles) do
    if valeurSimple(source[cle]) then copie[cle] = source[cle] end
  end
  return copie
end

-- « Nom-Royaume » : la clé d'un personnage (nil si le jeu ne donne pas encore son nom).
function ns.nomProfil(nom, royaume)
  if type(nom) ~= "string" or nom == "" then return nil end
  return nom .. "-" .. (type(royaume) == "string" and royaume or "")
end

-- ------------------------------------------------------- réglages propres à un personnage
-- La sauvegarde de l'addon garde sa table de travail à plat (db.cle, lue partout par les
-- addons) et deux tables à côté : db.compte = { cle = valeur } (réglages communs) et
-- db.parPerso = { ["Nom-Royaume"] = { cle = valeur } } (réglages propres). Un personnage
-- qui a une entrée dans parPerso est en mode « perso », les autres suivent le compte.

-- Ce personnage a-t-il ses réglages propres ?
function ns.modePerso(db, moi)
  return moi ~= nil and type(db) == "table" and type(db.parPerso) == "table" and type(db.parPerso[moi]) == "table"
end

local function preparerProfils(db)
  if type(db.compte) ~= "table" then db.compte = {} end
  if type(db.parPerso) ~= "table" then db.parPerso = {} end
end

-- La valeur d'une clé dans un profil, sinon dans le compte, sinon la valeur de départ.
local function valeurDeProfil(db, profil, cle, defauts)
  local v = profil and profil[cle]
  if not valeurSimple(v) then v = db.compte[cle] end
  if not valeurSimple(v) and type(defauts) == "table" then v = defauts[cle] end
  if valeurSimple(v) then return v end
end

-- Au chargement : recopie dans db les valeurs du bon profil. Premier lancement (compte
-- vide) : le compte est rempli avec les valeurs actuelles, rien ne change pour le joueur.
-- Renvoie « perso » ou « compte ».
function ns.chargerProfil(db, cles, moi, defauts)
  if moi == nil then return "compte" end -- nom inconnu : la table reste telle quelle, rien n'est écrit
  preparerProfils(db)
  if next(db.compte) == nil then db.compte = ns.copierReglages(db, cles) end
  local mode = ns.modePerso(db, moi) and "perso" or "compte"
  local profil = mode == "perso" and db.parPerso[moi] or db.compte
  for _, cle in ipairs(cles) do
    local v = valeurDeProfil(db, profil, cle, defauts)
    if v ~= nil then db[cle] = v end
  end
  return mode
end

-- À chaque changement : les valeurs de db sont aussi écrites dans le profil du personnage
-- (ses réglages propres s'il en a, sinon ceux du compte). Renvoie « perso » ou « compte ».
function ns.ecrireProfil(db, cles, moi)
  if moi == nil then return "compte" end -- nom inconnu : rien n'est écrit dans le compte
  preparerProfils(db)
  local perso = ns.modePerso(db, moi)
  local cible = perso and db.parPerso[moi] or db.compte
  for _, cle in ipairs(cles) do
    if valeurSimple(db[cle]) then cible[cle] = db[cle] end
  end
  return perso and "perso" or "compte"
end

-- Active (perso = vrai) ou coupe les réglages propres à ce personnage. Activer copie les
-- valeurs actuelles dans parPerso[moi] ; couper efface parPerso[moi] et recharge le compte.
-- Renvoie le mode obtenu (« compte » aussi quand le personnage est inconnu).
function ns.changerMode(db, cles, moi, perso, defauts)
  if moi == nil then return "compte" end
  ns.ecrireProfil(db, cles, moi) -- ce qui a changé sans passer par r.changer n'est pas perdu
  if perso then
    if not ns.modePerso(db, moi) then db.parPerso[moi] = ns.copierReglages(db, cles) end
    return "perso"
  end
  db.parPerso[moi] = nil
  for _, cle in ipairs(cles) do
    local v = valeurDeProfil(db, nil, cle, defauts)
    if v ~= nil then db[cle] = v end
  end
  return "compte"
end

-- ------------------------------------------------------- le texte à partager
-- Format : « VA1;Addon:cle=valeur,cle=valeur;Addon:… » (VA = addons de Valentin, 1 = version
-- du format). Un interrupteur s'écrit 1 ou 0, un curseur par son nombre.

local function formatNombre(v)
  if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
  return string.format("%.6g", v)
end

-- blocs = { { nom = "GPS", valeurs = { taille = 160, actif = true } }, … } -> le texte.
function ns.encoderReglages(blocs)
  local morceaux = {}
  local liste = {}
  for _, b in ipairs(type(blocs) == "table" and blocs or {}) do
    if type(b) == "table" and type(b.nom) == "string" and b.nom:match("^[%w_]+$") and type(b.valeurs) == "table" then
      liste[#liste + 1] = b
    end
  end
  table.sort(liste, function(a, b) return a.nom < b.nom end)
  for _, b in ipairs(liste) do
    local cles = {}
    for cle, v in pairs(b.valeurs) do
      if type(cle) == "string" and cle:match("^[%w_]+$") and valeurSimple(v) then cles[#cles + 1] = cle end
    end
    table.sort(cles)
    if #cles > 0 then
      local paires = {}
      for _, cle in ipairs(cles) do
        local v = b.valeurs[cle]
        if type(v) == "boolean" then v = v and 1 or 0 end
        paires[#paires + 1] = cle .. "=" .. formatNombre(v)
      end
      morceaux[#morceaux + 1] = b.nom .. ":" .. table.concat(paires, ",")
    end
  end
  return "VA1;" .. table.concat(morceaux, ";")
end

-- Un bout de texte reçu, court et sans code de couleur, pour un message d'erreur.
local function extrait(s)
  return (s:sub(1, 28):gsub("|", "||"))
end

-- Le texte reçu -> { Addon = { cle = nombre } }, ou nil et un message clair.
function ns.decoderReglages(texte)
  if type(texte) ~= "string" then return nil, "Colle d'abord le texte reçu." end
  local t = texte:gsub("%s+", "") -- un texte collé peut avoir des retours à la ligne
  if t == "" then return nil, "Colle d'abord le texte reçu." end
  if #t > 20000 then return nil, "Ce texte est beaucoup trop long pour être un texte de réglages." end
  local version = t:match("^VA(%d+);")
  if not version then
    return nil, "Ce n'est pas un texte de réglages : il doit commencer par « VA1; ». Copie-le en entier."
  end
  if version ~= "1" then
    return nil, "Ce texte vient d'une autre version (VA" .. version .. ") : mets les addons à jour, des deux côtés."
  end
  local resultat, nombreDeBlocs = {}, 0
  for bloc in (t:sub(5) .. ";"):gmatch("([^;]*);") do
    if bloc ~= "" then
      local nom, corps = bloc:match("^([%w_]+):(.*)$")
      if not nom then
        return nil, "Texte abîmé : « " .. extrait(bloc) .. " » n'est pas de la forme Addon:réglage=valeur."
      end
      local valeurs = resultat[nom] or {}
      for paire in (corps .. ","):gmatch("([^,]*),") do
        if paire ~= "" then
          local cle, v = paire:match("^([%w_]+)=([%-%+%.%deE]+)$")
          local n = v and tonumber(v)
          if not cle or not n or n ~= n or n == math.huge or n == -math.huge then
            return nil, "Texte abîmé dans « " .. nom .. " » : « " .. extrait(paire) .. " » n'est pas de la forme réglage=valeur."
          end
          valeurs[cle] = n
        end
      end
      resultat[nom] = valeurs
      nombreDeBlocs = nombreDeBlocs + 1
    end
  end
  if nombreDeBlocs == 0 then return nil, "Ce texte ne contient aucun réglage." end
  return resultat
end

-- La valeur à poser pour une option déclarée, d'après un nombre reçu ; nil si elle est
-- refusée (un interrupteur ne prend que 0 ou 1 ; un curseur reste entre son minimum et
-- son maximum, sur son pas).
function ns.valeurValide(opt, brut)
  if type(opt) ~= "table" or type(brut) ~= "number" then return nil end
  if opt.type == "nombre" then
    local mini, maxi, pas = nombre(opt.min, 0), nombre(opt.max, 10), nombre(opt.pas, 1)
    if pas <= 0 then pas = 1 end
    local v = math.max(mini, math.min(maxi, brut))
    v = mini + math.floor((v - mini) / pas + 0.5) * pas
    return math.max(mini, math.min(maxi, v))
  end
  if brut == 1 then return true end
  if brut == 0 then return false end
  return nil
end

-- Applique le texte décodé. cibles = { { nom = "GPS", options = { cle = option }, poser = fonction(cle, valeur) } }.
-- Les addons et les clés inconnus sont ignorés (et comptés). Renvoie le bilan.
function ns.appliquerPartage(recu, cibles)
  local bilan = { appliques = 0, addons = 0, inconnus = 0, refuses = 0, absents = {} }
  local vus = {}
  for _, c in ipairs(cibles or {}) do
    local valeurs = recu[c.nom]
    if valeurs then
      vus[c.nom] = true
      local cles = {}
      for cle in pairs(valeurs) do cles[#cles + 1] = cle end
      table.sort(cles)
      local n = 0
      for _, cle in ipairs(cles) do
        local opt = c.options and c.options[cle]
        local v = opt and ns.valeurValide(opt, valeurs[cle])
        if not opt then
          bilan.inconnus = bilan.inconnus + 1
        elseif v == nil or not pcall(c.poser, cle, v) then
          bilan.refuses = bilan.refuses + 1
        else
          n = n + 1
        end
      end
      if n > 0 then bilan.addons = bilan.addons + 1 end
      bilan.appliques = bilan.appliques + n
    end
  end
  for nom in pairs(recu) do
    if not vus[nom] then bilan.absents[#bilan.absents + 1] = nom end
  end
  table.sort(bilan.absents)
  return bilan
end

-- Le bilan en une phrase, pour la fenêtre.
function ns.texteBilanPartage(bilan)
  local t
  if bilan.appliques == 0 then
    t = "Aucun réglage appliqué."
  else
    t = bilan.appliques .. " réglage(s) appliqué(s) dans " .. bilan.addons .. " addon(s)."
  end
  if bilan.inconnus > 0 then t = t .. " " .. bilan.inconnus .. " réglage(s) inconnu(s) ignoré(s)." end
  if bilan.refuses > 0 then t = t .. " " .. bilan.refuses .. " valeur(s) refusée(s)." end
  if #bilan.absents > 0 then t = t .. " Pas chez toi : " .. table.concat(bilan.absents, ", ") .. "." end
  return t
end

-- ============================================================ petits outils

-- Un bouton de la fenêtre, avec sa bulle d'aide.
local function creerBouton(parent, texte, aide, action, largeur)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(largeur or 150, 22)
  b:SetText(texte)
  b:SetScript("OnClick", function() action() end)
  if aide then
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(self:GetText() or texte)
      GameTooltip:AddLine(aide, 1, 1, 1, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  return b
end
ns.creerBouton = creerBouton

-- Un interrupteur : vert à droite = activé, rouge sombre à gauche = coupé.
local function creerInterrupteur(parent, surClic)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(42, 20)
  local bord = b:CreateTexture(nil, "BACKGROUND")
  bord:SetAllPoints()
  bord:SetColorTexture(0, 0, 0, 1)
  local fond = b:CreateTexture(nil, "BORDER")
  fond:SetPoint("TOPLEFT", 1, -1)
  fond:SetPoint("BOTTOMRIGHT", -1, 1)
  local pastille = b:CreateTexture(nil, "ARTWORK")
  pastille:SetSize(16, 16)
  pastille:SetColorTexture(0.88, 0.82, 0.70, 1)
  local etat = false
  function b.poser(v)
    etat = v and true or false
    pastille:ClearAllPoints()
    if etat then
      fond:SetColorTexture(0.16, 0.52, 0.12, 1)
      pastille:SetPoint("RIGHT", -2, 0)
    else
      fond:SetColorTexture(0.32, 0.10, 0.07, 1)
      pastille:SetPoint("LEFT", 2, 0)
    end
  end
  function b.permettre(v)
    if v then b:Enable() else b:Disable() end
    b:SetAlpha(v and 1 or 0.4)
  end
  b:SetScript("OnClick", function()
    if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856) end
    surClic(not etat)
  end)
  b.poser(false)
  return b
end

-- Un curseur fait main (les modèles du jeu changent d'une version à l'autre).
local function creerCurseur(parent, mini, maxi, pas)
  local s = CreateFrame("Slider", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  s:SetOrientation("HORIZONTAL")
  s:SetSize(170, 16)
  if s.SetBackdrop then
    s:SetBackdrop({
      bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
      edgeFile = "Interface\\Buttons\\UI-SliderBar-Border", edgeSize = 8, tile = true, tileSize = 8,
      insets = { left = 3, right = 3, top = 6, bottom = 6 },
    })
  end
  s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  local poignee = s.GetThumbTexture and s:GetThumbTexture()
  if poignee then poignee:SetSize(32, 32) end
  s:SetMinMaxValues(mini, maxi)
  s:SetValueStep(pas)
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  s:EnableMouseWheel(true)
  s:SetScript("OnMouseWheel", function(self, sens)
    if self:IsEnabled() then self:SetValue(self:GetValue() + sens * pas) end
  end)
  return s
end

-- La hauteur réelle d'un texte (repli quand elle n'est pas encore connue).
local function hauteurTexte(fs, defaut)
  local h = fs.GetStringHeight and fs:GetStringHeight()
  return math.max(nombre(h, defaut), defaut)
end

-- Un grand champ de texte sur plusieurs lignes, dans un cadre doré, qui défile (pour copier
-- ou coller un long texte). Renvoie le champ et son cadre.
local function creerChampDefilant(parent, largeur, hauteur)
  local cadre = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  cadre:SetSize(largeur, hauteur)
  if cadre.SetBackdrop then
    cadre:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    cadre:SetBackdropColor(0, 0, 0, 0.45)
    cadre:SetBackdropBorderColor(0.80, 0.63, 0.30, 0.9)
  end
  local okD, defile = pcall(CreateFrame, "ScrollFrame", nil, cadre, "UIPanelScrollFrameTemplate")
  if not okD or not defile then defile = CreateFrame("ScrollFrame", nil, cadre) end
  defile:SetPoint("TOPLEFT", 6, -6)
  defile:SetPoint("BOTTOMRIGHT", -26, 6)
  local champ = CreateFrame("EditBox", nil, defile)
  champ:SetMultiLine(true)
  champ:SetAutoFocus(false)
  champ:SetMaxLetters(20000)
  champ:SetFontObject(ChatFontNormal or GameFontHighlight)
  champ:SetWidth(largeur - 38)
  champ:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  -- Le champ grandit avec son texte : le curseur reste visible dans le cadre défilant.
  champ:SetScript("OnCursorChanged", function(self, _, y, _, h)
    if not (defile.GetVerticalScroll and defile.SetVerticalScroll and defile.GetHeight) then return end
    local haut = -nombre(y, 0)
    local bas = haut + nombre(h, 0)
    local debut = nombre(defile:GetVerticalScroll(), 0)
    local visible = nombre(defile:GetHeight(), hauteur)
    if haut < debut then defile:SetVerticalScroll(haut)
    elseif bas > debut + visible then defile:SetVerticalScroll(bas - visible) end
  end)
  defile:EnableMouseWheel(true)
  defile:SetScript("OnMouseWheel", function(self, sens)
    local maxi = nombre(self:GetVerticalScrollRange(), 0)
    self:SetVerticalScroll(math.max(0, math.min(maxi, nombre(self:GetVerticalScroll(), 0) - sens * 30)))
  end)
  defile:SetScrollChild(champ)
  -- Un clic dans le cadre, même à côté du texte, donne la main au champ.
  cadre:EnableMouse(true)
  cadre:SetScript("OnMouseDown", function() champ:SetFocus() end)
  return champ, cadre
end

-- ============================================================ liste éditable
-- spec = {
--   titre = "…", vide = "texte quand la liste est vide", hauteur = lignes visibles (5),
--   lignes = function() return { { texte = "…", lien = lien ou nil, retirer = fonction, clic = fonction ou nil }, … } end,
--   deposer = function(idObjet, lien, quantite) end,   -- facultatif : zone de dépôt
--   texteDepot = "…", quantite = 20,                   -- quantite : un champ nombre en plus
--   vider = function() end,                            -- facultatif : bouton « Tout retirer »
-- }
-- Renvoie le nouveau y et une fonction maj().
function ns.creerListe(parent, y, spec)
  local visibles = spec.hauteur or 5
  local HAUT = 18
  local t = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  t:SetPoint("TOPLEFT", 16, y - 4)
  y = y - 22

  local cadre = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  cadre:SetPoint("TOPLEFT", 16, y)
  cadre:SetSize(370, visibles * HAUT + 8)
  if cadre.SetBackdrop then
    cadre:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    cadre:SetBackdropColor(0, 0, 0, 0.35)
    cadre:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
  end
  local videTexte = cadre:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  videTexte:SetPoint("CENTER")
  videTexte:SetText(spec.vide or "Vide.")

  local decalage, donnees = 0, {}
  local boutons = {}
  local maj
  for i = 1, visibles do
    local l = CreateFrame("Button", nil, cadre)
    l:SetPoint("TOPLEFT", 4, -4 - (i - 1) * HAUT)
    l:SetSize(340, HAUT)
    l:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    l.texte = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l.texte:SetPoint("LEFT", 4, 0)
    l.texte:SetPoint("RIGHT", -4, 0)
    l.texte:SetJustifyH("LEFT")
    if l.texte.SetWordWrap then l.texte:SetWordWrap(false) end
    l.croix = CreateFrame("Button", nil, cadre, "UIPanelCloseButton")
    l.croix:SetSize(18, 18)
    l.croix:SetPoint("LEFT", l, "RIGHT", 2, 0)
    l.croix:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine("Retirer de la liste")
      GameTooltip:Show()
    end)
    l.croix:SetScript("OnLeave", function() GameTooltip:Hide() end)
    l:SetScript("OnEnter", function(self)
      if self.lien then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, self.lien)
        GameTooltip:Show()
      end
    end)
    l:SetScript("OnLeave", function() GameTooltip:Hide() end)
    boutons[i] = l
  end
  cadre:EnableMouseWheel(true)
  cadre:SetScript("OnMouseWheel", function(_, sens)
    local nouveau = math.max(0, math.min(decalage - sens, math.max(0, #donnees - visibles)))
    if nouveau == decalage then
      -- La liste ne bouge plus (courte, ou au bout) : c'est la page qui défile.
      local defile = parent.GetParent and parent:GetParent()
      local estDefilant = defile and defile.IsObjectType and defile:IsObjectType("ScrollFrame")
      local roulette = estDefilant and defile:GetScript("OnMouseWheel")
      if roulette then roulette(defile, sens) end
      return
    end
    decalage = nouveau
    maj()
  end)
  y = y - (visibles * HAUT + 8) - 6

  -- La zone de dépôt : on y lâche un objet pris dans le sac (ou on clique avec).
  local depot, qte
  if spec.deposer then
    depot = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    depot:SetPoint("TOPLEFT", 16, y)
    depot:SetSize(spec.quantite and 300 or 370, 26)
    if depot.SetBackdrop then
      depot:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
      depot:SetBackdropColor(0.2, 0.15, 0.05, 0.5)
      depot:SetBackdropBorderColor(0.8, 0.63, 0.3, 0.9)
    end
    local dt = depot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dt:SetPoint("CENTER")
    dt:SetText(spec.texteDepot or "Glisse un objet de ton sac ici pour l'ajouter")
    local function recevoir()
      local genre, id, lien = GetCursorInfo()
      if genre ~= "item" then return end
      local n = qte and tonumber(qte:GetText()) or nil
      ClearCursor()
      spec.deposer(id, lien, n)
      maj()
    end
    depot:RegisterForClicks("LeftButtonUp")
    depot:SetScript("OnReceiveDrag", recevoir)
    depot:SetScript("OnClick", recevoir)
    if spec.quantite then
      qte = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
      qte:SetSize(50, 20)
      qte:SetPoint("LEFT", depot, "RIGHT", 12, 0)
      qte:SetAutoFocus(false)
      qte:SetNumeric(true)
      qte:SetMaxLetters(4)
      qte:SetText(tostring(spec.quantite))
      local q = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      q:SetPoint("BOTTOM", qte, "TOP", 0, 0)
      q:SetText("Quantité")
    end
    y = y - 32
  end
  if spec.vider then
    local b = creerBouton(parent, "Tout retirer", "Vide toute la liste.", function() spec.vider(); maj() end, 120)
    b:SetPoint("TOPLEFT", 16, y)
    y = y - 28
  end

  maj = function()
    donnees = spec.lignes() or {}
    decalage = math.max(0, math.min(decalage, math.max(0, #donnees - visibles)))
    t:SetText((spec.titre or "") .. "  |cff888888" .. #donnees .. "|r")
    videTexte:SetShown(#donnees == 0)
    for i, l in ipairs(boutons) do
      local d = donnees[i + decalage]
      if d then
        l.texte:SetText(d.texte)
        l.lien = d.lien
        l.croix:SetScript("OnClick", function() d.retirer(); maj() end)
        -- Une ligne peut aussi se cliquer (d.clic), par exemple pour lancer une recherche.
        l:SetScript("OnClick", d.clic and function() d.clic() end or nil)
        l:Show(); l.croix:Show()
      else
        l:Hide(); l.croix:Hide()
      end
    end
  end
  return y, maj
end

-- ============================================================ la fenêtre commune
-- _G.ValentinAddons : { entrees, fenetre, zone, courant, … }, créé par le premier
-- addon chargé. Une entrée : { titre, icone, db, ouvrir, basculer, actif = fonction,
-- panneau = fonction ou nil, page = cadre, recherche = { … }, allerOnglet = fonction }.

local function leHub()
  local hub = _G.ValentinAddons
  if hub and hub.pret then return hub end
  hub = hub or {}
  hub.entrees = hub.entrees or {}
  hub.speciales = {} -- les pages qui ne sont pas des addons (Quoi de neuf…), refaites avec le hub
  _G.ValentinAddons = hub

  -- Si une copie précédente a échoué en route, on repart de sa fenêtre.
  local fenetre = _G.ValentinAddonsReglages
    or CreateFrame("Frame", "ValentinAddonsReglages", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  hub.fenetre = fenetre
  fenetre:SetSize(LARGEUR, HAUTEUR)
  fenetre:SetPoint("CENTER")
  fenetre:SetFrameStrata("DIALOG")
  fenetre:SetToplevel(true)
  fenetre:SetMovable(true)
  fenetre:SetClampedToScreen(true)
  fenetre:EnableMouse(true)
  fenetre:RegisterForDrag("LeftButton")
  fenetre:SetScript("OnDragStart", fenetre.StartMoving)
  fenetre:SetScript("OnDragStop", fenetre.StopMovingOrSizing)
  if fenetre.SetBackdrop then
    fenetre:SetBackdrop(FOND)
    fenetre:SetBackdropColor(0.07, 0.06, 0.045, 0.97)
    fenetre:SetBackdropBorderColor(0.80, 0.63, 0.30, 1)
  end
  fenetre:Hide()
  tinsert(UISpecialFrames, "ValentinAddonsReglages") -- Échap la ferme

  local titre = fenetre:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  titre:SetPoint("TOPLEFT", 14, -12)
  titre:SetText("Addons de Valentin")
  local fermer = CreateFrame("Button", nil, fenetre, "UIPanelCloseButton")
  fermer:SetPoint("TOPRIGHT", 0, 0)
  fermer:SetScript("OnClick", function() fenetre:Hide() end)
  local trait = fenetre:CreateTexture(nil, "ARTWORK")
  trait:SetColorTexture(0.80, 0.63, 0.30, 0.6)
  trait:SetPoint("TOPLEFT", 6, -38)
  trait:SetPoint("TOPRIGHT", -6, -38)
  trait:SetHeight(1)

  local okR, recherche = pcall(CreateFrame, "EditBox", "ValentinAddonsRecherche", fenetre, "SearchBoxTemplate")
  if not okR or not recherche then recherche = CreateFrame("EditBox", "ValentinAddonsRecherche", fenetre, "InputBoxTemplate") end
  recherche:SetSize(220, 20)
  recherche:SetPoint("TOPRIGHT", -40, -10)
  recherche:SetAutoFocus(false)
  hub.recherche = recherche

  -- La liste des addons, à gauche.
  local cote = CreateFrame("Frame", nil, fenetre)
  cote:SetPoint("TOPLEFT", 6, -42)
  cote:SetPoint("BOTTOMLEFT", 6, 6)
  cote:SetWidth(COTE)
  local fondCote = cote:CreateTexture(nil, "BACKGROUND")
  fondCote:SetAllPoints()
  fondCote:SetColorTexture(0, 0, 0, 0.25)
  local aideCote = cote:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  aideCote:SetPoint("BOTTOMLEFT", 6, 6)
  aideCote:SetWidth(COTE - 12)
  aideCote:SetJustifyH("LEFT")
  aideCote:SetText("Clic droit : activer ou couper\nMaj+clic : le panneau de l'addon")

  -- La zone des pages, à droite.
  local zone = CreateFrame("Frame", nil, fenetre)
  zone:SetPoint("TOPLEFT", COTE + 14, -44)
  zone:SetPoint("BOTTOMRIGHT", -8, 8)
  hub.zone = zone

  -- Les résultats de la recherche.
  local resultats = CreateFrame("Frame", nil, zone)
  resultats:SetAllPoints()
  resultats:Hide()
  local titreResultats = resultats:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  titreResultats:SetPoint("TOPLEFT", 8, -6)
  local lignesResultats = {}

  local lignes = {}
  -- Les pages spéciales d'abord (Quoi de neuf…), puis les addons par ordre alphabétique.
  local function toutesLesEntrees()
    local liste = {}
    for _, e in ipairs(hub.speciales) do liste[#liste + 1] = e end
    for _, e in ipairs(hub.entrees) do liste[#liste + 1] = e end
    return liste
  end

  function hub.majCote()
    table.sort(hub.entrees, function(a, b) return a.titre < b.titre end)
    local liste = toutesLesEntrees()
    local nSpeciales = #hub.speciales
    for i, e in ipairs(liste) do
      local l = lignes[i]
      if not l then
        l = CreateFrame("Button", nil, cote)
        l:SetSize(COTE - 8, 24)
        l:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 25 - (i > nSpeciales and 8 or 0))
        l:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        l:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        l.choisi = l:CreateTexture(nil, "BACKGROUND")
        l.choisi:SetAllPoints()
        l.choisi:SetColorTexture(0.80, 0.63, 0.30, 0.22)
        l.icone = l:CreateTexture(nil, "ARTWORK")
        l.icone:SetSize(18, 18)
        l.icone:SetPoint("LEFT", 4, 0)
        l.nom = l:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        l.nom:SetPoint("LEFT", l.icone, "RIGHT", 6, 0)
        l.point = l:CreateTexture(nil, "OVERLAY")
        l.point:SetSize(8, 8)
        l.point:SetPoint("RIGHT", -6, 0)
        -- La pastille dorée : il y a du nouveau sur cette page.
        l.pastille = l:CreateTexture(nil, "OVERLAY")
        l.pastille:SetSize(10, 10)
        l.pastille:SetPoint("RIGHT", -5, 0)
        l.pastille:SetColorTexture(1, 0.82, 0.30, 1)
        lignes[i] = l
      end
      l.pastille:SetShown(e.pastille ~= nil and e.pastille() and true or false)
      l.icone:SetTexture(e.icone)
      l.nom:SetText(e.titre)
      local actif = e.actif and e.actif()
      l.point:SetShown(actif ~= nil)
      if actif then l.point:SetColorTexture(0.24, 0.86, 0.24, 1) else l.point:SetColorTexture(1, 0.29, 0.23, 1) end
      l.icone:SetDesaturated(actif == false)
      if e == hub.courant then l.nom:SetTextColor(1, 0.82, 0) else l.nom:SetTextColor(1, 1, 1) end
      l.choisi:SetShown(e == hub.courant)
      l:SetScript("OnClick", function(_, souris)
        if souris == "RightButton" then
          if e.basculer then e.basculer() end
        elseif IsShiftKeyDown() and e.panneau then
          fenetre:Hide()
          e.panneau()
        else
          recherche:SetText("")
          if recherche.ClearFocus then recherche:ClearFocus() end
          hub.selectionner(e)
        end
      end)
      l:Show()
    end
    for i = #liste + 1, #lignes do lignes[i]:Hide() end
    -- Beaucoup d'addons : la fenêtre grandit pour tous les montrer.
    fenetre:SetHeight(math.max(HAUTEUR, #liste * 25 + 104))
  end

  function hub.selectionner(e)
    hub.courant = e or hub.courant or hub.entrees[1]
    for _, x in ipairs(toutesLesEntrees()) do
      if x.page and x ~= hub.courant then x.page:Hide() end
    end
    resultats:Hide()
    if hub.courant and hub.courant.page then hub.courant.page:Show() end
    hub.majCote()
  end

  function hub.montrer(e)
    if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
    if fenetre:IsShown() then fenetre:Raise() else fenetre:Show() end
    if recherche:GetText() ~= "" then recherche:SetText("") end
    hub.selectionner(e)
  end

  function hub.basculerFenetre()
    if fenetre:IsShown() then fenetre:Hide() else hub.montrer(nil) end
  end

  -- La recherche : chaque résultat mène au bon addon et au bon onglet.
  function hub.chercher(texte)
    local trouves = ns.chercherReglages(hub.entrees, texte)
    if simple(texte) == "" then hub.selectionner(hub.courant) return end
    for _, x in ipairs(toutesLesEntrees()) do
      if x.page then x.page:Hide() end
    end
    resultats:Show()
    titreResultats:SetText(#trouves == 0 and "Aucun réglage ne contient ce texte."
      or (#trouves .. " réglage(s) trouvé(s)" .. (#trouves > 14 and ", les 14 premiers ci-dessous" or "") .. " : clique pour y aller"))
    for i = 1, math.max(#trouves, #lignesResultats) do
      local l = lignesResultats[i]
      local t = trouves[i]
      if t and i <= 14 then
        if not l then
          l = CreateFrame("Button", nil, resultats)
          l:SetSize(PAGE, 32)
          l:SetPoint("TOPLEFT", 4, -28 - (i - 1) * 34)
          l:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
          l.chemin = l:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
          l.chemin:SetPoint("TOPLEFT", 6, -2)
          l.libelle = l:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
          l.libelle:SetPoint("TOPLEFT", 6, -14)
          lignesResultats[i] = l
        end
        l.chemin:SetText(t.entree.titre .. "  >  " .. (t.item.section or ""))
        l.libelle:SetText(t.item.libelle)
        l:SetScript("OnClick", function()
          recherche:SetText("")
          if recherche.ClearFocus then recherche:ClearFocus() end
          hub.selectionner(t.entree)
          if t.entree.allerOnglet then t.entree.allerOnglet(t.item.onglet) end
        end)
        l:Show()
      elseif l then
        l:Hide()
      end
    end
  end
  recherche:HookScript("OnTextChanged", function(self) hub.chercher(self:GetText()) end)

  -- ----------------------------------------------------- Quoi de neuf
  -- Une page à part, tout en haut de la liste : pas un addon, donc ni point ni interrupteur.
  local pageNeuf = CreateFrame("Frame", nil, zone)
  pageNeuf:SetAllPoints()
  pageNeuf:Hide()
  local entreeNeuf = { titre = "Quoi de neuf", icone = "Interface\\Icons\\INV_Misc_Note_01", page = pageNeuf, special = true }
  hub.speciales[#hub.speciales + 1] = entreeNeuf

  local titreNeuf = pageNeuf:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  titreNeuf:SetPoint("TOPLEFT", 10, -6)
  titreNeuf:SetTextColor(1, 0.82, 0.30)
  titreNeuf:SetText("Quoi de neuf")
  local soustitreNeuf = pageNeuf:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  soustitreNeuf:SetPoint("TOPLEFT", titreNeuf, "BOTTOMLEFT", 0, -4)
  soustitreNeuf:SetText("Ce qui a changé dans les addons, du plus récent au plus ancien.")

  local okN, defileNeuf = pcall(CreateFrame, "ScrollFrame", "ValentinAddonsNeufDefile", pageNeuf, "UIPanelScrollFrameTemplate")
  if not okN or not defileNeuf then defileNeuf = CreateFrame("ScrollFrame", nil, pageNeuf) end
  defileNeuf:SetPoint("TOPLEFT", 6, -52)
  defileNeuf:SetPoint("BOTTOMRIGHT", -26, 8)
  defileNeuf:EnableMouseWheel(true)
  defileNeuf:SetScript("OnMouseWheel", function(self, sens)
    local maxi = nombre(self:GetVerticalScrollRange(), 0)
    self:SetVerticalScroll(math.max(0, math.min(maxi, nombre(self:GetVerticalScroll(), 0) - sens * 40)))
  end)
  local contenuNeuf = CreateFrame("Frame", nil, defileNeuf)
  contenuNeuf:SetSize(PAGE - 10, 10)
  local texteNeuf = contenuNeuf:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  texteNeuf:SetPoint("TOPLEFT", 4, -4)
  texteNeuf:SetWidth(PAGE - 34)
  texteNeuf:SetJustifyH("LEFT")
  if texteNeuf.SetJustifyV then texteNeuf:SetJustifyV("TOP") end
  defileNeuf:SetScrollChild(contenuNeuf)

  -- La plus ancienne date vue parmi les addons chargés (ceux sans date sont ignorés, nil si
  -- aucune n'est connue) : ce qui est plus récent est marqué « nouveau » dans la page.
  local function plusAncienneVue()
    local dates = {}
    for _, x in ipairs(hub.entrees) do dates[#dates + 1] = x.db and x.db.nouveautesVues end
    return ns.plusAncienneDate(dates)
  end

  -- Il y a du nouveau pour au moins un addon chargé.
  function hub.aDuNeuf()
    for _, x in ipairs(hub.entrees) do
      if x.db and ns.ilYADuNeuf(ns.NOUVEAUTES, x.db.nouveautesVues) then return true end
    end
    return false
  end

  -- La page a été ouverte : chaque addon retient la date de la dernière nouveauté.
  function hub.marquerVu()
    local derniere = ns.derniereNouveaute(ns.NOUVEAUTES)
    if not derniere then return end
    for _, x in ipairs(hub.entrees) do
      if x.db then x.db.nouveautesVues = derniere end
    end
    hub.majCote()
  end

  entreeNeuf.pastille = function() return hub.aDuNeuf() end
  pageNeuf:SetScript("OnShow", function()
    texteNeuf:SetText(ns.texteNouveautes(ns.NOUVEAUTES, plusAncienneVue()))
    contenuNeuf:SetHeight(nombre(texteNeuf:GetStringHeight(), 400) + 16)
    defileNeuf:SetVerticalScroll(0)
    hub.marquerVu()
  end)

  -- Un seul message par connexion, même avec 21 addons (le drapeau est dans le hub commun).
  function hub.annoncerNouveautes()
    if hub.messageNouveau then return end
    hub.messageNouveau = true
    local function dire()
      if hub.aDuNeuf() then
        print("|cffffd200Addons de Valentin|r : il y a du nouveau, clique sur l'engrenage (autour de la minimap) puis sur « Quoi de neuf ».")
      end
    end
    if C_Timer and C_Timer.After then C_Timer.After(5, dire) else dire() end
  end

  -- ----------------------------------------------------- Partager mes réglages
  -- Sous « Quoi de neuf » : un texte à copier (tous les réglages de tous les addons chargés)
  -- et un champ où coller celui d'un ami. Les listes (objets ignorés, balises…) ne partent pas.
  local pagePartage = CreateFrame("Frame", nil, zone)
  pagePartage:SetAllPoints()
  pagePartage:Hide()
  local entreePartage = { titre = "Partager mes réglages", icone = "Interface\\Icons\\INV_Letter_15", page = pagePartage, special = true }
  hub.speciales[#hub.speciales + 1] = entreePartage

  local titrePartage = pagePartage:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  titrePartage:SetPoint("TOPLEFT", 10, -6)
  titrePartage:SetTextColor(1, 0.82, 0.30)
  titrePartage:SetText("Partager mes réglages")
  local explication = pagePartage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  explication:SetPoint("TOPLEFT", titrePartage, "BOTTOMLEFT", 0, -6)
  explication:SetWidth(PAGE - 20)
  explication:SetJustifyH("LEFT")
  explication:SetText("Les interrupteurs et les curseurs de tous les addons tiennent dans un seul texte. "
    .. "Clique dans le premier cadre, Ctrl+A puis Ctrl+C pour le copier, et envoie-le à un ami. "
    .. "Lui le colle dans le second cadre et clique sur « Appliquer ». "
    .. "Les listes (objets ignorés, balises, courses…) ne sont pas partagées.")

  local etiquetteEnvoi = pagePartage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  etiquetteEnvoi:SetPoint("TOPLEFT", 10, -98)
  etiquetteEnvoi:SetText("Mes réglages (à copier)")
  local champEnvoi, cadreEnvoi = creerChampDefilant(pagePartage, PAGE - 10, 120)
  cadreEnvoi:SetPoint("TOPLEFT", 8, -116)

  local etiquetteRecu = pagePartage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  etiquetteRecu:SetPoint("TOPLEFT", 10, -248)
  etiquetteRecu:SetText("Réglages reçus (à coller)")
  local champRecu, cadreRecu = creerChampDefilant(pagePartage, PAGE - 10, 100)
  cadreRecu:SetPoint("TOPLEFT", 8, -266)

  local resultatPartage = pagePartage:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  resultatPartage:SetPoint("TOPLEFT", 10, -408)
  resultatPartage:SetWidth(PAGE - 20)
  resultatPartage:SetJustifyH("LEFT")

  -- Le texte de mes réglages : un bloc par addon chargé.
  local texteEnvoi = ""
  local function calculerEnvoi()
    local blocs = {}
    for _, x in ipairs(hub.entrees) do
      local pa = x.partage
      if pa then
        local ok, valeurs = pcall(pa.lire)
        if ok then blocs[#blocs + 1] = { nom = pa.nom, valeurs = valeurs } end
      end
    end
    texteEnvoi = ns.encoderReglages(blocs)
    champEnvoi:SetText(texteEnvoi)
  end
  -- Le premier champ ne se modifie pas : une frappe remet le texte en place.
  champEnvoi:SetScript("OnTextChanged", function(self, saisie)
    if saisie and self:GetText() ~= texteEnvoi then
      self:SetText(texteEnvoi)
      self:HighlightText()
    end
  end)
  champEnvoi:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)

  local function appliquerRecu()
    local recu, erreur = ns.decoderReglages(champRecu:GetText())
    if not recu then
      resultatPartage:SetText("|cffff4a3a" .. erreur .. "|r")
      return
    end
    local cibles = {}
    for _, x in ipairs(hub.entrees) do
      if x.partage then cibles[#cibles + 1] = x.partage end
    end
    local bilan = ns.appliquerPartage(recu, cibles)
    resultatPartage:SetText((bilan.appliques > 0 and "|cff3ddc3d" or "|cffff4a3a") .. ns.texteBilanPartage(bilan) .. "|r")
    calculerEnvoi()
  end
  local boutonAppliquer = creerBouton(pagePartage, "Appliquer", "Applique les réglages du texte collé. Les addons ou les réglages que tu n'as pas sont ignorés.", appliquerRecu, 150)
  boutonAppliquer:SetPoint("TOPLEFT", 8, -374)
  local boutonVider = creerBouton(pagePartage, "Vider le champ", "Efface le texte collé.", function()
    champRecu:SetText("")
    resultatPartage:SetText("")
  end, 130)
  boutonVider:SetPoint("LEFT", boutonAppliquer, "RIGHT", 8, 0)

  pagePartage:SetScript("OnShow", function()
    calculerEnvoi()
    resultatPartage:SetText("")
  end)

  -- L'icône commune autour de la minimap : un clic ouvre la fenêtre.
  if not _G.ValentinAddonsMinimap then
    local bouton = CreateFrame("Button", "ValentinAddonsMinimap", Minimap)
    bouton:SetSize(31, 31)
    bouton:SetFrameStrata("MEDIUM")
    bouton:SetFrameLevel(8)
    bouton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    bouton:RegisterForDrag("LeftButton")
    bouton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local fond = bouton:CreateTexture(nil, "BACKGROUND")
    fond:SetSize(20, 20)
    fond:SetPoint("TOPLEFT", 7, -5)
    fond:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    local icone = bouton:CreateTexture(nil, "ARTWORK")
    icone:SetSize(17, 17)
    icone:SetPoint("TOPLEFT", 7, -6)
    icone:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
    local cadre = bouton:CreateTexture(nil, "OVERLAY")
    cadre:SetSize(53, 53)
    cadre:SetPoint("TOPLEFT")
    cadre:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    -- Angle gardé : celui du premier addon inscrit qui en a un.
    local function angle()
      for _, x in ipairs(hub.entrees) do
        if x.db and x.db.angleHub then return x.db.angleHub end
      end
      return 200
    end
    function hub.placer()
      local rayon = nombre(Minimap:GetWidth(), 140) / 2 + 5
      local a = math.rad(angle())
      bouton:ClearAllPoints()
      bouton:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * rayon, math.sin(a) * rayon)
    end
    local function suivreSouris()
      local cx, cy = Minimap:GetCenter()
      local sx, sy = GetCursorPosition()
      local echelle = Minimap:GetEffectiveScale()
      local a = math.deg(math.atan2(sy / echelle - cy, sx / echelle - cx))
      for _, x in ipairs(hub.entrees) do if x.db then x.db.angleHub = a end end
      hub.placer()
    end
    bouton:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", suivreSouris) end)
    bouton:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    bouton:SetScript("OnClick", function() hub.basculerFenetre() end)
    bouton:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:AddLine("Addons de Valentin")
      for _, x in ipairs(hub.entrees) do
        local actif = x.actif and x.actif()
        local etat = actif == nil and "" or (actif and "|cff00ff00activé|r" or "|cffff4040coupé|r")
        GameTooltip:AddDoubleLine(x.titre, etat, 1, 1, 1)
      end
      if hub.aDuNeuf() then GameTooltip:AddLine("Il y a du nouveau : page « Quoi de neuf »", 1, 0.82, 0.30) end
      GameTooltip:AddLine("Clic : tous les réglages\nGlisser : déplacer", 0.7, 0.7, 0.7)
      GameTooltip:Show()
    end)
    bouton:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  hub.placer = hub.placer or function() end
  hub.pret = true
  return hub
end

-- Inscrit un addon dans la fenêtre commune.
function ns.inscrireAuHub(e)
  local hub = leHub()
  table.insert(hub.entrees, e)
  hub.placer()
  hub.majCote()
  -- Un réglage change ailleurs (commande, raccourci) : la liste se remet à jour.
  e.maj = function() hub.majCote() end
  return e
end

-- ============================================================ la page d'un addon

function ns.creerReglages(p)
  local r = {}
  local db
  local hub = leHub()
  local cles = ns.clesReglages(p.options) -- les clés déclarées : les seules qui se partagent ou se rangent par personnage
  local optionsParCle = {}
  for _, opt in ipairs(p.options) do
    if opt.cle then optionsParCle[opt.cle] = opt end
  end
  local moi -- « Nom-Royaume » du personnage, connu au chargement

  local function dire(texte) print("|cffffd200" .. p.titre .. "|r : " .. texte) end
  r.dire = dire

  local page = CreateFrame("Frame", NOM_ADDON .. "Reglages", hub.zone)
  page:SetAllPoints()
  page:Hide()

  -- ------------------------------------------------------- en-tête
  local icone = page:CreateTexture(nil, "ARTWORK")
  icone:SetSize(34, 34)
  icone:SetPoint("TOPLEFT", 6, -4)
  icone:SetTexture(p.icone)
  local nom = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  nom:SetPoint("TOPLEFT", icone, "TOPRIGHT", 10, -1)
  nom:SetText(p.titre)
  local description = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  description:SetPoint("TOPLEFT", nom, "BOTTOMLEFT", 0, -3)
  description:SetWidth(PAGE - 190)
  description:SetJustifyH("LEFT")
  if description.SetMaxLines then description:SetMaxLines(2) end
  local lireNotes = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  if lireNotes then
    local okN, notes = pcall(lireNotes, NOM_ADDON, "Notes")
    if okN and type(notes) == "string" then description:SetText(notes) end
  end

  local aActif = false
  for _, opt in ipairs(p.options) do if opt.cle == "actif" then aActif = true end end
  local interrupteurGeneral, etatGeneral
  if aActif then
    interrupteurGeneral = creerInterrupteur(page, function(v) r.changer("actif", v) end)
    interrupteurGeneral:SetPoint("TOPRIGHT", -30, -10)
    etatGeneral = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    etatGeneral:SetPoint("RIGHT", interrupteurGeneral, "LEFT", -8, 0)
  end

  -- Réglages propres à ce personnage : un petit interrupteur sous l'interrupteur général.
  local interrupteurPerso = creerInterrupteur(page, function(v)
    if not moi or not db then return end
    ns.changerMode(db, cles, moi, v, p.defauts)
    r.appliquer()
    dire(v and "réglages propres à ce personnage (copiés depuis les réglages actuels)."
      or "réglages communs à tout le compte (ceux du compte sont rechargés).")
  end)
  interrupteurPerso:SetScale(0.85)
  interrupteurPerso:SetPoint("TOPRIGHT", -30, -52)
  local textePerso = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  textePerso:SetPoint("RIGHT", interrupteurPerso, "LEFT", -8, 0)
  textePerso:SetText("Réglages propres à ce personnage")
  interrupteurPerso:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Réglages propres à ce personnage")
    GameTooltip:AddLine("Coupé : les réglages de cet addon sont les mêmes pour tous tes personnages. Activé : ce personnage a les siens (copiés depuis les réglages actuels), les autres personnages ne changent pas. Seuls les interrupteurs et les curseurs sont concernés, pas les listes ni les positions.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  interrupteurPerso:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- ------------------------------------------------------- onglets
  -- Un onglet par section ({ titre = … }) ; les options d'avant la première
  -- section vont dans « Général » ; contenu() a son propre onglet.
  local onglets = {}
  local courant
  for _, opt in ipairs(p.options) do
    if opt.titre then
      courant = { titre = opt.titre, options = {} }
      onglets[#onglets + 1] = courant
    else
      if not courant then
        courant = { titre = "Général", options = {} }
        onglets[#onglets + 1] = courant
      end
      -- L'interrupteur général est déjà dans l'en-tête.
      if opt.cle ~= "actif" then courant.options[#courant.options + 1] = opt end
    end
  end
  -- Une section qui n'avait que « actif » : on ne garde pas un onglet vide.
  for i = #onglets, 1, -1 do
    if #onglets[i].options == 0 then table.remove(onglets, i) end
  end
  if p.contenu then onglets[#onglets + 1] = { titre = p.ongletContenu or "Détails", contenu = true, options = {} } end
  if #onglets == 0 then onglets[1] = { titre = "Général", options = {} } end

  local x, ligne = 4, 0
  for _, o in ipairs(onglets) do
    local b = CreateFrame("Button", nil, page)
    b.texte = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.texte:SetPoint("CENTER")
    b.texte:SetText(o.titre)
    local largeur = nombre(b.texte:GetStringWidth(), #o.titre * 7) + 22
    if x + largeur > PAGE then x, ligne = 4, ligne + 1 end
    b:SetSize(largeur, 24)
    b:SetPoint("TOPLEFT", x, -76 - ligne * 26)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.trait = b:CreateTexture(nil, "ARTWORK")
    b.trait:SetColorTexture(1, 0.82, 0, 1)
    b.trait:SetPoint("BOTTOMLEFT", 4, 0)
    b.trait:SetPoint("BOTTOMRIGHT", -4, 0)
    b.trait:SetHeight(2)
    o.bouton = b
    x = x + largeur + 4
  end
  local hautOnglets = 76 + (ligne + 1) * 26 + 6

  -- ------------------------------------------------------- boutons d'action, en bas
  local actions = {}
  if p.ouvrirHub then
    actions[1] = { texte = p.texteHub or "Ouvrir le panneau", aide = "Aussi : Maj+clic sur son nom dans la liste des addons.",
      action = function() hub.fenetre:Hide(); p.ouvrirHub() end }
  end
  for _, b in ipairs(p.boutons or {}) do actions[#actions + 1] = b end
  local places, bx, rangee = {}, 4, 0
  for _, a in ipairs(actions) do
    local largeur = a.largeur or 150
    if bx + largeur > PAGE then bx, rangee = 4, rangee + 1 end
    places[#places + 1] = { a = a, x = bx, rangee = rangee, largeur = largeur }
    bx = bx + largeur + 6
  end
  local hautActions = #actions > 0 and ((rangee + 1) * 26 + 8) or 0
  for _, pl in ipairs(places) do
    local b = creerBouton(page, pl.a.texte, pl.a.aide, pl.a.action, pl.largeur)
    b:SetPoint("BOTTOMLEFT", pl.x, 4 + (rangee - pl.rangee) * 26)
  end

  -- ------------------------------------------------------- le contenu qui défile
  local okD, defile = pcall(CreateFrame, "ScrollFrame", NOM_ADDON .. "ReglagesDefile", page, "UIPanelScrollFrameTemplate")
  if not okD or not defile then defile = CreateFrame("ScrollFrame", nil, page) end
  defile:SetPoint("TOPLEFT", 0, -hautOnglets)
  defile:SetPoint("BOTTOMRIGHT", -26, hautActions + 2)
  defile:EnableMouseWheel(true)
  defile:SetScript("OnMouseWheel", function(self, sens)
    local maxi = nombre(self:GetVerticalScrollRange(), 0)
    self:SetVerticalScroll(math.max(0, math.min(maxi, nombre(self:GetVerticalScroll(), 0) - sens * 40)))
  end)

  local controles = {}
  local majContenu

  -- Une option = une ligne : libellé et aide à gauche, interrupteur ou curseur à droite.
  local function ligneOption(parent, opt, y)
    local rangeeOpt = CreateFrame("Frame", nil, parent)
    rangeeOpt:SetPoint("TOPLEFT", 0, y)
    rangeeOpt:SetWidth(PAGE)
    local libelle = rangeeOpt:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    libelle:SetPoint("TOPLEFT", 8, -7)
    libelle:SetJustifyH("LEFT")
    libelle:SetText(opt.libelle)
    local aide = rangeeOpt:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    aide:SetPoint("TOPLEFT", libelle, "BOTTOMLEFT", 0, -2)
    aide:SetJustifyH("LEFT")
    aide:SetText(opt.aide or "")
    local ctl = { opt = opt, libelle = libelle, aide = aide, rangee = rangeeOpt }
    if opt.type == "nombre" then
      libelle:SetWidth(PAGE - 270)
      aide:SetWidth(PAGE - 270)
      local s = creerCurseur(rangeeOpt, opt.min or 0, opt.max or 10, opt.pas or 1)
      s:SetPoint("TOPRIGHT", -62, -8)
      local valeur = rangeeOpt:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      valeur:SetPoint("LEFT", s, "RIGHT", 8, 0)
      local enCours = false
      local function texte(v) return opt.format and opt.format(v) or tostring(v) end
      s:SetScript("OnValueChanged", function(_, v)
        local mini, pas = opt.min or 0, opt.pas or 1
        v = mini + math.floor((nombre(v, mini) - mini) / pas + 0.5) * pas
        valeur:SetText(texte(v))
        if not enCours and db and db[opt.cle] ~= v then r.changer(opt.cle, v) end
      end)
      ctl.curseur = s
      ctl.poser = function(v)
        enCours = true
        s:SetValue(v or opt.min or 0)
        enCours = false
        valeur:SetText(texte(v or opt.min or 0))
      end
    else
      libelle:SetWidth(PAGE - 80)
      aide:SetWidth(PAGE - 80)
      ctl.interrupteur = creerInterrupteur(rangeeOpt, function(v) r.changer(opt.cle, v) end)
      ctl.interrupteur:SetPoint("TOPRIGHT", -10, -8)
    end
    local h = math.max(36, hauteurTexte(libelle, 12) + (opt.aide and hauteurTexte(aide, 10) + 2 or 0) + 16)
    rangeeOpt:SetHeight(h)
    local filet = rangeeOpt:CreateTexture(nil, "BACKGROUND")
    filet:SetColorTexture(1, 1, 1, 0.07)
    filet:SetPoint("BOTTOMLEFT", 4, 0)
    filet:SetPoint("BOTTOMRIGHT", -4, 0)
    filet:SetHeight(1)
    controles[#controles + 1] = ctl
    parent.rangees = parent.rangees or {}
    parent.rangees[#parent.rangees + 1] = ctl
    return y - h
  end

  local recherche = {}
  for i, o in ipairs(onglets) do
    local f = CreateFrame("Frame", nil, defile)
    f:SetSize(PAGE, 10)
    f:Hide()
    o.cadre = f
    local y = -2
    if o.contenu then
      y, majContenu = p.contenu(f, -4, r)
      y = nombre(y, -200)
    else
      for _, opt in ipairs(o.options) do
        y = ligneOption(f, opt, y)
        recherche[#recherche + 1] = { libelle = opt.libelle, aide = opt.aide, section = o.titre, onglet = i }
      end
    end
    if i == 1 and p.astuce then
      local astuce = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      o.astuce = astuce
      astuce:SetPoint("TOPLEFT", 8, y - 10)
      astuce:SetWidth(PAGE - 20)
      astuce:SetJustifyH("LEFT")
      astuce:SetText(p.astuce)
      y = y - 16 - hauteurTexte(astuce, 24)
    end
    o.hauteur = -y + 8
    f:SetHeight(o.hauteur)
  end

  -- Remet chaque ligne à sa vraie hauteur, une fois les textes mesurables.
  local function disposer(o)
    if o.contenu or not o.cadre.rangees then return end
    local y = -2
    for _, ctl in ipairs(o.cadre.rangees) do
      local h = math.max(36, hauteurTexte(ctl.libelle, 12) + (ctl.opt.aide and hauteurTexte(ctl.aide, 10) + 2 or 0) + 16)
      ctl.rangee:ClearAllPoints()
      ctl.rangee:SetPoint("TOPLEFT", 0, y)
      ctl.rangee:SetHeight(h)
      y = y - h
    end
    if o.astuce then
      o.astuce:ClearAllPoints()
      o.astuce:SetPoint("TOPLEFT", 8, y - 10)
      y = y - 16 - hauteurTexte(o.astuce, 24)
    end
    o.hauteur = -y + 8
    o.cadre:SetHeight(o.hauteur)
  end

  local ongletOuvert = 1
  local function choisirOnglet(i)
    if not onglets[i] then i = 1 end
    ongletOuvert = i
    disposer(onglets[i])
    for j, o in ipairs(onglets) do
      o.cadre:SetShown(j == i)
      o.bouton.trait:SetShown(j == i)
      if j == i then o.bouton.texte:SetTextColor(1, 0.82, 0) else o.bouton.texte:SetTextColor(0.6, 0.57, 0.5) end
    end
    defile:SetScrollChild(onglets[i].cadre)
    defile:SetVerticalScroll(0)
    local barre = defile.ScrollBar or _G[NOM_ADDON .. "ReglagesDefileScrollBar"]
    local visible = nombre(defile:GetHeight(), 0)
    if visible <= 0 then visible = HAUTEUR - 52 - hautOnglets - hautActions end
    if barre then barre:SetShown(onglets[i].hauteur > visible) end
  end
  for i, o in ipairs(onglets) do
    o.bouton:SetScript("OnClick", function() choisirOnglet(i) end)
  end

  -- Une option est grisée quand ce dont elle dépend n'est pas réglé comme il faut.
  local function disponible(opt)
    if aActif and opt.cle ~= "minimap" and not opt.toujours and not db.actif then return false end
    if type(opt.dispo) == "function" then
      local ok, v = pcall(opt.dispo)
      if ok and not v then return false end
    end
    local d = opt.dependDe
    if not d then return true end
    if d:sub(1, 1) == "!" then return not db[d:sub(2)] end
    return db[d] and true or false
  end

  local function majFenetre()
    if not db then return end
    if interrupteurGeneral then
      interrupteurGeneral.poser(db.actif)
      etatGeneral:SetText(db.actif and "|cff3ddc3dActivé|r" or "|cffff4a3aCoupé|r")
    end
    interrupteurPerso.poser(ns.modePerso(db, moi))
    interrupteurPerso.permettre(moi ~= nil)
    for _, ctl in ipairs(controles) do
      local dispo = disponible(ctl.opt)
      if ctl.interrupteur then
        ctl.interrupteur.poser(db[ctl.opt.cle])
        ctl.interrupteur.permettre(dispo)
      else
        ctl.poser(db[ctl.opt.cle])
        if dispo then ctl.curseur:Enable() else ctl.curseur:Disable() end
        ctl.curseur:SetAlpha(dispo and 1 or 0.4)
      end
      if dispo then ctl.libelle:SetTextColor(1, 1, 1) else ctl.libelle:SetTextColor(0.5, 0.5, 0.5) end
    end
    if majContenu then majContenu(db) end
  end
  r.majFenetre = function() if page:IsShown() then majFenetre() end end
  page:SetScript("OnShow", function()
    choisirOnglet(ongletOuvert)
    majFenetre()
  end)

  -- Ouvre ou ferme (icône, commande) ; montrer() ouvre toujours.
  function r.montrer() hub.montrer(r.hub) end
  function r.ouvrir()
    if hub.fenetre:IsShown() and hub.courant == r.hub and page:IsShown() then hub.fenetre:Hide() else r.montrer() end
  end
  -- Nom global pour le .toc (## AddonCompartmentFunc) et les raccourcis.
  _G[NOM_ADDON .. "_OuvrirReglages"] = r.ouvrir

  -- Page dans Échap > Options > AddOns, avec un bouton qui ouvre la fenêtre.
  local pageJeu = CreateFrame("Frame")
  pageJeu.name = p.titre
  local pageTexte = pageJeu:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  pageTexte:SetPoint("TOPLEFT", 16, -16)
  pageTexte:SetText("Tous les réglages de " .. p.titre .. " sont dans la fenêtre des addons de Valentin :")
  local pageBouton = CreateFrame("Button", nil, pageJeu, "UIPanelButtonTemplate")
  pageBouton:SetSize(200, 26)
  pageBouton:SetPoint("TOPLEFT", pageTexte, "BOTTOMLEFT", 0, -12)
  pageBouton:SetText("Ouvrir les réglages")
  pageBouton:SetScript("OnClick", function() r.montrer() end)
  if Settings and Settings.RegisterCanvasLayoutCategory then
    Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(pageJeu, pageJeu.name))
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(pageJeu)
  end

  -- ------------------------------------------------------- icône minimap à part
  local mini = CreateFrame("Button", NOM_ADDON .. "Minimap", Minimap)
  mini:SetSize(31, 31)
  mini:SetFrameStrata("MEDIUM")
  mini:SetFrameLevel(8)
  mini:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  mini:RegisterForDrag("LeftButton")
  mini:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local fond = mini:CreateTexture(nil, "BACKGROUND")
  fond:SetSize(20, 20)
  fond:SetPoint("TOPLEFT", 7, -5)
  fond:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  local iconeMini = mini:CreateTexture(nil, "ARTWORK")
  iconeMini:SetSize(17, 17)
  iconeMini:SetPoint("TOPLEFT", 7, -6)
  iconeMini:SetTexture(p.icone)
  r.iconeMini = iconeMini
  local cadre = mini:CreateTexture(nil, "OVERLAY")
  cadre:SetSize(53, 53)
  cadre:SetPoint("TOPLEFT")
  cadre:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

  -- Place l'icône sur le bord de la minimap, à l'angle donné (0° = à droite).
  local function placerMini()
    local rayon = nombre(Minimap:GetWidth(), 140) / 2 + 5
    local a = math.rad(db.angleMinimap or 225)
    mini:ClearAllPoints()
    mini:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * rayon, math.sin(a) * rayon)
  end
  local function suivreSouris()
    local cx, cy = Minimap:GetCenter()
    local sx, sy = GetCursorPosition()
    local echelle = Minimap:GetEffectiveScale()
    db.angleMinimap = math.deg(math.atan2(sy / echelle - cy, sx / echelle - cx))
    placerMini()
  end
  mini:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", suivreSouris) end)
  mini:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  mini:SetScript("OnClick", function(_, souris)
    if souris == "RightButton" then r.basculer()
    elseif IsShiftKeyDown() and p.ouvrirHub then p.ouvrirHub()
    else r.ouvrir() end
  end)
  mini:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(p.titre)
    GameTooltip:AddLine(db.actif and "|cff00ff00Activé|r" or "|cffff4040Coupé|r")
    GameTooltip:AddLine("Clic gauche : réglages\nClic droit : activer ou couper\nGlisser : déplacer", 1, 1, 1)
    if p.ouvrirHub then GameTooltip:AddLine("Maj+clic : " .. (p.texteHub or "le panneau"), 1, 1, 1) end
    GameTooltip:Show()
  end)
  mini:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- ------------------------------------------------------- changements
  function r.appliquer()
    -- Les valeurs actuelles vont aussi dans le profil du personnage (ses réglages propres, sinon le compte).
    ns.ecrireProfil(db, cles, moi)
    iconeMini:SetDesaturated(not db.actif)
    mini:SetShown(db.minimap == true)
    if page:IsShown() then majFenetre() end
    if r.hub then r.hub.maj() end
    if p.surChangement then p.surChangement(db) end
  end

  function r.changer(cle, valeur)
    db[cle] = valeur
    r.appliquer()
  end

  function r.basculer()
    r.changer("actif", not db.actif)
    dire(db.actif and "|cff00ff00activé|r" or "|cffff4040coupé|r")
  end

  -- Bascule une option par son nom (pour la commande slash). Renvoie vrai si trouvée.
  function r.basculerOption(nomOption)
    for _, opt in ipairs(p.options) do
      if opt.cle and opt.cle:lower() == nomOption and opt.type ~= "nombre" then
        r.changer(opt.cle, not db[opt.cle])
        dire(opt.libelle .. " : " .. (db[opt.cle] and "|cff00ff00oui|r" or "|cffff4040non|r"))
        return true
      end
    end
  end

  -- ------------------------------------------------------- chargement
  local ecouteur = CreateFrame("Frame")
  ecouteur:RegisterEvent("ADDON_LOADED")
  ecouteur:SetScript("OnEvent", function(self, _, nomCharge)
    if nomCharge ~= NOM_ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")
    local sauve = _G[p.nomDB] or {}
    _G[p.nomDB] = sauve
    for cle, valeur in pairs(p.defauts) do
      if sauve[cle] == nil then sauve[cle] = type(valeur) == "table" and {} or valeur end
    end
    db = sauve
    r.db = db
    -- Une seule fois : l'icône à part laisse la place à l'icône commune.
    if not db.iconeCommune then db.minimap = false; db.iconeCommune = true end
    -- Réglages du compte ou propres à ce personnage : la table de travail reçoit les bonnes valeurs
    -- avant que l'addon les lise.
    local nomJoueur = UnitName and UnitName("player")
    if nomJoueur == UNKNOWNOBJECT then nomJoueur = nil end
    moi = ns.nomProfil(nomJoueur, GetRealmName and GetRealmName())
    ns.chargerProfil(db, cles, moi, p.defauts)
    r.hub = ns.inscrireAuHub({
      titre = p.titre, icone = p.icone, db = db, ouvrir = r.montrer, basculer = r.basculer,
      panneau = p.ouvrirHub, textePanneau = p.texteHub, page = page, recherche = recherche, allerOnglet = choisirOnglet,
      actif = function() return db.actif and true or false end,
      partage = {
        nom = NOM_ADDON, options = optionsParCle,
        lire = function() return ns.copierReglages(db, cles) end,
        poser = function(cle, valeur) r.changer(cle, valeur) end,
      },
    })
    placerMini()
    if p.auChargement then p.auChargement(db) end
    r.appliquer()
    -- Une nouveauté que cet addon n'a pas encore montrée : un seul message pour tous les addons.
    if hub.annoncerNouveautes and ns.ilYADuNeuf(ns.NOUVEAUTES, db.nouveautesVues) then hub.annoncerNouveautes() end
  end)

  return r
end
