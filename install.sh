#!/usr/bin/env bash

# Preview and replace tracked dotfiles in $HOME, then set up Fedora.
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

dotfile_destination_ok() {
    local relative_path=$1 parent=$1
    local destination="$HOME/$relative_path"

    while [[ "$parent" == */* ]]; do
        parent=${parent%/*}
        if [[ -L "$HOME/$parent" || ( -e "$HOME/$parent" && ! -d "$HOME/$parent" ) ]]; then
            printf '  !  %q (parent %q is a file or symlink)\n' "$relative_path" "$parent"
            return 1
        fi
    done
    if [[ -e "$destination" && ! -f "$destination" && ! -L "$destination" ]]; then
        printf '  !  %q (destination is a directory or special file)\n' "$relative_path"
        return 1
    fi
}

dotfiles_match() {
    if [[ -L "$1" || -L "$2" ]]; then
        [[ -L "$1" && -L "$2" ]] || return 1
        local source_link destination_link
        # A suffix keeps command substitution from stripping trailing newlines.
        source_link=$(readlink -n -- "$1" && printf '.') || return 1
        destination_link=$(readlink -n -- "$2" && printf '.') || return 1
        [[ "$source_link" == "$destination_link" ]]
    else
        git diff --no-index --no-ext-diff --no-textconv --quiet -- "$1" "$2"
    fi
}

# Step 1: Replace tracked dotfiles after confirmation.
replace_dotfiles() (
    # If stdin contains the installer, read the answer from the terminal.
    if [[ $- == *s* || ${BASH_SOURCE[0]:-} -ef /dev/stdin ]]; then
        if ! { exec </dev/tty; } 2>/dev/null; then
            printf '%s\n' 'A terminal is required when piping the installer into Bash. Aborting.' >&2
            return 1
        fi
    fi

    printf '%s\n' 'Step 1/2: replace dotfiles.'
    if ! command -v git >/dev/null 2>&1; then
        sudo dnf -y install git
    fi

    install_tmp=$(mktemp -d)
    staging=
    trap 'rm -rf -- "$install_tmp" ${staging:+"$staging"}' EXIT

    dotfiles_repo="$install_tmp/repo"
    git clone --quiet --depth 1 --branch main https://github.com/dist1ll/dotfiles.git "$dotfiles_repo"

    # Git's file list includes dotfiles and excludes the clone's Git metadata.
    git -C "$dotfiles_repo" ls-files -z > "$install_tmp/tracked"
    printf '%s\n' 'Dotfile changes (A = add, M = replace, ! = skip)'
    paths=()
    actions=()
    while IFS= read -r -d '' relative_path; do
        source="$dotfiles_repo/$relative_path"
        destination="$HOME/$relative_path"
        if [[ ! -f "$source" && ! -L "$source" ]]; then
            printf '  !  %q (tracked entry is not a file or symlink)\n' "$relative_path"
            continue
        fi
        dotfile_destination_ok "$relative_path" || continue
        if [[ ! -e "$destination" && ! -L "$destination" ]]; then
            action=A
        elif dotfiles_match "$source" "$destination"; then
            continue
        else
            action=M
        fi
        printf '  %s  %q\n' "$action" "$relative_path"
        paths+=("$relative_path")
        actions+=("$action")
    done < "$install_tmp/tracked"

    if (( ${#paths[@]} == 0 )); then
        printf '%s\n' 'No dotfile changes to apply.'
        return
    fi
    printf '%s' 'Apply these dotfile changes? [y/N] '
    if ! IFS= read -r confirmation || [[ "$confirmation" != [yY] ]]; then
        printf '%s\n' 'Dotfile changes were not confirmed. Aborting installation.' >&2
        return 1
    fi

    for index in "${!paths[@]}"; do
        relative_path=${paths[index]}
        dotfile_destination_ok "$relative_path" || continue
        destination="$HOME/$relative_path"
        parent=${destination%/*}
        mkdir -p -- "$parent"
        # Stage beside the destination so a failed copy cannot remove the old file.
        staging=$(mktemp -d -- "$parent/.dotfiles.XXXXXX")
        cp -PT -- "$dotfiles_repo/$relative_path" "$staging/file"
        if [[ "${actions[index]}" == A ]]; then
            mv -T --update=none-fail -- "$staging/file" "$destination"
        else
            mv -fT -- "$staging/file" "$destination"
        fi
        rmdir -- "$staging"
        staging=
    done
    printf '%s\n' 'Dotfile changes applied.'
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

replace_dotfiles
install_fedora
