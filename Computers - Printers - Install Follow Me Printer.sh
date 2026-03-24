#!/bin/bash

# Install Printer
# Author - Encore Technologies
# Author - Tyler Sparr + Jon Covey
# This script will install the specified printer


echo "Installing Follow Me Printer"
lpadmin -p "Follow_Me_Printer" -v "smb://ETPS11APP1.corp.gianteagle.com/Follow-Me-Print" -E -P "/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/PrintCore.framework/Versions/A/Resources/Generic.ppd" -o printer-is-shared=false -o auth-info-required=negotiate -L "Follow Me Print"

#Print Details
lpstat -l -p "Follow_Me_Printer"


exit 0
