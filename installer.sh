#!/usr/bin/env bash
set -e

RST=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
ITA=$'\033[3m'
HIDE=$'\033[?25l'
SHOW=$'\033[?25h'
CLR=$'\033[K'

CORAL=$'\033[38;2;240;144;130m'
BLUE=$'\033[38;2;77;154;191m'
GOLD=$'\033[38;2;241;190;88m'
TURQ=$'\033[38;2;131;204;210m'
PLUM=$'\033[38;2;180;140;220m'
MINT=$'\033[38;2;120;220;180m'
ROSE=$'\033[38;2;230;120;150m'
WHT=$'\033[38;2;240;240;240m'
GRY=$'\033[38;2;140;145;160m'
DGRY=$'\033[38;2;70;75;90m'
VDGRY=$'\033[38;2;40;45;55m'
RED=$'\033[38;2;230;110;110m'
GRN=$'\033[38;2;120;210;140m'
YEL=$'\033[38;2;240;200;90m'

PROVIDER="devnova-id"
MODEL_ID="yarsya-coder"
MODEL_NAME="yarsya-coder"
CTX_WINDOW="128000"
MAX_TOKENS="16384"
API_KIND="openai-completions"
PI_PKG="@earendil-works/pi-coding-agent"
NVM_VER="v0.40.8"
NODE_TARGET="24"

TTY=/dev/tty
[ -t 1 ] || { echo "installer requires a TTY"; exit 1; }

W()  { printf '%s' "$1" >&"$TTY"; }
WL() { printf '%s\n' "$1" >&"$TTY"; }
WF() { printf "$@" >&"$TTY"; }

# ═══════════════════════════════════════════════════════════════════
# ENVIRONMENT DETECTION
# ═══════════════════════════════════════════════════════════════════
ENV_TYPE=""
ENV_DISTRO=""
ENV_ARCH=""
ENV_SUDO=""
ENV_NODE_METHOD=""
ENV_NODE_LABEL=""
ENV_PKG_MANAGER=""
ENV_IS_TERMUX=0
ENV_IS_PROOT=0
ENV_IS_WSL=0
ENV_IS_CONTAINER=0
ENV_HAS_SUDO=0
ENV_HAS_ROOT=0

