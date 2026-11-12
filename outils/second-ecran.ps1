# Second écran : étire la fenêtre de World of Warcraft sur deux écrans côte à côte, sans bordure.
# L'addon « Fenêtres déplaçables » garde ensuite le monde et l'interface sur un seul écran ; l'autre
# reste libre pour les fenêtres.
#
# Le plus simple : laisser tourner ce programme en arrière-plan (mode -Surveiller), puis tout faire
# depuis le jeu, dans les réglages de « Fenêtres déplaçables » :
#   « Passer au second écran »   : le jeu passe en mode fenêtré deux fois plus large ; ce programme le
#                                  voit et étale aussitôt la fenêtre sur les deux écrans, sans bordure ;
#   « Revenir à un seul écran »  : le jeu revient en plein écran fenêtré ; ce programme ne fait rien.
#
#   pwsh -File outils\second-ecran.ps1 -Surveiller              (tourne en fond, sans fenêtre utile)
#   pwsh -File outils\second-ecran.ps1                          (une seule fois : étire maintenant)
#   pwsh -File outils\second-ecran.ps1 -Cote droite             (l'autre écran à droite du principal)
#   pwsh -File outils\second-ecran.ps1 -Retirer                 (ramène la fenêtre sur l'écran principal)
#
# Le programme ne touche qu'à la place et à la bordure de la fenêtre du jeu, jamais au jeu lui-même.
param(
  [ValidateSet("gauche", "droite")] [string] $Cote = "gauche",
  [switch] $Retirer,
  [switch] $Surveiller
)

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

function Get-Zone([string] $cote) {
  $ecrans = [System.Windows.Forms.Screen]::AllScreens
  $b = ($ecrans | Where-Object { $_.Primary } | Select-Object -First 1).Bounds
  if ($cote -eq "gauche") {
    $voisin = $ecrans | Where-Object { $_.Bounds.Right -eq $b.Left -and $_.Bounds.Top -eq $b.Top -and $_.Bounds.Height -eq $b.Height } | Select-Object -First 1
  } else {
    $voisin = $ecrans | Where-Object { $_.Bounds.Left -eq $b.Right -and $_.Bounds.Top -eq $b.Top -and $_.Bounds.Height -eq $b.Height } | Select-Object -First 1
  }
  if (-not $voisin) { return $null }
  return @{ X = [Math]::Min($b.Left, $voisin.Bounds.Left); Y = $b.Top; L = $b.Width + $voisin.Bounds.Width; H = $b.Height }
}

function Set-Etiree([IntPtr] $h, [string] $cote) {
  $z = Get-Zone $cote
  if (-not $z) { Write-Host "Aucun écran de même hauteur collé à $cote de l'écran principal."; return $false }
  [FenetreJeu]::SetWindowLong($h, -16, $SANS_BORDURE) | Out-Null
  [FenetreJeu]::SetWindowPos($h, [IntPtr]::Zero, $z.X, $z.Y, $z.L, $z.H, $OPTIONS) | Out-Null
  Write-Host ("Fenêtre du jeu étirée sur deux écrans : {0} x {1} à partir de x = {2}." -f $z.L, $z.H, $z.X)
  return $true
}

if ($Surveiller) {
  # Une seule copie à la fois.
  $verrou = New-Object System.Threading.Mutex($false, "Global\SecondEcranWow")
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
