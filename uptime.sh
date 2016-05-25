#!/bin/bash

############################################################################################################
#
# Script to monitor uptime, and notify user if uptime threshold is approaching.
#
# Author: Luke Windram
# Created: 3/18/15
# Modified: 3/27/15 - moved repetitive tasks into functions, changed countdowns to progress bar cocoaDialog
#
# Credits:
#       scriptLogging functions from @rtrouton
#       cocoaDialog countdown timer from jamfnation - post 8360
#
# Dependencies:
#       requires cocoaDialog v 3.0 beta 7 located at variable CD
#
# File Locations:
#   This script should be located at /private/var/uptimeCheck.sh
#   Upon the first instantiation,
#       A permanent LaunchDaemon will be created at variable launchDaemonStd
#   Depending upon conditions met,
#       A temporary LaunchDaemon may be created at variable launchDaemonAccel
#   extensive logging at variable logLocation
#
############################################################################################################

############################################################################################################
#
# NOTES:
#
# 4 conditions can result from this script:
#
# 1.) No Action - if uptime is less than the initialNotification threshold
# 2.) Soft Warning - if uptime is greater than initialNotification threshold but less than (maxUptime-increaseUrgency)
# 3.) Urgent Warning - if uptime is greater than maxUptime-increaseUrgnecy but less than maxUptime
#   a.) notify user
#   b.) place plist to call this script at frequency specified by acceleratedCheckFrequency
# 4.) Warning and Reboot - if uptime is greater than maxUptime.  5 minutes are provided for saving prior to shutdown
#   a.) notify user every thirty seconds
#   b.) hard shutdown
#
# Script needs to be called once after placement to enable continued use.  I deploy as a package with a
# post-install script.
#
# On initial deployment, some devices may be greatly in excess of the maxUptime value.  It is not desirable to shut
# them down with only 5 minutes warning.  In the event that the uptime is greater than maxUptime a 5th condition
# will occur.  It is similar to condition #4, but the countdown occurs over 2 hours.  This condition can only be
# reached once per device.
#
############################################################################################################

############################################################################################################
#                                                                                                          #
#  Variables Section                                                                                       #
#                                                                                                          #
############################################################################################################

############################################################################################################
# User Modifiable Variables
############################################################################################################

# Time conversions reference
# 1 hour = 3600
# 2 hours = 7200
# 4 hours = 14400
# 8 hours = 28800
# 1 day = 86400
# 2 days = 172800
# 3 days = 259200
# 4 days = 345600
# 5 days = 432000
# 6 days = 518400
# 7 days = 604800

# What is the desired initial notfiication uptime (in seconds)
# i.e. at what minimum uptime should Condition #2 be reached
# measured in seconds
initialNotification=345600

# What is the desired maximum uptime before an automated reboot?
# i.e. at what minimum uptime should Condition #4 be reached
# measured in seconds
maxUptime=604800

# With how much time remaining should the warnings become more urgent?
# i.e. how long before maxUptime should Condition #3 be reached
# measured in seconds
# Note that maxuptime will be reduced by this value!  It is not an uptime threshold.
increaseUrgency=86400

# What is the desired frequency for checking uptime?
# i.e. how often should this script run?
# measured in seconds
# Note that value is only applied during the first iteration of the script
# once the script is placed it will bypass creation of this file.  If you
# wish to modify this value for testing, refer to the comments in the
# Pre-Script cleanup and dependency verification section
checkFrequency=14400

# What is the desired frequency for checking uptime once condition 3 is met?
# This should be a fraction of the increaseUrgency value, but not so frequent that the computer becomes diffficult to use.
# measured in seconds
# Note that value is applied every time the script is instantiated
acceleratedCheckFrequency=3600

# Where should script logs be stored?
logLocation="/var/log/uptimeChecker"

#Location of CocoaDialog.app
CD="/private/var/CocoaDialog.app/Contents/MacOS/CocoaDialog"

############################################################################################################
# Fixed Variables - Do not modify!!!!!
############################################################################################################

userName=$(who |grep console| awk '{print $1}')
launchDaemonStd="/Library/LaunchDaemons/com.grcs.uptimeCheck.plist"
launchDaemonAccel="/Library/LaunchDaemons/com.grcs.acceleratedUptimeCheck.plist"

