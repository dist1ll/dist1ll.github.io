#!/bin/bash
sudo apt install build-essential gdb wget git gzip linux-tools-common linux-tools-generic linux-tools-`uname -r` -y

# git config
git config --global user.email "contact@alic.dev"
git config --global user.name "Adrian Alic"
git config --global core.editor hx

# move to home directory
cd

# install Helix editor
wget https://github.com/helix-editor/helix/releases/download/22.12/helix-22.12-x86_64-linux.tar.xz \
  -O __hx.tar.xz
mkdir helix # install in helix directory
tar -xf __hx.tar.xz -C helix --strip-components 1
rm __hx.tar.xz

# install Rust LSP
mkdir -p bin
wget https://github.com/rust-lang/rust-analyzer/releases/download/2023-01-09/rust-analyzer-x86_64-unknown-linux-gnu.gz \
  -O rust-analyzer.gz
gzip -d rust-analyzer
chmod +x rust-analyzer
mv rust-analyzer bin/rust-analyzer

# change env variables
echo "export PATH=\"\$PATH:$(pwd)/bin:$(pwd)/helix\"" >> .profile
source .profile

# install tmux config
curl https://alic.dev/.tmux.conf > ~/.tmux.conf

mkdir -p ~/.config/helix/
curl https://alic.dev/config.toml > ~/.config/helix/config.toml

# installing Rust toolchain
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh


