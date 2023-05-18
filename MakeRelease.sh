#!/bin/bash

mkdir -p ./Mach4Hobby
cp -r ./Modules/ ./Mach4Hobby/Modules/
mkdir -p ./Mach4Hobby/Profiles/AvidCNC/Macros
mkdir -p ./Mach4Hobby/Screens
rm ./Mach4Hobby/Modules/CorbinsWorkshop/.DS_Store
rm ./Mach4Hobby/Modules/CorbinsWorkshop/.vscode/settings.json 
rmdir ./Mach4Hobby/Modules/CorbinsWorkshop/.vscode/
rmdir ./Mach4Hobby/Modules/.vscode/
rm ./Mach4Hobby/Modules/.DS_Store
cp ./Profiles/AvidCNC/Macros/m5.mcs ./Mach4Hobby/Profiles/AvidCNC/Macros/m5.mcs
cp ./Profiles/AvidCNC/Macros/m3.mcs ./Mach4Hobby/Profiles/AvidCNC/Macros/m3.mcs
cp ./Profiles/AvidCNC/Macros/m6.mcs ./Mach4Hobby/Profiles/AvidCNC/Macros/m6.mcs
cp ./Profiles/AvidCNC/Macros/m30.mcs ./Mach4Hobby/Profiles/AvidCNC/Macros/m30.mcs
cp ./Profiles/AvidCNC/Macros/load_modules.mcs ./Mach4Hobby/Profiles/AvidCNC/Macros/load_modules.mcs
cp ./Screens/AvidCNC_ATC_corbin.set ./Mach4Hobby/Screens/AvidCNC_ATC_corbin.set
zip -r -X Mach4Hobby.zip ./Mach4Hobby 
