
#!/bin/bash
echo Installing essentials packages...

# Installing essential packages
source /etc/wspecs/functions.sh
hide_output apt-get update
install_once tmux
install_once curl
install_once zsh
install_once git