detect_environment() {
    ENV_ARCH="$(uname -m)"
    case "$ENV_ARCH" in
        x86_64|amd64)  ENV_ARCH="x64" ;;
        aarch64|arm64) ENV_ARCH="arm64" ;;
        armv7l)        ENV_ARCH="armv7l" ;;
        ppc64le)       ENV_ARCH="ppc64le" ;;
        s390x)         ENV_ARCH="s390x" ;;
    esac

    # ── Termux detection ──────────────────────────────────────────
    if [ -n "${TERMUX_VERSION:-}" ] || [ -n "${TERMUX_APP_PID:-}" ] \
       || [ "${PREFIX:-}" = "/data/data/com.termux/files/usr" ] \
       || [ -d "/data/data/com.termux/files/usr" ]; then
        ENV_IS_TERMUX=1
        ENV_TYPE="termux"
        ENV_DISTRO="termux"
        ENV_PKG_MANAGER="pkg"
        ENV_NODE_METHOD="pkg"
        ENV_NODE_LABEL="pkg (Termux native)"
        return 0
    fi

    # ── proot-distro detection ────────────────────────────────────
    if [ -n "${PROOT_TMP_DIR:-}" ] || [ -n "${PROOT_LOADER:-}" ] \
       || [ -f "/.proot" ] || grep -qi "proot" /proc/1/cmdline 2>/dev/null; then
        ENV_IS_PROOT=1
    fi

    # ── WSL detection ─────────────────────────────────────────────
    if grep -qiE "(microsoft|wsl)" /proc/version 2>/dev/null; then
        ENV_IS_WSL=1
    fi

    # ── Container detection ───────────────────────────────────────
    if [ -f "/.dockerenv" ] || [ -f "/run/.containerenv" ]; then
        ENV_IS_CONTAINER=1
    fi

    # ── Root / sudo ───────────────────────────────────────────────
    if [ "$(id -u)" -eq 0 ]; then
        ENV_HAS_ROOT=1
        ENV_SUDO=""
    elif command -v sudo >/dev/null 2>&1; then
        ENV_HAS_SUDO=1
        ENV_SUDO="sudo"
    fi

    # ── OS + distro ───────────────────────────────────────────────
    case "$(uname -s)" in
        Darwin)
            ENV_TYPE="macos"
            ENV_DISTRO="darwin"
            if command -v brew >/dev/null 2>&1; then
                ENV_PKG_MANAGER="brew"
                ENV_NODE_METHOD="brew"
                ENV_NODE_LABEL="Homebrew"
            else
                ENV_NODE_METHOD="standalone"
                ENV_NODE_LABEL="standalone binary"
            fi
            ;;
        Linux)
            if [ -f /etc/os-release ]; then
                . /etc/os-release
                ENV_DISTRO="${ID:-linux}"
            elif [ -f /etc/alpine-release ]; then
                ENV_DISTRO="alpine"
            elif [ -f /etc/arch-release ]; then
                ENV_DISTRO="arch"
            else
                ENV_DISTRO="linux"
            fi

            case "$ENV_DISTRO" in
                ubuntu|debian|linuxmint|pop|kali|raspbian|armbian)
                    ENV_TYPE="linux"
                    ENV_PKG_MANAGER="apt"
                    ENV_NODE_METHOD="apt"
                    ENV_NODE_LABEL="apt"
                    ;;
                fedora|rhel|centos|rocky|almalinux)
                    ENV_TYPE="linux"
                    ENV_PKG_MANAGER="dnf"
                    ENV_NODE_METHOD="dnf"
                    ENV_NODE_LABEL="dnf"
                    ;;
                arch|manjaro|endeavouros|garuda)
                    ENV_TYPE="linux"
                    ENV_PKG_MANAGER="pacman"
                    ENV_NODE_METHOD="pacman"
                    ENV_NODE_LABEL="pacman"
                    ;;
                alpine)
                    ENV_TYPE="linux"
                    ENV_PKG_MANAGER="apk"
                    ENV_NODE_METHOD="apk"
                    ENV_NODE_LABEL="apk"
                    ;;
                opensuse*|sles)
                    ENV_TYPE="linux"
                    ENV_PKG_MANAGER="zypper"
                    ENV_NODE_METHOD="zypper"
                    ENV_NODE_LABEL="zypper"
                    ;;
                *)
                    ENV_TYPE="linux"
                    ENV_PKG_MANAGER="unknown"
                    ENV_NODE_METHOD="standalone"
                    ENV_NODE_LABEL="standalone binary"
                    ;;
            esac
            ;;
        FreeBSD|OpenBSD|NetBSD)
            ENV_TYPE="bsd"
            ENV_DISTRO="$(uname -s | tr 'A-Z' 'a-z')"
            ENV_PKG_MANAGER="pkg"
            ENV_NODE_METHOD="standalone"
            ENV_NODE_LABEL="standalone binary"
            ;;
        *)
            ENV_TYPE="unknown"
            ENV_DISTRO="unknown"
            ENV_NODE_METHOD="standalone"
            ENV_NODE_LABEL="standalone binary"
            ;;
    esac
}

env_description() {
    local parts="$ENV_TYPE/$ENV_DISTRO"
    [ "$ENV_IS_TERMUX" = 1 ] && parts="termux"
    [ "$ENV_IS_PROOT" = 1 ] && parts="${parts} (proot)"
    [ "$ENV_IS_WSL" = 1 ] && parts="${parts} (wsl)"
    [ "$ENV_IS_CONTAINER" = 1 ] && parts="${parts} (container)"
    printf '%s/%s' "$parts" "$ENV_ARCH"
}

# ═══════════════════════════════════════════════════════════════════
# VISUAL HELPERS (dari v10)
# ═══════════════════════════════════════════════════════════════════
SCRAMBLE_POOL='░▒▓█▄▀▌▐│┤╡╢╖╕╣║╗╝╜╛┐└┴┬├─┼╞╟╚╔╩╦╠═╬╧╨╤╥╙╘╒╓╫╪┘┌'

