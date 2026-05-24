#!/bin/bash
# ============================================================================
# Hermes Agent - Portable Launcher (macOS / Linux)
# ============================================================================
# Terminal:   ./launch.sh
# macOS Finder: rename this file to "launch.command" for double-click support.
# On first run, it downloads ~600MB of runtime files automatically.
# All data stays in the "data/" folder — nothing touches the host computer.
# ============================================================================

set -e

# Resolve portable root (directory containing this script)
PORTABLE_ROOT="$(cd "$(dirname "$0")" && pwd)"
HERMES_HOME="$PORTABLE_ROOT/data"
CACHE_DIR="$PORTABLE_ROOT/.cache"
SRC_DIR="$PORTABLE_ROOT/src"

# ---------------------------------------------------------------------------
# Detect OS and architecture
# ---------------------------------------------------------------------------
OS_RAW="$(uname -s)"
ARCH_RAW="$(uname -m)"

case "$OS_RAW" in
    Linux*)     PLATFORM="linux" ;;
    Darwin*)    PLATFORM="macos" ;;
    CYGWIN*|MINGW*|MSYS*) PLATFORM="windows" ;;
    *)
        echo "[ERROR] Unsupported operating system: $OS_RAW"
        exit 1
        ;;
esac

case "$ARCH_RAW" in
    x86_64|amd64) ARCH="x64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *)
        echo "[ERROR] Unsupported architecture: $ARCH_RAW"
        exit 1
        ;;
esac

RUNTIME_DIR="$CACHE_DIR/runtimes/${PLATFORM}-${ARCH}"

# ---------------------------------------------------------------------------
# First-run setup
# ---------------------------------------------------------------------------
if [ ! -f "$RUNTIME_DIR/ready.flag" ]; then
    echo ""
    echo "============================================"
    echo "    Hermes Portable - First Run Setup"
    echo "============================================"
    echo "  Platform: ${PLATFORM}-${ARCH}"
    echo "  This will download ~600MB of runtime files."
    echo "  Please be patient."
    echo "============================================"
    echo ""
    bash "$PORTABLE_ROOT/scripts/setup-unix.sh" "$PORTABLE_ROOT"
    if [ $? -ne 0 ]; then
        echo ""
        echo "[ERROR] Setup failed. Please check your internet connection and try again."
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Environment isolation — keep everything inside the portable folder
# ---------------------------------------------------------------------------
export HERMES_HOME="$HERMES_HOME"
export VIRTUAL_ENV="$RUNTIME_DIR/venv"
export PATH="$VIRTUAL_ENV/bin:$RUNTIME_DIR/python/bin:$RUNTIME_DIR/node/bin:$RUNTIME_DIR/uv:$RUNTIME_DIR/bin:$PATH"
export PYTHONNOUSERSITE=1
export PYTHONHOME=""
export PYTHONPATH=""
export UV_NO_CONFIG=1
export UV_PYTHON="$RUNTIME_DIR/python/bin/python3"
export PLAYWRIGHT_BROWSERS_PATH="$RUNTIME_DIR/playwright"
export NODE_PATH="$RUNTIME_DIR/node/lib/node_modules"
export NPM_CONFIG_PREFIX="$RUNTIME_DIR/node"

# Prevent Node/npm from writing to host home directory
export HOME="$PORTABLE_ROOT/.cache/unix-home"
mkdir -p "$HOME"

# Portable Ollama isolation - keep all downloaded GGUF models on the USB drive
export OLLAMA_MODELS="$HERMES_HOME/models"


# ---------------------------------------------------------------------------
# Launch Hermes
# ---------------------------------------------------------------------------
if [ ! -d "$SRC_DIR/hermes-agent" ]; then
    echo "[ERROR] Hermes source not found. Please delete .cache and try again."
    exit 1
fi

cd "$SRC_DIR/hermes-agent"

# Strip "hermes" from the start of arguments if user typed "launch.sh hermes setup"
if [ "$1" = "hermes" ] || [ "$1" = "HERMES" ]; then
    shift
fi

