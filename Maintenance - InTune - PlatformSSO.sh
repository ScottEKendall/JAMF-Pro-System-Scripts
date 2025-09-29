#!/bin/zsh
#
# pSSO_Text
#
# by: Scott Kendall
#
# Written: 10/23/2025
#
# Script Purpose: Make sure platform SSO is running properly on machine, force prompt if not.
#
# 1.0 - Initial

######################################################################################################
#
# Gobal "Common" variables (do not change these!)
#
######################################################################################################
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
LOGGED_IN_USER=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' )
USER_DIR=$( dscl . -read /Users/${LOGGED_IN_USER} NFSHomeDirectory | awk '{ print $2 }' )

# Swift Dialog version requirements

SW_DIALOG="/usr/local/bin/dialog"
MIN_SD_REQUIRED_VERSION="2.5.0"
[[ -e "${SW_DIALOG}" ]] && SD_VERSION=$( ${SW_DIALOG} --version) || SD_VERSION="0.0.0"

DIALOG_COMMAND_FILE=$(mktemp /var/tmp/pSSORegister.XXXXX)
/bin/chmod 666 $DIALOG_COMMAND_FILE
SD_DIALOG_GREETING=$((){print Good ${argv[2+($1>11)+($1>18)]}} ${(%):-%D{%H}} morning afternoon evening)

###################################################
#
# App Specfic variables (Feel free to change these)
#
###################################################

# Support / Log files location

SUPPORT_DIR="/Library/Application Support/GiantEagle"
LOG_FILE="${SUPPORT_DIR}/logs/AppDelete.log"

# Display items (banner / icon)

BANNER_TEXT_PADDING="      " #5 spaces to accomodate for icon offset
SD_WINDOW_TITLE="${BANNER_TEXT_PADDING}Platform SSO Registration"
SD_BANNER_IMAGE="${SUPPORT_DIR}/SupportFiles/GE_SD_BannerImage.png"
SD_ICON_FILE="${SUPPORT_DIR}/SupportFiles/sso.png"

# Trigger installs for Images & icons

PSSO_INSTALL_POLICY="install_pSSO_Additional_Files"
SUPPORT_FILE_INSTALL_POLICY="install_SymFiles"
DIALOG_INSTALL_POLICY="install_SwiftDialog"

##################################################
#
# Passed in variables
# 
#################################################

JAMF_LOGGED_IN_USER=${3:-"$LOGGED_IN_USER"}    # Passed in by JAMF automatically
SD_FIRST_NAME="${(C)JAMF_LOGGED_IN_USER%%.*}"   

####################################################################################################
#
# Functions
#
####################################################################################################

