#!/bin/zsh
#
# Rebuilt the spotlight index to fix any search issues that might been occuring
#
mdutil -ai off 
rm -rf /.Spotlight* 
mdutil -ai on 
mdutil -Ea
