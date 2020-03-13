#!/bin/bash

if [ ! /etc/wspecs/functions.sh ]; then
  echo wspecs/box-functions is required
	exit 1
fi
source /etc/wspecs/functions.sh


hide_output apt-get update

function install_once() {
	if which $1 > /dev/null; then
    echo "Installing $1"
    hide_output apt-get install $1
	fi
}

install_once tmux