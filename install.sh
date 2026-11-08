#!/usr/bin/env bash

# Merge missing dotfiles into $HOME, then set up Fedora.
# Run as the intended user, without sudo; system changes use sudo.
set -euo pipefail

if (( $# )); then
    printf '%s\n' 'This script takes no arguments.' >&2
    exit 2
fi

if [[ -z "${HOME:-}" || "$HOME" != /* || ! -d "$HOME" ]]; then
    printf '%s\n' 'HOME must point to an existing absolute directory.' >&2
    exit 1
fi

# Step 1: Add missing dotfiles while preserving local configuration.
merge_dotfiles() (
    printf '%s\n' 'Step 1/2: merge dotfiles.'
    # Bootstrap the tools needed for the merge on a fresh Fedora install.
    if ! command -v git >/dev/null 2>&1 || ! command -v rsync >/dev/null 2>&1; then
        sudo dnf -y install git rsync
    fi

    install_tmp=$(mktemp -d)
    trap 'rm -rf -- "$install_tmp"' EXIT

    git clone --quiet --depth 1 --branch main https://github.com/dist1ll/dotfiles.git "$install_tmp/repo"

    # Git's file list includes dotfiles and excludes the clone's Git metadata.
    git -C "$install_tmp/repo" ls-files -z |
    while IFS= read -r -d '' relative_path; do
        if [[ -e "$HOME/$relative_path" || -L "$HOME/$relative_path" ]]; then
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
        printf '%s\0' "$relative_path"
    done > "$install_tmp/missing-files"

    # NUL-separated literal paths also handle spaces and newlines in filenames.
    # New files retain executable bits; existing directory modes stay intact.
    rsync --links --ignore-existing --itemize-changes --from0 \
        --files-from="$install_tmp/missing-files" -- "$install_tmp/repo/" "$HOME/"
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
    	intel-one-mono-fonts \
    	alacritty \
    	helix

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
    	usbutils || exit 1

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
        case "$(uname -m)" in
            x86_64)
                slang_server_arch=x64
                slang_server_sha256=29ad91f245f100337c35ce27dba711d5f0ea50ebc70e73c78e2b27400a87ae62
                ;;
            *)
                printf 'No slang-server release configured for architecture: %s\n' "$(uname -m)" >&2
                exit 1
                ;;
        esac
        slang_server_tmp=$(mktemp -d) || exit 1
        trap 'rm -rf -- "$slang_server_tmp"' EXIT
        slang_server_archive="slang-server-linux-${slang_server_arch}.tar.gz"
        curl -fL --retry 3 \
            "https://github.com/hudson-trading/slang-server/releases/download/${slang_server_version}/${slang_server_archive}" \
            -o "$slang_server_tmp/$slang_server_archive" || exit 1
        printf '%s  %s\n' "$slang_server_sha256" "$slang_server_tmp/$slang_server_archive" \
            | sha256sum --check --status || exit 1
        tar -xzf "$slang_server_tmp/$slang_server_archive" -C "$slang_server_tmp" || exit 1
        "$slang_server_tmp/slang-server" --version || exit 1
        install -d "$slang_server_install_dir" || exit 1
        install -m 0755 "$slang_server_tmp/slang-server" "$slang_server_install_dir/slang-server" || exit 1
        "$slang_server_install_dir/slang-server" --version
    ) || exit 1

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
