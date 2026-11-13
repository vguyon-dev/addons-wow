-- ============================================================================
-- Banc d'essai : outil de développement, jamais publié (il vit dans outils/banc, hors de la racine).
-- Il exécute Banc.script (défini dans Script.lua) une fois par identifiant Banc.id, note tout ce
-- que le script écrit (Banc.note) et tout ce qui passe dans la discussion, garde le résultat dans
-- BancEssaiDB, puis recharge l'interface pour que le jeu écrive le fichier sur le disque.
-- Boucle de travail : écrire Script.lua avec un nouvel identifiant, taper /reload, lire
-- WTF/Account/<compte>/SavedVariables/BancEssai.lua. Voir outils/banc/LISEZMOI.md.
-- ============================================================================
Banc = {}
local lignes, ecoute, fini = {}, false, false

local function texte(...)
  local t = {}
  for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
  return table.concat(t, " ")
end
local function propre(s)
  return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

function Banc.note(...) lignes[#lignes + 1] = propre(texte(...)) end

-- Le contenu d'une table, sur un niveau (deux avec profondeur = 2).
function Banc.voir(nom, t, profondeur)
  if type(t) ~= "table" then return Banc.note(nom, "=", t) end
  local cles = {}
  for k in pairs(t) do cles[#cles + 1] = k end
  table.sort(cles, function(a, b) return tostring(a) < tostring(b) end)
  for _, k in ipairs(cles) do
    local v = t[k]
    if type(v) == "table" and (profondeur or 1) > 1 then
      Banc.voir(nom .. "." .. tostring(k), v, (profondeur or 1) - 1)
    else
      Banc.note(nom .. "." .. tostring(k), "=", v)
    end
  end
end

-- Lance une commande d'addon comme si on la tapait (« /qd etat »). Pas les commandes du jeu.
function Banc.commande(ligne)
  local cmd, reste = tostring(ligne):match("^(/%S+)%s*(.*)$")
  if not cmd then return Banc.note("commande illisible :", ligne) end
  cmd = cmd:lower()
  for cle, f in pairs(SlashCmdList) do
    local i = 1
    while _G["SLASH_" .. cle .. i] do
      if _G["SLASH_" .. cle .. i]:lower() == cmd then
        local ok, e = pcall(f, reste or "")
        if not ok then Banc.note("ERREUR dans", ligne, ":", e) end
        return ok
      end
      i = i + 1
    end
  end
  Banc.note("commande inconnue des addons :", cmd)
end

-- Plus tard, sans casser le banc si ça plante.
function Banc.apres(delai, f)
  C_Timer.After(delai, function()
    local ok, e = pcall(f)
    if not ok then Banc.note("ERREUR (minuteur) :", e) end
  end)
end

-- Fin de l'essai : garde le résultat, puis recharge pour l'écrire sur le disque.
function Banc.fin(sansRecharger)
  if fini then return end
  fini, ecoute = true, false
  BancEssaiDB = { id = Banc.id, quand = date("%Y-%m-%d %H:%M:%S"), interface = select(4, GetBuildInfo()),
    joueur = UnitName("player"), lignes = lignes }
  if sansRecharger or Banc.sansRecharger then
    print("|cff66ccffBanc d'essai|r : essai « " .. tostring(Banc.id) .. " » fini, " .. #lignes .. " lignes. /reload pour l'écrire.")
  else
    C_Timer.After(0.5, function() (C_UI and C_UI.Reload or ReloadUI)() end)
  end
end

local cadre = CreateFrame("Frame")
cadre:RegisterEvent("PLAYER_ENTERING_WORLD")
cadre:SetScript("OnEvent", function(self)
  self:UnregisterAllEvents()
  if type(Banc.script) ~= "function" or not Banc.id then return end
  if type(BancEssaiDB) == "table" and BancEssaiDB.id == Banc.id then
    print("|cff66ccffBanc d'essai|r : essai « " .. tostring(Banc.id) .. " » déjà fait (" .. #(BancEssaiDB.lignes or {}) .. " lignes).")
    return
  end
  -- Tout ce qui s'écrit dans la discussion pendant l'essai est noté aussi.
  if DEFAULT_CHAT_FRAME and hooksecurefunc then
    hooksecurefunc(DEFAULT_CHAT_FRAME, "AddMessage", function(_, message)
      if ecoute then lignes[#lignes + 1] = "chat> " .. propre(message) end
    end)
  end
  C_Timer.After(Banc.depart or 2, function()
    ecoute = true
    local ok, e = xpcall(Banc.script, function(m) return tostring(m) .. "\n" .. (debugstack and debugstack(2) or "") end)
    if not ok then Banc.note("ERREUR du script :", e) end
    if Banc.attente then
      -- Le script finit lui-même (Banc.fin) ; garde-fou si un minuteur ne revient jamais.
      C_Timer.After(Banc.attente, function()
        if not fini then Banc.note("(fin forcée après " .. Banc.attente .. " s)") Banc.fin() end
      end)
    else
      Banc.fin()
    end
  end)
end)

SLASH_BANCESSAI1 = "/banc"
SlashCmdList.BANCESSAI = function()
  local d = BancEssaiDB
  print("|cff66ccffBanc d'essai|r : dernier essai « " .. tostring(d and d.id) .. " », " .. #((d and d.lignes) or {}) .. " lignes.")
  for _, l in ipairs((d and d.lignes) or {}) do print("  " .. l) end
end
