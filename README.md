Kernel build script
==============

Tested using both Debian Stable and Testing with Kernel 3.8.5
 
This script will:
 
 - Check the build environment.
	- will exit+warn if incorrect
 - Check the grsecuity website for the most recent testing version of the patch. 
 - Download grsec patch and the Linux Kernel source that the patch uses, if we don't have them locally. 
 - Verify downloads with pgp keys
	- will download keys from keyservers if missing.
 - Untar Linux source (will keep compressed source)
 - Patch the kernel with the most recent grsec patch
	- if there is a new grsec patch then rm the old linux dir and untar
 - Build the .deb packages, if we have a .config file.
 - Copy .deb files and .config from build into a folder
 

 
  Kernel build notes
==============

 - Packages needed for build:
	apt-get install build-essential make fakeroot pgp wget ncurses-dev curl wget xz-utils 
 - Don't compile as root.	