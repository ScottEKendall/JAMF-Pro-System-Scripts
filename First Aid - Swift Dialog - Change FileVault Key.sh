#!/bin/zsh
#
# ChangeFVKey
#
# by: Scott Kendall
#
# Written: 09/03/2025
# Last updated: 09/03/2025
#
# Script Purpose: Change users personal recovery key and escrow to server
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

[[ "$(/usr/bin/uname -p)" == 'i386' ]] && HWtype="SPHardwareDataType.0.cpu_type" || HWtype="SPHardwareDataType.0.chip_type"

SYSTEM_PROFILER_BLOB=$( /usr/sbin/system_profiler -json 'SPHardwareDataType')
MAC_CPU=$( echo $SYSTEM_PROFILER_BLOB | /usr/bin/plutil -extract "${HWtype}" 'raw' -)
MAC_RAM=$( echo $SYSTEM_PROFILER_BLOB | /usr/bin/plutil -extract 'SPHardwareDataType.0.physical_memory' 'raw' -)
FREE_DISK_SPACE=$(($( /usr/sbin/diskutil info / | /usr/bin/grep "Free Space" | /usr/bin/awk '{print $6}' | /usr/bin/cut -c 2- ) / 1024 / 1024 / 1024 ))

ICON_FILES="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/"

# Swift Dialog version requirements

SW_DIALOG="/usr/local/bin/dialog"
MIN_SD_REQUIRED_VERSION="2.5.0"
[[ -e "${SW_DIALOG}" ]] && SD_VERSION=$( ${SW_DIALOG} --version) || SD_VERSION="0.0.0"

# Make some temp files for this app

#JSON_OPTIONS=$(mktemp /var/tmp/AppDelete.XXXXX)
#TMP_FILE_STORAGE=$(mktemp /var/tmp/AppDelete.XXXXX)
#/bin/chmod 666 $JSON_OPTIONS
#/bin/chmod 666 $TMP_FILE_STORAGE

SD_DIALOG_GREETING=$((){print Good ${argv[2+($1>11)+($1>18)]}} ${(%):-%D{%H}} morning afternoon evening)

###################################################
#
# App Specfic variables (Feel free to change these)
#
###################################################

# Support / Log files location

SUPPORT_DIR="/Library/Application Support/GiantEagle"
LOG_FILE="${SUPPORT_DIR}/logs/ChangeFVKey.log"

# Display items (banner / icon)

BANNER_TEXT_PADDING="      " #5 spaces to accomodate for icon offset
SD_WINDOW_TITLE="${BANNER_TEXT_PADDING}Change FileVault Key"
SD_BANNER_IMAGE="${SUPPORT_DIR}/SupportFiles/GE_SD_BannerImage.png"
OVERLAY_ICON="SF=wrench.and.screwdriver.fill,color=blue"
#OVERLAY_ICON="${ICON_FILES}ToolbarCustomizeIcon.icns"
SD_ICON="${ICON_FILES}FileVaultIcon.icns"

# Trigger installs for Images & icons

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
}

function create_infobox_message()
{
	################################
	#
	# Swift Dialog InfoBox message construct
	#
	################################

	SD_INFO_BOX_MSG="## System Info ##<br>"
	SD_INFO_BOX_MSG+="${MAC_CPU}<br>"
	SD_INFO_BOX_MSG+="{serialnumber}<br>"
	SD_INFO_BOX_MSG+="${MAC_RAM} RAM<br>"
	SD_INFO_BOX_MSG+="${FREE_DISK_SPACE}GB Available<br>"
	SD_INFO_BOX_MSG+="{osname} {osversion}<br>"
}

function cleanup_and_exit ()
{
	[[ -f ${JSON_OPTIONS} ]] && /bin/rm -rf ${JSON_OPTIONS}
	[[ -f ${TMP_FILE_STORAGE} ]] && /bin/rm -rf ${TMP_FILE_STORAGE}
    [[ -f ${DIALOG_COMMAND_FILE} ]] && /bin/rm -rf ${DIALOG_COMMAND_FILE}
	exit 0
}

