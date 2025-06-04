#!/bin/bash

# Reset InTune/Jamf integration. Removes all files and keychain items.
# Updated by Patrick Gallagher
# Last update 03/19/2020

jamfTrigger="companyportal"
loggedInUser=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' )

if [[ $(pgrep "Company Portal") != "" ]]; then
  echo "Quitting Company Portal"
  killall "Company Portal"
fi


file_Array=(
  "/Applications/Company Portal.app/"
  "/Users/${loggedInUser}/Library/Application Support/com.microsoft.CompanyPortal.usercontext.info"
  "/Users/${loggedInUser}/Library/Application Support/com.jamfsoftware.selfservice.mac"
  "/Users/${loggedInUser}/Library/Saved Application State/com.jamfsoftware.selfservice.mac.savedState"
  "/Users/${loggedInUser}/Library/Saved Application State/com.jamf.management.jamfAAD.savedState/"
  "/Users/${loggedInUser}/Library/Saved Application State/com.microsoft.CompanyPortal.savedState"
  "/Users/${loggedInUser}/Library/Preferences/com.microsoft.CompanyPortal.plist"
  "/Users/${loggedInUser}/Library/Preferences/com.jamfsoftware.management.jamfAAD.plist"
  "/Users/${loggedInUser}/Library/Cookies/com.microsoft.CompanyPortal.binarycookies"
  "/Users/${loggedInUser}/Library/Cookies/com.jamf.management.jamfAAD.binarycookies"
)


for i in "${file_Array[@]}"; do
  if [[ -e $i ]]; then
    echo "Deleting file $i"
    rm -rf "$i"
  fi
done

/usr/sbin/pkgutil --forget com.microsoft.CompanyPortalMac

passwordItemAccounts_Array=(
  'com.microsoft.workplacejoin.thumbprint'
  'com.microsoft.workplacejoin.registeredUserPrincipalName'
  'com.microsoft.workplacejoin.deviceName'
  'com.microsoft.workplacejoin.thumbprint'
  'com.microsoft.workplacejoin.deviceOSVersion'
  'com.microsoft.workplacejoin.discoveryHint'
)

for i in "${passwordItemAccounts_Array[@]}"; do
  itemCheck=$(/usr/bin/security find-generic-password -a $i | grep svce) #> /dev/null 2>&1)
  if [[ "$itemCheck" != "" ]]; then
    echo "Deleting Password Item $i"
    /usr/bin/security delete-generic-password -a $i /Users/${loggedInUser}/Library/Keychains/login.keychain-db > /dev/null 2>&1
  fi
done

# There may be more than one of 'com.microsoft.workplacejoin.devicePatchAttemptTimestamp' so using a while loop to get them all
devicePatchAttemptTimestamp=$(/usr/bin/security find-generic-password -a 'com.microsoft.workplacejoin.devicePatchAttemptTimestamp' | grep svce)
while [[ $devicePatchAttemptTimestamp != "" ]]; do
  /usr/bin/security delete-generic-password -a 'com.microsoft.workplacejoin.devicePatchAttemptTimestamp' /Users/${loggedInUser}/Library/Keychains/login.keychain-db > /dev/null 2>&1
  devicePatchAttemptTimestamp=$(/usr/bin/security find-generic-password -a 'com.microsoft.workplacejoin.devicePatchAttemptTimestamp' | grep svce)
done

identityPref_Array=(
  'com.jamf.management.jamfAAD'
  'com.microsoft.CompanyPortal'
  'com.microsoft.CompanyPortal.HockeySDK'
  'enterpriseregistration.windows.net'
  'https://device.login.microsoftonline.com'
  'https://device.login.microsoftonline.com/'
  'https://enterpriseregistration.windows.net'
  'https://enterpriseregistration.windows.net/'
)

for i in "${identityPref_Array[@]}"; do
  itemCheck=$(/usr/bin/security find-generic-password -l $i | grep svce)
  if [[ $itemCheck != "" ]]; then
    echo "Deleting Identity Preference $i"
    /usr/bin/security delete-generic-password -l $i /Users/${loggedInUser}/Library/Keychains/login.keychain-db > /dev/null 2>&1
  fi
done

certCheck=$(/usr/bin/security find-certificate -a -Z | grep -B 9 "MS-ORGANIZATION-ACCESS" | grep "SHA-1" | awk '{print $3}')
if [[ $certCheck != "" ]]; then
    echo "Deleting $certCheck"
    /usr/bin/security delete-identity -Z "$certCheck" -t /Users/${loggedInUser}/Library/Keychains/login.keychain-db > /dev/null 2>&1
fi


/usr/local/bin/jamf policy -event $jamfTrigger
