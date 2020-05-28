CC=tcc make

echo 'configuring ttyS1'
stty -F /dev/ttyS1 -ignbrk -brkint -parmrk -istrip -inlcr -igncr -icrnl -ixon -opost -echo -echonl -icanon -isig -iexten -parenb cs8

echo 'launching tapper'
./tapper --tapper-headers --ip-address 10.0.2.0 --netmask 255.255.255.0 --randomize-ip /dev/ttyS1 /dev/ttyS1 &

echo 'sleeping 1sec'
sleep 1

echo 'adding dns nameserver'
rm -rf /var/root/etc
umount /etc
cp -R /etc/ /var/root/etc
mount -o bind /var/root/etc /etc/
echo nameserver 8.8.8.8 > /var/root/etc/resolv.conf

echo 'enabling passwordless root login'
sed -i 's/^root:x:/root::/' /var/root/etc/passwd

#echo 'routing through 10.0.2.1'
echo 'routing through 10.0.2.1'
route add default gw 10.0.2.1

echo 'symlinking telnetd and httpd'
ln -s /bin/busybox telnetd
ln -s /bin/busybox httpd

echo 'making httpd home'
mkdir /var/www
echo 'This is an embedded system!' > /var/www/index.html

echo 'launching telnetd and httpd'
./telnetd
./httpd -h /var/www

echo ''
echo 'this is your tap0 configuration:'
echo ''
ifconfig tap0
