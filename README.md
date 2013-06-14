About
==============
Tested using both Debian Stable and Testing with Kernel 3.8.5
 
This script will:
 
 - Check the build environment.
	- will exit+warn can't find build packages.
	- wil exit if run as root.
 - Check the grsecuity website (over HTTPS) for the most recent testing version of the patch. 
 - Download grsec patch and the Linux Kernel sources (over HTTPS) that the patch uses, if we don't have them locally. 
 - Verify downloads with pgp keys.
	- will download keys from keyservers if missing.
 - Untar Linux source (will keep compressed source).
 - Patch the kernel with the most recent grsec patch.
	- if there is a new grsec patch then rm the old linux dir and untar.
 - Build the .deb packages, if we have a .config file.
 - Copy .deb files and .config from build into a folder
 
Place this script where you want to build/store the kernels, eg: copy the script to /home/theuser/sources/kernels/ and run it from there.

To compile with last found build config use: ./get-and-build.sh buildlastconfig

Grsec notes
==============

I found that PAX was killing update-grub programs, which are run on after a kernel install by /etc/kernel/postinst.d/zz-update-grub and on removing a kernel by /etc/kernel/postrm.d/zz-update-grub

To stop this use the paxctl command to disable protections on /usr/sbin/grub-probe and /usr/bin/grub-script-check

Backup the binaries first before converting them. (paxctl -cC /bin/program) 

Credit
==============
This script is based on https://github.com/StalkR/misc/blob/master/kernel/get-and-build.sh


