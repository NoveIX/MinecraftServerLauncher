#!/bin/sh
set -e

# To use a specific Java runtime, set JAVA_EXE to the full path of the Java executable.
# JAVA_EXE="/usr/lib/jvm/java-17-openjdk-amd64/bin/java"

# To enable automatic server restarts, set SERVER_RESTART to true.
# SERVER_RESTART="true"

# To install the server without starting it, set INSTALL_ONLY to true.
# INSTALL_ONLY="true"



# ====================================================================================== #



# Modpack root
ROOT=$(CDPATH= cd -P "$(dirname "$0")" && pwd -P)
ENV="$ROOT/server/server.env"
LOAD="$ROOT/server/load-env.sh"
SETUP="$ROOT/server/setup.sh"
cd "$ROOT"

# Check if load-env.sh exists
if [ ! -f "$LOAD" ]; then
    printf "error: File not found '%s'\n" "$LOAD"
    exit 1
fi

# Load server environment
if ! . "$LOAD"; then
    exit 1
fi

# Terminal title
printf '\033]0;%s %s v%s\007' "$PROJECT_ID" "$PROJECT_ROLE" "$MODPACK_VERSION"

# Check if setup.sh exists
if [ ! -f "$SETUP" ]; then
    printf "error: File not found '%s'\n" "$SETUP"
    exit 1
fi

# Load server environment
if ! . "$SETUP"; then
    exit 1
fi

# Check if Java is available, install it if missing, and set JAVA_EXE variable
if [ -z "$JAVA_EXE" ]; then

    # Check system architecture
    JAVA_ARCH=$(system_arch) || exit 1

    # Check OS
    JAVA_OS=$(java_os) || exit 1

    # Convert Java variant to lowercase
    JAVA_VARIANT_LOWER=$(printf '%s' "$JAVA_VARIANT" | tr '[:upper:]' '[:lower:]')

    # Java installation directory
    JAVA_DIR="$ROOT/java/${JAVA_OS}-${JAVA_ARCH}-${JAVA_VARIANT_LOWER}-${JAVA_VERSION}"

    # macOS Java archives contain Java inside Contents/Home
    if [ "$JAVA_OS" = "mac" ]; then
        JAVA_HOME="$JAVA_DIR/Contents/Home"
    else
        JAVA_HOME="$JAVA_DIR"
    fi

    # Check or install local java
    JAVA_EXE="$JAVA_HOME/bin/java"

    if [ ! -f "$JAVA_EXE" ]; then
        if ! install_java; then
            exit 1
        fi
    fi
fi

# Verify Java availability (file or PATH)
if [ ! -f "$JAVA_EXE" ]; then
    if ! command -v "$JAVA_EXE" >/dev/null 2>&1; then
        log_error "Java not found '$JAVA_EXE'"
        exit 1
    fi
fi

# Check Java version and parse the version string
RAW_VER=$("$JAVA_EXE" -version 2>&1 | awk -F '"' '/version/ {print $2}')
case "$RAW_VER" in
    1.*)
        CTX_VER=${RAW_VER#1.}
        CTX_VER=${CTX_VER%%.*}
    ;;

    *)
        CTX_VER=${RAW_VER%%.*}
    ;;
esac

# Check Java version compatibility with required Minecraft version
if [ "$CTX_VER" -lt "$JAVA_VERSION" ]; then
    printf 'Minecraft %s requires Java %s. Found Java %s\n' \
    "$MINECRAFT_VERSION" "$JAVA_VERSION" "$CTX_VER"
    exit 1
fi

# Check if libraries directory exists, install if missing
if [ ! -d "libraries" ]; then
    if ! install_loader; then
        exit 1
    fi
fi

# Check if running in "Install Only" mode
if [ "${INSTALL_ONLY:-false}" = "true" ]; then
    log_done "Install completed the server will NOT start"
    exit 0
fi

# Start server (auto-restart on crash)
loader=$(printf '%s' "$MINECRAFT_LOADER" | tr '[:upper:]' '[:lower:]')
while true; do
    case "$loader" in
        vanilla)
            # Start vanilla server
            "$JAVA_EXE" $JAVA_ARGS -jar "server-$MINECRAFT_VERSION.jar" nogui
        ;;

        forge)
            # Start Forge server
            "$JAVA_EXE" $JAVA_ARGS "@libraries/net/minecraftforge/forge/$MINECRAFT_VERSION-$MINECRAFT_LOADER_VERSION/unix_args.txt" nogui
        ;;

        neoforge)
            # Start NeoForge server
            "$JAVA_EXE" $JAVA_ARGS "@libraries/net/neoforged/neoforge/$MINECRAFT_LOADER_VERSION/unix_args.txt" nogui
        ;;

        fabric)
            # Start Fabric server
            "$JAVA_EXE" $JAVA_ARGS -jar fabric-server-launch.jar nogui
        ;;

        quilt)
            # Start Quilt server
            "$JAVA_EXE" $JAVA_ARGS -jar quilt-server-launch.jar nogui
        ;;

        paper)
            # Start Paper server
            "$JAVA_EXE" $JAVA_ARGS -jar "paper-$MINECRAFT_VERSION-$MINECRAFT_LOADER_VERSION.jar" nogui
        ;;

        *)
            log_error "Unsupported Minecraft loader: $loader"
            exit 1
        ;;
    esac

    # Restart Server
    if [ "${SERVER_RESTART:-false}" != "true" ]; then
        exit 0
    fi

    printf 'Restarting automatically in 10 seconds (press Ctrl + C to cancel)\n'
    sleep 10
done
