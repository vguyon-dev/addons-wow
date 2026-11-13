# ============================================================================
# banc.ps1 : le pilote du banc d'essai. Une commande = un essai complet en jeu.
#
#   pwsh outils/banc/banc.ps1 -Script essai.lua
#   pwsh outils/banc/banc.ps1 -Lua 'Banc.note(GetCVar("SoftTargetInteract"))'
#   pwsh outils/banc/banc.ps1 -Lua 'Banc.commande("/metiers peche")' -Touches 'F:0.2; attendre:10; F:0.2'
#
# Ce qu'il fait : écrit BancEssai/Script.lua, met la fenêtre du jeu devant, tape /reload, attend que le
# script tourne (en jouant les touches demandées), tape /reload une seconde fois pour que le jeu écrive le
# résultat, puis affiche les lignes notées et les nouvelles erreurs de BugGrabber.
#
# Garde-fou : avant chaque frappe, il vérifie que la fenêtre de devant est bien celle du jeu. Sinon il
# s'arrête sans rien taper (jamais une touche dans une autre application).
# Outil de développement : il envoie des touches au jeu, à réserver à de courts essais de nos addons.
# ============================================================================
param(
  [string]$Script,                 # un fichier .lua : le corps de Banc.script, ou un Script.lua complet
  [string]$Lua,                    # ou le corps de Banc.script, en ligne
  [string]$Touches = "",           # actions jouées pendant l'essai, séparées par « ; » (voir LISEZMOI.md)
  [double]$Duree = -1,             # secondes laissées au script (défaut : Banc.attente + 3, sinon 4)
  [double]$Chargement = 12,        # secondes pour que le jeu recharge son interface
  [string]$Jeu = "_forever_",      # _forever_ ou _retail_
  [string]$Racine = "D:\Program Files (x86)\Battle.net\World of Warcraft",
  [switch]$Verifier,               # ne touche pas au jeu : dit seulement ce qui serait fait
  [switch]$Relire                  # ne touche pas au jeu : réaffiche le résultat du dernier essai
)
$ErrorActionPreference = "Stop"

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class BancFenetre {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint type);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
  [StructLayout(LayoutKind.Explicit)] public struct INPUT {
    [FieldOffset(0)] public uint type;
    [FieldOffset(8)] public KEYBDINPUT ki;
    [FieldOffset(8)] public long remplissage1;
    [FieldOffset(16)] public long remplissage2;
    [FieldOffset(24)] public long remplissage3;
    [FieldOffset(32)] public long remplissage4; // la structure INPUT fait 40 octets en 64 bits, sinon SendInput refuse tout
  }
  [DllImport("user32.dll", SetLastError = true)] public static extern uint SendInput(uint n, INPUT[] entrees, int taille);
  static void Envoyer(ushort vk, ushort scan, uint drapeaux) {
    INPUT[] e = new INPUT[1];
    e[0].type = 1;
    e[0].ki.wVk = vk; e[0].ki.wScan = scan; e[0].ki.dwFlags = drapeaux;
    SendInput(1, e, Marshal.SizeOf(typeof(INPUT)));
  }
  public static void Touche(ushort vk, int appuiMs) {
    ushort scan = (ushort)MapVirtualKey(vk, 0);
    Envoyer(vk, scan, 0);
    System.Threading.Thread.Sleep(appuiMs);
    Envoyer(vk, scan, 2);
  }
  public static void Caractere(char c) {
    Envoyer(0, (ushort)c, 4);
    Envoyer(0, (ushort)c, 4 | 2);
  }
  public static void Devant(IntPtr h) {
    if (IsIconic(h)) ShowWindow(h, 9);
    // Windows refuse de changer de fenêtre sans frappe récente : un appui sur Alt le permet.
    keybd_event(0x12, 0, 0, UIntPtr.Zero);
    SetForegroundWindow(h);
    keybd_event(0x12, 0, 2, UIntPtr.Zero);
  }
}
"@

