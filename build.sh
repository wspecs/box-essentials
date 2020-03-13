#!/bin/bash
echo 'running wspecs/box-essentials...'

if [ ! /etc/wspecs/functions.sh ]; then
  echo wspecs/box-functions is required
  exit 1
fi
source /etc/wspecs/functions.sh
source preflight.sh
source config.sh
source encoding.sh
source packages.sh
source shell.sh
source system.sh
source ssl.sh
