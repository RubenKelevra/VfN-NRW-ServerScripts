#!/bin/bash

mv server-worker.sh server-worker.sh.bak
mv update_server-worker.sh update_server-worker.sh.bak

wget https://raw.githubusercontent.com/FF-NRW/ServerScripts/master/server-worker.sh
wget https://raw.githubusercontent.com/FF-NRW/ServerScripts/master/update_server-worker.sh

chmod +x server-worker.sh
chmod +x update_server-worker.sh