# ----- les touches que l'on sait nommer
$CODES = @{ "ENTREE" = 0x0D; "ENTER" = 0x0D; "ECHAP" = 0x1B; "ESC" = 0x1B; "ESPACE" = 0x20; "TAB" = 0x09; "GAUCHE" = 0x25; "HAUT" = 0x26; "DROITE" = 0x27; "BAS" = 0x28 }
foreach ($c in 65..90) { $CODES[[string][char]$c] = $c }
foreach ($c in 48..57) { $CODES[[string][char]$c] = $c }
foreach ($n in 1..12) { $CODES["F$n"] = 0x6F + $n }

# Lit « F:0.2; attendre:10; cmd:/metiers peche » : une liste d'actions, ou une erreur claire.
function Lire-Touches([string]$texte) {
  $actions = @()
  foreach ($morceau in ($texte -split ";")) {
    $m = $morceau.Trim()
    if (-not $m) { continue }
    $i = $m.IndexOf(":")
    $nom = if ($i -ge 0) { $m.Substring(0, $i).Trim() } else { $m }
    $reste = if ($i -ge 0) { $m.Substring($i + 1).Trim() } else { "" }
    $cle = $nom.ToUpperInvariant()
    if ($cle -eq "ATTENDRE") {
      $actions += @{ genre = "attendre"; secondes = [double]::Parse($reste, [Globalization.CultureInfo]::InvariantCulture) }
    } elseif ($cle -eq "CMD") {
      if (-not $reste.StartsWith("/")) { throw "action « $m » : une commande commence par /" }
      $actions += @{ genre = "commande"; texte = $reste }
    } elseif ($CODES.ContainsKey($cle)) {
      $appui = if ($reste) { [double]::Parse($reste, [Globalization.CultureInfo]::InvariantCulture) } else { 0.2 }
      $actions += @{ genre = "touche"; nom = $cle; vk = $CODES[$cle]; appui = $appui }
    } else {
      throw "action inconnue : « $m ». Connues : une touche (F, 1, F5, ESPACE, ENTREE, ECHAP, TAB) avec sa durée, attendre:secondes, cmd:/commande."
    }
  }
  return ,$actions
}

# Fabrique le contenu de Script.lua et son identifiant.
function Faire-Script([string]$corps, [string]$id) {
  if ($corps -match "(?m)^\s*function\s+Banc\.script") {
    # Un Script.lua complet : on force seulement un identifiant neuf.
    $sans = [regex]::Replace($corps, "(?m)^\s*Banc\.id\s*=.*$", "")
    return "Banc.id = `"$id`"`n$sans"
  }
  return "Banc.id = `"$id`"`nfunction Banc.script()`n$corps`nend`n"
}

# Les lignes notées par le banc, tirées du fichier que le jeu écrit.
function Lire-Resultat([string]$chemin) {
  $r = @{ id = $null; lignes = @() }
  if (-not (Test-Path -LiteralPath $chemin)) { return $r }
  $dansLignes = $false
  foreach ($l in [IO.File]::ReadAllLines($chemin, [Text.Encoding]::UTF8)) {
    if ($l -match '^\["lignes"\] = \{') { $dansLignes = $true; continue }
    if ($dansLignes) {
      if ($l -match '^\},?$') { $dansLignes = $false; continue }
      if ($l -match '^"(.*)",?\s*(--.*)?$') { $r.lignes += ($Matches[1] -replace '\\"', '"' -replace '\\\\', '\' -replace '\\n', "`n") }
    } elseif ($l -match '^\["id"\] = "(.*)",?$') { $r.id = $Matches[1] }
  }
  return $r
}

function Compter-Erreurs([string]$chemin) {
  if (-not (Test-Path -LiteralPath $chemin)) { return @() }
  return @([IO.File]::ReadAllLines($chemin, [Text.Encoding]::UTF8) | Where-Object { $_ -match '^\["message"\] = ' })
}

