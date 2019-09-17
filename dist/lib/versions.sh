vmajor=19; vminor=9; vpatch=0
opus="1.3.1"
openssl="1.1.1d"
openssl_sha256="1e3a91bc1f9dfce01af26026f856e064eab4c8ee0a8f457b5ae30b40b8b711f2"
rtaudio="master"
flac="1.3.3"
github_org="https://github.com/Studio-Link"
vstsdk="vstsdk367_03_03_2017_build_352"
debug="RELEASE=1"
if [ -z "${TRAVIS_BRANCH+x}" ]; then
TRAVIS_BRANCH=$(git rev-parse --abbrev-ref HEAD)
fi
