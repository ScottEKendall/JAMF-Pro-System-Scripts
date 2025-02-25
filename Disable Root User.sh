#!/bin/bash

# Source: https://community.jamf.com/t5/jamf-pro/how-to-disable-root-for-users-that-have-enabled-root-on-their/m-p/242644

# remove the AuthenticationAuthority from the user's account
dscl . delete /Users/root AuthenticationAuthority

# Put a single asterisk in the password entry, thus locking the account.
dscl . -create /Users/root Password '*'

# Disable root login by setting root's shell to /usr/bin/false
## Note: This will prevent use of 'su root' or 'su -' to elevate to root.
##       Comment out, remove, or use 'sudo' with another admin account if needed.
dscl . -create /Users/root UserShell /usr/bin/false

exit 0
