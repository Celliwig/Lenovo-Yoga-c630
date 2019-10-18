# GRUB

## Patches

These patches alter grubs configuration in 2 ways.

* The default kernel command line of 'quiet splash' is replaced with 'efi=novamap' which is required for booting.

* An additional parameter 'devicetree' is added to every linux entry in the GRUB menu.
