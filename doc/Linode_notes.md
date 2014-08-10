Custom Debian kernel with grsecurity on Linode
==============

There are good instructions on the Linode Library on how to compile and use your own Kernel, but I do things slightly differently by using the grsecurity hardening patch and build a .deb (Debian) package of my kernel.

The Linode kernels are configured to be nice and lean. I use them as a good base config and have then:

- Disabled kernel modules (don't need these on my server)
- Disabled network filesystem support
- Enabled dmesg restrictions

Under grsecurity I have enabled almost all of the settings without any issues. Depends on what your requirements are as to how suitable some of these options are.

Be sure to enable grsecurity hardening for Xen guests.

Linode wiki build instructions:
--------------
	$ make -j3 bzImage
	$ make -j3 modules
	$ make
	$ make install
	$ make modules_install

Building a .deb package instead
--------------
	$ make oldconfig
	$ make -j3 bzImage
	$ make deb-pkg

Other brief relevant notes for Linode:
--------------
- Add barrier=0 to your fstab file.
- To stop all the page allocation errors I was getting In sysctl.conf I had to add vm.min_free_kbytes = 5120
- If you get "close blk: backend at /local/domain/0/backend/vbd/6401/51712" then disable "Sanitize kernel stack" in Grsecurity is apparnently the fix.



