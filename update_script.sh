HostIP="$1"

if [ -z "$HostIP" ]; then
    echo "no ip provided"; exit 1
fi

ping6 -q $HostIP -c 4 -W 5 >/dev/null 2>&1

if [ $? -ne 0 ]; then
    echo "Host $HostIP not reachable via ping."; exit 1
fi

if [ -f "images/build" ]; then
    newver=`cat images/build`
    [ -z "$newver" ] && exit 1
fi

echo "Host is reachable, getting installed version..."
oldver=`ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ServerAliveInterval=2 -o ServerAliveCountMax=5 -o ConnectTimeout=4 root@$HostIP "cat /build"`

if [ -z "$oldver" ]; then
    echo "I can't connect or determine the installed version, exiting"
    exit 1
elif [ "$oldver" == "$newver" ]; then
    echo "This version ($newver) has already been deployed on node $HostIP"
    exit 0
fi

echo "getting router-type..."
Filename=`ssh -o ServerAliveInterval=2 -o ServerAliveCountMax=5 -o ConnectTimeout=4 root@$HostIP "uci get freifunk.fw.filename"`

if [ -z "$Filename" ]; then
    echo "Error while fetching filename"; exit 1
fi

if [ ! -f "images/$Filename" ]; then
    echo "File to update host $HostIP was not found."; exit 1
fi

echo "Uploading image..."

scp "images/$Filename" root@[$HostIP]:/tmp >/dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "Upload completed, checking file..."
else
    echo "Upload failed."; exit 1
fi

#FIXME replace md5sum with something better.
echo "Generating local checksum..."
localsum=`md5sum "images/$Filename" | awk '{print $1}'`
echo "Generating remote checksum..."
remotesum=`ssh -o ServerAliveInterval=2 -o ServerAliveCountMax=5 -o ConnectTimeout=4 root@$HostIP "md5sum /tmp/$Filename" | awk '{print $1}'`

if [ "$localsum" == "$remotesum" ]; then
    echo "Checksum valid, updating..."
    ssh -o ServerAliveInterval=2 -o ServerAliveCountMax=5 -o ConnectTimeout=4 root@$HostIP "sysupgrade -n /tmp/$Filename"
else
    echo "transfered has not the valid md5-sum"
fi

