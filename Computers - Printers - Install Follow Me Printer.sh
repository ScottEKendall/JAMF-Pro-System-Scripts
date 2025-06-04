#!/bin/bash

# Install Printer
# Author - Encore Technologies
# Author - Tyler Sparr + Jon Covey
# This script will install the specified printer

# This script is provided without warranty or guarantee, and is licensed for use only at the direction of Encore Technologies.
# It is not for distribution. Any application of this script at a customer location is allowed; however,
# use of this script by Encore Technologies or customers of Encore Technologies does not make Encore Technologies
# responsible for any ongoing maintenance of this script.

# Copyright © 2021 Encore Technologies

echo "Installing Follow Me Printer"
lpadmin -p "Follow_Me_Printer" -v "smb://ETPS11APP1.corp.gianteagle.com/Follow-Me-Print" -E -P "/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/PrintCore.framework/Versions/A/Resources/Generic.ppd" -o printer-is-shared=false -o auth-info-required=negotiate -L "Follow Me Print"

#Print Details
lpstat -l -p "Follow_Me_Printer"


exit 0
