#!/bin/zsh

updatepath() {
  for ARG in "$@"; do
    [ -d "$ARG" ] && [[ ":$PATH:" != *":$ARG:"* ]] && PATH="${PATH:+"$PATH:"}$ARG"
  done
}

# ensure /bin and /usr/bin are in $PATH
updatepath "/bin" "/usr/bin" 

# unload user agents
for name in $(who | awk '{print $1}' | uniq); do
    userid=$(id -u ${name})
    for agent in $(sudo -u ${name} launchctl list | egrep -i 'outset' | awk '{print $NF}'); do
        launchctl bootout gui/${userid}/${agent}
    done
done

# unload system Daemons
for daemon in $(launchctl list | egrep -i 'outset' | awk '{print $NF}'); do 
    launchctl bootout system ${daemon}
done

# remove launchd plists
rm /Library/LaunchAgents/io.macadmins.Outset*
rm /Library/LaunchDaemons/io.macadmins.Outset*

# remove outset
rm -r /usr/local/outset
