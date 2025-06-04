#!/bin/zsh
#
# promote or remove admin rights
#
# Parm #4 promote or revoke admin rights
#
rights="${4:-"promote"}"

LOGGED_IN_USER=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' )

if [[ "${rights}" == "promote" ]]; then
	dseditgroup -o edit -a "${LOGGED_IN_USER}" -t user admin
	echo "User ${LOGGED_IN_USER} promoted to admin"
else
	dseditgroup -o edit -d "${LOGGED_IN_USER}" -t user admin
    echo "Removing admins rights for user ${LOGGED_IN_USER}"
fi
exit 0
