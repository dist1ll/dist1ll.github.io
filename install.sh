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
        curl -fL --retry 3 \
            "https://proton.me/download/drive/cli/${proton_drive_version}/linux-x64/proton-drive" \
            -o "$proton_drive_tmp/proton-drive"
        printf '%s  %s\n' "$proton_drive_sha512" "$proton_drive_tmp/proton-drive" \
            | sha512sum --check
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
    	openssl-libs \
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
    	curl \
    	wget \
    	tar \
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

    # slang-server: SystemVerilog language server, installed for the current user.
    # https://github.com/hudson-trading/slang-server/releases
    (
        slang_server_version=v0.3.0
        slang_server_install_dir="$HOME/.local/bin"
        if [ -x "$slang_server_install_dir/slang-server" ] && \
            slang_server_installed_version=$("$slang_server_install_dir/slang-server" --version 2>&1); then
            case "$slang_server_installed_version" in
                "slang-server version ${slang_server_version#v}"|"slang-server version ${slang_server_version#v}+")
                    printf 'slang-server %s is already installed; skipping.\n' "$slang_server_version"
                    exit 0
                    ;;
            esac
        fi
        slang_server_sha256=29ad91f245f100337c35ce27dba711d5f0ea50ebc70e73c78e2b27400a87ae62
        slang_server_tmp=$(mktemp -d)
        trap 'rm -rf -- "$slang_server_tmp"' EXIT
        slang_server_archive=slang-server-linux-x64.tar.gz
        curl -fL --retry 3 \
            "https://github.com/hudson-trading/slang-server/releases/download/${slang_server_version}/${slang_server_archive}" \
            -o "$slang_server_tmp/$slang_server_archive"
        printf '%s  %s\n' "$slang_server_sha256" "$slang_server_tmp/$slang_server_archive" \
            | sha256sum --check --status
        tar -xzf "$slang_server_tmp/$slang_server_archive" -C "$slang_server_tmp"
        "$slang_server_tmp/slang-server" --version
        install -d "$slang_server_install_dir"
        install -m 0755 "$slang_server_tmp/slang-server" "$slang_server_install_dir/slang-server"
        "$slang_server_install_dir/slang-server" --version
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
