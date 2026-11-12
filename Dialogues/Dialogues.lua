-- ============================================================================
-- Dialogues de quête : un affichage à la place de la fenêtre de dialogue des PNJ, en cinq styles
-- (réglage « style », changeable sans /reload : /dial style compact, bandeau, scene, face ou cinema) :
--   compact : UN SEUL cadre compact au centre, juste au-dessus des barres d'action : la tête du PNJ en
--             3D à gauche, son nom, le titre de la quête et le texte à droite ; les réponses et les
--             récompenses en boutons empilés à droite du cadre (le style par défaut) ;
--   bandeau : le bandeau d'origine, décrit ci-dessous ;
--   scene   : un grand modèle 3D animé du PNJ à gauche, une boîte de texte en bas au centre, les
--             réponses et récompenses en cartes à droite ;
--   face    : comme la scène, avec ton personnage à droite ; le texte en haut, les cartes en bas ;
--   cinema  : deux bandes noires, le texte dans celle du bas, les cartes à droite.
-- Le texte peut s'écrire lettre par lettre (option « machine »). Le style ne change que l'affichage.
--
-- Quand tu parles à un PNJ, la fenêtre du jeu (GossipFrame, QuestFrame) devient invisible et un
-- bandeau sombre à bordure dorée prend sa place :
--   - à gauche, le portrait rond du PNJ ; au centre, son nom, le titre de la quête (en doré) et son
--     texte, affiché PAR MORCEAUX (une page à la fois, « 2 / 3 ») ;
--   - en bas à droite, le bouton d'action avec sa touche : « Suivant » tant qu'il reste des pages,
--     puis « Accepter » (et « Refuser »), « Continuer », « Terminer la quête » ou « Au revoir » ;
--   - au-dessus du bandeau, la liste des réponses (numérotées de 1 à 9) ou des récompenses à choisir.
--
-- Clavier (option « Les touches ») : Espace = le bouton d'action, 1 à 9 = une réponse ou une
-- récompense, Échap = fermer. Les autres touches passent au jeu (tu peux te déplacer et sauter).
-- En combat, le bandeau ne prend AUCUNE touche (le jeu interdit de les rendre au jeu en combat) :
-- la souris marche toujours.
--
-- Ce que l'addon ne fait jamais :
--   - couper les événements de la fenêtre du jeu (c'est ce qui rend Immersion fragile) ;
--   - écrire dans un cadre de Blizzard (un champ écrit = un cadre « contaminé ») ;
--   - agir sans un clic ou une touche de ta part (le bot n'existe pas ici) ;
--   - te laisser bloqué devant un PNJ : si l'affichage lève une erreur, la fenêtre du jeu est
--     remontrée aussitôt, et le bouton « Fenêtre du jeu » du bandeau la rend à la demande.
--
-- Commandes : /dial (réglages)   /dial jeu (affichage ou fenêtre du jeu)   /dial test   /dial style   /dial aide
--
-- Le fichier a deux parties : la logique pure (testée hors jeu, tests/Dialogues_simu.lua) puis
-- tout ce qui parle au jeu.
-- ============================================================================

local NOM_ADDON, ns = ...

local DEFAUTS = {
  actif = true,
  morceaux = true,     -- le texte page par page (décoché : tout d'un coup)
  touches = true,      -- Espace, 1 à 9 et Échap
  conseil = true,      -- « Mieux pour toi » sous une récompense, quand Sacs rangés le dit
  style = "compact",   -- l'affichage : "compact", "bandeau", "scene", "face" ou "cinema" (voir ns.STYLES)
  machine = true,      -- le texte s'écrit lettre par lettre (Espace affiche tout, puis avance)
  tailleTexte = 17,
  largeur = 30,        -- en % de la largeur de l'écran (styles compact et bandeau)
  fenetreJeu = false,  -- vrai : on garde la fenêtre du jeu (rien de nous ne s'affiche)
  minimap = false,
}

-- ---------------------------------------------------------------------------
-- Partie « logique pure » : aucune fonction du jeu, donc testable hors jeu.
-- ---------------------------------------------------------------------------

-- Le nombre de caractères d'un texte (un caractère accentué compte pour un, pas pour deux octets).
local function longueur(t)
  local _, suites = t:gsub("[\128-\191]", "")
  return #t - suites
end
ns.longueur = longueur

local function rogner(t) return (t:gsub("^%s+", ""):gsub("%s+$", "")) end

-- Coupe une phrase trop longue entre deux mots (jamais au milieu d'un mot : un mot plus long que
-- la taille maximale reste entier). Renvoie une liste de morceaux.
local function couperEntreMots(phrase, tailleMax)
  local morceaux, courant = {}, nil
  for mot in phrase:gmatch("%S+") do
    if not courant then
      courant = mot
    elseif longueur(courant) + 1 + longueur(mot) <= tailleMax then
      courant = courant .. " " .. mot
    else
      morceaux[#morceaux + 1] = courant
      courant = mot
    end
  end
  if courant then morceaux[#morceaux + 1] = courant end
  return morceaux
end

-- Les phrases d'un paragraphe. Une phrase finit par . ! ? ou … suivi d'un espace (ou de la fin),
-- avec les guillemets fermants qui suivent. « M. Dupont » ne se coupe pas après « M. ».
-- Les caractères à plusieurs octets (…, », ”, ’) sont comparés par sous-chaînes : dans une classe
-- de caractères, ils seraient coupés en octets.
local function phrasesDe(par)
  local liste, debut, i, n = {}, 1, 1, #par
  while i <= n do
    local c = par:sub(i, i)
    local fin
    if c == "." or c == "!" or c == "?" then
      fin = i
      while par:sub(fin + 1, fin + 1):match("[%.!%?]") do fin = fin + 1 end
      -- Une initiale (« M. ») n'est pas une fin de phrase.
      if c == "." and fin == i and par:sub(1, i):match("%f[%a]%u%.$") and par:sub(i + 1, i + 1) == " " then
        fin = nil
      end
    elseif par:sub(i, i + 2) == "…" then
      fin = i + 2
    end
    if fin then
      local suite = par:sub(fin + 1, fin + 1)
      if suite == '"' or suite == "'" then
        fin = fin + 1
      elseif par:sub(fin + 1, fin + 2) == "»" then
        fin = fin + 2
      elseif par:sub(fin + 1, fin + 3) == "”" or par:sub(fin + 1, fin + 3) == "’" then
        fin = fin + 3
      else
        local j = fin + 1
        while par:sub(j, j) == " " do j = j + 1 end
        if j > fin + 1 and par:sub(j, j + 1) == "»" then fin = j + 1 end
      end
      local apres = par:sub(fin + 1, fin + 1)
      if apres == "" or apres:match("%s") then
        local p = rogner(par:sub(debut, fin))
        if p ~= "" then liste[#liste + 1] = p end
        debut = fin + 1
        i = fin + 1
      else
        i = fin + 1
      end
    else
      i = i + 1
    end
  end
  local reste = rogner(par:sub(debut))
  if reste ~= "" then liste[#liste + 1] = reste end
  return liste
end

-- Découpe un texte en pages d'au plus tailleMax caractères : d'abord aux paragraphes, puis aux fins
-- de phrase, enfin (une phrase trop longue) entre deux mots. Texte vide : { }.
function ns.decouper(texte, tailleMax)
  if type(texte) ~= "string" then return {} end
  tailleMax = tonumber(tailleMax) or 300
  if tailleMax < 10 then tailleMax = 10 end
  texte = texte:gsub("\r", "")
  local unites = {}
  local numeroPar = 0
  for brut in (texte .. "\n"):gmatch("(.-)\n") do
    local p = rogner(brut)
    if p ~= "" then
      numeroPar = numeroPar + 1
      if longueur(p) <= tailleMax then
        unites[#unites + 1] = { texte = p, par = numeroPar }
      else
        for _, ph in ipairs(phrasesDe(p)) do
          if longueur(ph) <= tailleMax then
            unites[#unites + 1] = { texte = ph, par = numeroPar }
          else
            for _, m in ipairs(couperEntreMots(ph, tailleMax)) do
              unites[#unites + 1] = { texte = m, par = numeroPar }
            end
          end
        end
      end
    end
  end
  -- On remplit chaque page tant que ça tient ; un nouveau paragraphe passe à la ligne.
  local pages, courant, parCourant = {}, nil, nil
  for _, u in ipairs(unites) do
    if not courant then
      courant, parCourant = u.texte, u.par
    else
      local sep = (u.par == parCourant) and " " or "\n"
      if longueur(courant) + #sep + longueur(u.texte) <= tailleMax then
        courant = courant .. sep .. u.texte
        parCourant = u.par
      else
        pages[#pages + 1] = courant
        courant, parCourant = u.texte, u.par
      end
    end
  end
  if courant then pages[#pages + 1] = courant end
  return pages
end

-- Combien de caractères tiennent sur une page : la largeur du texte (en pixels) divisée par la
-- largeur moyenne d'un caractère (environ 0,52 fois la taille de la police), sur 4 lignes (ou le
-- nombre de lignes demandé).
function ns.tailleMorceau(largeurTexte, taille, lignes)
  largeurTexte = tonumber(largeurTexte) or 600
  taille = tonumber(taille) or 15
  lignes = tonumber(lignes) or 4
  if lignes < 1 then lignes = 1 end
  if taille < 8 then taille = 8 end
  local parLigne = math.floor(largeurTexte / (taille * 0.52))
  local n = math.floor(parLigne * lignes * 0.9)
  if n < 120 then n = 120 end
  if n > 700 then n = 700 end
  return n
end

-- Les pages d'un échange : le texte (par morceaux ou d'un bloc), puis l'objectif de la quête en
-- dernière page (ou ajouté au bloc quand le texte n'est pas coupé).
function ns.pagesDe(texte, objectif, morceaux, tailleMax)
  texte = type(texte) == "string" and rogner(texte) or ""
  objectif = type(objectif) == "string" and rogner(objectif) or ""
  local etiquette = objectif ~= "" and ("|cffffd200Objectif :|r " .. objectif) or nil
  if morceaux == false then
    local t = texte
    if etiquette then t = (t ~= "" and (t .. "\n\n") or "") .. etiquette end
    if t == "" then return {} end
    return { t }
  end
  local pages = ns.decouper(texte, tailleMax)
  if etiquette then pages[#pages + 1] = etiquette end
  return pages
end

-- L'indicateur de page : « 2 / 3 » (rien quand il n'y a qu'une page).
function ns.compteur(page, nombre)
  if type(nombre) ~= "number" or nombre <= 1 then return "" end
  return (tonumber(page) or 1) .. " / " .. nombre
end

-- Un montant en pièces de cuivre, en français : « 1 po 20 pa 5 pc ».
function ns.texteArgent(cuivre)
  cuivre = tonumber(cuivre) or 0
  if cuivre < 0 then cuivre = 0 end
  cuivre = math.floor(cuivre)
  local po, pa, pc = math.floor(cuivre / 10000), math.floor((cuivre % 10000) / 100), cuivre % 100
  local t = {}
  if po > 0 then t[#t + 1] = po .. " po" end
  if pa > 0 then t[#t + 1] = pa .. " pa" end
  if pc > 0 or #t == 0 then t[#t + 1] = pc .. " pc" end
  return table.concat(t, " ")
end

-- Le code couleur d'un lien d'objet (« |cffa335ee|Hitem:…|h[Nom]|h|r » donne « ffa335ee »), ou blanc.
function ns.couleurDeLien(lien)
  if type(lien) == "string" then
    local c = lien:match("|c(%x%x%x%x%x%x%x%x)")
    if c then return c end
  end
  return "ffffffff"
end

-- Le nom d'un objet de récompense avec sa couleur de qualité et son nombre.
function ns.nomObjet(o)
  local nom = type(o) == "table" and type(o.nom) == "string" and o.nom or ""
  if nom == "" then nom = "Objet" end
  local t = "|c" .. ns.couleurDeLien(o and o.lien) .. nom .. "|r"
  if type(o) == "table" and type(o.nombre) == "number" and o.nombre > 1 then t = t .. " x" .. o.nombre end
  return t
end

-- Le bouton d'action de l'étape (le grand bouton en bas à droite).
--   etape : "gossip" | "greeting" | "detail" | "progress" | "complete"
--   page / nombrePages : la page affichée, le nombre de pages
--   completable : la quête peut être rendue (étape « progress »)
--   nbChoix / choix : combien de récompenses au choix, laquelle est choisie (nil : aucune)
-- Renvoie { libelle, action, actif }. Les actions : suivant, accepter, continuer, terminer, fermer.
function ns.boutonAction(etape, page, nombrePages, completable, nbChoix, choix)
  page, nombrePages = tonumber(page) or 1, tonumber(nombrePages) or 0
  if page < nombrePages then return { libelle = "Suivant", action = "suivant", actif = true } end
  if etape == "detail" then return { libelle = "Accepter", action = "accepter", actif = true } end
  if etape == "progress" then
    if completable then return { libelle = "Continuer", action = "continuer", actif = true } end
    return { libelle = "Au revoir", action = "fermer", actif = true }
  end
  if etape == "complete" then
    if (tonumber(nbChoix) or 0) > 1 and not choix then
      return { libelle = "Choisis une récompense", action = "terminer", actif = false }
    end
    return { libelle = "Terminer la quête", action = "terminer", actif = true }
  end
  return { libelle = "Au revoir", action = "fermer", actif = true }
end
ns.etape = ns.boutonAction

-- Le petit bouton à côté du grand (nil : pas de second bouton). Seulement à la dernière page.
function ns.boutonSecondaire(etape, page, nombrePages, completable)
  page, nombrePages = tonumber(page) or 1, tonumber(nombrePages) or 0
  if page < nombrePages then return nil end
  if etape == "detail" then return { libelle = "Refuser", action = "refuser", actif = true } end
  if etape == "progress" and completable then return { libelle = "Au revoir", action = "fermer", actif = true } end
  return nil
end

-- La liste numérotée des réponses : les quêtes à rendre (finies d'abord, marque « ? »), les quêtes
-- à prendre (« ! »), puis les phrases du PNJ. Neuf au plus : le second résultat dit combien ont été
-- laissées de côté (pour le dire au joueur, qui garde la fenêtre du jeu).
--   chaque élément : { title/name, questID | indice | gossipOptionID, isComplete, source }
function ns.reponses(aRendre, aPrendre, phrases)
  local liste, total = {}, 0
  local function ajouter(genre, marque, e, texte, fini)
    if type(texte) ~= "string" or texte == "" then return end
    total = total + 1
    if #liste >= 9 then return end
    liste[#liste + 1] = {
      numero = #liste + 1, genre = genre, marque = marque, texte = texte, fini = fini,
      valeur = e.questID or e.indice or e.gossipOptionID, source = e.source,
    }
  end
  local finies, autres = {}, {}
  for _, q in ipairs(aRendre or {}) do
    if type(q) == "table" then
      if q.isComplete then finies[#finies + 1] = q else autres[#autres + 1] = q end
    end
  end
  for _, q in ipairs(finies) do ajouter("rendre", "?", q, q.title, true) end
  for _, q in ipairs(autres) do ajouter("rendre", "?", q, q.title, false) end
  for _, q in ipairs(aPrendre or {}) do
    if type(q) == "table" then ajouter("prendre", "!", q, q.title, false) end
  end
  for _, o in ipairs(phrases or {}) do
    if type(o) == "table" then ajouter("phrase", "", o, o.name, false) end
  end
  return liste, total - #liste
end

-- La touche appuyée donne-t-elle une action ? Renvoie nil (la touche passe au jeu), ou
--   "bouton"            : le bouton d'action (Espace)
--   "ignorer"           : Espace alors que le bouton est grisé (la touche est prise sans rien faire)
--   "fermer"            : Échap
--   "reponse", n        : la réponse n° n (étapes gossip et greeting)
--   "choix", n          : la récompense n° n (étape complete)
-- etat : { affiche, touches, combat, modificateur, etape, derniere, nbReponses, nbChoix, boutonActif }
function ns.toucheVers(touche, etat)
  if type(touche) ~= "string" or type(etat) ~= "table" then return nil end
  if not etat.affiche or not etat.touches or etat.combat or etat.modificateur then return nil end
  if touche == "SPACE" then
    if etat.boutonActif == false then return "ignorer" end
    return "bouton"
  end
  if touche == "ESCAPE" then return "fermer" end
  local n = tonumber(touche:match("^(%d)$") or touche:match("^NUMPAD(%d)$"))
  if n and n >= 1 and etat.derniere then
    if (etat.etape == "gossip" or etat.etape == "greeting") and n <= (tonumber(etat.nbReponses) or 0) then
      return "reponse", n
    end
    if etat.etape == "complete" and n <= (tonumber(etat.nbChoix) or 0) then return "choix", n end
  end
  return nil
end

-- Sacs rangés ajoute, dans la bulle de chaque objet qui améliore ce que tu portes, une ligne
-- « Mieux pour <spécialisation> : raison ». On la relit dans les lignes de la bulle (sans les codes
-- couleur) et on la reformule : « Mieux pour toi : raison ». nil si aucune ligne ne commence ainsi.
function ns.avisDepuisLignes(lignes)
  for _, l in ipairs(lignes or {}) do
    if type(l) == "string" then
      local t = rogner(l:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
      if t:sub(1, 10) == "Mieux pour" then
        local raison = t:match("^Mieux pour[^:]*:%s*(.-)%s*$")
        if raison and raison ~= "" then return "Mieux pour toi : " .. raison end
        return "Mieux pour toi"
      end
    end
  end
  return nil
end

local COULEUR_OR = "|cffffd200"

-- Les lignes de la liste au-dessus du bandeau, pour l'état d'un échange (fonction pure).
-- Seulement à la dernière page. Chaque ligne : { type = titre | texte | reponse | objet | choix, … }.
function ns.lignesListe(e)
  local l = {}
  if type(e) ~= "table" then return l end
  local nb = #(e.pages or {})
  if (e.page or 1) < nb then return l end
  local function titre(t) l[#l + 1] = { type = "titre", texte = t } end
  local function objets(liste, type_, genre)
    for i, o in ipairs(liste or {}) do
      l[#l + 1] = {
        type = type_, texte = ns.nomObjet(o), icone = o.icone, lien = o.lien, genre = genre, indice = o.indice or i,
        numero = (type_ == "choix" and i <= 9) and i or nil, choisi = (type_ == "choix" and e.choix == i) or nil,
        conseil = e.conseils and e.conseils[genre .. (o.indice or i)] or nil, test = e.test,
      }
    end
  end
  local function argentEtXp(rec)
    if rec and (rec.argent or 0) > 0 then l[#l + 1] = { type = "texte", texte = "Or : " .. ns.texteArgent(rec.argent) } end
    if rec and (rec.xp or 0) > 0 then l[#l + 1] = { type = "texte", texte = "Expérience : " .. rec.xp } end
  end
  local rec = e.recompenses or {}
  local etape = e.etape
  if etape == "gossip" or etape == "greeting" then
    for _, r in ipairs(e.reponses or {}) do
      l[#l + 1] = { type = "reponse", numero = r.numero, marque = r.marque, texte = r.texte, fini = r.fini, reponse = r }
    end
    if (e.reste or 0) > 0 then
      l[#l + 1] = { type = "texte", texte = "+ " .. e.reste .. " autres : clique sur « Fenêtre du jeu »." }
    end
  elseif etape == "detail" then
    if #(rec.choix or {}) > 0 then titre("Au choix :"); objets(rec.choix, "objet", "choice") end
    if #(rec.fixes or {}) > 0 then titre("Tu recevras :"); objets(rec.fixes, "objet", "reward") end
    argentEtXp(rec)
  elseif etape == "progress" then
    if #(e.requis or {}) > 0 then titre("Objets demandés :"); objets(e.requis, "objet", "required") end
    if (e.argentRequis or 0) > 0 then
      l[#l + 1] = { type = "texte", texte = "Or demandé : " .. ns.texteArgent(e.argentRequis) }
    end
  elseif etape == "complete" then
    local nbc = #(rec.choix or {})
    if nbc > 0 then
      titre(nbc > 1 and "Choisis ta récompense :" or "Récompense :")
      objets(rec.choix, "choix", "choice")
    end
    if #(rec.fixes or {}) > 0 then titre(nbc > 0 and "Tu recevras aussi :" or "Tu recevras :"); objets(rec.fixes, "objet", "reward") end
    argentEtXp(rec)
  end
  return l
end

-- Les styles d'affichage, dans l'ordre. Un nom inconnu (réglage abîmé) vaut "compact".
ns.STYLES = { "compact", "bandeau", "scene", "face", "cinema" }
local NOMS_STYLES = { compact = "compact", bandeau = "bandeau", scene = "scène", face = "face à face", cinema = "cinéma" }
local ALIAS_STYLES = {
  compact = "compact", bandeau = "bandeau", scene = "scene", ["scène"] = "scene", face = "face", ["face à face"] = "face",
  ["face a face"] = "face", facealface = "face", cinema = "cinema", ["cinéma"] = "cinema",
}

function ns.styleValide(s)
  for _, v in ipairs(ns.STYLES) do
    if s == v then return v end
  end
  return "compact"
end

-- Les réponses et récompenses du style compact : les boutons et les titres dans l'ordre, puis toutes
-- les lignes de texte simple (or, expérience, « + 2 autres ») réunies en UNE ligne discrète tout en bas.
function ns.pileCompacte(specs)
  local pile, lignes = {}, {}
  for _, s in ipairs(type(specs) == "table" and specs or {}) do
    if type(s) == "table" then
      if s.type == "texte" then
        if type(s.texte) == "string" and s.texte ~= "" then lignes[#lignes + 1] = s.texte end
      else
        pile[#pile + 1] = s
      end
    end
  end
  if #lignes > 0 then pile[#pile + 1] = { type = "texte", texte = table.concat(lignes, "   ") } end
  return pile
end

-- Passe une fois du style « scene » (l'ancien style par défaut) au style « compact », dans les
-- réglages du compte et dans ceux de chaque personnage. Ensuite, un choix explicite de « scene » reste.
function ns.migrerCompact(d)
  if type(d) ~= "table" or d.migreCompact then return false end
  d.migreCompact = true
  local function passer(t)
    if type(t) == "table" and t.style == "scene" then
      t.style = "compact"
      if t.largeur == 70 then t.largeur = 30 end -- l'ancien défaut de la largeur
    end
  end
  passer(d)
  passer(d.compte)
  if type(d.parPerso) == "table" then
    for _, p in pairs(d.parPerso) do passer(p) end
  end
  return true
end

-- Le nom lisible d'un style : « scène », « face à face »…
function ns.nomStyle(s) return NOMS_STYLES[ns.styleValide(s)] end

-- Le style que désigne un texte tapé (« scene », « scène », « face à face »…), nil si inconnu.
function ns.styleDepuisTexte(t)
  if type(t) ~= "string" then return nil end
  return ALIAS_STYLES[rogner(t):lower()]
end

-- Lit un texte caractère visible par caractère visible : un caractère accentué (2 à 4 octets) compte
-- pour un, les codes couleur « |cAARRGGBB » et « |r » ne comptent pas, « || » compte pour un.
-- S'arrête dès que `limite` caractères visibles sont lus. Rend l'index du premier octet non lu, le
-- nombre de caractères visibles lus, et si une couleur est encore ouverte.
local function balayer(texte, limite)
  local i, len, vus, ouvert = 1, #texte, 0, false
  while i <= len and vus < limite do
    local c = texte:byte(i)
    if c == 124 then -- le caractère |
      local s = texte:sub(i + 1, i + 1)
      if s == "c" and texte:sub(i + 2, i + 9):find("^%x%x%x%x%x%x%x%x$") then
        i = i + 10
        ouvert = true
      elseif s == "r" then
        i = i + 2
        ouvert = false
      elseif s == "|" then
        i = i + 2
        vus = vus + 1
      else
        i = i + 1
        vus = vus + 1
      end
    else
      i = i + ((c >= 240 and 4) or (c >= 224 and 3) or (c >= 192 and 2) or 1)
      vus = vus + 1
    end
  end
  return i, vus, ouvert
end

-- Le nombre de caractères visibles d'un texte (sans les codes couleur).
function ns.longueurVisible(texte)
  if type(texte) ~= "string" then return 0 end
  local _, vus = balayer(texte, math.huge)
  return vus
end

-- Les n premiers caractères visibles d'un texte, pour l'écrire lettre par lettre : jamais coupé au
-- milieu d'un caractère UTF-8 ni d'un code couleur ; une couleur restée ouverte est refermée.
-- n <= 0 : "" ; n au moins égal à la longueur visible : le texte entier.
function ns.morceauTexte(texte, n)
  if type(texte) ~= "string" then return "" end
  n = math.floor(tonumber(n) or 0)
  if n <= 0 then return "" end
  local i, vus, ouvert = balayer(texte, n)
  if vus < n then return texte end
  local reste = texte:sub(i)
  if ns.longueurVisible(reste) == 0 then return texte end
  return texte:sub(1, i - 1) .. (ouvert and "|r" or "")
end

-- ---------------------------------------------------------------------------
-- Tout ce qui parle au jeu
-- ---------------------------------------------------------------------------

if not CreateFrame then return end -- hors jeu : la suite ne sert qu'en jeu

-- Un appel protégé qui rend les résultats de la fonction (ou rien si elle manque ou échoue).
local function suite(ok, ...) if ok then return ... end end
local function sur(f, ...)
  if type(f) ~= "function" then return nil end
  return suite(pcall(f, ...))
end

local function estSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) == true end
-- Un texte lisible : une chaîne qui n'est pas une « secret value », sinon "".
local function chaine(v)
  if type(v) == "string" and not estSecret(v) then return v end
  return ""
end
local function entier(v)
  if type(v) == "number" and not estSecret(v) then return v end
  return 0
end

-- Vrai pour true, mais aussi pour 1 : le jeu rend parfois un nombre là où on attend un booléen
-- (Blizzard teste ces retours par simple vérité). Une « secret value » n'est jamais vraie.
local function vrai(v)
  if estSecret(v) then return false end
  return v ~= nil and v ~= false and v ~= 0
end

local function enCombat() return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false end

local db
local bandeau, liste      -- les deux cadres à nous
local etat                -- l'échange affiché (nil : rien)
local courant             -- l'étape ouverte côté jeu : "gossip", "greeting", "detail", "progress", "complete"
local generation = 0      -- change à chaque événement : une réponse en retard est ignorée
local repli = false       -- vrai : la fenêtre du jeu garde la main jusqu'à la fin de cet échange
local pannes = 0          -- erreurs d'affichage depuis la connexion (trois : on laisse le jeu tranquille)
local avertiPanne, avertiImmersion = false, false

local function dire(texte)
  if ns.reglages then ns.reglages.dire(texte) else print("|cffffd200Dialogues de quête|r : " .. texte) end
end

local function apres(delai, f)
  if C_Timer and type(C_Timer.After) == "function" then C_Timer.After(delai, f) else f() end
end

-- ------------------------------------------------------------ la fenêtre du jeu
-- Choix du masquage. Écrire un champ dans GossipFrame ou QuestFrame les « contamine », et les
-- cacher (Hide) ferait fermer l'échange. On les laisse donc ouvertes, avec leurs événements, et on
-- leur applique seulement deux appels de méthode (jamais d'écriture de champ) :
--   - SetAlpha(0) : invisibles. Permis même en combat ;
--   - EnableMouse(false) : elles ne prennent plus de clics invisibles sur le monde. Seulement hors
--     combat (un cadre sécurisé est intouchable en combat) ; remis à la fin du combat sinon.
--   - SetScale(0.001) : les boutons enfants gardent leur souris même quand le cadre parent ne
--     l'a plus, donc on réduit la fenêtre à un point (un clic dans le décor ne tombe plus sur un
--     bouton invisible, ce qui lancerait une option sans que le joueur le voie). Même règle que
--     la souris : hors combat seulement, remis à la fin du combat sinon.
local FENETRES_JEU = { "GossipFrame", "QuestFrame" }
local alphaAvant = {}   -- [nom] = l'opacité d'avant (à remettre)
local sourisAvant = {}  -- [nom] = vrai/faux : l'état de la souris d'avant, tant qu'on ne l'a pas remis
local echelleAvant = {}  -- [nom] = l'échelle d'avant, tant qu'on ne l'a pas remise
local ECHELLE_CACHEE = 0.001

local function masquerJeu()
  for _, nom in ipairs(FENETRES_JEU) do
    local f = _G[nom]
    if f then
      if alphaAvant[nom] == nil then
        local a = entier(sur(f.GetAlpha, f))
        if a == 0 then a = 1 end
        alphaAvant[nom] = a
      end
      sur(f.SetAlpha, f, 0)
      if sourisAvant[nom] == nil and not enCombat() then
        sourisAvant[nom] = (sur(f.IsMouseEnabled, f) ~= false)
        sur(f.EnableMouse, f, false)
        local ech = entier(sur(f.GetScale, f))
        if ech <= ECHELLE_CACHEE then ech = 1 end
        echelleAvant[nom] = ech
        sur(f.SetScale, f, ECHELLE_CACHEE)
      end
    end
  end
end

-- Remet la souris et l'échelle des fenêtres du jeu (hors combat seulement).
local function remettreSouris()
  if enCombat() then return end
  for _, nom in ipairs(FENETRES_JEU) do
    local f = _G[nom]
    if f and sourisAvant[nom] ~= nil then sur(f.EnableMouse, f, sourisAvant[nom]) end
    if f and echelleAvant[nom] ~= nil then sur(f.SetScale, f, echelleAvant[nom]) end
    sourisAvant[nom] = nil
    echelleAvant[nom] = nil
  end
end

local function rendreJeu()
  for _, nom in ipairs(FENETRES_JEU) do
    local f = _G[nom]
    if f and alphaAvant[nom] ~= nil then sur(f.SetAlpha, f, alphaAvant[nom]) end
    alphaAvant[nom] = nil
  end
  remettreSouris() -- en combat : repoussé à la fin du combat (finirRemiseJeu)
end

-- À la fin du combat : la souris des fenêtres du jeu qu'on n'avait pas pu remettre. Seulement si
-- elles ne sont plus masquées : si l'échange est encore ouvert (alpha 0), la souris reste coupée.
local function finirRemiseJeu()
  if next(alphaAvant) == nil then remettreSouris() end
end

local function immersionPresent()
  if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then return sur(C_AddOns.IsAddOnLoaded, "Immersion") == true end
  if type(IsAddOnLoaded) == "function" then return sur(IsAddOnLoaded, "Immersion") == true end
  return false
end

-- Doit-on prendre la main sur cet échange ?
local function prise()
  if not (db and db.actif) or db.fenetreJeu or pannes >= 3 then return false end
  if immersionPresent() then
    if not avertiImmersion then
      avertiImmersion = true
      dire("Immersion est chargé : je n'affiche rien tant qu'il est là, pour ne pas me mêler à lui.")
    end
    return false
  end
  return true
end

-- ------------------------------------------------------------ lire l'échange en cours
local function unitePNJ()
  for _, u in ipairs({ "npc", "questnpc" }) do
    local existe = sur(UnitExists, u)
    if not estSecret(existe) and existe then return u end
  end
end

local function listeDe(f)
  local l = sur(f)
  return type(l) == "table" and l or {}
end

-- Les objets d'un genre : « choice » (au choix), « reward » (fixes), « required » (demandés).
local function lireObjets(genre, nombre)
  local liste_ = {}
  for i = 1, math.min(entier(nombre), 20) do
    local nom, icone, nb, qualite = sur(GetQuestItemInfo, genre, i)
    local lien = sur(GetQuestItemLink, genre, i)
    liste_[i] = {
      genre = genre, indice = i, nom = chaine(nom), icone = icone, nombre = entier(nb), qualite = qualite,
      lien = chaine(lien) ~= "" and lien or nil,
    }
  end
  return liste_
end

-- Ce que Sacs rangés dit d'un objet : les lignes de la bulle qui s'affiche en ce moment.
local function lignesBulle()
  local l = {}
  if not GameTooltip then return l end
  local n = entier(sur(GameTooltip.NumLines, GameTooltip))
  for i = 1, math.min(n, 40) do
    local fs = _G["GameTooltipTextLeft" .. i]
    local t = fs and chaine(sur(fs.GetText, fs))
    if t and t ~= "" then l[#l + 1] = t end
  end
  return l
end

-- Pose la bulle d'une récompense, hors écran, pour la lire (sans toucher à une bulle déjà affichée).
local function avisObjet(genre, indice)
  if not (GameTooltip and sur(GameTooltip.IsShown, GameTooltip) ~= true) then return nil end
  sur(GameTooltip.SetOwner, GameTooltip, UIParent, "ANCHOR_NONE")
  sur(GameTooltip.SetQuestItem, GameTooltip, genre, indice)
  local avis = ns.avisDepuisLignes(lignesBulle())
  sur(GameTooltip.Hide, GameTooltip)
  return avis
end

local function lireRecompenses()
  local rec = {
    choix = lireObjets("choice", sur(GetNumQuestChoices)),
    fixes = lireObjets("reward", sur(GetNumQuestRewards)),
    argent = entier(sur(GetRewardMoney)),
    xp = entier(sur(GetRewardXP)),
  }
  return rec
end

local largeurBandeau, largeurTexte -- définies avec l'affichage, plus bas

local styleActuel -- définie avec l'affichage, plus bas

local function tailleMax()
  -- Le style compact a un cadre qui grandit : cinq lignes par page au lieu de quatre.
  return ns.tailleMorceau(largeurTexte(), db.tailleTexte, (styleActuel() == "compact") and 5 or 4)
end

local function paginer(e)
  e.pages = ns.pagesDe(e.texte, e.objectif, db.morceaux, tailleMax())
  if e.page > math.max(#e.pages, 1) then e.page = 1 end
end

-- Construit l'état d'un échange à partir de ce que le jeu dit maintenant.
local function lireEtape(etape)
  local e = { etape = etape, page = 1, unite = unitePNJ(), recompenses = {}, reponses = {}, reste = 0, conseils = {} }
  if e.unite then e.pnj = chaine(sur(UnitName, e.unite)) end
  e.pnj = e.pnj or ""
  if etape == "gossip" then
    local c = C_GossipInfo or {}
    e.texte = chaine(sur(c.GetText))
    local aRendre, aPrendre, phrases = {}, {}, {}
    for _, q in ipairs(listeDe(c.GetActiveQuests)) do
      if type(q) == "table" then aRendre[#aRendre + 1] = { title = chaine(q.title), questID = q.questID, isComplete = q.isComplete == true, source = "gossip" } end
    end
    for _, q in ipairs(listeDe(c.GetAvailableQuests)) do
      if type(q) == "table" then aPrendre[#aPrendre + 1] = { title = chaine(q.title), questID = q.questID, source = "gossip" } end
    end
    for _, o in ipairs(listeDe(c.GetOptions)) do
      if type(o) == "table" then phrases[#phrases + 1] = { name = chaine(o.name), gossipOptionID = o.gossipOptionID, source = "gossip" } end
    end
    e.reponses, e.reste = ns.reponses(aRendre, aPrendre, phrases)
  elseif etape == "greeting" then
    e.texte = chaine(sur(GetGreetingText))
    local aRendre, aPrendre = {}, {}
    for i = 1, entier(sur(GetNumActiveQuests)) do
      local titre, finie = sur(GetActiveTitle, i)
      aRendre[#aRendre + 1] = { title = chaine(titre), indice = i, isComplete = vrai(finie), source = "greeting" }
    end
    for i = 1, entier(sur(GetNumAvailableQuests)) do
      aPrendre[#aPrendre + 1] = { title = chaine(sur(GetAvailableTitle, i)), indice = i, source = "greeting" }
    end
    e.reponses, e.reste = ns.reponses(aRendre, aPrendre, {})
  elseif etape == "detail" then
    e.titre = chaine(sur(GetTitleText))
    e.texte = chaine(sur(GetQuestText))
    e.objectif = chaine(sur(GetObjectiveText))
    e.recompenses = lireRecompenses()
  elseif etape == "progress" then
    e.titre = chaine(sur(GetTitleText))
    e.texte = chaine(sur(GetProgressText))
    e.completable = vrai(sur(IsQuestCompletable))
    e.requis = lireObjets("required", sur(GetNumQuestItems))
    e.argentRequis = entier(sur(GetQuestMoneyToGet))
  elseif etape == "complete" then
    e.titre = chaine(sur(GetTitleText))
    e.texte = chaine(sur(GetRewardText))
    e.recompenses = lireRecompenses()
  end
  e.nbChoix = #(e.recompenses.choix or {})
  -- Une seule récompense au choix : elle est déjà choisie.
  if etape == "complete" and e.nbChoix == 1 then e.choix = 1 end
  if db.conseil and (etape == "complete" or etape == "detail") then
    for i, o in ipairs(e.recompenses.choix or {}) do
      local avis = e.nbChoix > 1 and avisObjet("choice", o.indice or i) or nil
      if avis then e.conseils["choice" .. (o.indice or i)] = avis end
    end
  end
  paginer(e)
  return e
end

-- ------------------------------------------------------------ l'affichage : quatre styles
-- Le style ne change QUE l'affichage (jamais les événements, les touches, le repli sur la fenêtre du
-- jeu ni le combat) :
--   bandeau : le bandeau d'origine, en bas de l'écran ;
--   scene   : un grand modèle 3D du PNJ à gauche, la boîte de texte en bas au centre, les réponses en
--             cartes empilées à droite ;
--   face    : comme la scène, avec en plus ton personnage à droite ; la boîte de texte passe en haut
--             et les cartes en bas au centre ;
--   cinema  : deux bandes noires, le texte dans celle du bas, le modèle du PNJ juste au-dessus, les
--             cartes à droite entre les deux bandes.
-- Tout est en strate "DIALOG" : sur la même strate que les fenêtres du jeu, la souris leur restait
-- (vu en jeu). Les modèles 3D n'ont pas de souris, et tout ce qui les touche est protégé.
local OR = { 0.80, 0.63, 0.30, 1 }
local BORDURE_SOMBRE = { 0.30, 0.25, 0.15, 1 }
local FOND_LIGNE = { 0.12, 0.10, 0.07, 0.95 }
local FOND_LIGNE_CHOISIE = { 0.28, 0.21, 0.08, 0.98 }
local FOND_CARTE = { 0.08, 0.065, 0.045, 0.97 }
local FOND_BOITE = { 0.04, 0.035, 0.03, 0.97 }
local FOND_COMPACT = { 0.035, 0.03, 0.025, 0.97 }
local NOIR = { 0, 0, 0, 1 }
local TRANSPARENT = { 0, 0, 0, 0 }
local LARGEUR_LISTE, NB_LIGNES_MAX = 430, 24
local LARGEUR_PILE = 260       -- style compact : la largeur d'un bouton de la pile
local TETE = 96                -- style compact : le côté du portrait carré
local ANGLE_PNJ, ANGLE_JOUEUR = 0.4, -0.4 -- en radians : à régler en jeu si les regards ne se croisent pas
local CARACTERES_PAR_SECONDE = 60
local POLICE_TITRE = "Fonts\\MORPHEUS.TTF" -- la plus proche d'un italique dans le jeu

local function police() return STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF" end

-- Pose une police ; si le chemin est refusé, retombe sur la police du jeu (un texte sans police lève une erreur).
local function poserPolice(fs, chemin, taille, drapeaux)
  if not sur(fs.SetFont, fs, chemin, taille, drapeaux or "") then
    sur(fs.SetFont, fs, police(), taille, drapeaux or "")
  end
end

-- Met un cadre à nous sur la strate des fenêtres de dialogue.
local function dialog(f)
  if f and f.SetFrameStrata then sur(f.SetFrameStrata, f, "DIALOG") end
  return f
end

-- Un disque : une texture avec son masque rond (sans masque, un carré : rien ne casse).
local function arrondir(cadre, texture)
  local ok, masque = pcall(cadre.CreateMaskTexture, cadre)
  if ok and masque and texture.AddMaskTexture then
    masque:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    masque:SetAllPoints(texture)
    texture:AddMaskTexture(masque)
  end
end

local function largeurEcran()
  local l = (UIParent and entier(sur(UIParent.GetWidth, UIParent))) or 1920
  if l <= 0 then l = 1920 end
  return l
end

local function hauteurEcran()
  local h = (UIParent and entier(sur(UIParent.GetHeight, UIParent))) or 1080
  if h <= 0 then h = 1080 end
  return h
end

styleActuel = function() return ns.styleValide(db and db.style) end

-- La largeur de la boîte principale (le bandeau, la boîte de texte ou la bande du bas).
local function largeurBandeau()
  local ecran = largeurEcran()
  local style = styleActuel()
  if style == "cinema" then return ecran end
  local l
  if style == "compact" then
    -- Un cadre étroit : 30 % de l'écran par défaut, 360 px au moins, jamais plus large que l'écran.
    l = math.floor(ecran * ((tonumber(db and db.largeur) or 30) / 100))
    if l < 360 then l = 360 end
    if l > ecran - 20 then l = ecran - 20 end
    return l
  end
  if style == "scene" or style == "face" then
    l = math.floor(ecran * ((style == "face") and 0.5 or 0.45))
  else
    l = math.floor(ecran * ((tonumber(db and db.largeur) or 70) / 100))
  end
  if l > ecran - 20 then l = ecran - 20 end
  if l < 480 then l = math.min(480, ecran - 20) end
  if style == "bandeau" and l < 640 then l = math.min(640, ecran - 20) end
  return l
end

-- La largeur du texte du PNJ, en pixels, selon le style.
largeurTexte = function()
  local style = styleActuel()
  if style == "bandeau" then return largeurBandeau() - 152 end
  if style == "compact" then return largeurBandeau() - 140 end
  if style == "cinema" then return math.floor(largeurEcran() * 0.5) end
  return largeurBandeau() - 48
end

-- La largeur de la colonne des réponses (le bandeau : celle d'origine).
local function largeurListe(style)
  if style == "bandeau" then return LARGEUR_LISTE end
  if style == "compact" then return LARGEUR_PILE + 12 end
  return math.max(300, math.floor(largeurEcran() * ((style == "face") and 0.36 or 0.26)))
end

local actionBouton, actionSecondaire, fermerEchange, choisirReponse, choisirRecompense, replierSurLeJeu
local echec -- définie plus bas ; déclarée ici pour que les gestionnaires du bandeau la voient

local touchesPrises = {} -- les touches prises par le bandeau et encore enfoncées (pour ignorer la répétition)

-- Une carte (ou une ligne) change de couleur au survol et quand elle est choisie : dorée.
local function colorerCarte(l, survol)
  local s = l.spec
  if not l.carte or not s or s.type == "titre" or s.type == "texte" then return end
  local fort = survol or s.choisi
  ns.habiller(l, { fond = fort and FOND_LIGNE_CHOISIE or FOND_CARTE, bordure = fort and OR or BORDURE_SOMBRE })
end

local function creerLigne(i)
  local l = CreateFrame("Button", nil, liste, "BackdropTemplate")
  dialog(l)
  l:SetHeight(24)
  l:SetWidth(LARGEUR_LISTE - 12)
  ns.habiller(l, { fond = FOND_LIGNE, bordure = BORDURE_SOMBRE })
  l.numero = l:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  l.numero:SetPoint("LEFT", 8, 0)
  l.marque = l:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  l.marque:SetPoint("LEFT", 26, 0)
  l.icone = l:CreateTexture(nil, "ARTWORK")
  l.icone:SetSize(22, 22)
  l.icone:SetPoint("LEFT", 28, 0)
  l.texte = l:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  l.texte:SetJustifyH("LEFT")
  l.conseil = l:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  l.conseil:SetJustifyH("LEFT")
  l.conseil:SetTextColor(0.12, 1, 0)
  l:SetScript("OnClick", function(self)
    local s = self.spec
    if not s or not etat or etat.occupe then return end
    local ok, err
    if s.type == "reponse" then ok, err = pcall(choisirReponse, s.reponse)
    elseif s.type == "choix" then ok, err = pcall(choisirRecompense, s.indice)
    else return end
    if not ok then echec(err) end
  end)
  l:SetScript("OnEnter", function(self)
    colorerCarte(self, true)
    local s = self.spec
    if not s or not (s.lien or s.test) or not GameTooltip then return end
    GameTooltip:SetOwner(self, (styleActuel() == "compact") and "ANCHOR_RIGHT" or "ANCHOR_LEFT")
    if s.test then
      GameTooltip:AddLine("Un objet pour essayer")
    elseif s.genre then
      pcall(GameTooltip.SetQuestItem, GameTooltip, s.genre, s.indice)
    end
    GameTooltip:Show()
    -- La bulle est affichée : si Sacs rangés y a mis son avis, on le montre aussi sous l'objet.
    if db.conseil and s.type == "choix" and not s.conseil then
      local avis = ns.avisDepuisLignes(lignesBulle())
      if avis and etat then etat.conseils[s.genre .. s.indice] = avis; self.conseil:SetText(avis); self.conseil:Show() end
    end
  end)
  l:SetScript("OnLeave", function(self)
    colorerCarte(self, false)
    if GameTooltip then GameTooltip:Hide() end
  end)
  return l
end

-- ------------------------------------------------------------ l'écriture lettre par lettre
-- Le texte de la page s'écrit à CARACTERES_PAR_SECONDE (option « machine »). L'état est dans
-- l'échange (e.ecr) : la page, le temps écoulé, le nombre de caractères visibles. Seul un cadre
-- à nous porte le script OnUpdate, et seulement pendant l'écriture.
local function terminerEcriture()
  local e, b = etat, bandeau
  if not e or not b or not e.ecr or e.ecr.fini then return end
  e.ecr.fini = true
  b.ecrivain:SetScript("OnUpdate", nil)
  b.texte:SetText(e.ecr.complet)
end

local function avancerEcriture(dt)
  local e, b = etat, bandeau
  if not b then return end
  local ec = e and e.ecr
  if not ec or ec.fini then b.ecrivain:SetScript("OnUpdate", nil) return end
  ec.t = ec.t + (tonumber(dt) or 0)
  local n = math.floor(ec.t * CARACTERES_PAR_SECONDE)
  if n >= ec.total then terminerEcriture() return end
  if n ~= ec.n then
    ec.n = n
    b.texte:SetText(ns.morceauTexte(ec.complet, n))
  end
end

-- ------------------------------------------------------------ les modèles 3D
-- Un modèle sans souris, sur la bonne strate, caché au départ ; nil si le jeu refuse de le créer.
local function creerModele(nom, parent)
  local ok, m = pcall(function()
    local f = CreateFrame("PlayerModel", nom, parent)
    dialog(f)
    f:EnableMouse(false)
    f:Hide()
    return f
  end)
  if ok then return m end
end

-- Charge l'unité dans le modèle ; sans unité (PNJ disparu) ou si le jeu refuse, le modèle est caché.
local function chargerModele(m, unite, angle)
  if not m then return end
  if not unite then
    sur(m.ClearModel, m)
    m:Hide()
    return
  end
  local ok = pcall(function()
    m:SetUnit(unite)
    sur(m.SetPortraitZoom, m, 0)
    sur(m.SetCamDistanceScale, m, 1)
    sur(m.SetFacing, m, angle)
  end)
  if ok then m:Show() else m:Hide() end
end

-- Le portrait du style compact : la tête du PNJ en 3D, cadrée de près. Sans modèle (le jeu refuse),
-- l'image ronde du portrait prend la place dans le même carré.
local function chargerTete(m, unite)
  -- Le modèle se charge un peu après SetUnit et reprend alors l'orientation du PNJ (vu en jeu le
  -- 12/11 : visage de profil quand le PNJ se tourne vers le joueur). Une fois chargé, on le remet
  -- de face, cadré sur la tête.
  if m.SetScript then
    pcall(m.SetScript, m, "OnModelLoaded", function(self)
      sur(self.SetPortraitZoom, self, 1)
      sur(self.SetCamDistanceScale, self, 1)
      sur(self.SetFacing, self, 0)
    end)
  end
  local ok = pcall(function()
    m:SetUnit(unite)
    sur(m.SetPortraitZoom, m, 1)
    sur(m.SetCamDistanceScale, m, 1)
    sur(m.SetFacing, m, 0)
  end)
  if ok then m:Show() else m:Hide() end
  return ok
end

local function majTete(e)
  local b = bandeau
  if not b.cadrePortrait then return end
  b.cadrePortrait:Show()
  local unite = e.test and "player" or unitePNJ()
  local cle = tostring(unite) .. "|" .. (e.test and "t" or "r")
  if b.teteCle == cle then return end
  b.teteCle = cle
  local ok = false
  if b.modeleTete and unite then ok = chargerTete(b.modeleTete, unite) end
  if ok then
    b.teteTexture:Hide()
    return
  end
  if b.modeleTete then b.modeleTete:Hide() end
  if unite then
    sur(SetPortraitTexture, b.teteTexture, unite)
    b.teteTexture:Show()
  else
    b.teteTexture:Hide()
  end
end

-- Place les modèles selon le style et charge ce qui a changé (un échange, un style, une unité).
local function majModeles(e, style)
  local b = bandeau
  local mp, mj = b.modelePNJ, b.modeleJoueur
  if style == "bandeau" or style == "compact" then
    if mp then mp:Hide() end
    if mj then mj:Hide() end
    b.modeleCle = nil
    if style == "compact" then
      majTete(e)
    else
      if b.modeleTete then b.modeleTete:Hide() end
      b.teteCle = nil
    end
    return
  end
  if b.modeleTete then b.modeleTete:Hide() end
  b.teteCle = nil
  local ecran, haut = largeurEcran(), hauteurEcran()
  local hm = math.floor(haut * 0.40)
  local lm = math.floor(hm * 0.6)
  local function placer(m, point, x, y)
    if not m then return end
    m:ClearAllPoints()
    m:SetSize(lm, hm)
    m:SetPoint(point, UIParent, point, x, y)
  end
  local bas = (style == "cinema") and entier(sur(b.GetHeight, b)) or 0
  placer(mp, "BOTTOMLEFT", math.floor(ecran * ((style == "scene") and 0.03 or 0.04)), bas)
  if style == "face" then placer(mj, "BOTTOMRIGHT", -math.floor(ecran * 0.04), 0) end
  local unite = e.test and "player" or unitePNJ()
  local cle = style .. "|" .. tostring(unite) .. "|" .. (e.test and "t" or "r")
  if b.modeleCle ~= cle then
    b.modeleCle = cle
    chargerModele(mp, unite, ANGLE_PNJ)
    if style == "face" then chargerModele(mj, "player", ANGLE_JOUEUR) elseif mj then mj:Hide() end
  end
end

-- ------------------------------------------------------------ le cadre principal
local function creerBandeau()
  if bandeau then return bandeau end
  local b = CreateFrame("Frame", "DialoguesBandeau", UIParent, "BackdropTemplate")
  b:SetFrameStrata("DIALOG")
  b:SetHeight(180)
  b:EnableMouse(true)
  b:Hide()
  local _, croix = ns.habiller(b, { fermer = true, fond = { 0.06, 0.05, 0.04, 0.95 } })
  if croix then
    dialog(croix)
    croix:SetScript("OnClick", function() fermerEchange() end)
  end

  -- Le portrait (style bandeau) : un anneau doré et le visage du PNJ, tous deux ronds.
  b.anneau = b:CreateTexture(nil, "BACKGROUND")
  b.anneau:SetSize(92, 92)
  b.anneau:SetPoint("TOPLEFT", 20, -18)
  b.anneau:SetColorTexture(OR[1], OR[2], OR[3], 1)
  arrondir(b, b.anneau)
  b.portrait = b:CreateTexture(nil, "ARTWORK")
  b.portrait:SetSize(84, 84)
  b.portrait:SetPoint("CENTER", b.anneau, "CENTER", 0, 0)
  arrondir(b, b.portrait)

  b.nomPNJ = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.nomPNJ:SetPoint("TOPLEFT", 128, -14)
  b.nomPNJ:SetJustifyH("LEFT")
  b.titreQuete = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  b.titreQuete:SetPoint("TOPLEFT", 128, -30)
  b.titreQuete:SetJustifyH("LEFT")
  b.titreQuete:SetTextColor(1, 0.82, 0.30)
  b.texte = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  b.texte:SetPoint("TOPLEFT", 128, -56)
  b.texte:SetJustifyH("LEFT")
  b.texte:SetJustifyV("TOP")
  b.compteur = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  b.compteur:SetPoint("BOTTOMLEFT", 128, 18)

  b.bouton = dialog(ns.creerBouton(b, "Suivant", nil, function()
    local ok, err = pcall(actionBouton)
    if not ok then echec(err) end
  end, 190))
  b.bouton:SetHeight(30)
  b.bouton:SetPoint("BOTTOMRIGHT", -20, 14)
  b.boutonDeux = dialog(ns.creerBouton(b, "Refuser", nil, function()
    local ok, err = pcall(actionSecondaire)
    if not ok then echec(err) end
  end, 120))
  b.boutonDeux:SetHeight(30)
  b.boutonDeux:Hide()
  -- La touche du bouton d'action, dans une petite case à sa gauche.
  b.caseTouche = dialog(CreateFrame("Frame", nil, b, "BackdropTemplate"))
  b.caseTouche:SetSize(56, 24)
  b.caseTouche:SetPoint("RIGHT", b.bouton, "LEFT", -6, 0)
  ns.habiller(b.caseTouche, { fond = { 0.14, 0.12, 0.08, 1 }, bordure = OR })
  b.caseTouche.texte = b.caseTouche:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.caseTouche.texte:SetPoint("CENTER", 0, 0)
  b.caseTouche.texte:SetText("Espace")
  b.boutonDeux:SetPoint("RIGHT", b.caseTouche, "LEFT", -16, 0)

  -- Le recours : rendre la main à la fenêtre du jeu pour cet échange.
  b.boutonJeu = dialog(ns.creerBouton(b, "Fenêtre du jeu", "Montre la fenêtre de dialogue du jeu à la place de l'affichage, jusqu'à la fin de cet échange.",
    function() replierSurLeJeu() end, 110))
  b.boutonJeu:SetHeight(18)
  b.boutonJeu:SetPoint("TOPRIGHT", -30, -6)

  b:SetScript("OnKeyDown", function(self, touche)
    -- Une touche prise qu'on garde enfoncée se répète : on ignore les répétitions (sinon Espace
    -- maintenu ferait défiler les pages sans les laisser lire, puis accepterait).
    if touchesPrises[touche] and not enCombat() then
      sur(self.SetPropagateKeyboardInput, self, false)
      return
    end
    local ok, pris = pcall(ns.surTouche, self, touche)
    if not ok then echec(pris) return end
    if pris then touchesPrises[touche] = true end
  end)
  b:SetScript("OnKeyUp", function(self, touche)
    touchesPrises[touche] = nil
    -- Une touche relâchée repasse toujours au jeu (sinon une touche de déplacement relâchée
    -- pendant qu'on appuie sur Espace resterait « enfoncée »). Jamais en combat.
    if not enCombat() then sur(self.SetPropagateKeyboardInput, self, true) end
  end)

  liste = CreateFrame("Frame", "DialoguesListe", b, "BackdropTemplate")
  dialog(liste)
  liste:SetWidth(LARGEUR_LISTE)
  liste:SetPoint("BOTTOMRIGHT", b, "TOPRIGHT", 0, 4)
  ns.habiller(liste, { fond = { 0.06, 0.05, 0.04, 0.95 } })
  liste:Hide()
  b.liste = liste
  b.lignes = {}

  -- Style cinéma : la bande noire du haut. Les modèles 3D. Le cadre qui écrit le texte lettre par lettre.
  b.bandeHaut = dialog(CreateFrame("Frame", "DialoguesBandeHaut", b, "BackdropTemplate"))
  ns.habiller(b.bandeHaut, { fond = NOIR, bordure = TRANSPARENT })
  b.bandeHaut:EnableMouse(false)
  b.bandeHaut:Hide()
  b.modelePNJ = creerModele("DialoguesModelePNJ", b)
  b.modeleJoueur = creerModele("DialoguesModeleJoueur", b)
  -- Style compact : le portrait carré (cadre doré, fond sombre) avec la tête du PNJ en 3D dedans.
  b.cadrePortrait = dialog(CreateFrame("Frame", "DialoguesCadrePortrait", b, "BackdropTemplate"))
  b.cadrePortrait:SetSize(TETE, TETE)
  b.cadrePortrait:EnableMouse(false)
  ns.habiller(b.cadrePortrait, { fond = { 0.03, 0.025, 0.02, 1 }, bordure = OR })
  b.cadrePortrait:Hide()
  b.teteTexture = b.cadrePortrait:CreateTexture(nil, "ARTWORK")
  b.teteTexture:SetPoint("TOPLEFT", 4, -4)
  b.teteTexture:SetPoint("BOTTOMRIGHT", -4, 4)
  b.teteTexture:Hide()
  b.modeleTete = creerModele("DialoguesModeleTete", b.cadrePortrait)
  if b.modeleTete then
    b.modeleTete:SetPoint("TOPLEFT", 4, -4)
    b.modeleTete:SetPoint("BOTTOMRIGHT", -4, 4)
  end
  b.ecrivain = dialog(CreateFrame("Frame", "DialoguesEcrivain", b))
  b.surEcriture = function(_, dt)
    local ok, err = pcall(avancerEcriture, dt)
    if not ok then echec(err) end
  end
  bandeau = b
  return b
end

-- Place et dimensionne le cadre principal, la colonne des réponses, la bande du haut (cinéma).
local function appliquerStyle()
  if not bandeau then return end
  local b = bandeau
  local style = styleActuel()
  local ecran, haut = largeurEcran(), hauteurEcran()
  local marge = math.floor(ecran * 0.012)
  b:SetWidth(largeurBandeau())
  b:ClearAllPoints()
  liste:ClearAllPoints()
  if style == "bandeau" then
    b:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 36)
    ns.habiller(b, { fermer = true, fond = { 0.06, 0.05, 0.04, 0.95 } })
    liste:SetPoint("BOTTOMRIGHT", b, "TOPRIGHT", 0, 4)
    ns.habiller(liste, { fond = { 0.06, 0.05, 0.04, 0.95 } })
  elseif style == "compact" then
    -- Juste au-dessus des barres d'action ; la pile de réponses se place à droite à chaque tracé.
    b:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, math.floor(haut * 0.12))
    ns.habiller(b, { fermer = true, fond = FOND_COMPACT, bordure = OR })
    liste:SetPoint("BOTTOMLEFT", b, "TOPRIGHT", 6, -38)
    ns.habiller(liste, { fond = TRANSPARENT, bordure = TRANSPARENT })
  else
    if style == "cinema" then
      b:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 0)
      ns.habiller(b, { fermer = true, fond = NOIR, bordure = TRANSPARENT })
      liste:SetPoint("RIGHT", UIParent, "RIGHT", -marge, math.floor(haut * 0.08))
    elseif style == "face" then
      b:SetPoint("TOP", UIParent, "TOP", 0, -40)
      ns.habiller(b, { fermer = true, fond = FOND_BOITE, bordure = OR })
      liste:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 40)
    else
      b:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 40)
      ns.habiller(b, { fermer = true, fond = FOND_BOITE, bordure = OR })
      liste:SetPoint("RIGHT", UIParent, "RIGHT", -marge, 0)
    end
    ns.habiller(liste, { fond = TRANSPARENT, bordure = TRANSPARENT })
  end
  liste:SetWidth(largeurListe(style))
  b.anneau:SetShown(style == "bandeau")
  b.cadrePortrait:SetShown(style == "compact")
  b.bandeHaut:ClearAllPoints()
  b.bandeHaut:SetSize(ecran, math.floor(haut * 0.12))
  b.bandeHaut:SetPoint("TOP", UIParent, "TOP", 0, 0)
  b.bandeHaut:SetShown(style == "cinema")
end

-- Le contenu d'une ligne du style bandeau (celui d'origine). Rend la hauteur de la ligne.
local function texteMarque(s)
  if s.reponse.genre == "rendre" then return s.fini and "|cffffd200?|r" or "|cff999999?|r" end
  return "|cffffd200!|r"
end

local function remplirLigneBandeau(l, s)
  local avecObjet = (s.type == "choix" or s.type == "objet")
  local haut = avecObjet and ((s.conseil and 40) or 30) or 24
  if s.type == "titre" or s.type == "texte" then haut = 20 end
  -- Fond : aucun pour un simple titre ou texte, doré pour la récompense choisie.
  if s.type == "titre" or s.type == "texte" then
    ns.habiller(l, { fond = { 0, 0, 0, 0 }, bordure = { 0, 0, 0, 0 } })
  else
    ns.habiller(l, { fond = s.choisi and FOND_LIGNE_CHOISIE or FOND_LIGNE, bordure = s.choisi and OR or BORDURE_SOMBRE })
  end
  l.numero:ClearAllPoints()
  l.numero:SetPoint("LEFT", 8, 0)
  l.marque:ClearAllPoints()
  l.marque:SetPoint("LEFT", 26, 0)
  l.icone:ClearAllPoints()
  l.icone:SetSize(22, 22)
  l.icone:SetPoint("LEFT", 28, 0)
  l.numero:SetText(s.numero and tostring(s.numero) or "")
  l.numero:SetTextColor(1, 0.82, 0)
  sur(l.numero.SetFontObject, l.numero, _G.GameFontNormal)
  l.marque:SetText("")
  l.icone:Hide()
  l.conseil:ClearAllPoints()
  l.conseil:SetText("")
  l.conseil:Hide()
  l.texte:ClearAllPoints()
  if s.type == "titre" then
    l.texte:SetPoint("LEFT", 8, 0)
    l.texte:SetText(COULEUR_OR .. s.texte .. "|r")
  elseif s.type == "texte" then
    l.texte:SetPoint("LEFT", 8, 0)
    l.texte:SetText("|cffdddddd" .. s.texte .. "|r")
  elseif s.type == "reponse" then
    local couleur = (s.reponse.genre == "rendre" and not s.fini) and "|cff999999" or "|cffffffff"
    if s.marque ~= "" then
      l.marque:SetText(texteMarque(s))
      l.texte:SetPoint("LEFT", 46, 0)
    else
      l.texte:SetPoint("LEFT", 28, 0)
    end
    l.texte:SetText(couleur .. s.texte .. "|r")
  else -- objet ou choix
    if s.icone then l.icone:SetTexture(s.icone); l.icone:Show() end
    l.texte:SetPoint("LEFT", 58, s.conseil and 7 or 0)
    l.texte:SetText(s.texte)
    if s.conseil then
      l.conseil:SetPoint("LEFT", 58, -9)
      l.conseil:SetText(s.conseil)
      l.conseil:Show()
    end
  end
  l.texte:SetWidth(LARGEUR_LISTE - 80)
  return haut
end

-- Le contenu d'une carte (styles scène, face à face et cinéma) : numéro doré, icône, texte qui
-- passe à la ligne, ligne verte « Mieux pour toi ». Rend la hauteur de la carte.
local function remplirCarte(l, s, lw)
  local larg = lw - 12
  l.numero:ClearAllPoints()
  l.marque:ClearAllPoints()
  l.icone:ClearAllPoints()
  l.texte:ClearAllPoints()
  l.conseil:ClearAllPoints()
  l.numero:SetText(s.numero and tostring(s.numero) or "")
  l.numero:SetTextColor(1, 0.82, 0)
  sur(l.numero.SetFontObject, l.numero, _G.GameFontNormal)
  l.marque:SetText("")
  l.icone:Hide()
  l.conseil:SetText("")
  l.conseil:Hide()
  sur(l.texte.SetWordWrap, l.texte, true)
  if s.type == "titre" or s.type == "texte" then
    ns.habiller(l, { fond = TRANSPARENT, bordure = TRANSPARENT })
    l.texte:SetPoint("TOPLEFT", 8, -3)
    l.texte:SetWidth(larg - 16)
    l.texte:SetText(s.type == "titre" and (COULEUR_OR .. s.texte .. "|r") or ("|cffdddddd" .. s.texte .. "|r"))
    return math.max(20, entier(sur(l.texte.GetStringHeight, l.texte)) + 8)
  end
  colorerCarte(l, false)
  local x0 = s.numero and 30 or 10
  if s.numero then l.numero:SetPoint("TOPLEFT", 10, -10) end
  if s.type == "reponse" then
    local couleur = (s.reponse.genre == "rendre" and not s.fini) and "|cff999999" or "|cffffffff"
    local x = x0
    if s.marque ~= "" then
      l.marque:SetText(texteMarque(s))
      l.marque:SetPoint("TOPLEFT", x0, -7)
      x = x0 + 18
    end
    l.texte:SetPoint("TOPLEFT", x, -10)
    l.texte:SetWidth(larg - x - 10)
    l.texte:SetText(couleur .. s.texte .. "|r")
    return math.max(38, entier(sur(l.texte.GetStringHeight, l.texte)) + 20)
  end
  -- objet ou choix
  if s.icone then
    l.icone:SetTexture(s.icone)
    l.icone:SetSize(28, 28)
    l.icone:SetPoint("TOPLEFT", x0, -8)
    l.icone:Show()
  end
  local x = x0 + 34
  l.texte:SetPoint("TOPLEFT", x, -9)
  l.texte:SetWidth(larg - x - 10)
  l.texte:SetText(s.texte)
  l.conseil:SetPoint("TOPLEFT", l.texte, "BOTTOMLEFT", 0, -3)
  l.conseil:SetWidth(larg - x - 10)
  local extra = 0
  if s.conseil then
    l.conseil:SetText(s.conseil)
    l.conseil:Show()
    extra = 16
  end
  local mini = (s.type == "choix" and db.conseil) and 56 or 46
  return math.max(mini, entier(sur(l.texte.GetStringHeight, l.texte)) + extra + 20)
end

-- Les petites icônes du jeu pour les boutons du style compact.
local ICONE_PRENDRE = "Interface\\GossipFrame\\AvailableQuestIcon"       -- le point d'exclamation doré
local ICONE_RENDRE = "Interface\\GossipFrame\\ActiveQuestIcon"            -- le point d'interrogation doré
local ICONE_RENDRE_GRIS = "Interface\\GossipFrame\\IncompleteQuestIcon"   -- le même, grisé (quête pas finie)
local ICONE_PHRASE = "Interface\\GossipFrame\\GossipGossipIcon"           -- la bulle de dialogue

-- Le contenu d'un bouton de la pile du style compact (260 px de large) : icône à gauche, texte clair
-- qui passe à la ligne, numéro de touche discret à droite, ligne verte « Mieux pour toi » sous un
-- objet. Un titre ou la ligne d'or et d'expérience n'ont ni fond ni bordure. Rend la hauteur.
local function remplirBoutonCompact(l, s)
  local larg = LARGEUR_PILE
  l.numero:ClearAllPoints()
  l.marque:ClearAllPoints()
  l.icone:ClearAllPoints()
  l.texte:ClearAllPoints()
  l.conseil:ClearAllPoints()
  l.numero:SetText("")
  l.marque:SetText("")
  l.icone:Hide()
  l.conseil:SetText("")
  l.conseil:Hide()
  sur(l.texte.SetWordWrap, l.texte, true)
  if s.type == "titre" or s.type == "texte" then
    ns.habiller(l, { fond = TRANSPARENT, bordure = TRANSPARENT })
    l.texte:SetPoint("TOPLEFT", 4, -2)
    l.texte:SetWidth(larg - 8)
    l.texte:SetText(s.type == "titre" and (COULEUR_OR .. s.texte .. "|r") or ("|cffb8b09c" .. s.texte .. "|r"))
    return math.max(18, entier(sur(l.texte.GetStringHeight, l.texte)) + 6)
  end
  colorerCarte(l, false)
  local droite = (db.touches and s.numero) and 28 or 10
  if db.touches and s.numero then
    sur(l.numero.SetFontObject, l.numero, _G.GameFontNormalSmall)
    l.numero:SetTextColor(0.72, 0.64, 0.42)
    l.numero:SetText(tostring(s.numero))
    l.numero:SetPoint("RIGHT", -9, 0)
  end
  local x, haut
  if s.type == "reponse" then
    local chemin = ICONE_PHRASE
    if s.reponse.genre == "prendre" then
      chemin = ICONE_PRENDRE
    elseif s.reponse.genre == "rendre" then
      chemin = s.fini and ICONE_RENDRE or ICONE_RENDRE_GRIS
    end
    l.icone:SetTexture(chemin)
    l.icone:SetSize(20, 20)
    l.icone:SetPoint("LEFT", 8, 0)
    l.icone:Show()
    x = 36
    local couleur = (s.reponse.genre == "rendre" and not s.fini) and "|cff999999" or "|cffffffff"
    l.texte:SetWidth(larg - x - droite)
    l.texte:SetText(couleur .. s.texte .. "|r")
    local ht = entier(sur(l.texte.GetStringHeight, l.texte))
    if ht <= 18 then l.texte:SetPoint("LEFT", x, 0) else l.texte:SetPoint("TOPLEFT", x, -7) end
    haut = math.max(30, ht + 14)
  else -- un objet (récompense ou demandé)
    if s.icone then
      l.icone:SetTexture(s.icone)
      l.icone:SetSize(26, 26)
      l.icone:SetPoint("LEFT", 6, 0)
      l.icone:Show()
    end
    x = 38
    l.texte:SetWidth(larg - x - droite)
    l.texte:SetText(s.texte)
    local ht = entier(sur(l.texte.GetStringHeight, l.texte))
    local extra = 0
    if s.conseil then
      l.conseil:SetPoint("TOPLEFT", l.texte, "BOTTOMLEFT", 0, -2)
      l.conseil:SetWidth(larg - x - droite)
      l.conseil:SetText(s.conseil)
      l.conseil:Show()
      extra = 16
    end
    if ht <= 18 and extra == 0 then l.texte:SetPoint("LEFT", x, 0) else l.texte:SetPoint("TOPLEFT", x, -7) end
    haut = math.max(extra > 0 and 46 or 32, ht + extra + 14)
  end
  return haut
end

-- Remplit la liste des réponses ou des récompenses (au-dessus du bandeau, en cartes, ou en pile de
-- boutons à droite du cadre dans le style compact).
local function tracerListe(specs)
  local style = styleActuel()
  local cartes = style ~= "bandeau"
  local compact = style == "compact"
  if compact then specs = ns.pileCompacte(specs) end
  local lw = largeurListe(style)
  liste:SetWidth(lw)
  local nb = math.min(#specs, NB_LIGNES_MAX)
  if nb == 0 then liste:Hide() return end
  local y = compact and 0 or 8
  local limite = hauteurEcran() - 16 -- la pile ne dépasse jamais le haut de l'écran
  local affiches = 0
  for i = 1, nb do
    local s = specs[i]
    local l = bandeau.lignes[i]
    if not l then l = creerLigne(i); bandeau.lignes[i] = l end
    l.spec = s
    l.carte = cartes
    l:SetWidth(lw - 12)
    local clicable = (s.type == "reponse" or s.type == "choix")
    l:EnableMouse(clicable or (s.lien ~= nil) or (s.test == true))
    local haut
    if compact then haut = remplirBoutonCompact(l, s)
    elseif cartes then haut = remplirCarte(l, s, lw)
    else haut = remplirLigneBandeau(l, s) end
    if compact and i > 1 and y + haut > limite then break end
    l:SetHeight(haut)
    l:ClearAllPoints()
    l:SetPoint("TOPLEFT", liste, "TOPLEFT", 6, -y)
    y = y + haut + (compact and 4 or (cartes and 5 or 3))
    l:Show()
    affiches = i
  end
  for i = affiches + 1, #bandeau.lignes do bandeau.lignes[i]:Hide() end
  liste:SetHeight(compact and math.max(y - 4, 1) or (y + 5))
  liste:Show()
end

-- Style compact : la pile à droite du cadre, collée à son bord droit, son bas un peu sous le haut du
-- cadre (le premier bouton est donc à la hauteur du haut du cadre) ; elle monte vers le haut. Son haut
-- ne dépasse jamais celui de l'écran : sinon on la descend. Écran trop étroit pour la mettre à
-- droite : elle passe au-dessus du cadre.
local function placerPileCompacte()
  local b = bandeau
  if not b or not liste or styleActuel() ~= "compact" then return end
  local ecran, haut = largeurEcran(), hauteurEcran()
  local bas = math.floor(haut * 0.12)
  local hb = entier(sur(b.GetHeight, b))
  local hl = entier(sur(liste.GetHeight, liste))
  local lw = largeurListe("compact")
  local droiteCadre = math.floor(ecran / 2 + largeurBandeau() / 2)
  liste:ClearAllPoints()
  if droiteCadre + 6 + lw <= ecran - 8 then
    local decal = -38
    if bas + hb + decal + hl > haut - 8 then
      decal = math.max(8 - (bas + hb), (haut - 8 - hl) - (bas + hb))
    end
    liste:SetPoint("BOTTOMLEFT", b, "TOPRIGHT", 6, decal)
  else
    liste:SetPoint("BOTTOMRIGHT", b, "TOPRIGHT", 0, 4)
  end
end

-- Place le nom, le titre, le texte, le compteur et le bouton d'action selon le style, applique les
-- polices et les couleurs. Rend la hauteur occupée au-dessus du texte.
local function placerTextes(e, style)
  local b = bandeau
  local largeur = largeurBandeau()
  local lt = largeurTexte()
  local ecran = largeurEcran()
  local gauche, droite, yNom, yTitre, yTexte
  if style == "bandeau" then
    gauche, droite, yNom, yTitre, yTexte = 128, 20, 14, 30, 56
    sur(b.nomPNJ.SetFontObject, b.nomPNJ, _G.GameFontHighlightSmall)
    b.nomPNJ:SetTextColor(1, 1, 1)
    b.nomPNJ:SetWidth(0)
    sur(b.titreQuete.SetFontObject, b.titreQuete, _G.GameFontNormalLarge)
    b.texte:SetTextColor(1, 1, 1)
  elseif style == "compact" then
    -- À droite du portrait carré : le nom, le titre de la quête (plus petit), puis le texte.
    gauche, droite = 14 + TETE + 14, 12
    yNom, yTitre = 10, 33
    yTexte = ((e.titre or "") ~= "") and 53 or 36
    poserPolice(b.nomPNJ, POLICE_TITRE, 18, "")
    b.nomPNJ:SetTextColor(1, 0.82, 0.30)
    b.nomPNJ:SetWidth(math.max(100, lt - 110))
    poserPolice(b.titreQuete, police(), 13, "")
    b.texte:SetTextColor(0.95, 0.93, 0.88)
    -- Le portrait se pose dans le coin haut gauche du cadre. Sans ce point, il restait accroché
    -- nulle part et n'apparaissait pas (vu en jeu le 12/11).
    b.cadrePortrait:ClearAllPoints()
    b.cadrePortrait:SetPoint("TOPLEFT", b, "TOPLEFT", 14, -12)
  else
    gauche = (style == "cinema") and math.floor(ecran * 0.25) or 24
    droite = (style == "cinema") and gauche or 20
    yNom, yTitre = 14, 46
    yTexte = ((e.titre or "") ~= "") and 70 or 50
    poserPolice(b.nomPNJ, police(), 22, "")
    b.nomPNJ:SetTextColor(1, 0.82, 0.30)
    b.nomPNJ:SetWidth(math.max(100, lt - 150))
    poserPolice(b.titreQuete, POLICE_TITRE, 17, "")
    b.texte:SetTextColor(0.95, 0.93, 0.88)
  end
  b.titreQuete:SetTextColor(1, 0.82, 0.30)
  if style == "compact" then b.titreQuete:SetTextColor(1, 0.9, 0.62) end -- doré pâle
  b.nomPNJ:ClearAllPoints()
  b.nomPNJ:SetPoint("TOPLEFT", gauche, -yNom)
  b.titreQuete:ClearAllPoints()
  b.titreQuete:SetPoint("TOPLEFT", gauche, -yTitre)
  b.titreQuete:SetWidth(lt - 36)
  b.texte:ClearAllPoints()
  b.texte:SetPoint("TOPLEFT", gauche, -yTexte)
  b.texte:SetWidth(lt)
  poserPolice(b.texte, police(), tonumber(db.tailleTexte) or 15, "")
  b.bouton:ClearAllPoints()
  b.boutonDeux:ClearAllPoints()
  b.boutonJeu:ClearAllPoints()
  b.compteur:ClearAllPoints()
  if style == "compact" then
    -- Une rangée de petits boutons en bas à droite ; le compteur discret juste à leur gauche.
    b.bouton:SetSize(150, 26)
    b.bouton:SetPoint("BOTTOMRIGHT", -droite, 10)
    b.caseTouche:SetSize(46, 22)
    b.boutonDeux:SetSize(86, 26)
    b.boutonDeux:SetPoint("RIGHT", b.caseTouche:IsShown() and b.caseTouche or b.bouton, "LEFT", -8, 0)
    b.boutonJeu:SetSize(96, 18)
    b.boutonJeu:SetPoint("TOPRIGHT", -30, -5)
    local repere = b.bouton
    if b.caseTouche:IsShown() then repere = b.caseTouche end
    if b.boutonDeux:IsShown() then repere = b.boutonDeux end
    b.compteur:SetPoint("RIGHT", repere, "LEFT", -10, 0)
  else
    b.bouton:SetSize(190, 30)
    b.bouton:SetPoint("BOTTOMRIGHT", -droite, 14)
    b.caseTouche:SetSize(56, 24)
    b.boutonDeux:SetSize(120, 30)
    b.boutonDeux:SetPoint("RIGHT", b.caseTouche, "LEFT", -16, 0)
    b.boutonJeu:SetSize(110, 18)
    b.boutonJeu:SetPoint("TOPRIGHT", -30, -6)
    b.compteur:SetPoint("BOTTOMLEFT", gauche, 18)
  end
  return yTexte
end

-- L'écriture lettre par lettre de la page : démarre quand la page change (pas à chaque tracé).
local function gererEcriture(e, plein)
  local b = bandeau
  if db.machine and plein ~= "" then
    local cle = e.page .. "|" .. plein
    if not e.ecr or e.ecr.cle ~= cle then
      e.ecr = { cle = cle, complet = plein, total = ns.longueurVisible(plein), t = 0, n = 0, fini = false }
    end
    if e.ecr.fini then
      b.ecrivain:SetScript("OnUpdate", nil)
    else
      b.ecrivain:SetScript("OnUpdate", b.surEcriture)
      b.texte:SetText(ns.morceauTexte(e.ecr.complet, e.ecr.n))
    end
  else
    if e.ecr then e.ecr.fini = true end
    b.ecrivain:SetScript("OnUpdate", nil)
  end
end

-- Dessine l'état courant.
local function tracer()
  local e, b = etat, bandeau
  local style = styleActuel()
  local nb = #e.pages
  local plein = e.pages[e.page] or ""
  b.nomPNJ:SetText(e.pnj or "")
  b.titreQuete:SetText(e.titre or "")
  b.texte:SetText(plein) -- le texte entier d'abord : sa hauteur règle celle de la boîte
  b.compteur:SetText(ns.compteur(e.page, nb))

  local act = ns.boutonAction(e.etape, e.page, nb, e.completable, e.nbChoix, e.choix)
  b.bouton:SetText(act.libelle)
  if act.actif then b.bouton:Enable() else b.bouton:Disable() end
  e.action = act
  local deux = ns.boutonSecondaire(e.etape, e.page, nb, e.completable)
  e.secondaire = deux
  if deux then
    b.boutonDeux:SetText(deux.libelle)
    b.boutonDeux:Show()
  else
    b.boutonDeux:Hide()
  end
  b.caseTouche:SetShown(db.touches and true or false)

  local unite = e.test and "player" or e.unite
  if style == "bandeau" and unite then
    sur(SetPortraitTexture, b.portrait, unite)
    b.portrait:Show()
  else
    b.portrait:Hide()
  end
  tracerListe(ns.lignesListe(e))
  local yTexte = placerTextes(e, style)

  -- La hauteur suit celle du texte (plus de texte, une boîte plus haute).
  local h = entier(sur(b.texte.GetStringHeight, b.texte))
  local total
  if style == "bandeau" then
    total = 56 + math.max(h, 64) + 52
    if total < 150 then total = 150 end
    if total > 420 then total = 420 end
  elseif style == "compact" then
    -- Hauteur minimale : le portrait et ses marges ; le cadre grandit vers le haut avec le texte,
    -- jusqu'à 40 % de la hauteur de l'écran.
    total = yTexte + math.max(h, 34) + 44
    local mini = TETE + 28
    local maxi = math.max(mini, math.floor(hauteurEcran() * 0.40))
    if total < mini then total = mini end
    if total > maxi then total = maxi end
  else
    total = yTexte + math.max(h, 60) + 56
    if total < 140 then total = 140 end
    if total > 460 then total = 460 end
    if style == "cinema" then total = math.max(total, math.floor(hauteurEcran() * 0.28)) end
  end
  b:SetHeight(total)
  if style == "compact" then placerPileCompacte() end

  gererEcriture(e, plein)
  -- Les modèles 3D : une panne ici ne doit jamais gêner le dialogue.
  local okM, errM = pcall(majModeles, e, style)
  if not okM then ns.erreurModele = tostring(errM) end
end

local function clavierActif()
  if not bandeau or not db.touches or enCombat() then return end
  touchesPrises = {}
  sur(bandeau.SetPropagateKeyboardInput, bandeau, true)
  sur(bandeau.EnableKeyboard, bandeau, true)
end

-- Plus aucune touche prise (début de combat, bandeau fermé, option coupée). À appeler hors combat
-- ou à PLAYER_REGEN_DISABLED, quand les deux appels sont encore permis.
local function clavierCoupe()
  if not bandeau then return end
  touchesPrises = {} -- le relâchement d'une touche n'arrivera plus au bandeau
  sur(bandeau.SetPropagateKeyboardInput, bandeau, true)
  sur(bandeau.EnableKeyboard, bandeau, false)
end

local function cacherBandeau()
  if not bandeau then return end
  if not enCombat() then clavierCoupe() end
  bandeau:Hide()
end

-- Une erreur d'affichage : on le note, on le dit une fois, la fenêtre du jeu reprend la main.
echec = function(err)
  ns.derniereErreur = tostring(err)
  pannes = pannes + 1
  if not avertiPanne then
    avertiPanne = true
    dire("un souci d'affichage : la fenêtre du jeu reprend la main. (/dial test pour réessayer)")
  end
  etat = nil
  repli = courant ~= nil
  pcall(cacherBandeau)
  pcall(rendreJeu)
end

-- Fait une action du jeu pour le joueur ; une API absente ou en erreur rend la main au jeu.
local function faire(f, ...)
  if type(f) ~= "function" then echec("API du jeu absente") return false end
  local ok, err = pcall(f, ...)
  if not ok then echec(err) return false end
  return true
end

-- Après une action : le bandeau ignore les clics jusqu'à la suite (sinon un double clic accepterait
-- deux fois). Si le jeu n'envoie rien, on rend la main au bout de deux secondes.
local function occuper()
  if not etat then return end
  local e = etat
  e.occupe = true
  apres(2, function() if etat == e then e.occupe = false end end)
end

local function afficherEtat()
  creerBandeau()
  bandeau.modeleCle = nil -- un nouvel échange : les modèles 3D sont rechargés (« npc » peut être un autre PNJ)
  bandeau.teteCle = nil
  appliquerStyle()
  paginer(etat)
  tracer()
  bandeau:Show()
  clavierActif()
end

-- ------------------------------------------------------------ les actions du joueur
local function fermerBandeauSeulement()
  etat = nil
  cacherBandeau()
end

fermerEchange = function()
  local e = etat
  local etape = (e and e.etape) or courant
  if e and e.test then fermerBandeauSeulement() return end
  fermerBandeauSeulement()
  if etape == "gossip" then
    faire(C_GossipInfo and C_GossipInfo.CloseGossip)
  else
    faire(CloseQuest)
  end
  -- Pas d'événement de fermeture ? La fenêtre du jeu est remise dans les deux secondes.
  apres(2, function() if not etat then rendreJeu() end end)
end

replierSurLeJeu = function()
  repli = true
  generation = generation + 1
  fermerBandeauSeulement()
  rendreJeu()
end

choisirReponse = function(r)
  if not etat or etat.occupe or not r then return end
  local gossip = C_GossipInfo or {}
  local ok
  local ancien = (r.source == "greeting") -- les anciens PNJ (QUEST_GREETING) ont leurs propres fonctions
  if r.genre == "rendre" then
    if ancien then ok = faire(SelectActiveQuest, r.valeur) else ok = faire(gossip.SelectActiveQuest, r.valeur) end
  elseif r.genre == "prendre" then
    if ancien then ok = faire(SelectAvailableQuest, r.valeur) else ok = faire(gossip.SelectAvailableQuest, r.valeur) end
  else
    ok = faire(gossip.SelectOption, r.valeur)
  end
  if ok then occuper() end
end

choisirRecompense = function(n)
  local e = etat
  if not e or e.etape ~= "complete" or e.occupe then return end
  if n < 1 or n > e.nbChoix then return end
  e.choix = n
  tracer()
end

local function lancerTest() end -- définie plus bas

actionBouton = function()
  local e = etat
  if not e or e.occupe then return end
  -- Pendant l'écriture lettre par lettre, le premier appui affiche d'abord tout le texte.
  if e.ecr and not e.ecr.fini then terminerEcriture() return end
  if not e.action or not e.action.actif then return end
  local a = e.action.action
  if a == "suivant" then
    e.page = e.page + 1
    tracer()
    return
  end
  if e.test then
    lancerTest(e, a)
    return
  end
  local ok
  if a == "accepter" then
    -- Les confirmations du jeu (quête JcJ, quête déjà acceptée d'office) ne se contournent pas :
    -- on rend la main à la fenêtre du jeu, qui les pose.
    if vrai(sur(QuestFlagsPVP)) then
      dire("cette quête active le JcJ : la fenêtre du jeu te demande confirmation, accepte-la depuis elle.")
      replierSurLeJeu()
      return
    end
    if vrai(sur(QuestGetAutoAccept)) and type(AcknowledgeAutoAcceptQuest) == "function" then
      ok = faire(AcknowledgeAutoAcceptQuest)
    else
      ok = faire(AcceptQuest)
    end
  elseif a == "continuer" then ok = faire(CompleteQuest)
  elseif a == "terminer" then
    if entier(sur(GetQuestMoneyToGet)) > 0 then
      dire("cette quête te coûte de l'or : la fenêtre du jeu te demande confirmation, termine-la depuis elle.")
      replierSurLeJeu()
      return
    end
    ok = faire(GetQuestReward, e.choix or 0)
  elseif a == "fermer" then fermerEchange() return end
  if ok then occuper() end
end

actionSecondaire = function()
  local e = etat
  if not e or e.occupe or not e.secondaire then return end
  local a = e.secondaire.action
  if e.test then lancerTest(e, a) return end
  if a == "refuser" then
    -- Comme le jeu : refuser, c'est fermer la quête (DeclineQuest n'est pas une API du jeu).
    if faire(CloseQuest) then occuper() end
  elseif a == "fermer" then
    fermerEchange()
  end
end

-- Une touche (appelée par le script OnKeyDown du bandeau). Tout se décide hors combat :
-- SetPropagateKeyboardInput est interdit en combat.
-- Rend vrai si la touche est prise par le bandeau (elle ne passe pas au jeu).
function ns.surTouche(cadre, touche)
  if enCombat() then return false end
  local e = etat
  local action, n
  if e and bandeau and sur(bandeau.IsShown, bandeau) then
    -- Maj n'est pas compté : sur un clavier AZERTY, les chiffres du haut se tapent avec Maj (vu en
    -- jeu le 12/11 : la touche 2 ne choisissait pas la récompense). Ctrl et Alt restent au jeu.
    local modificateur = (sur(IsControlKeyDown) == true) or (sur(IsAltKeyDown) == true)
    action, n = ns.toucheVers(touche, {
      affiche = true, touches = db.touches, combat = false, modificateur = modificateur, etape = e.etape,
      derniere = e.page >= #e.pages, nbReponses = #e.reponses, nbChoix = e.nbChoix,
      boutonActif = e.action == nil or e.action.actif,
    })
  end
  -- La touche est prise (rien pour le jeu) seulement si elle fait quelque chose pour nous.
  sur(cadre.SetPropagateKeyboardInput, cadre, action == nil)
  if action == "bouton" then
    local ok, err = pcall(actionBouton)
    if not ok then echec(err) end
  elseif action == "ignorer" then
    -- Bouton grisé : Espace ne fait rien, sauf finir d'écrire le texte.
    local ok, err = pcall(terminerEcriture)
    if not ok then echec(err) end
  elseif action == "fermer" then
    fermerEchange()
  elseif action == "reponse" then
    local ok, err = pcall(choisirReponse, e.reponses[n])
    if not ok then echec(err) end
  elseif action == "choix" then
    local ok, err = pcall(choisirRecompense, n)
    if not ok then echec(err) end
  end
  -- Dernier mot : fermer le bandeau (Échap) remet le clavier au jeu, ce qui changerait le
  -- sort de la touche en cours. La touche prise reste prise, celle qui ne nous sert à rien passe.
  if not enCombat() then sur(cadre.SetPropagateKeyboardInput, cadre, action == nil) end
  return action ~= nil
end

-- ------------------------------------------------------------ le bandeau d'essai
local TEST_TEXTE = "Bonjour, voyageur. Je suis un faux PNJ : je n'existe que pour te montrer le bandeau.\n\n"
  .. "Le texte s'affiche par morceaux, une page à la fois. Appuie sur Espace, ou clique sur le bouton en bas à droite, pour passer à la suite. "
  .. "Les chiffres choisissent une réponse ou une récompense, et Échap ferme tout.\n\n"
  .. "Tu peux changer la taille du texte et la largeur du bandeau dans les réglages, sans recharger l'interface."

local function essaiDetail()
  return {
    etape = "detail", test = true, page = 1, pnj = "Garde d'essai", titre = "Une quête pour voir",
    texte = TEST_TEXTE, objectif = "Appuyer sur le bouton Accepter.", recompenses = { choix = {}, fixes = {}, argent = 12500, xp = 340 },
    reponses = {}, reste = 0, nbChoix = 0, conseils = {},
  }
end

local function essaiFin()
  local objets = {
    { genre = "choice", indice = 1, nom = "Épée d'essai", icone = "Interface\\Icons\\INV_Sword_04", nombre = 1 },
    { genre = "choice", indice = 2, nom = "Bouclier d'essai", icone = "Interface\\Icons\\INV_Shield_04", nombre = 1 },
    { genre = "choice", indice = 3, nom = "Bague d'essai", icone = "Interface\\Icons\\INV_Jewelry_Ring_03", nombre = 1 },
  }
  return {
    etape = "complete", test = true, page = 1, pnj = "Garde d'essai", titre = "Une quête pour voir",
    texte = "Bien joué ! Choisis ta récompense : un chiffre au clavier ou un clic, puis Terminer la quête.",
    recompenses = { choix = objets, fixes = {}, argent = 12500, xp = 340 }, reponses = {}, reste = 0, nbChoix = 3, conseils = {},
  }
end

-- Une action dans l'essai : Accepter mène à l'écran de fin, le reste ferme.
lancerTest = function(e, action)
  if action == "accepter" then
    local suivant = essaiFin()
    suivant.pages = ns.pagesDe(suivant.texte, nil, db.morceaux, tailleMax())
    etat = suivant
    tracer()
    return
  end
  fermerBandeauSeulement()
  if action == "terminer" then dire("fin de l'essai : tout marche. Aucune vraie quête n'a bougé.") end
end

local function afficherTest()
  if not db then return end
  pannes = 0
  local ok, err = pcall(function()
    etat = essaiDetail()
    afficherEtat()
  end)
  if not ok then echec(err) end
end

-- ------------------------------------------------------------ les événements du jeu
local ETAPES_PAR_EVENEMENT = {
  GOSSIP_SHOW = "gossip", QUEST_GREETING = "greeting", QUEST_DETAIL = "detail",
  QUEST_PROGRESS = "progress", QUEST_COMPLETE = "complete",
}

-- Le jeu ouvre (ou change) une étape : on masque sa fenêtre tout de suite, puis on affiche le
-- bandeau 0,15 s plus tard, seulement si l'échange est toujours ouvert et à la même étape.
-- (Quêtes auto accepte et rend des quêtes sur ces mêmes événements : sans ce délai, le bandeau
-- clignoterait pour rien.)
local function surOuverture(etape)
  generation = generation + 1
  local g = generation
  courant = etape
  if repli or not prise() then return end
  -- Pendant les 0,15 s, l'ancien bandeau ne doit plus agir : le jeu est déjà passé à l'étape suivante.
  if etat then etat.occupe = true end
  masquerJeu()
  apres(0.15, function()
    if g ~= generation or courant ~= etape or repli or not prise() then return end
    local ok, err = pcall(function()
      etat = lireEtape(etape)
      afficherEtat()
    end)
    if not ok then echec(err) end
  end)
end

-- Fin d'un échange. Un GOSSIP_CLOSED qui arrive APRÈS l'ouverture d'une quête (l'ordre varie)
-- ne doit pas fermer la quête : on ne ferme que l'étape qui correspond. Le bandeau reste 0,15 s,
-- pour ne pas clignoter quand une étape en remplace une autre.
local function surFermeture(evenement)
  local gossip = (courant == "gossip")
  if evenement == "GOSSIP_CLOSED" and not gossip then return end
  if evenement == "QUEST_FINISHED" and gossip then return end
  courant = nil
  generation = generation + 1
  local g = generation
  apres(0.15, function()
    if g ~= generation or courant ~= nil then return end
    repli = false
    etat = nil
    pcall(cacherBandeau)
    pcall(rendreJeu)
  end)
end

local ecouteur = CreateFrame("Frame")
for _, e in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE",
                     "GOSSIP_CLOSED", "QUEST_FINISHED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
                     "PLAYER_ENTERING_WORLD" }) do
  pcall(ecouteur.RegisterEvent, ecouteur, e)
end

ecouteur:SetScript("OnEvent", function(_, evenement)
  if not db then return end
  local ok, err = pcall(function()
    local etape = ETAPES_PAR_EVENEMENT[evenement]
    if etape then
      surOuverture(etape)
    elseif evenement == "GOSSIP_CLOSED" or evenement == "QUEST_FINISHED" then
      surFermeture(evenement)
    elseif evenement == "PLAYER_REGEN_DISABLED" then
      -- Le combat commence : on rend les touches au jeu tant qu'on peut encore le faire.
      clavierCoupe()
    elseif evenement == "PLAYER_REGEN_ENABLED" then
      finirRemiseJeu()
      if bandeau and sur(bandeau.IsShown, bandeau) and etat then clavierActif() end
    elseif evenement == "PLAYER_ENTERING_WORLD" then
      courant, repli, etat = nil, false, nil
      if bandeau then pcall(cacherBandeau) end
      pcall(rendreJeu)
    end
  end)
  if not ok then echec(err) end
end)

-- ---------------------------------------------------------------------------
-- Réglages
-- ---------------------------------------------------------------------------

-- Change le style d'affichage (sans /reload) et le dit dans le chat.
local function choisirStyle(valeur)
  if not db or not ns.reglages then return end
  ns.reglages.changer("style", valeur)
  dire("style « " .. ns.nomStyle(valeur) .. " ». /dial test pour le voir.")
end

-- Un bouton de réglages par style (l'API des réglages n'a pas de liste déroulante).
local function boutonStyle(valeur, aide, texte)
  return { texte = texte or ("Style : " .. ns.nomStyle(valeur)), aide = aide, action = function() choisirStyle(valeur) end }
end

ns.reglages = ns.creerReglages({
  titre = "Dialogues de quête",
  icone = "Interface\\GossipFrame\\GossipGossipIcon",
  nomDB = "DialoguesDB",
  defauts = DEFAUTS,
  options = {
    { titre = "Affichage" },
    { cle = "actif", libelle = "Activer les dialogues de quête",
      aide = "Un cadre en bas de l'écran remplace la fenêtre de dialogue des PNJ. Coupé : la fenêtre du jeu revient tout de suite." },
    { cle = "morceaux", libelle = "Le texte par morceaux",
      aide = "Le texte du PNJ s'affiche une page à la fois (« 2 / 3 »). Décoché : tout le texte d'un coup." },
    { cle = "machine", libelle = "Le texte lettre par lettre",
      aide = "Le texte de la page s'écrit comme à la machine (environ 60 lettres par seconde). Espace affiche d'abord tout le texte, un second appui passe à la suite. Décoché : tout le texte d'un coup." },
    { cle = "touches", libelle = "Les touches du clavier",
      aide = "Espace = le bouton d'action, 1 à 9 = une réponse ou une récompense, Échap = fermer. Les autres touches passent au jeu. En combat, aucune touche n'est prise." },
    { cle = "conseil", libelle = "Récompense conseillée",
      aide = "Sous une récompense, « Mieux pour toi » en vert quand Sacs rangés juge qu'elle améliore ce que tu portes. Sans Sacs rangés, la ligne est absente." },
    { cle = "tailleTexte", type = "nombre", libelle = "Taille du texte", min = 12, max = 22, pas = 1,
      format = function(v) return v .. " px" end,
      aide = "La taille des lettres du texte du PNJ. Le découpage en pages s'adapte." },
    { cle = "largeur", type = "nombre", libelle = "Largeur du cadre", min = 20, max = 90, pas = 5,
      format = function(v) return v .. " %" end,
      aide = "La largeur du cadre (styles compact et bandeau), en pourcentage de la largeur de l'écran. Le style compact ne descend pas sous 360 pixels." },
    { titre = "Jeu" },
    { cle = "fenetreJeu", libelle = "Garder la fenêtre de dialogue du jeu",
      aide = "Coché : le bandeau ne s'affiche pas, la fenêtre du jeu fait tout (comme /dial jeu). Utile pour comparer ou en cas de souci." },
  },
  boutons = {
    { texte = "Tester le dialogue", aide = "Affiche un faux dialogue, sans PNJ, dans le style choisi, pour le voir et essayer les touches.", action = function()
      afficherTest()
    end },
    boutonStyle("compact", "Un seul cadre compact au-dessus des barres d'action : la tête du PNJ en 3D, son nom et son texte ; les réponses en boutons empilés à droite du cadre. Le style par défaut.", "Style : compact (comme Immersion)"),
    boutonStyle("bandeau", "Le bandeau d'origine, en bas de l'écran."),
    boutonStyle("scene", "Un grand modèle 3D du PNJ à gauche, le texte en bas au centre, les réponses en cartes à droite."),
    boutonStyle("face", "Comme la scène, avec ton personnage à droite ; le texte en haut, les réponses en bas."),
    boutonStyle("cinema", "Deux bandes noires, le texte dans celle du bas, le modèle du PNJ au-dessus, les cartes à droite."),
  },
  astuce = "Espace passe à la page suivante puis accepte ; les chiffres choisissent une réponse ou une récompense ; Échap ferme. /dial jeu rend la fenêtre du jeu.",
  auChargement = function(d)
    db = d
    ns.migrerCompact(d) -- une fois : l'ancien style par défaut (scène) passe au style compact
  end,
  surChangement = function()
    if not db then return end
    -- Addon coupé ou fenêtre du jeu demandée : on rend tout au jeu tout de suite.
    if not db.actif or db.fenetreJeu then
      generation = generation + 1
      etat = nil
      pcall(cacherBandeau)
      pcall(rendreJeu)
      return
    end
    if bandeau then
      appliquerStyle()
      if etat and sur(bandeau.IsShown, bandeau) then
        local e = etat
        paginer(e)
        tracer()
      end
      if db.touches then
        if etat and sur(bandeau.IsShown, bandeau) then clavierActif() end
      else
        if not enCombat() then clavierCoupe() end
      end
    end
  end,
})

-- ---------------------------------------------------------------------------
-- Commandes
-- ---------------------------------------------------------------------------

local function commande(texte)
  local c = strtrim(texte or ""):lower()
  if c == "" or c == "options" or c == "reglages" then
    ns.reglages.ouvrir()
  elseif c == "jeu" then
    if not db then return end
    ns.reglages.changer("fenetreJeu", not db.fenetreJeu)
    dire(db.fenetreJeu and "fenêtre du jeu rétablie (le bandeau ne s'affiche plus)." or "le bandeau est de retour.")
  elseif c == "test" then
    afficherTest()
  elseif c == "style" or c:find("^style%s") then
    local demande = strtrim(c:sub(6))
    if demande == "" then
      dire("style actuel : " .. ns.nomStyle(db and db.style) .. ". Pour en changer : /dial style compact, bandeau, scene, face ou cinema.")
    else
      local v = ns.styleDepuisTexte(demande)
      if v then choisirStyle(v) else dire("style inconnu : « " .. demande .. " ». Au choix : compact, bandeau, scene, face, cinema.") end
    end
  elseif c == "on" or c == "off" then
    if db and (c == "on") ~= (db.actif and true or false) then ns.reglages.basculer() end
  elseif c == "aide" or c == "help" or c == "?" then
    dire("/dial : les réglages     /dial test : un faux dialogue pour essayer")
    dire("/dial style compact, bandeau, scene, face ou cinema : l'affichage     /dial style : le style actuel")
    dire("/dial jeu : bascule entre l'affichage et la fenêtre du jeu     /dial on, /dial off : activer ou couper")
  elseif not ns.reglages.basculerOption(c) then
    dire("commande inconnue. /dial aide donne la liste.")
  end
end

SLASH_DIALOGUES1 = "/dial"
SLASH_DIALOGUES2 = "/dialogues"
SlashCmdList.DIALOGUES = commande
