# install-helper

## Overview
A recurring problem when dealing with new (non-x86) platforms is the inability to perform an installation with the standard media provided by the various distributions. These problems primarily revolve around the inability of the kernel shipped on the media to boot the system (sufficiently), and secondly there can also be problems with the bootloader (eg. GRUB) failing to intergrate correctly with the system. The necessary changes that are needed to these components are generally made as part of the development cycle of the system, however the time between those changes being available to the public and appearing upstream in the general release kernel can be quite large. Factoring in the additional delay of waiting for a new distribution release which may or may not support the desired platform creates a bit of a problem when dealing with these platforms. While individual distribution releases can be patched with the required kernel/updated initrd image, experimenting with different distributions/releases becomes cumbersome. These utilites provide a way of booting a collection of different standard media using a standalone kernel and GRUB (if needed) packages/source.

## ISO Install Description
The problems of trying to get a new kernel intergrated with a particular distribution's installer can be further complicated by the fact that different installation methods are used depending depending on the media type (Workstation/Server/etc). An easier installer to work with would be, for example, the Debian Network Installer consisting of a CLI installer running from the an initramfs image. To update this (kernel wise) you merely copy your new kernel image over the top of the old one, then unpacked the initramfs (initrd) image, added the modules directory for your kernel, and then repacked the initramfs image again. This would allow you to perform a normal installation, with the only downside that you had to manually install a copy of your kernel yourself before finishing installation. With more complex installers (LiveCDs) you not only have the kernel/initrd image to worry about, but also the (probably) CRAMFS image containing the live image. One way to avoid potential problems with the second image is to try and load (if it's not builtin already) any modules that it needs before it's loaded, and this is the approach that is used here.

To keep this a generic method an initramfs image is generated which is used to preload and patch the installer initramfs image. It does this by first loading a number of predefined kernel modules (e.g. device mapper related, XFS which needed by Fedora 2nd stage!!!), but can also include user specified modules. A basic CLI menu system is then run so that the installation media can be selected. From that selection it takes the existing initramfs image, unpacks it, and copies in the necessary kernel libraries. It then patches the kernel command line string (/proc/cmdline) with the kernel arguments from selected installation method (necessary for Fedora, for example). It then uses switch_root to start executing the installer initramfs as if it were initiated as normal.

## Commands

* build_initrd.sh - Used to build the initramfs image with all the required tools from a specified kernel package.
* mkefiusb.sh - Builds a UEFI bootable device with kernel package and initrd installed.

### build_initrd
#### Options
* -k <path to kernel package> This is the path to a Debian/RedHat kernel package which will be included in the initramfs image.
* -m <kernel module name> Name of a kernel module to load at boot time. Can be specified multiple times.

`e.g. ./build_initrd.sh -k ../linux-image-5.4.0-rc7.deb -m "i2c-qcom-geni" -m "usbhid"`

Builds an initramfs image using kernel package '../linux-image-5.4.0-rc7.deb', loads modules i2c-qcom-geni, and usbhid on boot.

An initramfs image is just a root filing system compressed into an easy format to unpack in to RAM. Whilst various tools exist to create initramfs images (e.g. initramfs-tools), makejail is used as there is greater flexability to create fuller and more capable images easily, as it was originally designed to create chroot environments using minimal configuration files. First makejail's configuration file is preprocessed to set the output directory correctly, and makejail is then run. Then the specified kernel image is unpacked into the makejail's output directory, and the extras directory is copied into that as well. Finally the modules file is updated with any modules the user selected, and the whole output directory is 'cpio'ed to create an initramfs image. That is then gzipped to compress it for efficiency.

### mkefiusb
#### Options
* -d <device path>
* -g Build GRUB.
* -i Build initrd.
* -k <path to kernel package> This is the path to a Debian/RedHat kernel package which will be installed.
* -m <kernel module name> Name of a kernel module to load at boot time. Can be specified multiple times.
* -p Erase target device and build required partitions.

`e.g. ./mkefiusb.sh -p -d /dev/sdb -k ../linux-image-5.4.0-rc7.deb -i -m "i2c-qcom-geni" -g`

Builds a UEFI bootable device by erasing '/dev/sdb'. It then creates 2 GPT partitions labeled 'IHEFI' (ESP, EFI System Partition), and 'IHFILES' used to build GRUB. These labels are important as they are used to identify the partitions in the next steps. The kernel package is then unpacked in the ESP. The initramfs image is built, and placed in the ESP as well. GRUB is then downloaded from it's repository if not already, and built. Then installed into the ESP. Finally a config is built for GRUB from the contents of the ESP /boot directory. 
