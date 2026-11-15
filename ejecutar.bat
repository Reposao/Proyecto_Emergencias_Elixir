@echo off
chcp 65001 >nul
cd /d "%~dp0"
call mix.bat run -e "Emergencias.Consola.main()"
pause