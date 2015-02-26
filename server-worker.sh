#/bin/bash

random_=$[ ( $RANDOM % 20 ) + 2 ]
echo "sleeping $(echo $random_)s seconds..."
sleep $(echo $random_)s

LAST=""
LAST_file='server-worker.last'

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

JOBLINE=$(curl -s http://freifunk.liztv.net/api/serverjobs.php?last=$LAST)
if [ -z "$JOBLINE" ]; then
  exit 0
fi

JOBID=$(echo "$JOBLINE" | cut -d '|' -f 1)
if [[ ! "$JOBID" =~ ^-?[0-9]+$ ]]; then
  exit 1
fi

JOB=$(echo "$JOBLINE" | cut -d '|' -f 2)

if [ $(echo "$JOB" | cut -d ' ' -f 1) == "deployvpn" ]; then 
  HWID=$(echo "$JOB" | cut -d ' ' -f 2)
  if [ ${#HWID} -ne 12 ]; then
    exit 1
  fi
  COMMUNITY_EXPECTED=$(echo "$JOB" | cut -d ' ' -f 3)

  RESPONSE=$(curl -sS http://freifunk.liztv.net/api/fastd-key.php?hwid=$HWID)

  if [ -z "$RESPONSE" ]; then
    logger "server-worker: Error: No such HWID found in Database"
    echo $JOBID > "$LAST_file"
    exit 1
  fi

  COMMUNITY=$(echo $RESPONSE | cut -d'|' -f 1)
  KEY=$(echo $RESPONSE | cut -d'|' -f 2)

  if [ -z "$COMMUNITY" ]; then
        logger "server-worker: Error: Community-string fetched from server was empty"
        echo $JOBID > "$LAST_file"
        exit 1
  fi

  if [ -z "$KEY" ]; then
        logger "server-worker: Error: Fastd-public-key fetched from server was empty"
        echo $JOBID > "$LAST_file"
        exit 1
  fi

  if [ ${#KEY} -ne 64 ]; then
    logger "server-worker: Error: Fastd-public-key fetched from server was not valid."
    echo $JOBID > "$LAST_file"
    exit 1
  fi

  if [ "$COMMUNITY" != "$COMMUNITY_EXPECTED" ]; then
    logger "server-worker: Error: Server said community is $COMMUNITY, you entered $COMMUNITY_EXPECTED, you have to fix the database."
    echo $JOBID > "$LAST_file"
    exit 1
  fi

  DIR="/etc/fastd/$COMMUNITY/nodes/"
  if [ ! -d "$DIR" ]; then
    logger "server-worker: Error: we can't locate the folder for the keyfiles"
    echo $JOBID > "$LAST_file"
    exit 1
  fi

  KEY="key \"$KEY\";"
  
  if [ -f $DIR$HWID ]; then
  	if [ "$(cat $DIR$HWID)" == "$KEY" ]; then
  		logger "server-worker: no need to reimport '$HWID' for community '$COMMUNITY'"
  		echo $JOBID > "$LAST_file"
  		exit 0
  	else
  		logger "server-worker: overwriting fastd-key for hwid '$HWID' in community '$COMMUNITY'"
  	fi
  else
    logger "server-worker: importing fastd-key for new hwid '$HWID' in community '$COMMUNITY'"
  fi
  
  echo $KEY > $DIR$HWID
  kill -HUP $(ps aux | grep fastd | grep $COMMUNITY | awk '{print $2}')
fi

echo $JOBID > "$LAST_file"
