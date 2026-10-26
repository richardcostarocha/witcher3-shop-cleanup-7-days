@echo off
cd /d "%~dp0"
python tools/project.py build %*
if errorlevel 1 (echo Verifique a mensagem acima.)
pause
