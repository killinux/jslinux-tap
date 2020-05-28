Websockets TUN/TAP
==================

This pywebsocket request handler allows Javascript software to establish
ethernet connectivity to the server through a service exposing the TAP
device via Websockets.

Useful for 'certain emulators'.

Note: this is not of production quality, and is almost certainly a
security risk. Think hard before running this without authentication or
thinking multiple times whether you want the server you run this on to be
VPNed to. While intended for Javascript, remember that anyone could connect
to this service even without Javascript.

(c) 2013 Ivan Vucica

apt-get  install python-virtualenv  
virtualenv mysite 
cd mysite/  
source bin/activate  
echo $VIRTUAL_ENV  
echo $PATH
pip install mod_pywebsocket 

python -m mod_pywebsocket.standalone -d . --log-level=info -p 3000


注意个问题：
chrome不要用两个tab页，否则ping不通
应为只有使用的tab页面才是可操作的
把chrome分两个，两个jslinux都是可见状态才能ping通
