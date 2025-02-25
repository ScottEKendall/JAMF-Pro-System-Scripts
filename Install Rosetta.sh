#!/bin/bash

if [[ "$(/usr/bin/uname -p)" == 'i386' ]]; then
    echo "Intel processor installed. No need to install Rosetta."
    exit 0
fi

if [[ -f "/Library/Apple/System/Library/LaunchDaemons/com.apple.oahd.plist" ]]; then
    echo "Rosetta is already installed. Nothing to do."
    exit 0
fi

/usr/sbin/softwareupdate --install-rosetta --agree-to-license

if [[ $? -eq 0 ]]; then
    echo "Rosetta has been successfully installed."
else
    echo "Rosetta installation failed!"
    exit 1
fi