############################################################################################################
# Uptime calculation
############################################################################################################

# calculate value for lower boundary of urgent threshold
urgentThreshold=$(($maxUptime-$increaseUrgency))

# determine uptime
then=$(sysctl kern.boottime | awk '{print $5}' | sed "s/,//")
now=$(date +%s)
diff=$(($now-$then))
uptime=$diff

############################################################################################################
#                                                                                                          #
#  Functions Section                                                                                       #
#                                                                                                          #
############################################################################################################

############################################################################################################
# Function - Script Logging
############################################################################################################

#call as scriptLogging quotedTextForLog

scriptLogging(){

DATE=$(date +%Y-%m-%d\ %H:%M:%S)

echo "$DATE" " $1" >> $logLocation
}

############################################################################################################
# Function - appropriately display single v. plural values
############################################################################################################

#call as format number label

format(){
if [ $1 == 1 ]; then
    echo $1 $2
else
    echo $1 $2"s"
fi
}

############################################################################################################
# Function - appropriately display time (uptime or countdown)
############################################################################################################

#call as formatSeconds timeInSeconds

formatSeconds(){

passedSeconds=$1
displayHours=$(($passedSeconds/3600))
passedSeconds=$(($passedSeconds-($displayHours*3600)))
displayMinutes=$(($passedSeconds/60))
passedSeconds=$(($passedSeconds-($displayMinutes*60)))
if [ $displayHours = 0 ]; then
    if [ $displayMinutes = 0 ]; then
        formattedRemainingTime="$(format $passedSeconds " second")"
    else
        formattedRemainingTime="$(format $displayMinutes " minute") $(format $passedSeconds " second")"
    fi
else
    formattedRemainingTime="$(format $displayHours " hour") $(format $displayMinutes " minute") $(format $passedSeconds " second")"
fi

echo "$formattedRemainingTime"

}

############################################################################################################
# Function - display sticky shutdown counter
############################################################################################################

#call as displayCountdown timeSeconds title message

displayCountdown(){

timerSeconds=$1
rm -f /tmp/hpipe
mkfifo /tmp/hpipe
sleep 0.2

"$CD" progressbar --title "$2" --text "Preparing to shutdown this Mac..." \
--posX "right" --posY "top" --width 450 --float \
--icon "hazard" \
--icon-height 48 --icon-width 48 --height 90 < /tmp/hpipe &

## Send progress through the named pipe
exec 3<> /tmp/hpipe
echo "100" >&3
sleep 1.5

startTime=`date +%s`
stopTime=$((startTime+timerSeconds))
secsLeft=$timerSeconds
progLeft="100"

while [[ "$secsLeft" -gt 0 ]]; do
    sleep 1
    currTime=`date +%s`
    progLeft=$((secsLeft*100/timerSeconds))
    secsLeft=$((stopTime-currTime))
    formattedDisplayCounter=$(formatSeconds $secsLeft)
    echo "$progLeft $formattedDisplayCounter $3" >&3
done

}

############################################################################################################
#                                                                                                          #
#  Pre-Script cleanup and dependency verification                                                          #
#                                                                                                          #
############################################################################################################

scriptLogging "* Script Initiated"
scriptLogging "User is $userName"

############################################################################################################
# log pretty uptime
############################################################################################################

formattedUptime=$(formatSeconds $uptime)
scriptLogging "Uptime: $formattedUptime or $uptime seconds  User: $UserName"

############################################################################################################
# Install and load standard check-in plist if it does not exist
#
# Commenting out the the lines below ### will cause the plist to be recreated every time the script runs
# - refer to checkFrequency to determine how often this will occur
#
############################################################################################################

###comment out below line for testing (1 of 2)
if [ ! -e $launchDaemonStd ]; then
    #install plist
    /bin/cat <<EOM >$launchDaemonStd
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
    <key>Label</key>
    <string>com.grcs.uptimeCheck.plist</string>
    <key>ProgramArguments</key>
    <array>
    <string>/private/var/uptimeCheck.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>$checkFrequency</integer>
    </dict>
    </plist>
