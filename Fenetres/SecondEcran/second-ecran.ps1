# Second écran : étire la fenêtre de World of Warcraft sur deux écrans côte à côte, sans bordure.
# L'addon « Fenêtres déplaçables » garde ensuite le monde et l'interface sur un seul écran ; l'autre
# reste libre pour les fenêtres. Un addon ne peut rien lancer hors du jeu : ce petit programme le fait.
#
# Pour un joueur : double-clique UNE fois sur « Installer.cmd » (dans ce dossier). Le programme tourne
# alors caché, tout de suite et à chaque ouverture de Windows. Ensuite tout se fait dans le jeu
# (/fen, boutons « Passer au second écran » et « Revenir à un seul écran »). « Retirer.cmd » enlève tout.
#
# Ce qu'il fait, en fond : toutes les 2 secondes, si la fenêtre du jeu a une barre de titre (le jeu
# vient de passer en mode fenêtré par le bouton de l'addon), il l'étale sans bordure sur l'écran
# principal et l'écran voisin de même hauteur. En plein écran fenêtré (un seul écran), il ne fait rien.
# Il ne touche qu'à la place et à la bordure de la fenêtre du jeu, jamais au jeu lui-même.
#
# À la main :
#   second-ecran.ps1                  étire la fenêtre une fois, maintenant
#   second-ecran.ps1 -Cote droite     l'autre écran est à droite du principal (auto : le voisin trouvé)
#   second-ecran.ps1 -Retirer         ramène la fenêtre sur l'écran principal
#   second-ecran.ps1 -Surveiller      tourne en fond (ce que lance l'installation)
#   second-ecran.ps1 -Installer       lance la surveillance maintenant et à chaque ouverture de Windows
#   second-ecran.ps1 -Desinstaller    arrête la surveillance et ne la relance plus
param(
  [ValidateSet("auto", "gauche", "droite")] [string] $Cote = "auto",
  [switch] $Retirer,
  [switch] $Surveiller,
  [switch] $Installer,
  [switch] $Desinstaller
)

$ici = $PSCommandPath
$raccourci = Join-Path ([Environment]::GetFolderPath("Startup")) "Second ecran WoW.lnk"

# Les autres copies de la surveillance (lancées par ce même fichier).
function Get-Surveillances {
  Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like "*second-ecran.ps1*-Surveiller*" }
}

if ($Desinstaller) {
  if (Test-Path $raccourci) { Remove-Item $raccourci -Force }
  Get-Surveillances | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Write-Host "Second écran retiré : la surveillance est arrêtée et ne démarre plus avec Windows."
  exit 0
}