LOGO_ROWS=(
" ██╗   ██╗ █████╗ ██████╗ ███████╗██╗   ██╗ █████╗ "
" ╚██╗ ██╔╝██╔══██╗██╔══██╗██╔════╝╚██╗ ██╔╝██╔══██╗"
"  ╚████╔╝ ███████║██████╔╝███████╗ ╚████╔╝ ███████║"
"   ╚██╔╝  ██╔══██║██╔══██╗╚════██║  ╚██╔╝  ██╔══██║"
"    ██║   ██║  ██║██║  ██║███████║   ██║   ██║  ██║"
"    ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝"
)
LOGO_COLORS=( "$CORAL" "$BLUE" "$GOLD" "$TURQ" "$PLUM" "$MINT" )

SPIN=( '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏' )
SP_I=0
next_spin() { SP_I=$(( (SP_I + 1) % ${#SPIN[@]} )); printf '%s' "${SPIN[$SP_I]}"; }

boot_sequence() {
    W "$HIDE"
    clear >&"$TTY"
    local checks=(
        "bios ................ yarsya-agent v1.1.0"
        "cpu ................. $ENV_ARCH"
        "kernel .............. $(uname -sr)"
        "shell ............... $(basename "${SHELL:-/bin/sh}")"
        "user ................ ${USER:-$(id -un)}"
        "home ................ $HOME"
        "platform ............ $(env_description)"
        "pkg-manager ......... ${ENV_PKG_MANAGER:-none}"
        "node-method ......... ${ENV_NODE_METHOD:-auto}"
    )
    local i
    for (( i=0; i<${#checks[@]}; i++ )); do
        printf '  %s%s%s\n' "$VDGRY" "${checks[$i]}" "$RST" >&"$TTY"
        sleep 0.035
    done
    printf '  %s─────────────────────────────────────────────────────────%s\n' "$VDGRY" "$RST" >&"$TTY"
    printf '  %s▸ initiating installer...%s\n' "$GRY" "$RST" >&"$TTY"
    sleep 0.35
    printf '\033[2J\033[H' >&"$TTY"
    W "$SHOW"
}

animate_logo() {
    W "$HIDE"
    WL ""
    local i
    for (( i=0; i<6; i++ )); do WL ""; done
    W "\033[7A"

    local total_width=${#LOGO_ROWS[0]}
    local pool_len=${#SCRAMBLE_POOL}
    local frames=26 f j k

    for (( f=0; f<=frames; f++ )); do
        local lock_width=$(( total_width * f / frames ))
        W "\033[6A\r"
        for (( k=0; k<6; k++ )); do
            local line="${LOGO_ROWS[$k]}"
            local line_len=${#line}
            local color="${LOGO_COLORS[$k]}"
            local out=""
            for (( j=0; j<line_len; j++ )); do
                local ch="${line:$j:1}"
                if [ "$ch" = " " ]; then
                    out+=" "
                elif (( j < lock_width )); then
                    out+="${color}${ch}${RST}"
                else
                    local ridx=$(( RANDOM % pool_len ))
                    out+="${VDGRY}${SCRAMBLE_POOL:$ridx:1}${RST}"
                fi
            done
            printf '\r%s%s\n' "$out" "$RST" >&"$TTY"
        done
        sleep 0.035
    done

    W "\033[6A\r"
    for (( k=0; k<6; k++ )); do
        printf '\r%s%s%s\n' "${LOGO_COLORS[$k]}" "${LOGO_ROWS[$k]}" "$RST" >&"$TTY"
    done
    WL ""

    local tag_a="     Yarsya AI Agent Installer"
    local tag_b="     presented by DreamToRealityCreative"
    local l
    for (( l=0; l<${#tag_a}; l++ )); do
        [ "${tag_a:$l:1}" = " " ] && W " " || W "${BOLD}${PLUM}${tag_a:$l:1}${RST}"
        sleep 0.014
    done
    WL ""
    for (( l=0; l<${#tag_b}; l++ )); do
        [ "${tag_b:$l:1}" = " " ] && W " " || W "${DIM}${GRY}${tag_b:$l:1}${RST}"
        sleep 0.008
    done
    WL ""
    WL ""
    W "$SHOW"
}

section() {
    local title="$1"
    WL ""
    WF "  %s▎%s %s%s%s\n" "$PLUM" "$RST" "$BOLD" "$title" "$RST"
    WF "  %s" "$DGRY"
    local i
    for (( i=0; i<54; i++ )); do W "─"; sleep 0.004; done
    WF "%s\n" "$RST"
    WL ""
}

draw_progress() {
    local step="$1" label="$2" sub="$3"
    local width=30 trail=10
    local head=$(( step % (width + trail) ))
    local bar="" i age
    for (( i=0; i<width; i++ )); do
        age=$(( head - i ))
        if (( age >= 0 && age < trail )); then
            case $age in
                0|1) bar="${bar}${GOLD}█" ;;
                2|3) bar="${bar}${CORAL}█" ;;
                4|5) bar="${bar}${PLUM}█" ;;
                6|7) bar="${bar}${BLUE}█" ;;
                *)   bar="${bar}${TURQ}█" ;;
            esac
        else
            bar="${bar}${VDGRY}░"
        fi
    done
    bar="${bar}${RST}"
    local sp; sp=$(next_spin)
    printf '\r%s  %s%s%s %s  %s%s%s  %s%s%s%s' \
        "$CLR" "$TURQ" "$sp" "$RST" "$bar" \
        "$BOLD" "$WHT" "$label" "$DIM" "$GRY" "$sub" "$RST" >&"$TTY"
}

run_with_progress() {
    local label="$1"; shift
    local parser="$1"; shift
    local log; log=$(mktemp)
    "$@" >"$log" 2>&1 &
    local pid=$!
    local step=0 sub=""
    while kill -0 "$pid" 2>/dev/null; do
        if [ -n "$parser" ] && [ -f "$log" ]; then
            local parsed
            parsed=$($parser "$log" 2>/dev/null || true)
            [ -n "$parsed" ] && sub="$parsed"
        fi
        draw_progress "$step" "$label" "$sub"
        step=$(( step + 1 ))
        sleep 0.07
    done
    wait "$pid"; local rc=$?
    printf '\r%s' "$CLR" >&"$TTY"
    if (( rc == 0 )); then
        WF "  %s✓%s  %s%s%s\n" "$GRN" "$RST" "$BOLD" "$label" "$RST"
    else
        WF "  %s✗%s  %s%s%s\n" "$RED" "$RST" "$BOLD" "$label" "$RST"
        WL ""
        sed 's/^/     /' "$log" >&"$TTY"
        rm -f "$log"
        return $rc
    fi
    rm -f "$log"
}

parse_npm_progress() {
    local log="$1"
    local tarballs metadata
    tarballs=$(grep -c 'http fetch GET .*\.tgz' "$log" 2>/dev/null || echo 0)
    metadata=$(grep -c 'http fetch GET .*registry.npmjs.org' "$log" 2>/dev/null || echo 0)
    if (( tarballs > 0 )); then printf 'fetching tarballs (%d)' "$tarballs"
    elif (( metadata > 0 )); then printf 'resolving packages (%d)' "$metadata"
    else printf 'resolving dependencies'; fi
}

parse_pkg_progress() {
    local log="$1"
    local dl
    dl=$(grep -c 'Get:' "$log" 2>/dev/null || echo 0)
    if (( dl > 0 )); then printf 'downloading (%d)' "$dl"
    else printf 'resolving packages'; fi
}

ask() {
    local var="$1" label="$2" hint="$3"
    local val=""
    while [ -z "$val" ]; do
        WF "  %s▸%s %s%s%s\n" "$TURQ" "$RST" "$BOLD" "$label" "$RST"
        [ -n "$hint" ] && WF "    %s%s%s\n" "$DIM$GRY" "$hint" "$RST"
        WF "    %s➜%s " "$GOLD" "$RST"
        IFS= read -r val <"$TTY" || val=""
        if [ -z "$val" ]; then
            WF "    %s✗%s %sfield is required%s\n\n" "$RED" "$RST" "$DIM" "$RST"
        fi
    done
    eval "$var=\$val"
}

ask_secret() {
    local var="$1" label="$2"
    local val=""
    while [ -z "$val" ]; do
        WF "  %s▸%s %s%s%s\n" "$TURQ" "$RST" "$BOLD" "$label" "$RST"
        WF "    %s➜%s " "$GOLD" "$RST"
        IFS= read -rs val <"$TTY" || val=""
        WL ""
        if [ -z "$val" ]; then
            WF "    %s✗%s %sfield is required%s\n\n" "$RED" "$RST" "$DIM" "$RST"
        fi
    done
    eval "$var=\$val"
}

arrow_menu() {
    local prompt="$1"
    local -a options=("Yes" "No")
    local selected=0
    WF "  %s%s%s  " "$BOLD" "$prompt" "$RST"
    printf '\033[s' >&"$TTY"
    while :; do
        printf '\033[u' >&"$TTY"
        local i
        for (( i=0; i<${#options[@]}; i++ )); do
            if (( i == selected )); then
                WF "%s▸ %s%s  " "$GOLD" "${options[$i]}" "$RST"
            else
                WF "%s  %s  " "$DIM$GRY" "${options[$i]}" "$RST"
            fi
        done
        W "$CLR"
        local key
        IFS= read -rsn1 key <"$TTY" || key=""
        case "$key" in
            $'\033')
                local seq
                IFS= read -rsn2 -t 1 seq <"$TTY" || seq=""
                case "$seq" in
                    '[D'|'[A') selected=$(( (selected - 1 + ${#options[@]}) % ${#options[@]} )) ;;
                    '[C'|'[B') selected=$(( (selected + 1) % ${#options[@]} )) ;;
                esac
                ;;
            '') break ;;
            y|Y) selected=0; break ;;
            n|N) selected=1; break ;;
        esac
    done
    WL ""
    return $selected
}

pulse_text() {
    local text="$1"
    local cycles="${2:-4}"
    local i
    for (( i=0; i<cycles; i++ )); do
        printf '\r%s' "$CLR" >&"$TTY"; WF "  %s%s%s" "$BOLD$CORAL" "$text" "$RST"; sleep 0.08
        printf '\r%s' "$CLR" >&"$TTY"; WF "  %s%s%s" "$BOLD$GOLD" "$text" "$RST"; sleep 0.08
        printf '\r%s' "$CLR" >&"$TTY"; WF "  %s%s%s" "$BOLD$PLUM" "$text" "$RST"; sleep 0.08
    done
    printf '\r%s' "$CLR" >&"$TTY"
    WF "  %s%s%s\n" "$BOLD$GOLD" "$text" "$RST"
}

# ═══════════════════════════════════════════════════════════════════
# NODE.JS INSTALLERS (per platform)
# ═══════════════════════════════════════════════════════════════════

install_node_termux() {
    section "Node.js runtime — Termux native"
    WF "  %s•%s  %sDetected Termux. Using %spkg install nodejs%s%s%s\n" \
        "$YEL" "$RST" "$DIM" "$BOLD" "$RST" "$DIM" "$RST"
    WF "  %s•%s  %sNVM is not used here — it conflicts with Termux's PREFIX%s\n" \
        "$YEL" "$RST" "$DIM" "$RST"
    WL ""

    run_with_progress "Updating Termux packages" parse_pkg_progress pkg update -y
    run_with_progress "Upgrading Termux packages" parse_pkg_progress pkg upgrade -y
    run_with_progress "Installing nodejs + npm + git" parse_pkg_progress pkg install -y nodejs git
}

install_node_apt() {
    section "Node.js runtime — apt"
    run_with_progress "Updating apt package lists" parse_pkg_progress \
        ${ENV_SUDO} apt-get update -qq
    run_with_progress "Installing Node.js + npm" parse_pkg_progress \
        ${ENV_SUDO} apt-get install -y -qq nodejs npm git curl
}

install_node_dnf() {
    section "Node.js runtime — dnf"
    run_with_progress "Installing Node.js + npm" parse_pkg_progress \
        ${ENV_SUDO} dnf install -y -q nodejs npm git
}

install_node_pacman() {
    section "Node.js runtime — pacman"
    run_with_progress "Installing Node.js + npm" parse_pkg_progress \
        ${ENV_SUDO} pacman -S --noconfirm --quiet nodejs npm git
}

install_node_apk() {
    section "Node.js runtime — apk"
    run_with_progress "Updating apk index" parse_pkg_progress \
        ${ENV_SUDO} apk update
    run_with_progress "Installing Node.js + npm" parse_pkg_progress \
        ${ENV_SUDO} apk add nodejs npm git curl
}

install_node_zypper() {
    section "Node.js runtime — zypper"
    run_with_progress "Installing Node.js + npm" parse_pkg_progress \
        ${ENV_SUDO} zypper --quiet install -y nodejs npm git
}

install_node_brew() {
    section "Node.js runtime — Homebrew"
    if brew list node >/dev/null 2>&1; then
        run_with_progress "Upgrading Node.js" parse_npm_progress brew upgrade node
    else
        run_with_progress "Installing Node.js" parse_npm_progress brew install node
    fi
}

install_node_nvm() {
    section "Node.js runtime — NVM"
    export NVM_DIR="$HOME/.nvm"
    if [ -d "$HOME/.nvm" ] && [ -s "$NVM_DIR/nvm.sh" ]; then
        WF "  %s•%s  %sNVM already installed%s\n" "$YEL" "$RST" "$DIM" "$RST"
        \. "$NVM_DIR/nvm.sh"
    else
        local log; log=$(mktemp)
        ( curl -sSSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VER}/install.sh" | bash ) >"$log" 2>&1 &
        local p=$!
        local step=0
        while kill -0 $p 2>/dev/null; do
            draw_progress "$step" "Installing NVM ${NVM_VER}" "fetching installer"
            step=$(( step + 1 ))
            sleep 0.07
        done
        wait $p || { printf '\r%s' "$CLR" >&"$TTY"; sed 's/^/     /' "$log" >&"$TTY"; rm -f "$log"; return 1; }
        printf '\r%s' "$CLR" >&"$TTY"
        WF "  %s✓%s  %sNVM %s installed%s\n" "$GRN" "$RST" "$BOLD" "$NVM_VER" "$RST"
        rm -f "$log"
        \. "$NVM_DIR/nvm.sh"
    fi
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
    command -v nvm >/dev/null 2>&1 || { WF "  %s✗%s  nvm could not be loaded\n" "$RED" "$RST"; return 1; }
    run_with_progress "Installing Node.js v${NODE_TARGET}" parse_pkg_progress nvm install "$NODE_TARGET"
    nvm use "$NODE_TARGET" >/dev/null 2>&1 || true
}

install_node_standalone() {
    section "Node.js runtime — standalone binary"

    local platform arch
    case "$(uname -s)" in
        Darwin) platform="darwin" ;;
        Linux)  platform="linux"  ;;
        *)      platform="linux"  ;;
    esac
    case "$ENV_ARCH" in
        x64)    arch="x64"    ;;
        arm64)  arch="arm64"  ;;
        armv7l) arch="armv7l" ;;
        *)      arch="x64"    ;;
    esac

    if [ "$ENV_IS_TERMUX" = 1 ]; then
        WF "  %s✗%s  %sStandalone Node binary is not compatible with Termux.%s\n" \
            "$RED" "$RST" "$DIM" "$RST"
        WF "     %sUse 'pkg install nodejs' instead.%s\n" "$DIM" "$RST"
        return 1
    fi

    local base_dir
    if [ -n "${XDG_DATA_HOME:-}" ]; then
        base_dir="$XDG_DATA_HOME/pi-node"
    else
        base_dir="$HOME/.local/share/pi-node"
    fi

    local dist_base="https://nodejs.org/dist/latest-v${NODE_TARGET}.x"
    local tmp_dir="${TMPDIR:-/tmp}/yarsya-node.$$"
    rm -rf "$tmp_dir"
    mkdir -p "$tmp_dir" "$base_dir"

    WF "  %s•%s  Resolving Node.js binary for %s-%s\n" "$YEL" "$RST" "$platform" "$arch"
    curl -fsSL "$dist_base/SHASUMS256.txt" -o "$tmp_dir/SHASUMS256.txt"

    local node_file
    node_file=$(awk -v suffix="-$platform-$arch.tar.xz" '
        index($2, "node-v") == 1 && length($2) >= length(suffix) \
        && substr($2, length($2) - length(suffix) + 1) == suffix { print $2; exit }
    ' "$tmp_dir/SHASUMS256.txt")

    if [ -z "$node_file" ]; then
        WF "  %s✗%s  No Node.js binary available for %s-%s\n" "$RED" "$RST" "$platform" "$arch"
        rm -rf "$tmp_dir"
        return 1
    fi

    run_with_progress "Downloading ${node_file%.tar.xz}" parse_pkg_progress \
        curl -fsSL "$dist_base/$node_file" -o "$tmp_dir/$node_file"

    # Verify checksum
    awk -v f="$node_file" '$2 == f { print }' "$tmp_dir/SHASUMS256.txt" > "$tmp_dir/SHASUMS256.selected"
    ( cd "$tmp_dir" && (sha256sum -c SHASUMS256.selected 2>/dev/null || shasum -a 256 -c SHASUMS256.selected) ) >/dev/null 2>&1 \
        && WF "  %s✓%s  checksum verified\n" "$GRN" "$RST"

    local node_dir="$base_dir/${node_file%.tar.xz}"
    rm -rf "$node_dir"
    run_with_progress "Extracting Node.js" parse_pkg_progress \
        tar -xf "$tmp_dir/$node_file" -C "$base_dir"
    rm -f "$base_dir/current"
    ln -s "$node_dir" "$base_dir/current"
    rm -rf "$tmp_dir"

    export PATH="$base_dir/current/bin:$PATH"
    PI_STANDALONE_NODE_BIN="$base_dir/current/bin"
    PI_NODE_INSTALLED_STANDALONE=1
    WF "  %s✓%s  Node.js installed at %s%s%s\n" "$GRN" "$RST" "$DIM" "$node_dir" "$RST"
}

# ═══════════════════════════════════════════════════════════════════
# ROUTER — pilih method berdasarkan env
# ═══════════════════════════════════════════════════════════════════

install_node_runtime() {
    case "$ENV_NODE_METHOD" in
        pkg)        install_node_termux ;;
        apt)        install_node_apt ;;
        dnf)        install_node_dnf ;;
        pacman)     install_node_pacman ;;
        apk)        install_node_apk ;;
        zypper)     install_node_zypper ;;
        brew)       install_node_brew ;;
        nvm)        install_node_nvm ;;
        standalone) install_node_standalone ;;
        *)          install_node_standalone ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════
