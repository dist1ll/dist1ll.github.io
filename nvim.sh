#! /bin/bash

# to use: eval "$(curl "https://www.alic.dev/nvim.sh")"
mkdir -p ~/.vim/plugged/
mkdir -p ~/.config/nvim/
curl https://www.alic.dev/init.vim > ~/.config/nvim/init.vim
