ARMSX3
======

<img width="2778" height="1284" alt="ARMSX3_Screenshot2" src="https://github.com/user-attachments/assets/4cba4930-c363-4c35-90a9-8e9c641e75cf" />


<img width="1284" height="2778" alt="ARMSX3_Screenshot" src="https://github.com/user-attachments/assets/de857097-3456-4644-afc6-8b62b14bb17c" />



An iOS port (made with AI) that works on iOS 15+. Requires JIT and currently limited to devices supporting TrollStore. 
This is due to limitations with free dev accounts when sideloading newer devices for the time being.

Uses the latest RPCS3 upstream code (the recent ARM64 improvements included). 

STATUS
--------
* 2D Games working at full speed - i.e. Bejeweled 3, and Duck Tales Remastered
* 3D Games vary - Ratatouille, Bound by Flame, The Walking Dead and some other games work full speed
* Games NOT working Full Speed Uncharted,1,2,3, Red Dead Redemption...GTA5 works in the 20's currently

I am working on porting MoltenVK to Metal so we can get better performance on major 3D games.

Support for PS3NETServ. Point to your extracted or ISO games and connect. No need to install the ISO locally. Some games will create install files, but much more efficient over network. You can import ISO games locally but limited virtual HD space at this time.

Very much a Pre-Beta right now...but hopefully you can enjoy it. Tested on iPhone 13 Pro Max - iOS 15.3 - installed via TrollStore.


Building
--------

 arm64-v8a and armv8.2 is supported. You need the Android SDK with NDK r27 or newer,
CMake 3.30 or newer, and a JDK 17. Android Studio ships all of these.

Clone with submodules, then fetch the two third party checkouts that are not
submodules:

    git clone --recursive https://github.com/ARMSX2/ARMSX3.git
    cd ARMSX3
    git clone https://github.com/SnowflakePowered/librashader 3rdparty/librashader
    git clone https://github.com/bylaws/libadrenotools android/armsx3-ui/app/src/main/cpp/libadrenotools

Build the core. This is the long part and produces an unstripped library of
around 1.3 GB:

    export ANDROID_HOME=$HOME/Library/Android/sdk
    cmake -B build-android -G Ninja \
      -DCMAKE_TOOLCHAIN_FILE=$ANDROID_HOME/ndk/<version>/build/cmake/android.toolchain.cmake \
      -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-31 \
      -DCMAKE_BUILD_TYPE=RelWithDebInfo
    cmake --build build-android --target rpcsx-android -j8

Strip it and put it where the app expects it:

    llvm-strip --strip-unneeded build-android/android/libarmsx3-core.so
    cp build-android/android/libarmsx3-core.so \
       android/armsx3-ui/app/src/main/jniLibs/arm64-v8a/

Then build the app:

    cd android/armsx3-ui
    export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
    ./gradlew :app:assembleRelease

The apk lands in app/build/outputs/apk/release/.

Note that the core library has to be rebuilt and copied again whenever anything
under rpcs3/ or android/src/ changes. Gradle does not build it for you.

The Discord Social SDK is proprietary and is not redistributed here. Get it from
Discord's developer portal and drop it in app/libs/ and
app/src/main/cpp/discord_sdk/ if you want that feature. The build skips it
otherwise.

Running it needs PS3 firmware, which is not included. 
License
-------

GPL-2.0-only, the same as RPCS3. See LICENSE. Some files may be licensed
differently, check the file headers.

Based on RPCS3, https://github.com/RPCS3/rpcs3