# ----- préparation
if ($Relire) {
  $c = Get-ChildItem -LiteralPath (Join-Path $Racine "$Jeu\WTF\Account") -Directory | Where-Object { $_.Name -ne "SavedVariables" } | Select-Object -First 1
  $r = Lire-Resultat (Join-Path $c.FullName "SavedVariables\BancEssai.lua")
  Write-Output "=== $($r.id) : $($r.lignes.Count) lignes ==="
  $r.lignes | ForEach-Object { Write-Output $_ }
  return
}
if (-not $Script -and -not $Lua) { throw "donne -Script fichier.lua ou -Lua 'code'." }
$corps = if ($Script) { [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Script), [Text.Encoding]::UTF8) } else { $Lua }
$id = "essai-" + (Get-Date -Format "yyyyMMdd-HHmmss")
$contenu = Faire-Script $corps $id
$actions = Lire-Touches $Touches
if ($Duree -lt 0) {
  $Duree = if ($contenu -match "Banc\.attente\s*=\s*([0-9.]+)") { [double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture) + 3 } else { 4 }
}
$dureeActions = 0.0
foreach ($a in $actions) {
  if ($a.genre -eq "attendre") { $dureeActions += $a.secondes } elseif ($a.genre -eq "touche") { $dureeActions += $a.appui + 0.2 } else { $dureeActions += 0.8 }
}
$cible = Join-Path $PSScriptRoot "BancEssai\Script.lua"
$compte = Get-ChildItem -LiteralPath (Join-Path $Racine "$Jeu\WTF\Account") -Directory -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -ne "SavedVariables" } | Select-Object -First 1
$sv = if ($compte) { Join-Path $compte.FullName "SavedVariables" } else { $null }
$fichierBanc = if ($sv) { Join-Path $sv "BancEssai.lua" } else { $null }
$fichierErreurs = if ($sv) { Join-Path $sv "!BugGrabber.lua" } else { $null }

if ($Verifier) {
  Write-Output "identifiant : $id"
  Write-Output "script ($($contenu.Length) caractères) vers $cible"
  Write-Output "résultat lu dans : $fichierBanc"
  Write-Output ("actions : " + (($actions | ForEach-Object { if ($_.genre -eq "touche") { "$($_.nom) $($_.appui) s" } elseif ($_.genre -eq "attendre") { "attendre $($_.secondes) s" } else { "taper $($_.texte)" } }) -join ", "))
  Write-Output "durée prévue : $([math]::Round($Chargement * 2 + [math]::Max($Duree, $dureeActions) + 4)) s"
  return
}

$jeuProc = Get-Process -ErrorAction SilentlyContinue | Where-Object {
  $_.MainWindowHandle -ne [IntPtr]::Zero -and $_.Path -and $_.Path -like "*World of Warcraft\$Jeu\*"
} | Select-Object -First 1
if (-not $jeuProc) { throw "le jeu ($Jeu) n'est pas lancé : rien n'a été tapé." }
if (-not $fichierBanc) { throw "dossier WTF\Account introuvable sous $Racine\$Jeu." }
$fenetre = $jeuProc.MainWindowHandle

