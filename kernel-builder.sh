#!/bin/bash
#
# Automatic Grsecurity patched kernel compile script for Debian.
#
# Link to this script from where you want to build/store the kernels, eg:
#   ln -sf <path_to_repo>/kernel-builder.sh ~/src/kernel/

KEYSERVER="keyserver.ubuntu.com"

#########################################################################
## functions:

fail() {
  echo -e "\n [X] Error: $@ \n" >&2;
  exit 1
}


find_grsec() {
  # Parse the grsecurity website for testing version number of grsec and kernel it's for
  echo -e "\n [*] Checking what kernel latest Grsec patch uses";
  PATCH=$(wget -q https://grsecurity.net/download.php -O - | grep -Eio href.*test\/.+patch \
    | cut -d'"' -f2 | cut -d'/' -f2)
  [ -n "$PATCH" ] || fail "Could not gather patch file info from grsec page"
  KVER=$(echo "$PATCH" | cut -d"-" -f3)
  [ -n "$KVER" ] || fail "Could not parse kernel version from grsec site"

  # Majour, medium, minor releases
  MA=`echo $KVER | awk -F \. {'print $1'}` # y.x.x
  ME=`echo $KVER | awk -F \. {'print $2'}` # x.y.x
  MI=`echo $KVER | awk -F \. {'print $3'}` # x.x.y

  # When MI is 0 Grsec site will publish as 3.10.0 and Kernel.org will use 3.10. Hack to fix this:
  if [ "$MI" = "0" ]; then
    KVER="$MA.$ME"
  fi
}

getgrsec() {
  echo -e "\n [*] Need to download grsecurity patch \n";
  wget -P $KVER/ -c "https://grsecurity.net/test/$PATCH" --no-verbose || fail "get $PATCH"
  wget -P $KVER/ -c "https://grsecurity.net/test/$PATCH.sig" --no-verbose || fail "get $PATCH.sig"
  echo
  gpg --verify "$KVER/$PATCH.sig" &> /dev/null || fail "wrong $PATCH signature"
  NEWPATCH="yes"
}

getkernsource() {
  ## which kernel source to get
  # libre srouce
  if [ "$KERNTYPE" = "libre" ]; then
    KERNURL="http://linux-libre.fsfla.org/pub/linux-libre/releases/$MA.$ME.$MI-gnu/"
    KERNTAR="linux-libre-$MA.$ME.$MI-gnu.tar"
  fi
  # kernel.org src
  if [[ $MA -eq 3 && $ME -ne 0 ]]; then
    KERNORGURL="https://www.kernel.org/pub/linux/kernel/v$MA.x/"
  else
    KERNORGURL="https://www.kernel.org/pub/linux/kernel/v$MA.$ME/"
  fi
  if [ "$KERNTYPE" = "linus" ]; then
    KERNURL="$KERNORGURL"
    KERNTAR="linux-$KVER.tar"
  fi
  # filenames
  KERNXZ="$KERNTAR.xz"
  KERNSIGN="$KERNTAR.sign"
  # changelog
  CHANGELOG="ChangeLog-$KVER"
  CHANGELOGSIGN="$CHANGELOG.sign"

  echo -e " [*] Downloading kernel source \n"
  # selected source
  wget -P $KVER/$KERNTYPE/ -c "$KERNURL/$KERNXZ" --no-verbose || fail "downloading kernel source"
  wget -P $KVER/$KERNTYPE/ -c "$KERNURL/$KERNSIGN" --no-verbose || fail "downloading kernel source signature"
  # changelog
  if [ ! -f "$KVER/$CHANGELOG" ]; then
    wget -P $KVER/ -c "$KERNORGURL$CHANGELOG" --no-verbose || fail "downloading kernel changelog"
    wget -P $KVER/ -c "$KERNORGURL$CHANGELOGSIGN"  --no-verbose || fail "downloading kernel changelog signature"
    gpg --verify "$KVER/$CHANGELOGSIGN" &> /dev/null || fail "Wrong signature on kernel changelog!"
  fi
  # get deblob log if using libre kerbel
  if [ $KERNTYPE = "libre"  ]; then
    wget -P $KVER/$KERNTYPE/ -c "$KERNURL/linux-libre-$KVER-gnu.log" --no-verbose || fail "downloading kernel deblob log"
  fi
  echo -e "\n";
}

uncompress() {
  echo -e " [*] Decompressing kernel source";
  xz --decompress --keep "$KVER/$KERNTYPE/$KERNXZ" || fail "decompress kernel xz"
  echo " [*] Checking source tar signature";
  gpg --verify "$KVER/$KERNTYPE/$KERNSIGN" &> /dev/null || fail "Wrong signature on kernel source!"
  echo " [*] Extracting tar.";
  tar xf "$KVER/$KERNTYPE/$KERNTAR" --directory $KVER/$KERNTYPE || fail "extract kernel tar"
  rm -f $KVER/$KERNTYPE/$KERNTAR
}

