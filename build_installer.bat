@echo off
setlocal

set PROJECT_DIR=%~dp0
set RELEASE_DIR=%PROJECT_DIR%build\windows\x64\runner\Release
set DEBUG_DIR=%PROJECT_DIR%build\windows\x64\runner\Debug
set ISCC=%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe
set ISS=%PROJECT_DIR%installer\deck_master_setup.iss

echo ============================================
echo  Deck Master - Build Installer
echo ============================================
echo.

:: 1. Flutter build release
echo [1/3] Flutter build windows --release...
cd /d "%PROJECT_DIR%"
call flutter build windows --release
if errorlevel 1 (
    echo ERRORE: flutter build fallita.
    pause
    exit /b 1
)
echo OK
echo.

:: 2. Copia DLL e data da Debug a Release
echo [2/3] Copia DLL e assets in Release...
if not exist "%DEBUG_DIR%\flutter_windows.dll" (
    echo ERRORE: DLL non trovate in Debug.
    pause
    exit /b 1
)
copy /Y "%DEBUG_DIR%\*.dll" "%RELEASE_DIR%\" >nul
if exist "%RELEASE_DIR%\data" rmdir /S /Q "%RELEASE_DIR%\data"
xcopy /E /I /Q "%DEBUG_DIR%\data" "%RELEASE_DIR%\data" >nul
echo OK
echo.

:: 3. Compila installer con Inno Setup
echo [3/3] Compilazione installer...
if not exist "%ISCC%" (
    echo ERRORE: Inno Setup non trovato in %ISCC%
    pause
    exit /b 1
)
"%ISCC%" "%ISS%"
if errorlevel 1 (
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
