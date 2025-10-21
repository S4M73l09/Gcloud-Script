@echo off
setlocal enableextensions disabledelayedexpansion
rem ======================================================
rem  Google Cloud SDK Wrapper (multi-ruta + utilidades)
rem ======================================================
rem: Status: Active
rem: by S4M73l09

rem --- Guardar codepage actual y cambiar a UTF-8 (tildes limpias) ---
for /f "tokens=2 delims=:" %%A in ('chcp') do set "GCLOUD_WRAPPER_OLDCP=%%A"
for /f "tokens=* delims= " %%A in ("%GCLOUD_WRAPPER_OLDCP%") do set "GCLOUD_WRAPPER_OLDCP=%%A"
chcp 65001 >nul

rem --- Situarnos en la carpeta del script ---
cd /d "%~dp0"

rem --- (Opcional) usar perfil local si existe .gcloud-config ---
if exist "%~dp0.gcloud-config" set "CLOUDSDK_CONFIG=%~dp0.gcloud-config"

rem --- Detectar google-cloud-sdk en varias ubicaciones ---
set "GCLOUD_ROOT="
if exist "%LOCALAPPDATA%\Google\Cloud SDK\google-cloud-sdk" set "GCLOUD_ROOT=%LOCALAPPDATA%\Google\Cloud SDK\google-cloud-sdk"
if not defined GCLOUD_ROOT if exist "%ProgramFiles%\Google\Cloud SDK\google-cloud-sdk" set "GCLOUD_ROOT=%ProgramFiles%\Google\Cloud SDK\google-cloud-sdk"
if not defined GCLOUD_ROOT if exist "%ProgramFiles(x86)%\Google\Cloud SDK\google-cloud-sdk" set "GCLOUD_ROOT=%ProgramFiles(x86)%\Google\Cloud SDK\google-cloud-sdk"

if not defined GCLOUD_ROOT (
  echo [ERROR] No se encontro Google Cloud SDK en el sistema.
  echo         Instala la CLI de Google Cloud y vuelve a intentarlo.
  goto :restore_cp_and_exit1
)

rem --- Asegurar que gcloud.cmd existe ---
if not exist "%GCLOUD_ROOT%\bin\gcloud.cmd" (
  echo [ERROR] No se encontro el launcher: "%GCLOUD_ROOT%\bin\gcloud.cmd"
  goto :restore_cp_and_exit1
)

rem --- Añadir bin al PATH (por si no esta global) ---
set "PATH=%GCLOUD_ROOT%\bin;%PATH%"

rem --- Forzar Python embebido del SDK ---
set "CLOUDSDK_PYTHON=%GCLOUD_ROOT%\platform\bundledpython\python.exe"

rem --- Saneo de CLOUDSDK_PYTHON (evita "(unset)" / rutas rotas / espacios) ---
if /I "%CLOUDSDK_PYTHON%"=="(unset)" set "CLOUDSDK_PYTHON="
if defined CLOUDSDK_PYTHON if not exist "%CLOUDSDK_PYTHON%" set "CLOUDSDK_PYTHON="
for /f "tokens=* delims= " %%# in ("%CLOUDSDK_PYTHON%") do set "CLOUDSDK_PYTHON=%%#"

if not exist "%CLOUDSDK_PYTHON%" (
  echo [ADVERTENCIA] No se encontro el Python embebido del SDK. Continuando igualmente...
  echo.
)

rem --- /diag: diagnostico rapido (no modifica nada) ---
if /I "%~1"=="/diag" (
  echo === DIAGNOSTICO WRAPPER ===
  echo SDK Root         : "%GCLOUD_ROOT%"
  echo gcloud launcher  : "%GCLOUD_ROOT%\bin\gcloud.cmd"
  echo CLOUDSDK_PYTHON  : "%CLOUDSDK_PYTHON%"
  echo CLOUDSDK_CONFIG  : "%CLOUDSDK_CONFIG%"
  echo PATH (head)      : "%GCLOUD_ROOT%\bin"
  where gcloud 2>nul
  "%GCLOUD_ROOT%\bin\gcloud.cmd" version
  set "RC=%ERRORLEVEL%"
  goto :restore_cp_and_exit
)

rem --- /dry-run: mostrar el comando sin ejecutarlo ---
if /I "%~1"=="/dry-run" (
  shift
  echo gcloud %*
  set "RC=0"
  goto :restore_cp_and_exit
)

rem --- Logging opcional (si defines GCLOUD_WRAPPER_LOG=archivo.log) ---
if defined GCLOUD_WRAPPER_LOG (
  echo [%DATE% %TIME%] gcloud %*>>"%GCLOUD_WRAPPER_LOG%"
)

rem --- Ejecutar gcloud con los argumentos recibidos ---
"%GCLOUD_ROOT%\bin\gcloud.cmd" %*
set "RC=%ERRORLEVEL%"

:restore_cp_and_exit
rem --- Restaurar codepage original (si existia) ---
if defined GCLOUD_WRAPPER_OLDCP chcp %GCLOUD_WRAPPER_OLDCP% >nul
endlocal & exit /b %RC%

:restore_cp_and_exit1
if defined GCLOUD_WRAPPER_OLDCP chcp %GCLOUD_WRAPPER_OLDCP% >nul
endlocal & exit /b 1

