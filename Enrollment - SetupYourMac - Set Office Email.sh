#!/bin/zdsh

LOGGED_IN_USER=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }')
PLIST="/Users/$LOGGED_IN_USER/Library/Preferences/com.microsoft.office.plist"

echo "Logged in user: $LOGGED_IN_USER"

USER_EMAIL=$(/usr/libexec/PlistBuddy -c "Print :DisplayName" "/Users/$LOGGED_IN_USER/Library/Preferences/com.jamf.connect.state.plist")

echo "Detected email address: $USER_EMAIL"
echo "Configuring Microsoft Office preferences..."

# Configure Office preferences
defaults write "$PLIST" OfficeActivationEmailAddress -string "$USER_EMAIL"
echo "OfficeActivationEmailAddress configured"

defaults write "$PLIST" OfficeAutoSignIn -bool true
echo "OfficeAutoSignIn enabled"

# Fix file ownership
chown "$LOGGED_IN_USER" "$PLIST"
echo "File ownership updated"

echo "Microsoft Office configuration completed successfully"

exit 0