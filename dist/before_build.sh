#!/bin/bash -e

if [ "$BUILD_OS" == "linux" ] || [ "$BUILD_OS" == "linuxjack" ]; then
    if [ "$(id -u)" == "0" ]; then
        apt-get update -qq
        apt-get install -y libasound2-dev libjack-jackd2-dev libpulse-dev libpulse0 vim-common
    fi
fi
