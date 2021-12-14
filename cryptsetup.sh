#!/bin/bash
#
# Copyright (C) 2013,2021 Wade T. Cline
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#/

# The user's command.
COMMAND=""
# The device to mount.
DEVICE=""
# Keyfile for the specified device.
KEYFILE=`false`
# Name for the mapping of the device.
NAME="device"
# Passphrase for the device.
PASSPHRASE=""
# Salt for the key-stretching algorithm.
SALT=""

# Parse arguments.
# TODO: Use 'getopt'
arguments_parse() {
	# Validate argument count.
	if [ $# -lt 2 ]; then
		usage_print "Too few arguments"
	fi

	# Parse the command and its arguments.
	COMMAND=${1}
	shift
	case "${COMMAND}" in
	init)
		# Parse optional arguments.
		while [ $# -gt 3 ]; do
			case "${1}" in
			-n|--name)
				shift
				NAME=${1}
				shift
				;;
			-k|--key-file)
				shift
				KEYFILE=${1}
				if [ ! -f ${KEYFILE} ]; then
					usage_print "Keyfile does not exist"
				fi
				shift
				;;
			*)
				usage_print "Unrecognized option: ${1}"
			esac
		done

		# Parse the device.
		DEVICE=${1}
		if [ ! -b ${DEVICE} ]; then
			usage_print "Not a block device: ${DEVICE}"
		fi
		shift

		# Parse the passphrase.
		PASSPHRASE=${1}
		shift

		# Parse the base salt.
		SALT=${1}
		shift
		;;
	free)
		# Parse the mapping name.
		if [ $# -gt 0 ]; then
			NAME=${1}
			shift
		fi
		;;
	*)
		usage_print "Unrecognized command ${COMMAND}"
	esac

	# Check for additonal arguments.
	if [ $# -gt 0 ]; then
		usage_print "Additional argument: ${1}"
	fi
}

# Setup cryptsetup. (almost redundant)
cryptsetup_init() {
	# Define the cryptography layers.
	local -a layers=(
		"serpent-xts-essiv:sha256" "${DEVICE}" ".${NAME}0"
		"aes-xts-essiv:sha256" "/dev/mapper/.${NAME}0" ".${NAME}1"
		"twofish-xts-essiv:sha256" "/dev/mapper/.${NAME}1" "${NAME}"
	)

	# Set the first value of the key.
	KEY=${PASSPHRASE}

	# Set-up the crypytography layers.
	echo -n "Hashing/Setup of '${DEVICE}'"
	if [ -z "${KEYFILE}" ]; then
		cryptsetup_init_password
	else
		cryptsetup_init_keyfile
	fi
	echo ""
}

# Set up the cryptography layers using a keyfile.
cryptsetup_init_keyfile() {
	# Set up the keyfile loopback device.
	local -a device_loop="$(losetup -f)"
	losetup "${device_loop}" "${KEYFILE}"
	ret=$?
	if [ $ret -ne 0 ]; then
		echo "Error setting up loop device: ${ret}"
		return 1
	fi
	local name_key="$(basename ${device_loop})_key"

	# Set-up the cryptography mappings.
	# The idea for using a different keyfile mapping with each layer is so
	# that the each segment of the key is encrypted with a different
	# symmetric cipher rather than the whole key being encrypted with a
	# single symmetric cipher.
	for ((i=0; i<${#layers[@]}; i+=3)); do
		local cipherspec="${layers[i]}"
		local device="${layers[i+1]}"
		local name="${layers[i+2]}"
		local iter=$(($i/3))

		# Stretch the key.
		# Not technically necessary to do multiple smaller stretches
		# rather than one big stretch, but multiple stretches make a
		# nice progress indicator.
		echo -n "."
		KEY="$(cryptsetup_key_stretch "${SALT}" "${KEY}")"

		# Set-up the keyfile mapping.
		printf %s "${KEY}" | cryptsetup open --type plain --hash sha512 --cipher "${cipherspec}" "${device_loop}" "${name_key}"

		# Set-up the crypto mapping.
		cryptsetup open --type plain --key-file="/dev/mapper/${name_key}" --keyfile-offset=$(($iter*512)) --cipher "${cipherspec}" "${device}" "${name}"

		# Remove the keyfile mapping.
		cryptsetup remove "${name_key}"
	done

	# Free the keyfile loopback device.
	losetup -d "${device_loop}"
}

# Set up the cryptography layers using a password.
cryptsetup_init_password() {
	# Set up the mappings.
	for ((i=0; i<${#layers[@]}; i+=3)); do
		local cipherspec="${layers[i]}"
		local device="${layers[i+1]}"
		local name="${layers[i+2]}"

		# Stretch the key.
		echo -n "."
		KEY="$(cryptsetup_key_stretch "${SALT}" "${KEY}")"

		# Set-up the mapping.
		printf %s "${KEY}" | cryptsetup open --type plain --hash sha512 --cipher "${cipherspec}" "${device}" "${name}"
	done
}

# Remove cryptsetup mappings.
cryptsetup_free() {
	# Validate arguments.
	if [ $# -ne 0 ]; then
		usage_print "cryptsetup_free(); invalid argument count: $#."
	fi

	# Remove cryptsetup mappings.
	cryptsetup remove "${NAME}"
	cryptsetup remove ".${NAME}1"
	cryptsetup remove ".${NAME}0"
}

# Stretch the specified key by hashing it with a large number of rounds.
# 1: Salt for the key-derivation function.
# 2: Key to derive.
# 3(opt): Hash function to use.
# 4(opt): Number of rounds to use.
# stdout: Stretched key.
cryptsetup_key_stretch() {
	local salt="$1"
	local key="$2"
	local hash="${3:-sha-512}"
	local rounds=${4:-72853}

	# Execute the key derivation function.
	key="$(printf %s "${key}" | mkpasswd -m "${hash}" -R ${rounds} -s -S "${salt}" | cut -d '$' -f 5)"
	echo -n "${key}"
}

# Makes sure that the system can run the script.
system_validate() {
	# Check for root privileges.
	if [[ ${EUID} -ne 0 ]]; then
		usage_print "This script must be run as 'root'"
	fi

	# Check for 'cryptsetup' utility.
	if ! command -v cryptsetup > /dev/null; then
		usage_print "Unable to find 'cryptsetup' utility"
	fi

	# Check for 'mkpasswd' utility.
	if ! command -v mkpasswd > /dev/null; then
		usage_print "Unable to find 'mkpasswd' utility"
	fi
}

# Print the usage message.
# 1:	An error message (optional).
usage_print() {
	echo "ERROR: $1."
	echo ""
	echo "./cryptsetup.sh init [-n name] [-k keyfile] <device> <passphrase> <salt>"
	echo "./cryptsetup.sh free [name]"
	echo ""
	echo "  init:	Initialize mappings."
	echo "  free:	Remove mappings."
	echo ""
	echo "  device:	The block device to create mappings for."
	echo "  name:	The name for the mapping of the specified device."
	echo "		(default: \"device\")."
	echo "  passphrase:	The passphrase for the specified device."
	exit 1
}

# Validate system pre-requirements.
system_validate

# Parse arguments.
arguments_parse $@

# Call the correct command.
case "${COMMAND}" in
init)
	cryptsetup_init
	;;
free)
	cryptsetup_free
	;;
*)
	usage_print "Unrecognized command ${COMMAND}"
esac
