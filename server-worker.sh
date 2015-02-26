#/bin/bash
LAST=""
LAST_file='server-worker.last'

if [ -f "$LAST_file" ]; then
  LAST=$(cat server-worker.last)
  
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
    echo "No such HWID found in Database"
    exit 1
  fi

  COMMUNITY=$(echo $RESPONSE | cut -d'|' -f 1)
  KEY=$(echo $RESPONSE | cut -d'|' -f 2)

  if [ -z "$COMMUNITY" ]; then
        echo "Error: Community-string fetched from server was empty"
        exit 1
  fi

  if [ -z "$KEY" ]; then
        echo "Error: Fastd-public-key fetched from server was empty"
        exit 1
  fi

  if [ ${#KEY} -ne 64 ]; then
    echo "Error: Fastd-public-key fetched from server was not valid."
    exit 1
  fi

  if [ "$COMMUNITY" != "$COMMUNITY_EXPECTED" ]; then
    echo "Error: Server said community is $COMMUNITY, you entered $COMMUNITY_EXPECTED, you have to fix the database."
    exit 1
  fi

  DIR="/etc/fastd/$COMMUNITY/nodes/"
  if [ ! -d "$DIR" ]; then
    echo "Error: we can't locate the folder for the keyfiles"
    exit 1
  fi

  KEY="key \"$KEY\";"

  echo $KEY > $DIR$HWID
  kill -HUP $(ps aux | grep fastd | grep $COMMUNITY | awk '{print $2}')

  echo "deploy $HWID $COMMUNITY"
fi

echo $JOBID > server-worker.last
