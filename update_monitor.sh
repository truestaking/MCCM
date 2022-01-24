#!/bin/bash

DEST='/opt/moonbeam/mccm'
cd $DEST

################################
#### CONVENIENCE FUNCTIONS #####
################################

#Courtesy of cardano guild tools
get_input_default() {
  printf "%s (default: %s): " "$1" "$2" >&2; read -r answer
  if [ -z "$answer" ]; then echo "$2"; else echo "$answer"; fi
}

#Courtesy of cardano guild tools
get_answer() {
  printf "%s (y/n): " "$*" >&2; read -n1 -r answer
  while : 
  do
    case $answer in
    [Yy]*)
      return 0;;
    [Nn]*)
      return 1;;
    *) echo; printf "%s" "Please enter 'y' or 'n' to continue: " >&2; read -n1 -r answer
    esac
  done
}

generate_data(){
cat << EOF
{
"chain": "$CHAIN",
"name": "$NAME",
"address": "$COLLATOR_ADDRESS",
"telegram_username": "$TELEGRAM_USER",
"email_username": "$EMAIL_USER",
"monitor": {
  "process": "$MONITOR_PROCESS",
  "cpu": "$MONITOR_CPU",
  "nvme_heat": "$MONITOR_NVME_HEAT",
  "nvme_lifespan": "$MONITOR_NVME_LIFESPAN",
  "nvme_selftest": "$MONITOR_NVME_SELFTEST",
  "drive_space": "$MONITOR_DRIVE_SPACE",
  "producing_blocks": "$MONITOR_PRODUCING_BLOCKS",
  "oom_condition": "$MONITOR_OOM_CONDITION"
  }
}
EOF
}

write_env() {
  echo -ne "
##### MCCM user variables #####
### Uncomment the next line to set your own peak_load_avg value or leave it undefined to use the MCCM default
#peak_load_avg=

##### END MCCM user variables #####

#### DO NOT EDIT BELOW THIS LINE! #####
#### TO EDIT THESE VARIABLES, RUN update_monitor.sh ####
#### DO NOT COPY THIS FILE or edit the API KEY ####
API_KEY=$API_KEY
NAME='$NAME'
MONITOR_PRODUCING_BLOCKS=$MONITOR_PRODUCING_BLOCKS
MONITOR_PROCESS=$MONITOR_PROCESS
MONITOR_CPU=$MONITOR_CPU
MONITOR_OOM_CONDITION=$MONITOR_OOM_CONDITION
MONITOR_DRIVE_SPACE=$MONITOR_DRIVE_SPACE
MONITOR_NVME_HEAT=$MONITOR_NVME_HEAT
MONITOR_NVME_LIFESPAN=$MONITOR_NVME_LIFESPAN
MONITOR_NVME_SELFTEST=$MONITOR_NVME_SELFTEST
EMAIL_USER=$EMAIL_USER
TELEGRAM_USER=$TELEGRAM_USER
COLLATOR_ADDRESS=$COLLATOR_ADDRESS
ACTIVE=$ACTIVE
" | sudo dd of=$DEST/env status=none
}

####################################
#### END CONVENIENCE FUNCTIONS #####
####################################

echo; echo

