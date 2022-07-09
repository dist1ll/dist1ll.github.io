#! /bin/bash
mkdir -p ~/.vim/pack
curl https://raw.githubusercontent.com/m2q/vim-env/main/_vimrc > ~/.vimrc
REPOSRC="https://github.com/m2q/vim-env"
LOCALREPO="${HOME}/.vim/pack/"

# We do it this way so that we can abstract if from just git later on
LOCALREPO_VC_DIR=$LOCALREPO/.git

if [ ! -d $LOCALREPO_VC_DIR ]
then
	git clone $REPOSRC $LOCALREPO
else
	cd $LOCALREPO
	git pull $REPOSRC
	cd ../../
fi
