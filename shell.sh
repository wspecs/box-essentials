#!/bin/bash

TMUX_VERSION=57eeffcf0e5b356b9cda27aa44edbf2c849103eb
OH_MY_ZSH_VERSION=07e3236bc5c8dbf9d818a4f0145f09bdb4bec6f0
DOTFILES_VERSION=876401856ddbb70cf0ffe58b7f3ebc948eaf9524

source /etc/wspecs/functions.sh

echo Adding tmux conf file
cd $HOME
git_clone https://github.com/gpakosz/.tmux.git $TMUX_VERSION '' .tmux
ln -s -f .tmux/.tmux.conf
cp .tmux/.tmux.conf.local .
rm -rf .tmux

if [ ! -f .oh-my-zsh/oh-my-zsh.sh ]; then
  git_clone https://github.com/ohmyzsh/ohmyzsh.git $OH_MY_ZSH_VERSION '' ohmyzsh
  sh -c ohmyzsh/tools/install.sh <<< $'y\n'
  chsh -s `which zsh` $USER
  rm -rf ohmyzsh
fi

if [ ! -d .vim/autoload ]; then
  echo installing vim bundles
  mkdir -p ~/.vim/autoload ~/.vim/bundle
  curl -LSso ~/.vim/autoload/pathogen.vim https://tpo.pe/pathogen.vim
  git clone https://github.com/mattn/emmet-vim.git ~/.vim/bundle/emmet-vim
  git clone https://github.com/preservim/nerdtree.git ~/.vim/bundle/nerdtree
fi

git_clone https://github.com/wspecs/dotfiles.git $DOTFILES_VERSION '' dotfiles
cp dotfiles/vim/.vimrc ./
cp dotfiles/zsh/.zsh* ./
rm -rd dotfiles
goto_working_directory
