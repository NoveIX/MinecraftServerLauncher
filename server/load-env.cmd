@echo off

:: Check if the environment file exists
if not exist "!ENV!" (
    echo ERROR: File not found ^'!ENV!^'
    exit /b 1
)

:: Load environment variables from the file
for /F "usebackq tokens=1,* delims==" %%A in ("!ENV!") do (
    if not "%%A:~0,1%"=="#" (
        set "%%A=%%B"
    )
)

exit /b 0
