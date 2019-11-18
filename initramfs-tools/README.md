# initramfs-tools

This provides a hook for initramfs-tools which pulls in additional firmware files when building initrd images for kernels.
Copy the files to their respective places in '/etc/initramfs-tools/', then run 'update-initramfs -u -k {kernel-version}' to regenerate the initrd.

* hooks/firmware_hook - Updates the initrd image with firmware files specfied in
* firmware - File specifies individual files to import in to initrd image (don't use directories)
