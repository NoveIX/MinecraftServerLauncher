#region Logging
log() {
    level="$1"
    message="$2"

    case "$level" in

        info)
            color='\033[94m'       # Blue
        ;;

        warn)
            color='\033[33m'       # Yellow
        ;;

        error)
            color='\033[31m'       # Red
        ;;

        done)
            color='\033[32m'       # Green
        ;;

        *)
            printf 'invalid log level: %s\n' "$level"
            return 1
        ;;

    esac

    printf '%b%s%b %s\n' "$color" "$level" '\033[0m' "$message"
}

log_info() {
    log "info" "$1"
}

log_warn() {
    log "warn" "$1"
}

log_error() {
    log "error" "$1" >&2
}

log_done() {
    log "done" "$1"
}
#endregion


# ====================================================================================== #


#region Utility func
# Get system architecture (x64 or ARM64)
system_arch() {

    case "$(uname -m)" in
        x86_64|amd64)
            arch='x64'
        ;;

        aarch64|arm64)
            arch='arm64'
        ;;

        *)
            log_error "Unsupported processor architecture $(uname -m). Supported architectures: x64 and arm64"
            return 1
        ;;
    esac

    if [ "${1:-}" = 'javaapi' ] && [ "$arch" = 'arm64' ]; then
        arch='aarch64'
    fi

    # Return system arch
    printf '%s\n' "$arch"
}

# Get operating system
java_os() {

    case "$(uname -s)" in
        Linux)
            os="linux"

            if [ -f /etc/os-release ]; then

                # Get os id from /etc
                os_id=$(sed -n 's/^ID=//p' /etc/os-release)

                # Remove optional double quotes.
                os_id="${os_id#\"}"
                os_id="${os_id%\"}"

                if [ "$os_id" = "alpine" ]; then
                    os="alpine-linux"
                fi
            fi
        ;;

        Darwin)
            os="mac"
        ;;

        *)
            log_error "Unsupported operating system $(uname -s). Supported operating systems: Linux, MacOS"
            return 1
        ;;
    esac

    # Return api os
    printf '%s\n' "$os"
}

# Download a file from a URL
file_download() {
    path="$1"
    url="$2"
    file=$(basename "$path")

    # Try wget
    if command -v wget >/dev/null 2>&1; then
        log_info "wget: downloading $file"

        if ! wget -q --show-progress -O "$path" "$url"; then
            log_error "wget: download failed"
            return 1
        fi

        log_info "wget: download completed"
        return 0
    fi

    log_warn "wget not found, trying curl"


    # Try curl
    if command -v curl >/dev/null 2>&1; then
        log_info "curl: downloading $file"

        if ! curl -# -L -o "$path" "$url"; then
            log_error "curl: download failed"
            return 1
        fi

        log_info "curl: download completed"
        return 0
    fi

    log_error "Neither wget nor curl is installed. Please install one of these tools to proceed."
    return 1
}
#endregion


# ====================================================================================== #


