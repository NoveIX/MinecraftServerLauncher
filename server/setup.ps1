param (
    # Java
    [Parameter(Mandatory = $true, ParameterSetName = "java")]
    [switch]$InstallJava,

    # Minecraft Loader
    [Parameter(Mandatory = $true, ParameterSetName = "Loader")]
    [switch]$InstallLoader
)


# ====================================================================================== #


#region Logging
function Write-Log {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateSet("Info", "Warn", "Error")]
        [string]$Level,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$Message
    )

    $Color = switch ($Level) {
        "Info" { "Blue" }
        "Warn" { "DarkYellow" }
        "Error" { "DarkRed" }
    }

    Write-Host "[" -NoNewline
    Write-Host $Level.ToUpper() -ForegroundColor $Color -NoNewline
    Write-Host "]: $Message"
}

function Write-LogInfo {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message
    )

    Write-Log -Level Info -Message $Message
}

function Write-LogError {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message
    )

    Write-Log -Level Error -Message $Message
}
#endregion


# ====================================================================================== #


#region Utility func
# Get system architecture (x64 or ARM64)
function Get-SystemArch {
    param(
        [switch]$JavaApi
    )

    switch ($env:PROCESSOR_ARCHITECTURE) {

        "AMD64" { return "x64" }
        "ARM64" {
            if ($JavaApi) { return "aarch64" }
            return "arm64"
        }

        Default {
            throw [System.PlatformNotSupportedException]::new(
                "Unsupported processor architecture $env:PROCESSOR_ARCHITECTURE. Required architecture: AMD64 or ARM64."
            )
        }
    }
}

# Download a file from a URL
function Invoke-FileDownload {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$Url
    )

    $FileInfo = [System.IO.FileInfo]::new($Path)

    # Try BITS
    try {
        Write-LogInfo "BITS: Downloading $($FileInfo.Name)"
        Start-BitsTransfer -Source $Url -Destination $FileInfo.FullName -ErrorAction Stop

        Write-LogInfo "BITS: Download completed"
        return
    }
    catch {
        Write-LogError "BITS: download failed: $($_.Exception.Message)"
    }

    # Try WebRequest
    try {
        Write-LogInfo "WebRequest: Downloading $($FileInfo.Name)"
        Invoke-WebRequest -Uri $Url -OutFile $FileInfo.FullName -UseBasicParsing -ErrorAction Stop

        Write-LogInfo "WebRequest: Download completed"
        return
    }
    catch {
        Write-LogError "WebRequest: download failed: $($_.Exception.Message)"
    }

    # If both methods fail, throw an exception
    throw [System.InvalidOperationException]::new(
        "Failed to download '$($FileInfo.Name)' using both BITS and WebRequest."
    )
}
#endregion


# ====================================================================================== #


#region Install java
# Download and install Java from Adoptium Temurin
function Install-Java {

    # Get system architecture
    $Arch = Get-SystemArch
    $JavaArch = Get-SystemArch -JavaApi

    # Get Java package metadata from environment variables
    $Major = $env:JAVA_VERSION
    $Variant = $env:JAVA_VARIANT.ToLower()

    # Build Java archive name and download URL
    $JavaArchive = "Adoptium-OpenJDK${Major}U-${Variant}-${Arch}-windows.zip"
    $JavaUrl = "https://api.adoptium.net/v3/binary/latest/${Major}/ga/windows/${JavaArch}/${Variant}/hotspot/normal/eclipse"

    # Build local Java paths
    $JavaZip = Join-Path -Path $env:ROOT -ChildPath $JavaArchive
    $JavaTemp = Join-Path -Path $env:ROOT -ChildPath "OpenJDK${Major}U"
    $JavaRoot = [System.IO.Path]::Combine($env:ROOT, "java", "windows-${Arch}-${Variant}-${Major}")
    #$JavaRoot = [System.IO.Path]::Combine($env:ROOT, "java", "windows", $Arch, $Variant, $Major)


    # Download Java archive if not already present
    if (-not (Test-Path -Path $JavaZip -PathType Leaf)) {
        Invoke-FileDownload -Path $JavaZip -Url $JavaUrl
    }


    # Install java if not already installed
    if (-not (Test-Path -Path $JavaRoot -PathType Container)) {

        # Expand Java Archive
        try {
            Write-LogInfo "Extracting $JavaArchive"
            Expand-Archive -Path $JavaZip -DestinationPath $JavaTemp -Force -ErrorAction Stop

            Write-LogInfo "Extraction completed"
        }
        catch {
            Write-LogError "Java extraction failed: $($_.Exception.Message)"
            throw
        }


        try {
            # Locate the extracted Java installation directory
            $JavaSource = Get-ChildItem -Path $JavaTemp -Directory -ErrorAction Stop |
            Where-Object { $_.Name -match "(jdk|jre)-?${Major}" } |
            Select-Object -First 1

            # Validate that the Java installation directory was found
            if (-not $JavaSource) {
                throw [System.IO.DirectoryNotFoundException]::new(
                    "Failed to locate Java installation directory in '$JavaTemp' for version $Major."
                )
            }


            # Ensure the final Java directory exists
            if (-not (Test-Path -Path $JavaRoot -PathType Container)) {
                New-Item -Path $JavaRoot -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }

            # Copy Java installation contents to the final destination
            Write-LogInfo "Copying Java installation"
            Get-ChildItem -Path $JavaSource.FullName -Force -ErrorAction Stop |
            Copy-Item -Destination $JavaRoot -Recurse -Force -ErrorAction Stop

            Write-LogInfo "Copy completed"


            # Remove temporary extraction directory
            Remove-Item -Path $JavaTemp -Force -Recurse -ErrorAction Stop

            Write-LogInfo "Java installation completed. Installed in '$JavaRoot'"
        }
        catch {
            Write-LogError "Java installation failed. $($_.Exception.Message)"
            throw
        }
    }
    else {
        Write-LogInfo "Java already installed"
    }
}
#endregion


