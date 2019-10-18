# UEFI

## Shell
This shell was compiled from the Tianocore source. Useful for configuring boot source/order which can be selected from the UEFI boot menu by pressing (Fn-)F12 (dependent on whether Hotkey Mode has been disabled or not). 

### Booting
Copy to somewhere on the EFI system partition eg: /boot/efi/EFI/Utils/Shell.efi. If you then reboot, and when GRUB's menu is displayed hit 'c'. This will drop you to the commandline. If you then type:
```
set root=(hd5,gpt1)
chainloader /efi/Utils/Shell.efi
boot
```
This will run the shell.

### Usage (use with care, you can break things!!!)

**bcfg** -To view/alter the boot source/order (numbers in bold represent the item in the boot order, not variable name)

* help bcfg                                                       _; Show help for bcfg_
* bcfg boot dump                                                  _; View the current boot configuration_
* bcfg boot add __0__ fs2:\EFI\Utils\Shell.efi "UEFI Shell"       _; Add the UEFI shell as the first item to boot_
* bfcg boot mv __1__ __0__                                        _; Boot order: swap 1st and 2nd items_
* bcfg boot rm __0__                                              _; Remove the first item in the boot list_