# FINISH SCREEN
# ═══════════════════════════════════════════════════════════════════
finish_screen() {
    WL ""
    pulse_text "  ✨  INSTALLATION COMPLETE  ✨" 4
    WF "  %s──────────────────────────────────────────────────────────%s\n" "$DGRY" "$RST"
    WL ""
    WF "  %s✓%s  environment      %s%s%s\n" "$GRN" "$RST" "$BOLD" "$(env_description)" "$RST"
    WF "  %s✓%s  Node.js          %s%s%s\n" "$GRN" "$RST" "$BOLD" "$NODE_VER_INST" "$RST"
    WF "  %s✓%s  npm              %s%s%s\n" "$GRN" "$RST" "$BOLD" "$NPM_VER_INST"  "$RST"
    WF "  %s✓%s  pi-agent         %sinstalled%s\n" "$GRN" "$RST" "$BOLD" "$RST"
    WF "  %s✓%s  config           %s~/.pi/agent/models.json%s\n" "$GRN" "$RST" "$BOLD" "$RST"
    WL ""
    WF "  %s➜%s  Run the agent:\n" "$PLUM" "$RST"
    WF "     %s%s$ pi --model %s/%s%s\n" "$BOLD" "$MINT" "$PROVIDER" "$MODEL_ID" "$RST"
    WL ""
    WF "  %s★%s  %syarsya-coder%s  %spresented by%s  %s%sDreamToRealityCreative%s\n" \
        "$GOLD" "$RST" "$BOLD$ROSE" "$RST" "$DIM" "$RST" "$BOLD" "$PLUM" "$RST"
    WL ""
}

