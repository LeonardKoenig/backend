#!/bin/bash -ex

version_t="v16.04.1-beta"
version_n="16.04.1"

#-----------------------------------------------------------------------------
rem="0.4.7"
re="0.4.15"
opus="1.1.2"
openssl="1.0.2h"
baresip="master"
juce="4.1.0"
github_org="https://github.com/Studio-Link-v2"
patch_url="$github_org/baresip/compare/Studio-Link-v2:master"

# Start build
#-----------------------------------------------------------------------------
echo "start build on $TRAVIS_OS_NAME"

mkdir -p src; cd src
mkdir -p my_include

if [ "$TRAVIS_OS_NAME" == "linux" ]; then

    sl_extra_lflags="-L../openssl"
    sl_extra_modules="alsa jack"

else
    #universal="-arch i386 -arch x86_64"
    sl_openssl_osx="/usr/local/opt/openssl/lib/libcrypto.a "
    sl_openssl_osx+="/usr/local/opt/openssl/lib/libssl.a"
    
    sl_extra_lflags="-framework SystemConfiguration "
    sl_extra_lflags+="-framework CoreFoundation $sl_openssl_osx"
    sl_extra_modules="audiounit"

    #opus_flags="CXXFLAGS='$universal' "
    #opus_flags+="CFLAGS='$universal' "
    #opus_flags+="LDFLAGS='$universal'"
    #./configure CC="$CC -m32"
fi


# Build openssl (linux only)
#-----------------------------------------------------------------------------
if [ "$TRAVIS_OS_NAME" == "linux" ]; then
    if [ ! -d openssl-${openssl} ]; then
        wget https://www.openssl.org/source/openssl-${openssl}.tar.gz
        tar -xzf openssl-${openssl}.tar.gz
        ln -s openssl-${openssl} openssl
        cd openssl
        ./config -fPIC shared
        make
        rm -f libcrypto.so
        rm -f libssl.so
        cp -a include/openssl ../my_include/
        cd ..
    fi
fi


