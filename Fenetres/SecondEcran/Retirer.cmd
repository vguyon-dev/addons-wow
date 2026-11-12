@echo off
rem Second ecran : arrete le petit programme et ne le relance plus avec Windows.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0second-ecran.ps1" -Desinstaller
pause
