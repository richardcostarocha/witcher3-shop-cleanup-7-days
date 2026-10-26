@echo off
cd /d "%~dp0"
python tools/project.py verify
if errorlevel 1 goto falha
python tests/run.py
if errorlevel 1 goto falha
pause
exit /b 0
:falha
echo Verificacao falhou. Confira a mensagem acima.
pause
exit /b 1