# Build libre
#-----------------------------------------------------------------------------
if [ ! -d re-$re ]; then
    wget -N "http://www.creytiv.com/pub/re-${re}.tar.gz"
    tar -xzf re-${re}.tar.gz
    ln -s re-$re re
    cd re
    patch --ignore-whitespace -p1 < ../../build/bluetooth_conflict.patch
    patch --ignore-whitespace -p1 < ../../build/re_ice_bug.patch

    if [ "$TRAVIS_OS_NAME" == "linux" ]; then
        make USE_OPENSSL=1 EXTRA_CFLAGS="-I ../my_include/" libre.a
    else
        make USE_OPENSSL=1 \
            EXTRA_CFLAGS="-I /usr/local/opt/openssl/include" libre.a
    fi

    cd ..
    mkdir -p my_include/re
    cp -a re/include/* my_include/re/
fi


# Build librem
#-----------------------------------------------------------------------------
if [ ! -d rem-$rem ]; then
    wget -N "http://www.creytiv.com/pub/rem-${rem}.tar.gz"
    tar -xzf rem-${rem}.tar.gz
    ln -s rem-$rem rem
    cd rem
    make librem.a 
    cd ..
fi


# Build opus
#-----------------------------------------------------------------------------
if [ ! -d opus-$opus ]; then
    wget -N "http://downloads.xiph.org/releases/opus/opus-${opus}.tar.gz"
    tar -xzf opus-${opus}.tar.gz
    cd opus-$opus; ./configure --with-pic; make; cd ..
    mkdir opus; cp opus-$opus/.libs/libopus.a opus/
    mkdir -p my_include/opus
    cp opus-$opus/include/*.h my_include/opus/ 
fi


# Build baresip with studio link addons
#-----------------------------------------------------------------------------
if [ ! -d baresip-$baresip ]; then
    git clone $github_org/baresip.git baresip-$baresip
    ln -s baresip-$baresip baresip
    cp -a baresip-$baresip/include/baresip.h my_include/
    cd baresip-$baresip;

    ## Add patches
    curl ${patch_url}...studio-link-config.patch | patch -p1
    patch -p1 < ../../build/max_calls.patch
    patch -p1 < ../../build/osx_sample_rate.patch
    patch -p1 < ../../build/0001-fix-incomplete-type-error.patch

    ## Link backend modules
    cp -a ../../webapp modules/webapp
    cp -a ../../effect modules/effect

    # Standalone
    make LIBRE_SO=../re LIBREM_PATH=../rem STATIC=1 \
        MODULES="opus stdio ice g711 turn stun uuid auloop webapp $sl_extra_modules" \
        EXTRA_CFLAGS="-I ../my_include" \
        EXTRA_LFLAGS="$sl_extra_lflags -L ../opus"

    cp -a baresip ../studio-link-standalone

    # libbaresip.a without effect plugin
    make LIBRE_SO=../re LIBREM_PATH=../rem STATIC=1 \
        MODULES="opus stdio ice g711 turn stun uuid auloop webapp $sl_extra_modules" \
        EXTRA_CFLAGS="-I ../my_include" \
        EXTRA_LFLAGS="$sl_extra_lflags -L ../opus" libbaresip.a
    cp -a libbaresip.a ../my_include/libbaresip_standalone.a

    # Effect Plugin
    make clean
    make LIBRE_SO=../re LIBREM_PATH=../rem STATIC=1 \
        MODULES="opus stdio ice g711 turn stun uuid auloop webapp effect" \
        EXTRA_CFLAGS="-I ../my_include -DSLPLUGIN" \
        EXTRA_LFLAGS="$sl_extra_lflags -L ../opus" libbaresip.a
    cd ..
fi


# Build overlay-lv2 plugin (linux only)
#-----------------------------------------------------------------------------
if [ "$TRAVIS_OS_NAME" == "linux" ]; then
    if [ ! -d overlay-lv2 ]; then
        git clone $github_org/overlay-lv2.git overlay-lv2
        cd overlay-lv2
	patch --ignore-whitespace -p1 < ../../build/0001-fix-path.patch
	git clone http://lv2plug.in/git/cgit.cgi/lv2.git

	./build.sh; cd ..
    fi
fi


# Build overlay-audio-unit plugin (osx only)
#-----------------------------------------------------------------------------
if [ "$TRAVIS_OS_NAME" == "osx" ]; then
    if [ ! -d overlay-audio-unit ]; then
        git clone \
            $github_org/overlay-audio-unit.git overlay-audio-unit
        cd overlay-audio-unit
        sed -i '' s/SLVERSION_N/$version_n/ StudioLink/StudioLink.jucer
        wget https://github.com/julianstorer/JUCE/archive/$juce.tar.gz
        tar -xzf $juce.tar.gz
        rm -Rf JUCE
        mv JUCE-$juce JUCE
        ./build.sh
        cd ..
    fi
fi


# Build standalone app bundle (osx only)
#-----------------------------------------------------------------------------
if [ "$TRAVIS_OS_NAME" == "osx" ]; then
    if [ ! -d overlay-standalone-osx ]; then
        git clone \
            $github_org/overlay-standalone-osx.git overlay-standalone-osx
        cp -a my_include/re overlay-standalone-osx/StudioLinkStandalone/
        cp -a my_include/baresip.h \
            overlay-standalone-osx/StudioLinkStandalone/
        cd overlay-standalone-osx
        sed -i '' s/SLVERSION_N/$version_n/ StudioLinkStandalone/Info.plist
        ./build.sh
        cd ..
    fi
fi


# Testing and prepare release upload
#-----------------------------------------------------------------------------

./studio-link-standalone -t

if [ "$TRAVIS_OS_NAME" == "linux" ]; then
    ldd studio-link-standalone
    mkdir -p lv2-plugin
    cp -a overlay-lv2/studio-link.so lv2-plugin/
    cp -a overlay-lv2/*.ttl lv2-plugin/
    cp -a overlay-lv2/README.md lv2-plugin/
    zip -r studio-link-plugin-linux lv2-plugin
    zip -r studio-link-standalone-linux studio-link-standalone
else
    otool -L studio-link-standalone
    cp -a ~/Library/Audio/Plug-Ins/Components/StudioLink.component StudioLink.component
    mv overlay-standalone-osx/build/Release/StudioLinkStandalone.app StudioLinkStandalone.app
    codesign -f -s "Developer ID Application: Sebastian Reimers (CX34XZ2JTT)" --keychain ~/Library/Keychains/sl-build.keychain StudioLinkStandalone.app
    zip -r studio-link-plugin-osx StudioLink.component
    zip -r studio-link-standalone-osx StudioLinkStandalone.app
    security delete-keychain ~/Library/Keychains/sl-build.keychain
fi
