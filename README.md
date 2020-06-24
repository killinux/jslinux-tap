本文代码在：[https://github.com/killinux/jslinux-tap](https://github.com/killinux/jslinux-tap)
测试demo在：[http://www.hackernel.com/jslinux/](http://www.hackernel.com/jslinux/)
![带网络的jslinux](https://img-blog.csdnimg.cn/20200624031118211.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L2xlYWZyZW5jaGxlYWY=,size_16,color_FFFFFF,t_70#pic_center)

11年很火的jslinux，把linux跑在浏览器上，10年过去了，还有人记得这个么？
这个代码参考了大神fabrice bellard的代码，版权归作者所有。
官网是： [https://bellard.org/jslinux](https://bellard.org/jslinux) 这个已经变成wasm的版本，所以目前这个纯js版的作为学习Linux内核的教程还是很好的。
没混淆的jslinux参考： [https://github.com/levskaya/jslinux-deobfuscated](https://github.com/levskaya/jslinux-deobfuscated)
 这个没有网络，但是代码可读。
 
 
**我修改了哪些**：
1.增加了硬盘部分
硬盘在hao下面，如果想修改硬盘内容，或生成rootfs 参考 [https://www.iteye.com/blog/haoningabc-2240076](https://www.iteye.com/blog/haoningabc-2240076)
2.增加了网络部分：通过websocket作为server，浏览器中linux的tap设备与服务器端通信


**把代码运行起来**：

运行方法：
**1、安装依赖**，mod_pywebsocket 和bridge-utils：
```shell
cd jslinux/websocketstuntap
yum install python-virtualenv -y
virtualenv mysite
source mysite/bin/activate
pip install mod_pywebsocket
yum install bridge-utils -y
brctl show
```
具体参考脚本：launch.sh
注意设置 MASQUERADE 和 ip_forward=1 的转发，否则网络可能会不通

**2.启动 websocketstuntap 的websocket服务**：这个服务生成tap设备和websocket的关联，并把tap设备都挂在br1桥上，是jslinux之间互相通信的基础
```shell
brctl addbr br1
brctl stp br1 on
ip link set br1 promisc on
ip link set br1 up
ifconfig br1 hw ether ee:ee:ee:ee:ee:50
```
需要指定mac地址，否则每次新建tap这个mac会变成最新的，影响网络交互
```shell
ifconfig br1 10.0.2.1 netmask 255.0.0.0 up
```
**3.修改websocket客户端**
代码在：jslinux-tap/js/network-websockets.js
中的WebSocket server 修改成刚建立的websocket服务

**4.启动两个chrome页面**，注意不要在一个tab里面
在jslinux里面输入命令 cat /dev/clipboard |sh  
这里是在jslinux内部建立tap设备，并通过 PCEmulator.js的serial2  调用network-websockets.js 的websocket进行交互
jslinux里面的tap设备建立：
```shell
stty -F /dev/ttyS1 -ignbrk -brkint -parmrk -istrip -inlcr -igncr -icrnl -ixon -opost -echo -echonl -icanon -isig -iexten -parenb cs8
./tapper --tapper-headers --ip-address 10.0.2.0 --netmask 255.255.255.0 --randomize-ip /dev/ttyS1 /dev/ttyS1 &
```


**主要原理是**
jslinux:/dev/ttyS1----->:jslinux:tap0--->PCEmulator.js:serial2(0x2f8)--->network-websockets.js:websocket client----->python:tap_wsh.py的websocket server---->linux tap:websockettunt0 ---linux桥：br1
通过桥实现多个jslinux的互通：


/dev/ttyS1 对应 com口，序列号 0x2f8  
参考：[google定义的设备号](https://books.google.com.hk/books?id=u7ZVYFu50hkC&pg=PA719&lpg=PA719&dq=0x2f8%20/dev/ttyS1&source=bl&ots=IZRjCKGEGa&sig=ACfU3U0DNRadlUsVJejKNXo1m_5pYm8E3Q&hl=zh-CN&sa=X&redir_esc=y&sourceid=cndr#v=onepage&q=0x2f8&f=false)

jslinux:
dmesg |grep ttyS* 
用的 serial8250 的驱动

tapper.c 在jslinux内建立tap0，tap_wsh.py 在vm里建立tap设备websockettunt0，基本原理相同.
jslinux:tap0 --->jslinux:8250驱动的/dev/ttyS1 ---->websocket ---> vm:websockettunt0

jslinux:ping 10.0.2.1
vm:tcpdump -i websockettunt0 
查看流量


**faq：**
1.双jslinux网络不通的问题？  
答：两个jslinux-tap浏览器要都在可见的地方，不能放在tab下面，一个没有写显示就不会加载，tap_wsh.py 中的select不是可读写状态  
2. 服务端的代码在哪？
答：jslinux-tap/websocketstuntap的下面，使用的mod_pywebsocket  



**其他可能的想法和todo：**  
1、改成webrtc的版本，未实现。 
2、单桥多vm互通，已解决  
3、net0其实没用，用serial2传的数据  
4、硬盘问题：大文件加载后到indexdb  
5、回写问题，如何保存，如何同步？  
6、开机状态迁移，内存怎么保存和移动？ 
7、hdb ,第二块硬盘怎么建立？  
8、建立的tap设备，在websocket断掉后怎么自动清除 


**其他说明:**

1.内核建立tap设备通过websocket与底层连接,传输2层协议，  
2.底层python的服务端使用vxlan与openvswitch可以支持集群。   
3.页面network status显示网络状态，红色网络异常，请刷新页面，
4.chrome的开发者工具可以查看2层协议.    

**测试方式**：  
在命令行输入：    
ifconfig    
如果手动建立tap设备  
```shell
cat /dev/clipboard |sh  
```
建立tap设备与websocket通信 
测试网关  
```shell
ifconfig  
ping 10.0.2.1  
```
测试dns  
ping 8.8.8.8  

ping www.baidu.com

