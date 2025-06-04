#!/bin/bash
# Reset Printing System.sh
# This script will reset the printing system removing all printers

#Stop CUPS
launchctl stop org.cups.cupsd

#Backup Installed Printers Property List
[[ -e "/Library/Printers/InstalledPrinters.plist" ]] && mv /Library/Printers/InstalledPrinters.plist /Library/Printers/InstalledPrinters.plist.bak

#Backup the CUPS config file
[[ -e "/etc/cups/cupsd.conf" ]] && mv /etc/cups/cupsd.conf /etc/cups/cupsd.conf.bak

#Restore the default config by copying it
[[ ! -e "/etc/cups/cupsd.conf" ]] && cp /etc/cups/cupsd.conf.default /etc/cups/cupsd.conf

#Backup the printers config file
[[ -e "/etc/cups/printers.conf" ]] && mv /etc/cups/printers.conf /etc/cups/printers.conf.bak

#Start CUPS
launchctl start org.cups.cupsd

#Remove all printers
lpstat -p | cut -d' ' -f2 | xargs -I{} lpadmin -x {}

exit 0
