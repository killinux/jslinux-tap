#!/bin/bash

# Obtain and install mod_pywebsocket from:
#  https://code.google.com/p/pywebsocket/

#sudo python -m mod_pywebsocket.standalone -d . --log-level=info -p 3000
#tcpdump -i eth0 -e -v -l
#tcpdump -i eth0 -e -v -l -w a.pcap

#echo 1 >/proc/sys/net/ipv4/ip_forward  
#yum install bridge-utils
#brctl addbr br1
#brctl stp br1 on
#ip link set br1 promisc on 
#ip link set br1 up
#ifconfig br1 hw ether ee:ee:ee:ee:ee:50
#if not ifconfig hw ,the ip of br1 will autochange with the ip of tapX
#ifconfig br1 10.0.2.1 netmask 255.0.0.0 up
#
#dnsmasq --strict-order --except-interface=lo --interface=br1 --listen-address=10.0.2.1 --bind-interfaces  --dhcp-range=10.0.2.100,10.0.2.254 --conf-file=""  --pid-file=/var/run/qemu-dhcp-br1.pid  --dhcp-leasefile=/var/run/qemu-dhcp-br1.leases --dhcp-no-override
#
#iptables -t nat -A POSTROUTING -s "10.0.2.0/255.255.255.0" ! -d "10.0.2.0/255.255.255.0" -j MASQUERADE 

#virtualenv mysite
#source mysite/bin/activate
#pip install mod_pywebsocket
#kill `pidof python`
#source /opt/qemu/deobfuscated/websocketstuntap/mysite/bin/activate
python -m mod_pywebsocket.standalone -d . --log-level=info -p 3000
