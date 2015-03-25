HostIP="$1"

if [ -z "$HostIP" ]; then
    echo "no ip provided"; exit 1
fi

ping6 -q $HostIP -c 4 -W 5 >/dev/null 2>&1

if [ $? -ne 0 ]; then
    echo "Host $HostIP not reachable via ping."; exit 1
fi

echo "Host is reachable, SSH to query router-type..."
Filename=`ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ServerAliveInterval=2 -o ServerAliveCountMax=5 -o ConnectTimeout=4 root@$HostIP "uci get freifunk.fw.filename"`

if [ -z "$Filename" ]; then
    echo "Error while fetching filename"; exit 1
fi

if [ ! -f "images/$Filename" ]; then
    echo "File to update host $HostIP was not found."; exit 1
fi

echo "Uploading image..."

scp "images/$Filename" root@[$HostIP]:/tmp >/dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "Upload completed, updating..."
else
    echo "Upload failed."; exit 1
fi

ssh -o ServerAliveInterval=2 -o ServerAliveCountMax=5 -o ConnectTimeout=4 root@$HostIP "sysupgrade -n /tmp/$Filename"

if [ $? -eq 0 ]; then
    echo "update successfully initiated."
else
    echo "update initiation failed."
    exit 1
fi