# ═══════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════

trap 'printf "%s\033[?25h" "$RST" >&"$TTY"; exit 130' INT TERM

detect_environment
boot_sequence
animate_logo

# ── Preflight ─────────────────────────────────────────────────────
section "Preflight"
command -v curl >/dev/null 2>&1 || { WF "  %s✗%s  curl is required\n" "$RED" "$RST"; exit 1; }
WF "  %s✓%s  curl detected\n" "$GRN" "$RST"
WF "  %s✓%s  platform %s%s%s\n" "$GRN" "$RST" "$DIM" "$(env_description)" "$RST"
WF "  %s✓%s  package manager %s%s%s\n" "$GRN" "$RST" "$DIM" "${ENV_PKG_MANAGER:-none}" "$RST"
WF "  %s✓%s  node method %s%s%s\n" "$GRN" "$RST" "$DIM" "${ENV_NODE_METHOD:-auto}" "$RST"
[ "$ENV_IS_TERMUX" = 1 ] && WF "  %s•%s  %sTermux detected — NVM bypassed%s\n" "$YEL" "$RST" "$DIM" "$RST"
[ "$ENV_IS_PROOT" = 1 ] && WF "  %s•%s  %sproot-distro detected%s\n" "$YEL" "$RST" "$DIM" "$RST"
[ "$ENV_IS_WSL" = 1 ] && WF "  %s•%s  %sWSL detected%s\n" "$YEL" "$RST" "$DIM" "$RST"

