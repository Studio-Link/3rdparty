#!/bin/bash -ex

export PATH="$PATH:/usr/bin/core_perl"

source dist/lib/versions.sh
source dist/lib/functions.sh

sl_prepare

make_opts="-j4"

mkdir -p mingw
pushd mingw
mingwurl="https://github.com/Studio-Link/mingw/releases/download/v18.01.0"
wget -N $mingwurl/cloog-0.18.5-1-x86_64.pkg.tar.xz
wget -N $mingwurl/isl-0.18-3-x86_64.pkg.tar.xz
wget -N $mingwurl/mingw-w64-binutils-2.29-1-x86_64.pkg.tar.xz
wget -N $mingwurl/mingw-w64-configure-0.1-1-any.pkg.tar.xz
wget -N $mingwurl/mingw-w64-crt-5.0.3-1-any.pkg.tar.xz
wget -N $mingwurl/mingw-w64-gcc-7.2.1.20180116-1-x86_64.pkg.tar.xz
wget -N $mingwurl/mingw-w64-headers-5.0.3-1-any.pkg.tar.xz
wget -N $mingwurl/mingw-w64-pkg-config-2-3-any.pkg.tar.xz
wget -N $mingwurl/mingw-w64-winpthreads-5.0.3-1-any.pkg.tar.xz
wget -N $mingwurl/osl-0.9.1-1-x86_64.pkg.tar.xz
yes | LANG=C sudo pacman -U *.pkg.tar.xz
popd

if [ "$BUILD_OS" == "windows32" ]; then
    _arch="i686-w64-mingw32"
else
    _arch="x86_64-w64-mingw32"
fi

unset CC
unset CXX


# Build libsamplerate
#-----------------------------------------------------------------------------
if [ ! -d libsamplerate ]; then
    git clone https://github.com/studio-link-3rdparty/libsamplerate.git
    pushd libsamplerate
    ./autogen.sh
    ./configure --host=${_arch}
    make
    cp -a ./src/.libs/libsamplerate.a ../my_include/
    cp -a ./src/samplerate.h ../my_include/

    ls -lha ../my_include/
    popd
fi


# Build RtAudio
#-----------------------------------------------------------------------------
if [ ! -d rtaudio-${rtaudio} ]; then
    sl_get_rtaudio
    pushd rtaudio-${rtaudio}
    export CPPFLAGS="-Wno-unused-function -Wno-unused-but-set-variable"
    ./autogen.sh --with-wasapi --host=${_arch}
    make $make_opts
    unset CPPFLAGS
    cp -a .libs/librtaudio.a ../my_include/
    popd
fi

# Download openssl
#-----------------------------------------------------------------------------
if [ ! -d openssl-${openssl} ]; then
    sl_get_openssl
fi

# Build FLAC
#-----------------------------------------------------------------------------
if [ ! -d flac-${flac} ]; then
    sl_get_flac
    mkdir flac/build_win
    pushd flac/build_win
    ${_arch}-configure --disable-ogg --enable-static --disable-cpplibs
    make $make_opts
    popd
    cp -a flac/include/FLAC my_include/
    cp -a flac/include/share my_include/
    cp -a flac/build_win/src/libFLAC/.libs/libFLAC.a my_include/
fi

# Build opus
#-----------------------------------------------------------------------------
if [ ! -d opus-$opus ]; then
    wget -N "https://archive.mozilla.org/pub/opus/opus-${opus}.tar.gz"
    tar -xzf opus-${opus}.tar.gz
    mkdir opus-$opus/build
    pushd opus-$opus/build
    ${_arch}-configure \
        --enable-custom-modes \
        --disable-doc \
        --disable-extra-programs
    make $make_opts
    popd
    mkdir opus; cp opus-$opus/build/.libs/libopus.a opus/
    cp -a opus-$opus/include/*.h opus/
fi


# Build
#-----------------------------------------------------------------------------

cp -a ../dist/windows/Makefile .
make openssl

s3_path="s3_upload/3rdparty/$version_t/"
mkdir -p $s3_path
zip -r $BUILD_OS.zip opus openssl my_include
cp $BUILD_OS.zip $s3_path
