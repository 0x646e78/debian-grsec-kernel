#!/bin/bash
#
# Automatic Grsecurity patched kernel compile script for Debian.
#
# Will build a .deb of the kernel only if we have a .config for it,
# otherwise this script will just check for and manage updates.
#
# Tested with Kernels 3.9.5 and on Debian Wheezy and Squeeze.
#
# Place this script where you want to build/store the kernels,
# eg: copy script to /home/user/source/kernels/ and run it there.
#
# To compile with last found build config: ./get-and-build.sh buildlastconfig
#
# This script is based on:
# https://github.com/StalkR/misc/blob/master/kernel/get-and-build.sh


fail() {
	echo -e "\n [X] Error: $@ \n" >&2;
	exit 1
}

## Check our current building environment.
CWD1=`pwd`
[ -z "$BASH_VERSION" ] && fail "need bash"
[ "$(id -u)" = "0" ] && fail "don't roll as root"
[ ! -f  "/etc/debian_version" ] && fail "this script is for Debian"

## are these packages installed?
PACKAGENEEDS="build-essential make fakeroot pgpgpg wget git ncurses-dev curl wget xz-utils grub-legacy paxctl"
for thepackage in $PACKAGENEEDS
do
	dpkg-query -W $thepackage &> /dev/null || needthese="$needthese $thepackage"
done
if [ `echo ${needthese} | wc -w` -gt 0 ]; then
	fail "You need to run: sudo apt-get install $needthese"
fi

## do we have these pgp keys, if not try to download them
if [ `gpg --list-keys 6092693E | wc -l` -eq 0 ]; then
        echo "[*] don't have kernel gpg keys";
        gpg --recv-keys 6092693E &> /dev/null || fail "gpg get kernel keys"
        GPGKERN=`gpg --fingerprint 6092693E | grep fingerprint | tr -d ' ' | sed 's/Keyfingerprint\=//g'`
        if [ "$GPGKERN" != "647F28654894E3BD457199BE38DBBDC86092693E" ]; then
                fail "Kernel pgp key has wrong fingerprint!"
        fi
        echo "[*] Got Greg Kroah-Hartman's pgp key (Linux kernel stable release signing key)";
fi
# for grsec
if [ `gpg --list-keys 4245D46A | wc -l` -eq 0 ]; then
        echo "[*] don't have grsec pgp key";
        curl -# -O https://grsecurity.net/spender-gpg-key.asc
        gpg --import spender-gpg-key.asc &> /dev/null
        GPGSPEND=`gpg --fingerprint 4245D46A | grep fingerprint | tr -d ' ' | sed 's/Keyfingerprint\=//g'`
        if [ "$GPGSPEND" != "9F74393D7E7FFF3C6500E7789879B6494245D46A" ]; then
                fail "Spenders gpg key has wrong fingerprint!"
        fi
        echo "[*] Got Bradley Spengler's pgp key";
fi

