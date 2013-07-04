#!/bin/bash

# Author: Hirakendu Das

# 0. Some variables.

# Set Chromium version and SVN revision. Use http://omahaproxy.appspot.com/
# to find current stable version, true branch and branch revision.
# Use the revision lookup tool to verify branch revision.
if [ -z "${CHROMIUM_VERSION}" ]; then
  CHROMIUM_VERSION="28.0.1500.71"
fi
# CHROMIUM_SVN_BRANCH="1500"
# CHROMIUM_SVN_REVISION="209842"

# Get API keys (one time) as outlined in https://code.google.com/p/chromium/wiki/LinuxBuildInstructions
# and https://sites.google.com/a/chromium.org/dev/developers/how-tos/api-keys.
if [ -z "${GOOGLE_API_KEY}" ]; then
  GOOGLE_API_KEY=""
  GOOGLE_DEFAULT_CLIENT_ID=""
  GOOGLE_DEFAULT_CLIENT_SECRET=""
fi

# These keys are for the author's personal builds only.
# Please get own keys as indicated above.
GOOGLE_API_KEY_HDAS="AIzaSyARhw5TMluIVNJXFc7eDB3EAZbt9VEUJRU"
GOOGLE_DEFAULT_CLIENT_ID_HDAS="959953815234.apps.googleusercontent.com"
GOOGLE_DEFAULT_CLIENT_SECRET_HDAS="ZehXu6hIJ_e4_rTx3UXHW6PK"
if [ -z "${GOOGLE_API_KEY}" ]; then
  GOOGLE_API_KEY="${GOOGLE_API_KEY_HDAS}"
  GOOGLE_DEFAULT_CLIENT_ID="${GOOGLE_DEFAULT_CLIENT_ID_HDAS}"
  GOOGLE_DEFAULT_CLIENT_SECRET="${GOOGLE_DEFAULT_CLIENT_SECRET_HDAS}"
fi

ARCH="$(uname -i)"

# 1. Install prerequisites.
echo -e "\n\n1. Installing pre-requisite dependencies.\n"
# 1.1. Install dependencies listed in
# https://code.google.com/p/chromium/wiki/LinuxBuildInstructionsPrerequisites.
echo -e "\n1.1. Installing main pre-requisites\n"
sudo yum install -y subversion git git-svn pkgconfig python perl gcc-c++ bison \
    flex gperf nss-devel nspr-devel gtk2-devel glib2-devel freetype-devel \
    atk-devel pango-devel cairo-devel fontconfig-devel GConf2-devel \
    dbus-devel alsa-lib-devel libX11-devel expat-devel bzip2-devel \
    dbus-glib-devel elfutils-libelf-devel libjpeg-devel \
    mesa-libGLU-devel libXScrnSaver-devel \
    cups-devel libXtst-devel libXt-devel pam-devel 
if [ "${ARCH}" == "x86_64" ]; then
    sudo yum install -y glibc.i686 libstdc++.i686 
fi
# 1.2. Install additional dependencies found later on while configuring:
# yum whatprovides */libpci.pc
# yum whatprovides */gnome-keyring-1.pc
# yum whatprovides */libudev.pc
# yum whatprovides */libpulse.pc
echo -e "\n1.2. Installing additional pre-requisites\n"
sudo yum install -y pciutils-devel libpciaccess-devel gnome-keyring-devel libudev-devel \
    pulseaudio-libs-devel
