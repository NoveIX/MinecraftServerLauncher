# Minecraft Server Launcher

A cross-platform launcher for Minecraft servers. It reads server settings from a single configuration file, downloads a local Java runtime when needed, installs the selected server software, and starts the server.

>[!NOTE]
> **Project background**
>
> Originally developed for [Project Anoxia Lunar Ruins](https://github.com/NoveIX/Anoxia), this launcher was later expanded into a standalone project to support a wider range of Minecraft servers. The included configuration is based on Project Anoxia Lunar Ruins and serves as a practical example of how the launcher works.

- Minecraft **1.20.1**
- Forge **47.4.20**
- Java **17**

## Supported server software

The launcher supports:

- Vanilla
- Forge
- NeoForge
- Fabric
- Quilt
- Paper

## Requirements

- An x64 or ARM64 processor and an internet connection when downloading Java or server files.
- **Windows:** Windows PowerShell (`powershell.exe`), used by `startserver.bat`.
- **Linux/macOS:** a POSIX-compatible shell. When Java is downloaded automatically, `tar` and either `curl` or `wget` are needed. To install a server loader, Vanilla, Fabric, Quilt, or Paper require `curl` and `jq`; Forge and NeoForge require either `curl` or `wget` for downloads.

Java does not need to be installed in advance. Unless `JAVA_EXE` points to an existing Java executable, the launcher downloads the configured Temurin runtime from [Adoptium](https://adoptium.net/) into the project directory. An existing Java executable must meet the configured minimum version.

## Getting started

1. Download or clone this repository.
2. Review and, if needed, edit [`server/server.env`](server/server.env).
3. Start the launcher from the project directory:
   - **Windows:** run `startserver.bat`.
   - **Linux/macOS:** run `sh ./startserver.sh`.
4. On the first run, wait for Java and the server files to be downloaded and installed.
5. If Minecraft creates `eula.txt`, read the Minecraft EULA and set `eula=true` to accept it before starting the server again.

The launcher starts Minecraft with `nogui`. Server files, downloaded Java, and libraries are kept in the project directory.

## Configuration

Edit [`server/server.env`](server/server.env) to change the server configuration.

| Variable | Purpose | Included value |
| --- | --- | --- |
| `JAVA_VERSION` | Minimum Java major version; also used when downloading Java | `17` |
| `JAVA_VARIANT` | Java package variant to download, such as `JRE` or `JDK` | `JRE` |
| `JAVA_ARGS` | JVM arguments passed to Java | `@user_jvm_args.txt` |
| `MINECRAFT_VERSION` | Minecraft version | `1.20.1` |
| `MINECRAFT_LOADER` | Server software to install and launch | `FORGE` |
| `MINECRAFT_LOADER_VERSION` | Loader version or Paper build | `47.4.20` |
| `PROJECT_NAME`, `PROJECT_ID`, `PROJECT_ROLE`, `PROJECT_AUTHOR`, `PROJECT_REPOSITORY` | Project metadata; `PROJECT_ID`, `PROJECT_ROLE`, and `MODPACK_VERSION` are shown in the terminal window title to make the running server easier to identify | Anoxia Server v0.3.0 |
| `MODPACK_VERSION` | Modpack version shown in the terminal window title | `0.3.0` |

Use the loader's expected version format when changing `MINECRAFT_LOADER_VERSION`. For example, Forge uses its Forge version, while Paper uses a build number.

### Java arguments

Edit [`user_jvm_args.txt`](user_jvm_args.txt) to change memory allocation and other JVM options. The included file sets the minimum and maximum heap sizes to 8 GB (`-Xms8G` and `-Xmx8G`) and includes Aikar's G1GC flags. Adjust the heap sizes according to the server's requirements and the memory available on the host. Keep JVM options in this file when using Java 17 or newer.

For Java 8, do not use the `@user_jvm_args.txt` argument-file syntax. Put the JVM options directly in the `JAVA_ARGS` value in `server/server.env`, on the same line, separated by spaces. The launcher passes these options to Java when it starts the server. For example:

```env
JAVA_ARGS=-Xms4G -Xmx4G -XX:+UseG1GC
```

### Launcher options

Optional launcher settings are provided as commented lines near the top of `startserver.bat` and `startserver.sh`. These settings are independent of the server configuration file and can be enabled by uncommenting the relevant line in the launcher for your operating system.

- `JAVA_EXE`: path to an existing Java executable. If set, automatic Java download is skipped.
- `INSTALL_ONLY=true`: install missing components and exit without starting the server.
- `SERVER_RESTART=true`: enable automatic restart attempts after the server process exits, with a 10-second delay.

## Test configurations

The following Minecraft 1.21.1 configurations can be used to test the launcher. **Java 21 is required** for Minecraft 1.21.1.

| Server software | Minecraft version | Loader version |
| --- | --- | --- |
| Vanilla | `1.21.1` | — |
| Forge | `1.21.1` | `52.1.20` |
| NeoForge | `1.21.1` | `21.1.265` |
| Fabric | `1.21.1` | `0.20.1` |
| Quilt | `1.21.1` | `0.30.1` |
| Paper | `1.21.1` | `133` |

To try one of these configurations, set `JAVA_VERSION=21`, `MINECRAFT_VERSION=1.21.1`, and the matching `MINECRAFT_LOADER` and `MINECRAFT_LOADER_VERSION` values in `server/server.env`. Vanilla does not use a loader version. Use a separate clean copy of the project for each loader test so an existing `libraries` directory does not cause the launcher to skip installation.

## How it works

1. The launcher loads variables from `server/server.env`.
2. It locates the configured Java runtime or downloads the matching Temurin runtime from Adoptium.
3. It checks that Java meets the configured minimum version.
4. If the `libraries` directory is missing, it downloads the selected server software and runs its installer where required.
5. Unless `INSTALL_ONLY=true` is enabled, it starts the server with the arguments for the selected loader.

Downloads are obtained from the respective official upstream services, including [Adoptium](https://adoptium.net/), [Mojang](https://www.minecraft.net/en-us/download/server), [Forge](https://files.minecraftforge.net/), [NeoForged](https://neoforged.net/), [Fabric](https://fabricmc.net/), [Quilt](https://quiltmc.org/en/), and [PaperMC](https://papermc.io/).

## Project files

- `startserver.bat` and `startserver.sh`: Windows and Unix launchers.
- `server/server.env`: server, Java, and project settings.
- `server/setup.ps1` and `server/setup.sh`: Java and server-software download and installation routines.
- `server/load-env.cmd` and `server/load-env.sh`: load the configuration into the launcher environment.
- `user_jvm_args.txt`: JVM memory and runtime options.
