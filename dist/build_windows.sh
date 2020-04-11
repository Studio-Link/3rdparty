#!/bin/bash -ex

#sudo cp -a /build /build2
sudo ls -lha
export PATH="$PATH:/usr/bin/core_perl"

source dist/lib/versions.sh
source dist/lib/functions.sh

sl_prepare

make_opts="-j4"

mkdir -p mingw
pushd mingw
mingwurl="https://github.com/Studio-Link/mingw/releases/download/v20.03.0"
wget -N $mingwurl/mingw-w64-binutils-2.34-1-x86_64.pkg.tar.xz
wget -N $mingwurl/mingw-w64-configure-0.1.1-9-any.pkg.tar.xz
wget -N $mingwurl/mingw-w64-crt-7.0.0-1-any.pkg.tar.xz
wget -N $mingwurl/mingw-w64-environment-1-2-any.pkg.tar.xz
wget -N $mingwurl/mingw-w64-gcc-9.3.0-1-x86_64.pkg.tar.xz
wget -N $mingwurl/mingw-w64-headers-7.0.0-1-any.pkg.tar.xz
wget -N $mingwurl/mingw-w64-pkg-config-2-4-any.pkg.tar.xz
wget -N $mingwurl/mingw-w64-winpthreads-7.0.0-1-any.pkg.tar.xz
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
    popd
fi

# Build soundio
#-----------------------------------------------------------------------------
if [ ! -d soundio ]; then
    sl_get_soundio
    pushd soundio
    mkdir build
    pushd build
    if [ "$BUILD_OS" == "windows32" ]; then
        export MINGW_ARCH=32; cmake -D CMAKE_TOOLCHAIN_FILE=toolchain.cmake -D BUILD_TESTS=OFF ..
    fi
    if [ "$BUILD_OS" == "windows64" ]; then
        export MINGW_ARCH=64; cmake -D CMAKE_TOOLCHAIN_FILE=toolchain.cmake -D BUILD_TESTS=OFF ..
    fi
    make
    popd

    cp -a build/libsoundio.a ../my_include/
    popd
fi

# Build RtAudio
#-----------------------------------------------------------------------------
if [ ! -d rtaudio-${rtaudio} ]; then
    sl_get_rtaudio
    pushd rtaudio-${rtaudio}
    export CPPFLAGS="-Wno-unused-function -Wno-unused-but-set-variable"
    ./autogen.sh --with-wasapi --with-asio --with-dsound --host=${_arch}
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

# Package
#-----------------------------------------------------------------------------
zip -r $BUILD_OS.zip my_include openssl opus
