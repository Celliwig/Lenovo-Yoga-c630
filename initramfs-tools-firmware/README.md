# initramfs-tools-firmware

This provides a hook for initramfs-tools which pulls in additional firmware files when building initrd images for kernels.

* hooks/firmware_hook - Updates the initrd image with firmware files specfied in
* firmware - File specifies individual files to import in to initrd image (don't use directories)

The package updates the firmware config file on installation (or dpkg-reconfigure) with the firmware listed in the devicetree.
