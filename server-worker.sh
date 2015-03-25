#/bin/bash

LAST=""
LAST_file='server-worker.last'
RETRY=0

function load_check_last_file() {
  if [ -f "$LAST_file" ]; then
    LAST=$(cat "$LAST_file")
  
    if [ -z "$LAST" ]; then
      echo "lastid not found, starting from top"
      LAST=1
      echo "$LAST" > "$LAST_file" || exit 1
    elif [[ ! "$LAST" =~ ^-?[0-9]+$ ]]; then
      echo "lastid is broken, starting from top"
      LAST=1
      echo "$LAST" > "$LAST_file" || exit 1
    fi
  else
    touch $LAST_file || exit 1
  fi  
}

function fetch_jobline() {
  JOBLINE=$(curl -s http://freifunk.liztv.net/api/serverjobs.php?last=$LAST)
  if [ -z "$JOBLINE" ]; then
    exit 0
  fi  
}

function parse_jobline() {
  JOBID=$(echo "$JOBLINE" | cut -d '|' -f 1)
  
  check_jobid
  
  JOB=$(echo "$JOBLINE" | cut -d '|' -f 2)  

  if [ $(echo "$JOB" | cut -d ' ' -f 1) == "deployvpn" ]; then 
    HWID=$(echo "$JOB" | cut -d ' ' -f 2)
    if [ ${#HWID} -ne 12 ]; then
      RETRY=$(expr $RETRY + 1)
    else
      COMMUNITY_EXPECTED=$(echo "$JOB" | cut -d ' ' -f 3)
    fi
  else #no job for us
    exit 0
  fi
  
}

function check_jobid() {
  if [[ ! "$JOBID" =~ ^-?[0-9]+$ ]]; then
    exit 1
  fi
}

function get_check_fastd_key {
  RESPONSE=$(curl -sS http://freifunk.liztv.net/api/fastd-key.php?hwid=$HWID)
  if [ -z "$RESPONSE" ]; then
    logger "server-worker: Error: No such HWID found in Database"
    RETRY=$(expr $RETRY + 1)
  else
    COMMUNITY=$(echo $RESPONSE | cut -d'|' -f 1)
    KEY=$(echo $RESPONSE | cut -d'|' -f 2)
    
    if [ -z "$COMMUNITY" ]; then
        logger "server-worker: Error: Community-string fetched from server was empty"
        RETRY=$(expr $RETRY + 1)
    elif [ -z "$KEY" ]; then
      logger "server-worker: Error: Fastd-public-key fetched from server was empty"
      RETRY=$(expr $RETRY + 1)
    elif [ ${#KEY} -ne 64 ]; then
      logger "server-worker: Error: Fastd-public-key fetched from server was not valid."
      RETRY=$(expr $RETRY + 1)
    elif [ "$COMMUNITY" != "$COMMUNITY_EXPECTED" ]; then
      logger "server-worker: Error: Server said community is $COMMUNITY, you entered $COMMUNITY_EXPECTED, you have to fix the database."
      RETRY=$(expr $RETRY + 1)
    fi
    
    DIR="/etc/fastd/$COMMUNITY/nodes/"
    KEY="key \"$KEY\";"
    
    if [ ! -d "$DIR" ]; then
      logger "server-worker: Error: we can't locate the folder for the keyfiles"
      RETRY=$(expr $RETRY + 1)
    elif [ -f $DIR$HWID ]; then
    	if [ "$(cat $DIR$HWID)" == "$KEY" ]; then
    		logger "server-worker: no need to reimport '$HWID' for community '$COMMUNITY'"
    		RETRY=$(expr $RETRY + 1)
    	else
    		logger "server-worker: overwriting fastd-key for hwid '$HWID' in community '$COMMUNITY'"
    		RETRY=0
    	fi
    else
      logger "server-worker: importing fastd-key for new hwid '$HWID' in community '$COMMUNITY'"
      RETRY=0
    fi
  fi
  
}

load_check_last_file
fetch_jobline
parse_jobline

#we are working on it, move JOBID one forward...
echo $JOBID > "$LAST_file"

until [ "$RETRY" -ge 90 ]; do #10 seconds sleep * 90 times means 15 minutes retrys
  get_check_fastd_key
  if [ "$RETRY" -eq 0 ]; then
    echo $KEY > $DIR$HWID
    kill -HUP $(ps aux | grep fastd | grep $COMMUNITY | awk '{print $2}')
  fi
done
