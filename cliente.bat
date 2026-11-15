@echo off
chcp 65001 >nul
cd /d "%~dp0"
call elixir.bat --sname cliente_%RANDOM%@localhost --cookie emergencias_clase -S mix run --no-start -e "Emergencias.Consola.main({Emergencias.Servidor, :emergencias_servidor@localhost})"
pause
