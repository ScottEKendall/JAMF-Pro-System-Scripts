#!/bin/zsh

#
# Log Viewer
#
# Created by: Scott Kendall
# Created on: 01/29/25
# Last Modified: 01/29/25
# 
# Expected Parmaters
#
# Parm #4 - Full Path of Log to view
# Parm #5 - Window Title
# Parm #6 - Length of log to display or email (tail -n)
######################################################################################################
#
# Gobal "Common" variables (do not change these!)
#
######################################################################################################
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
LOGGED_IN_USER=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' )
USER_DIR=$( dscl . -read /Users/${LOGGED_IN_USER} NFSHomeDirectory | awk '{ print $2 }' )

OS_PLATFORM=$(/usr/bin/uname -p)

[[ "$OS_PLATFORM" == 'i386' ]] && HWtype="SPHardwareDataType.0.cpu_type" || HWtype="SPHardwareDataType.0.chip_type"

SYSTEM_PROFILER_BLOB=$( /usr/sbin/system_profiler -json 'SPHardwareDataType')
MAC_SERIAL_NUMBER=$( echo $SYSTEM_PROFILER_BLOB | /usr/bin/plutil -extract 'SPHardwareDataType.0.serial_number' 'raw' -)
MAC_CPU=$( echo $SYSTEM_PROFILER_BLOB | /usr/bin/plutil -extract "${HWtype}" 'raw' -)
MAC_HADWARE_CLASS=$( echo $SYSTEM_PROFILER_BLOB | /usr/bin/plutil -extract 'SPHardwareDataType.0.machine_name' 'raw' -)
MAC_RAM=$( echo $SYSTEM_PROFILER_BLOB | /usr/bin/plutil -extract 'SPHardwareDataType.0.physical_memory' 'raw' -)
FREE_DISK_SPACE=$(($( /usr/sbin/diskutil info / | /usr/bin/grep "Free Space" | /usr/bin/awk '{print $6}' | /usr/bin/cut -c 2- ) / 1024 / 1024 / 1024 ))
MACOS_VERSION=$( sw_vers -productVersion | xargs)

SW_DIALOG="/usr/local/bin/dialog"

#
# Set default vales if not passed
#

LOG_TO_VIEW=${4:-"/var/log/system.log"}
LOG_WINDOW_TITLE=${5:-"System Log"}
LOG_LENGTH=${6:-100}

###################################################
#
# App Specfic variables (Feel free to change these)
#
###################################################

SUPPORT_DIR="/Library/Application Support/GiantEagle"
LOG_DIR="${SUPPORT_DIR}/logs"
LOG_FILE="${LOG_DIR}/AppDelete.log"
LOG_STAMP=$(echo $(/bin/date +%Y%m%d))
SD_BANNER_IMAGE="${SUPPORT_DIR}/SupportFiles/GE_SD_BannerImage.png"

ICON_FILES="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/"
MAIL_ICON="/Applications/Microsoft Outlook.app"
OVERLAY_ICON="${ICON_FILES}AllMyFiles.icns"
TMP_FILE_STORAGE=$(mktemp /var/tmp/ClearBrowserCache.XXXXX)
BANNER_TEXT_PADDING="      "
SD_INFO_BOX_MSG=""
SD_WINDOW_TITLE="${BANNER_TEXT_PADDING}View ${LOG_WINDOW_TITLE}"

# Swift Dialog version requirements

[[ -e "${SW_DIALOG}" ]] && SD_VERSION=$( ${SW_DIALOG} --version) || SD_VERSION="0.0.0"
MIN_SD_REQUIRED_VERSION="2.3.3"
DIALOG_INSTALL_POLICY="install_SwiftDialog"
SUPPORT_FILE_INSTALL_POLICY="install_SymFiles"

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

	# If the log directory doesnt exist - create it and set the permissions
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

	SD_INFO_BOX_MSG="## System Info ##
"
	SD_INFO_BOX_MSG+="${MAC_CPU}<br>"
	SD_INFO_BOX_MSG+="${MAC_SERIAL_NUMBER}<br>"
	SD_INFO_BOX_MSG+="${MAC_RAM} RAM<br>"
	SD_INFO_BOX_MSG+="${FREE_DISK_SPACE}GB Available<br>"
	SD_INFO_BOX_MSG+="macOS ${MACOS_VERSION}<br>"
}

function import_log_contents ()
{
    tail -${LOG_LENGTH} "${LOG_TO_VIEW}" > "${TMP_FILE_STORAGE}"

    tempmsg=""
    while IFS= read -r item; do
        tempmsg+="$item<br>"
    done < "${TMP_FILE_STORAGE}"
}

function mail_logs ()
{
	MainDialogBody=(
		--message "The contents of the log file have been put on the clipboard.  Once the new message is composed, be sure to paste the log (Option-V or Edit > Paste) into the body of the mail message."
        --messagefont "size=16"
		--ontop
		--icon "${MAIL_ICON}"
		--bannerimage "${SD_BANNER_IMAGE}"
		--bannertitle "${SD_WINDOW_TITLE}"
        --titlefont shadow=1
		--quitkey 0
        --json
        --textfield "Email Address:",value="<username>@gianteagle.com"
		--button1text "Send"
        --button2text "Cancel"
        )

    output=$("${SW_DIALOG}" "${MainDialogBody[@]}" 2>/dev/null)
    buttonpress=$?
    [[ ${buttonpress} -eq 2 ]] && return 0

    cat ${TMP_FILE_STORAGE} | pbcopy
    email_address=$(echo $output | awk '{print $NF}'| grep @ | xargs )
    
    # Use outlook to send the email message

    /usr/bin/open -b com.microsoft.outlook 'mailto:'${email_address}'?subject='${LOG_WINDOW_TITLE}' from '${MAC_SERIAL_NUMBER}

}

function welcomemsg ()
{
	MainDialogBody=(
    	--message ${tempmsg}
        --messagefont "size=12"
		--ontop
		--icon "${OVERLAY_ICON}"
		--bannerimage "${SD_BANNER_IMAGE}"
		--bannertitle "${SD_WINDOW_TITLE}"
        --titlefont shadow=1
        --infobox "${SD_INFO_BOX_MSG}"
		--width 1120
        --height 600
		--quitkey 0
        --json
		--button1text "OK"
        --button2text "Send via Email"
        )

	# Show the dialog screen and allow the user to choose

    "${SW_DIALOG}" "${MainDialogBody[@]}" 2>/dev/null
	buttonpress=$?
	[[ ${buttonpress} -eq 0 ]] && return 0
    mail_logs

}

function cleanup_and_exit ()
{
	[[ -f ${JSON_OPTIONS} ]] && /bin/rm -rf ${JSON_OPTIONS}
	[[ -f ${TMP_FILE_STORAGE} ]] && /bin/rm -rf ${TMP_FILE_STORAGE}
    [[ -f ${DIALOG_COMMAND_FILE} ]] && /bin/rm -rf ${DIALOG_COMMAND_FILE}
	exit 0
}

autoload 'is-at-least'

declare email_address

check_swift_dialog_install
create_infobox_message
check_support_files
import_log_contents
welcomemsg
cleanup_and_exit
