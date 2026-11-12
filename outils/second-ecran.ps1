# Second écran : étire la fenêtre de World of Warcraft sur deux écrans côte à côte, sans bordure.
# L'addon « Fenêtres déplaçables » (option « Le jeu sur un écran, les fenêtres sur l'autre ») garde
# ensuite le monde et l'interface sur un seul écran ; l'autre reste libre pour les fenêtres.
#
# À faire une seule fois dans le jeu (le réglage est gardé) :
#   /console gxMaximize 0
#   /console gxWindowedResolution 3840x1080      (la largeur des deux écrans réunis, ici 2 x 1920)
#   /console gxRestart
#
# Puis, à chaque lancement du jeu :
#   pwsh -File outils\second-ecran.ps1                 (le jeu à droite, l'autre écran à sa gauche)
#   pwsh -File outils\second-ecran.ps1 -Cote droite    (l'autre écran à droite de l'écran principal)
#   pwsh -File outils\second-ecran.ps1 -Retirer        (la fenêtre revient sur l'écran principal seul)
#
# Pour revenir au plein écran habituel : -Retirer, puis dans le jeu /console gxMaximize 1 et /console gxRestart.
param(
  [ValidateSet("gauche", "droite")] [string] $Cote = "gauche",
  [switch] $Retirer
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices;
public class FenetreJeu {
  [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int i, int v);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
}
"@

$jeu = Get-Process Wow -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $jeu) { Write-Host "World of Warcraft n'est pas lancé (aucune fenêtre Wow trouvée)."; exit 1 }
$h = $jeu.MainWindowHandle

$ecrans = [System.Windows.Forms.Screen]::AllScreens
$principal = $ecrans | Where-Object { $_.Primary } | Select-Object -First 1
$b = $principal.Bounds

# Style « fenêtre sans bordure » : WS_POPUP | WS_VISIBLE | WS_CLIPSIBLINGS | WS_CLIPCHILDREN.
$SANS_BORDURE = [int]0x96000000
# SWP_NOZORDER | SWP_FRAMECHANGED | SWP_SHOWWINDOW
$OPTIONS = 0x0004 -bor 0x0020 -bor 0x0040

if ($Retirer) {
  [FenetreJeu]::SetWindowLong($h, -16, $SANS_BORDURE) | Out-Null
  [FenetreJeu]::SetWindowPos($h, [IntPtr]::Zero, $b.X, $b.Y, $b.Width, $b.Height, $OPTIONS) | Out-Null
  Write-Host ("Fenêtre du jeu ramenée sur l'écran principal ({0} x {1})." -f $b.Width, $b.Height)
  exit 0
}

# L'écran voisin : même hauteur, même ligne, collé à gauche (ou à droite) de l'écran principal.
if ($Cote -eq "gauche") {
  $voisin = $ecrans | Where-Object { $_.Bounds.Right -eq $b.Left -and $_.Bounds.Top -eq $b.Top -and $_.Bounds.Height -eq $b.Height } | Select-Object -First 1
} else {
  $voisin = $ecrans | Where-Object { $_.Bounds.Left -eq $b.Right -and $_.Bounds.Top -eq $b.Top -and $_.Bounds.Height -eq $b.Height } | Select-Object -First 1
}
if (-not $voisin) { Write-Host "Aucun écran de même hauteur collé à $Cote de l'écran principal."; exit 1 }

$gauche = [Math]::Min($b.Left, $voisin.Bounds.Left)
$largeur = $b.Width + $voisin.Bounds.Width
[FenetreJeu]::SetWindowLong($h, -16, $SANS_BORDURE) | Out-Null
[FenetreJeu]::SetWindowPos($h, [IntPtr]::Zero, $gauche, $b.Top, $largeur, $b.Height, $OPTIONS) | Out-Null
Write-Host ("Fenêtre du jeu étirée sur deux écrans : {0} x {1} à partir de x = {2}." -f $largeur, $b.Height, $gauche)
Write-Host "Dans les réglages de « Fenêtres déplaçables », coche « Le jeu sur un écran, les fenêtres sur l'autre »."
