#!/bin/zsh
#
# DialogMsg
# 
# Written by: Scott Kendall
#
# Created Date: 01/227/2025
# Last modified: 12/12/2025
#
# Script Purpose: Display a generic SWifDialog notification to JAMF users.  Pass in variables to customize display
#
# v1.0 - Initial script
# v1.1 - Code cleanup to be more consistent with all apps
# v1.2 - the JAMF_LOGGED_IN_USER will default to LOGGED_IN_USER if there is no name present
#      - Added -ignorednd to make sure that the message is displayed regardless of focus setting
#      - Will display the infobox items if you call the function first
#      - Minimum version of SwiftDialog is now 2.5.0
# v1.3 - Reworked top section (again) to be more consistent across apps
#      - Fixed tons of typos
#
# Expected Parameters: 
# #4 - Title
# #5 - Full formatted message to display
# #6 - Button1 Text
# #7 - Image to display
# #8 - JAMF policy to load image if it doesn't exist
# #9 - Notification icon name
# #10 - Timer (in seconds) to wait until dismissal

######################################################################################################
#
# Global "Common" variables (do not change these!)
#
######################################################################################################
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
SCRIPT_NAME="DialogNotify"
LOGGED_IN_USER=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' )
USER_DIR=$( dscl . -read /Users/${LOGGED_IN_USER} NFSHomeDirectory | awk '{ print $2 }' )

[[ "$OS_PLATFORM" == 'i386' ]] && HWtype="SPHardwareDataType.0.cpu_type" || HWtype="SPHardwareDataType.0.chip_type"

SYSTEM_PROFILER_BLOB=$( /usr/sbin/system_profiler -json 'SPHardwareDataType')
MAC_CPU=$( echo $SYSTEM_PROFILER_BLOB | /usr/bin/plutil -extract "${HWtype}" 'raw' -)
MAC_RAM=$( echo $SYSTEM_PROFILER_BLOB | /usr/bin/plutil -extract 'SPHardwareDataType.0.physical_memory' 'raw' -)
FREE_DISK_SPACE=$(($( /usr/sbin/diskutil info / | /usr/bin/grep "Free Space" | /usr/bin/awk '{print $6}' | /usr/bin/cut -c 2- ) / 1024 / 1024 / 1024 ))

ICON_FILES="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/"

# Swift Dialog version requirements

SW_DIALOG="/usr/local/bin/dialog"
MIN_SD_REQUIRED_VERSION="2.5.0"
[[ -e "${SW_DIALOG}" ]] && SD_VERSION=$( ${SW_DIALOG} --version) || SD_VERSION="0.0.0"

SD_DIALOG_GREETING=$((){print Good ${argv[2+($1>11)+($1>18)]}} ${(%):-%D{%H}} morning afternoon evening)

###################################################
#
# App Specific variables (Feel free to change these)
#
###################################################
   
# See if there is a "defaults" file...if so, read in the contents
DEFAULTS_DIR="/Library/Managed Preferences/com.gianteaglescript.defaults.plist"
if [[ -e $DEFAULTS_DIR ]]; then
    echo "Found Defaults Files.  Reading in Info"
    SUPPORT_DIR=$(defaults read $DEFAULTS_DIR "SupportFiles")
    SD_BANNER_IMAGE=$SUPPORT_DIR$(defaults read $DEFAULTS_DIR "BannerImage")
    spacing=$(defaults read $DEFAULTS_DIR "BannerPadding")
else
    SUPPORT_DIR="/Library/Application Support/GiantEagle"
    SD_BANNER_IMAGE="${SUPPORT_DIR}/SupportFiles/GE_SD_BannerImage.png"
    spacing=5 #5 spaces to accommodate for icon offset
fi
repeat $spacing BANNER_TEXT_PADDING+=" "

# Log files location

LOG_FILE="${SUPPORT_DIR}/logs/${SCRIPT_NAME}.log"

# Trigger installs for Images & icons

DIALOG_INSTALL_POLICY="install_SwiftDialog"
SUPPORT_FILE_INSTALL_POLICY="install_SymFiles"
JQ_INSTALL_POLICY="install_jq"

SD_INFO_BOX_MSG=""
SD_DEFAULT_LANGUAGE="EN"
DISPLAY_MESSAGE=""

