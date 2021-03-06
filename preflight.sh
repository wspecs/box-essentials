# Are we running as root?
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root. Please re-run like this:"
  echo
  echo "sudo $0"
  echo
  exit 1
fi

# Check that we are running on Ubuntu 20.04 LTS (or 20.04.xx).
CURRENT_SYSTEM="`lsb_release -d | sed 's/.*:\s*//' `"
ACCEPTED_PLATFORM="Ubuntu 20.04"

if [[ "$CURRENT_SYSTEM" != *"$ACCEPTED_PLATFORM"* ]]; then
  echo "wspecs-box only supports being installed on Ubuntu 20.04, sorry. You are running:"
  echo
  lsb_release -d | sed 's/.*:\s*//'
  echo
  echo "We can't write scripts that run on every possible setup, sorry."
  exit 1
fi

# Check that we have enough memory.
#
# /proc/meminfo reports free memory in kibibytes. Our baseline will be 512 MB,
# which is 500000 kibibytes.
#
# We will display a warning if the memory is below 768 MB which is 750000 kibibytes
#
# Skip the check if we appear to be running inside of Vagrant, because that's really just for testing.
TOTAL_PHYSICAL_MEM=$(head -n 1 /proc/meminfo | awk '{print $2}')
if [ $TOTAL_PHYSICAL_MEM -lt 490000 ]; then
if [ ! -d /vagrant ]; then
  TOTAL_PHYSICAL_MEM=$(expr \( \( $TOTAL_PHYSICAL_MEM \* 1024 \) / 1000 \) / 1000)
  echo "Your wspecs-box needs more memory (RAM) to function properly."
  echo "Please provision a machine with at least 512 MB, 1 GB recommended."
  echo "This machine has $TOTAL_PHYSICAL_MEM MB memory."
  exit 1
fi
fi
if [ $TOTAL_PHYSICAL_MEM -lt 750000 ]; then
  echo "WARNING: Your wspecs-box has less than 768 MB of memory."
  echo "         It might run unreliably when under heavy load."
fi

# Check that tempfs is mounted with exec
MOUNTED_TMP_AS_NO_EXEC=$(grep "/tmp.*noexec" /proc/mounts || /bin/true)
if [ -n "$MOUNTED_TMP_AS_NO_EXEC" ]; then
  echo "wspecs-box has to have exec rights on /tmp, please mount /tmp with exec"
  exit 1
fi

# Check that no .wgetrc exists
if [ -e ~/.wgetrc ]; then
  echo "wspecs-box expects no overrides to wget defaults, ~/.wgetrc exists"
  exit 1
fi

# Check that we are running on x86_64 or i686 architecture, which are the only
# ones we support / test.
ARCHITECTURE=$(uname -m)
if [ "$ARCHITECTURE" != "x86_64" ] && [ "$ARCHITECTURE" != "i686" ]; then
  echo
  echo "WARNING:"
  echo "wspecs-box has only been tested on x86_64 and i686 platform"
  echo "architectures. Your architecture, $ARCHITECTURE, may not work."
  echo "You are on your own."
  echo
fi
