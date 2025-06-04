#!/bin/bash

function DecryptString() {
    echo "${1}" | /usr/bin/openssl enc -aes256 -d -a -A -S "${2}" -k "${3}"
}
username=$(DecryptString $4 'xxxxxxxxx' 'xxxxxxxxxx') 
password=$(DecryptString $5 'xxxxxxxxx' 'xxxxxxxxxx') 
jssURL=$(DecryptString $6 'xxxxxxxxx' 'xxxxxxxxxx') 
ea_name="Status"
ea_value="Disposed"
serial=$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformSerialNumber/{print $4}')

# Create xml
    cat << EOF > /private/tmp/ea.xml
<computer>
    <extension_attributes>
        <extension_attribute>
            <name>$ea_name</name>
            <value>$ea_value</value>
        </extension_attribute>
    </extension_attributes>
</computer>
EOF

## Upload the xml file
curl -sfku "${username}":"${password}" "${jssURL}/JSSResource/computers/serialnumber/${serial}" -T /private/tmp/ea.xml -X PUT

exit 0