# ====================================================================================== #


#region Install Minecraft loader
# Download and install Minecraft loader
function Install-Loader {

    # Get loader metadata
    $McVer = $env:MINECRAFT_VERSION
    $Loader = $env:MINECRAFT_LOADER.ToLower()
    $LoaderVer = $env:MINECRAFT_LOADER_VERSION

    # Build loader archive name and download URL
    try {
        switch -CaseSensitive ($Loader) {

            # Vanilla server
            "vanilla" {
                $LoaderName = "Vanilla"
                $LoaderArchive = "server-${McVer}.jar"
                $ApiUrl = "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"

                # Get Minecraft version manifest
                $Manifests = Invoke-RestMethod -Uri $ApiUrl -ErrorAction Stop
                $Manifest = $Manifests.versions | Where-Object { $_.id -eq $McVer } | Select-Object -First 1

                if (-not $Manifest) {
                    throw [System.InvalidOperationException]::new(
                        "Minecraft version '$McVer' not found."
                    )
                }

                $VersionManifest = Invoke-RestMethod -Uri $Manifest.url -ErrorAction Stop
                $LoaderUrl = $VersionManifest.downloads.server.url
            }

            # ====================================================================================== #

            # Forge Server
            "forge" {
                $LoaderName = "Forge"
                $LoaderArchive = "forge-${McVer}-${LoaderVer}-installer.jar"
                $LoaderUrl = "https://maven.minecraftforge.net/net/minecraftforge/forge/${McVer}-${LoaderVer}/${LoaderArchive}"
            }

            # ====================================================================================== #

            # NeoForge Server
            "neoforge" {
                $LoaderName = "NeoForge"
                $LoaderArchive = "neoforge-${LoaderVer}-installer.jar"
                $LoaderUrl = "https://maven.neoforged.net/releases/net/neoforged/neoforge/${LoaderVer}/${LoaderArchive}"
            }

            # ====================================================================================== #

            # Fabric Server
            "fabric" {
                $LoaderName = "Fabric"
                $ApiUrl = "https://meta.fabricmc.net/v2/versions/installer"

                # Get latest stable Fabric installer
                $Installers = Invoke-RestMethod -Uri $ApiUrl -ErrorAction Stop
                $Installer = $Installers | Where-Object { $_.stable } | Select-Object -First 1

                if (-not $Installer) {
                    throw [System.InvalidOperationException]::new(
                        "No stable Fabric installer version found."
                    )
                }

                $LoaderArchive = "fabric-installer-$($Installer.version).jar"
                $LoaderUrl = $Installer.url
            }

            # ====================================================================================== #

            # Quilt Server
            "quilt" {
                $LoaderName = "Quilt"
                $ApiUrl = "https://meta.quiltmc.org/v3/versions/installer"

                # Get latest Quilt installer version
                $Installers = Invoke-RestMethod -Uri $ApiUrl -ErrorAction Stop
                $Installer = $Installers | Where-Object { $_.version -match '^\d+(\.\d+)+$' } | Sort-Object { [version]$_.version } -Descending | Select-Object -First 1

                if (-not $Installer) {
                    throw [System.InvalidOperationException]::new(
                        "No valid Quilt installer version found."
                    )
                }

                $LoaderArchive = "quilt-installer-$($Installer.version).jar"
                $LoaderUrl = $Installer.url
            }

            # ====================================================================================== #

            # Paper Server
            "paper" {
                $LoaderName = "Paper"
                $LoaderArchive = "paper-${McVer}-${LoaderVer}.jar"
                $ApiUrl = "https://fill.papermc.io/v3/projects/paper/versions/${McVer}/builds"

                $Headers = @{
                    "User-Agent" = "MinecraftServerSetup/1.0 (https://github.com/)"
                }

                # Get Paper build download URL
                $Builds = Invoke-RestMethod -Uri $ApiUrl -Headers $Headers -ErrorAction Stop
                $Build = $Builds | Where-Object { $_.id -eq $LoaderVer } | Select-Object -First 1

                if (-not $Build) {
                    throw [System.InvalidOperationException]::new(
                        "Paper build '$LoaderVer' not found for Minecraft '$McVer'."
                    )
                }

                $LoaderUrl = $Build.downloads.'server:default'.url
            }

            # ====================================================================================== #
            # "spigot" { break }

            Default {
                throw [System.ArgumentException]::new(
                    "Unsupported Minecraft loader '$Loader'."
                )
            }
        }

    }
    catch {
        $LoaderName = if ($LoaderName) { $LoaderName } else { $Loader }
        Write-LogError "$LoaderName installation failed. $($_.Exception.Message)"
        throw
    }

    # Build local loader paths
    $LoaderJar = Join-Path -Path $env:ROOT -ChildPath $LoaderArchive
    $LibrariesDir = Join-Path -Path $env:ROOT -ChildPath "libraries"


    # Download loader archive if not already present
    if (-not (Test-Path -Path $LoaderJar -PathType Leaf)) {
        Invoke-FileDownload -Path $LoaderJar -Url $LoaderUrl
    }


    # Install loader if not already installed
    if (-not (Test-Path -Path $LibrariesDir -PathType Container)) {
        try {
            # Validate Java executable
            if (-not (Test-Path -Path $env:JAVA_EXE -PathType Leaf)) {
                throw [System.IO.FileNotFoundException]::new(
                    "Java executable not found: '$env:JAVA_EXE'."
                )
            }

            try {
                Push-Location $env:ROOT

                # Run the appropriate command based on the loader type
                if ($Loader -cnotin @("vanilla", "paper")) {
                    Write-LogInfo "Installing $LoaderName"

                    switch -CaseSensitive ($Loader) {
                        { $_ -in @("forge", "neoforge") } {
                            & $env:JAVA_EXE -jar $LoaderJar --installServer
                        }

                        "fabric" {
                            & $env:JAVA_EXE -jar $LoaderJar server `
                                -mcversion $McVer `
                                -loader $LoaderVer `
                                -dir $env:ROOT `
                                -downloadMinecraft
                        }

                        "quilt" {
                            & $env:JAVA_EXE -jar $LoaderJar `
                                install server $McVer $LoaderVer `
                                "--install-dir=${env:ROOT}" `
                                --download-server
                        }

                        Default {
                            throw [System.ArgumentException]::new(
                                "Unsupported Minecraft loader '$Loader'."
                            )
                        }
                    }

                    # Check loader installation
                    if ($LASTEXITCODE -ne 0) {
                        throw [System.InvalidOperationException]::new(
                            "$LoaderName installation failed with exit code $LASTEXITCODE."
                        )
                    }
                }

                # Remove default run.* files created by the installer
                Get-ChildItem -Path $env:ROOT -Filter "run.*" -File |
                Remove-Item -Force

                Write-LogInfo "Installation completed"
            }
            finally {
                Pop-Location
            }
        }
        catch {
            Write-LogError "$LoaderName installation failed. $($_.Exception.Message)"
            throw
        }
    }
    else {
        Write-LogInfo "$LoaderName already installed"
    }
}
#endregion


# ====================================================================================== #


if ($InstallJava) { Install-Java }
if ($InstallLoader) { Install-Loader }
