# Not actually an init script. This is supposed to be the companion script to
# the init script; this script does the initial formatting and mounting of
# the file system for the installlation; it -must- be synchronized with the
# init script, obviously.

#!/bin/busybox sh
# History: (y/m/d)
# ------------------
# 2013.05.28 - Wade Cline
#    Completely gutted and re-made into something simple and dumb for his own
#    purposes. 
# 2006.08.24 - Federico Zagarzazu
#    Fix: call splash_setup() if fbsplash args exist   
# 2006.08.06 - Federico Zagarzazu
#    Released.
# 2006.08.06 - Federico Zagarzazu
#    Fixed: /dev/device-mapper /dev/mapper/control issue 
#	   otherwise it fails on my amd64 system
# 2006.08.04 - Federico Zagarzazu
#    Bug fixes, several improvements.
#    Test phase finished.
# 2006.06.20 - Federico Zagarzazu
#    Written.
# 
# Thank you! 
# ---------------------------------------------------------------
# o Alon Bar-Lev [http://en.gentoo-wiki.com/wiki/Linux_Disk_Encryption_Using_LoopAES_And_SmartCards]
#	 I stole ideas, general structure and entire functions from his init script.
# o nix
#
# o Andreas Steinmetz [kernel doc: power/swsusp-dmcrypt.txt]

# Path to the key-file; later, the encryption key.
KEY=""
# Where to mount the filesystem.
MOUNTPOINT=""
# The device to format.
ROOT=""
# Salt for the key-stretching algorithm.
SALT=""

# Parse command-line arguments.
arguments_parse() {
	# Validate argument count.
	if [ $# -ne 3 ]; then
		die "Invalidate argument count: $#."
	fi

	# Parse arguments.
	ROOT="`echo "${1}" | cut -d'=' -f2`"
	KEY=$2
	MOUNTPOINT=$3
}

# Exit this script.
die() {
	echo "$1"
	echo ""
	echo "USAGE: ./format <device> <key-file> <mount point>"
	echo ""
	exit 1
}

# Perform key-stretching.
# 1: The key to stretch.
# 2: Path to keyfile (used as a salt).
key_stretch() {
	# Validate arguments.
	if [ $# -ne 2 ]; then
		echo "key_stretch(); invalidate argument count: $#."
	fi

	# Set the salt.
	SALT=$(cat $2 | cut -c 1-16)

	# Stretch the key.
	KEY=$(mkpasswd -m sha-256 -R 72851 $1 $SALT | cut -d '$' -f 5)
}

# Mount the root filesystem.
setup() {
	DONE=`false`
	DEVICE_LOOP=""

	# Validate arguments.
	[ -n "${ROOT}" ] || die "Error: root missing."

	# Read in the password
	until [ $DONE ]; do
		# Read the passphrase.
		echo "Enter passphrase:"
		read -s PASSPRHASE

		# Verify the passphrase.
		echo "Verify passphrase:"
		read -s VERIFY

		# Verify the passphrase.
		if [ $PASSPHRASE != $VERIFY ]; then # Failure.
			# See if the user wishes to try again.
			echo "Passphrases do not match."
			echo "Try again? [y/N]"
			read AGAIN
			if [ $AGAIN != "y" ]; then # Quitting.
				return
			fi
			continue
		fi

		# Verifing.
		DONE=true
	done

	# Set up the key.
	DEVICE_LOOP=`losetup -f`
	losetup "${DEVICE_LOOP}" "${KEY}"
	if [ "$?" -ne 0 ]; then
		die "Error setting up loop device."
	fi
	echo -n "Hashing/Setup."
	key_stretch "$PASSPHRASE" "$DEVICE_LOOP"
	echo "$KEY" | cryptsetup create --cipher serpent-xts-essiv:sha256 --hash sha512 key0 "$DEVICE_LOOP"
	echo -n "."
	key_stretch "$KEY" "/dev/mapper/key0"
	echo "$KEY" | cryptsetup create --cipher aes-xts-essiv:sha256 --hash sha512 key1 /dev/mapper/key0
	echo -n "."
	key_stretch "$KEY" "/dev/mapper/key1"
	echo "$KEY" | cryptsetup create --cipher twofish-xts-essiv:sha256 --hash sha512 key2 /dev/mapper/key1
	echo -n "."
	key_stretch "$KEY" "/dev/mapper/key2"
	echo "$KEY" | cryptsetup create --cipher serpent-cbc-essiv:sha256 --hash sha512 key3 /dev/mapper/key2
	echo -n "."
	key_stretch "$KEY" "/dev/mapper/key3"
	echo "$KEY" | cryptsetup create --cipher aes-cbc-essiv:sha256 --hash sha512 key4 /dev/mapper/key3
	echo "."
	key_stretch "$KEY" "/dev/mapper/key4"
	echo "$KEY" | cryptsetup create --cipher twofish-cbc-essiv:sha256 --hash sha512 key5 /dev/mapper/key4
	
	# Set up root mappings.
	cryptsetup create --cipher serpent-xts-essiv:sha256 --key-file=/dev/mapper/key0 ".root0" "${ROOT}"
	cryptsetup create --cipher aes-xts-essiv:sha256 --key-file=/dev/mapper/key1 ".root1" "/dev/mapper/.root0"
	cryptsetup create --cipher twofish-xts-essiv:sha256 --key-file=/dev/mapper/key2 ".root2" "/dev/mapper/.root1"
	cryptsetup create --cipher serpent-cbc-essiv:sha256 --key-file=/dev/mapper/key3 ".root3" "/dev/mapper/.root2"
	cryptsetup create --cipher aes-cbc-essiv:sha256 --key-file=/dev/mapper/key4 ".root4" "/dev/mapper/.root3"
	cryptsetup create --cipher twofish-cbc-essiv:sha256 --key-file=/dev/mapper/key5 "root" "/dev/mapper/.root4"

	# Free the key.
	cryptsetup remove key5
	cryptsetup remove key4
	cryptsetup remove key3
	cryptsetup remove key2
	cryptsetup remove key1
	cryptsetup remove key0
	losetup -d "$DEVICE_LOOP"

	# Format the filesystem.
	mkfs.ext3 /dev/mapper/root
	if [ "$?" -ne 0]; then # Failure.
		# Clean-up root mappings.
		cryptsetup remove "root"
		cryptsetup remove ".root4"
		cryptsetup remove ".root3"
		cryptsetup remove ".root2"
		cryptsetup remove ".root1"
		cryptsetup remove ".root0"

		# Exit failure.
		echo "Unable to format filesystem."
		exit 1
	fi

	# Mount the filesystem.
	mount -t ext3 /dev/mapper/root $MOUNTPOINT
	if [ "$?" -ne 0 ]; then # Failure.
		# Clean-up root mappings.
		cryptsetup remove "root"
		cryptsetup remove ".root4"
		cryptsetup remove ".root3"
		cryptsetup remove ".root2"
		cryptsetup remove ".root1"
		cryptsetup remove ".root0"

		# Exit failure.
		echo "Unable to format filesystem."
		exit 1
	fi
}

# Validate the system. This function is not comprehensive.
system_validate() {
	# Check for 'mkpasswd'
	if ! command -v mkpasswd > /dev/null; then
		echo "Unable to find 'mkpasswd' utility."
		exit 1
	fi
}

# The main function (duh).
main() {
	# Parse the command-line arguments into the appropriate shell variables.
	arguments_parse $@

	# Validate the system.
	system_validate

	# Format the device.
	setup
}

main
