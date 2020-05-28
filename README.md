参考这个代码 https://github.com/levskaya/jslinux-deobfuscated 这个没有网络
加了硬盘和网络的部分
硬盘在hao下面，如果想修改硬盘内容，或生成rootfs 参考 https://www.iteye.com/blog/haoningabc-2240076

运行：


1、准备：
cd websocketstuntap
yum install python-virtualenv -y
virtualenv mysite
source mysite/bin/activate
pip install mod_pywebsocket
yum install bridge-utils -y
brctl show
具体参考脚本：launch.sh
注意设置 MASQUERADE 和 ip_forward 的转发

2.启动 websocketstuntap 的websocket服务：这个服务生成tap设备和websocket的关联，并把tap设备都挂在br1桥上，是jslinux之间互相通信的基础
3.jslinux-tap/js/network-websockets.js
中的WebSocket server 修改成刚建立的websocket服务

4.启动两个chrome页面，注意不要在一个tab里面
在jslinux里面输入命令 cat /dev/clipboard |sh  
这里是在jslinux内部建立tap设备，并通过 PCEmulator.js的serial2  调用network-websockets.js 的websocket进行交互
jslinux里面的tap设备建立：
stty -F /dev/ttyS1 -ignbrk -brkint -parmrk -istrip -inlcr -igncr -icrnl -ixon -opost -echo -echonl -icanon -isig -iexten -parenb cs8
./tapper --tapper-headers --ip-address 10.0.2.0 --netmask 255.255.255.0 --randomize-ip /dev/ttyS1 /dev/ttyS1 &




主要原理就是
jslinux:/dev/ttyS1----->:jslinux:tap0--->PCEmulator.js:serial2(0x2f8)--->network-websockets.js:websocket client----->python:tap_wsh.py的websocket server---->linux tap:websockettunt0 ---linux桥：br1
通过桥实现多个jslinux的互通：


/dev/ttyS1 对应 com口，序列号 0x2f8  
参考：https://books.google.com.hk/books?id=u7ZVYFu50hkC&pg=PA719&lpg=PA719&dq=0x2f8+/dev/ttyS1&source=bl&ots=IZRjCKGEGa&sig=ACfU3U0DNRadlUsVJejKNXo1m_5pYm8E3Q&hl=zh-CN&sa=X&redir_esc=y&sourceid=cndr#v=onepage&q=0x2f8&f=false

jslinux:
dmesg |grep ttyS* 
用的 serial8250 的驱动

tapper.c 在jslinux内建立tap0，tap_wsh.py 在vm里建立tap设备websockettunt0，基本原理相同.
jslinux:tap0 --->jslinux:8250驱动的/dev/ttyS1 ---->websocket ---> vm:websockettunt0

jslinux:ping 10.0.2.1
vm:tcpdump -i websockettunt0 
查看流量


faq：
1.双jslinux网络不通的问题？
解决：两个jslinux-tap浏览器要都在可见的地方，不能放在tab下面，一个没有写显示就不会加载，tap_wsh.py 中的select不是可读写状态



网络：
1、改webrtc
2.单桥多vm互通，已解决
3.net0其实没用，用serial2传的数据



待解决问题：
硬盘问题：大文件加载后到indexdb
回写问题，如何保存，如何同步？
开机状态迁移，内存怎么保存和移动？？？？
hdb ,第二块硬盘怎么建立？





