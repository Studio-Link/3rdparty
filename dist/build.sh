#!/bin/bash -ex

source dist/lib/versions.sh
source dist/lib/functions.sh

make_opts="-j4"

# Start build
#-----------------------------------------------------------------------------
sl_prepare

sl_extra_lflags="-L ../opus -L ../my_include "

if [ "$BUILD_OS" == "linux" ]; then
    sl_extra_modules="alsa slrtaudio"
else
    export MACOSX_DEPLOYMENT_TARGET=10.9
    sl_extra_lflags+="-L ../openssl ../openssl/libssl.a ../openssl/libcrypto.a "
    sl_extra_lflags+="-framework SystemConfiguration "
    sl_extra_lflags+="-framework CoreFoundation"
    sl_extra_modules="slrtaudio"
    sed_opt="-i ''"
fi

if [ "$BUILD_TARGET" == "macos_arm64" ]; then
    xcode="/Applications/Xcode_12.2.app/Contents/Developer"
    sysroot="$xcode/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
    sudo xcode-select --switch $xcode
    BUILD_CFLAGS="$CFLAGS -arch arm64 -isysroot $sysroot -host arm64"
    BUILD_CXXFLAGS="$CXXFLAGS -arch arm64 -isysroot $sysroot -host arm64"
fi

# Build libsamplerate
#-----------------------------------------------------------------------------
if [ ! -d libsamplerate ]; then
    git clone https://github.com/studio-link-3rdparty/libsamplerate.git
    pushd libsamplerate
    ./autogen.sh
    export CFLAGS=$BUILD_CFLAGS
    export CXXFLAGS=$BUILD_CXXFLAGS
    ./configure
    make

    cp -a ./src/.libs/libsamplerate.a ../my_include/
    cp -a ./src/samplerate.h ../my_include/
    popd
fi

# Build openssl
#-----------------------------------------------------------------------------
if [ ! -d openssl-${openssl} ]; then
    sl_get_openssl
    cd openssl
if [ "$BUILD_TARGET" == "macos_arm64" ]; then
    cp -a ../../dist/patches/openssl-10-main.conf Configurations/10-main.conf
    ./Configure no-shared darwin64-arm64-cc no-asm
else
    ./config no-shared
fi
    make $make_opts build_libs
    cp -a include/openssl ../my_include/
    cd ..
fi

# Build soundio
#-----------------------------------------------------------------------------
if [ ! -d soundio ]; then
    sl_get_soundio
    pushd soundio
    mkdir build
    pushd build
    if [ "$BUILD_TARGET" == "linux" ]; then
        cmake -D BUILD_DYNAMIC_LIBS=OFF -D CMAKE_BUILD_TYPE=Release -D ENABLE_JACK=OFF ..
    fi
    if [ "$BUILD_TARGET" == "linuxjack" ]; then
        cmake -D BUILD_DYNAMIC_LIBS=OFF -D CMAKE_BUILD_TYPE=Release ..
    fi
    if [ "$BUILD_OS" == "macos" ]; then
        cmake -D BUILD_DYNAMIC_LIBS=OFF -D CMAKE_BUILD_TYPE=Release ..
    fi
    make
    popd

    cp -a build/libsoundio.a ../my_include/
    popd
fi

# Build FLAC
#-----------------------------------------------------------------------------
if [ ! -d flac-${flac} ]; then
    sl_get_flac

    cd flac
    ./configure --disable-ogg --enable-static
    make $make_opts
    cp -a include/FLAC ../my_include/
    cp -a include/share ../my_include/
    cp -a src/libFLAC/.libs/libFLAC.a ../my_include/
    cd ..
fi


# Build opus
#-----------------------------------------------------------------------------
if [ ! -d opus-$opus ]; then
    wget "https://archive.mozilla.org/pub/opus/opus-${opus}.tar.gz"
    tar -xzf opus-${opus}.tar.gz
    cd opus-$opus; ./configure --with-pic; make; cd ..
    mkdir opus; cp opus-$opus/.libs/libopus.a opus/
    mkdir -p my_include/opus
    cp opus-$opus/include/*.h my_include/opus/ 
fi

# Testing and prepare release upload
#-----------------------------------------------------------------------------
zip -r $BUILD_TARGET.zip my_include openssl opus