# 1.3. Install speech_dispatcher dependencies from
# http://li.nux.ro/download/nux/dextop/el6/x86_64/.
echo -e "\n1.3. Installing speech-dispatcher\n"
if [ "${ARCH}" == "x86_64" ]; then
     sudo yum install -y speech_dispatcher/*.x86_64* speech_dispatcher/*.noarch*
elif [ "${ARCH}" == "i386" ]; then
     sudo yum install -y speech_dispatcher/*.i686* speech_dispatcher/*.noarch*
fi

# 2. Get source code.
echo -e "\n\n2. Getting chromium source code.\n"
# 2.1. Install depot_tools (includes gclient) from
#  http://dev.chromium.org/developers/how-tos/install-depot-tools
echo -e "\n2.1. Fetching depot_tools and adding temporarily to PATH.\n"
rm -rf depot_tools
git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
export PATH="${PATH}:$(pwd)/depot_tools"
# 2.2. Download Chromium source code from SVN using gclient (in depot_tools).
export GYP_GENERATORS=make
echo -e "\n2.2 Downloading the chromium source from SVN, ~1.2 GB (5.4 GB expanded) 20 minutes.\n"
rm -rf chromium_build
if [ -f chromium_build.tgz ]; then
  # Re-use existing source archive if possible.
  time tar -xzf chromium_build.tgz
  cd chromium_build
else
  mkdir chromium_build && cd chromium_build
  # Configure the .gclient file.
  gclient config https://src.chromium.org/chrome/releases/${CHROMIUM_VERSION}
  cat << EOF > .gclient
solutions = [
  { "name"        : "${CHROMIUM_VERSION}",
    "url"         : "https://src.chromium.org/chrome/releases/${CHROMIUM_VERSION}",
    "deps_file"   : "DEPS",
    "managed"     : True,
    "custom_deps" : {
    "src/third_party/WebKit/LayoutTests": None,
    "src/content/test/data/layout_tests/LayoutTests": None,
    "src/chrome/tools/test/reference_build/chrome_win": None,
    "src/chrome_frame/tools/test/reference_build/chrome_win": None,
    "src/chrome/tools/test/reference_build/chrome_linux": None,
    "src/chrome/tools/test/reference_build/chrome_mac": None,
    "src/third_party/hunspell_dictionaries": None,
    },
    "safesync_url": "",
  },
]
EOF
fi
# Sync.
time gclient sync
# 2.3. Archive for future.
echo -e "\n2.3 Archiving downloaded code for reuse, ~1.5 GB in 5 minutes.\n"
cd ..
rm -rf chromium_build.tgz
time tar -czpf chromium_build.tgz chromium_build
# Go to source folder to build.
cd chromium_build/src
# SVN info should show the same branch and revision as the revision lookup tool
# in http://omahaproxy.appspot.com/.
svn info
CHROMIUM_SVN_REVISION="$(svn info  | grep Revision | cut -f2 -d: | sed s/\ //)"

# 3. Build source code.
echo -e "\n\n3. Building chromium source code.\n"
# 3.1. Patch.
echo -e "\n3.1. Patching.\n"
# This patch is required to compile with gcc-4.4.
# From http://code.google.com/p/v8/issues/detail?id=2093.
patch -p1 < ../../patches/c21c51a-new.patch
# This patch includes gtk compatibility headers for older GTK versions.
patch -p1 < ../../patches/gtk_compat.patch
major_version="$(echo $CHROMIUM_VERSION | cut -f1 -d.)"
if [ "${major_version}" -le "26" ]; then
  # This patch adds extern "C" qualifiers for udev library headers.
  patch -p1 < ../../patches/udev_extern_c_26.patch
else
  # Patch differs slightly for versions > 27, system_monitor -> storage_monitor.
  patch -p1 < ../../patches/udev_extern_c.patch
  # Patch to disable warning message for GTK versions older than 2.20.0.
  # EL6 uses GTK 2.18.x.
  patch -p1 < ../../patches/disable_os_info_bar_el6.patch
fi
# This optional patch increases the space above tab bar by 4 pixels,
# to aid in moving the window by dragging the window.
patch -p1 < ../../patches/title_bar_size.patch
# 3.2. Configure.
echo -e "\n3.2. Configuring, ~ 1 minute.\n"
time gclient runhooks
time build/gyp_chromium -Dgoogle_api_key="${GOOGLE_API_KEY}" -Dgoogle_default_client_id="${GOOGLE_DEFAULT_CLIENT_ID}" -Dgoogle_default_client_secret="${GOOGLE_DEFAULT_CLIENT_SECRET}" -Dproprietary_codecs=1 -Dffmpeg_branding=Chrome
# 3.3. Compile.
echo -e "\n3.3. Compiling, ~80 minutes and expands to 7.4 GB.\n"
time make -j4 BUILDTYPE=Release V=1 chrome

# 3.4 Package tar.
echo -e "\n3.4. Packaging tar.\n"
cd ../../
rm -rf chromium-${CHROMIUM_VERSION}
mkdir -p chromium-${CHROMIUM_VERSION}/opt/
cp -a chromium_build/src/out/Release chromium-${CHROMIUM_VERSION}/opt/chromium
rm -rf chromium-${CHROMIUM_VERSION}/opt/chromium/{obj*,.deps}
mkdir -p chromium-${CHROMIUM_VERSION}/usr/share/applications/
cp chromium-devel.desktop chromium-${CHROMIUM_VERSION}/usr/share/applications/
tar -czpf chromium-${CHROMIUM_VERSION}.tgz chromium-${CHROMIUM_VERSION}


# 4. Make RPM.
echo -e "\n\n4. Packaging RPM.\n"
rm -rf rpmbuild
time CHROMIUM_VERSION=${CHROMIUM_VERSION} CHROMIUM_SVN_REVISION=${CHROMIUM_SVN_REVISION} bash chromium_rpm_packager.sh


