# Fabrique le zip à partager : tous les addons du dépôt + une notice d'installation.
# Lancer depuis Windows :  powershell -File outils\paquet.ps1
# Le zip part dans Téléchargements\@Claude\Telechargements\AddonsWow\.
$ErrorActionPreference = "Stop"
$racine = Split-Path $PSScriptRoot -Parent
$addons = Get-ChildItem $racine -Directory | Where-Object { Test-Path (Join-Path $_.FullName "$($_.Name).toc") }
$date = Get-Date -Format "yyyy-MM-dd"
$sortie = Join-Path $env:USERPROFILE "Downloads\@Claude\Telechargements\AddonsWow"
New-Item -ItemType Directory -Force $sortie | Out-Null
$zip = Join-Path $sortie "$date AddonsValentin.zip"

# Dossier de travail : les addons + la notice, puis on zippe.
$tmp = Join-Path $env:TEMP "paquet-addons-wow"
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
New-Item -ItemType Directory $tmp | Out-Null
foreach ($a in $addons) { Copy-Item $a.FullName (Join-Path $tmp $a.Name) -Recurse }
Copy-Item (Join-Path $PSScriptRoot "LISEZMOI.txt") $tmp
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $tmp "*") -DestinationPath $zip
Remove-Item $tmp -Recurse -Force

$i = 0
foreach ($a in $addons) {
  $i++
  $v = (Select-String (Join-Path $a.FullName "$($a.Name).toc") -Pattern '^## Version: (.+)$').Matches[0].Groups[1].Value
  Write-Host ("[{0}/{1}] {2} {3}" -f $i, $addons.Count, $a.Name, $v)
}
Write-Host "Zip prêt : $zip"