## Parse the grsecurity website for testing version number of grsec and kernel it's for
echo -e "\n [*] Kernel update: Checking versions";
GRSEC=$(curl -s https://grsecurity.net/test.php)
[ -n "$GRSEC" ] || fail "downloading grsecurity page"
PATCH=$(echo "$GRSEC" | grep -o 'grsecurity-[.0-9]*-[.0-9]*-[0-9]*\.patch' | sort -ru | head -n 1)
[ -n "$PATCH" ] || fail "parse patch file from grsec page"
KVER=$(echo "$PATCH" | sed 's/^grsecurity-[0-9.]\+-\([0-9.]\+\)-[0-9]\+\.patch/\1/')
[ -n "$KVER" ] || fail "could not parse kernel version"

# sometimes the version numbers change, so this might need altering in the future.
MAJOR=${KVER%%.*} # a.b.c.d => a
REST=${KVER:${#MAJOR}+1} # => b.c.d
MINOR=${REST%%.*} # => b
# linux kernel filename.
TAR="linux-$KVER.tar"
XZ="$TAR.xz"
SIGN="$TAR.sign"

## What is the current Kernel verion? Is grsec supporting current kernel?
KERNCV=$(curl -s https://www.kernel.org/index.html)
[ -n "$KERNCV" ] || fail "could not check kernel.org"
KERNSTABLE=$(echo "$KERNCV" | grep -o 'linux-[.0-9].[.0-9].[.0-9].tar.xz' | sort -ru | head -n 1)
KERNCV=$(echo "$KERNSTABLE" | grep -o '[.0-9].[.0-9].[.0-9]' )
[ -n "$KERNCV" ] || fail "could not parse kernel.org site"

echo "	* Current stable Kernel: $KERNCV";
echo "	* Grsec supports Kernel: $KVER";
echo "	* Grsec Patch `echo $PATCH | sed 's/^.\{,11\}//' | sed 's/.\{6\}$//'`";

## check if we have the required kernel and download if not.
if [ ! -d "$KVER" ]; then
	echo -e "\n [*] Don't have $KVER, downloading.. . \n";
	mkdir $KVER
	wget -P $KVER/ -c "https://www.kernel.org/pub/linux/kernel/v$MAJOR.0/$XZ" --no-verbose || fail "getting $XZ"
	wget -P $KVER/ -c "https://www.kernel.org/pub/linux/kernel/v$MAJOR.0/$SIGN" --no-verbose || fail "getting $SIGN"
	echo -e "\n [*] Uncompressing.. .";
	xz --decompress --keep "$KVER/$XZ" || fail "Decompressing $XZ with xz didn't work"
	gpg --verify "$KVER/$SIGN" &> /dev/null || fail "Wrong $SIGN signature!"
	echo " [*] Extracting tar.";
	tar xf $KVER/$TAR --directory $KVER || fail "could not extract $TAR"
	rm -f "$KVER/$TAR" || fail "remove $TAR"
else
	echo -e "\n [*] Have the current Kernel used by Grsec";
fi

## has this kernel been patched before?
if [ -d "$KVER/linux-$KVER/grsecurity" ]; then
	echo -e "\n [*] Have the current grsecurity patch";
	OLDPATCH="yes"
fi

## download current grsec patch if we don't have it.
if [ ! -f "$KVER/$PATCH" ]; then
	echo -e "\n [*] Need to download newer grsecurity patch \n";
	wget -P $KVER/ -c "https://grsecurity.net/test/$PATCH" --no-verbose || fail "get $PATCH"
	wget -P $KVER/ -c "https://grsecurity.net/test/$PATCH.sig" --no-verbose || fail "get $PATCH.sig"
	echo;
	gpg --verify "$KVER/$PATCH.sig" &> /dev/null || fail "wrong $PATCH signature"
	NEWPATCH="yes"
fi

## if our kernel has been patched by grsec and there is a newer patch available
## wipe the source so we can patch with the most recent version of grsec
if [[ $OLDPATCH = "yes" && $NEWPATCH = "yes" ]]; then
	echo " \n[*] removing preivously patched kernel";
	rm $KVER/linux-$KVER -rf || fail "removing previously patched kernel source"
	xz --decompress --keep "$KVER/$XZ" || fail "to decompress with xz $KVER/$XZ"
	tar xf "$KVER/$TAR" --directory $KVER || fail "extract $TAR"
        rm -f "$KVER/$TAR" || fail "remove $TAR"
fi

## patch the kernel with grsecurity.
if [ ! -d "$KVER/linux-$KVER/grsecurity" ]; then
	cd "$KVER/linux-$KVER" || fail "cd linux-$KVER"
        patch -p1 < "../$PATCH" &>/dev/null || fail "apply $PATCH"
        cd $CWD1 || "fail wd return"
        echo -e "\n [*] Applied patch to kernel source."
fi

## use old config?
if [ "$1" = "buildlastconfig" ]; then
        # find most recent build config
        LASTBUILDCONF=`find -type f -name build.config -exec ls {} -t \; | tail -n1`
        echo -e "\n [*] Using config from last build"
        cp $LASTBUILDCONF $KVER/linux-$KVER/.config -v
fi

## compile the kenel if we have a config for it
if [ -f "$KVER/linux-$KVER/.config"  ]; then
        echo -e "\n [*] Starting Kernel build"
        cd $KVER/linux-$KVER/
        echo | make oldconfig || fail "make oldconfig"
        startbuild_time=`date +%s`
        make -j3 bzImage || fail "make bzimage"
        make deb-pkg || fail "compiling with 'make deb-pg' failed"
        endbuild_time=`date +%s`
        echo -e " \n [*] build time: `expr $endbuild_time - $startbuild_time` seconds. \n";
        timebuilt=`date "+%H_%M_%d-%m-%y"`
        cd ..
        mkdir build_$timebuilt -v
        cp linux-$KVER/.config build_$timebuilt/build.config -v
        mv *.deb build_$timebuilt/ -v
        cd $CWD1
        echo -e "\n [*] Kernel compiled.";
else
	echo -e "\n [*] Could not find the kernel config at $KVER/linux-$KVER/.config so not building"
fi

echo -e "\n [*] Complete";
exit