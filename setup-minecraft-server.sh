#!/usr/bin/env bash

GAME_VERSIONS="https://meta.fabricmc.net/v2/versions/game"
LOADER_VERSIONS="https://meta.fabricmc.net/v2/versions/loader/"
INSTALLER_VERSIONS="https://meta.fabricmc.net/v2/versions/installer"
MANAGER="https://api.github.com/repos/Edenhofer/minecraft-server/tags"
tmpdir="${TMPDIR:-/tmp}"
workdir="${tmpdir}/minecraft-server"

# Check for dependencies
if ! command -v jq &> /dev/null; then
    echo "Error: 'jq' is required but not installed."
    exit 1
fi

if ! command -v fzf &> /dev/null; then
    echo "Error: 'fzf' is required but not installed."
    echo "Install it from https://github.com/junegunn/fzf or your package manager."
    exit 1
fi


print_help() {
    echo "Usage: $0 -n|--name <name> [--update]"
    echo
    echo "Options:"
    echo "  -n, --name    Specify the name (required)"
    echo "  -p, --port    Specify the server port (default 25565)"
    echo "  -r, --ram     Specify the RAM amount in GB (default 4)"
    echo "  -h, --help    Display this help message and exit"
}

# Default values
name=""
port="25565"
ram="4"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--name)
            if [[ -n "$2" && ! "$2" =~ ^- ]]; then
                name="$2"
                shift 2
            else
                echo "Error: --name requires a non-empty argument."
                exit 1
            fi
            ;;
        -p|--port)
            if [[ -n "$2" && ! "$2" =~ ^- ]]; then
                port="$2"
                shift 2
            else
                echo "Error: --port requires a non-empty argument."
                exit 1
            fi
            ;;
        -r|--ram)
            if [[ -n "$2" && ! "$2" =~ ^- ]]; then
                ram="$2"
                shift 2
            else
                echo "Error: --ram requires a non-empty argument."
                exit 1
            fi
            ;;
        -h|--help)
            print_help
            exit 0
            ;;
        *)
            echo "Error: Unknown option: $1"
            print_help
            exit 1
            ;;
    esac
done

if [[ -z "$name" ]]; then
    echo "Error: --name is required."
    print_help
    exit 1
fi

ram_mb=$((ram * 1024))

# Fetch and parse versions
game_versions=$(curl -s "$GAME_VERSIONS" | jq -r '.[] | "\(.version) (\(if .stable then "stable" else "snapshot" end))"')

# Let user fuzzy-select a version
selected=$(echo "$game_versions" | fzf --prompt="Select a Minecraft version: ")

# Extract just the version string
game_version=$(echo "$selected" | awk '{print $1}')

if [ -z "$game_version" ]; then
    echo "No version selected."
    exit 1
fi

loader_version=$(curl -s "${LOADER_VERSIONS}${game_version}" | jq -r '.[] | select(.loader.stable == true) | .loader.version' | head -n 1)

installer_version=$(curl -s "$INSTALLER_VERSIONS" | jq -r '.[] | select(.stable == true) | .version' | head -n 1)

manager_version=$(curl -s "$MANAGER" | jq -r '.[] | .name' | head -n 1)
manager_version=${manager_version:1}

# create working dir
mkdir -p "${workdir}"

# Download manager
cd "${workdir}" || exit 1
curl -sSLO "https://github.com/Edenhofer/minecraft-server/archive/refs/tags/v${manager_version}.tar.gz"
curl -OJ "https://meta.fabricmc.net/v2/versions/loader/${game_version}/${loader_version}/${installer_version}/server/jar"
tar -xf "v${manager_version}.tar.gz"

server_jar="$(ls ./*.jar)"
server_root="/srv/${name}"

make -C "${workdir}/minecraft-server-${manager_version}" \
	GAME="${name}" \
	INAME="${name}"d \
    GAME_PORT="${port}" \
	SERVER_ROOT="${server_root}" \
	GAME_USER="${name}" \
	MAIN_EXECUTABLE="${server_jar}" \
	SERVER_START_CMD="java -Xms${ram_mb}M -Xmx${ram_mb}M -XX:+AlwaysPreTouch -XX:+DisableExplicitGC -XX:+ParallelRefProcEnabled -XX:+PerfDisableSharedMem -XX:+UnlockExperimentalVMOptions -XX:+UseG1GC -XX:G1HeapRegionSize=8M -XX:G1HeapWastePercent=5 -XX:G1MaxNewSizePercent=40 -XX:G1MixedGCCountTarget=4 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1NewSizePercent=30 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:G1ReservePercent=20 -XX:InitiatingHeapOccupancyPercent=15 -XX:MaxGCPauseMillis=200 -XX:MaxTenuringThreshold=1 -XX:SurvivorRatio=32 -Dusing.aikars.flags=https://mcflags.emc.gs -Daikars.new.flags=true -jar './\$\${MAIN_EXECUTABLE}' nogui" \
	clean
