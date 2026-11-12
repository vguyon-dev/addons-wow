-- Simulation hors jeu de Dialogues de quête : le découpage du texte, le bouton d'action, la liste des
-- réponses, les touches, puis un chargement simulé de l'addon avec de faux cadres et un faux jeu
-- (chaque étape d'un dialogue, le combat, une erreur d'affichage, Immersion, des API qui manquent).
-- Lancer depuis la racine du dépôt, sous Windows :
--   wsl lua5.1 tests/Dialogues_simu.lua Dialogues/Dialogues.lua
local ok = true
local nbOK = 0
local function verifie(libelle, attendu, obtenu)
  local bon = attendu == obtenu
  ok = ok and bon
  if bon then nbOK = nbOK + 1 end
  io.write(string.format("%s %-66s attendu %s, obtenu %s\n", bon and "OK " or "KO ", libelle, tostring(attendu), tostring(obtenu)))
end

local fichier = arg[1]
local reglagesLua = fichier:gsub("[^/]+$", "Reglages.lua")

local function lire(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
verifie("Reglages.lua identique dans QuetesAuto", true,
  lire(reglagesLua) == lire((reglagesLua:gsub("Dialogues/Reglages", "QuetesAuto/Reglages"))))
local toc = lire((fichier:gsub("Dialogues%.lua$", "Dialogues.toc")))
verifie("toc : charge Reglages.lua puis Dialogues.lua", true, toc:find("Reglages%.lua%s+Dialogues%.lua") ~= nil)
verifie("toc : sauvegarde déclarée", true, toc:find("## SavedVariables: DialoguesDB", 1, true) ~= nil)
verifie("toc : les deux versions du jeu", true, toc:find("## Interface: 120105, 16001", 1, true) ~= nil)
verifie("toc : fonction du compartiment d'addons", true, toc:find("## AddonCompartmentFunc: Dialogues_OuvrirReglages", 1, true) ~= nil)
verifie("toc : version 0.2.0", true, toc:find("## Version: 0.2.0", 1, true) ~= nil)
verifie("toc : catégorie des addons de Valentin", true, toc:find("## Category: Addons de Valentin", 1, true) ~= nil)
verifie("toc : titre", true, toc:find("## Title: Dialogues de quête", 1, true) ~= nil)
local source = lire(fichier)
verifie("source : aucun tiret cadratin ni demi-cadratin", true, source:find("—", 1, true) == nil and source:find("–", 1, true) == nil)
verifie("source : pas de UIDropDownMenu", true, source:find("UIDropDownMenu", 1, true) == nil)
verifie("source : pas de SetOverrideBinding", true, source:find("SetOverrideBinding", 1, true) == nil)
verifie("source : aucun UnregisterEvent sur les fenêtres du jeu", true, source:find("UnregisterEvent", 1, true) == nil)

-- ============================================================================
-- 1. La logique pure : on charge le fichier sans aucune fonction du jeu.
-- ============================================================================
local ns = {}
assert(loadfile(fichier))("Dialogues", ns)

local function normalise(t) return (t:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")) end
local function rejoint(pages) return table.concat(pages, " ") end
local function pagesTrop(pages, max)
  for _, p in ipairs(pages) do
    if ns.longueur(p) > max and not p:find(" ", 1, true) then -- un mot trop long reste entier
    elseif ns.longueur(p) > max then return true end
  end
  return false
end
local function utf8Net(pages)
  for _, p in ipairs(pages) do if p:find("^[\128-\191]") or p:find("[\194-\244]$") then return false end end
  return true
end

-- ---- ns.decouper
verifie("découper : texte vide", 0, #ns.decouper("", 100))
verifie("découper : nil", 0, #ns.decouper(nil, 100))
verifie("découper : que des espaces", 0, #ns.decouper("  \n \n ", 100))
verifie("découper : un nombre n'est pas un texte", 0, #ns.decouper(42, 100))
verifie("découper : texte court, une page", "Bonjour.", ns.decouper("Bonjour.", 100)[1])
verifie("découper : texte court, une seule page", 1, #ns.decouper("Bonjour.", 100))
verifie("découper : deux paragraphes tiennent ensemble", "Un peu.\nBeaucoup.", ns.decouper("Un peu.\n\nBeaucoup.", 100)[1])
verifie("découper : deux paragraphes, une page chacun", 2, #ns.decouper("Premier paragraphe ici.\n\nSecond paragraphe ici.", 30))
verifie("découper : le paragraphe n'est pas coupé quand il tient", "Premier paragraphe ici.", ns.decouper("Premier paragraphe ici.\n\nSecond paragraphe ici.", 30)[1])
verifie("découper : fins de ligne Windows", 2, #ns.decouper("Premier paragraphe ici.\r\n\r\nSecond paragraphe ici.", 30))
local long = "Il était une fois un garde. Il surveillait la porte. Chaque matin, il comptait les loups. Chaque soir, il les comptait encore ! Que faire ? Rien."
local pl = ns.decouper(long, 45)
verifie("découper : phrases, aucune page trop longue", false, pagesTrop(pl, 45))
verifie("découper : phrases, plusieurs pages", true, #pl > 1)
verifie("découper : phrases, rien de perdu", normalise(long), normalise(rejoint(pl)))
verifie("découper : coupe à une fin de phrase", true, pl[1]:match("[%.%!%?]$") ~= nil)
local sansPonct = "un deux trois quatre cinq six sept huit neuf dix onze douze treize quatorze quinze"
local pm = ns.decouper(sansPonct, 20)
verifie("découper : sans ponctuation, jamais trop long", false, pagesTrop(pm, 20))
verifie("découper : sans ponctuation, mots entiers conservés", normalise(sansPonct), normalise(rejoint(pm)))
verifie("découper : mot plus long que la taille", "extraordinairement", ns.decouper("extraordinairement", 12)[1])
verifie("découper : mot trop long, une page", 1, #ns.decouper("extraordinairement", 12))
verifie("découper : mot trop long entre deux mots", 3, #ns.decouper("un extraordinairement beau", 12))
local acc = "Élève à l'école, où l'été s'achève, il écoute sa mère. Ça va être très très long maintenant ! Ô ciel."
local pa = ns.decouper(acc, 30)
verifie("découper : accents, jamais trop long (en caractères)", false, pagesTrop(pa, 30))
verifie("découper : accents, rien de perdu", normalise(acc), normalise(rejoint(pa)))
verifie("découper : accents, octets entiers", true, utf8Net(pa))
verifie("longueur : é compte un", 2, ns.longueur("éé"))
verifie("longueur : œ et …", 3, ns.longueur("œ…a"))
local pe = ns.decouper("Il hésite… Puis il part. Fin.", 15)
verifie("découper : points de suspension, octets entiers", true, utf8Net(pe))
verifie("découper : points de suspension, rien de perdu", "Il hésite… Puis il part. Fin.", normalise(rejoint(pe)))
verifie("découper : coupe après « … »", "Il hésite…", pe[1])
local pg = ns.decouper("« Bonjour ! » dit-il. Ensuite il part.", 14)
verifie("découper : guillemet fermant avec la phrase", "« Bonjour ! »", pg[1])
verifie("découper : guillemets, rien de perdu", "« Bonjour ! » dit-il. Ensuite il part.", normalise(rejoint(pg)))
verifie("découper : « M. Dupont » reste ensemble", "M. Dupont arrive.", ns.decouper("M. Dupont arrive. Il parle.", 18)[1])
verifie("découper : un nombre décimal ne coupe pas", "Il vaut 3.5 pièces.", ns.decouper("Il vaut 3.5 pièces.", 100)[1])
verifie("découper : taille absente = 300 par défaut", 1, #ns.decouper(string.rep("mot ", 70), nil))
verifie("découper : taille minuscule relevée à 10", false, pagesTrop(ns.decouper("abc def ghi jkl mno pqr", 2), 10))
verifie("découper : taille texte", 1, #ns.decouper("Bonjour.", "abc"))

-- ---- tailleMorceau, compteur, argent, couleur
verifie("tailleMorceau : 1000 px à 15", 460, ns.tailleMorceau(1000, 15))
verifie("tailleMorceau : étroit, plancher à 120", 120, ns.tailleMorceau(100, 15))
verifie("tailleMorceau : très large, plafond à 700", 700, ns.tailleMorceau(5000, 10))
verifie("tailleMorceau : plus grand texte, moins de caractères", true, ns.tailleMorceau(1000, 22) < ns.tailleMorceau(1000, 12))
verifie("tailleMorceau : valeurs absentes", true, type(ns.tailleMorceau(nil, nil)) == "number")
verifie("compteur : 2 / 3", "2 / 3", ns.compteur(2, 3))
verifie("compteur : une seule page", "", ns.compteur(1, 1))
verifie("compteur : aucune page", "", ns.compteur(1, 0))
verifie("compteur : page absente", "1 / 3", ns.compteur(nil, 3))
verifie("argent : zéro", "0 pc", ns.texteArgent(0))
verifie("argent : 5 pc", "5 pc", ns.texteArgent(5))
verifie("argent : 1 po 20 pa 5 pc", "1 po 20 pa 5 pc", ns.texteArgent(12005))
verifie("argent : 1 po", "1 po", ns.texteArgent(10000))
verifie("argent : 1 pa 50 pc", "1 pa 50 pc", ns.texteArgent(150))
verifie("argent : négatif", "0 pc", ns.texteArgent(-3))
verifie("argent : absent", "0 pc", ns.texteArgent(nil))
verifie("couleur d'un lien", "ffa335ee", ns.couleurDeLien("|cffa335ee|Hitem:1|h[X]|h|r"))
verifie("couleur : pas de lien", "ffffffff", ns.couleurDeLien(nil))
verifie("couleur : texte sans code", "ffffffff", ns.couleurDeLien("juste un nom"))
verifie("nom d'objet : couleur et nombre", "|cffa335eeÉpée|r x3", ns.nomObjet({ nom = "Épée", lien = "|cffa335ee|Hitem:1|h[X]|h|r", nombre = 3 }))
verifie("nom d'objet : sans nom", "|cffffffffObjet|r", ns.nomObjet({}))
verifie("nom d'objet : nil", "|cffffffffObjet|r", ns.nomObjet(nil))

-- ---- pagesDe
verifie("pagesDe : texte et objectif en dernière page", "|cffffd200Objectif :|r Tuer 4 loups.", ns.pagesDe("Salut.", "Tuer 4 loups.", true, 100)[2])
verifie("pagesDe : deux pages", 2, #ns.pagesDe("Salut.", "Tuer 4 loups.", true, 100))
verifie("pagesDe : sans objectif", 1, #ns.pagesDe("Salut.", "", true, 100))
verifie("pagesDe : objectif seul", 1, #ns.pagesDe("", "Tuer 4 loups.", true, 100))
verifie("pagesDe : rien du tout", 0, #ns.pagesDe("", "", true, 100))
verifie("pagesDe : sans morceaux, une page", 1, #ns.pagesDe(string.rep("Une phrase assez longue. ", 40), "Faire ça.", false, 50))
verifie("pagesDe : sans morceaux, l'objectif est dans la page", true,
  ns.pagesDe("Salut.", "Faire ça.", false, 50)[1]:find("Faire ça.", 1, true) ~= nil)
verifie("pagesDe : textes absents", 0, #ns.pagesDe(nil, nil, true, 100))

-- ---- boutonAction
local function ba(...) local b = ns.boutonAction(...) return b.libelle .. "|" .. b.action .. "|" .. tostring(b.actif) end
verifie("bouton : il reste des pages", "Suivant|suivant|true", ba("detail", 1, 3))
verifie("bouton : pages restantes, étape fin", "Suivant|suivant|true", ba("complete", 2, 3, false, 3, nil))
verifie("bouton : gossip, dernière page", "Au revoir|fermer|true", ba("gossip", 1, 1))
verifie("bouton : greeting, dernière page", "Au revoir|fermer|true", ba("greeting", 2, 2))
verifie("bouton : détail, dernière page", "Accepter|accepter|true", ba("detail", 3, 3))
verifie("bouton : progression finie", "Continuer|continuer|true", ba("progress", 1, 1, true))
verifie("bouton : progression pas finie", "Au revoir|fermer|true", ba("progress", 1, 1, false))
verifie("bouton : fin sans choix", "Terminer la quête|terminer|true", ba("complete", 1, 1, false, 0, nil))
verifie("bouton : fin, un seul choix", "Terminer la quête|terminer|true", ba("complete", 1, 1, false, 1, nil))
verifie("bouton : fin, trois choix, aucun choisi", "Choisis une récompense|terminer|false", ba("complete", 1, 1, false, 3, nil))
verifie("bouton : fin, trois choix, un choisi", "Terminer la quête|terminer|true", ba("complete", 1, 1, false, 3, 2))
verifie("bouton : aucune page = dernière page", "Accepter|accepter|true", ba("detail", 1, 0))
verifie("bouton : étape inconnue", "Au revoir|fermer|true", ba("bidule", 1, 1))
verifie("bouton : ns.etape est le même", true, ns.etape == ns.boutonAction)
local function bs(...) local b = ns.boutonSecondaire(...) return b and (b.libelle .. "|" .. b.action) or "rien" end
verifie("second bouton : refuser", "Refuser|refuser", bs("detail", 2, 2))
verifie("second bouton : pas avant la dernière page", "rien", bs("detail", 1, 2))
verifie("second bouton : progression finie", "Au revoir|fermer", bs("progress", 1, 1, true))
verifie("second bouton : progression pas finie", "rien", bs("progress", 1, 1, false))
verifie("second bouton : gossip", "rien", bs("gossip", 1, 1))
verifie("second bouton : fin", "rien", bs("complete", 1, 1))

-- ---- reponses
local rep, reste = ns.reponses(
  { { title = "Fini A", questID = 1, isComplete = true, source = "gossip" }, { title = "Pas fini", questID = 2, isComplete = false },
    { title = "Fini B", questID = 3, isComplete = true } },
  { { title = "Nouvelle", questID = 4 } },
  { { name = "Acheter", gossipOptionID = 77 } })
local function titresRep(r) local t = {} for _, e in ipairs(r) do t[#t + 1] = e.numero .. e.marque .. e.texte end return table.concat(t, ",") end
verifie("réponses : ordre, marques et numéros", "1?Fini A,2?Fini B,3?Pas fini,4!Nouvelle,5Acheter", titresRep(rep))
verifie("réponses : rien d'écarté", 0, reste)
verifie("réponses : valeur d'une quête", 1, rep[1].valeur)
verifie("réponses : valeur d'une phrase", 77, rep[5].valeur)
verifie("réponses : genre rendre", "rendre", rep[1].genre)
verifie("réponses : genre prendre", "prendre", rep[4].genre)
verifie("réponses : genre phrase", "phrase", rep[5].genre)
verifie("réponses : fini ou pas", true, rep[1].fini and not rep[3].fini)
verifie("réponses : source gardée", "gossip", rep[1].source)
local grosse = {}
for i = 1, 8 do grosse[i] = { title = "Q" .. i, questID = i } end
local r2, reste2 = ns.reponses({}, grosse, { { name = "Phrase 1", gossipOptionID = 1 }, { name = "Phrase 2", gossipOptionID = 2 } })
verifie("réponses : neuf au plus", 9, #r2)
verifie("réponses : le reste est compté", 1, reste2)
verifie("réponses : la dernière retenue", "9Phrase 1", r2[9].numero .. r2[9].texte)
local r3 = ns.reponses({ { title = "", questID = 1 }, { questID = 2 }, "n'importe quoi" }, nil, { { name = "", gossipOptionID = 3 } })
verifie("réponses : titres vides ou éléments bizarres ignorés", 0, #r3)
verifie("réponses : tout nil", 0, #ns.reponses(nil, nil, nil))
local r4 = ns.reponses({ { title = "Ancien", indice = 2, isComplete = true, source = "greeting" } })
verifie("réponses : indice d'un ancien PNJ", 2, r4[1].valeur)

-- ---- toucheVers
local function tv(touche, etat) local a, n = ns.toucheVers(touche, etat) return tostring(a) .. (n and (":" .. n) or "") end
local base = { affiche = true, touches = true, combat = false, modificateur = false, etape = "gossip", derniere = true, nbReponses = 4, nbChoix = 0, boutonActif = true }
local function avec(champ, valeur) local t = {} for k, v in pairs(base) do t[k] = v end t[champ] = valeur return t end
verifie("touche : Espace", "bouton", tv("SPACE", base))
verifie("touche : Espace, bouton grisé", "ignorer", tv("SPACE", avec("boutonActif", false)))
verifie("touche : Échap", "fermer", tv("ESCAPE", base))
verifie("touche : 1", "reponse:1", tv("1", base))
verifie("touche : 4", "reponse:4", tv("4", base))
verifie("touche : 5 (pas de 5e réponse)", "nil", tv("5", base))
verifie("touche : 9", "nil", tv("9", base))
verifie("touche : pavé numérique", "reponse:2", tv("NUMPAD2", base))
verifie("touche : 0", "nil", tv("0", base))
verifie("touche : lettre (se déplacer)", "nil", tv("W", base))
verifie("touche : maj gauche", "nil", tv("LSHIFT", base))
verifie("touche : option coupée", "nil", tv("SPACE", avec("touches", false)))
verifie("touche : en combat, Espace", "nil", tv("SPACE", avec("combat", true)))
verifie("touche : en combat, Échap", "nil", tv("ESCAPE", avec("combat", true)))
verifie("touche : en combat, un chiffre", "nil", tv("1", avec("combat", true)))
verifie("touche : bandeau pas affiché", "nil", tv("SPACE", avec("affiche", false)))
verifie("touche : avec une touche de modification", "nil", tv("1", avec("modificateur", true)))
verifie("touche : chiffre avant la dernière page", "nil", tv("1", avec("derniere", false)))
verifie("touche : Espace avant la dernière page", "bouton", tv("SPACE", avec("derniere", false)))
verifie("touche : récompense 2 sur 3", "choix:2", tv("2", { affiche = true, touches = true, etape = "complete", derniere = true, nbChoix = 3 }))
verifie("touche : récompense 4 sur 3", "nil", tv("4", { affiche = true, touches = true, etape = "complete", derniere = true, nbChoix = 3 }))
verifie("touche : chiffre en étape détail", "nil", tv("1", avec("etape", "detail")))
verifie("touche : état absent", "nil", tv("SPACE", nil))
verifie("touche : touche absente", "nil", tv(nil, base))

-- ---- avis de Sacs rangés
verifie("avis : ligne verte de Sacs rangés", "Mieux pour toi : +5 % (Pawn)",
  ns.avisDepuisLignes({ "Épée", "|cff1eff00Mieux pour Vindicte : +5 % (Pawn)|r", "Remplace : Vieille épée" }))
verifie("avis : sans raison", "Mieux pour toi", ns.avisDepuisLignes({ "Mieux pour Vindicte" }))
verifie("avis : aucune ligne", nil, ns.avisDepuisLignes({ "Épée", "Niveau 20" }))
verifie("avis : liste absente", nil, ns.avisDepuisLignes(nil))
verifie("avis : éléments bizarres", nil, ns.avisDepuisLignes({ 42, {} }))

-- ---- lignesListe
local function resume(l) local t = {} for _, x in ipairs(l) do t[#t + 1] = x.type .. ":" .. (x.numero and (x.numero .. ":") or "") .. (x.texte:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end return table.concat(t, " | ") end
local objA = { nom = "Épée", indice = 1, icone = "i", genre = "choice" }
local objB = { nom = "Bague", indice = 2 }
verifie("liste : pas avant la dernière page", 0, #ns.lignesListe({ etape = "complete", page = 1, pages = { "a", "b" }, recompenses = { choix = { objA, objB } } }))
verifie("liste : gossip", "reponse:1:Fini A | reponse:2:Acheter", resume(ns.lignesListe({ etape = "gossip", page = 1, pages = { "a" },
  reponses = { { numero = 1, marque = "?", texte = "Fini A", genre = "rendre" }, { numero = 2, marque = "", texte = "Acheter", genre = "phrase" } } })))
verifie("liste : gossip, réponses de côté", "texte:+ 3 autres : clique sur « Fenêtre du jeu ».",
  resume(ns.lignesListe({ etape = "gossip", page = 1, pages = {}, reponses = {}, reste = 3 })))
verifie("liste : détail, au choix et fixes", "titre:Au choix : | objet:Épée | titre:Tu recevras : | objet:Bague | texte:Or : 1 pa 50 pc | texte:Expérience : 300",
  resume(ns.lignesListe({ etape = "detail", page = 2, pages = { "a", "b" }, recompenses = { choix = { objA }, fixes = { objB }, argent = 150, xp = 300 } })))
verifie("liste : progression", "titre:Objets demandés : | objet:Épée | texte:Or demandé : 5 pc",
  resume(ns.lignesListe({ etape = "progress", page = 1, pages = { "a" }, requis = { objA }, argentRequis = 5 })))
verifie("liste : progression sans rien", 0, #ns.lignesListe({ etape = "progress", page = 1, pages = { "a" }, requis = {}, argentRequis = 0 }))
local lc = ns.lignesListe({ etape = "complete", page = 1, pages = { "a" }, choix = 2, recompenses = { choix = { objA, objB }, fixes = { { nom = "Pain", indice = 1 } } },
  conseils = { choice1 = "Mieux pour toi : +5 %" } })
verifie("liste : fin, choix numérotés", "titre:Choisis ta récompense : | choix:1:Épée | choix:2:Bague | titre:Tu recevras aussi : | objet:Pain", resume(lc))
verifie("liste : fin, le choix est marqué", true, lc[3].choisi == true and lc[2].choisi == nil)
verifie("liste : fin, le conseil suit l'objet", "Mieux pour toi : +5 %", lc[2].conseil)
verifie("liste : fin, un seul choix", "titre:Récompense :", resume(ns.lignesListe({ etape = "complete", page = 1, pages = { "a" }, recompenses = { choix = { objA } } })):match("^titre:Récompense :"))
verifie("liste : état absent", 0, #ns.lignesListe(nil))

-- ---- morceauTexte, longueurVisible, styles
local outils = {}
function outils.utf8Valide(t)
  local i = 1
  while i <= #t do
    local c = t:byte(i)
    local n = (c >= 240 and 4) or (c >= 224 and 3) or (c >= 192 and 2) or 1
    if c >= 128 and c < 192 then return false end
    for k = 1, n - 1 do
      local d = t:byte(i + k)
      if not d or d < 128 or d > 191 then return false end
    end
    i = i + n
  end
  return true
end
function outils.nbCodes(t, motif) local _, k = t:gsub(motif, "") return k end
verifie("morceauTexte : texte simple", "Bon", ns.morceauTexte("Bonjour", 3))
verifie("morceauTexte : n = 0", "", ns.morceauTexte("Bonjour", 0))
verifie("morceauTexte : n négatif", "", ns.morceauTexte("Bonjour", -4))
verifie("morceauTexte : n absent", "", ns.morceauTexte("Bonjour", nil))
verifie("morceauTexte : n plus grand que le texte", "Bonjour", ns.morceauTexte("Bonjour", 99))
verifie("morceauTexte : n égal à la longueur", "Bonjour", ns.morceauTexte("Bonjour", 7))
verifie("morceauTexte : texte absent", "", ns.morceauTexte(nil, 3))
verifie("morceauTexte : texte vide", "", ns.morceauTexte("", 3))
verifie("morceauTexte : É entier (2 octets)", "É", ns.morceauTexte("Élève", 1))
verifie("morceauTexte : Él", "Él", ns.morceauTexte("Élève", 2))
verifie("morceauTexte : œ compte pour un", "œuf", ns.morceauTexte("œuf…", 3))
verifie("morceauTexte : … (3 octets) entier", "œuf…", ns.morceauTexte("œuf…", 4))
verifie("morceauTexte : couleur ouverte, refermée", "|cffffd200Obje|r", ns.morceauTexte("|cffffd200Objectif :|r Tuer", 4))
verifie("morceauTexte : fin de la couleur, refermée", "|cffffd200Objectif :|r", ns.morceauTexte("|cffffd200Objectif :|r Tuer", 10))
verifie("morceauTexte : après la couleur", "|cffffd200Objectif :|r T", ns.morceauTexte("|cffffd200Objectif :|r Tuer", 12))
verifie("morceauTexte : tout est visible, codes de fin compris", "|cff112233ab|r", ns.morceauTexte("|cff112233ab|r", 2))
verifie("morceauTexte : une barre doublée compte pour un", "a||", ns.morceauTexte("a||b", 2))
do
  local texteMelange = "|cffffd200Objectif :|r Élève à l'œuf… |cff00ff00ok|r fin"
  local total = ns.longueurVisible(texteMelange)
  local propre = true
  for k = 0, total + 3 do
    local r = ns.morceauTexte(texteMelange, k)
    if not outils.utf8Valide(r) or r:find("|c%x?%x?%x?%x?%x?%x?%x?$") or r:find("|$") then propre = false end
    if ns.longueurVisible(r) ~= math.min(k, total) then propre = false end
    if outils.nbCodes(r, "|c%x%x%x%x%x%x%x%x") ~= outils.nbCodes(r, "|r") then propre = false end
  end
  verifie("morceauTexte : pour tout n, jamais coupé (UTF-8, codes) et couleurs équilibrées", true, propre)
end
verifie("longueurVisible : sans les codes couleur", 15, ns.longueurVisible("|cffffd200Objectif :|r Tuer"))
verifie("longueurVisible : accents", 2, ns.longueurVisible("éé"))
verifie("longueurVisible : absent", 0, ns.longueurVisible(nil))
verifie("styles : quatre", 4, #ns.STYLES)
verifie("styleValide : face", "face", ns.styleValide("face"))
verifie("styleValide : inconnu = scène", "scene", ns.styleValide("zorglub"))
verifie("styleValide : absent = scène", "scene", ns.styleValide(nil))
verifie("styleValide : vide = scène", "scene", ns.styleValide(""))
verifie("nomStyle : scène", "scène", ns.nomStyle("scene"))
verifie("nomStyle : face à face", "face à face", ns.nomStyle("face"))
verifie("styleDepuisTexte : scène avec accent", "scene", ns.styleDepuisTexte("scène"))
verifie("styleDepuisTexte : majuscule", "scene", ns.styleDepuisTexte("Scene"))
verifie("styleDepuisTexte : face à face", "face", ns.styleDepuisTexte("face à face"))
verifie("styleDepuisTexte : cinéma", "cinema", ns.styleDepuisTexte("cinéma"))
verifie("styleDepuisTexte : bandeau", "bandeau", ns.styleDepuisTexte(" bandeau "))
verifie("styleDepuisTexte : inconnu", nil, ns.styleDepuisTexte("zorglub"))
verifie("styleDepuisTexte : absent", nil, ns.styleDepuisTexte(nil))

-- ============================================================================
-- 2. Chargement simulé avec de faux cadres et un faux jeu.
-- ============================================================================
local imprime = {}
local function lireImprime() return table.concat(imprime, "\n") end
local function compte(motif) local n = 0 for _, l in ipairs(imprime) do if l:find(motif, 1, true) then n = n + 1 end end return n end
local printOrigine = print
print = function(...)
  local t = {}
  for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
  imprime[#imprime + 1] = table.concat(t, " ")
end

local toutes, enCombat, file, JEU, declencher
local modelePanne = false -- vrai : SetUnit des modèles 3D lève une erreur
local M = {}
local metaF = {}
function metaF.__index(t, k)
  if type(k) ~= "string" or not k:match("^%u") then return nil end
  if (k == "SetBackdrop" or k == "SetBackdropColor" or k == "SetBackdropBorderColor") and not rawget(t, "_fond") then return nil end
  return M[k] or function() end
end

local function nouveau(genre, nom, parent, modele)
  local f = setmetatable({ _type = genre, _nom = nom, _parent = parent, _shown = true, _events = {}, _scripts = {},
    _w = 100, _h = 20, _scale = 1, _text = "", _attr = {}, _niveau = 1 }, metaF)
  toutes[#toutes + 1] = f
  if nom then _G[nom] = f end
  if modele and tostring(modele):find("Backdrop") then f._fond = true end
  return f
end

function M.SetSize(s, w, h) s._w, s._h = w, h end
function M.SetWidth(s, w) s._w = w end
function M.SetHeight(s, h) s._h = h end
function M.GetWidth(s) return s._w end
function M.GetHeight(s) return s._h end
function M.GetStringWidth(s) return #s._text * 6 end
function M.GetStringHeight(s)
  local _, n = s._text:gsub("\n", "")
  return 12 * (n + 1)
end
function M.SetText(s, t)
  t = tostring(t == nil and "" or t)
  if t:find("BOOM", 1, true) then error("erreur d'affichage simulée") end
  s._text = t
end
function M.GetText(s) return s._text end
function M.SetTextColor(s, r, g, b) s._couleur = { r, g, b } end
function M.SetPoint(s, point, rel, relPoint, x, y)
  if type(rel) == "number" then x, y, rel, relPoint = rel, relPoint, nil, nil end
  s._pt = { point, rel, relPoint or point, x or 0, y or 0 }
end
function M.ClearAllPoints(s) s._pt = nil end
function M.GetPoint(s) local p = s._pt or { "CENTER", UIParent, "CENTER", 0, 0 } return p[1], p[2], p[3], p[4], p[5] end
function M.GetLeft(s) return 100 end
function M.GetRight(s) return 400 end
function M.GetTop(s) return 800 end
function M.GetBottom(s) return 300 end
function M.GetCenter() return 500, 400 end
function M.GetEffectiveScale(s) return s._scale end
function M.SetScale(s, v) s._scale = v end
function M.SetAlpha(s, v) s._alpha = v end
function M.GetAlpha(s) return s._alpha or 1 end
function M.GetScale(s) return s._scale end
function M.Show(s) s._shown = true end
function M.Hide(s) s._shown = false end
function M.SetShown(s, v) s._shown = v and true or false end
function M.IsShown(s) return s._shown end
function M.IsVisible(s) return s._shown end
function M.RegisterEvent(s, e) s._events[e] = true end
M.RegisterUnitEvent = M.RegisterEvent
function M.UnregisterEvent(s, e) s._events[e] = nil end
function M.SetScript(s, nom, fn) s._scripts[nom] = fn end
function M.GetScript(s, nom) return s._scripts[nom] end
function M.CreateFontString(s) return nouveau("FontString", nil, s) end
function M.CreateTexture(s) return nouveau("Texture", nil, s) end
function M.CreateMaskTexture(s) return nouveau("MaskTexture", nil, s) end
function M.SetAttribute(s, k, v) s._attr[k] = v end
function M.GetAttribute(s, k) return s._attr[k] end
function M.GetParent(s) return s._parent end
function M.GetName(s) return s._nom end
function M.SetFrameLevel(s, n) s._niveau = n end
function M.GetFrameLevel(s) return s._niveau end
function M.GetVerticalScroll(s) return 0 end
function M.GetVerticalScrollRange() return 0 end
function M.IsObjectType() return false end
function M.SetTexture(s, t) s._texture = t end
function M.SetBackdropBorderColor(s, r, g, b, a) s._bordure = { r, g, b, a } end
function M.SetBackdropColor(s, r, g, b, a) s._fondCouleur = { r, g, b, a } end
function M.Enable(s) s._actif = true end
function M.Disable(s) s._actif = false end
function M.IsEnabled(s) return s._actif ~= false end
-- La souris : un cadre du jeu marqué _interditCombat refuse en combat (un cadre sécurisé).
function M.EnableMouse(s, v)
  if enCombat and rawget(s, "_interditCombat") then error("ADDON_ACTION_BLOCKED EnableMouse sur " .. tostring(s._nom)) end
  s._souris = v
end
function M.IsMouseEnabled(s) return s._souris end
function M.EnableKeyboard(s, v) s._clavier = v end
-- Les modèles 3D (CreateFrame("PlayerModel")) et la strate des cadres.
function M.SetUnit(s, u)
  if modelePanne then error("SetUnit impossible (panne simulée)") end
  s._unite = u
end
function M.ClearModel(s) s._unite = nil end
function M.SetFacing(s, a) s._angle = a end
function M.SetCamDistanceScale(s, v) s._camera = v end
function M.SetPortraitZoom(s, v) s._zoom = v end
function M.SetFrameStrata(s, v) s._strate = v end
function M.SetFont(s, f, t) s._police = f s._taillePolice = t return true end
function M.SetPropagateKeyboardInput(s, v)
  if enCombat then error("ADDON_ACTION_BLOCKED SetPropagateKeyboardInput") end
  s._propage = v
end

local function installer()
  toutes, enCombat, file = {}, false, {}
  imprime = {}
  _G.ValentinAddons, _G.ValentinAddonsReglages, _G.ValentinAddonsMinimap = nil, nil, nil
  _G.DialoguesDB, _G.DialoguesBandeau, _G.DialoguesListe = nil, nil, nil
  _G.DialoguesBandeHaut, _G.DialoguesModelePNJ, _G.DialoguesModeleJoueur, _G.DialoguesEcrivain = nil, nil, nil, nil
  modelePanne = false
  _G.UIParent = nouveau("Frame", "UIParent")
  UIParent._h, UIParent._w = 1080, 1920
  _G.GossipFrame = nouveau("Frame", "GossipFrame", UIParent)
  _G.QuestFrame = nouveau("Frame", "QuestFrame", UIParent)
  for _, f in ipairs({ GossipFrame, QuestFrame }) do f._souris = true; f._interditCombat = true end
  -- La bulle du jeu : vide, cachée, et qui remplit ses lignes depuis JEU.bulles.
  local tip = nouveau("GameTooltip", "GameTooltip")
  tip._shown = false
  tip._lignes = {}
  function tip.SetOwner(s) s._lignes = {} end
  function tip.AddLine(s, t) s._lignes[#s._lignes + 1] = t end
  function tip.NumLines(s) return #s._lignes end
  function tip.IsShown(s) return s._shown end
  function tip.Show(s) s._shown = true end
  function tip.Hide(s) s._shown = false end
  function tip.SetQuestItem(s, genre, i)
    s._lignes = {}
    for _, l in ipairs((JEU.bulles or {})[genre .. i] or {}) do s._lignes[#s._lignes + 1] = l end
    for k = 1, 10 do _G["GameTooltipTextLeft" .. k] = { GetText = function() return s._lignes[k] end } end
  end
  _G.Minimap = nouveau("Frame", "Minimap")
  _G.CreateFrame = function(genre, nom, parent, modele) return nouveau(genre, nom, parent or UIParent, modele) end
  _G.UISpecialFrames, _G.SlashCmdList = {}, {}
  _G.tinsert = table.insert
  _G.strtrim = function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
  _G.hooksecurefunc = function(t, nom, fn) end
  _G.C_Timer = {
    After = function(_, fn)
      if type(fn) ~= "function" then error("C_Timer.After exige une fonction Lua") end
      file[#file + 1] = fn
    end,
    NewTicker = function() return {} end,
  }
  _G.C_AddOns = { IsAddOnLoaded = function() return false end }
  _G.InCombatLockdown = function() return enCombat end
  _G.IsShiftKeyDown, _G.IsControlKeyDown, _G.IsAltKeyDown = function() return false end, function() return false end, function() return false end
  _G.GetCursorPosition = function() return 600, 500 end
  _G.UnitName = function(u) if u == "player" then return "Testeur" end return "Garde Mortemine" end
  _G.UnitExists = function(u) return u == "npc" end
  _G.GetRealmName = function() return "Royaume" end
  _G.UNKNOWNOBJECT = "Inconnu"
  _G.BackdropTemplateMixin = {}
  _G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
  _G.PlaySound = function() end
  _G.issecretvalue = nil
  _G.SetPortraitTexture = function(tex, unite) JEU.portraits[#JEU.portraits + 1] = tostring(unite) end

  -- Le faux jeu : ce que le PNJ dit et fait, et le journal de ce que l'addon a demandé.
  JEU = {
    appels = {}, portraits = {}, bulles = {},
    gossip = { texte = "Bienvenue, voyageur.\n\nQue puis-je faire pour toi ?",
      actives = { { questID = 11, title = "Retour au village", isComplete = false }, { questID = 10, title = "Livraison urgente", isComplete = true } },
      dispos = { { questID = 20, title = "Les loups" } }, options = { { gossipOptionID = 5, name = "Je voudrais voir vos marchandises." } } },
    greeting = { texte = "Salutations.", actives = { { "Rapport au capitaine", true } }, dispos = { { "Une affaire de rats" } } },
    detail = { titre = "Les loups", texte = string.rep("Les loups rôdent près de la ferme et dévorent le bétail. ", 8) .. "\n\n" .. string.rep("Personne n'ose plus sortir la nuit. ", 10),
      objectif = "Tuez 4 loups.", choix = {}, fixes = { { "Pain de voyage", "Interface\\Icons\\INV_Misc_Food_01", 2, 1, "|cff1eff00|Hitem:1|h[Pain de voyage]|h|r" } }, argent = 150, xp = 200 },
    progress = { titre = "Livraison urgente", texte = "As-tu mon colis ?", completable = false,
      requis = { { "Colis scellé", "Interface\\Icons\\INV_Box_01", 1, 1, "|cffffffff|Hitem:2|h[Colis scellé]|h|r" } }, argent = 0 },
    complete = { titre = "Livraison urgente", texte = "Merci, voyageur. Voici ta récompense.",
      choix = {
        { "Épée de garde", "Interface\\Icons\\INV_Sword_01", 1, 3, "|cff0070dd|Hitem:3|h[Épée de garde]|h|r" },
        { "Bouclier de garde", "Interface\\Icons\\INV_Shield_01", 1, 3, "|cff0070dd|Hitem:4|h[Bouclier de garde]|h|r" },
        { "Bague simple", "Interface\\Icons\\INV_Jewelry_Ring_01", 1, 2, "|cff1eff00|Hitem:5|h[Bague simple]|h|r" },
      }, fixes = {}, argent = 12500, xp = 340 },
  }
  local function log(t) JEU.appels[#JEU.appels + 1] = t end
  _G.C_GossipInfo = {
    GetText = function() return JEU.gossip.texte end,
    GetActiveQuests = function() return JEU.gossip.actives end,
    GetAvailableQuests = function() return JEU.gossip.dispos end,
    GetOptions = function() return JEU.gossip.options end,
    SelectActiveQuest = function(id) log("gossip.active:" .. id) end,
    SelectAvailableQuest = function(id) log("gossip.dispo:" .. id) end,
    SelectOption = function(id) log("gossip.option:" .. id) end,
    CloseGossip = function() log("gossip.close") end,
  }
  _G.GetGreetingText = function() return JEU.greeting.texte end
  _G.GetNumActiveQuests = function() return #JEU.greeting.actives end
  _G.GetActiveTitle = function(i) return JEU.greeting.actives[i][1], JEU.greeting.actives[i][2] end
  _G.GetNumAvailableQuests = function() return #JEU.greeting.dispos end
  _G.GetAvailableTitle = function(i) return JEU.greeting.dispos[i][1] end
  _G.SelectActiveQuest = function(i) log("greeting.active:" .. i) end
  _G.SelectAvailableQuest = function(i) log("greeting.dispo:" .. i) end
  _G.GetTitleText = function() return JEU.etape and JEU[JEU.etape].titre or "" end
  _G.GetQuestText = function() return JEU.detail.texte end
  _G.GetObjectiveText = function() return JEU.detail.objectif end
  _G.GetProgressText = function() return JEU.progress.texte end
  _G.GetRewardText = function() return JEU.complete.texte end
  _G.IsQuestCompletable = function() return JEU.progress.completable end
  _G.GetQuestMoneyToGet = function() return JEU.progress.argent end
  _G.GetNumQuestItems = function() return #JEU.progress.requis end
  _G.GetNumQuestChoices = function() return #JEU[JEU.etape or "complete"].choix end
  _G.GetNumQuestRewards = function() return #JEU[JEU.etape or "complete"].fixes end
  local function objets(genre)
    local e = JEU[JEU.etape or "complete"]
    return genre == "choice" and e.choix or genre == "reward" and e.fixes or JEU.progress.requis
  end
  _G.GetQuestItemInfo = function(genre, i) local o = objets(genre)[i] return o[1], o[2], o[3], o[4] end
  _G.GetQuestItemLink = function(genre, i) return objets(genre)[i][5] end
  _G.GetRewardMoney = function() return JEU[JEU.etape or "complete"].argent end
  _G.GetRewardXP = function() return JEU[JEU.etape or "complete"].xp end
  _G.AcceptQuest = function() log("accept") end
  _G.DeclineQuest = function() log("decline") end
  _G.CompleteQuest = function() log("complete") end
  _G.GetQuestReward = function(n) log("reward:" .. tostring(n)) end
  _G.CloseQuest = function() log("close") end
  for k = 1, 10 do _G["GameTooltipTextLeft" .. k] = nil end
end

declencher = function(evenement, ...)
  for _, f in ipairs(toutes) do
    if f._events[evenement] and f._scripts.OnEvent then f._scripts.OnEvent(f, evenement, ...) end
  end
end
local function avancer()
  local garde = 0
  while #file > 0 and garde < 1000 do garde = garde + 1; table.remove(file, 1)() end
end
-- Charge l'addon. Par défaut, le style « bandeau » et l'écriture d'un bloc (les vérifications d'origine
-- lisent le texte tout de suite) ; demarrer("scene", true) choisit le style et l'écriture lettre par lettre ;
-- demarrer("defaut") garde les valeurs de départ de l'addon.
local function demarrer(style, machine)
  local n = {}
  assert(loadfile(reglagesLua))("Dialogues", n)
  assert(loadfile(fichier))("Dialogues", n)
  declencher("ADDON_LOADED", "Dialogues")
  declencher("PLAYER_ENTERING_WORLD")
  avancer()
  if style ~= "defaut" then
    DialoguesDB.style = style or "bandeau"
    DialoguesDB.machine = machine == true
  end
  return n
end

-- Ouvre une étape comme le ferait le jeu : événement, puis le délai de 0,15 s.
local function ouvrir(etape, evenement)
  JEU.etape = etape == "gossip" and "gossip" or etape == "greeting" and "greeting" or etape
  declencher(evenement)
  avancer()
end
local function entrerCombat() declencher("PLAYER_REGEN_DISABLED") enCombat = true end
local function appels() return table.concat(JEU.appels, ",") end
-- Un appui complet : la touche enfoncée puis relâchée (le relâchement ne change pas l'état de
-- propagation que les vérifications lisent juste après).
local function toucher(touche)
  local b = DialoguesBandeau
  b._scripts.OnKeyDown(b, touche)
  local propage = b._propage
  if b._scripts.OnKeyUp then b._scripts.OnKeyUp(b, touche) end
  b._propage = propage
end
-- Une touche gardée enfoncée : le jeu envoie des OnKeyDown répétés, sans relâchement.
local function maintenir(touche) DialoguesBandeau._scripts.OnKeyDown(DialoguesBandeau, touche) end
local function relacher(touche) DialoguesBandeau._scripts.OnKeyUp(DialoguesBandeau, touche) end
local function cliquer(bouton) bouton._scripts.OnClick(bouton, "LeftButton") end
local function ligneListe(i) return DialoguesBandeau.lignes[i] end
local function texteLigne(i) local l = ligneListe(i) return l and l.texte._text or "" end
local function bandeauVisible() return DialoguesBandeau ~= nil and DialoguesBandeau._shown == true end
local function cles(f) local t = {} for k in pairs(f) do if type(k) == "string" and k:sub(1, 1) ~= "_" then t[#t + 1] = k end end table.sort(t) return table.concat(t, ",") end

-- ---------------------------------------------------------------------------
-- 2a. Chargement et réglages
-- ---------------------------------------------------------------------------
installer()
local clesJeuAvant = cles(GossipFrame) .. "/" .. cles(QuestFrame)
local n = demarrer("defaut")
verifie("chargement : aucune erreur", nil, n.derniereErreur)
verifie("chargement : réglages créés", true, n.reglages ~= nil and DialoguesDB ~= nil)
verifie("chargement : valeurs de départ", "true,true,true,17,70", tostring(DialoguesDB.actif) .. "," .. tostring(DialoguesDB.morceaux) .. "," .. tostring(DialoguesDB.touches) .. "," .. DialoguesDB.tailleTexte .. "," .. DialoguesDB.largeur)
verifie("chargement : style de départ = scène", "scene", DialoguesDB.style)
verifie("chargement : écriture lettre par lettre par défaut", true, DialoguesDB.machine)
-- Les vérifications qui suivent (2b à 2p) lisent le bandeau d'origine, texte entier : on les y met.
DialoguesDB.style, DialoguesDB.machine = "bandeau", false
verifie("chargement : fenêtre du jeu coupée par défaut", false, DialoguesDB.fenetreJeu)
verifie("chargement : global du compartiment d'addons", "function", type(Dialogues_OuvrirReglages))
verifie("chargement : commande /dial", "/dial", SLASH_DIALOGUES1)
verifie("chargement : commande /dialogues", "/dialogues", SLASH_DIALOGUES2)
verifie("chargement : rien d'affiché au départ", false, bandeauVisible())

-- ---------------------------------------------------------------------------
-- 2b. Gossip : réponses numérotées, touches, clics
-- ---------------------------------------------------------------------------
declencher("GOSSIP_SHOW")
verifie("gossip : la fenêtre du jeu est invisible tout de suite", 0, GossipFrame:GetAlpha())
verifie("gossip : la fenêtre de quête aussi", 0, QuestFrame:GetAlpha())
verifie("gossip : leur souris est coupée", false, GossipFrame._souris)
verifie("gossip : leurs boutons enfants ne reçoivent plus de clic (échelle réduite)", 0.001, GossipFrame._scale)
verifie("gossip : le bandeau attend 0,15 s", false, bandeauVisible())
avancer()
verifie("gossip : le bandeau est affiché", true, bandeauVisible())
verifie("gossip : nom du PNJ", "Garde Mortemine", DialoguesBandeau.nomPNJ._text)
verifie("gossip : pas de titre de quête", "", DialoguesBandeau.titreQuete._text)
verifie("gossip : texte par paragraphes", "Bienvenue, voyageur.\nQue puis-je faire pour toi ?", DialoguesBandeau.texte._text)
verifie("gossip : une page, pas d'indicateur", "", DialoguesBandeau.compteur._text)
verifie("gossip : bouton Au revoir", "Au revoir", DialoguesBandeau.bouton._text)
verifie("gossip : pas de second bouton", false, DialoguesBandeau.boutonDeux._shown)
verifie("gossip : la case de la touche", "Espace", DialoguesBandeau.caseTouche.texte._text)
verifie("gossip : portrait du PNJ", "npc", JEU.portraits[#JEU.portraits])
verifie("gossip : la liste est affichée", true, DialoguesListe._shown)
verifie("gossip : première réponse (finie d'abord)", "|cffffffffLivraison urgente|r", texteLigne(1))
verifie("gossip : deuxième réponse (pas finie, grisée)", "|cff999999Retour au village|r", texteLigne(2))
verifie("gossip : troisième (quête à prendre)", "|cffffffffLes loups|r", texteLigne(3))
verifie("gossip : quatrième (phrase)", "|cffffffffJe voudrais voir vos marchandises.|r", texteLigne(4))
verifie("gossip : numéros", "1,2,3,4", ligneListe(1).numero._text .. "," .. ligneListe(2).numero._text .. "," .. ligneListe(3).numero._text .. "," .. ligneListe(4).numero._text)
verifie("gossip : marque ? dorée", "|cffffd200?|r", ligneListe(1).marque._text)
verifie("gossip : marque ! dorée", "|cffffd200!|r", ligneListe(3).marque._text)
verifie("gossip : cinq lignes n'existent pas", nil, ligneListe(5))
verifie("gossip : le clavier est pris", true, DialoguesBandeau._clavier)
toucher("W")
verifie("gossip : une lettre passe au jeu", true, DialoguesBandeau._propage)
toucher("3")
verifie("gossip : la touche 3 est prise", false, DialoguesBandeau._propage)
verifie("gossip : la touche 3 prend la quête n° 20", "gossip.dispo:20", appels())
JEU.appels = {}
avancer() -- l'attente de deux secondes finit
toucher("1")
verifie("gossip : la touche 1 rend la quête n° 10", "gossip.active:10", appels())
JEU.appels = {}
avancer()
toucher("4")
verifie("gossip : la touche 4 choisit la phrase", "gossip.option:5", appels())
JEU.appels = {}
avancer()
cliquer(ligneListe(2))
verifie("gossip : un clic sur la ligne 2", "gossip.active:11", appels())
JEU.appels = {}
avancer()
toucher("5")
verifie("gossip : la touche 5 n'existe pas, elle passe au jeu", true, DialoguesBandeau._propage and appels() == "")
toucher("SPACE")
verifie("gossip : Espace = Au revoir", "gossip.close", appels())
JEU.appels = {}
avancer()
declencher("GOSSIP_CLOSED") avancer()
ouvrir("gossip", "GOSSIP_SHOW")
toucher("ESCAPE")
verifie("gossip : Échap ferme aussi", "gossip.close", appels())
verifie("gossip : Échap est prise", false, DialoguesBandeau._propage)
verifie("gossip : le bandeau est caché après Échap", false, bandeauVisible())
JEU.appels = {}
declencher("GOSSIP_CLOSED")
avancer()
verifie("fin : la fenêtre du jeu est remise (opacité)", 1, GossipFrame:GetAlpha())
verifie("fin : la fenêtre de quête aussi", 1, QuestFrame:GetAlpha())
verifie("fin : la souris est remise", true, GossipFrame._souris)
verifie("fin : l'échelle est remise", 1, GossipFrame._scale)
verifie("fin : le clavier est rendu", false, DialoguesBandeau._clavier)

-- Beaucoup de réponses : neuf au plus, le reste est signalé.
JEU.gossip.dispos = {}
for i = 1, 11 do JEU.gossip.dispos[i] = { questID = 100 + i, title = "Quête " .. i } end
ouvrir("gossip", "GOSSIP_SHOW")
verifie("gossip : neuf réponses, puis la note sur les cinq autres", true, ligneListe(10) ~= nil and ligneListe(10).texte._text:find("+ 5 autres", 1, true) ~= nil and ligneListe(11) == nil)
verifie("gossip : la neuvième réponse porte le numéro 9", "9", ligneListe(9).numero._text)
verifie("gossip : la note parle de la fenêtre du jeu", true, ligneListe(10).texte._text:find("Fenêtre du jeu", 1, true) ~= nil)
declencher("GOSSIP_CLOSED") avancer()
JEU.gossip.dispos = { { questID = 20, title = "Les loups" } }

-- ---------------------------------------------------------------------------
-- 2c. Quête proposée (détail) : pages, accepter, refuser
-- ---------------------------------------------------------------------------
ouvrir("detail", "QUEST_DETAIL")
verifie("détail : bandeau affiché", true, bandeauVisible())
verifie("détail : titre de la quête", "Les loups", DialoguesBandeau.titreQuete._text)
verifie("détail : titre en doré", "1,0.82,0.3", table.concat(DialoguesBandeau.titreQuete._couleur, ","))
local nbPages = #(DialoguesBandeau.compteur._text:match("/ (%d+)") and { DialoguesBandeau.compteur._text:match("/ (%d+)") } or {})
local total = tonumber(DialoguesBandeau.compteur._text:match("/ (%d+)"))
verifie("détail : plusieurs pages", true, total ~= nil and total >= 3)
verifie("détail : indicateur 1 / n", "1 / " .. tostring(total), DialoguesBandeau.compteur._text)
verifie("détail : la première page n'est pas toute la quête", true, #DialoguesBandeau.texte._text < #JEU.detail.texte)
verifie("détail : bouton Suivant", "Suivant", DialoguesBandeau.bouton._text)
verifie("détail : pas de liste avant la fin", false, DialoguesListe._shown)
verifie("détail : pas de second bouton", false, DialoguesBandeau.boutonDeux._shown)
toucher("1")
verifie("détail : un chiffre ne fait rien ici", "", appels())
for i = 2, total do
  toucher("SPACE")
  verifie("détail : page " .. i .. " affichée", i .. " / " .. total, DialoguesBandeau.compteur._text)
end
verifie("détail : dernière page = l'objectif", true, DialoguesBandeau.texte._text:find("Objectif :", 1, true) ~= nil and DialoguesBandeau.texte._text:find("Tuez 4 loups.", 1, true) ~= nil)
verifie("détail : bouton Accepter", "Accepter", DialoguesBandeau.bouton._text)
verifie("détail : bouton Refuser", "Refuser", DialoguesBandeau.boutonDeux._text)
verifie("détail : bouton Refuser affiché", true, DialoguesBandeau.boutonDeux._shown)
verifie("détail : liste des récompenses", true, DialoguesListe._shown)
verifie("détail : rubrique « Tu recevras »", true, texteLigne(1):find("Tu recevras", 1, true) ~= nil)
verifie("détail : l'objet fixe, avec son nombre", true, texteLigne(2):find("Pain de voyage", 1, true) ~= nil and texteLigne(2):find("x2", 1, true) ~= nil)
verifie("détail : l'or", "|cffdddddd" .. "Or : 1 pa 50 pc" .. "|r", texteLigne(3))
verifie("détail : l'expérience", "|cffdddddd" .. "Expérience : 200" .. "|r", texteLigne(4))
toucher("SPACE")
verifie("détail : Espace accepte", "accept", appels())
toucher("SPACE")
verifie("détail : un second appui n'accepte pas deux fois", "accept", appels())
JEU.appels = {}
avancer()
-- Refuser.
ouvrir("detail", "QUEST_DETAIL")
for i = 2, total do toucher("SPACE") end
cliquer(DialoguesBandeau.boutonDeux)
verifie("détail : Refuser ferme la quête (CloseQuest, comme le jeu)", "close", appels())
JEU.appels = {}
avancer()
-- Un clic sur le bouton, comme au clavier.
ouvrir("detail", "QUEST_DETAIL")
cliquer(DialoguesBandeau.bouton)
verifie("détail : un clic sur Suivant passe à la page 2", "2 / " .. total, DialoguesBandeau.compteur._text)
-- Échap pendant une quête.
toucher("ESCAPE")
verifie("détail : Échap appelle CloseQuest", "close", appels())
JEU.appels = {}
declencher("QUEST_FINISHED") avancer()

-- ---------------------------------------------------------------------------
-- 2d. Progression
-- ---------------------------------------------------------------------------
ouvrir("progress", "QUEST_PROGRESS")
verifie("progression : bandeau affiché", true, bandeauVisible())
verifie("progression : texte", "As-tu mon colis ?", DialoguesBandeau.texte._text)
verifie("progression : pas finie, bouton Au revoir", "Au revoir", DialoguesBandeau.bouton._text)
verifie("progression : pas de second bouton", false, DialoguesBandeau.boutonDeux._shown)
verifie("progression : objets demandés", true, texteLigne(1):find("Objets demandés", 1, true) ~= nil and texteLigne(2):find("Colis scellé", 1, true) ~= nil)
toucher("SPACE")
verifie("progression : Espace = Au revoir = CloseQuest", "close", appels())
JEU.appels = {}
declencher("QUEST_FINISHED") avancer()
JEU.progress.completable = true
ouvrir("progress", "QUEST_PROGRESS")
verifie("progression : finie, bouton Continuer", "Continuer", DialoguesBandeau.bouton._text)
verifie("progression : finie, second bouton Au revoir", "Au revoir", DialoguesBandeau.boutonDeux._text)
toucher("SPACE")
verifie("progression : Continuer appelle CompleteQuest", "complete", appels())
JEU.appels = {}
JEU.progress.completable = false
declencher("QUEST_FINISHED") avancer()

-- ---------------------------------------------------------------------------
-- 2e. Fin de quête : récompenses à choisir
-- ---------------------------------------------------------------------------
JEU.bulles = { choice1 = { "Épée de garde", "|cff1eff00Mieux pour Vindicte : +5 % (Pawn)|r" } }
ouvrir("complete", "QUEST_COMPLETE")
verifie("fin de quête : bandeau affiché", true, bandeauVisible())
verifie("fin de quête : texte", "Merci, voyageur. Voici ta récompense.", DialoguesBandeau.texte._text)
verifie("fin de quête : bouton grisé", "Choisis une récompense", DialoguesBandeau.bouton._text)
verifie("fin de quête : bouton désactivé", false, DialoguesBandeau.bouton._actif)
verifie("fin de quête : rubrique des choix", true, texteLigne(1):find("Choisis ta récompense", 1, true) ~= nil)
verifie("fin de quête : trois choix numérotés", "1,2,3", ligneListe(2).numero._text .. "," .. ligneListe(3).numero._text .. "," .. ligneListe(4).numero._text)
verifie("fin de quête : nom coloré par la qualité", "|cff0070ddÉpée de garde|r", texteLigne(2))
verifie("fin de quête : icône", "Interface\\Icons\\INV_Sword_01", ligneListe(2).icone._texture)
verifie("fin de quête : « Mieux pour toi » sous l'épée", "Mieux pour toi : +5 % (Pawn)", ligneListe(2).conseil._text)
verifie("fin de quête : rien sous le bouclier", "", ligneListe(3).conseil._text)
verifie("fin de quête : la bulle n'est pas restée affichée", false, GameTooltip._shown)
verifie("fin de quête : l'or", true, texteLigne(5):find("Tu recevras", 1, true) == nil and (texteLigne(5):find("Or : 1 po 25 pa", 1, true) ~= nil or texteLigne(6):find("Or : 1 po 25 pa", 1, true) ~= nil))
toucher("SPACE")
verifie("fin de quête : Espace ne termine pas sans choix", "", appels())
verifie("fin de quête : Espace grisé est pris sans rien faire", false, DialoguesBandeau._propage)
cliquer(DialoguesBandeau.bouton)
verifie("fin de quête : le bouton grisé ne fait rien non plus", "", appels())
toucher("4")
verifie("fin de quête : la touche 4 n'existe pas", "", appels())
verifie("fin de quête : aucun choix encore", "Choisis une récompense", DialoguesBandeau.bouton._text)
toucher("2")
verifie("fin de quête : la touche 2 choisit le bouclier", "Terminer la quête", DialoguesBandeau.bouton._text)
verifie("fin de quête : le bouton est actif", true, DialoguesBandeau.bouton._actif)
verifie("fin de quête : le choix est encadré d'or", "0.8,0.63,0.3,1", table.concat(ligneListe(3)._bordure, ","))
verifie("fin de quête : les autres gardent la bordure sombre", "0.3,0.25,0.15,1", table.concat(ligneListe(2)._bordure, ","))
-- Au survol : la bulle de l'objet, et l'avis de Sacs rangés s'il y est.
JEU.bulles = { choice2 = { "Bouclier de garde", "|cff1eff00Mieux pour toi : +9 %|r" } }
ligneListe(3)._scripts.OnEnter(ligneListe(3))
verifie("fin de quête : au survol, la bulle est affichée", true, GameTooltip._shown)
verifie("fin de quête : au survol, l'avis apparaît sous l'objet", "Mieux pour toi : +9 %", ligneListe(3).conseil._text)
ligneListe(3)._scripts.OnLeave(ligneListe(3))
verifie("fin de quête : la bulle se cache", false, GameTooltip._shown)
JEU.bulles = {}
cliquer(ligneListe(4))
verifie("fin de quête : un clic choisit la bague (3)", "Terminer la quête", DialoguesBandeau.bouton._text)
toucher("2")
toucher("SPACE")
verifie("fin de quête : GetQuestReward avec le bon numéro", "reward:2", appels())
JEU.appels = {}
avancer()
declencher("QUEST_FINISHED") avancer()
-- Un seul choix : déjà choisi.
local unique = JEU.complete.choix
JEU.complete.choix = { unique[1] }
ouvrir("complete", "QUEST_COMPLETE")
verifie("fin de quête : un seul choix, bouton actif", "Terminer la quête", DialoguesBandeau.bouton._text)
toucher("SPACE")
verifie("fin de quête : un seul choix, GetQuestReward(1)", "reward:1", appels())
JEU.appels = {}
declencher("QUEST_FINISHED") avancer()
-- Aucun choix.
JEU.complete.choix = {}
JEU.complete.fixes = { { "Pièce d'or", "Interface\\Icons\\INV_Misc_Coin_01", 1, 1, "|cffffffff|Hitem:9|h[Pièce d'or]|h|r" } }
ouvrir("complete", "QUEST_COMPLETE")
verifie("fin de quête : sans choix, bouton actif", "Terminer la quête", DialoguesBandeau.bouton._text)
verifie("fin de quête : sans choix, rubrique des récompenses fixes", true, texteLigne(1):find("Tu recevras", 1, true) ~= nil)
toucher("SPACE")
verifie("fin de quête : sans choix, GetQuestReward(0)", "reward:0", appels())
JEU.appels = {}
declencher("QUEST_FINISHED") avancer()
JEU.complete.choix, JEU.complete.fixes = unique, {}
-- Avec l'option « conseil » coupée.
JEU.complete.choix = unique
n.reglages.changer("conseil", false)
ouvrir("complete", "QUEST_COMPLETE")
verifie("fin de quête : option conseil coupée, ligne absente", "", ligneListe(2).conseil._text)
n.reglages.changer("conseil", true)
declencher("QUEST_FINISHED") avancer()
-- Sans la ligne de Sacs rangés : rien n'est inventé.
JEU.bulles = {}
ouvrir("complete", "QUEST_COMPLETE")
verifie("fin de quête : sans Sacs rangés, ligne absente", "", ligneListe(2).conseil._text)
declencher("QUEST_FINISHED") avancer()

-- ---------------------------------------------------------------------------
-- 2f. Ancien PNJ (QUEST_GREETING)
-- ---------------------------------------------------------------------------
ouvrir("greeting", "QUEST_GREETING")
verifie("greeting : bandeau affiché", true, bandeauVisible())
verifie("greeting : texte", "Salutations.", DialoguesBandeau.texte._text)
verifie("greeting : quête à rendre", "|cffffffffRapport au capitaine|r", texteLigne(1))
verifie("greeting : quête à prendre", "|cffffffffUne affaire de rats|r", texteLigne(2))
toucher("1")
verifie("greeting : la touche 1 rend la quête n° 1 (ancienne API)", "greeting.active:1", appels())
JEU.appels = {}
avancer()
toucher("2")
verifie("greeting : la touche 2 prend la quête n° 1 (ancienne API)", "greeting.dispo:1", appels())
JEU.appels = {}
declencher("QUEST_FINISHED") avancer()

-- ---------------------------------------------------------------------------
-- 2g. Cohabitation avec Quêtes auto et l'ordre des événements
-- ---------------------------------------------------------------------------
JEU.appels = {}
declencher("GOSSIP_SHOW")
JEU.etape = "detail"
declencher("QUEST_DETAIL") -- Quêtes auto choisit la quête, l'accepte : QUEST_FINISHED, tout avant le délai
declencher("QUEST_FINISHED")
avancer()
verifie("cohabitation : événement clos avant 0,15 s, rien affiché", false, bandeauVisible())
verifie("cohabitation : la fenêtre du jeu est remise", 1, GossipFrame:GetAlpha())
-- Ce QUEST_FINISHED n'a pas fermé un GOSSIP en cours (il vient d'une autre quête).
declencher("GOSSIP_SHOW")
declencher("QUEST_FINISHED")
avancer()
verifie("cohabitation : QUEST_FINISHED ne ferme pas un dialogue gossip", true, bandeauVisible())
declencher("GOSSIP_CLOSED") avancer()
verifie("cohabitation : GOSSIP_CLOSED le ferme", false, bandeauVisible())
-- Gossip puis quête : seule la quête s'affiche.
declencher("GOSSIP_SHOW")
JEU.etape = "detail"
declencher("QUEST_DETAIL")
avancer()
verifie("cohabitation : seule l'étape la plus récente s'affiche", "Les loups", DialoguesBandeau.titreQuete._text)
-- GOSSIP_CLOSED en retard, après QUEST_DETAIL : la quête reste.
declencher("GOSSIP_CLOSED")
avancer()
verifie("cohabitation : GOSSIP_CLOSED tardif ne ferme pas la quête", true, bandeauVisible())
verifie("cohabitation : la fenêtre du jeu reste invisible", 0, QuestFrame:GetAlpha())
declencher("QUEST_FINISHED") avancer()
verifie("cohabitation : fin de quête, bandeau caché", false, bandeauVisible())
verifie("cohabitation : fin de quête, fenêtre du jeu remise", 1, QuestFrame:GetAlpha())
-- Passage d'une étape à l'autre : le bandeau ne se ferme pas entre les deux.
JEU.etape = "gossip"
declencher("GOSSIP_SHOW") avancer()
declencher("GOSSIP_CLOSED")
JEU.etape = "detail"
declencher("QUEST_DETAIL")
avancer()
verifie("cohabitation : gossip fermé puis quête ouverte, bandeau montré", true, bandeauVisible())
declencher("QUEST_FINISHED") avancer()

-- ---------------------------------------------------------------------------
-- 2h. Combat : aucune touche, aucun appel interdit
-- ---------------------------------------------------------------------------
ouvrir("gossip", "GOSSIP_SHOW")
verifie("combat : le clavier est pris avant le combat", true, DialoguesBandeau._clavier)
declencher("PLAYER_REGEN_DISABLED") -- le combat commence : les appels sont encore permis
enCombat = true
verifie("combat : les touches sont rendues au jeu", true, DialoguesBandeau._propage)
verifie("combat : plus de clavier sur le bandeau", false, DialoguesBandeau._clavier)
local okC, errC = pcall(toucher, "SPACE")
verifie("combat : une touche reçue par erreur ne lève rien", true, okC)
if not okC then io.write("   " .. tostring(errC) .. "\n") end
verifie("combat : Espace ne fait rien", "", appels())
okC = pcall(toucher, "1")
verifie("combat : un chiffre ne fait rien", "", appels())
local okR, errR = pcall(function() DialoguesBandeau._scripts.OnKeyUp(DialoguesBandeau, "W") end)
verifie("combat : relâcher une touche ne lève rien", true, okR)
cliquer(ligneListe(3))
verifie("combat : la souris marche toujours (clic sur une réponse)", "gossip.dispo:20", appels())
JEU.appels = {}
avancer()
-- Une quête s'ouvre en plein combat : affichée, sans clavier, sans toucher la souris des cadres du jeu.
JEU.etape = "detail"
local okE, errE = pcall(function() declencher("QUEST_DETAIL") avancer() end)
verifie("combat : une quête s'ouvre sans erreur", true, okE)
if not okE then io.write("   " .. tostring(errE) .. "\n") end
verifie("combat : bandeau affiché", true, bandeauVisible())
verifie("combat : toujours pas de clavier", false, DialoguesBandeau._clavier)
verifie("combat : la fenêtre du jeu est invisible", 0, QuestFrame:GetAlpha())
declencher("QUEST_FINISHED") avancer()
verifie("combat : fin de l'échange, fenêtre du jeu remise", 1, QuestFrame:GetAlpha())
-- La souris coupée hors combat est remise seulement après le combat.
enCombat = false
JEU.etape = "gossip"
declencher("GOSSIP_SHOW") avancer()
verifie("combat : (hors combat) la souris du cadre est coupée", false, GossipFrame._souris)
entrerCombat()
declencher("GOSSIP_CLOSED")
local okF = pcall(avancer)
verifie("combat : fermeture en combat sans erreur", true, okF)
verifie("combat : l'opacité est remise tout de suite", 1, GossipFrame:GetAlpha())
verifie("combat : la souris attend la fin du combat", false, GossipFrame._souris)
enCombat = false
declencher("PLAYER_REGEN_ENABLED")
verifie("combat : fin du combat, la souris est remise", true, GossipFrame._souris)
-- Le clavier revient à la fin du combat si le bandeau est affiché.
JEU.etape = "gossip"
entrerCombat()
declencher("GOSSIP_SHOW") avancer()
verifie("combat : bandeau ouvert en combat, clavier coupé", true, bandeauVisible() and not DialoguesBandeau._clavier)
enCombat = false
declencher("PLAYER_REGEN_ENABLED")
verifie("combat : fin du combat, le clavier revient", true, DialoguesBandeau._clavier)
declencher("GOSSIP_CLOSED") avancer()

-- ---------------------------------------------------------------------------
-- 2i. Erreur d'affichage : la fenêtre du jeu reprend la main
-- ---------------------------------------------------------------------------
local texteSain = JEU.gossip.texte
JEU.gossip.texte = "BOOM"
imprime = {}
JEU.etape = "gossip"
declencher("GOSSIP_SHOW") avancer()
verifie("erreur : le bandeau est caché", false, bandeauVisible())
verifie("erreur : la fenêtre du jeu est remontrée", 1, GossipFrame:GetAlpha())
verifie("erreur : la souris du jeu est remise", true, GossipFrame._souris)
verifie("erreur : l'erreur est notée", true, n.derniereErreur ~= nil and n.derniereErreur:find("erreur d'affichage simulée", 1, true) ~= nil)
verifie("erreur : dite une seule fois dans le chat", 1, compte("la fenêtre du jeu reprend la main"))
-- Les autres étapes du même échange restent chez le jeu.
JEU.etape = "detail"
declencher("QUEST_DETAIL") avancer()
verifie("erreur : le reste de l'échange reste dans la fenêtre du jeu", true, not bandeauVisible() and QuestFrame:GetAlpha() == 1)
declencher("QUEST_FINISHED") avancer()
-- Deuxième et troisième pannes : pas de nouveau message.
for _ = 1, 2 do
  JEU.etape = "gossip"
  declencher("GOSSIP_SHOW") avancer()
  declencher("GOSSIP_CLOSED") avancer()
end
verifie("erreur : toujours un seul message", 1, compte("la fenêtre du jeu reprend la main"))
-- Après trois pannes, on ne masque plus rien.
JEU.gossip.texte = texteSain
JEU.etape = "gossip"
declencher("GOSSIP_SHOW")
verifie("erreur : après trois pannes, la fenêtre du jeu n'est plus masquée", 1, GossipFrame:GetAlpha())
avancer()
verifie("erreur : après trois pannes, pas de bandeau", false, bandeauVisible())
declencher("GOSSIP_CLOSED") avancer()

-- ---------------------------------------------------------------------------
-- 2j. Le bandeau d'essai (/dial test)
-- ---------------------------------------------------------------------------
JEU.appels = {}
SlashCmdList.DIALOGUES("test")
verifie("essai : le bandeau s'affiche (et remet les pannes à zéro)", true, bandeauVisible())
verifie("essai : le portrait est le joueur", "player", JEU.portraits[#JEU.portraits])
verifie("essai : un faux PNJ", "Garde d'essai", DialoguesBandeau.nomPNJ._text)
local totalEssai = tonumber(DialoguesBandeau.compteur._text:match("/ (%d+)"))
verifie("essai : plusieurs pages", true, totalEssai ~= nil and totalEssai >= 2)
for _ = 2, totalEssai do toucher("SPACE") end
verifie("essai : dernière page, Accepter", "Accepter", DialoguesBandeau.bouton._text)
toucher("SPACE")
verifie("essai : Accepter mène à l'écran de fin", "Choisis une récompense", DialoguesBandeau.bouton._text)
toucher("3")
toucher("SPACE")
verifie("essai : terminer ferme le bandeau", false, bandeauVisible())
verifie("essai : aucune action du jeu pendant l'essai", "", appels())
verifie("essai : le chat dit que c'est fini", true, lireImprime():find("fin de l'essai", 1, true) ~= nil)
verifie("essai : la fenêtre du jeu n'a pas été touchée", true, GossipFrame:GetAlpha() == 1 and QuestFrame:GetAlpha() == 1)
SlashCmdList.DIALOGUES("test")
toucher("ESCAPE")
verifie("essai : Échap ferme le faux dialogue", false, bandeauVisible())
verifie("essai : Échap n'appelle rien au jeu", "", appels())

-- Un échange réel fonctionne de nouveau après l'essai (les pannes sont remises à zéro).
JEU.etape = "gossip"
declencher("GOSSIP_SHOW") avancer()
verifie("essai : un vrai dialogue s'affiche de nouveau", true, bandeauVisible())
declencher("GOSSIP_CLOSED") avancer()

-- ---------------------------------------------------------------------------
-- 2k. /dial jeu, le bouton « Fenêtre du jeu », l'addon coupé
-- ---------------------------------------------------------------------------
JEU.etape = "gossip"
declencher("GOSSIP_SHOW") avancer()
verifie("jeu : bandeau affiché", true, bandeauVisible())
SlashCmdList.DIALOGUES("jeu")
verifie("/dial jeu : l'option est cochée", true, DialoguesDB.fenetreJeu)
verifie("/dial jeu : le bandeau disparaît", false, bandeauVisible())
verifie("/dial jeu : la fenêtre du jeu est remise", 1, GossipFrame:GetAlpha())
verifie("/dial jeu : la souris du jeu est remise", true, GossipFrame._souris)
declencher("GOSSIP_CLOSED") avancer()
declencher("GOSSIP_SHOW") avancer()
verifie("/dial jeu : plus de bandeau ni de masque", true, not bandeauVisible() and GossipFrame:GetAlpha() == 1)
declencher("GOSSIP_CLOSED") avancer()
SlashCmdList.DIALOGUES("jeu")
verifie("/dial jeu : l'option est décochée", false, DialoguesDB.fenetreJeu)
declencher("GOSSIP_SHOW") avancer()
verifie("/dial jeu : le bandeau est de retour", true, bandeauVisible())
-- Le bouton du bandeau : la fenêtre du jeu pour cet échange seulement.
cliquer(DialoguesBandeau.boutonJeu)
verifie("bouton « Fenêtre du jeu » : le bandeau se cache", false, bandeauVisible())
verifie("bouton « Fenêtre du jeu » : la fenêtre du jeu revient", 1, GossipFrame:GetAlpha())
JEU.etape = "detail"
declencher("QUEST_DETAIL") avancer()
verifie("bouton « Fenêtre du jeu » : la suite de l'échange reste chez le jeu", true, not bandeauVisible() and QuestFrame:GetAlpha() == 1)
declencher("QUEST_FINISHED") avancer()
JEU.etape = "gossip"
declencher("GOSSIP_SHOW") avancer()
verifie("bouton « Fenêtre du jeu » : l'échange suivant revient au bandeau", true, bandeauVisible())
-- L'addon coupé pendant un dialogue.
n.reglages.changer("actif", false)
verifie("addon coupé : le bandeau disparaît", false, bandeauVisible())
verifie("addon coupé : la fenêtre du jeu revient", 1, GossipFrame:GetAlpha())
declencher("GOSSIP_CLOSED") avancer()
declencher("GOSSIP_SHOW") avancer()
verifie("addon coupé : rien ne s'affiche", true, not bandeauVisible() and GossipFrame:GetAlpha() == 1)
declencher("GOSSIP_CLOSED") avancer()
n.reglages.changer("actif", true)
SlashCmdList.DIALOGUES("off")
verifie("/dial off : coupé", false, DialoguesDB.actif)
SlashCmdList.DIALOGUES("on")
verifie("/dial on : activé", true, DialoguesDB.actif)
imprime = {}
SlashCmdList.DIALOGUES("aide")
verifie("/dial aide : la liste des commandes", true, lireImprime():find("/dial jeu", 1, true) ~= nil and lireImprime():find("/dial test", 1, true) ~= nil)
imprime = {}
SlashCmdList.DIALOGUES("zorglub")
verifie("commande inconnue : message", true, lireImprime():find("commande inconnue", 1, true) ~= nil)
verifie("/dial : ouvre les réglages sans erreur", true, pcall(SlashCmdList.DIALOGUES, ""))

-- ---------------------------------------------------------------------------
-- 2l. Réglages appliqués sans /reload
-- ---------------------------------------------------------------------------
JEU.etape = "detail"
declencher("QUEST_DETAIL") avancer()
local pagesAvant = tonumber(DialoguesBandeau.compteur._text:match("/ (%d+)"))
n.reglages.changer("tailleTexte", 22)
local pagesApres = tonumber(DialoguesBandeau.compteur._text:match("/ (%d+)"))
verifie("réglage : texte plus grand, plus de pages", true, pagesApres > pagesAvant)
n.reglages.changer("tailleTexte", 12)
verifie("réglage : texte plus petit, moins de pages", true, tonumber(DialoguesBandeau.compteur._text:match("/ (%d+)")) < pagesApres)
n.reglages.changer("tailleTexte", 15)
local largeurAvant = DialoguesBandeau._w
n.reglages.changer("largeur", 50)
verifie("réglage : largeur 50 % de l'écran", 960, DialoguesBandeau._w)
verifie("réglage : la largeur change", true, DialoguesBandeau._w < largeurAvant)
n.reglages.changer("largeur", 90)
verifie("réglage : largeur 90 %", 1728, DialoguesBandeau._w)
n.reglages.changer("largeur", 70)
n.reglages.changer("morceaux", false)
verifie("réglage : sans morceaux, une seule page", "", DialoguesBandeau.compteur._text)
verifie("réglage : sans morceaux, tout le texte", true, DialoguesBandeau.texte._text:find("Personne n'ose plus sortir la nuit.", 1, true) ~= nil)
verifie("réglage : sans morceaux, Accepter tout de suite", "Accepter", DialoguesBandeau.bouton._text)
n.reglages.changer("morceaux", true)
verifie("réglage : les morceaux reviennent", true, DialoguesBandeau.compteur._text ~= "")
n.reglages.changer("touches", false)
verifie("réglage : touches coupées, clavier rendu", false, DialoguesBandeau._clavier)
verifie("réglage : touches coupées, case de touche cachée", false, DialoguesBandeau.caseTouche._shown)
n.reglages.changer("touches", true)
verifie("réglage : touches remises, clavier pris", true, DialoguesBandeau._clavier)
declencher("QUEST_FINISHED") avancer()
-- Chaque réglage existe, avec ses bornes.
local okOpts = true
for _, cle in ipairs({ "actif", "morceaux", "touches", "conseil", "tailleTexte", "largeur" }) do
  if DialoguesDB[cle] == nil then okOpts = false end
end
verifie("réglages : toutes les clés sont sauvegardées", true, okOpts)
verifie("réglage : /dial conseil bascule l'option", true, (function()
  SlashCmdList.DIALOGUES("conseil")
  local coupe = DialoguesDB.conseil == false
  SlashCmdList.DIALOGUES("conseil")
  return coupe and DialoguesDB.conseil == true
end)())

-- ---------------------------------------------------------------------------
-- 2m. Immersion chargé : on ne s'en mêle pas
-- ---------------------------------------------------------------------------
installer()
C_AddOns.IsAddOnLoaded = function(nom) return nom == "Immersion" end
local ni = demarrer()
imprime = {}
declencher("GOSSIP_SHOW") avancer()
declencher("GOSSIP_CLOSED") avancer()
declencher("QUEST_DETAIL") avancer()
declencher("QUEST_FINISHED") avancer()
verifie("Immersion : rien n'est affiché", false, bandeauVisible())
verifie("Immersion : la fenêtre du jeu n'est pas touchée", true, GossipFrame:GetAlpha() == 1 and QuestFrame:GetAlpha() == 1 and GossipFrame._souris == true)
verifie("Immersion : un seul message", 1, compte("Immersion est chargé"))
verifie("Immersion : aucune erreur", nil, ni.derniereErreur)

-- ---------------------------------------------------------------------------
-- 2n. Rien n'est écrit dans les cadres du jeu
-- ---------------------------------------------------------------------------
verifie("cadres du jeu : aucun champ écrit par l'addon", clesJeuAvant, (function()
  -- la même série de scénarios sur une installation neuve
  installer()
  local avant = cles(GossipFrame) .. "/" .. cles(QuestFrame)
  demarrer()
  for _, e in ipairs({ { "gossip", "GOSSIP_SHOW" }, { "greeting", "QUEST_GREETING" }, { "detail", "QUEST_DETAIL" },
                       { "progress", "QUEST_PROGRESS" }, { "complete", "QUEST_COMPLETE" } }) do
    ouvrir(e[1], e[2])
    pcall(toucher, "SPACE")
    declencher("QUEST_FINISHED"); declencher("GOSSIP_CLOSED"); avancer()
  end
  verifie("cadres du jeu : bien revenus à l'état d'avant", "1,true", GossipFrame:GetAlpha() .. "," .. tostring(GossipFrame._souris))
  verifie("cadres du jeu : avant les scénarios, rien d'écrit", clesJeuAvant, avant)
  return cles(GossipFrame) .. "/" .. cles(QuestFrame)
end)())
-- Le test sait-il voir une écriture ? (preuve que la mesure n'est pas vide)
installer()
GossipFrame.champIntrus = 1
verifie("cadres du jeu : la mesure repère un champ écrit", true, cles(GossipFrame) ~= clesJeuAvant:match("^[^/]*"))

-- ---------------------------------------------------------------------------
-- 2o. Des API qui manquent une à une : aucune erreur ne sort
-- ---------------------------------------------------------------------------
local manques = {
  { "C_GossipInfo", function() C_GossipInfo = nil end },
  { "C_GossipInfo.GetText", function() C_GossipInfo.GetText = nil end },
  { "C_GossipInfo.GetActiveQuests", function() C_GossipInfo.GetActiveQuests = nil end },
  { "C_GossipInfo.GetAvailableQuests", function() C_GossipInfo.GetAvailableQuests = nil end },
  { "C_GossipInfo.GetOptions", function() C_GossipInfo.GetOptions = nil end },
  { "C_GossipInfo.SelectOption", function() C_GossipInfo.SelectOption = nil end },
  { "C_GossipInfo.CloseGossip", function() C_GossipInfo.CloseGossip = nil end },
  { "GetGreetingText", function() GetGreetingText = nil end },
  { "GetNumActiveQuests", function() GetNumActiveQuests = nil end },
  { "GetActiveTitle", function() GetActiveTitle = nil end },
  { "GetNumAvailableQuests", function() GetNumAvailableQuests = nil end },
  { "GetAvailableTitle", function() GetAvailableTitle = nil end },
  { "GetTitleText", function() GetTitleText = nil end },
  { "GetQuestText", function() GetQuestText = nil end },
  { "GetObjectiveText", function() GetObjectiveText = nil end },
  { "GetProgressText", function() GetProgressText = nil end },
  { "GetRewardText", function() GetRewardText = nil end },
  { "IsQuestCompletable", function() IsQuestCompletable = nil end },
  { "GetQuestMoneyToGet", function() GetQuestMoneyToGet = nil end },
  { "GetNumQuestItems", function() GetNumQuestItems = nil end },
  { "GetNumQuestChoices", function() GetNumQuestChoices = nil end },
  { "GetNumQuestRewards", function() GetNumQuestRewards = nil end },
  { "GetQuestItemInfo", function() GetQuestItemInfo = nil end },
  { "GetQuestItemLink", function() GetQuestItemLink = nil end },
  { "GetRewardMoney", function() GetRewardMoney = nil end },
  { "GetRewardXP", function() GetRewardXP = nil end },
  { "UnitName", function() UnitName = nil end },
  { "UnitExists", function() UnitExists = nil end },
  { "SetPortraitTexture", function() SetPortraitTexture = nil end },
  { "GossipFrame", function() GossipFrame = nil end },
  { "QuestFrame", function() QuestFrame = nil end },
  { "STANDARD_TEXT_FONT", function() STANDARD_TEXT_FONT = nil end },
  { "InCombatLockdown", function() InCombatLockdown = nil end },
  { "IsShiftKeyDown", function() IsShiftKeyDown = nil end },
  { "IsControlKeyDown", function() IsControlKeyDown = nil end },
  { "C_AddOns", function() C_AddOns = nil end },
  { "C_Timer", function() C_Timer = nil end },
  { "GameTooltip", function() GameTooltip = nil end },
  { "issecretvalue qui répond toujours oui", function() issecretvalue = function() return true end end },
  { "CreateFrame sans PlayerModel", function()
      local cf = CreateFrame
      CreateFrame = function(g, ...) if g == "PlayerModel" then error("type de cadre inconnu") end return cf(g, ...) end
    end },
  { "SetUnit qui échoue", function() modelePanne = true end },
  { "UIParent.GetHeight absurde", function() UIParent.GetHeight = function() return "bizarre" end end },
  { "un jeu qui répond n'importe quoi", function()
      C_GossipInfo.GetActiveQuests = function() return "pas une liste" end
      C_GossipInfo.GetOptions = function() return { 42, "x", {} } end
      C_GossipInfo.GetText = function() return 12 end
      GetQuestItemInfo = function() return nil end
      GetNumQuestChoices = function() return "trois" end
    end },
}
for _, styleManque in ipairs({ "bandeau", "scene", "face", "cinema" }) do
for _, m in ipairs(manques) do
  installer()
  m[2]()
  local nm
  local okM, err = pcall(function()
    nm = demarrer(styleManque, styleManque ~= "bandeau")
    for _, e in ipairs({ { "gossip", "GOSSIP_SHOW" }, { "greeting", "QUEST_GREETING" }, { "detail", "QUEST_DETAIL" },
                         { "progress", "QUEST_PROGRESS" }, { "complete", "QUEST_COMPLETE" } }) do
      JEU.etape = e[1]
      declencher(e[2])
      avancer()
      if DialoguesBandeau and DialoguesBandeau._shown then
        for _, t in ipairs({ "SPACE", "2", "1", "SPACE", "ESCAPE" }) do
          if DialoguesBandeau._shown then DialoguesBandeau._scripts.OnKeyDown(DialoguesBandeau, t) end
        end
      end
      declencher("QUEST_FINISHED"); declencher("GOSSIP_CLOSED"); avancer()
    end
    SlashCmdList.DIALOGUES("test")
    pcall(toucher, "SPACE")
    avancer()
  end)
  verifie("API manquante (" .. styleManque .. ") : " .. m[1] .. " : aucune erreur", true, okM)
  if not okM then io.write("   " .. tostring(err) .. "\n") end
end
end

-- Une action du jeu absente ou en erreur : la fenêtre du jeu reprend la main, rien ne plante.
local actions = { "AcceptQuest", "Refuser", "CompleteQuest", "GetQuestReward", "CloseQuest" }
for _, nomAction in ipairs(actions) do
  installer()
  local nm = demarrer()
  imprime = {}
  _G[nomAction == "Refuser" and "CloseQuest" or nomAction] = nil
  local okA, errA = pcall(function()
    local scenario = nomAction == "CompleteQuest" and "progress" or nomAction == "GetQuestReward" and "complete" or "detail"
    JEU.progress.completable = true
    JEU.etape = scenario
    declencher(scenario == "detail" and "QUEST_DETAIL" or scenario == "progress" and "QUEST_PROGRESS" or "QUEST_COMPLETE")
    avancer()
    -- On tourne les pages jusqu'au bouton d'action final.
    local garde = 0
    while DialoguesBandeau.bouton._text == "Suivant" and garde < 20 do garde = garde + 1; toucher("SPACE") end
    if scenario == "complete" then toucher("1") end
    if nomAction == "Refuser" then cliquer(DialoguesBandeau.boutonDeux) else toucher("SPACE") end
    if nomAction == "CloseQuest" then toucher("ESCAPE") end
    avancer()
  end)
  verifie("action absente : " .. nomAction .. " : aucune erreur qui sorte", true, okA)
  if not okA then io.write("   " .. tostring(errA) .. "\n") end
  verifie("action absente : " .. nomAction .. " : la fenêtre du jeu est visible", 1, QuestFrame:GetAlpha())
end

-- ---------------------------------------------------------------------------
-- 2p. Correctifs de la relecture
-- ---------------------------------------------------------------------------
-- (1) Une erreur dans le chemin clavier : le filet de sécurité se déclenche, aucune erreur ne sort.
installer()
local np = demarrer()
ouvrir("detail", "QUEST_DETAIL")
np.toucheVers = function() error("panne simulée dans toucheVers") end
local okP, errP = pcall(toucher, "SPACE")
verifie("erreur au clavier : aucune erreur ne sort de OnKeyDown", true, okP)
if not okP then io.write("   " .. tostring(errP) .. "\n") end
verifie("erreur au clavier : l'erreur est notée", true, tostring(np.derniereErreur):find("panne simulée", 1, true) ~= nil)
verifie("erreur au clavier : le bandeau est caché", false, bandeauVisible())
verifie("erreur au clavier : la fenêtre du jeu est remontrée", 1, QuestFrame:GetAlpha())
verifie("erreur au clavier : un seul message", 1, compte("un souci d'affichage"))
declencher("QUEST_FINISHED") avancer()

-- (4) Une erreur de rendu au clic (Suivant, récompense) : même filet, rien ne sort.
installer()
np = demarrer()
ouvrir("detail", "QUEST_DETAIL")
np.lignesListe = function() error("panne de rendu simulée") end
okP, errP = pcall(cliquer, DialoguesBandeau.bouton)
verifie("clic Suivant : une erreur de rendu ne sort pas", true, okP)
verifie("clic Suivant : le bandeau est caché", false, bandeauVisible())
verifie("clic Suivant : la fenêtre du jeu est remontrée", 1, QuestFrame:GetAlpha())
declencher("QUEST_FINISHED") avancer()
installer()
np = demarrer()
ouvrir("complete", "QUEST_COMPLETE")
np.lignesListe = function() error("panne de rendu simulée") end
okP, errP = pcall(cliquer, ligneListe(3))
verifie("clic sur une récompense : une erreur de rendu ne sort pas", true, okP)
verifie("clic sur une récompense : la fenêtre du jeu est remontrée", 1, QuestFrame:GetAlpha())
declencher("QUEST_FINISHED") avancer()

-- (5) Le jeu rend 1 au lieu de true : « Continuer » et la marque « ? » marchent quand même.
installer()
demarrer()
JEU.progress.completable = 1
ouvrir("progress", "QUEST_PROGRESS")
verifie("IsQuestCompletable rend 1 : bouton Continuer", "Continuer", DialoguesBandeau.bouton._text)
declencher("QUEST_FINISHED") avancer()
JEU.progress.completable = 0
ouvrir("progress", "QUEST_PROGRESS")
verifie("IsQuestCompletable rend 0 : bouton Au revoir", "Au revoir", DialoguesBandeau.bouton._text)
declencher("QUEST_FINISHED") avancer()
JEU.greeting.actives = { { "Rapport au capitaine", 1 } }
ouvrir("greeting", "QUEST_GREETING")
verifie("GetActiveTitle rend 1 : la quête est marquée finie (?)", "|cffffd200?|r", ligneListe(1).marque._text)
declencher("QUEST_FINISHED") avancer()

-- (2) Les confirmations du jeu ne sont pas contournées.
installer()
demarrer()
_G.QuestFlagsPVP = function() return true end
ouvrir("detail", "QUEST_DETAIL")
for _ = 1, 20 do if DialoguesBandeau.bouton._text == "Suivant" then toucher("SPACE") end end
toucher("SPACE")
verifie("quête JcJ : AcceptQuest n'est pas appelé", "", appels())
verifie("quête JcJ : la fenêtre du jeu reprend la main", 1, QuestFrame:GetAlpha())
verifie("quête JcJ : le bandeau est caché", false, bandeauVisible())
verifie("quête JcJ : le joueur est prévenu", 1, compte("active le JcJ"))
declencher("QUEST_FINISHED") avancer()
_G.QuestFlagsPVP = nil
_G.QuestGetAutoAccept = function() return 1 end
_G.AcknowledgeAutoAcceptQuest = function() JEU.appels[#JEU.appels + 1] = "ack" end
ouvrir("detail", "QUEST_DETAIL")
for _ = 1, 20 do if DialoguesBandeau.bouton._text == "Suivant" then toucher("SPACE") end end
toucher("SPACE")
verifie("quête auto-acceptée : AcknowledgeAutoAcceptQuest, pas AcceptQuest", "ack", appels())
JEU.appels = {}
declencher("QUEST_FINISHED") avancer()
_G.QuestGetAutoAccept, _G.AcknowledgeAutoAcceptQuest = nil, nil
JEU.progress.argent = 500
ouvrir("complete", "QUEST_COMPLETE")
toucher("2")
toucher("SPACE")
verifie("quête qui coûte de l'or : GetQuestReward n'est pas appelé", "", appels())
verifie("quête qui coûte de l'or : la fenêtre du jeu reprend la main", 1, QuestFrame:GetAlpha())
verifie("quête qui coûte de l'or : le joueur est prévenu", 1, compte("te coûte de l'or"))
declencher("QUEST_FINISHED") avancer()
JEU.progress.argent = 0

-- (7) Pendant les 0,15 s d'un changement d'étape, l'ancien bandeau n'agit plus.
installer()
demarrer()
ouvrir("gossip", "GOSSIP_SHOW")
JEU.etape = "detail"
declencher("QUEST_DETAIL") -- le jeu est passé à la quête, le bandeau n'a pas encore changé
toucher("1")
cliquer(ligneListe(1))
verifie("changement d'étape : une touche dans les 0,15 s ne fait rien", "", appels())
avancer()
verifie("changement d'étape : le nouveau bandeau est là", "Les loups", DialoguesBandeau.titreQuete._text)
toucher("SPACE")
verifie("changement d'étape : le nouveau bandeau répond", true, DialoguesBandeau.compteur._text:find("^2 /") ~= nil)
declencher("QUEST_FINISHED") avancer()

-- (8) Une touche prise et gardée enfoncée ne se répète pas ; une touche pour le jeu se répète.
installer()
demarrer()
ouvrir("detail", "QUEST_DETAIL")
maintenir("SPACE") maintenir("SPACE") maintenir("SPACE")
verifie("touche maintenue : une seule page tournée", true, DialoguesBandeau.compteur._text:find("^2 /") ~= nil)
verifie("touche maintenue : la répétition reste prise", false, DialoguesBandeau._propage)
relacher("SPACE")
maintenir("SPACE")
verifie("touche relâchée puis appuyée : la page suivante", true, DialoguesBandeau.compteur._text:find("^3 /") ~= nil)
relacher("SPACE")
maintenir("W") DialoguesBandeau._propage = false maintenir("W")
verifie("touche pour le jeu maintenue : elle passe toujours au jeu", true, DialoguesBandeau._propage)
relacher("W")
-- Le bandeau se ferme touche enfoncée : la prochaine ouverture n'est pas bloquée.
maintenir("SPACE")
declencher("QUEST_FINISHED") avancer()
ouvrir("detail", "QUEST_DETAIL")
maintenir("SPACE")
verifie("touche enfoncée pendant une fermeture : pas de blocage ensuite", true, DialoguesBandeau.compteur._text:find("^2 /") ~= nil)
declencher("QUEST_FINISHED") avancer()

-- (9) Fin de combat avec l'échange encore ouvert : la souris et l'échelle restent coupées.
installer()
demarrer()
ouvrir("gossip", "GOSSIP_SHOW")
entrerCombat()
enCombat = false
declencher("PLAYER_REGEN_ENABLED")
verifie("fin de combat, échange ouvert : fenêtre du jeu toujours invisible", 0, GossipFrame:GetAlpha())
verifie("fin de combat, échange ouvert : souris toujours coupée", false, GossipFrame._souris)
verifie("fin de combat, échange ouvert : échelle toujours réduite", 0.001, GossipFrame._scale)
declencher("GOSSIP_CLOSED") avancer()
verifie("échange fini : souris remise", true, GossipFrame._souris)
verifie("échange fini : échelle remise", 1, GossipFrame._scale)
verifie("échange fini : opacité remise", 1, GossipFrame:GetAlpha())

-- ---------------------------------------------------------------------------
-- 2q. Les quatre styles d'affichage
-- ---------------------------------------------------------------------------
do
  local function modelesVisibles(b)
    return (b.modelePNJ and b.modelePNJ._shown and "1" or "0") .. (b.modeleJoueur and b.modeleJoueur._shown and "1" or "0")
  end
  local function toutesStrates(b)
    local liste_ = { b, b.liste, b.bandeHaut, b.modelePNJ, b.modeleJoueur, b.ecrivain, b.bouton, b.boutonDeux, b.caseTouche, b.boutonJeu }
    for _, l in ipairs(b.lignes) do liste_[#liste_ + 1] = l end
    for _, f in ipairs(liste_) do if f._strate ~= "DIALOG" then return false end end
    return true
  end
  local attendusStyles = {
    bandeau = { point = "BOTTOM", liste = "BOTTOMRIGHT", modeles = "00", haut = false, largeur = 1344, cartes = false },
    scene = { point = "BOTTOM", liste = "RIGHT", modeles = "10", haut = false, largeur = 864, cartes = true },
    face = { point = "TOP", liste = "BOTTOM", modeles = "11", haut = false, largeur = 960, cartes = true },
    cinema = { point = "BOTTOM", liste = "RIGHT", modeles = "10", haut = true, largeur = 1920, cartes = true },
  }
  local ORDRE_STYLES = { "bandeau", "scene", "face", "cinema" }
  for _, st in ipairs(ORDRE_STYLES) do
    local att = attendusStyles[st]
    local pre = "style " .. st .. " : "
    installer()
    local clesAvant = cles(GossipFrame) .. "/" .. cles(QuestFrame)
    local ns_ = demarrer(st, false)
    ouvrir("gossip", "GOSSIP_SHOW")
    local b = DialoguesBandeau
    verifie(pre .. "affiché", true, bandeauVisible())
    verifie(pre .. "nom du PNJ", "Garde Mortemine", b.nomPNJ._text)
    verifie(pre .. "texte", "Bienvenue, voyageur.\nQue puis-je faire pour toi ?", b.texte._text)
    verifie(pre .. "place du cadre principal", att.point, b._pt[1])
    verifie(pre .. "largeur du cadre principal", att.largeur, b._w)
    verifie(pre .. "place des réponses", att.liste, DialoguesListe._pt[1])
    verifie(pre .. "modèles 3D visibles (PNJ, joueur)", att.modeles, modelesVisibles(b))
    if att.modeles:sub(1, 1) == "1" then verifie(pre .. "le modèle du PNJ montre npc", "npc", b.modelePNJ._unite) end
    verifie(pre .. "le modèle du joueur", att.modeles:sub(2, 2) == "1" and "player" or nil, b.modeleJoueur._unite)
    verifie(pre .. "bande noire du haut", att.haut, b.bandeHaut._shown)
    verifie(pre .. "tous les cadres sur la strate DIALOG", true, toutesStrates(b))
    verifie(pre .. "les modèles n'ont pas de souris", true, b.modelePNJ._souris == false and b.modeleJoueur._souris == false)
    verifie(pre .. "portrait rond seulement en bandeau", st == "bandeau", b.portrait._shown == true)
    verifie(pre .. "première réponse", "|cffffffffLivraison urgente|r", texteLigne(1))
    verifie(pre .. "quatre réponses, pas cinq", true, ligneListe(4) ~= nil and ligneListe(5) == nil)
    verifie(pre .. "la liste est affichée", true, DialoguesListe._shown)
    verifie(pre .. "couleur du titre de quête", "1,0.82,0.3", table.concat(b.titreQuete._couleur, ","))
    toucher("3")
    verifie(pre .. "la touche 3 prend la quête 20", "gossip.dispo:20", appels())
    JEU.appels = {}
    avancer()
    -- Changer de style pendant le dialogue, sans /reload.
    for _, autre in ipairs(ORDRE_STYLES) do
      ns_.reglages.changer("style", autre)
      local a2 = attendusStyles[autre]
      verifie(pre .. "vers " .. autre .. " : sans erreur", nil, ns_.derniereErreur)
      verifie(pre .. "vers " .. autre .. " : toujours affiché, même texte", true, bandeauVisible() and b.texte._text == "Bienvenue, voyageur.\nQue puis-je faire pour toi ?")
      verifie(pre .. "vers " .. autre .. " : modèles", a2.modeles, modelesVisibles(b))
      verifie(pre .. "vers " .. autre .. " : bande du haut", a2.haut, b.bandeHaut._shown)
      verifie(pre .. "vers " .. autre .. " : cadre principal", a2.largeur .. a2.point, b._w .. b._pt[1])
      verifie(pre .. "vers " .. autre .. " : réponses toujours là", "|cffffffffLivraison urgente|r", texteLigne(1))
    end
    ns_.reglages.changer("style", st)
    declencher("GOSSIP_CLOSED") avancer()
    -- La fin de quête : choix, surbrillance dorée au choix et au survol (cartes seulement pour le survol).
    ouvrir("complete", "QUEST_COMPLETE")
    verifie(pre .. "fin : bouton grisé", "Choisis une récompense", b.bouton._text)
    verifie(pre .. "fin : choix numérotés", "1,2,3", ligneListe(2).numero._text .. "," .. ligneListe(3).numero._text .. "," .. ligneListe(4).numero._text)
    toucher("2")
    verifie(pre .. "fin : la touche 2 choisit", "Terminer la quête", b.bouton._text)
    verifie(pre .. "fin : le choix est encadré d'or", "0.8,0.63,0.3,1", table.concat(ligneListe(3)._bordure, ","))
    verifie(pre .. "fin : l'autre garde la bordure sombre", "0.3,0.25,0.15,1", table.concat(ligneListe(2)._bordure, ","))
    ligneListe(2)._scripts.OnEnter(ligneListe(2))
    verifie(pre .. "fin : au survol, la carte devient dorée (cartes seulement)", att.cartes and "0.8,0.63,0.3,1" or "0.3,0.25,0.15,1", table.concat(ligneListe(2)._bordure, ","))
    ligneListe(2)._scripts.OnLeave(ligneListe(2))
    verifie(pre .. "fin : la carte redevient sombre", "0.3,0.25,0.15,1", table.concat(ligneListe(2)._bordure, ","))
    toucher("SPACE")
    verifie(pre .. "fin : GetQuestReward(2)", "reward:2", appels())
    JEU.appels = {}
    declencher("QUEST_FINISHED") avancer()
    -- Le dialogue d'essai montre le style choisi.
    SlashCmdList.DIALOGUES("test")
    verifie(pre .. "essai : affiché", true, bandeauVisible())
    verifie(pre .. "essai : le même cadre, au même endroit", att.point, b._pt[1])
    if st == "bandeau" then
      verifie(pre .. "essai : portrait du joueur", "player", JEU.portraits[#JEU.portraits])
    else
      verifie(pre .. "essai : le modèle montre le joueur", "player", b.modelePNJ._unite)
    end
    verifie(pre .. "essai : modèles", att.modeles, modelesVisibles(b))
    toucher("ESCAPE")
    verifie(pre .. "essai : Échap ferme", false, bandeauVisible())
    verifie(pre .. "aucune erreur d'affichage", nil, ns_.derniereErreur)
    verifie(pre .. "aucun champ écrit sur les cadres du jeu", clesAvant, cles(GossipFrame) .. "/" .. cles(QuestFrame))
  end

  -- Un style abîmé en base vaut « scène » ; un PNJ qui disparaît cache son modèle.
  installer()
  demarrer("defaut")
  DialoguesDB.style = "zorglub"
  DialoguesDB.machine = false
  ouvrir("gossip", "GOSSIP_SHOW")
  verifie("style abîmé : traité comme la scène (modèle du PNJ, cartes à droite)", "10RIGHT", modelesVisibles(DialoguesBandeau) .. DialoguesListe._pt[1])
  local uniteAvant = UnitExists
  _G.UnitExists = function() return false end
  SlashCmdList.DIALOGUES("style cinema")
  verifie("PNJ disparu : le modèle est caché", "00", modelesVisibles(DialoguesBandeau))
  _G.UnitExists = uniteAvant
  declencher("GOSSIP_CLOSED") avancer()

  -- /dial style et les boutons de style des réglages.
  installer()
  demarrer("defaut")
  DialoguesDB.machine = false
  verifie("/dial style : style de départ", "scene", DialoguesDB.style)
  SlashCmdList.DIALOGUES("style face")
  verifie("/dial style face", "face", DialoguesDB.style)
  SlashCmdList.DIALOGUES("style Cinema")
  verifie("/dial style Cinema (majuscule)", "cinema", DialoguesDB.style)
  SlashCmdList.DIALOGUES("style scène")
  verifie("/dial style scène (accent)", "scene", DialoguesDB.style)
  SlashCmdList.DIALOGUES("style bandeau")
  verifie("/dial style bandeau", "bandeau", DialoguesDB.style)
  imprime = {}
  SlashCmdList.DIALOGUES("style zorglub")
  verifie("/dial style inconnu : le style ne change pas", "bandeau", DialoguesDB.style)
  verifie("/dial style inconnu : message", true, lireImprime():find("style inconnu", 1, true) ~= nil)
  SlashCmdList.DIALOGUES("style face")
  imprime = {}
  SlashCmdList.DIALOGUES("style")
  verifie("/dial style seul : dit le style actuel", true, lireImprime():find("style actuel : face à face", 1, true) ~= nil)
  verifie("/dial style seul : ne change rien", "face", DialoguesDB.style)
  imprime = {}
  SlashCmdList.DIALOGUES("aide")
  verifie("/dial aide : parle de /dial style", true, lireImprime():find("/dial style", 1, true) ~= nil)
  local function boutonNomme(texte) for _, f in ipairs(toutes) do if f._text == texte and f._scripts.OnClick then return f end end end
  for _, v in ipairs({ { "Style : bandeau", "bandeau" }, { "Style : scène", "scene" }, { "Style : face à face", "face" }, { "Style : cinéma", "cinema" } }) do
    local bt = boutonNomme(v[1])
    if bt then bt._scripts.OnClick(bt) end
    verifie("réglages : le bouton " .. v[1], v[2], DialoguesDB.style)
  end
  -- Un dialogue ouvert prend le style tapé tout de suite.
  SlashCmdList.DIALOGUES("style scene")
  ouvrir("gossip", "GOSSIP_SHOW")
  SlashCmdList.DIALOGUES("style cinema")
  verifie("/dial style pendant un dialogue : bande du haut", true, DialoguesBandeau.bandeHaut._shown)
  verifie("/dial style pendant un dialogue : le dialogue reste", true, bandeauVisible())
  declencher("GOSSIP_CLOSED") avancer()
end

-- ---------------------------------------------------------------------------
-- 2r. Le texte lettre par lettre (option « machine »)
-- ---------------------------------------------------------------------------
do
  local function pageCourante(b) return tonumber(b.compteur._text:match("^(%d+) /")) end
  local function pagesTotal(b) return tonumber(b.compteur._text:match("/ (%d+)$")) end
  installer()
  local nm = demarrer("scene", true)
  ouvrir("detail", "QUEST_DETAIL")
  local bm = DialoguesBandeau
  local ecr = bm.ecrivain
  verifie("machine : le texte commence vide", "", bm.texte._text)
  verifie("machine : le cadre qui écrit a son script", "function", type(ecr._scripts.OnUpdate))
  ecr._scripts.OnUpdate(ecr, 0.5)
  verifie("machine : 0,5 s = 30 caractères", 30, nm.longueurVisible(bm.texte._text))
  ecr._scripts.OnUpdate(ecr, 100)
  local pleine = bm.texte._text
  verifie("machine : la page est écrite en entier", true, nm.longueurVisible(pleine) > 100 and pleine:find("^Les loups") ~= nil)
  verifie("machine : l'écriture finie, le script est retiré", nil, ecr._scripts.OnUpdate)
  verifie("machine : l'indicateur de page est là dès le début", true, pagesTotal(bm) ~= nil and pageCourante(bm) == 1)
  -- Pas à pas : jamais un caractère coupé, jamais plus de deux caractères d'un coup.
  declencher("QUEST_FINISHED") avancer()
  ouvrir("detail", "QUEST_DETAIL")
  local ecr2 = bm.ecrivain
  local propre2, pas, dernier, saut = true, 0, 0, 0
  while ecr2._scripts.OnUpdate and pas < 3000 do
    pas = pas + 1
    ecr2._scripts.OnUpdate(ecr2, 1 / 60)
    local t = bm.texte._text
    if not outils.utf8Valide(t) then propre2 = false end
    local v = nm.longueurVisible(t)
    if v - dernier > 2 then saut = saut + 1 end
    dernier = v
  end
  verifie("machine : pas à pas, jamais de caractère coupé", true, propre2)
  verifie("machine : pas à pas, une lettre à la fois", 0, saut)
  verifie("machine : pas à pas, le même texte à la fin", pleine, bm.texte._text)
  verifie("machine : environ 60 caractères par seconde", true, pas >= nm.longueurVisible(pleine) - 3 and pas <= nm.longueurVisible(pleine) + 3)
  -- Espace pendant l'écriture : tout le texte d'abord, un second appui avance.
  declencher("QUEST_FINISHED") avancer()
  ouvrir("detail", "QUEST_DETAIL")
  ecr = bm.ecrivain
  ecr._scripts.OnUpdate(ecr, 0.2)
  verifie("machine : à 0,2 s, 12 caractères", 12, nm.longueurVisible(bm.texte._text))
  toucher("SPACE")
  verifie("machine : Espace affiche d'abord tout le texte", pleine, bm.texte._text)
  verifie("machine : sans changer de page", 1, pageCourante(bm))
  verifie("machine : et sans rien faire au jeu", "", appels())
  toucher("SPACE")
  verifie("machine : le second appui passe à la page 2", 2, pageCourante(bm))
  verifie("machine : la page 2 commence vide", "", bm.texte._text)
  -- Jusqu'à la dernière page, avec son code couleur : toujours équilibré.
  local garde = 0
  while pageCourante(bm) < pagesTotal(bm) and garde < 40 do garde = garde + 1; toucher("SPACE"); toucher("SPACE") end
  verifie("machine : dernière page atteinte", true, pageCourante(bm) == pagesTotal(bm))
  ecr = bm.ecrivain
  local equilibre, secu = true, 0
  while ecr._scripts.OnUpdate and secu < 3000 do
    secu = secu + 1
    ecr._scripts.OnUpdate(ecr, 1 / 60)
    local t = bm.texte._text
    if outils.nbCodes(t, "|c%x%x%x%x%x%x%x%x") ~= outils.nbCodes(t, "|r") or not outils.utf8Valide(t) then equilibre = false end
  end
  verifie("machine : la page de l'objectif garde sa couleur équilibrée", true, equilibre)
  verifie("machine : la page de l'objectif est entière", "|cffffd200Objectif :|r Tuez 4 loups.", bm.texte._text)
  verifie("machine : Accepter à la dernière page", "Accepter", bm.bouton._text)
  declencher("QUEST_FINISHED") avancer()
  -- Couper l'option en cours d'écriture : tout s'affiche, et la remettre ne recommence pas.
  ouvrir("detail", "QUEST_DETAIL")
  ecr = bm.ecrivain
  ecr._scripts.OnUpdate(ecr, 0.2)
  nm.reglages.changer("machine", false)
  verifie("machine coupée en route : tout le texte", pleine, bm.texte._text)
  verifie("machine coupée en route : plus d'écriture", nil, ecr._scripts.OnUpdate)
  nm.reglages.changer("machine", true)
  verifie("machine remise : la page finie ne recommence pas", pleine, bm.texte._text)
  declencher("QUEST_FINISHED") avancer()
  -- Bouton grisé : Espace finit d'écrire sans rien faire d'autre. Un nouveau tracé ne relance pas l'écriture.
  ouvrir("complete", "QUEST_COMPLETE")
  ecr = bm.ecrivain
  ecr._scripts.OnUpdate(ecr, 0.1)
  verifie("machine : fin de quête, texte en cours d'écriture", 6, nm.longueurVisible(bm.texte._text))
  toucher("SPACE")
  verifie("machine : Espace (bouton grisé) finit le texte", "Merci, voyageur. Voici ta récompense.", bm.texte._text)
  verifie("machine : Espace (bouton grisé) ne termine pas la quête", "", appels())
  toucher("2")
  verifie("machine : choisir une récompense ne réécrit pas le texte", "Merci, voyageur. Voici ta récompense.", bm.texte._text)
  verifie("machine : ni ne relance l'écriture", nil, ecr._scripts.OnUpdate)
  declencher("QUEST_FINISHED") avancer()
  -- Le dialogue d'essai écrit aussi lettre par lettre ; Échap ferme en pleine écriture.
  SlashCmdList.DIALOGUES("test")
  verifie("machine : essai, le texte commence vide", "", bm.texte._text)
  verifie("machine : essai, le modèle montre le joueur", "player", bm.modelePNJ._unite)
  toucher("ESCAPE")
  verifie("machine : Échap ferme en pleine écriture", false, bandeauVisible())
  -- Le style bandeau écrit lettre par lettre sans changer la hauteur du bandeau (mesurée sur le texte entier).
  installer()
  demarrer("bandeau", false)
  ouvrir("detail", "QUEST_DETAIL")
  local hauteurEntier = DialoguesBandeau._h
  installer()
  demarrer("bandeau", true)
  ouvrir("detail", "QUEST_DETAIL")
  bm = DialoguesBandeau
  verifie("machine, bandeau : texte vide au départ", "", bm.texte._text)
  verifie("machine, bandeau : hauteur réglée sur le texte entier", hauteurEntier, bm._h)
  bm.ecrivain._scripts.OnUpdate(bm.ecrivain, 100)
  verifie("machine, bandeau : texte entier à la fin", true, bm.texte._text:find("^Les loups") ~= nil)
  declencher("QUEST_FINISHED") avancer()
  -- Un plantage dans l'écriture : la fenêtre du jeu reprend la main.
  installer()
  nm = demarrer("scene", true)
  ouvrir("gossip", "GOSSIP_SHOW")
  bm = DialoguesBandeau
  nm.morceauTexte = function() error("panne d'écriture simulée") end
  local okE2 = pcall(function() bm.ecrivain._scripts.OnUpdate(bm.ecrivain, 0.5) end)
  verifie("écriture en panne : aucune erreur ne sort", true, okE2)
  verifie("écriture en panne : la fenêtre du jeu reprend la main", 1, GossipFrame:GetAlpha())
  declencher("GOSSIP_CLOSED") avancer()
end

print = printOrigine
io.write(string.format("%d vérifications OK\n", nbOK))
if ok then io.write("Tout est bon.\n") end
os.exit(ok and 0 or 1)
