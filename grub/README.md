# GRUB

## Patches

These patches alter GRUB's configuration in 2 ways.

* The default kernel command line of 'quiet splash' is replaced with 'efi=novamap' which is required for booting.

* An additional parameter 'devicetree' is added to every linux entry in the GRUB menu to load the appropriate DTB. The parameter __GRUB_DTB_PREFIX__ configures this option, and is set in '/etc/default/grub'. This option configures a prefix which along with the discovered kernel version generates the filename of the appropriate DTB file for that kernel. Note: the patch was generated on a system with '/boot' as a seperate partition, so if '/boot' is part of the root structure replace it with '/boot/dtb/lenovo-yoga-c630'.

General upshot, apply these patches, then create (if you haven't already) a directory '/boot/dtb/'. Put the appropriate DTB files in there with, in this case, the filename 'lenovo-yoga-c630_{kernel_version}.dtb'. Running update-grub manually, or installing the appropriate kernel package should generate the correct 'grub.cfg'.
