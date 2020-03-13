
#!/bin/bash
source /etc/wspecs/functions.sh
source /etc/wspecs/global.conf

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

# First set the hostname in the configuration file, then activate the setting
echo $PRIMARY_HOSTNAME > /etc/hostname
hostname $PRIMARY_HOSTNAME

### Fix permissions
# The default Ubuntu Bionic image on Scaleway throws warnings during setup about incorrect
# permissions (group writeable) set on the following directories.
chmod g-w /etc /etc/default /usr

# We install some non-standard Ubuntu packages maintained by other
# third-party providers. First ensure add-apt-repository is installed.

if [ ! -f /usr/bin/add-apt-repository ]; then
  echo "Installing add-apt-repository..."
  hide_output apt-get update
  apt_install software-properties-common
fi

# Ensure the universe repository is enabled since some of our packages
# come from there and minimal Ubuntu installs may have it turned off.
hide_output add-apt-repository -y universe

# Install the certbot PPA.
hide_output add-apt-repository -y ppa:certbot/certbot

# ### Update Packages

# Update system packages to make sure we have the latest upstream versions
# of things from Ubuntu, as well as the directory of packages provide by the
# PPAs so we can install those packages later.

echo Updating system packages...
hide_output apt-get update
apt_get_quiet upgrade

# Old kernels pile up over time and take up a lot of disk space, and because of Mail-in-a-Box
# changes there may be other packages that are no longer needed. Clear out anything apt knows
# is safe to delete.

apt_get_quiet autoremove

# ### Install System Packages

# Install basic utilities.
#
# * haveged: Provides extra entropy to /dev/random so it doesn't stall
#           when generating random numbers for private keys (e.g. during
#           ldns-keygen).
# * unattended-upgrades: Apt tool to install security updates automatically.
# * cron: Runs background processes periodically.
# * ntp: keeps the system time correct
# * fail2ban: scans log files for repeated failed login attempts and blocks the remote IP at the firewall
# * netcat-openbsd: `nc` command line networking tool
# * git: we install some things directly from github
# * sudo: allows privileged users to execute commands as root without being root
# * coreutils: includes `nproc` tool to report number of processors, mktemp
# * bc: allows us to do math to compute sane defaults
# * openssh-client: provides ssh-keygen

echo Installing system packages...
apt_install python3 python3-dev python3-pip \
  netcat-openbsd wget curl git sudo coreutils bc \
  haveged pollinate openssh-client unzip \
  unattended-upgrades cron ntp fail2ban rsyslog

# ### Suppress Upgrade Prompts
# When Ubuntu 20 comes out, we don't want users to be prompted to upgrade,
# because we don't yet support it.
if [ -f /etc/update-manager/release-upgrades ]; then
  add_config Prompt=never /etc/update-manager/release-upgrades
  rm -f /var/lib/ubuntu-release-upgrader/release-upgrade-available
fi

### Set the system timezone

if [ ! -f /etc/timezone ]; then
  echo "Setting timezone to UTC."
  echo "Etc/UTC" > /etc/timezone
  restart_service rsyslog
fi

# ### Seed /dev/urandom

echo Initializing system random number generator...
dd if=/dev/random of=/dev/urandom bs=1 count=32 2> /dev/null

# This is supposedly sufficient. But because we're not sure if hardware entropy
# is really any good on virtualized systems, we'll also seed from Ubuntu's
# pollinate servers:

pollinate  -q -r

### Add ssh key
if [ ! -f /root/.ssh/id_rsa_foo ]; then
  echo 'Creating SSH key for key…'
  ssh-keygen -t rsa -b 2048 -a 100 -f /root/.ssh/id_rsa_foo -N '' -q
fi

# ### Package maintenance
#
# Allow apt to install system updates automatically every day.

cat > /etc/apt/apt.conf.d/02periodic <<EOF;
APT::Periodic::MaxAge "7";
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Verbose "0";
EOF
