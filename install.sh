#!/usr/bin/env bash

# Merge missing dotfiles into $HOME, then set up Fedora.
# Run as the intended user, without sudo; system changes use sudo.
set -euo pipefail

if (( $# )); then
    printf '%s\n' 'This script takes no arguments.' >&2
    exit 2
fi

if [[ "$(uname -s)" != Linux || "$(uname -m)" != x86_64 ]]; then
    printf '%s\n' 'This installer requires x86_64 Linux.' >&2
    exit 1
fi

if [[ -z "${HOME:-}" || "$HOME" != /* || ! -d "$HOME" ]]; then
    printf '%s\n' 'HOME must point to an existing absolute directory.' >&2
    exit 1
fi

# Step 1: Add missing dotfiles while preserving local configuration.
merge_dotfiles() (
    printf '%s\n' 'Step 1/2: merge dotfiles.'
    # Bootstrap the tools needed for the merge on a fresh Fedora install.
    if ! command -v git >/dev/null 2>&1; then
        sudo dnf -y install git
    fi

    install_tmp=$(mktemp -d)
    trap 'rm -rf -- "$install_tmp"' EXIT

    git clone --quiet --depth 1 --branch main https://github.com/dist1ll/dotfiles.git "$install_tmp/repo"

    # Git's file list includes dotfiles and excludes the clone's Git metadata.
    git -C "$install_tmp/repo" ls-files -z |
    while IFS= read -r -d '' relative_path; do
        destination="$HOME/$relative_path"
        if [[ "$relative_path" != .bashrc.d/10-managed.sh &&
              ( -e "$destination" || -L "$destination" ) ]]; then
            continue
        fi
        if [[ -d "$destination" && ! -L "$destination" ]]; then
            continue
        fi

        # Skip a whole subtree when an existing parent is a file or symlink.
        parent=$relative_path
        while [[ "$parent" == */* ]]; do
            parent=${parent%/*}
            if [[ -L "$HOME/$parent" || ( -e "$HOME/$parent" && ! -d "$HOME/$parent" ) ]]; then
                printf 'Skipping %s: existing parent %s is a file or symlink.\n' "$relative_path" "$parent" >&2
                continue 2
            fi
        done
        mkdir -p -- "${destination%/*}"
        # Only the managed Bash fragment may replace an existing file.
        if [[ "$relative_path" == .bashrc.d/10-managed.sh ]]; then
            cp --remove-destination -PT -- "$install_tmp/repo/$relative_path" "$destination"
        else
            cp --update=none -PT -- "$install_tmp/repo/$relative_path" "$destination"
        fi
    done
)

download_verified() {
    local url=$1 output=$2 checksum=$3 checksum_command=$4
    curl -fL --retry 3 "$url" -o "$output"
    printf '%s  %s\n' "$checksum" "$output" | "$checksum_command" --check
}

# With an archive directory, keep the whole release and link its executable.
# A standalone executable is checked with --version and copied into bin.
install_tar_release() (
    local url=$1 checksum=$2 executable=$3 archive_dir=${4:-}
    local bin_dir="$HOME/.local/bin" opt_dir="$HOME/.local/opt"
    local staging archive

    install -d "$bin_dir" "$opt_dir"
    if [[ -z "$archive_dir" || ! -x "$opt_dir/$archive_dir/$executable" ]]; then
        staging=$(mktemp -d "$opt_dir/.release.XXXXXX")
        trap 'rm -rf -- "$staging"' EXIT
        archive="$staging/${url##*/}"
        download_verified "$url" "$archive" "$checksum" sha256sum
        tar -xf "$archive" -C "$staging"

        if [[ -z "$archive_dir" ]]; then
            "$staging/$executable" --version
            install -m 0755 "$staging/$executable" "$bin_dir/$executable"
            "$bin_dir/$executable" --version
            return
        fi

        test -x "$staging/$archive_dir/$executable"
        mv -Tn -- "$staging/$archive_dir" "$opt_dir/$archive_dir"
    fi

    test -x "$opt_dir/$archive_dir/$executable"
    ln -sfnT -- "$opt_dir/$archive_dir/$executable" "$bin_dir/$executable"
)

# Step 2: Install Fedora packages and user tools.
install_fedora() {
    printf '%s\n' 'Step 2/2: set up Fedora.'

    # Avoid slowing down boot if we have NICs in a direct-attach loop.
    # Might require disabling systemd equivalent on server version.
    # sudo systemctl disable NetworkManager-wait-online.service

    # Dev environment
    sudo dnf -y install \
        curl \
        ca-certificates \
        libsecret \
        intel-one-mono-fonts \
        alacritty \
        helix

    # Lore VCS
    curl -fsSL https://raw.githubusercontent.com/EpicGames/lore/main/scripts/install.sh \
        | PATH="${LORE_INSTALL_DIR:-$HOME/.local/bin}:$PATH" bash

    # Zed IDE
    if ! command -v zed >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/zed" ]; then
        (
            setup_zed_tmp=$(mktemp -d)
            trap 'rm -rf -- "$setup_zed_tmp"' EXIT
            curl -fL --retry 3 https://zed.dev/install.sh -o "$setup_zed_tmp/install.sh"
            sh "$setup_zed_tmp/install.sh"
        )
    else
        printf '%s\n' 'Zed is already installed; skipping.'
    fi

    # Proton Drive CLI: Linux x86_64, installed for the current user.
    # https://proton.me/download/drive/cli/index.html
    (
        proton_drive_version=0.9.0
        proton_drive_sha512=3533025ba69ae112b64e3e01fbcc1ad0688136a4043f6cf6a72886967d85fdcd9ec235479c2e113171614be5225bfba93427509a05ca5aa6071d924fa7e91ca8
        proton_drive_bin="$HOME/.local/bin/proton-drive"
        if [ -x "$proton_drive_bin" ] && \
            printf '%s  %s\n' "$proton_drive_sha512" "$proton_drive_bin" \
                | sha512sum --check --status; then
            printf 'Proton Drive CLI %s is already installed; skipping.\n' "$proton_drive_version"
            exit 0
        fi
        proton_drive_tmp=$(mktemp -d)
        trap 'rm -rf -- "$proton_drive_tmp"' EXIT
        download_verified \
            "https://proton.me/download/drive/cli/${proton_drive_version}/linux-x64/proton-drive" \
            "$proton_drive_tmp/proton-drive" "$proton_drive_sha512" sha512sum
        chmod 0755 "$proton_drive_tmp/proton-drive"
        "$proton_drive_tmp/proton-drive" version
        install -D -m 0755 "$proton_drive_tmp/proton-drive" "$proton_drive_bin"
    )

    # System packages, kernel dev, hardware, virtualization
    sudo dnf -y install \
        git-lfs \
        kernel-devel \
        perf \
        cmake \
        lshw \
        htop \
        qemu-system-riscv \
        qemu-system-aarch64 \
        gcc-riscv64-linux-gnu \
        gcc-riscv32-linux-gnu \
        numactl \
        numactl-devel \
        dtc \
        @virtualization

    # PCB
    sudo dnf -y install \
        kicad

    # Unity dev
    sudo dnf -y install \
        openssl \
        GConf2

    # Languages, compilers, linkers, LSPs
    sudo dnf -y install \
        clang \
        clang-tools-extra \
        rustup

    # Ensure Rust nightly is installed, preserving an existing default toolchain.
    setup_cargo_home="${CARGO_HOME:-$HOME/.cargo}"
    setup_rustup=$(command -v rustup || true)
    if [ -z "$setup_rustup" ] && [ -x "$setup_cargo_home/bin/rustup" ]; then
        setup_rustup="$setup_cargo_home/bin/rustup"
    fi
    if [ -z "$setup_rustup" ]; then
        rustup-init -y --default-toolchain none --no-modify-path
        setup_rustup="$setup_cargo_home/bin/rustup"
    fi
    if [ -f "$setup_cargo_home/env" ]; then
        # shellcheck source=/dev/null
        . "$setup_cargo_home/env"
    fi
    setup_toolchains=$("$setup_rustup" toolchain list)
    if ! grep -Eq '^nightly(-[[:alpha:]]|[[:space:]]|$)' <<< "$setup_toolchains"; then
        "$setup_rustup" toolchain install --no-self-update nightly
    fi
    if ! "$setup_rustup" default >/dev/null 2>&1; then
        "$setup_rustup" default nightly
    fi

    # FPGA dev, SystemVerilog simulation, waveform viewers, serial tests
    sudo dnf -y install \
        git \
        wget \
        tar \
        xz \
        gzip \
        unzip \
        patch \
        diffutils \
        gcc \
        gcc-c++ \
        make \
        autoconf \
        automake \
        libtool \
        m4 \
        pkgconf-pkg-config \
        gmp-devel \
        zlib-devel \
        libffi-devel \
        readline-devel \
        ncurses-devel \
        verilator \
        gtkwave \
        python3 \
        python3-pyserial \
        picocom \
        zlib-ng-compat-static \
        usbutils

    # Blender: official Linux x64 release, installed for the current user.
    local blender_version=5.3.0
    local blender_release="blender-$blender_version-linux-x64"
    install_tar_release \
        "https://mirror.blender.org/release/Blender${blender_version%.*}/$blender_release.tar.xz" \
        dacb8264197a3f7fda6001285a5a506fc97ee943881261c2c3bd63c882f22e05 \
        blender "$blender_release"

    # slang-server: SystemVerilog language server, installed for the current user.
    # https://github.com/hudson-trading/slang-server/releases
    (
        slang_server_version=v0.3.0
        slang_server_bin="$HOME/.local/bin/slang-server"
        if [ -x "$slang_server_bin" ] && \
            slang_server_installed_version=$("$slang_server_bin" --version 2>&1); then
            case "$slang_server_installed_version" in
                "slang-server version ${slang_server_version#v}"|"slang-server version ${slang_server_version#v}+")
                    printf 'slang-server %s is already installed; skipping.\n' "$slang_server_version"
                    exit 0
                    ;;
            esac
        fi
        install_tar_release \
            "https://github.com/hudson-trading/slang-server/releases/download/${slang_server_version}/slang-server-linux-x64.tar.gz" \
            29ad91f245f100337c35ce27dba711d5f0ea50ebc70e73c78e2b27400a87ae62 \
            slang-server
    )

    # Get rid of things we don't need
    sudo dnf -y remove 'libreoffice*'

    # Admin, util, miscallaneous
    sudo dnf -y install \
        gnupg2-scdaemon \
        pass \
        just \
        pre-commit \
        cloc
}

merge_dotfiles
install_fedora
