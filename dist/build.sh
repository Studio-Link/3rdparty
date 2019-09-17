#!/bin/bash -ex

source dist/lib/versions.sh
source dist/lib/functions.sh

make_opts="-j4"

if [ "$BUILD_OS" == "windows32" ] || [ "$BUILD_OS" == "windows64" ]; then
    curl -s https://raw.githubusercontent.com/studio-link-3rdparty/arch-travis/master/arch-travis.sh | bash
    exit 0
fi

# Start build
#-----------------------------------------------------------------------------
sl_prepare

sl_extra_lflags="-L ../opus -L ../my_include "

if [ "$TRAVIS_OS_NAME" == "linux" ]; then
    sl_extra_modules="alsa slrtaudio"
else
    export MACOSX_DEPLOYMENT_TARGET=10.9
    sl_extra_lflags+="-L ../openssl ../openssl/libssl.a ../openssl/libcrypto.a "
    sl_extra_lflags+="-framework SystemConfiguration "
    sl_extra_lflags+="-framework CoreFoundation"
    sl_extra_modules="slrtaudio"
    sed_opt="-i ''"
fi

# Build libsamplerate
#-----------------------------------------------------------------------------
if [ ! -d libsamplerate ]; then
    git clone https://github.com/studio-link-3rdparty/libsamplerate.git
    pushd libsamplerate
    ./autogen.sh
    ./configure
    make
    cp -a ./src/.libs/libsamplerate.a ../my_include/
    cp -a ./src/samplerate.h ../my_include/
    popd
fi

# Build RtAudio
#-----------------------------------------------------------------------------
if [ ! -d rtaudio-${rtaudio} ]; then
    sl_get_rtaudio
    pushd rtaudio-${rtaudio}
    if [ "$TRAVIS_OS_NAME" == "linux" ]; then
        ./autogen.sh --with-alsa --with-pulse
    else
        export CXXFLAGS="-Wno-deprecated -DUNICODE"
        sudo mkdir -p /usr/local/Library/ENV/4.3
        sudo ln -s $(which sed) /usr/local/Library/ENV/4.3/sed
        ./autogen.sh --with-core
    fi
    make $make_opts
    unset CXXFLAGS
    cp -a .libs/librtaudio.a ../my_include/
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

# Build openssl
#-----------------------------------------------------------------------------
if [ ! -d openssl-${openssl} ]; then
    sl_get_openssl
    cd openssl
    ./config no-shared
    make $make_opts build_libs
    cp -a include/openssl ../my_include/
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

s3_path="s3_upload/3rdparty/$version_t"
mkdir -p $s3_path
zip -r $BUILD_OS.zip my_include openssl
mv $BUILD_OS.zip $s3_path