if ($Installer) {
  $arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ici`" -Surveiller -Cote $Cote"
  $shell = New-Object -ComObject WScript.Shell
  $lien = $shell.CreateShortcut($raccourci)
  $lien.TargetPath = "powershell.exe"
  $lien.Arguments = $arguments
  $lien.WindowStyle = 7
  $lien.Description = "Second écran pour World of Warcraft (addon Fenêtres déplaçables)"
  $lien.Save()
  if (-not (Get-Surveillances)) {
    Start-Process powershell.exe -ArgumentList $arguments -WindowStyle Hidden
  }
  Write-Host "Second écran installé : la surveillance tourne et démarrera avec Windows."
  Write-Host "Dans le jeu : /fen, puis « Passer au second écran ». Pour tout enlever : Retirer.cmd."
  exit 0
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices;
public class FenetreJeu {
  [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int i, int v);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
}
"@

# Style « fenêtre sans bordure » : WS_POPUP | WS_VISIBLE | WS_CLIPSIBLINGS | WS_CLIPCHILDREN.
$SANS_BORDURE = [int]0x96000000
# WS_CAPTION : la fenêtre a une barre de titre (le jeu est en mode « fenêtré » classique).
$WS_CAPTION = 0x00C00000
# SWP_NOZORDER | SWP_FRAMECHANGED | SWP_SHOWWINDOW
$OPTIONS = 0x0004 -bor 0x0020 -bor 0x0040

function Get-FenetreJeu {
  $jeu = Get-Process Wow -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  if ($jeu) { return $jeu.MainWindowHandle }
  return $null
}

# L'écran voisin de l'écran principal, de même hauteur, collé à gauche ou à droite (auto : gauche d'abord).
function Get-Zone([string] $cote) {
  $ecrans = [System.Windows.Forms.Screen]::AllScreens
  $b = ($ecrans | Where-Object { $_.Primary } | Select-Object -First 1).Bounds
  $gauche = $ecrans | Where-Object { $_.Bounds.Right -eq $b.Left -and $_.Bounds.Top -eq $b.Top -and $_.Bounds.Height -eq $b.Height } | Select-Object -First 1
  $droite = $ecrans | Where-Object { $_.Bounds.Left -eq $b.Right -and $_.Bounds.Top -eq $b.Top -and $_.Bounds.Height -eq $b.Height } | Select-Object -First 1
  $voisin = switch ($cote) { "gauche" { $gauche } "droite" { $droite } default { if ($gauche) { $gauche } else { $droite } } }
  if (-not $voisin) { return $null }
  return @{ X = [Math]::Min($b.Left, $voisin.Bounds.Left); Y = $b.Top; L = $b.Width + $voisin.Bounds.Width; H = $b.Height }
}

function Set-Etiree([IntPtr] $h, [string] $cote) {
  $z = Get-Zone $cote
  if (-not $z) { Write-Host "Aucun écran de même hauteur collé à l'écran principal ($cote)."; return $false }
  [FenetreJeu]::SetWindowLong($h, -16, $SANS_BORDURE) | Out-Null
  [FenetreJeu]::SetWindowPos($h, [IntPtr]::Zero, $z.X, $z.Y, $z.L, $z.H, $OPTIONS) | Out-Null
  Write-Host ("Fenêtre du jeu étirée sur deux écrans : {0} x {1} à partir de x = {2}." -f $z.L, $z.H, $z.X)
  return $true
}

if ($Surveiller) {
  # Une seule copie à la fois.
  $verrou = New-Object System.Threading.Mutex($false, "Local\SecondEcranWow")
  if (-not $verrou.WaitOne(0)) { Write-Host "La surveillance tourne déjà."; exit 0 }
  Write-Host "Surveillance du second écran : quand le jeu passe en mode fenêtré, sa fenêtre est étalée sur deux écrans."
  while ($true) {
    $h = Get-FenetreJeu
    if ($h -and -not [FenetreJeu]::IsIconic($h)) {
      $style = [FenetreJeu]::GetWindowLong($h, -16)
      # Une barre de titre : le jeu vient de passer en mode fenêtré (bouton « Passer au second écran »).
      if (($style -band $WS_CAPTION) -eq $WS_CAPTION) { Set-Etiree $h $Cote | Out-Null }
    }
    Start-Sleep -Seconds 2
  }
}

$h = Get-FenetreJeu
if (-not $h) { Write-Host "World of Warcraft n'est pas lancé (aucune fenêtre Wow trouvée)."; exit 1 }

if ($Retirer) {
  $b = ([System.Windows.Forms.Screen]::AllScreens | Where-Object { $_.Primary } | Select-Object -First 1).Bounds
  [FenetreJeu]::SetWindowLong($h, -16, $SANS_BORDURE) | Out-Null
  [FenetreJeu]::SetWindowPos($h, [IntPtr]::Zero, $b.X, $b.Y, $b.Width, $b.Height, $OPTIONS) | Out-Null
  Write-Host ("Fenêtre du jeu ramenée sur l'écran principal ({0} x {1})." -f $b.Width, $b.Height)
  exit 0
}

if (-not (Set-Etiree $h $Cote)) { exit 1 }
