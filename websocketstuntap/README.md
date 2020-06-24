Websockets TUN/TAP
==================
```shell
apt-get  install python-virtualenv  
virtualenv mysite 
cd mysite/  
source bin/activate  
echo $VIRTUAL_ENV  
echo $PATH
pip install mod_pywebsocket 

python -m mod_pywebsocket.standalone -d . --log-level=info -p 3000
```

注意个问题：
chrome不要用两个tab页，否则ping不通
应为只有使用的tab页面才是可操作的
把chrome分两个，两个jslinux都是可见状态才能ping通
