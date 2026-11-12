@echo off
rem Second ecran pour World of Warcraft (addon Fenetres deplacables).
rem Double-clique une fois : le petit programme tourne cache, maintenant et a chaque ouverture de Windows.
rem Il etale la fenetre du jeu sur deux ecrans quand tu cliques "Passer au second ecran" dans /fen.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0second-ecran.ps1" -Installer
pause
