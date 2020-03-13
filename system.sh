
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

cat > /etc/apt/apt.conf.d/02periodic <<EOF
APT::Periodic::MaxAge "7";
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Verbose "0";
EOF

# ### Firewall

# Various virtualized environments like Docker and some VPSs don't provide #NODOC
# a kernel that supports iptables. To avoid error-like output in these cases, #NODOC
# we skip this if the user sets DISABLE_FIREWALL=1. #NODOC
if [ -z "${DISABLE_FIREWALL:-}" ]; then
  # Install `ufw` which provides a simple firewall configuration.
  apt_install ufw

  # Allow incoming connections to SSH.
  ufw_allow ssh;

  # ssh might be running on an alternate port. Use sshd -T to dump sshd's #NODOC
  # settings, find the port it is supposedly running on, and open that port #NODOC
  # too. #NODOC
  SSH_PORT=$(sshd -T 2>/dev/null | grep "^port " | sed "s/port //") #NODOC
  if [ ! -z "$SSH_PORT" ]; then
  if [ "$SSH_PORT" != "22" ]; then

  echo Opening alternate SSH port $SSH_PORT. #NODOC
  ufw_allow $SSH_PORT #NODOC
  fi
  fi

  ufw --force enable;
fi #NODOC

# ### Local DNS Service

# Install a local recursive DNS server --- i.e. for DNS queries made by
# local services running on this machine.
#
# (This is unrelated to the box's public, non-recursive DNS server that
# answers remote queries about domain names hosted on this box. For that
# see dns.sh.)
#
# The default systemd-resolved service provides local DNS name resolution. By default it
# is a recursive stub nameserver, which means it simply relays requests to an
# external nameserver, usually provided by your ISP or configured in /etc/systemd/resolved.conf.
#
# This won't work for us for three reasons.
#
# 1) We have higher security goals --- we want DNSSEC to be enforced on all
#    DNS queries (some upstream DNS servers do, some don't).
# 2) We will configure postfix to use DANE, which uses DNSSEC to find TLS
#    certificates for remote servers. DNSSEC validation *must* be performed
#    locally because we can't trust an unencrypted connection to an external
#    DNS server.
# 3) DNS-based mail server blacklists (RBLs) typically block large ISP
#    DNS servers because they only provide free data to small users. Since
#    we use RBLs to block incoming mail from blacklisted IP addresses,
#    we have to run our own DNS server. See #1424.
#
# systemd-resolved has a setting to perform local DNSSEC validation on all
# requests (in /etc/systemd/resolved.conf, set DNSSEC=yes), but because it's
# a stub server the main part of a request still goes through an upstream
# DNS server, which won't work for RBLs. So we really need a local recursive
# nameserver.
#
# We'll install `bind9`, which as packaged for Ubuntu, has DNSSEC enabled by default via "dnssec-validation auto".
# We'll have it be bound to 127.0.0.1 so that it does not interfere with
# the public, recursive nameserver `nsd` bound to the public ethernet interfaces.
#
# About the settings:
#
# * Adding -4 to OPTIONS will have `bind9` not listen on IPv6 addresses
#   so that we're sure there's no conflict with nsd, our public domain
#   name server, on IPV6.
# * The listen-on directive in named.conf.options restricts `bind9` to
#   binding to the loopback interface instead of all interfaces.
apt_install bind9
edit_config /etc/default/bind9 \
  "OPTIONS=\"-u bind -4\""
if ! grep -q "listen-on " /etc/bind/named.conf.options; then
  # Add a listen-on directive if it doesn't exist inside the options block.
  sed -i "s/^}/\n\tlisten-on { 127.0.0.1; };\n}/" /etc/bind/named.conf.options
fi

# First we'll disable systemd-resolved's management of resolv.conf and its stub server.
# Breaking the symlink to /run/systemd/resolve/stub-resolv.conf means
# systemd-resolved will read it for DNS servers to use. Put in 127.0.0.1,
# which is where bind9 will be running. Obviously don't do this before
# installing bind9 or else apt won't be able to resolve a server to
# download bind9 from.
rm -f /etc/resolv.conf
edit_config /etc/systemd/resolved.conf DNSStubListener=no
echo "nameserver 127.0.0.1" > /etc/resolv.conf

# Restart the DNS services.

restart_service bind9
systemctl restart systemd-resolved

# ### Fail2Ban Service

# Configure the Fail2Ban installation to prevent dumb bruce-force attacks against dovecot, postfix, ssh, etc.
rm -f /etc/fail2ban/jail.local # we used to use this file but don't anymore
rm -f /etc/fail2ban/jail.d/defaults-debian.conf # removes default config so we can manage all of fail2ban rules in one config
cat fail2ban/jails.conf \
  | sed "s/PUBLIC_IP/$PUBLIC_IP/g" \
  | sed "s#STORAGE_ROOT#$STORAGE_ROOT#" \
  > /etc/fail2ban/jail.d/wspecsbox.conf
cp -f fail2ban/filter.d/* /etc/fail2ban/filter.d/

# On first installation, the log files that the jails look at don't all exist.
# e.g., The roundcube error log isn't normally created until someone logs into
# Roundcube for the first time. This causes fail2ban to fail to start. Later
# scripts will ensure the files exist and then fail2ban is given another
# restart at the very end of setup.
restart_service fail2ban

