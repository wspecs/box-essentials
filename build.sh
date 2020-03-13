#!/bin/bash
echo Installing essentials packages...

TMUX_VERSION=57eeffcf0e5b356b9cda27aa44edbf2c849103eb
OH_MY_ZSH_VERSION=07e3236bc5c8dbf9d818a4f0145f09bdb4bec6f0
DOTFILES_VERSION=876401856ddbb70cf0ffe58b7f3ebc948eaf9524

if [ ! /etc/wspecs/functions.sh ]; then
  echo wspecs/box-functions is required
  exit 1
fi
source /etc/wspecs/functions.sh

hide_output apt-get update
install_once tmux
install_once curl
install_once zsh
install_once git

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

# Set timeout for profile to 30 mins (if no activity)
add_config TMOUT=1800 /etc/profile

# Add swap file if necessary
if free -h | awk '{print $2}' | tail -1 | grep -q '0B'; then
  echo Checking the System for Swap Information
  swapon --show
  echo Checking Available Space on the Hard Drive Partition
  free -h
  df -h
  echo Creating a 2G Swap File
  fallocate -l 2G /swapfile
  echo Enabling the Swap File
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  swapon --show
  free -h
  echo Making the Swap File Permanent
  # Back up the /etc/fstab file in case anything goes wrong
  cp /etc/fstab /etc/fstab.bak
  # Add the swap file information to the end of your /etc/fstab file by typing
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
  sysctl vm.swappiness=10
  add_config vm.swappiness=10 /etc/sysctl.conf
  sysctl vm.vfs_cache_pressure=50
  add_config vm.vfs_cache_pressure=50 /etc/sysctl.conf
fi

goto_working_directory