# If explicit arguments were passed, run Hermes directly (skip menu)
if [ $# -gt 0 ]; then
    hermes "$@"
    exit 0
fi

# ---------------------------------------------------------------------------
# ANSI Colors
# ---------------------------------------------------------------------------
ESC='\033'
RESET="${ESC}[0m"
BOLD="${ESC}[1m"
DIM="${ESC}[2m"
CYAN="${ESC}[36m"
BRIGHT_CYAN="${ESC}[96m"
GREEN="${ESC}[32m"
BRIGHT_GREEN="${ESC}[92m"
YELLOW="${ESC}[33m"
BRIGHT_YELLOW="${ESC}[93m"
RED="${ESC}[31m"
BRIGHT_RED="${ESC}[91m"
WHITE="${ESC}[37m"
BRIGHT_WHITE="${ESC}[97m"
GRAY="${ESC}[90m"

# ---------------------------------------------------------------------------
# Status Detection
# ---------------------------------------------------------------------------
detect_status() {
    SETUP_STATUS="Not configured"
    SETUP_ICON="[x]"
    SETUP_COLOR="$RED"
    PROVIDER_NAME=""
    MODEL_NAME=""

    if [ -f "$HERMES_HOME/.env" ] && grep -q '^[A-Z].*=' "$HERMES_HOME/.env"; then
        SETUP_STATUS="Configured"
        SETUP_ICON="[OK]"
        SETUP_COLOR="$BRIGHT_GREEN"
    fi

    if [ -f "$HERMES_HOME/config.yaml" ]; then
        PROVIDER_NAME=$(grep '^  provider:' "$HERMES_HOME/config.yaml" | head -n 1 | awk '{print $2}' || true)
        MODEL_NAME=$(grep '^  default:' "$HERMES_HOME/config.yaml" | head -n 1 | awk '{print $2}' || true)
    fi

    GATEWAY_STATUS="Stopped"
    GATEWAY_ICON="[ ]"
    GATEWAY_COLOR="$GRAY"
    GATEWAY_PID=""

    if [ -f "$HERMES_HOME/gateway.pid" ]; then
        GATEWAY_PID=$(grep -o '"pid":[0-9]*' "$HERMES_HOME/gateway.pid" | grep -o '[0-9]*' || true)
    fi

    if [ -n "$GATEWAY_PID" ]; then
        if kill -0 "$GATEWAY_PID" 2>/dev/null; then
            GATEWAY_STATUS="Running (PID $GATEWAY_PID)"
            GATEWAY_ICON="[OK]"
            GATEWAY_COLOR="$BRIGHT_GREEN"
        else
            GATEWAY_STATUS="Stopped (stale lock)"
            GATEWAY_ICON="[!]"
            GATEWAY_COLOR="$YELLOW"
        fi
    fi

    HERMES_VERSION="unknown"
    if [ -f "$SRC_DIR/hermes-agent/hermes_cli/__init__.py" ]; then
        HERMES_VERSION=$(grep '__version__' "$SRC_DIR/hermes-agent/hermes_cli/__init__.py" | head -n 1 | sed 's/.*"\(.*\)".*/\1/')
    fi
}

# ---------------------------------------------------------------------------
# Main Menu
# ---------------------------------------------------------------------------
show_menu() {
    clear
    echo ""
    echo -e "${BRIGHT_CYAN}----------------------------------------------------------------${RESET}"
    echo -e "${BOLD}${BRIGHT_WHITE}                    HERMES PORTABLE LAUNCHER${RESET}"
    echo -e "${DIM}${GRAY}                         AI Agent for Everyone${RESET}"
    echo -e "${BRIGHT_CYAN}----------------------------------------------------------------${RESET}"
    echo ""
    echo -e " ${DIM}Setup${RESET}    ${SETUP_COLOR}${SETUP_ICON}${RESET} ${WHITE}${SETUP_STATUS}${RESET}"
    [ -n "$PROVIDER_NAME" ] && echo -e " ${DIM}Provider${RESET} ${CYAN}${PROVIDER_NAME}${RESET}"
    [ -n "$MODEL_NAME" ] && echo -e " ${DIM}Model${RESET}    ${WHITE}${MODEL_NAME}${RESET}"
    echo -e " ${DIM}Gateway${RESET}  ${GATEWAY_COLOR}${GATEWAY_ICON}${RESET} ${WHITE}${GATEWAY_STATUS}${RESET}"
    echo -e " ${DIM}Version${RESET}  ${GRAY}v${HERMES_VERSION}${RESET}"
    echo ""
    echo -e "${BRIGHT_CYAN}----------------------------------------------------------------${RESET}"
    echo ""
    echo -e "  ${BRIGHT_YELLOW}[1]${RESET}  ${WHITE}Start Hermes Chat (TUI)${RESET}"
    echo -e "  ${BRIGHT_YELLOW}[2]${RESET}  ${WHITE}Start Web Dashboard (GUI)${RESET}"
    echo -e "  ${BRIGHT_YELLOW}[3]${RESET}  ${WHITE}Setup / Reconfigure Hermes${RESET}"
    if [ "$GATEWAY_STATUS" = "Running (PID $GATEWAY_PID)" ]; then
        echo -e "  ${BRIGHT_YELLOW}[4]${RESET}  ${WHITE}Stop Gateway${RESET}  ${RED}[live]${RESET}"
    else
        echo -e "  ${BRIGHT_YELLOW}[4]${RESET}  ${WHITE}Start Gateway${RESET}"
    fi
    echo -e "  ${BRIGHT_YELLOW}[5]${RESET}  ${WHITE}Advanced Options${RESET}  ${GRAY}-->${RESET}"
    echo -e "  ${BRIGHT_YELLOW}[6]${RESET}  ${GRAY}Exit${RESET}"
    echo ""
    echo -e "${BRIGHT_CYAN}----------------------------------------------------------------${RESET}"
    echo ""
    read -p "$(echo -e "${BRIGHT_CYAN}Select option: ${RESET}")" choice

    case "$choice" in
        1) menu_chat ;;
        2) menu_dashboard ;;
        3) menu_setup ;;
        4) menu_gateway ;;
        5) show_advanced ;;
        6) menu_exit ;;
        *) show_menu ;;
    esac
}

