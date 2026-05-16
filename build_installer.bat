@echo off
setlocal

set PROJECT_DIR=%~dp0
set RELEASE_DIR=%PROJECT_DIR%build\windows\x64\runner\Release
:: Cerca Inno Setup in tutti i percorsi comuni
set ISCC=%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe
if not exist "%ISCC%" set ISCC=C:\Program Files (x86)\Inno Setup 6\ISCC.exe
if not exist "%ISCC%" set ISCC=C:\Program Files\Inno Setup 6\ISCC.exe
set ISS=%PROJECT_DIR%installer\deck_master_setup.iss

echo ============================================
echo  Deck Master - Build Installer v1.3.2
echo ============================================
echo.

:: 1. Flutter build release
echo [1/2] Flutter build windows --release...
cd /d "%PROJECT_DIR%"
call flutter build windows --release --dart-define-from-file=dart_defines.json
if errorlevel 1 (
    echo.
    echo ERRORE: flutter build fallita.
    pause
    exit /b 1
)
echo OK
echo.

:: Verifica che i file Release esistano
if not exist "%RELEASE_DIR%\deck_master.exe" (
    echo ERRORE: deck_master.exe non trovato in:
    echo   %RELEASE_DIR%
    pause
    exit /b 1
)

:: 2. Compila installer con Inno Setup
echo [2/2] Compilazione installer con Inno Setup...
if not exist "%ISCC%" (
    echo.
    echo ERRORE: Inno Setup 6 non trovato.
    echo Scaricalo da: https://jrsoftware.org/isdl.php
    echo Installalo in: %LOCALAPPDATA%\Programs\Inno Setup 6\
    pause
    exit /b 1
)

"%ISCC%" "%ISS%"
if errorlevel 1 (
    echo.
    echo ERRORE: Inno Setup ha fallito.
    pause
    exit /b 1
)

echo.
echo ============================================
echo  Installer creato in: installer_output\
echo ============================================
explorer "%PROJECT_DIR%installer_output"
pause