# ── Node.js runtime ───────────────────────────────────────────────
install_node_runtime
hash -r 2>/dev/null || true

if ! command -v node >/dev/null 2>&1; then
    WF "  %s✗%s  Node.js is not available after install\n" "$RED" "$RST"
    exit 1
fi

NODE_VER_INST="$(node -v)"
NPM_VER_INST="$(npm -v)"
WF "  %s✓%s  node %s%s%s\n" "$GRN" "$RST" "$BOLD" "$NODE_VER_INST" "$RST"
WF "  %s✓%s  npm  %s%s%s\n" "$GRN" "$RST" "$BOLD" "$NPM_VER_INST"  "$RST"

# ── pi-coding-agent ───────────────────────────────────────────────
section "Agent runtime"
run_with_progress "Installing ${PI_PKG}" parse_npm_progress \
    npm install -g --ignore-scripts "$PI_PKG"
hash -r 2>/dev/null || true

# ── Provider configuration ────────────────────────────────────────
section "Provider configuration"
WF "  %sCredentials are stored only on this machine.%s\n" "$DIM$GRY" "$RST"
WL ""

ask BASE_URL "Base URL" "e.g. https://studio.devnova.icu/v1"
ask_secret API_KEY "API Key"

WL ""
WF "  %s─%s Configuration summary\n" "$DGRY" "$RST"
WF "     %-16s %s%s%s\n" "provider"      "$BOLD" "$PROVIDER"      "$RST"
WF "     %-16s %s%s%s\n" "baseUrl"       "$BOLD" "$BASE_URL"      "$RST"
if [ ${#API_KEY} -gt 16 ]; then
    MASKED="${API_KEY:0:8}…${API_KEY: -6}"
else
    MASKED="$(printf '%*s' ${#API_KEY} '' | tr ' ' '•')"
fi
WF "     %-16s %s%s%s %s(len=%d)%s\n" "apiKey" "$BOLD" "$MASKED" "$RST" "$DIM" "${#API_KEY}" "$RST"
WF "     %-16s %s%s%s\n" "model.id"      "$BOLD" "$MODEL_ID"      "$RST"
WF "     %-16s %s%s%s\n" "contextWindow" "$BOLD" "$CTX_WINDOW"    "$RST"
WF "     %-16s %s%s%s\n" "maxTokens"     "$BOLD" "$MAX_TOKENS"    "$RST"
WL ""

if arrow_menu "Write config to ~/.pi/agent/models.json?"; then
    :
else
    WL ""
    WF "  %s•%s  aborted by user\n" "$YEL" "$RST"
    exit 0
fi

mkdir -p "$HOME/.pi/agent"
if [ -f "$HOME/.pi/agent/models.json" ]; then
    BK="$HOME/.pi/agent/models.json.bak.$(date +%Y%m%d%H%M%S)"
    cp "$HOME/.pi/agent/models.json" "$BK"
    WF "  %s•%s  previous config backed up to %s%s%s\n" "$YEL" "$RST" "$DIM" "$BK" "$RST"
fi

cat > "$HOME/.pi/agent/models.json" <<EOF
{
  "providers": {
    "${PROVIDER}": {
      "baseUrl": "${BASE_URL}",
      "apiKey": "${API_KEY}",
      "api": "${API_KIND}",
      "models": [
        {
          "id": "${MODEL_ID}",
          "name": "${MODEL_NAME}",
          "contextWindow": ${CTX_WINDOW},
          "maxTokens": ${MAX_TOKENS}
        }
      ]
    }
  }
}
EOF

chmod 600 "$HOME/.pi/agent/models.json"
WF "  %s✓%s  config written, permissions %s600%s\n" "$GRN" "$RST" "$BOLD" "$RST"

finish_screen