menu_chat() {
    clear
    if ! check_ollama; then
        show_menu
        return
    fi
    
    LLAMAFILE_RUNNING=0
    LLAMAFILE_EXE="$HERMES_HOME/bin/llamafile"
    LOCAL_SERVE=0
    
    if [ -f "$HERMES_HOME/config.yaml" ]; then
        if grep -q "provider: custom" "$HERMES_HOME/config.yaml" 2>/dev/null; then
            if grep -q "base_url: http://127.0.0.1:8080" "$HERMES_HOME/config.yaml" 2>/dev/null; then
                if [ -f "$LLAMAFILE_EXE" ]; then
                    LOCAL_SERVE=1
                fi
            fi
        fi
    fi
    
    if [ "$LOCAL_SERVE" -eq 1 ]; then
        MODEL_PATH=""
        for f in "$HERMES_HOME"/models/*.gguf; do
            if [ -z "$MODEL_PATH" ] && [ -f "$f" ]; then
                MODEL_PATH="$f"
            fi
        done
        if [ -n "$MODEL_PATH" ]; then
            echo -e "${CYAN}Starting local llamafile server with model: $MODEL_PATH${RESET}"
            chmod +x "$LLAMAFILE_EXE" 2>/dev/null || true
            "$LLAMAFILE_EXE" --server --host 127.0.0.1 --port 8080 --model "$MODEL_PATH" --nobrowser >/dev/null 2>&1 &
            LLAMAFILE_PID=$!
            LLAMAFILE_RUNNING=1
            sleep 3
        else
            echo -e "${YELLOW}[WARN] Llamafile executable found, but no .gguf models found in data/models/${RESET}"
        fi
    fi
    
    hermes
    
    if [ "$LLAMAFILE_RUNNING" -eq 1 ]; then
        echo -e "${CYAN}Stopping local llamafile server ...${RESET}"
        kill -9 "$LLAMAFILE_PID" 2>/dev/null || true
    fi
    show_menu
}

menu_dashboard() {
    clear
    echo -e "${CYAN}Starting premium Web Dashboard...${RESET}"
    echo -e "${GRAY}(Vite/React frontend is fully optimized for mobile, tablet, and laptop)${RESET}"
    echo ""
    if ! check_ollama; then
        show_menu
        return
    fi
    hermes dashboard
    show_menu
}

check_ollama() {
    OLLAMA_OFFLINE=0
    if [ -f "$HERMES_HOME/config.yaml" ]; then
        if grep -q "base_url: http://127.0.0.1:11434" "$HERMES_HOME/config.yaml" 2>/dev/null; then
            echo "Checking if local Ollama server is running on port 11434..."
            if ! nc -z 127.0.0.1 11434 2>/dev/null && ! curl -s http://127.0.0.1:11434 >/dev/null; then
                OLLAMA_OFFLINE=1
            fi
        fi
    fi
    if [ "$OLLAMA_OFFLINE" -eq 1 ]; then
        echo -e "${YELLOW}[WARN] Local Ollama server is not running on port 11434!${RESET}"
        echo "Please make sure Ollama is started on the host system,"
        echo "and that you have pulled the model by running:"
        echo "  ollama pull qwen2.5-coder:1.5b"
        echo ""
        read -p "$(echo -e "${BRIGHT_YELLOW}Do you want to continue anyway? [y/N]: ${RESET}")" yn
        case "$yn" in
            [Yy]* ) return 0 ;;
            * ) return 1 ;;
        esac
    fi
    return 0
}

menu_setup() {
    clear
    echo -e "${BRIGHT_CYAN}----------------------------------------------------------------${RESET}"
    echo -e "${BOLD}${BRIGHT_WHITE}                  Hermes Setup Configuration${RESET}"
    echo -e "${BRIGHT_CYAN}----------------------------------------------------------------${RESET}"
    echo " Choose how you want to run Hermes:"
    echo ""
    echo -e "  ${BRIGHT_YELLOW}[1]${RESET}  ${WHITE}Local Ollama Server (Recommended - GPU Accelerated)${RESET}"
    echo -e "  ${BRIGHT_YELLOW}[2]${RESET}  ${WHITE}Local USB Model (Offline - CPU served from USB)${RESET}"
    echo -e "  ${BRIGHT_YELLOW}[3]${RESET}  ${WHITE}Online Providers (Cloud APIs: OpenRouter, DeepSeek, etc.)${RESET}"
    echo -e "  ${BRIGHT_YELLOW}[4]${RESET}  ${GRAY}Back to Main Menu${RESET}"
    echo -e "${BRIGHT_CYAN}----------------------------------------------------------------${RESET}"
    echo ""
    read -p "$(echo -e "${BRIGHT_CYAN}Select option: ${RESET}")" choice
    
    case "$choice" in
        1) setup_ollama_local ;;
        2) setup_usb_local ;;
        3) setup_online ;;
        4) show_menu ;;
        *) menu_setup ;;
    esac
}

setup_online() {
    clear
    hermes setup
    detect_status
    show_menu
}

setup_ollama_local() {
    clear
    OLLAMA_EXE="$HERMES_HOME/bin/ollama"
    PORTABLE_OLLAMA_EXISTS=1
    if [ "$PLATFORM" = "macos" ]; then
        OLLAMA_EXE="$HERMES_HOME/bin/Ollama.app/Contents/Resources/ollama"
    fi

    if [ ! -f "$OLLAMA_EXE" ]; then
        PORTABLE_OLLAMA_EXISTS=0
        if [ "$PLATFORM" = "macos" ]; then
            if [ -f "/usr/local/bin/ollama" ]; then
                OLLAMA_EXE="/usr/local/bin/ollama"
            elif [ -f "/Applications/Ollama.app/Contents/Resources/ollama" ]; then
                OLLAMA_EXE="/Applications/Ollama.app/Contents/Resources/ollama"
            elif command -v ollama >/dev/null 2>&1; then
                OLLAMA_EXE="ollama"
            fi
        else
            if command -v ollama >/dev/null 2>&1; then
                OLLAMA_EXE="ollama"
            fi
        fi
    fi

    if ! command -v "$OLLAMA_EXE" >/dev/null 2>&1 && [ ! -f "$OLLAMA_EXE" ]; then
        echo ""
        echo -e "${YELLOW}[INFO] Local Ollama CLI was not found on your system.${RESET}"
        echo "We can automatically download and set up a 100% PORTABLE Ollama server"
        echo "directly inside your USB drive (~170 MB). All GGUF models and data will be"
        echo "saved on the USB drive, keeping your host computer completely clean!"
        echo ""
        read -p "$(echo -e "${BRIGHT_YELLOW}Do you want to download portable Ollama now? [y/N]: ${RESET}")" yn
        case "$yn" in
            [Yy]* ) ;;
            * )
                echo "Setup cancelled. Returning to setup menu."
                read -p "Press Enter to continue ..."
                menu_setup
                return
                ;;
        esac
        
        echo ""
        echo -e "${CYAN}Downloading portable Ollama (~170 MB) to USB drive...${RESET}"
        echo "Please keep this terminal open."
        echo ""
        mkdir -p "$HERMES_HOME/bin"
        
        if [ "$PLATFORM" = "macos" ]; then
            echo "Downloading Ollama macOS App ZIP..."
            curl -L -o "$HERMES_HOME/bin/Ollama-darwin.zip" "https://ollama.com/download/Ollama-darwin.zip"
            if [ $? -eq 0 ]; then
                echo "Extracting Ollama.app..."
                unzip -q -o "$HERMES_HOME/bin/Ollama-darwin.zip" -d "$HERMES_HOME/bin/"
                rm -f "$HERMES_HOME/bin/Ollama-darwin.zip"
                OLLAMA_EXE="$HERMES_HOME/bin/Ollama.app/Contents/Resources/ollama"
                PORTABLE_OLLAMA_EXISTS=1
            else
                echo -e "${RED}[ERROR] Download failed. Please check your internet connection.${RESET}"
                read -p "Press Enter to continue ..."
                menu_setup
                return
            fi
        else
            # Linux
            echo "Downloading Ollama Linux raw binary..."
            LINUX_ARCH="amd64"
            if [ "$ARCH" = "arm64" ]; then LINUX_ARCH="arm64"; fi
            curl -L -o "$HERMES_HOME/bin/ollama" "https://ollama.com/download/ollama-linux-${LINUX_ARCH}"
            if [ $? -eq 0 ]; then
                chmod +x "$HERMES_HOME/bin/ollama"
                OLLAMA_EXE="$HERMES_HOME/bin/ollama"
                PORTABLE_OLLAMA_EXISTS=1
            else
                echo -e "${RED}[ERROR] Download failed. Please check your internet connection.${RESET}"
                read -p "Press Enter to continue ..."
                menu_setup
                return
            fi
        fi
        echo -e "${BRIGHT_GREEN}✓ Portable Ollama successfully installed!${RESET}"
    fi

    echo "Checking if local Ollama server is running on port 11434..."
    if ! nc -z 127.0.0.1 11434 2>/dev/null && ! curl -s http://127.0.0.1:11434 >/dev/null; then
        echo -e "${YELLOW}Ollama is not running. Attempting to start local Ollama server...${RESET}"
        if [ "$PORTABLE_OLLAMA_EXISTS" -eq 1 ]; then
            echo "Starting portable Ollama CLI serve..."
            "$OLLAMA_EXE" serve >/dev/null 2>&1 &
        else
            if [ "$PLATFORM" = "macos" ]; then
                echo "Starting Ollama macOS App..."
                open -a Ollama 2>/dev/null || "$OLLAMA_EXE" serve >/dev/null 2>&1 &
            else
                # Linux
                echo "Starting Ollama service..."
                if systemctl --user is-failed ollama >/dev/null 2>&1 || systemctl --user is-active ollama >/dev/null 2>&1; then
                    systemctl --user start ollama >/dev/null 2>&1 || "$OLLAMA_EXE" serve >/dev/null 2>&1 &
                elif systemctl is-failed ollama >/dev/null 2>&1 || systemctl is-active ollama >/dev/null 2>&1; then
                    sudo systemctl start ollama >/dev/null 2>&1 || "$OLLAMA_EXE" serve >/dev/null 2>&1 &
                else
                    "$OLLAMA_EXE" serve >/dev/null 2>&1 &
                fi
            fi
        fi
        echo "Waiting 5 seconds for server startup..."
        sleep 5
        
        if ! nc -z 127.0.0.1 11434 2>/dev/null && ! curl -s http://127.0.0.1:11434 >/dev/null; then
            echo ""
            echo -e "${RED}[ERROR] Could not start or connect to Ollama server. Please verify it is installed and running.${RESET}"
            read -p "Press Enter to continue ..."
            menu_setup
            return
        else
            echo -e "${BRIGHT_GREEN}✓ Ollama server successfully started!${RESET}"
        fi
    else
        echo -e "${BRIGHT_GREEN}✓ Local Ollama server is already running!${RESET}"
    fi

    RECS=$(python3 "$PORTABLE_ROOT/scripts/detect_system.py" --recommend-tags 2>/dev/null || python "$PORTABLE_ROOT/scripts/detect_system.py" --recommend-tags 2>/dev/null || echo "")

    M1_LABEL="Qwen 2.5 Coder 1.5B   (qwen2.5-coder:1.5b)"
    M2_LABEL="Qwen 2.5 Coder 7B      (qwen2.5-coder:7b)"
    M3_LABEL="Gemma 4 E2B             (gemma4:e2b)"
    M4_LABEL="Gemma 4 E4B             (gemma4:e4b)"
    M5_LABEL="DeepSeek-Coder 1.3B     (deepseek-coder:1.3b)"
    M6_LABEL="DeepSeek-Coder 6.7B     (deepseek-coder:6.7b)"

    if echo "$RECS" | grep -q "qwen2.5-coder:1.5b"; then M1_LABEL="${M1_LABEL} ${BRIGHT_GREEN}(Recommended)${RESET}"; fi
    if echo "$RECS" | grep -q "qwen2.5-coder:7b"; then M2_LABEL="${M2_LABEL} ${BRIGHT_GREEN}(Recommended)${RESET}"; fi
    if echo "$RECS" | grep -q "gemma4:e2b"; then M3_LABEL="${M3_LABEL} ${BRIGHT_GREEN}(Recommended)${RESET}"; fi
    if echo "$RECS" | grep -q "gemma4:e4b"; then M4_LABEL="${M4_LABEL} ${BRIGHT_GREEN}(Recommended)${RESET}"; fi
    if echo "$RECS" | grep -q "deepseek-coder:1.3b"; then M5_LABEL="${M5_LABEL} ${BRIGHT_GREEN}(Recommended)${RESET}"; fi
    if echo "$RECS" | grep -q "deepseek-coder:6.7b"; then M6_LABEL="${M6_LABEL} ${BRIGHT_GREEN}(Recommended)${RESET}"; fi

    while true; do
        clear
        echo -e "${BRIGHT_CYAN}----------------------------------------------------------------${RESET}"
        echo -e "${BOLD}${BRIGHT_WHITE}                  Select Local Ollama Model${RESET}"
        echo -e "${BRIGHT_CYAN}----------------------------------------------------------------${RESET}"
        echo " Select the model you wish to use. Recommended models are highlighted."
        echo ""
        echo -e "  ${BRIGHT_YELLOW}[1]${RESET}  $M1_LABEL"
        echo -e "  ${BRIGHT_YELLOW}[2]${RESET}  $M2_LABEL"
        echo -e "  ${BRIGHT_YELLOW}[3]${RESET}  $M3_LABEL"
        echo -e "  ${BRIGHT_YELLOW}[4]${RESET}  $M4_LABEL"
        echo -e "  ${BRIGHT_YELLOW}[5]${RESET}  $M5_LABEL"
        echo -e "  ${BRIGHT_YELLOW}[6]${RESET}  $M6_LABEL"
        echo -e "  ${BRIGHT_YELLOW}[7]${RESET}  ${GRAY}Cancel setup (Back to menu)${RESET}"
        echo -e "${BRIGHT_CYAN}----------------------------------------------------------------${RESET}"
        echo ""
        read -p "$(echo -e "${BRIGHT_CYAN}Select option: ${RESET}")" choice
        
        case "$choice" in
            1) MODEL_TAG="qwen2.5-coder:1.5b"; break ;;
            2) MODEL_TAG="qwen2.5-coder:7b"; break ;;
            3) MODEL_TAG="gemma4:e2b"; break ;;
            4) MODEL_TAG="gemma4:e4b"; break ;;
            5) MODEL_TAG="deepseek-coder:1.3b"; break ;;
            6) MODEL_TAG="deepseek-coder:6.7b"; break ;;
            7) menu_setup; return ;;
            *) ;;
        esac
    done

    echo ""
    echo -e "${CYAN}Pulling local model: $MODEL_TAG...${RESET}"
    echo "Running: \"$OLLAMA_EXE\" pull $MODEL_TAG"
    "$OLLAMA_EXE" pull "$MODEL_TAG"
    if [ $? -ne 0 ]; then
        echo ""
        echo -e "${RED}[ERROR] Failed to pull model '$MODEL_TAG'. Please check internet connection.${RESET}"
        read -p "Press Enter to continue ..."
        menu_setup
        return
    fi
    echo -e "${BRIGHT_GREEN}✓ Model successfully pulled!${RESET}"
    echo ""
    echo -e "${CYAN}Configuring Hermes to use local Ollama model \"$MODEL_TAG\"...${RESET}"
    hermes config set model.provider custom
    hermes config set model.base_url http://127.0.0.1:11434/v1
    hermes config set model.default "$MODEL_TAG"
    echo -e "${BRIGHT_GREEN}✓ Configuration updated successfully!${RESET}"
    read -p "Press Enter to continue ..."
    detect_status
    show_menu
}

setup_usb_local() {
    clear
    LLAMAFILE_EXE="$HERMES_HOME/bin/llamafile"
    MODEL_FILE="$HERMES_HOME/models/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf"
    DOWNLOAD_REQUIRED=0
    
    if [ ! -f "$LLAMAFILE_EXE" ]; then DOWNLOAD_REQUIRED=1; fi
    if [ ! -f "$MODEL_FILE" ]; then DOWNLOAD_REQUIRED=1; fi
    
    if [ "$DOWNLOAD_REQUIRED" -eq 1 ]; then
        echo -e "${YELLOW}[INFO] Local model assets are missing from the USB drive.${RESET}"
        echo "This setup requires downloading:"
        echo "  - Llamafile runner (~35 MB)"
        echo "  - Qwen2.5-Coder-1.5B model (~1.0 GB)"
        echo ""
        read -p "$(echo -e "${BRIGHT_YELLOW}Do you want to download these files now? [y/N]: ${RESET}")" yn
        case "$yn" in
            [Yy]* ) ;;
            * )
                echo "Setup cancelled. Returning to setup menu."
                read -p "Press Enter to continue ..."
                menu_setup
                return
                ;;
        esac
        
        echo ""
        echo -e "${CYAN}Downloading local AI assets to USB drive...${RESET}"
        echo "Please keep this terminal open."
        echo ""
        mkdir -p "$HERMES_HOME/bin" "$HERMES_HOME/models"
        
        echo "Downloading llamafile ..."
        curl -L -o "$LLAMAFILE_EXE" "https://github.com/mozilla-ai/llamafile/releases/download/0.10.1/llamafile-0.10.1"
        chmod +x "$LLAMAFILE_EXE"
        
        echo "Downloading Qwen2.5-Coder-1.5B ..."
        curl -L -o "$MODEL_FILE" "https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf"
        
        if [ $? -ne 0 ]; then
            echo ""
            echo -e "${RED}[ERROR] Download failed. Please check your internet connection.${RESET}"
            read -p "Press Enter to continue ..."
            menu_setup
            return
        fi
        echo -e "${BRIGHT_GREEN}✓ Download completed successfully!${RESET}"
    fi
    
    echo ""
    echo -e "${CYAN}Configuring Hermes to use local USB model...${RESET}"
    hermes config set model.provider custom
    hermes config set model.base_url http://127.0.0.1:8080/v1
    hermes config set model.default qwen2.5-coder-1.5b-instruct-q4_k_m.gguf
    echo -e "${BRIGHT_GREEN}✓ Configuration updated!${RESET}"
    read -p "Press Enter to continue ..."
    detect_status
    show_menu
}

menu_gateway() {
    if [ "$GATEWAY_STATUS" = "Running (PID $GATEWAY_PID)" ]; then
        hermes gateway stop
        echo ""
        echo -e "${BRIGHT_GREEN}Gateway stopped.${RESET}"
    else
        echo ""
        echo -e "${CYAN}Starting gateway in background ...${RESET}"
        hermes gateway &
        sleep 2
    fi
    read -p "Press Enter to continue ..."
    detect_status
    show_menu
}

menu_exit() {
    clear
    echo ""
    echo -e "${GRAY}Goodbye!${RESET}"
    echo ""
    exit 0
}

# ---------------------------------------------------------------------------
# Advanced Menu
# ---------------------------------------------------------------------------
show_advanced() {
    clear
    echo ""
    echo -e "${BRIGHT_CYAN}----------------------------------------------------------------${RESET}"
    echo -e "${BOLD}${BRIGHT_WHITE}                       Advanced Options${RESET}"
    echo -e "${BRIGHT_CYAN}----------------------------------------------------------------${RESET}"
    echo ""
    echo -e "  ${BRIGHT_YELLOW}[1]${RESET}  ${WHITE}Run Doctor${RESET}            ${GRAY}- check for issues${RESET}"
    echo -e "  ${BRIGHT_YELLOW}[2]${RESET}  ${WHITE}View Logs${RESET}             ${GRAY}- last 20 lines${RESET}"
    echo -e "  ${BRIGHT_YELLOW}[3]${RESET}  ${WHITE}Edit Config${RESET}           ${GRAY}- open in editor${RESET}"
    echo -e "  ${BRIGHT_YELLOW}[4]${RESET}  ${WHITE}Restart Gateway${RESET}       ${GRAY}- stop + start${RESET}"
    echo -e "  ${BRIGHT_YELLOW}[5]${RESET}  ${WHITE}Update Hermes${RESET}         ${GRAY}- fetch latest${RESET}"
    echo -e "  ${BRIGHT_YELLOW}[6]${RESET}  ${GRAY}Back to Main Menu${RESET}"
    echo ""
    echo -e "${BRIGHT_CYAN}----------------------------------------------------------------${RESET}"
    echo ""
    read -p "$(echo -e "${BRIGHT_CYAN}Select option: ${RESET}")" choice

    case "$choice" in
        1) adv_doctor ;;
        2) adv_logs ;;
        3) adv_config ;;
        4) adv_restart ;;
        5) adv_update ;;
        6) show_menu ;;
        *) show_advanced ;;
    esac
}

adv_doctor() {
    clear
    hermes doctor
    read -p "Press Enter to continue ..."
    show_advanced
}

adv_logs() {
    clear
    if [ -f "$HERMES_HOME/logs/gateway.log" ]; then
        echo -e "${CYAN}=== Gateway Log (last 20 lines) ===${RESET}"
        tail -n 20 "$HERMES_HOME/logs/gateway.log"
    else
        echo -e "${YELLOW}No logs found.${RESET}"
    fi
    echo ""
    read -p "Press Enter to continue ..."
    show_advanced
}

adv_config() {
    clear
    hermes config edit
    show_advanced
}

adv_restart() {
    hermes gateway restart
    echo ""
    echo -e "${BRIGHT_GREEN}Gateway restarted.${RESET}"
    read -p "Press Enter to continue ..."
    detect_status
    show_menu
}

adv_update() {
    clear
    hermes update
    read -p "Press Enter to continue ..."
    show_advanced
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
detect_status
show_menu
