@echo off
setlocal

rem =============================
rem   Google Cloud SDK Wrapper
rem =============================

rem --- Cambia al directorio donde está este script (.cmd) ---
cd /d "%~dp0"

rem --- Añade gcloud al PATH local (por si no está en PATH global) ---
set "PATH=%LOCALAPPDATA%\Google\Cloud SDK\google-cloud-sdk\bin;%PATH%"

rem --- Fuerza el Python embebido del SDK (evita errores (unset)) ---
set "CLOUDSDK_PYTHON=%LOCALAPPDATA%\Google\Cloud SDK\google-cloud-sdk\platform\bundledpython\python.exe"

if not exist "%LOCALAPPDATA%\Google\Cloud SDK\google-cloud-sdk\platform\bundledpython\python.exe" (
  echo [ADVERTENCIA] No se encontro el Python embebido del SDK. 
  echo Continuo igualmente...
  echo.
)


rem --- Comprobación: ¿existe gcloud.cmd? ---
if not exist "%LOCALAPPDATA%\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd" (
    echo [ERROR] Google Cloud SDK no está instalado o la ruta no existe.
    echo Instálalo desde: https://cloud.google.com/sdk/docs/install
    pause
    exit /b 1
)

rem --- Comprobación: ¿existe el script PowerShell? ---
set "PS_SCRIPT=%~dp0setup_vm.ps1"
if not exist "%PS_SCRIPT%" (
    echo [ERROR] No se encontró el script PowerShell: %PS_SCRIPT%
    pause
    exit /b 1
)

rem --- Mensaje informativo ---
echo ==============================================
echo  Ejecutando script PowerShell: %PS_SCRIPT%
echo  Directorio actual: %CD%
echo  Argumentos: %*
echo ==============================================
echo.

rem --- Ejecuta el script PowerShell con control robusto de errores ---
call :runps
set ERR=%ERRORLEVEL%
if not "%ERR%"=="0" (
    echo.
    echo [ERROR] El script PowerShell terminó con errores (código %ERR%).
    pause
    exit /b %ERR%
)
echo.
echo [OK] Script completado correctamente.
pause
exit /b 0

:runps
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" %*
exit /b %ERRORLEVEL%
