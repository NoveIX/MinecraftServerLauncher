if ($PSEdition -ne "Core") {
    Write-Error "Only PowerShell Core is supported. Windows PowerShell Desktop is not supported."
    exit 1
}

$Items = @(
    "server"
    "LICENSE"
    "README.md"
    "startserver.cmd"
    "startserver.sh"
    "version.txt"
)

$RootDir = Split-Path $PSScriptRoot -Parent
$VersionFile = Join-Path $RootDir "version.txt"
$Version = (Get-Content $VersionFile -Raw).Trim()

# Windows ZIP
$ReleaseArchive = Join-Path $RootDir "ServerLauncher-v${version}.zip"

$ZipItems = $Items | ForEach-Object { Join-Path $RootDir $_ }

Compress-Archive -Path $ZipItems -DestinationPath $ReleaseArchive -Force


# ================================================================== #


# Linux TAR.GZ - WSL REQUIRED
$LinuxArchive = "ServerLauncher-v${Version}.tar.gz"

$WslRoot = (& wsl.exe --exec wslpath -a "$RootDir" | Out-String).Trim()

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($WslRoot)) {
    throw "Unable to resolve WSL path."
}

$WslArchive = "$WslRoot/$LinuxArchive"

& wsl.exe --cd "$WslRoot" tar -czf "$WslArchive" --mode='u=rw,go=r' -- @Items

if ($LASTEXITCODE -ne 0) {
    throw "Unable to create Linux release archive."
}
