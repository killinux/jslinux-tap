
测试demo在：[http://www.hackernel.com/jslinux/](http://www.hackernel.com/jslinux/)    
本文代码在：[https://github.com/killinux/jslinux-tap](https://github.com/killinux/jslinux-tap)  
![带网络的jslinux](https://img-blog.csdnimg.cn/20200624031118211.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L2xlYWZyZW5jaGxlYWY=,size_16,color_FFFFFF,t_70#pic_center)

2011年很火的jslinux，把linux跑在浏览器上，10年过去了，还有人记得这个么？

fabrice bellard官网是： [https://bellard.org/jslinux](https://bellard.org/jslinux) 这个已经变成wasm的版本，代码不可读，所以目前这个纯js版的作为学习Linux内核的教程还是很好的。  
没混淆的jslinux参考： [https://github.com/levskaya/jslinux-deobfuscated](https://github.com/levskaya/jslinux-deobfuscated)
 这个没有网络，硬盘也没这么大，但是代码可读。 
 
 
**我修改了哪些**：  
1.**增加了硬盘部分**：  
硬盘在hao下面，如果想修改硬盘内容，或生成rootfs 参考 [修改jslinux硬盘内容](https://www.iteye.com/blog/haoningabc-2240076)  
理论上如果用indexeddb作为硬盘，硬盘应该可以更大，后续计划把browserfs加上。  
2.**增加了网络部分**：通过websocket作为server，浏览器中linux的tap设备与服务器端通信，这个地方需要改内核编译的配置，内核的config选项一定要把TUN=yes  
<pre>
网络为三个部分：  
      （1）jslinux内部网络是建立tap设备，和/dev/ttyS1设备交互，这是jslinux和浏览器交互的部分  ，类似/dev/clipboard 和浏览器上的textare交互  ,建立tap设备的代码为 [tap代码链接](https://www.iteye.com/blog/haoningabc-2436305)
      （2）浏览器和server用websocket链接    
      （3）server端linux也是同样原理，建立一个桥，tap设备一端绑在桥上，一端连在websocket上  
 </pre>


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
```shell
jslinux:/dev/ttyS1
  ----->
    jslinux:tap0
      ----->
        PCEmulator.js:serial2(0x2f8)
          ----->
             network-websockets.js:websocket client
               ----->
                 python:tap_wsh.py:websocket server
                   ----->
                     linux tap:websockettunt0 
                       ----->
                         linux桥：br1
通过桥实现多个jslinux的互通：
```


/dev/ttyS1 对应 com口，序列号 0x2f8  
参考：[google定义的设备号](https://books.google.com.hk/books?id=u7ZVYFu50hkC&pg=PA719&lpg=PA719&dq=0x2f8%20/dev/ttyS1&source=bl&ots=IZRjCKGEGa&sig=ACfU3U0DNRadlUsVJejKNXo1m_5pYm8E3Q&hl=zh-CN&sa=X&redir_esc=y&sourceid=cndr#v=onepage&q=0x2f8&f=false)

jslinux 网络驱动：  
dmesg |grep ttyS* 
用的 serial8250 的驱动,这个驱动比较原始，尝试过用e1000的驱动也可以使用，参考[jslinux带网络功能的内核](https://www.iteye.com/blog/haoningabc-2338061)  

tapper.c 在jslinux内建立tap0，tap_wsh.py 在vm里建立tap设备websockettunt0，基本原理相同.  
```shell
jslinux:tap0
      --->jslinux:8250驱动的/dev/ttyS1 -
         --->websocket
              ---> vm:websockettunt0
```

在jslinux中:   ping 10.0.2.1  
在server中：tcpdump -i websockettunt0   查看流量  


**FAQ：**    
**1.双jslinux网络不通的问题**？  
答：两个jslinux-tap浏览器要都在可见的地方，不能放在tab下面，一个没有写显示就不会加载，tap_wsh.py 中的select不是可读写状态  
**2. 服务端的代码在哪**？
答：jslinux-tap/websocketstuntap的下面，使用的mod_pywebsocket  
**3.jslinux里面怎么和浏览器交互**： 
答：通过textarea，这部分需要内核驱动支持，
代码在[https://github.com/killinux/jslinux-kernel/](https://github.com/killinux/jslinux-kernel/) 的src/patch_linux-2.6.20里，定义了jsclipboard这个设备，对应在jslinux里的/dev/clipboard
想把内容从jslinux传到浏览器的textarea就使用
```shell
echo "haha" >/dev/clipboard
```
如果想从浏览器传到jslinux里，
在textarea修改内容后 ，
```shell
cat /dev/clipboard
```
jslinux里面的网络设备就是通过这个建立的
```shell
cat /dev/clipboard |sh
```
**4.如果我想重新编译内核这么办**：
答：具体参考 [https://www.iteye.com/blog/haoningabc-2338061](https://www.iteye.com/blog/haoningabc-2338061)
目前用2.6.20内核需要一些补丁，补丁的代码在代码在 [https://github.com/killinux/jslinux-kernel](https://github.com/killinux/jslinux-kernel)  
注意linuxstart.bin 和vmlinux-2.6.20.bin要一起重新编译，linuxstart里面定义了从第几字节开始加载内核
**5.如果想重新制作硬盘怎么办**：  
答：
1.把散落的硬盘文件合并成一个,并挂在到本地系统  
```shell
cd jslinux-tap/hao
cat hda000000*.bin > hda.bin  
mount -t ext2 -o loop hda.bin /mnt/jshda  
cp -r /mnt/jshda jslinux 
```
2.在/mnt/jshda里面修改jslinux硬盘内的文件  
3.再把修改过的硬盘拆分成小块给jslinux使用
```shell
split -a 9 -d -b 65536 hda.bin hda      
for f in hda000000*; do      
    mv $f $f.bin      
done 
```
这里拆成较快是为了加快浏览器读取硬盘的速度，
具体读取代码在jslinux-tap/jslinux.js里面
```javascript
params.hda = { url: "hao/hda%d.bin", block_size: 64, nb_blocks: 912 };
```



**其他可能的想法和todo：**  
1、改成webrtc的版本，未实现
2、单桥多vm互通，已解决  
3、net0其实没用，用serial2传的数据,需要单独编译网络驱动，验证通过。
4、硬盘问题：大文件加载后到indexdb  ，计划减少第二次加载时间
5、线上修改之后如何保存到本地，回写问题，如何保存，如何同步？ 
6、开机状态迁移，内存怎么保存和移动？ 
7、hdb ,第二块硬盘怎么建立？  
8、server端建立的tap设备，在websocket断掉后怎么自动清除 
9、后续支持ssh协议


**其他说明:**

1.内核建立tap设备通过websocket与底层连接,传输层协议   
2.底层python的服务端使用vxlan与openvswitch可以支持集群。   
3.页面network status显示网络状态，红色网络异常，请刷新页面  
4.chrome的开发者工具可以查看传输层协议 

**测试方式**：  
在命令行输入：  
```shell 
ifconfig  
```
如果没有手网络设备，动建立tap设备  
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
```shell
ping 8.8.8.8  

ping www.baidu.com
```
理论上两个chrome浏览器可以用jslinux互相ping通
