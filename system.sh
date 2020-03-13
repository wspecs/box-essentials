
#!/bin/bash
source /etc/wspecs/functions.sh

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