EOM
    scriptLogging "$launchDaemonStd placed"

    #set the permission on the file just made.
    chown root:wheel $launchDaemonStd
    chmod 644 $launchDaemonStd
    scriptLogging "$launchDaemonStd permissions set"

    #load plist
    launchctl load $launchDaemonStd
    scriptLogging "$launchDaemonStd loaded"


    #assumes that plist does not exist because script has not run previously!!
    scriptLogging "Initial run condition met"
    if [ $uptime -ge $maxUptime ]; then
        scriptLogging "Uptime in excess of MaxUptime"
        scriptLogging "Uptime = $uptime"
        scriptLogging "MaxUptime = $maxUptime"
        launchctl unload $launchDaemonStd
        scriptLogging "$launchDaemonStd unloaded - cannot run during this countdown"
        #start 2 hour countdown
        scriptLogging "2 Hour Countdown Started"
        displayCountdown 7200 "Maximum Uptime Exceeded!" "until automatic shutdown."
    #upon return from function - force immediate hard shutdown
        scriptLogging "!Performing hard shutdown now!"
        shutdown -h now
    fi
###comment out below line for testing (2 of 2)
fi

############################################################################################################
#                                                                                                          #
#  Script Body                                                                                             #
#                                                                                                          #
############################################################################################################

###########################################################################################################
# Unload and remove accelerated plist (this is only installed to repeat condition #2 more frequently)
###########################################################################################################

if [ -e $launchDaemonAccel ]; then
    launchctl unload $launchDaemonAccel
    scriptLogging "$launchDaemonAccel unloaded"
    rm -f $launchDaemonAccel
    scriptLogging "$launchDaemonAccel deleted"
fi

############################################################################################################
# Condition Testing
############################################################################################################

# Test for Condition #4
if [ $uptime -ge $maxUptime ]; then
    #start 5 minute countdown
    displayCountdown 300 "Maximum Uptime Approaching!" "until automatic shutdown!"
    scriptLogging "!Performing hard shutdown now!"
    shutdown -h now

# Test for Condition #3 and temporarily load additional plist if condition met
elif [ $uptime -ge $urgentThreshold ]; then

    #########################################################################################################
    # place accelerated uptimeCheck plist
    #########################################################################################################

    /bin/cat <<EOM2 >$launchDaemonAccel
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
    <key>Label</key>
    <string>com.grcs.acceleratedUptimeCheck.plist</string>
    <key>ProgramArguments</key>
    <array>
    <string>/private/var/uptimeCheck.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>$acceleratedCheckFrequency</integer>
    </dict>
    </plist>
EOM2

    #set the permission on the file just made.
    chown root:wheel $launchDaemonAccel
    chmod 644 $launchDaemonAccel
    scriptLogging "$launchDaemonAccel placed"

    #########################################################################################################
    # load accelerated check-in plist
    #########################################################################################################
    launchctl load $launchDaemonAccel
    scriptLogging "$launchDaemonAccel loaded"

    #########################################################################################################
    # notify user
    #########################################################################################################

    remainingTime=$(($maxUptime-$uptime))
    formattedRemainingTime=$(formatSeconds $remainingTime)
    secondsAdj="-v+"$remainingTime"S"
    rebootTime=$(date $secondsAdj +"%A at %r")
    $CD bubble --title "Reboot Urgently Needed" --text "Automatic Shutdown scheduled for $rebootTime" \
    --background-top "FFFF00" --background-bottom "FF9900" \
    --icon "caution" --no-timeout &
    scriptLogging "Urgent Warning Provided - Uptime was $formattedUptime"
    scriptLogging "Shutdown scheduled for $rebootTime"

# Test for Condition #2
elif [ $uptime -ge $initialNotification ]; then
#create temp file
    $CD bubble --debug --title "Reboot Needed Soon!" --text "Computer has been running for $formattedUptime." \
    --background-top "66FF00" --background-bottom "99CC00" \
    --icon "notice" --no-timeout &
    scriptLogging "Soft Warning Provided - Uptime was $formattedUptime"

# else assume Condition #1
else
    scriptLogging "No Action taken  - Uptime was $formattedUptime"
    scriptLogging "uptime: $uptime < threshold: $initialNotification"
fi

scriptLogging "* Script Completed"
exit 0

