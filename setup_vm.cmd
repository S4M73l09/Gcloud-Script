@echo off
REM ================================================================
REM  Wrapper para ejecutar setup_vm.ps1 desde CMD o doble clic
REM  Autor: Samuel | Proyecto: Gcloud-Script
REM ================================================================

REM Cambia al directorio donde está este script (.cmd)
cd /d "%~dp0"

REM Ejecuta PowerShell con permisos adecuados y sin logo
powershell -NoLogo -ExecutionPolicy Bypass -File "%~dp0setup_vm.ps1" %*

