#!/bin/bash

# load functions
source /etc/wspecs/functions.sh

WSPECS_CONFIG_FILE=/etc/wspecs/global.conf
CURRENT_FOLDER=$(pwd)

if [ ! -f "$WSPECS_CONFIG_FILE"  ]; then
  echo creating config file...
  mkdir -p /etc/wspecs
  cat > $WSPECS_CONFIG_FILE <<EOL
# This configuration file capture the global configs for this wspecs box.
EOL
fi

update_global_config() {
  add_config $1 $WSPECS_CONFIG_FILE
  source $WSPECS_CONFIG_FILE
}

# The box needs a name.
if [ -z "${PRIMARY_HOSTNAME:-}" ]; then
  update_global_config PRIMARY_HOSTNAME=$(get_default_hostname)
fi

# If the machine is behind a NAT, inside a VM, etc., it may not know
# its IP address on the public network / the Internet. Ask the Internet
# and possibly confirm with user.
if [ -z "${PUBLIC_IP:-}" ]; then
  # Ask the Internet.
  GUESSED_IP=$(get_publicip_from_web_service 4)
  update_global_config PUBLIC_IP=$GUESSED_IP
fi

# Same for IPv6. But it's optional. Also, if it looks like the system
# doesn't have an IPv6, don't ask for one.
if [ -z "${PUBLIC_IPV6:-}" ]; then
  # Ask the Internet.
  GUESSED_IP=$(get_publicip_from_web_service 6)
  update_global_config PUBLIC_IPV6=$GUESSED_IP
fi

# Get the IP addresses of the local network interface(s) that are connected
# to the Internet. We need these when we want to have services bind only to
# the public network interfaces (not loopback, not tunnel interfaces).
if [ -z "${PRIVATE_IP:-}" ]; then
  update_global_config PRIVATE_IP=$(get_default_privateip 4)
fi
if [ -z "${PRIVATE_IPV6:-}" ]; then
  update_global_config PRIVATE_IPV6=$(get_default_privateip 6)
fi
if [[ -z "$PRIVATE_IP" && -z "$PRIVATE_IPV6" ]]; then
  echo
  echo "I could not determine the IP or IPv6 address of the network inteface"
  echo "for connecting to the Internet. Setup must stop."
  echo
  hostname -I
  route
  echo
  exit 1
fi

# Set STORAGE_USER and STORAGE_ROOT to default values (user-data and /home/user-data), unless
# we've already got those values from a previous run.
if [ -z "${STORAGE_USER:-}" ]; then
  update_global_config STORAGE_USER=$([[ -z "${DEFAULT_STORAGE_USER:-}" ]] && echo "user-data" || echo "$DEFAULT_STORAGE_USER")
fi
if [ -z "${STORAGE_ROOT:-}" ]; then
  update_global_config STORAGE_ROOT=$([[ -z "${DEFAULT_STORAGE_ROOT:-}" ]] && echo "/home/$STORAGE_USER" || echo "$DEFAULT_STORAGE_ROOT")
fi
echo