function Exiger-Jeu {
  if ([BancFenetre]::GetForegroundWindow() -ne $fenetre) {
    [BancFenetre]::Devant($fenetre)
    Start-Sleep -Milliseconds 400
  }
  if ([BancFenetre]::GetForegroundWindow() -ne $fenetre) { throw "la fenêtre du jeu n'est pas devant : arrêt, rien n'est tapé ailleurs." }
}
function Appuyer([int]$vk, [double]$secondes) { Exiger-Jeu; [BancFenetre]::Touche([uint16]$vk, [int]($secondes * 1000)) }
function Taper([string]$texte) {
  Appuyer 0x0D 0.08
  Start-Sleep -Milliseconds 250
  foreach ($c in $texte.ToCharArray()) { Exiger-Jeu; [BancFenetre]::Caractere($c); Start-Sleep -Milliseconds 8 }
  Start-Sleep -Milliseconds 150
  Appuyer 0x0D 0.08
}
function Attendre-Ecriture([string]$chemin, $avant, [double]$delai) {
  $fin = (Get-Date).AddSeconds($delai)
  while ((Get-Date) -lt $fin) {
    if (Test-Path -LiteralPath $chemin) {
      $t = (Get-Item -LiteralPath $chemin).LastWriteTimeUtc
      if ($null -eq $avant -or $t -gt $avant) { return $true }
    }
    Start-Sleep -Milliseconds 250
  }
  return $false
}

# ----- l'essai
$erreursAvant = Compter-Erreurs $fichierErreurs
# Le top : l'heure où les touches commencent. Le banc fait partir le script à cette même seconde.
$top = [DateTimeOffset]::Now.ToUnixTimeSeconds() + [int][math]::Ceiling($Chargement) + 2
$contenu = "Banc.top = $top`n" + $contenu
[IO.File]::WriteAllText($cible, $contenu, (New-Object Text.UTF8Encoding $false))
$debut = Get-Date

$avant = if (Test-Path -LiteralPath $fichierErreurs) { (Get-Item -LiteralPath $fichierErreurs).LastWriteTimeUtc } else { $null }
Taper "/reload"
if (-not (Attendre-Ecriture $fichierErreurs $avant 20)) { throw "le jeu n'a pas rechargé (la commande /reload n'est pas partie)." }
$attente = $top - [DateTimeOffset]::Now.ToUnixTimeMilliseconds() / 1000.0
if ($attente -gt 0) { Start-Sleep -Milliseconds ([int]($attente * 1000)) }

$chrono = [Diagnostics.Stopwatch]::StartNew()
foreach ($a in $actions) {
  if ($a.genre -eq "attendre") { Start-Sleep -Milliseconds ([int]($a.secondes * 1000)) }
  elseif ($a.genre -eq "touche") { Appuyer $a.vk $a.appui; Start-Sleep -Milliseconds 200 }
  else { Taper $a.texte; Start-Sleep -Milliseconds 400 }
}
$reste = $Duree - $chrono.Elapsed.TotalSeconds
if ($reste -gt 0) { Start-Sleep -Milliseconds ([int]($reste * 1000)) }

$avant = if (Test-Path -LiteralPath $fichierBanc) { (Get-Item -LiteralPath $fichierBanc).LastWriteTimeUtc } else { $null }
Taper "/reload"
if (-not (Attendre-Ecriture $fichierBanc $avant 20)) { throw "le résultat n'a pas été écrit (second /reload pas parti, ou addon BancEssai pas chargé)." }
Start-Sleep -Milliseconds 500

# ----- le compte rendu
$r = Lire-Resultat $fichierBanc
if ($r.id -ne $id) {
  Write-Output "ATTENTION : le fichier porte l'essai « $($r.id) », pas « $id » : le script n'a pas tourné (erreur de syntaxe Lua, ou durée trop courte)."
}
Write-Output "=== $id : $($r.lignes.Count) lignes, $([math]::Round(((Get-Date) - $debut).TotalSeconds)) s ==="
$r.lignes | ForEach-Object { Write-Output $_ }
$erreursApres = Compter-Erreurs $fichierErreurs
$nouvelles = @($erreursApres | Where-Object { $erreursAvant -notcontains $_ })
if ($nouvelles.Count -gt 0) {
  Write-Output "=== $($nouvelles.Count) nouvelle(s) erreur(s) dans BugGrabber ==="
  $nouvelles | ForEach-Object { Write-Output ($_.Substring(0, [math]::Min(400, $_.Length))) }
} else {
  Write-Output "=== aucune nouvelle erreur dans BugGrabber ==="
}
