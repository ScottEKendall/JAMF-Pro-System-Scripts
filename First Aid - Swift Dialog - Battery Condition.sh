#!/bin/zsh
#
# Written by: Scott E. Kendall
# Created: 2025-01-15
# Last Modified: 2025-01-15
#
# Prompt user if battery needs service
#


######################################################################################################
#
# Gobal "Common" variables
#
######################################################################################################
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

JAMF_LOGGED_IN_USER=$3
SD_FIRST_NAME="${(C)JAMF_LOGGED_IN_USER%%.*}"

BATTERY_CONDITION="${4:-"info"}"

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
SUPPORT_DIR="/Library/Application Support/GiantEagle"
OVERLAY_ICON="SF=minus.plus.batteryblock, color=green, weight=normal"
SD_BANNER_IMAGE="${SUPPORT_DIR}/SupportFiles/GE_SD_BannerImage.png"
LOG_DIR="${SUPPORT_DIR}/logs"

ICON_FILES="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/"
LOG_STAMP=$(echo $(/bin/date +%Y%m%d))
LOG_FILE="${LOG_DIR}/BatteryService.log"
SD_WINDOW_TITLE="     Battery Condition"

# Swift Dialog version requirements

SD_VERSION=$( ${SW_DIALOG} --version)
MIN_SD_REQUIRED_VERSION="2.3.3"
DIALOG_INSTALL_POLICY="install_SwiftDialog"
SUPPORT_FILE_INSTALL_POLICY="install_SymFiles"
SD_DIALOG_GREETING=$((){print Good ${argv[2+($1>11)+($1>18)]}} ${(%):-%D{%H}} morning afternoon evening)

SYSTEM_PROFILER_BATTERY_BLOB=$( /usr/sbin/system_profiler 'SPPowerDataType')

BatteryCondition=$(echo $SYSTEM_PROFILER_BATTERY_BLOB | grep "Condition" | awk '{print $2}')
BatteryCycleCount=$(echo $SYSTEM_PROFILER_BATTERY_BLOB | grep "Cycle Count" | awk '{print $3}')
BatteryCapacity=$(echo $SYSTEM_PROFILER_BATTERY_BLOB | grep "Maximum Capacity:" | awk '{print $3}')
BatteryCurrentCharge=$(echo $SYSTEM_PROFILER_BATTERY_BLOB | grep "State of Charge (%):" | awk '{print $NF}' )
BatteryCharging=$(echo $SYSTEM_PROFILER_BATTERY_BLOB | grep "Connected:" | sed 's/.*Connected: //')
BatteryChargingWattage=$(echo $SYSTEM_PROFILER_BATTERY_BLOB | grep "Wattage (W)" | sed 's/.*Wattage (W): //')


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
    echo "${1}" 1>&2
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
    if [[ "${BATTERY_CONDITION:l}" == "info" ]]; then
        messagebody="${SD_DIALOG_GREETING} ${SD_FIRST_NAME}., here is the current state of your laptop battery:<br><br>"
        messagebody+="Condition: **${BatteryCondition}**<br>"
        messagebody+="Current # of Cycles: **${BatteryCycleCount}**<br>"
        messagebody+="Total Capacity Remain: **${BatteryCapacity}**<br>"
        messagebody+="Battery Current Charge: **${BatteryCurrentCharge}%**<br>"
        messagebody+="Currently on Charger: **$BatteryCharging**<br>"
        if [[ "$BatteryCharging" == "Yes" ]]; then
            messagebody+="Charger Wattage: **${BatteryChargingWattage}W**<br>"
        fi
    else
        messagebody="${SD_DIALOG_GREETING} ${SD_FIRST_NAME}.  This is an automated message from JAMF "
        messagebody+="to let you know that the battery in your laptop is below acceptable"
        messagebody+=" limits declared by Apple.  The runtime while on battery and "
        messagebody+="performance may be severly affected.  Please raise at ticket with the"
        messagebody+=" TSD to let them know that you received this message, and it is"
        messagebody+=" recommended that you purchase a new laptop at this time."
    fi
    
	MainDialogBody="${SW_DIALOG} \
		--message '${messagebody}' \
		--icon '${OVERLAY_ICON}' \
        --titlefont shadow=1 \
		--height 420 \
		--ontop \
		--bannerimage '${SD_BANNER_IMAGE}' \
		--bannertitle '${SD_WINDOW_TITLE}' \
        --infobox '${SD_INFO_BOX_MSG}' \
        --titlefont shadow=1 \
        --moveable \
		--button1text 'OK' \
		--buttonstyle center"

	# Show the dialog screen and allow the user to choose

	eval "${MainDialogBody}" 2>/dev/null
}

function cleanup_and_exit ()
{
	[[ -f ${JSON_OPTIONS} ]] && /bin/rm -rf ${JSON_OPTIONS}
	[[ -f ${TMP_FILE_STORAGE} ]] && /bin/rm -rf ${TMP_FILE_STORAGE}
    [[ -f ${DIALOG_COMMAND_FILE} ]] && /bin/rm -rf ${DIALOG_COMMAND_FILE}
	exit 0
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
create_infobox_message
welcomemsg
cleanup_and_exit