function create_log_directory ()
{
    # Ensure that the log directory and the log files exist. If they
    # do not then create them and set the permissions.
    #
    # RETURN: None

	# If the log directory doesnt exist - create it and set the permissions (using zsh paramter expansion to get directory)
	LOG_DIR=${LOG_FILE%/*}
	[[ ! -d "${LOG_DIR}" ]] && /bin/mkdir -p "${LOG_DIR}"
	/bin/chmod 755 "${LOG_DIR}"

	# If the log file does not exist - create it and set the permissions
	[[ ! -f "${LOG_FILE}" ]] && /usr/bin/touch "${LOG_FILE}"
	/bin/chmod 644 "${LOG_FILE}"
}

function logMe () 
{
    # Basic two pronged logging function that will log like this:
    #
    # 20231204 12:00:00: Some message here
    #
    # This function logs both to STDOUT/STDERR and a file
    # The log file is set by the $LOG_FILE variable.
    #
    # RETURN: None
    echo "$(/bin/date '+%Y-%m-%d %H:%M:%S'): ${1}" | tee -a "${LOG_FILE}"
}

function check_swift_dialog_install ()
{
    # Check to make sure that Swift Dialog is installed and functioning correctly
    # Will install process if missing or corrupted
    #
    # RETURN: None

    logMe "Ensuring that swiftDialog version is installed..."
    if [[ ! -x "${SW_DIALOG}" ]]; then
        logMe "Swift Dialog is missing or corrupted - Installing from JAMF"
        install_swift_dialog
        SD_VERSION=$( ${SW_DIALOG} --version)        
    fi

    if ! is-at-least "${MIN_SD_REQUIRED_VERSION}" "${SD_VERSION}"; then
        logMe "Swift Dialog is outdated - Installing version '${MIN_SD_REQUIRED_VERSION}' from JAMF..."
        install_swift_dialog
    else    
        logMe "Swift Dialog is currently running: ${SD_VERSION}"
    fi
}

function install_swift_dialog ()
{
    # Install Swift dialog From JAMF
    # PARMS Expected: DIALOG_INSTALL_POLICY - policy trigger from JAMF
    #
    # RETURN: None

	/usr/local/bin/jamf policy -trigger ${DIALOG_INSTALL_POLICY}
}

function check_support_files ()
{
    [[ ! -e "${SD_BANNER_IMAGE}" ]] && /usr/local/bin/jamf policy -trigger ${SUPPORT_FILE_INSTALL_POLICY}
    [[ ! -e "${SD_ICON_FILE}" ]] && /usr/local/bin/jamf policy -trigger ${PSSO_INSTALL_POLICY}
}

function cleanup_and_exit ()
{
	[[ -f ${JSON_OPTIONS} ]] && /bin/rm -rf ${JSON_OPTIONS}
	[[ -f ${TMP_FILE_STORAGE} ]] && /bin/rm -rf ${TMP_FILE_STORAGE}
    [[ -f ${DIALOG_COMMAND_FILE} ]] && /bin/rm -rf ${DIALOG_COMMAND_FILE}
	exit $1
}

function getValueOf ()
{
	echo $2 | grep "$1" | awk -F ":" '{print $2}' | tr -d "," | xargs
}

function get_sso_status ()
{
	ssoStatus=$(app-sso platform -s)
}

function kill_sso_agent()
{
	pkill AppSSOAgent
	sleep 1
	app-sso -l > /dev/null 2>&1
}

function check_logged_in_user ()
{
	# Exit if there's no user
	if [[ -z $LOGGED_IN_USER ]]; then
		echo "No user signed in, exiting"
		exit 1
	fi
}

function check_for_sudo_access () 
{
  # Check if the effective user ID is 0.
  if [[ $EUID -ne 0 ]]; then
    # Print an error message to standard error.
    echo "This script must be run with root privileges. Please use sudo." >&2
    # Exit the script with a non-zero status code.
    cleanup_and_exit 1
  fi
}

function displaymsg ()
{
	message="When you see this macOS notification, please click on it and go through the registration process."
	MainDialogBody=(
        --message "<br>$SD_DIALOG_GREETING $SD_FIRST_NAME. $message"
		--messagealignment "center"
        --titlefont shadow=1
        --ontop
        --icon "${SD_ICON_FILE}"
        --bannerimage "${SD_BANNER_IMAGE}"
        --bannertitle "${SD_WINDOW_TITLE}"
		--commandfile "${DIALOG_COMMAND_FILE}"
		--image "${SUPPORT_DIR}/SupportFiles/pSSO_Notification.png"
		--buttonstyle center
        --helpmessage ""
		--position "topleft"
        --width 700
        --ignorednd
        --quitkey 0
        --button1text none
    )

	"${SW_DIALOG}" "${MainDialogBody[@]}" 2>/dev/null &
}

####################################################################################################
#
# Main Script
#
####################################################################################################

autoload 'is-at-least'

declare ssoStatus

check_logged_in_user
check_for_sudo_access
create_log_directory
check_swift_dialog_install
check_support_files

# Prompt the user to register if needed
get_sso_status
if [[ $(getValueOf registrationCompleted "$ssoStatus") == true ]]; then
    logMe "User already registered"
    exit 0
fi

logMe "Prompting user to register device"
displaymsg
echo "activate:" > ${DIALOG_COMMAND_FILE}
# Force the registration dialog to appear
logMe "Stopping pSSO agent"
kill_sso_agent
# Wait until registation is complete
until [[ $(getValueOf registrationCompleted "$ssoStatus") == true ]]; do
    sleep 10
    get_sso_status
done
logMe "Registration Finished"
echo "quit:" > ${DIALOG_COMMAND_FILE}
cleanup_and_exit