cat << "EOF"
  __  __                   _                             _____      _ _       _                              
 |  \/  |                 | |                           / ____|    | | |     | |                             
 | \  / | ___   ___  _ __ | |__   ___  __ _ _ __ ___   | |     ___ | | | __ _| |_ ___  _ __                  
 | |\/| |/ _ \ / _ \| '_ \| '_ \ / _ \/ _` | '_ ` _ \  | |    / _ \| | |/ _` | __/ _ \| '__|                 
 | |  | | (_) | (_) | | | | |_) |  __/ (_| | | | | | | | |___| (_) | | | (_| | || (_) | |                    
 |_|__|_|\___/ \___/|_| |_|_.__/ \___|\__,_|_|_|_| |_|  \_____\___/|_|_|\__,_|\__\___/|_|      _             
  / ____|                                    (_) |         |  \/  |           (_) |           (_)            
 | |     ___  _ __ ___  _ __ ___  _   _ _ __  _| |_ _   _  | \  / | ___  _ __  _| |_ ___  _ __ _ _ __   __ _ 
 | |    / _ \| '_ ` _ \| '_ ` _ \| | | | '_ \| | __| | | | | |\/| |/ _ \| '_ \| | __/ _ \| '__| | '_ \ / _` |
 | |___| (_) | | | | | | | | | | | |_| | | | | | |_| |_| | | |  | | (_) | | | | | || (_) | |  | | | | | (_| |
  \_____\___/|_| |_| |_|_| |_| |_|\__,_|_| |_|_|\__|\__, | |_|  |_|\___/|_| |_|_|\__\___/|_|  |_|_| |_|\__, |
                                                     __/ |                                              __/ |
                                                    |___/                                              |___/ 
EOF
echo; echo;

if [ ! -f $DEST/env ]
then
    echo "Cannot find MCCM config file, please install MCCM"
    exit; exit
fi

source $DEST/env

#### Make sure server and local monitoring status is sycned ###
if sudo systemctl is-active mccm.timer | grep -qi ^active
then
  TIMER_ACTIVE=true
else
  TIMER_ACTIVE=false
fi
if ! [[ $ACTIVE =~ $TIMER_ACTIVE ]]
then
  echo "#####################"
  if [[ $TIMER_ACTIVE =~ "true" ]]
  then
    echo "WARNING: mccm.timer is active but monitoring is paused on our server"
    echo "If you want to resume monitoring, continue and enter y on the next prompt"
    echo "If you want to disable monitoring completely, run sudo systemctl stop mccm.timer"
  else
    echo "WARNING: mccm.timer is inactive but monitoring is active on our server"
    echo "If you want to resume monitoring, run sudo systemctl start mccm.timer"
    echo "If you want to disable monitoring completely, continue and enter y on the next prompt"
  fi
  echo "#####################"
  echo; echo
fi

#### Give the option to pause or resume monitoring
if [[ $ACTIVE =~ "true" ]]
then
  if get_answer "Monitoring is active, do you want to pause monitoring? "
  then
    echo
    RESP="$('/usr/bin/curl' -s -X POST -H 'Content-Type: application/json' -H 'Authorization: Bearer '$API_KEY'' -d '{"active": "false"}' https://monitor.truestaking.com/update)"
    if [[ $RESP =~ "OK" ]]
      then
      ACTIVE=false
      echo "Alerts from our server have been paused"
        if sudo systemctl stop mccm.timer
          then echo "mccm.timer has been paused"
          else echo "failed to stop mccm.timer. Possibly it is not installed, or it was already stopped/disabled." 
        fi
    else
      echo "Server side error: $RESP"
      exit; exit
    fi
    write_env
  fi
else
  if get_answer "Monitoring is inactive, do you want to resume monitoring? "
  then
    echo
    RESP="$('/usr/bin/curl' -s -X POST -H 'Content-Type: application/json' -H 'Authorization: Bearer '$API_KEY'' -d '{"active": "true"}' https://monitor.truestaking.com/update)"
    if [[ $RESP =~ "OK" ]]
      then
      ACTIVE=true
      sudo systemctl start mccm.timer
      echo "Monitoring has been resumed"
    else
      echo "Server side error: $RESP"
      exit; exit
    fi
    write_env
  fi
fi
echo; echo

if ! get_answer "Do you wish to make any other adjustments to your monitoring?"; then echo; exit; fi
echo; echo

##########################
#### SET ENV VARIABLES ####
##########################

#### Set active to be true by default in the setup.sh ####
ACTIVE=true

#### get name, default is hostname ###
if get_answer "The current name is $NAME do you want to set a different name for this server account? "
then
  echo
  NAME=$(get_input_default "Please enter the name for this service account" $NAME)
else echo
fi
echo

#### get chain ####
if get_answer "Is this on the Moonbeam network (yes for Moonbeam, no for Moonriver)"
then CHAIN=glmr
else CHAIN=movr
fi
echo; echo

#### is the collator producing blocks? ####
if get_answer "Do you want to be alerted if your node has failed to produce a block in the normal time window? "
    then MONITOR_PRODUCING_BLOCKS=true
    echo
    COLLATOR_ADDRESS=$(get_input_default "Please enter your node public address. Paste and press <ENTER> " $COLLATOR_ADDRESS)
    else MONITOR_PRODUCING_BLOCKS=false
    echo
fi
echo

#### is the collator process still running? ####
if get_answer "Do you want to be alerted if your collator service stops running?"
    then 
	echo
        service=$(get_input_default "Please enter the service name you want to monitor? This is usually moonriver or moonbeam" $MONITOR_PROCESS)
        if (sudo systemctl -q is-active $service)
            then MONITOR_PROCESS=$service
            else
                MONITOR_PROCESS=false
                echo "\"systemctl is-active $service\" failed, please check service name and rerun setup."
                exit;exit
        fi
    else MONITOR_PROCESS=false
    echo
fi
echo

#### is there an out of memory error condition ####
if get_answer "Do you want to check for an out of memory error condition"
then MONITOR_OOM_CONDITION=true
else MONITOR_OOM_CONDITION=false
fi
echo; echo

#### is my CPU going nuts? ####
if get_answer "Do you want to be alerted if your CPU load average is high?"
    then MONITOR_CPU=true
        if ! sudo apt list --installed 2>/dev/null | grep -qi util-linux
            then sudo apt install util-linux
        fi
        if ! sudo apt list --installed 2>/dev/null | grep -qi ^bc\/
            then sudo apt install bc
        fi
    else MONITOR_CPU=false
fi
echo; echo

#### are the NVME drives running hot? ####
if get_answer "Do you want to be alerted for NVME drive high temperatures? "
    then MONITOR_NVME_HEAT=true
    else MONITOR_NVME_HEAT=false
fi
echo; echo

#### are the NVME drives approaching end of life? ####
if get_answer "Do you want to be alerted when NVME drives reach 80% anticipated lifespan?"
    then MONITOR_NVME_LIFESPAN=true
    else MONITOR_NVME_LIFESPAN=false
fi
echo; echo

#### are the NVME drives failing the selftest? ####
if get_answer "Do you want to be alerted when an NVME drives fails the self-assessment check? "
    then MONITOR_NVME_SELFTEST=true
    else MONITOR_NVME_SELFTEST=false
fi
echo; echo

#### are any of the disks at 90%+ capacity? ####
if get_answer "Do you want to be alerted when any drive reaches 90% capacity?"
    then MONITOR_DRIVE_SPACE=true
    else MONITOR_DRIVE_SPACE=false
fi
echo; echo

#### do we need to install NVME utilities? ####
if echo $MONITOR_NVME_HEAT,$MONITOR_NVME_LIFESPAN,$MONITOR_NVME_SELFTEST | grep -qi true
    then
        echo "checking for NVME utilities..."
        if ! sudo apt list --installed 2>/dev/null | grep -qi nvme-cli
            then
                echo "installing nvme-cli.."
                if ! sudo apt install nvme-cli
                then echo;
                    echo "MCCM setup failed to install nvme-cli. Please manually install nvme-cli and rerun setup."
                echo; echo
                fi
        fi
        if ! sudo apt list --installed 2>/dev/null | grep -qi smartmontools
            then
                echo "installing smartmontools..."
                if ! sudo apt install smartmontools
                then echo
                    echo "MCCM setup failed to install smartmontools. Please manually install nvme-cli and rerun setup."
                    echo; echo
                fi
        fi
	echo;
fi

#### alert via email? ####
if get_answer "Do you want to receive collator alerts via email?" 
    then echo;
    EMAIL_USER=$(get_input_default "Please enter an email address for receiving alerts " $EMAIL_USER)
    else EMAIL_USER=''
fi
echo

#### alert via TG ####
if get_answer "Do you want to receive collator alerts via Telegram?"
    then echo;
    TELEGRAM_USER=$(get_input_default "Please enter your telegram username " $TELEGRAM_USER)
    echo "IMPORTANT: Please enter a telegram chat with our bot 'hi!' LINK: https://t.me/moonbeamccm_bot"
    echo "IMPORTANT: If you are already in a telegram chat with our bot you do not have to create a new one. Press <enter>"
    read -p "After you join a chat with our bot, return here and press <enter>."; echo
    else TELEGRAM_USER=''
fi
if ( echo $TELEGRAM_USER | grep -qi [A-Za-z0-9] ) 
    then echo -n "Please do not exit the chat with our telegram bot. If you do, you will not be able to receive alerts about your system. If you leave the chat please run update_monitor.sh"; echo ;
fi

#### check that there is at least one valid alerting mechanism ####
if ! ( [[ $EMAIL_USER =~ [\@] ]] || [[ $TELEGRAM_USER =~ [a-zA-Z0-9] ]] )
then
  logger "MCCM requires either email or telegram for alerting, bailing out of setup."  
  echo "MCCM requires either email or telegram for alerting. Rerun setup to provide email or telegram alerting.Bailing out."
  exit
fi

###############################
#### END SET ENV VARIABLES ####
###############################

##### update truestaking alert server #####
RESP="$('/usr/bin/curl' -s -X POST -H 'Content-Type: application/json' -H 'Authorization: Bearer '$API_KEY'' -d "$(generate_data)" https://monitor.truestaking.com/update)"
if ! [[ $RESP =~ "OK" ]]
then 
    echo "We encountered an error: $RESP "
    exit
else echo "success!"
fi
echo

write_env

if [[ $ACTIVE =~ "false" ]]
then
  echo
  echo "#############################"
  echo "Warning alerts are currently paused, to resume alerts run update_monitor.sh"
  echo "#############################"
fi