##################################################
#
# Passed in variables
# 
#################################################

JAMF_LOGGED_IN_USER=${3:-"$LOGGED_IN_USER"}    # Passed in by JAMF automatically
SD_FIRST_NAME="${(C)JAMF_LOGGED_IN_USER%%.*}"   

SD_WINDOW_TITLE="${BANNER_TEXT_PADDING}$4"
SD_WELCOME_MSG="${5:-"Information Message"}"
SD_WELCOME_MSG_ALT="${6:-""}"
SD_BUTTON1_PROMPT="${7:-"OK"}"
SD_IMAGE_TO_DISPLAY="${8:-""}"
SD_IMAGE_POLICY="${9:-""}"
SD_ICON_PRIMARY="${10:-"AlertNoteIcon.icns"}"
SD_TIMER="${11-120}"
SD_ICON_PRIMARY="${ICON_FILES}${SD_ICON_PRIMARY}"


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

	# If the log directory doesn't exist - create it and set the permissions (using zsh parameter expansion to get directory)
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
    echo "$(/bin/date '+%Y-%m-%d %H:%M:%S'): ${1}" | tee -a "${LOG_FILE}" 1>&2
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
    [[ ! -e "${SD_IMAGE_TO_DISPLAY}" ]] && /usr/local/bin/jamf policy -trigger ${SD_IMAGE_POLICY}
    /bin/chmod 666 "${SD_IMAGE_TO_DISPLAY}"
}

function check_logged_in_user ()
{
    if [[ -z "$LOGGED_IN_USER" ]] || [[ "$LOGGED_IN_USER" == "loginwindow" ]]; then
        logMe "INFO: No user logged in"
        exit 1
    fi
}

function display_msg ()
{
	MainDialogBody=(
		--message "${SD_DIALOG_GREETING}, ${SD_FIRST_NAME}.  ${DISPLAY_MESSAGE}"
		--ontop
		--icon "${SD_ICON_PRIMARY}"
        --titlefont shadow=1
		--overlayicon computer
		--bannerimage "${SD_BANNER_IMAGE}"
		--bannertitle "${SD_WINDOW_TITLE}"
        --infobox "${SD_INFO_BOX_MSG}"
        --ignorednd
        --moveable
        --helpmsg ""
		--quitkey 0
        --timer "${SD_TIMER}"
		--button1text "${SD_BUTTON1_PROMPT}"
    )
        [[ ! -z "${SD_IMAGE_TO_DISPLAY}" ]] && MainDialogBody+=(--height 530 --image "${SD_IMAGE_TO_DISPLAY}")

	# Show the dialog screen and allow the user to choose

    "${SW_DIALOG}" "${MainDialogBody[@]}" 2>/dev/null
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

function check_language_support ()
{

    declare -a languageArray
    declare preferredLanguage && preferredLanguage=${LANG[1,2]:u}

    # if there is no 2nd language line, the just return the 1st line
    
    if [[ -z "${SD_WELCOME_MSG_ALT}" ]]; then
        echo "${SD_WELCOME_MSG}"
        return 0
    fi

    languageArray+=(${SD_WELCOME_MSG})
    languageArray+=(${SD_WELCOME_MSG_ALT})

    # get the system(s) default language

    # Loop through the array and print the message for the preferred language
    for entry in "${languageArray[@]}"; do
        langCode=$(echo $entry | awk -F "|" '{print $1}' | xargs)
        message=$(echo $entry | awk -F "|" '{print $2}'| xargs)
        if [[ "$preferredLanguage" == "$langCode" ]]; then
            echo "${message}"
            return 0
        fi
    done

    # If no match was found, print the message for the default language
    for entry in "${languageArray[@]}"; do
        langCode=$(echo $entry | awk -F "|" '{print $1}'| xargs)
        message=$(echo $entry | awk -F "|" '{print $2}' | xargs)

        if [[ "$SD_DEFAULT_LANGUAGE" == "$langCode" ]]; then
            echo "${message}"
            return 0
        fi
    done
}

####################################################################################################
#
# Main Script
#
####################################################################################################

autoload 'is-at-least'

check_logged_in_user
check_swift_dialog_install
check_support_files
create_infobox_message
DISPLAY_MESSAGE=$(check_language_support)
display_msg
exit 0