#region Install java
# Download and install Java from Adoptium Temurin
install_java() {

    # Get system architecture
    arch=$(system_arch) || return 1
    java_arch=$(system_arch "javaapi") || return 1
    java_os=$(java_os) || return 1

    # Get Java package metadata from environment variables
    major="$JAVA_VERSION"
    variant=$(printf '%s' "$JAVA_VARIANT" | tr '[:upper:]' '[:lower:]')

    # Build Java archive name
    java_archive="Adoptium-OpenJDK${major}U-${variant}-${arch}-${java_os}.tar.gz"

    # Build Java download URL
    java_url="https://api.adoptium.net/v3/binary/latest/${major}/ga/${java_os}/${java_arch}/${variant}/hotspot/normal/eclipse"

    # Build local Java paths
    java_zip="$ROOT/$java_archive"
    java_temp="$ROOT/OpenJDK${major}U"
    java_root="$ROOT/java/${java_os}-${arch}-${variant}-${major}"
    #java_root="$ROOT/java/${java_os}/${arch}/${variant}/${major}"


    # Download Java archive if not already present
    if [ ! -f "$java_zip" ]; then
        file_download "$java_zip" "$java_url" || return 1
    fi


    # Install Java if not already installed
    if [ ! -d "$java_root" ]; then

        # Extract Java archive
        log_info "Extracting $java_archive"

        if ! mkdir -p "$java_temp"; then
            log_error "Failed to create extraction directory '$java_temp'"
            return 1
        fi

        if ! tar -xzf "$java_zip" -C "$java_temp"; then
            log_error "Java extraction failed"
            return 1
        fi

        log_info "Java extraction completed"


        # Locate the extracted Java installation directory
        java_source=$(find "$java_temp" -type d -print |
            grep -E '/[^/]*(jdk|jre).*'"$major"'.*$' |
            sed -n '1p')


        # Validate that the Java installation directory was found
        if [ -z "$java_source" ]; then
            log_error "Failed to locate Java installation directory in '$java_temp' for version $major."
            return 1
        fi


        # Ensure the final Java directory exists
        if ! mkdir -p "$java_root"; then
            log_error "Failed to create Java installation directory '$java_root'"
            return 1
        fi

        # Copy Java installation contents to the final destination
        log_info "Copying Java installation"

        if ! cp -R "$java_source"/. "$java_root"/; then
            log_error "Failed to copy Java installation"
            return 1
        fi

        log_info "Copy completed"


        # Remove temporary extraction directory
        if ! rm -rf "$java_temp"; then
            log_error "Failed to remove temporary extraction directory '$java_temp'"
            return 1
        fi

        # Log completion message
        log_info "Java installation completed. Installed in '$java_root'"

    else
        log_info "Java already installed"
    fi
}
#endregion


# ====================================================================================== #