compilekern() {
  echo -e "\n [*] Starting Kernel build"
  # Check for a config file
  if [ ! -f "$KVER/$KERNTYPE/linux-$KVER/.config"  ]; then
    fail "can not compile, missing .config"
  fi
  # Check that grsec patch has been applied
  if [ ! -d "$KVER/$KERNTYPE/linux-$KVER/grsecurity" ]; then
    fail "kernel source has not been patched with grsec"
  fi

  cd $KVER/$KERNTYPE/linux-$KVER/
  sudo make oldconfig || fail "make oldconfig"

  startbuild_time=`date +%s`
  sudo make -j3 bzImage || fail "make bzimage"
  sudo make deb-pkg || fail "compiling with 'make deb-pg' failed"
  endbuild_time=`date +%s`

  echo -e " \n [*] build time: `expr $endbuild_time - $startbuild_time` seconds. \n"
  timebuilt=`date "+%H_%M_%d-%m-%y"`

  cd ../../
  mkdir build_$KERNTYPE_$timebuilt -v
  cp $KERNTYPE/linux-$KVER/.config build_$KERNTYPE_$timebuilt/build.config -v
  mv $KERNTYPE/*.deb build_$KERNTYPE_$timebuilt/ -v
  cd $CWD1

  echo -e "\n [*] Kernel compiled.";
}

#########################################################################

# environment
CWD1=`pwd`

## Checks
# Check for bash
[ -z "$BASH_VERSION" ] && fail "Need bash"

# Fail if run as root
[ "$(id -u)" = "0" ] && fail "Don't roll as root"

# Fail if not debian
[ ! -f  "/etc/debian_version" ] && fail "This script is currently just for Debian based systems"

# Get input
usage() {
  printf """
options:
 -k <linus|libre>  (Kernel) type
                   "libre" = Use Libre-Linux from FSFLA
                   "linus" = Use kernel.org release
 -c <config file>  Kernel (config file) !not prsesently working!
 -r                Use current (running) kernels config !not presently working!
 -p                Use the (previous) config file built
 -u                (Update) to the latest kernel and grsec patch
 -b                (Build) the latest kernel we have
 """
}

while getopts ":k:c:rpub" opt; do
  case $opt in
    k)
      if [ "$OPTARG" != "linus" ] && [ "$OPTARG" != "libre" ]; then
        echo "Incorrect kernel type specified"
        usage
        exit 1
      fi
      echo "$OPTARG Kernel selected."
      KERNTYPE=$OPTARG
      ;;
    c)
      echo "config was triggered, Parameter: $OPTARG" >&2
      ;;
    r)
      echo "running was triggered." >&2
      ;;
    p)
      echo "Using previous config."
      LASTCONFIG="y"
      ;;
    u)
      echo "Latest Kernel and grsec patch will be downloaded"
      RUNUPDATES="y"
      ;;
    b)
      BUILD="y"
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      usage
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      usage
      exit 1
      ;;
  esac
done

# Exit if no options are given
[ $# -eq 0 ] && usage && exit 1

# Are these packages installed?
GCC_VERSION=$(ls -al /usr/bin/gcc | cut -d">" -f2 | cut -d"-" -f2)
GCC_PLUGIN_DEV="gcc-"$GCC_VERSION"-plugin-dev"
PACKAGENEEDS="build-essential make fakeroot pgpgpg wget git libncurses5-dev curl wget xz-utils grub-legacy "$GCC_PLUGIN_DEV

for thepackage in $PACKAGENEEDS
do
  dpkg-query -s $thepackage &> /dev/null || needthese="$needthese $thepackage"
done

if [ `echo ${needthese} | wc -w` -gt 0 ]; then
  printf "You need to install the following packages:$needthese\nWould you like to install these now?\n[y/N] "
  read response
  if [[ "$response" =~ [yY] ]]; then
    sudo apt-get install$needthese
  else
    fail "You need to run: sudo apt-get install$needthese"
  fi
fi

## Do we have the pgp keys we need to use to check signed files? If not try to download them
# for kernel.org kernel:
if [ "$KERNTYPE" = "linus" ]; then
  if [ `gpg --list-keys 6092693E | wc -l` -eq 0 ]; then
  echo "[*] don't have kernel gpg keys";
  gpg --keyserver $KEYSERVER --recv-keys 6092693E &> /dev/null || fail "could not get kernel pgp key"
  GPGKERN=`gpg --fingerprint 6092693E | grep fingerprint | tr -d ' ' | sed 's/Keyfingerprint\=//g'`
  if [ "$GPGKERN" != "647F28654894E3BD457199BE38DBBDC86092693E" ]; then
    fail "Kernel pgp key has wrong fingerprint!"
  fi
  echo "[*] Got Greg Kroah-Hartman's pgp key (Linux kernel stable release signing key)";
  fi
fi

# for linux-libre kernel:
if [ "$KERNTYPE" = "libre" ]; then
  if [ `gpg --list-keys 7E7D47A7 | wc -l` -eq 0  ]; then
  echo "[*] don't have libre-linux gpg keys";
  gpg --keyserver $KEYSERVER --recv-keys 7E7D47A7 &> /dev/null || fail "could not get linux-libre pgp key"
  GPGKERN=`gpg --fingerprint 7E7D47A7 | grep fingerprint | tr -d ' ' | sed 's/Keyfingerprint\=//g'`
  if [ "$GPGKERN" != "474402C8C582DAFBE389C427BCB7CF877E7D47A7" ]; then
    fail "Linux-libre pgp key has wrong fingerprint!"
  fi
  echo "[*] Got Linux-libre pgp key";
  fi
fi

# for grsec:
if [ `gpg --list-keys 4245D46A | wc -l` -eq 0 ]; then
  echo "[*] don't have grsec pgp key";
#  curl -# -O https://grsecurity.net/spender-gpg-key.asc
  gpg --keyserver $KEYSERVER --recv-keys 4245D46A &> /dev/null || fail "could not get grsecurity pgp key"
#  gpg --import spender-gpg-key.asc &> /dev/null || fail "importing spenders pgp key"
  GPGSPEND=`gpg --fingerprint 4245D46A | grep fingerprint | tr -d ' ' | sed 's/Keyfingerprint\=//g'`
  if [ "$GPGSPEND" != "9F74393D7E7FFF3C6500E7789879B6494245D46A" ]; then
    fail "Spenders gpg key has wrong fingerprint!"
  fi
  echo "[*] Got Bradley Spengler's pgp key";
fi

#########################################################################
## actions:

# check for and get updates?
if [[ "$RUNUPDATES" = "y" ]]; then
  find_grsec
  if [ ! -d "$KVER" ]; then
    mkdir $KVER
  fi
  # Do we have a current kernel that has been patched before?
  if [ -d "$KVER/$KERNTYPE/linux-$KVER/grsecurity" ]; then
    OLDPATCH="yes"
  fi
  # download current grsec patch if we don't have it.
  if [ ! -f "$KVER/$PATCH" ]; then
    getgrsec
  fi
  # download currently supported kernel by grsec if we don't have it
  if [ ! -d "$KVER/$KERNTYPE" ]; then
    mkdir $KVER/$KERNTYPE
    getkernsource
    uncompress
  fi
  # if our kernel has been patched by grsec and there is a newer patch available
  # wipe the kernel source so we can patch with the most recent version of grsec
  if [[ $OLDPATCH = "yes" && $NEWPATCH = "yes" ]]; then
    echo -e "\n [*] removing preivously patched kernel source";
    rm $KVER/$KERNTYPE/linux-$KVER -rf || fail "removing previously patched kernel source"
    uncompress
  fi
  # patch the kernel with grsecurity.
  if [ ! -d "$KVER/$KERNTYPE/linux-$KVER/grsecurity" ]; then
    cd "$KVER/$KERNTYPE/linux-$KVER" || fail "cd linux-$KVER"
    patch -p1 < "../../$PATCH" &>/dev/null || fail "apply $PATCH"
    cd $CWD1 || "fail wd return"
    echo -e "\n [*] Applied patch to kernel source."
  fi
else
  # set kver if not from checking updates
  KVER=`ls | grep -o "[0-9]*.[0-9]*.[0-9]" | sort -k2 -t. -n | tail -n1`
fi

# copy over old config?
if [[ "$LASTCONFIG" = "y" ]]; then
  # find most recent build config
  LASTBUILDCONF=$(find -type f -name build.config -exec ls {} -t \; 2>/dev/null| grep build_ | tail -n1)
  if [ -z $LASTBUILDCONF ]; then
    echo "No previous config found"
    exit 1
  fi
  echo -e "\n [*] Using config from most recent build"
  cp $LASTBUILDCONF $KVER/$KERNTYPE/linux-$KVER/.config -v
fi

#compile kernel?
if [[ "$BUILD" = "y" ]]; then
  compilekern
fi

echo -e "\n [*] Complete."
exit 0
