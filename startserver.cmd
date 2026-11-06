@echo off
setlocal EnableDelayedExpansion

:: To use a specific Java runtime, set JAVA_EXE to the full path of the Java executable.
:: set "JAVA_EXE=C:\Program Files\Eclipse Adoptium\jre-17.0.18.8-hotspot\bin\java.exe"

:: To enable automatic server restarts, set SERVER_RESTART to true.
:: set "SERVER_RESTART=true"

:: To install the server without starting it, set INSTALL_ONLY to true.
:: set "INSTALL_ONLY=true"



:: ==================================================================================== ::



:: Modpack root
set "ROOT=%~dp0"
set "ENV=!ROOT!server\server.env"
set "LOAD=!ROOT!server\load-env.cmd"
set "SETUP=!ROOT!server\setup.ps1"
cd /D "!ROOT!"

:: Check if load-env.cmd exists
if not exist "!LOAD!" (
    echo ERROR: File not found '!LOAD!'
    pause & exit /b 1
)

:: Load server environment
call "!LOAD!"
if errorlevel 1 (
    pause & exit /b 1
)

:: Check if setup.ps1 exists
if not exist "!SETUP!" (
    echo ERROR: File not found '!SETUP!'
    pause & exit /b 1
)

:: Terminal title
title !PROJECT_ID! !PROJECT_ROLE! v!MODPACK_VERSION!

:: Check if Java is available, install it if missing, and set JAVA_EXE variable
if not defined JAVA_EXE (

    :: Check system architecture
    if /i "!PROCESSOR_ARCHITECTURE!"=="AMD64" (
        set "JAVA_ARCH=x64"
    ) else if /i "!PROCESSOR_ARCHITECTURE!"=="ARM64" (
        set "JAVA_ARCH=arm64"
    ) else (
        echo ERROR: Unsupported processor architecture !PROCESSOR_ARCHITECTURE!. Required architecture: x64 or arm64.
        exit /b 1
    )

    :: Check or install local Java
    set "JAVA_EXE=!ROOT!java\windows-!JAVA_ARCH!-!JAVA_VARIANT!-!JAVA_VERSION!\bin\java.exe"

    if not exist "!JAVA_EXE!" (
        powershell -ExecutionPolicy Bypass ^
            -File "!SETUP!" ^
            -InstallJava

        :: Check PowerShell exit code
        if errorlevel 1 (
            pause & exit /b 1
        )
    )
)

:: Verify Java availability (file or PATH)
if not exist "!JAVA_EXE!" (
    where "!JAVA_EXE!" >nul 2>&1
    if errorlevel 1 (
        echo ERROR: Java not found '!JAVA_EXE!'
        pause & exit /b 1
    )
)

:: Get Java major version
for /f "delims=" %%v in ('powershell -NoProfile -Command ^
    "& { $output = & '!JAVA_EXE!' -fullversion 2^>^&1; if ($output -match 'version ""(?:1\.)?([0-9]+)') { $Matches[1] } }"'
) do (
    set "CTX_VER=%%v"
)

:: Check if Java version was detected
if not defined CTX_VER (
    echo ERROR: Unable to determine Java version.
    pause & exit /b 1
)

:: Check Java version compatibility with required Minecraft version
if !CTX_VER! lss !JAVA_VERSION! (
    echo Minecraft !MINECRAFT_VERSION! requires Java !JAVA_VERSION!. Found Java !CTX_VER!
    pause & exit /b 1
)

:: Check if libraries directory exists, install if missing
if not exist "libraries" (
    powershell -ExecutionPolicy Bypass ^
        -File "!SETUP!" ^
        -InstallLoader

    :: Powershell exit code
    if errorlevel 1 (
        pause & exit /b 1
    )
)

:: Check if running in "Install Only" mode
if /i "!INSTALL_ONLY!" == "true" (
    echo INFO: Install completed the Server will NOT start.
    pause
    goto :EOF
)

:START
:: Start server (auto-restart on crash)
if /i "!MINECRAFT_LOADER!" == "Vanilla" (
    :: Start vanilla server
    "!JAVA_EXE!" !JAVA_ARGS! -jar server-!MINECRAFT_VERSION!.jar nogui

) else if /i "!MINECRAFT_LOADER!" == "Forge" (
    :: Start forge server
    "!JAVA_EXE!" !JAVA_ARGS! @libraries/net/minecraftforge/forge/!MINECRAFT_VERSION!-!MINECRAFT_LOADER_VERSION!/win_args.txt nogui

) else if /i "!MINECRAFT_LOADER!" == "NeoForge" (
    :: Start NeoForge server
    "!JAVA_EXE!" !JAVA_ARGS! @libraries/net/neoforged/neoforge/!MINECRAFT_LOADER_VERSION!/win_args.txt nogui

) else if /i "!MINECRAFT_LOADER!" == "Fabric" (
    :: Start Fabric server
    "!JAVA_EXE!" !JAVA_ARGS! -jar fabric-server-launch.jar nogui

) else if /i "!MINECRAFT_LOADER!" == "Quilt" (
    :: Start Quilt server
    "!JAVA_EXE!" !JAVA_ARGS! -jar quilt-server-launch.jar nogui

) else if /i "!MINECRAFT_LOADER!" == "Paper" (
    :: Start Paper server
    "!JAVA_EXE!" !JAVA_ARGS! -jar paper-!MINECRAFT_VERSION!-!MINECRAFT_LOADER_VERSION!.jar nogui

) else (
    echo "Unsupported Minecraft loader: !MINECRAFT_LOADER!" >&2
    goto :EOF
)

:: Restart Server
if /i "!SERVER_RESTART!" == "true" (
    echo Restarting automatically in 10 seconds ^(press Ctrl + C to cancel^)
    timeout /t 10 /nobreak > NUL
    goto :START
)

pause