make -C "${workdir}/minecraft-server-${manager_version}" \
	GAME="${name}" \
	INAME="${name}"d \
    GAME_PORT="${port}" \
	SERVER_ROOT="${server_root}" \
	GAME_USER="${name}" \
	MAIN_EXECUTABLE="${server_jar}" \
	SERVER_START_CMD="java -Xms${ram_mb}M -Xmx${ram_mb}M -XX:+AlwaysPreTouch -XX:+DisableExplicitGC -XX:+ParallelRefProcEnabled -XX:+PerfDisableSharedMem -XX:+UnlockExperimentalVMOptions -XX:+UseG1GC -XX:G1HeapRegionSize=8M -XX:G1HeapWastePercent=5 -XX:G1MaxNewSizePercent=40 -XX:G1MixedGCCountTarget=4 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1NewSizePercent=30 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:G1ReservePercent=20 -XX:InitiatingHeapOccupancyPercent=15 -XX:MaxGCPauseMillis=200 -XX:MaxTenuringThreshold=1 -XX:SurvivorRatio=32 -Dusing.aikars.flags=https://mcflags.emc.gs -Daikars.new.flags=true -jar './\$\${MAIN_EXECUTABLE}' nogui" \
	all

make -C "${workdir}/minecraft-server-${manager_version}" \
	GAME="${name}" \
	INAME="${name}"d \
	install

# Install Fabric
install -Dm644 "${server_jar}" "${server_root}/${server_jar}"

# Link log files
mkdir -p "/var/log/"
install -dm2755 "${server_root}/logs"
ln -s "/srv/${name}/logs" "/var/log/${name}"

if ! getent group "${name}" &>/dev/null; then
    echo "Adding ${name} system group..."
    groupadd -r "$name" 1>/dev/null
fi

if ! getent passwd "$name" &>/dev/null; then
        echo "Adding ${name} system user..."
        useradd -r -g "${name}" -d "$server_root" "$name" 1>/dev/null
fi

# EULA and server.properties
if [ ! -f "${server_root}/eula.txt" ]; then
cat << EOF > "${server_root}/eula.txt"
#By changing the setting below to TRUE you are indicating your agreement to our EULA (https://aka.ms/MinecraftEULA).
#$(date)
eula=true
EOF
fi

if [ ! -f "${server_root}/server.properties" ]; then
cat << EOF > "${server_root}/server.properties"
#Minecraft server properties
#$(date)
allow-flight=false
allow-nether=true
broadcast-console-to-ops=true
broadcast-rcon-to-ops=true
difficulty=easy
enable-command-block=false
enable-jmx-monitoring=false
enable-query=false
enable-rcon=false
enable-status=true
enforce-secure-profile=true
enforce-whitelist=false
entity-broadcast-range-percentage=100
force-gamemode=false
function-permission-level=2
gamemode=survival
generate-structures=true
generator-settings={}
hardcore=false
hide-online-players=false
initial-disabled-packs=
initial-enabled-packs=vanilla
level-name=world
level-seed=
level-type=minecraft\:normal
log-ips=true
max-chained-neighbor-updates=1000000
max-players=20
max-tick-time=60000
max-world-size=29999984
motd=A Minecraft Server
network-compression-threshold=256
online-mode=true
op-permission-level=4
player-idle-timeout=0
prevent-proxy-connections=false
pvp=true
query.port=${port}
rate-limit=0
rcon.password=
rcon.port=$((port + 10))
require-resource-pack=false
resource-pack=
resource-pack-id=
resource-pack-prompt=
resource-pack-sha1=
server-ip=0.0.0.0
server-port=${port}
simulation-distance=10
spawn-animals=true
spawn-monsters=true
spawn-npcs=true
spawn-protection=16
sync-chunk-writes=true
text-filtering-config=
use-native-transport=true
view-distance=10
white-list=false
EOF
fi

chown -R "${name}:${name}" "$server_root"

# Give the group write permissions and set user or group ID on execution
chmod g+ws "${server_root}"

rm -rf "${workdir}"