#!/bin/zsh

######################################################################################################
#
# Global "Common" variables
#
######################################################################################################
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
LOGGED_IN_USER=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' )
USER_DIR=$( dscl . -read /Users/${LOGGED_IN_USER} NFSHomeDirectory | awk '{ print $2 }' )
USER_UID=$(id -u "$LOGGED_IN_USER")

FREE_DISK_SPACE=$(($( /usr/sbin/diskutil info / | /usr/bin/grep "Free Space" | /usr/bin/awk '{print $6}' | /usr/bin/cut -c 2- ) / 1024 / 1024 / 1024 ))
MACOS_NAME=$(sw_vers -productName)
MACOS_VERSION=$(sw_vers -productVersion)
MAC_RAM=$(($(sysctl -n hw.memsize) / 1024**3))" GB"
MAC_CPU=$(sysctl -n machdep.cpu.brand_string)

SD_DIALOG_GREETING=$((){print Good ${argv[2+($1>11)+($1>18)]}} ${(%):-%D{%H}} morning afternoon evening)

# Swift Dialog version requirements

SW_DIALOG="/usr/local/bin/dialog"
MIN_SD_REQUIRED_VERSION="2.5.0"
HOUR=$(date +%H)
case $HOUR in
    0[0-9]|1[0-1]) GREET="morning" ;;
    1[2-7])        GREET="afternoon" ;;
    *)             GREET="evening" ;;
esac
SD_DIALOG_GREETING="Good $GREET"

# Make some temp files

JSONOptions=$(mktemp -t "${SCRIPT_NAME}_json.XXXXX")
DIALOG_COMMAND_FILE=$(mktemp -t "${SCRIPT_NAME}_cmd.XXXXX")
chmod 666 $JSONOptions
chmod 666 $DIALOG_COMMAND_FILE
###################################################
#
# App Specific variables (Feel free to change these)
#
###################################################
   
# See if there is a "defaults" file...if so, read in the contents
DEFAULTS_DIR="/Library/Managed Preferences/com.gianteaglescript.defaults.plist"
if [[ -f "$DEFAULTS_DIR" ]]; then
    echo "Found Defaults Files.  Reading in Info"
    SUPPORT_DIR=$(defaults read "$DEFAULTS_DIR" SupportFiles)
    SD_BANNER_IMAGE="${SUPPORT_DIR}$(defaults read "$DEFAULTS_DIR" BannerImage)"
    SPACING=$(defaults read "$DEFAULTS_DIR" BannerPadding)
else
    SUPPORT_DIR="/Library/Application Support/GiantEagle"
    SD_BANNER_IMAGE="${SUPPORT_DIR}/SupportFiles/GE_SD_BannerImage.png"
    spacing=5 #5 spaces to accommodate for icon offset
fi
BANNER_TEXT_PADDING="${(j::)${(l:$SPACING:: :)}}"

# Log files location

LOG_FILE="${SUPPORT_DIR}/logs/${SCRIPT_NAME}.log"

# Display items (banner / icon)

SD_WINDOW_TITLE="${BANNER_TEXT_PADDING}Disk Space Notification"
SD_ICON_FILE="https://images.crunchbase.com/image/upload/c_pad,h_170,w_170,f_auto,b_white,q_auto:eco,dpr_1/vhthjpy7kqryjxorozdk"
OVERLAY_ICON="${SUPPORT_DIR}/SupportFiles/DiskSpace.png"

SHOW_DISK_USAGE="ShowDiskUsage"

DIALOG_INSTALL_POLICY="install_SwiftDialog"
SUPPORT_FILE_INSTALL_POLICY="install_SymFiles"
JQ_FILE_INSTALL_POLICY="install_jq"

##################################################
#
# Passed in variables
# 
#################################################

JAMF_LOGGED_IN_USER=$3                          # Passed in by JAMF automatically
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

	# If the log directory doesnt exist - create it and set the permissions
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

function create_infobox_message ()
{
	################################
	#
	# Swift Dialog InfoBox message construct
	#
	################################

	SD_INFO_BOX_MSG="## System Info ##
"
	#SD_INFO_BOX_MSG+="${MAC_CPU}<br>"
	SD_INFO_BOX_MSG+="${MAC_SERIAL_NUMBER}<br>"
	SD_INFO_BOX_MSG+="${MAC_RAM} RAM<br>"
	SD_INFO_BOX_MSG+="${FREE_DISK_SPACE} GB Available<br>"
	SD_INFO_BOX_MSG+="macOS ${MACOS_VERSION}<br>"
}

function welcomemsg ()
{
    DiskUsage=$(df -h /Users | awk 'END{ print $(NF-4) }' | tr -d '%' )
    
    messagebody='This is an automated message from JAMF<br>'
    messagebody+="to let you know that your available space on your hard drive is "
    messagebody+="getting very low. Your are currently using ${DiskUsage}% of "
    messagebody+="available space.  Anything over 80% utilized can result in problems "
    messagebody+="with software updates, poor system and application performance.  "
    messagebody+="It is recommended that you remove any uncessary files "
    messagebody+="(and make sure to empty the Trash when you are done).

"
    messagebody+="This message will appear if your space utilization gets above 80%, as a "
    messagebody+="friendly reminder to peform routine maintenance to keep your system in good operating condition.

"
    messagebody+="Click on \"Show Files\" to view the largest files on your hard drive."
 
	MainDialogBody=(
		--message "$SD_DIALOG_GREETING $SD_FIRST_NAME. $messagebody"
		--icon "${OVERLAY_ICON}"
        --titlefont shadow=1
		--height 520
        --width 850
		--ontop
		--bannerimage "${SD_BANNER_IMAGE}"
		--bannertitle "${SD_WINDOW_TITLE}"
        --infobox "${SD_INFO_BOX_MSG}"
        --titlefont shadow=1
        --moveable
		--button2text "Show Files"
		--button1text "OK"
		--buttonstyle center
    )

	# Show the dialog screen and allow the user to choose
	
    logMe "INFO: Disk space is at ${DiskUsage}% used."
    "${SW_DIALOG}" "${MainDialogBody[@]}"
	buttonpress=$?

	# User wants to continue, so delete the files

	[[ ${buttonpress} -eq 2 ]] && show_disk_usage
}

function show_disk_usage ()
{
    /usr/local/bin/jamf policy -trigger ${SHOW_DISK_USAGE}
}

####################################################################################################
#
# Main Program
#
####################################################################################################

autoload 'is-at-least'
create_log_directory
check_swift_dialog_install
check_support_files
create_infobox_message
welcomemsg
exit 0
