#!/bin/bash
# kernel-building script for slackware-current
# creates a package for generic non-smp kernel 
#
# heavily based on the instructions
# at https://docs.slackware.com/howtos:slackware_admin:kernelbuilding
#
# modify the section below to your liking
# build kernel of this version
kversion=4.12.2

# target architecture (e. g. x86_64)
arch=x86

# directory when the kernel sources are extracted to
# and built 
buildpath=/usr/src

# resulting packages will be placed here
destpath=/tmp

# use this mirror to get kernel config
mirror="ftp://teewurst.cc.columbia.edu/pub/linux/slackware/slackware-current/source/k/config-${arch}"

download=0
extract=0
build=0
package=0

function usage {
cat <<HERE
$1 [-b] [-d] [-h] [-p] [-x]

-b  build kernel from sources stored in ${buildpath}
-d  download kernel into ${buildpath}
-h  this help
-p  package kernel + modules 
-x  extract downloaded kernel source tarball

If you don't specify any of the actions, they will
ALL be executed!
HERE
}

while getopts "bpdhx" opt
do
	case "$opt" in
		b)
		build=1
		;;
		d)
		download=1
		;;
		h)
		usage $0
		exit 0
		;;
		p)
		package=1
		;;
		x)
		extract=1
		;;
	esac
done

if [ ${download} -eq 0 -a ${build} -eq 0 -a ${package} -eq 0 -a ${extract} -eq 0 ]
then
	download=1
	extract=1
	build=1
	package=1
fi

if [ ${download} -eq 1 -a ${extract} -eq 0 -a ${build} -eq 1 ]
then
	echo "WARN: You selected DOWNLOAD and BUILD without EXTRACTION, as this does not make much sense I will add extraction for you"
	echo
	extract=1
fi

echo "You made the selection to:"
[ $download -eq 1 ] && echo "* DOWNLOAD"
[ $extract -eq 1 ] && echo "* EXTRACT"
[ $build -eq 1 ] && echo "* BUILD"
[ $package -eq 1 ] && echo "* PACKAGE"

cat <<HERE

Kernel version: ${kversion}
Architecture: ${arch}
Path for building: ${buildpath}
Destination for packages: ${destpath}

If you're happy with your selection, press Enter,
otherwise press Ctrl-C and check the options by running
$0 -h and/or edit the constants defined in the script.
HERE

read

# download kernel
if [ ${download} -eq 1 ]
then
	wget -nc https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-${kversion}.tar.xz
fi

# extract sources
if [ ${extract} -eq 1 ]
then
	echo "Extracting.."
	tar -C ${buildpath} -Jxf linux-${kversion}.tar.xz
	cd ${buildpath}
	# reestablish symbolic link to point to the freshly unpacked kernel
	[ -f linux ] && rm linux
	ln -s linux-${kversion} linux
	# pull the latest .config file Slackware uses for generic-type kernels
	wget -qO- "${mirror}"'/config-generic-4*' >${buildpath}/linux/.config
fi

if [ ${build} -eq 1 ]
then
	echo "Building.."
	cd ${buildpath}/linux
	make clean
	# accept the defaults
	yes "" | make oldconfig
	# build the kernel + modules
	make bzImage modules
fi

if [ ${package} -eq 1 ]
then
	cd ${buildpath}/linux
	KERNPKG=$(mktemp -d)
	MODUPKG=$(mktemp -d)

	INSTALL_MOD_PATH=$MODUPKG make modules_install

	install -D arch/${arch}/boot/bzImage $KERNPKG/boot/vmlinuz-custom-generic-${kversion}
	install -D .config $KERNPKG/boot/config-custom-generic-${kversion}

	# creating kernel package
	cd $KERNPKG
	makepkg -l y -c n ${destpath}/kernel-custom-generic-${kversion}-1.tgz

	# creating modules package
	cd $MODUPKG
	makepkg -l y -c n ${destpath}/kernel-custom-modules-${kversion}-1.tgz

	root=`mount | awk '$3 == "/" {print $1}'`
	krelease=`cat ${buildpath}/linux/include/config/kernel.release`
	# pull package description from core packages
	slackpkg info kernel-generic | grep -e ^kernel-generic -e "^PACKAGE DESCRIPTION" >${KERNPKG}/install/slack-desc
	slackpkg info kernel-modules | grep -e ^kernel-modules -e "^PACKAGE DESCRIPTION" >${MODUPKG}/install/slack-desc
	cat <<HERE
Done.
To install invoke:
* cd ${destpath}
* installpkg kernel-custom-generic-${kversion}-1.tgz 
* installpkg kernel-custom-modules-${kversion}-1.tgz
Once you install the packages do not forget to:
* generate ramdisk after installation, e. g. with:
  mkinitrd -c -k ${krelease} -m ext3 -o /boot/initrd-custom-generic-${kversion}.gz
* if you use lilo, adjust /etc/lilo.conf. Example:
image = /boot/vmlinuz-custom-generic-${kversion}
  root = ${root}
  initrd = /boot/initrd-custom-generic-${kversion}.gz
  label = kernel-${kversion}
  read-only
* run lilo -v and fix any reported errors
* reboot
HERE
fi
