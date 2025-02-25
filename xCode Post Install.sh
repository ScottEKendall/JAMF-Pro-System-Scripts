#!/bin/sh

export PATH=/usr/bin:/bin:/usr/sbin:/sbin

xcodePath="/Applications/Xcode.app"

if [[ ! -e "$xcodePath" ]]; then
    echo "no app at $xcodePath, exiting..."
    exit 1
fi

# select Xcode
xcode-select -s "$xcodePath"

# accept license
xcodebuild -license accept

# install additional components
xcodebuild -runFirstLaunch

# add everyone (every local account) to developer group
dseditgroup -o edit -a everyone -t group _developer

# enable dev tools security
DevToolsSecurity -enable

# download platform SDK

# all available platforms
# xcodebuild -downloadAllPlatforms

# update previously downloaded platforms
# xcodebuild -downloadAllPreviouslySelectedPlatforms

# download individual platforms (repeat for each)
# options are: watchOS, tvOS, and (Xcode 15+) iOS, and xrOS
xcodebuild -downloadPlatform iOS