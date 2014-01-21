#!/bin/bash

# Script to assist in a Gentoo install in the 'chroot' environment. The fact
# that this script is needed is a giant pain in the ass, IMO.
#
# Copyright (C) 2014 Wade T. Cline
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Finish entering the new environment.
env-update
source "/etc/profile"
export PS1="(chroot) $PS1"

# Have the user select a profile.
echo "Choose a profile."
eselect profile list
echo "Enter profile number:"
read TEMP
eselect profile set ${TEMP}

# Update Portage.
echo "Updating Portage."
emerge --sync

# Emerge 'vim' because holy wow I hate using 'nano' when I can avoid it.
emerge -v vim

# Add USE flags to Portage.
echo "Add use flags to Portage."
read
vim "/etc/portage/make.conf"

# Specify locales.
echo "Choose locales."
read
vim "/etc/locale.gen"
locale-gen

### CHapter 7: Configuring the kernel ###

# Set the timezone.
echo "Setting timezone."
cp "/usr/share/zoneinfo/US/Pacific" "/etc/localtime"

# Download kernel sources from 'kernel.org' rather than using Gentoo's sources because 1337 (sarcasm).
TEMP=1
cd "/usr/src"
while [ ${TEMP} -ne 0 ]; do
	echo "Downloading Linux Kernel source."
	echo "Enter stable kernel version number."
	read KERNEL_VERSION
	wget --no-check-certificate "https://www.kernel.org/pub/linux/kernel/v3.x/linux-${KERNEL_VERSION}.tar.xz"
	TEMP=$?
done
tar -xJvf "linux-${KERNEL_VERSION}.tar.xz"
ln -s "linux-${KERNEL_VERSION}" "linux"
cd "linux"

# Configure kernel sources.
echo "Configure kernel sources."
read
make menuconfig

# Compile the kernel!
echo "Compiling the kernel."
TEMP=$(cat /proc/cpuinfo | grep -E "^processor.*" | wc -l)
TEMP=$(( ${TEMP} + 1 ))
make -j${TEMP} && make modules_install

### Chapter 8: Configuring Your System ###

# Edit 'fstab'
echo "Edit 'fstab'."
read
vim "/etc/fstab"

# Set the hostname.
echo "Set your hostname."
read
vim "/etc/conf.d/hostname"

# Skip setting the domainname
echo "Skipping setting the domainname."

# Configure the nwtwork.
echo "Configure network file."
read
vim "/etc/conf.d/net"

# Add networks to runlevel defaults.
echo "Add networks to default runlevel? [Y/n]"
read TEMP
while [ "${TEMP:0:1}" != "N" -a "${TEMP:0:1}" != "n" ]; do
	cd "/etc/init.d"

	# Get network interface name.
	echo "Enter network interface name:"
	read TEMP

	# Add the specified network interface name to the default runlevel.
	ln -s net.lo net.${TEMP}
	rc-update add net.${TEMP} default

	# See if the user wants to add another network interface.
	echo "Add another interface? [Y/n]"
	read TEMP
done

# Set the root password.
TEMP=1
while [ ${TEMP} -ne 0 ]; do
	echo "Set the root password."
	passwd
	TEMP=$?
done

# Configure 'rc.conf'.
echo "Configure OpenRC."
read
vim "/etc/rc.conf"

# Configure keymaps.
echo "Configure keymaps."
read
vim "/etc/conf.d/keymaps"

# Configure hwclock.
echo "Configure the hardware clock."
read
vim "/etc/conf.d/hwclock"

# Install system loggers.
echo "Installing system loggers."
emerge -v syslog-ng
rc-update add syslog-ng default
emerge -v logrotate

# Install cron daemon.
echo "Installing cron daemon."
emerge -v vixie-cron
rc-update add vixie-cron default

# Install DHCP daemon.
echo "Install DHCP daemon."
emerge -v dhcpcd

### Chapter 10: Configuring the Bootloader ###
# Bootloader? Tch, boot to removable device ftw.

# Clean the downloaded files up.
echo "Cleaning stage3 tarball and Portage snapshot."
rm /stage3-*.tar.bz2*
rm /portage-latest.tar.bz2*

# Exit the Gentoo system.
echo "Exiting the Gentoo system."
exit
