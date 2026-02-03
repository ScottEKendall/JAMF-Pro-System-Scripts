#!/bin/zsh
#
# Rebuilt the spotlight index to fix any search issues that might been occuring
#
/usr/bin/mdutil -ai off 
/bin/rm -rf /.Spotlight* 
/usr/bin/mdutil -ai on 
/usr/bin/mdutil -Ea