#region Install Minecraft loader
# Download and install Minecraft loader
install_loader() {

    # Get loader metadata
    mc_ver="$MINECRAFT_VERSION"
    loader=$(printf '%s' "$MINECRAFT_LOADER" | tr '[:upper:]' '[:lower:]')
    loader_ver="$MINECRAFT_LOADER_VERSION"

    # Check required dependencies
    case "$loader" in
        vanilla|fabric|quilt|paper)
            for cmd in curl jq; do
                if ! command -v "$cmd" >/dev/null 2>&1; then
                    log_error "Required command $cmd not found"
                    return 1
                fi
            done
            ;;
    esac

    # Build loader archive name and download URL
    case "$loader" in

        # Vanilla server
        vanilla)
            loader_name="Vanilla"
            loader_archive="server-${mc_ver}.jar"
            api_url="https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"

            # Get Minecraft version manifest
            manifest_url=$(curl -fsSL "$api_url" | jq -er --arg version "$mc_ver" '
            .versions[] | select(.id == $version) | .url' | head -n 1) || {
                log_error "Minecraft version $mc_ver not found"
                return 1
            }

            # Get server download URL
            loader_url=$(curl -fsSL "$manifest_url" | jq -er '.downloads.server.url') || {
                log_error "Failed to retrieve Minecraft server download URL"
                return 1
            }
        ;;

        # ====================================================================================== #

        # Forge Server
        forge)
            loader_name="Forge"
            loader_archive="forge-${mc_ver}-${loader_ver}-installer.jar"
            loader_url="https://maven.minecraftforge.net/net/minecraftforge/forge/${mc_ver}-${loader_ver}/${loader_archive}"
        ;;

        # ====================================================================================== #

        # NeoForge Server
        neoforge)
            loader_name="NeoForge"
            loader_archive="neoforge-${loader_ver}-installer.jar"
            loader_url="https://maven.neoforged.net/releases/net/neoforged/neoforge/${loader_ver}/${loader_archive}"
        ;;

        # ====================================================================================== #

        # Fabric Server
        fabric)
            loader_name="Fabric"
            api_url="https://meta.fabricmc.net/v2/versions/installer"

            # Get latest stable Fabric installer
            installers=$(curl -fsSL "$api_url") || {
                log_error "Failed to retrieve Fabric installer versions"
                return 1
            }

            installer=$(printf '%s' "$installers" | jq -cer '
            [.[] | select(.stable == true)]
            | first // error("No stable installer found")
            ') || {
                log_error "No stable Fabric installer version found." >&2
                return 1
            }

            installer_ver=$(printf '%s' "$installer" | jq -er '.version')
            loader_archive="fabric-installer-$installer_ver.jar"
            loader_url=$(printf '%s' "$installer" | jq -er '.url')
        ;;

        # ====================================================================================== #

        # Quilt Server
        quilt)
            loader_name="Quilt"
            api_url="https://meta.quiltmc.org/v3/versions/installer"

            # Get latest Quilt installer version
            installers=$(curl -fsSL "$api_url") || {
                log_error "Failed to retrieve Quilt installer versions"
                return 1
            }

            installer=$(printf '%s' "$installers" | jq -cer '
            [.[] | select(.version | test("^[0-9]+(\\.[0-9]+)+$"))]
            | sort_by(.version | split(".") | map(tonumber))
            | last // error("No valid installer found")') || {
                log_error "No valid Quilt installer version found"
                return 1
            }

            installer_ver=$(printf '%s' "$installer" | jq -er '.version')
            loader_archive="quilt-installer-$installer_ver.jar"
            loader_url=$(printf '%s' "$installer" | jq -er '.url')
        ;;

        # ====================================================================================== #

        # Paper Server
        paper)
            loader_name="Paper"
            loader_archive="paper-${mc_ver}-${loader_ver}.jar"
            api_url="https://fill.papermc.io/v3/projects/paper/versions/$mc_ver/builds"

            # Get Paper build download URL
            builds=$(curl -fsSL -H "User-Agent: MinecraftServerSetup/1.0 (https://github.com/)" "$api_url") || {
                log_error "Failed to retrieve Paper builds for Minecraft $mc_ver"
                return 1
            }

            build=$(printf '%s' "$builds" | jq -cer --arg build "$loader_ver" '
            [.[] | select((.id | tostring) == $build)]
            | first // error("Build not found")') || {
                log_error "Paper build '$loader_ver' not found for Minecraft $mc_ver"
                return 1
            }

            loader_url=$(printf '%s' "$build" | jq -er '."downloads"."server:default".url') || {
                log_error "Paper download URL not found for build $loader_ver"
                return 1
            }
        ;;

        # ====================================================================================== #

        *)
            log_error "unsupported Minecraft mod loader $loader"
            return 1
        ;;
    esac

    # Build local loader paths
    loader_jar="$ROOT/$loader_archive"
    libraries_dir="$ROOT/libraries"


    # Download loader archive if not already present
    if [ ! -f "$loader_jar" ]; then
        file_download "$loader_jar" "$loader_url" || return 1
    fi


    # Install loader if not already installed
    if [ ! -d "$libraries_dir" ]; then

        # Validate Java executable
        if [ ! -f "$JAVA_EXE" ]; then
            log_error "java executable not found: '$JAVA_EXE'."
            return 1
        fi

        # Run the appropriate command based on the loader type
        if [ "$loader" != "vanilla" ] && [ "$loader" != "paper" ]; then
            log_info "installing $loader_name"

            case "$loader" in
                forge|neoforge)
                    "$JAVA_EXE" -jar "$loader_jar" --installServer || {
                        exit_code=$?
                        log_error "$loader_name installation failed with exit code $exit_code."
                        return 1
                    }
                ;;

                fabric)
                    "$JAVA_EXE" -jar "$loader_jar" server \
                    -mcversion "$mc_ver" \
                    -loader "$loader_ver" \
                    -dir "$ROOT" \
                    -downloadMinecraft || {
                        exit_code=$?
                        log_error "$loader_name installation failed with exit code $exit_code."
                        return 1
                    }
                ;;

                quilt)
                    "$JAVA_EXE" -jar "$loader_jar" \
                    install server "$mc_ver" "$loader_ver" \
                    "--install-dir=$ROOT" \
                    --download-server || {
                        exit_code=$?
                        log_error "$loader_name installation failed with exit code $exit_code."
                        return 1
                    }
                ;;

                *)
                    log_error "Unsupported Minecraft loader $loader"
                    return 1
                ;;
            esac

            # Remove default run.* files created by the installer
            rm -f "$ROOT"/run.*

            log_info "Installation completed"
        fi

    else
        log_info "$loader_name already installed"
    fi
}
#endregion