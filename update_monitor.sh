#!/bin/bash

DEST='/opt/moonbeam/mccm'

cd $DEST

get_input() {
  printf "$1: " "$2" >&2; read -r answer
  if [ -z "$answer" ]; then echo "$2"; else echo "$answer"; fi
}

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

cat << "EOF"
 #   #                       #                                   ###           ##     ##            #                  
 ## ##   ###    ###   # ##   ####    ###    ####  ## #          #   #   ###     #      #     ####  ####    ###   # ##  
 # # #  #   #  #   #  ##  #  #   #  #####  #   #  # # #         #      #   #    #      #    #   #   #     #   #  ##    
 # # #  #   #  #   #  #   #  #   #  #      #  ##  # # #         #   #  #   #    #      #    #  ##   #     #   #  #     
 #   #   ###    ###   #   #  ####    ###    ## #  #   #          ###    ###    ###    ###    ## #    ##    ###   #     
                                                                                                                       
  ###                                        #     #                   #   #                  #     #                     #                 
 #   #   ###   ## #   ## #   #   #  # ##          ####   #   #         ## ##   ###   # ##          ####    ###   # ##          # ##    #### 
 #      #   #  # # #  # # #  #   #  ##  #    #     #     #   #         # # #  #   #  ##  #    #     #     #   #  ##       #    ##  #  #   # 
 #   #  #   #  # # #  # # #  #  ##  #   #    #     #      ####         # # #  #   #  #   #    #     #     #   #  #        #    #   #   #### 
  ###    ###   #   #  #   #   ## #  #   #    #      ##       #         #   #   ###   #   #    #      ##    ###   #        #    #   #      # 
                                                          ###                                                                          ###  
EOF
echo; echo;

if [ ! -f $DEST/env ]
then
    echo "Cannot find MCCM config file, please install MCCM"
    exit; exit
fi

source $DEST/env

IS_ALIVE=1
read -n1 -sp "Do you want to pause or resume MCCM alerts? p for pause, r for resume, n for no [p/r/n]: " pqn ;
echo
if [[ $pqn =~ "p" ]]
then
  RESP="$('/usr/bin/curl' -s -X POST -H 'Content-Type: application/json' -H 'Authorization: Bearer '$API_KEY'' -d '{"active": "false"}' https://monitor.truestaking.com/update)"
  if [[ $RESP =~ "OK" ]]
    then
    IS_ALIVE=0
    echo "Alerts from our server have been paused"
      if sudo systemctl stop mccm.timer
        then echo "mccm.timer has been paused"
        else echo "failed to stop mccm.timer. Possibly it is not installed, or it was already stopped/disabled." 
      fi
  else
    echo "Server side error: $RESP"
    exit; exit
  fi
elif [[ $pqn =~ "r" ]]
then
  RESP="$('/usr/bin/curl' -s -X POST -H 'Content-Type: application/json' -H 'Authorization: Bearer '$API_KEY'' -d '{"active": "true"}' https://monitor.truestaking.com/update)"
  if [[ $RESP =~ "OK" ]]
    then
    echo "Monitoring has been resumed"
  else
    echo "Server side error: $RESP"
    exit; exit
  fi
fi
echo

if ! get_answer "Do you wish to make any other adjustments to your monitoring?"; then exit; fi
echo

cat << "EOF"


Moonbeam Collator Community Monitoring

Basic -> just the stuff you need near time alerting on

Simple -> just standard Linux command line tools

Essential -> everything you need, nothing more
    - block production warning
    - collator service status
    - loss of network connectivity
    - disk space
    - nvme heat, lifespan, and selftest
    - cpu load average

Free -> backend alerting contributed by True Staking (we use it for our own servers, we might as well share)

EOF
echo;echo

##### Is my collator producing blocks? #####
COLLATOR_ADDRESS=''
if get_answer "Do you want to be alerted if your node has failed to produce a block in the normal time window? "
    then MONITOR_PRODUCING_BLOCKS='true'
    echo
    COLLATOR_ADDRESS=$(get_input "Please enter your node public address. Paste and press <ENTER> ")
    else MONITOR_PRODUCING_BLOCKS='false'
    echo
fi
echo

##### Is the collator process still running? #####
if get_answer "Do you want to be alerted if your collator service stops running?"
    then 
	echo
        service=$(get_input "Please enter the service name you want to monitor? This is usually moonriver or moonbeam")
        if (sudo systemctl -q is-active $service)
            then MONITOR_PROCESS=$service
            else
                MONITOR_PROCESS='false'
                echo "\"systemctl is-active $service\" failed, please check service name and rerun setup."
                exit;exit
        fi
    else MONITOR_PROCESS='false'
    echo
fi
echo

##### Is my CPU going nuts? #####
if get_answer "Do you want to be alerted if your CPU load average is high?"
    then MONITOR_CPU='true'
        if ! sudo apt list --installed 2>/dev/null | grep -qi util-linux
            then sudo apt install util-linux
        fi
        if ! sudo apt list --installed 2>/dev/null | grep -qi ^bc\/
            then sudo apt install bc
        fi
    else MONITOR_CPU='false'
