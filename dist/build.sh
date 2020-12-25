#!/bin/bash -ex

source dist/lib/versions.sh
source dist/lib/functions.sh

make_opts="-j4"

# Prepare build
#-----------------------------------------------------------------------------
sl_prepare

if [ "$BUILD_OS" == "macos" ]; then
    export MACOSX_DEPLOYMENT_TARGET=10.9
fi

if [ "$BUILD_TARGET" == "macos_arm64" ]; then
    xcode="/Applications/Xcode_12.2.app/Contents/Developer"
    sysroot="$xcode/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
    sudo xcode-select --switch $xcode
    BUILD_CFLAGS="$CFLAGS -arch arm64 -isysroot $sysroot"
    BUILD_CXXFLAGS="$CXXFLAGS -arch arm64 -isysroot $sysroot"
    export CFLAGS=$BUILD_CFLAGS
    export CXXFLAGS=$BUILD_CXXFLAGS
    _arch="arm64-apple-darwin"
fi

if [ "$BUILD_OS" == "mingw" ]; then
    if [ "$BUILD_TARGET" == "windows32" ]; then
        _arch="i686-w64-mingw32"
    else
        _arch="x86_64-w64-mingw32"
    fi

    unset CC
    unset CXX
fi

# Disabled builds (debugging)
#mkdir libsamplerate openssl-${openssl} soundio flac-${flac} opus-$opus

# Build libsamplerate
#-----------------------------------------------------------------------------
if [ ! -d libsamplerate ]; then
    git clone https://github.com/studio-link-3rdparty/libsamplerate.git
    pushd libsamplerate
    ./autogen.sh
    if [ -n "${_arch}" ]; then
        ./configure --host=${_arch}
    else
        ./configure
    fi
    make

    cp -a ./src/.libs/libsamplerate.a ../3rdparty/lib/
    cp -a ./src/samplerate.h ../3rdparty/include/
    popd
fi

# Build openssl
#-----------------------------------------------------------------------------
if [ ! -d openssl-${openssl} ]; then
    sl_get_openssl
    pushd openssl
    if [ "$BUILD_TARGET" == "macos_arm64" ]; then
        ./Configure no-shared darwin64-arm64-cc
    elif [ "$BUILD_TARGET" == "windows32" ]; then
		CC=${_arch}-gcc RANLIB=${_arch}-ranlib AR=${_arch}-ar \
		./Configure mingw no-shared no-threads
    elif [ "$BUILD_TARGET" == "windows64" ]; then
		CC=${_arch}-gcc RANLIB=${_arch}-ranlib AR=${_arch}-ar \
		./Configure mingw64 no-shared no-threads
    else
        ./config no-shared
    fi
    
    make $make_opts build_libs
    cp -a include/openssl ../3rdparty/include/
    cp -a *.a ../3rdparty/lib/

    popd
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
    if [ "$BUILD_TARGET" == "windows32" ]; then
        export MINGW_ARCH=32; cmake -D CMAKE_TOOLCHAIN_FILE=toolchain.cmake -D BUILD_TESTS=OFF ..
    fi
    if [ "$BUILD_TARGET" == "windows64" ]; then
        export MINGW_ARCH=64; cmake -D CMAKE_TOOLCHAIN_FILE=toolchain.cmake -D BUILD_TESTS=OFF ..
    fi
    make
    popd

    cp -a build/libsoundio.a ../3rdparty/lib/
    popd
fi

# Build FLAC
#-----------------------------------------------------------------------------
if [ ! -d flac-${flac} ]; then
    sl_get_flac

    pushd flac
    if [ "$BUILD_TARGET" == "macos_arm64" ]; then
        ./configure --disable-ogg --enable-static --host arm-apple-darwin
        make $make_opts
    elif [ "$BUILD_OS" == "mingw" ]; then
        mkdir build_win
        pushd build_win
        ${_arch}-configure --disable-ogg --enable-static --disable-cpplibs
        make $make_opts
        popd
    else
        ./configure --disable-ogg --enable-static
        make $make_opts
    fi

    cp -a include/FLAC ../3rdparty/include/

    if [ "$BUILD_OS" == "mingw" ]; then
        cp -a build_win/src/libFLAC/.libs/libFLAC.a ../3rdparty/lib/
    else
        cp -a src/libFLAC/.libs/libFLAC.a ../3rdparty/lib/
    fi

    popd
fi


# Build opus
#-----------------------------------------------------------------------------
if [ ! -d opus-$opus ]; then
    wget "https://archive.mozilla.org/pub/opus/opus-${opus}.tar.gz"
    tar -xzf opus-${opus}.tar.gz
    pushd opus-$opus
    if [ "$BUILD_TARGET" == "macos_arm64" ]; then
        ./configure --with-pic --host arm-apple-darwin
        make
    elif [ "$BUILD_OS" == "mingw" ]; then
        mkdir build_win
        pushd build_win
        ${_arch}-configure \
            --enable-custom-modes \
            --disable-doc \
            --disable-extra-programs
        make $make_opts
        popd
    else
        ./configure --with-pic
        make
    fi
    popd

    if [ "$BUILD_OS" == "mingw" ]; then
        cp opus-$opus/build_win/.libs/libopus.a 3rdparty/lib/
    else
        cp opus-$opus/.libs/libopus.a 3rdparty/lib/
    fi

    mkdir -p 3rdparty/include/opus
    cp opus-$opus/include/*.h 3rdparty/include/opus/

fi

# Prepare release upload
#-----------------------------------------------------------------------------
zip -r $BUILD_TARGET.zip 3rdparty
