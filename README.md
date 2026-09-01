ARMSX3 for iOS 
======

<img width="2778" height="1284" alt="ARMSX3_Screenshot2" src="https://github.com/user-attachments/assets/4cba4930-c363-4c35-90a9-8e9c641e75cf" />


<img width="1284" height="2778" alt="ARMSX3_Screenshot" src="https://github.com/user-attachments/assets/de857097-3456-4644-afc6-8b62b14bb17c" />

(Vertical View is temporary)
--------
An iOS port (made with AI) that works on iOS 15+. Requires JIT and currently limited to devices supporting TrollStore. 
This is due to limitations with free dev accounts when sideloading newer devices for the time being.

Built with the intention of being part of EmuHub, but planning on retaining a stand-alone IPA.

Uses the latest RPCS3 upstream code (the recent ARM64 improvements included). 

STATUS
--------
* 2D Games working at full speed - i.e. Bejeweled 3, and Duck Tales Remastered
* 3D Games vary - Ratatouille, Bound by Flame, The Walking Dead and some other games work full speed
* Games NOT working Full Speed Uncharted,1,2,3, Red Dead Redemption...GTA5 works in the 20's currently

I am working on porting MoltenVK to Metal so we can get better performance on major 3D games.

Support for PS3NETServ. Point to your extracted or ISO games and connect. No need to install the ISO locally. Some games will create install files, but much more efficient over network. You can import ISO games locally but limited virtual HD space at this time.

Very much a Pre-Beta right now...but hopefully you can enjoy it. Tested on iPhone 13 Pro Max - iOS 15.3 - installed via TrollStore.

**Running it needs PS3 firmware, which is not included. **

License
-------

GPL-2.0-only, the same as RPCS3. See LICENSE. Some files may be licensed
differently, check the file headers.

Based on RPCS3, https://github.com/RPCS3/rpcs3