fi
echo; echo

##### Are my NVME drives running hot? #####
if get_answer "Do you want to be alerted for NVME drive high temperatures? "
    then MONITOR_NVME_HEAT='true'
    else MONITOR_NVME_HEAT='false'
fi
echo; echo

##### Are NVME drives approaching end of life? #####
if get_answer "Do you want to be alerted when NVME drives reach 80% anticipated lifespan?"
    then MONITOR_NVME_LIFESPAN='true'
    else MONITOR_NVME_LIFESPAN='false'
fi
echo; echo

##### Are NVME drives failing the selftest? #####
if get_answer "Do you want to be alerted when an NVME drives fails the self-assessment check? "
    then MONITOR_NVME_SELFTEST='true'
    else MONITOR_NVME_SELFTEST='false'
fi
echo; echo

##### Are any of the disks at 90%+ capacity? #####
if get_answer "Do you want to be alerted when any drive reaches 90% capacity?"
    then MONITOR_DRIVE_SPACE='true'
    else MONITOR_DRIVE_SPACE='false'
fi
echo; echo

##### Do we need to install NVME utilities? #####
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

##### ALert me via email? #####
if get_answer "Do you want to receive collator alerts via email?" 
    then echo;
    EMAIL_USER=$(get_input "Please enter an email address for receiving alerts ")
    else EMAIL_USER=''
fi
echo

##### Alert me via TG #####
TELEGRAM_USER="";
if get_answer "Do you want to receive collator alerts via Telegram?"
    then echo;
    TELEGRAM_USER=$(get_input "Please enter your telegram username ")
    echo "IMPORTANT: Please enter a telegram chat with our bot and message 'hi!' LINK: https://t.me/moonbeamccm_bot"
    read -p "After you say "hi" to the mccm bot press <enter>."; echo
    else TELEGRAM_USER=''
fi
if ( echo $TELEGRAM_USER | grep -qi [A-Za-z0-9] ) 
    then echo -n "Please do not exit the chat with our telegram bot. If you do, you will not be able to receive alerts about your system. If you leave the chat please run update_monitor.sh"; echo ;
fi

##### check that we have at least one valid alerting mechanism #####
if ! ( [[ $EMAIL_USER =~ [\@] ]] || [[ $TELEGRAM_USER =~ [a-zA-Z0-9] ]] )
then
  logger "MCCM requires either email or telegram for alerting, bailing out of setup."  
  echo "MCCM requires either email or telegram for alerting. Rerun setup to provide email or telegram alerting.Bailing out."
  exit
fi

##### register with truestaking alert server #####
RESP="$('/usr/bin/curl' -s -X POST -H 'Content-Type: application/json' -H 'Authorization: Bearer '$API_KEY'' -d '{"chain": "movr", "address": "'$COLLATOR_ADDRESS'", "telegram_username": "'$TELEGRAM_USER'", "email_username": "'$EMAIL_USER'", "monitor": {"process": "'$MONITOR_PROCESS'", "nvme_heat": '$MONITOR_NVME_HEAT', "nvme_lifespan": '$MONITOR_NVME_LIFESPAN', "nvme_selftest": '$MONITOR_NVME_SELFTEST', "drive_space": '$MONITOR_DRIVE_SPACE', "cpu": '$MONITOR_CPU', "producing_blocks": '$MONITOR_PRODUCING_BLOCKS'}}' https://monitor.truestaking.com/update)"
if ! [[ $RESP =~ "OK" ]]
then 
    echo "We encountered an error: $RESP "
else echo "success!"
fi
  
echo
sudo mkdir -p $DEST 2>&1 >/dev/null
sudo echo -ne "##### MCCM user variables #####\n### Uncomment the next line to set your own peak_load_avg value or leave it undefined to use the MCCM default\n#peak_load_avg=\n\n##### END MCCM user variables #####\n\n#### DO NOT EDIT BELOW THIS LINE! #####\nAPI_KEY=$API_KEY\nMONITOR_PRODUCING_BLOCKS=$MONITOR_PRODUCING_BLOCKS\nMONITOR_IS_ALIVE=$MONITOR_IS_ALIVE\nMONITOR_PROCESS=$MONITOR_PROCESS\nMONITOR_CPU=$MONITOR_CPU\nMONITOR_DRIVE_SPACE=$MONITOR_DRIVE_SPACE\nMONITOR_NVME_HEAT=$MONITOR_NVME_HEAT\nMONITOR_NVME_LIFESPAN=$MONITOR_NVME_LIFESPAN\nMONITOR_NVME_SELFTEST=$MONITOR_NVME_SELFTEST\nEMAIL_USER=$EMAIL_USER\nTELEGRAM_USER=$TELEGRAM_USER\nCOLLATOR_ADDRESS=$COLLATOR_ADDRESS" > $DEST/env

if [[ $IS_ALIVE =~ "0" ]]
then
  echo
  echo "#############################"
  echo "Warning alerts are currently paused, to resume alerts run update_monitor.sh"
  echo "#############################"
fi
