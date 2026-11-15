@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo Servidor de la demostración local. Mantenga abierta esta ventana.
call elixir.bat --sname emergencias_servidor@localhost --cookie emergencias_clase -S mix run --no-halt
pause