function welcomemsg ()
{
    # PURPOSE: Display a custom message to the user with option button selections
    # RETURNS: value of which button was pressed
    # PARAMETERS: $1 = Message to display
    #             $2 = keyword "password" if you want to challenge the user for their password
    #                  keyword "change" to allow the user to change their existing password
    #             $3 - Overlay icon to show
    # EXPECTED: None
	MainDialogBody=(
        --message "$1"
        --titlefont shadow=1
        --ontop
        --icon "${SD_ICON}"
        --overlayicon "${3}"
        --bannerimage "${SD_BANNER_IMAGE}"
        --bannertitle "${SD_WINDOW_TITLE}"
        --infobox "${SD_INFO_BOX_MSG}"
        --helpmessage ""
        --moveable
        --height 500
        --width 820
        --ignorednd
        --quitkey 0
        --button2text "Cancel"
    )

    # Add items to the array depending on what info was passed

    [[ "$2" == "password" ]] && MainDialogBody+=(--textfield "Enter Password",secure,required)
    [[ "$2" == "change" ]] && MainDialogBody+=(--button1text "Change" --textfield "Enter Password",secure,required) || MainDialogBody+=(--button1text "OK")

	returnval=$("${SW_DIALOG}" "${MainDialogBody[@]}" 2>/dev/null)
    returnCode=$?

    [[ $returnCode == 2 || $returnCode == 10 ]] && {logMe "INFO: User exiting without changes"; cleanup_and_exit;}

    # retrieve the password

    userPass=$(echo $returnval | grep "Enter Password" | awk -F " : " '{print $NF}')
}

function checkFVStatus ()
{
    # PURPOSE: check to see if FV is already eanbled for the user
    # RETURNS: true if FV is enable, otherwise false
    # PARAMETERS: None
    # EXPECTED: None
    echo $(fdesetup haspersonalrecoverykey)
}

function regen_and_escrow () 
{    
    # PURPOSE: regen a new password and escrow it to the JAMF server
    # RETURNS: None
    # PARAMETERS: None
    # EXPECTED: None
    logMe "Generating a new FV Key and escrow to server"

    result=$(expect -c "
    spawn fdesetup changerecovery -personal -user ${LOGGED_IN_USER}
    expect \"Enter the password for user ${LOGGED_IN_USER}:\"
    send '${userPass}'
    expect eof
    ")

    # Log the results
    logMe $result

    logMe "Forcing JAMF recon to escrow token"
    /usr/local/bin/jamf recon

    ${SW_DIALOG} --message 'Your new FileVault key has been generated and escrowed to the server' \
        --icon "${SD_ICON}" \
        --width 550 \
        --height 200 \
        --mini \
        --bannertitle "FileVault Key"
}        

####################################################################################################
#
# Main Script
#
####################################################################################################

declare isFVEanbled
declare userPass

autoload 'is-at-least'

create_log_directory
check_swift_dialog_install
check_support_files
create_infobox_message

isFVEanbled=$(checkFVStatus)

if [[ $isFVEanbled == "true" ]]; then
    logMe "WARNING: No FV key found, prompting user to create key"
    message="It doesn't appear that you have a FileVault key assigned to your account. This key is necessary to allow you into your computer in case you forget your login password.<br><br>Please enter your login password to create a new key"
    welcomemsg $message "password" "warning"
else
    logMe "INFO: Existing FV Key found, allow user to force change"
    message="It appears that you already have a FileVault key assigned to your account. You can force a new recovery key to be generated and that key will be stored on the JAMF server.<br><br>If you want to force a new key, then please type in your password below."
    welcomemsg $message "change" ${OVERLAY_ICON}
fi
while true; do
    # Test the entered admin password
    if dscl /Local/Default -authonly "${LOGGED_IN_USER}" "${userPass}" &>/dev/null; then
        logMe "Password Verified"
        regen_and_escrow
        break
    fi
    welcomemsg "Password verification failed for $LOGGED_IN_USER.  Please try again" "password" "warning"
done
exit 0
