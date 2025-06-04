#!/bin/bash
# 
# Delete User Accounts

# Written: Nov 21, 2024
# Last updated: Nov 30, 2024

# Discover the logged in user, so we dont accidentally delete them
loggedInUser=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ && ! /loginwindow/ { print $3 }' )
if [[ -z "$loggedInUser" ]]; then
	echo "Cannot find logged in user!"
	exit 1
fi
echo "$loggedInUser is currently logged in"

#Find Users, excluding selected Admin user, and System and Service Accounts
users=$( dscl . ls /Users | grep -v '_' | grep -v 'root' | grep -v 'daemon'| grep -v 'nobody'| grep -v $loggedInUser )
userstodelete=("jamfenroll" "shortcircuit" "elder.oblex" "macadmin" "enrollment" "admin" "mdmenroll" "jamfadmin" "LAPSAccount" "LOCALadmin" "helpdesk")

###########
# Functions 
###########


function contains ()
{
    local list=$1[@]
    local elem=$2
    for i in "${!list}"
    do
        [[ "$i" == "${elem}" ]] && return 0
    done
    return 1
}

###############
# Main Program
###############
for a in $users; do
    if contains userstodelete "$a"; then
        #delete user from admin & staff groups
        dseditgroup -o edit -d "$a" -t user admin
        echo "$a removed from admin group"
        dseditgroup -o edit -d "$a" -t user staff
        echo "$a removed from staff group"
        #delete user
		/usr/bin/dscl . delete /Users/$a > /dev/null 2>&1
	    echo "$a's user account has been removed"
        #Delete User Home Folder
	    /bin/rm -rf /Users/"$a"
	    echo "$a's user home folder has been removed"
    fi
    continue
done

echo "User accounts Removed Sucessfully"
exit 0
