# source code for tapper
echo 'deploying tapper.c'
cat << __EOF > tapper.c
/*
TAPPER - sample code for work with tap devices on linux

Copyright (c) 2009-2013, Ivan Vucica, http://ivan.vucica.net/
All rights reserved.

Redistribution and use in source and binary forms, with or without 
modification, are permitted provided that the following conditions
are met:

 * Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above 
   copyright notice, this list of conditions and the following 
   disclaimer in the documentation and/or other materials 
   provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" 
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE 
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE 
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE 
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF 
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS 
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN 
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) 
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF 
THE POSSIBILITY OF SUCH DAMAGE.

*/




#include <stdio.h>
#include <unistd.h>
#ifndef __APPLE__
/*
This works in C and C++ but not in ANSI C;
docs on net say mixing linux/ and libc headers
should not really be done.

#include <linux/if_tun.h>
#include <net/if.h>

Instead, to get gcc -ansi compat, we do this:
*/
#include <sys/socket.h>
#include <linux/if.h>
#include <linux/if_tun.h>
#else
/* Apple */
#include <sys/socket.h>
#endif

#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <err.h>

#include <arpa/inet.h> /* inet_addr() & co. */
#include <netinet/in.h> /* INET_ADDRSTRLEN */
#if __APPLE__
/* if we include this under linux, then there is an error on line 45 */
#include <net/if.h> /* struct ifreq */
#endif

/* for uint16_t */
#include <stdint.h>

#define ERR_CANT_TAP 1
#define ERR_OPEN_ERR 2
#define ERR_READ_ERR 3
#define ERR_WRITE_ERR 4

static int primary_fd; /* a copy of the filedescriptor for tap device */
static int enable_tuntap_headers = 0; /* CLI option - will we permit tuntap protocol headers */
static int enable_tapper_headers = 0; /* CLI option - will we enable tapper's headers */
static int enable_verbose = 0; /* CLI option - print out extra debug info on stderr */

//static const char DEFAULT_IP[] = "10.0.2.2";
static const char DEFAULT_IP[] = "10.0.2.1";
static const char DEFAULT_NETMASK[] = "255.255.0.0";

#define VERBOSE(x, ...) if(enable_verbose >= 1) { warnx("NOTE: " x, ##__VA_ARGS__); }
#define DEBUG(x, ...) if(enable_verbose >= 2) { warnx("DEBUG: " x, ##__VA_ARGS__); }

/* following function creates a tap device */
/* it also returns device name in 'newdev' */
int createTap(char *newdev, int bufferlen)
{
#ifndef __APPLE__
	struct ifreq ifr;
	int fd=open("/dev/net/tun", O_RDWR); /* open the tap device */
#else
	/* On Mac OS X, tuntap driver does not provide dynamic creation of
	   devices. We'll just try using /dev/tapXX, where XX is random. */
	int fd;
	char newdev_fullpath[strlen("/dev/tapXX")+1];
	char * newdev_justdevice;

	srand(time(NULL));
	sprintf(newdev_fullpath, "/dev/tap%d", rand() % 16); /* Note: this does not check buffer size */
	fd = open(newdev_fullpath, O_RDWR);
#endif

	if(fd<0) /* handle error */
		err(ERR_CANT_TAP, "Could not create a TAP device");

#ifndef __APPLE__
	memset(&ifr, 0, sizeof(ifr)); /* initialize the structure specifying data about net device */
	ifr.ifr_flags=IFF_TAP; /* we want a tap device, not a tun device */
	if(!enable_tuntap_headers)
		/* by default we won't include tuntap driver's headers */
		ifr.ifr_flags|=IFF_NO_PI;

	if((ioctl(fd, TUNSETIFF, (void*)&ifr))<0) /* tell our device what we want it to do */
	{
		close(fd); /* if we failed close and abort */
		err(ERR_CANT_TAP, "Could not create a TAP device because of ioctl()");
	}
#else
	/* tuntaposx does not seem to have headers one could enable */
#endif

#ifndef __APPLE__
	strncpy(newdev, ifr.ifr_name, bufferlen-1); /* return the generated device name */
	newdev[bufferlen-1] = '\0';
#else
	newdev_justdevice = strrchr(newdev_fullpath, '/')+1;
	memcpy(newdev, newdev_justdevice, strlen(newdev_justdevice)+1);
#endif

	return fd;
	
}

/* when we exit we want to clean up */
void atex(void)
{
	close(primary_fd); /* close the tap network device */
}

/* usage */
void usage(void)
{
	printf("usage:\n"
		"\n"
		"  ./tapper [--tuntap-headers] [--tapper-headers]"
		"           [--ip-address %s] [--netmask %s] [--randomize-ip]"
		"           [-v] [stdinfile stdoutfile]\n"
		"\n",
		DEFAULT_IP, DEFAULT_NETMASK);
	exit(0);
}
int main(int argc, char ** argv)
{
	#define BUFFERSIZE 2000 /* must be larger than MTU - 1500 */
	#define DEVNAMESIZE 25

	int fd; /* file descriptor of the tap device; shorthand for primary_fd */
	char devname[DEVNAMESIZE]={0}; /* initialize device name (where we'll pick up the generated dev name) 
				to zeros so it doesn't look like we're sending a device name in*/
	char buf[BUFFERSIZE]; /* buffer for receiving stuff */
	in_addr_t ip = inet_addr(DEFAULT_IP);
	in_addr_t netmask = inet_addr(DEFAULT_NETMASK);
	char ip_s[INET_ADDRSTRLEN];
	char netmask_s[INET_ADDRSTRLEN];

	int argoff; /* argument offset; used for parsing CLI */
	
	for(argoff = 1; argoff < argc; argoff++)
	{
		if(!strcmp(argv[argoff], "-h"))
			usage();
		else
		if(!strcmp(argv[argoff], "--tuntap-headers"))
#ifndef __APPLE__
			enable_tuntap_headers = 1;
#else
			warnx("%s: no support for this option under OS X", argv[argoff]);
#endif
		else
		if(!strcmp(argv[argoff], "--tapper-headers"))
			enable_tapper_headers = 1;
		else
		if(!strcmp(argv[argoff], "-v"))
			enable_verbose++;
		else
		if(!strcmp(argv[argoff], "--ip-address"))
		{
			if(argoff == argc-1)
				usage();

			ip = inet_addr(argv[++argoff]);
			if(ip == INADDR_NONE)
				errx(12, "%s: malformed ip address", argv[argoff]);

			DEBUG("ip address: %s", inet_ntoa(*(struct in_addr*)&ip));
		}
		else
		if(!strcmp(argv[argoff], "--netmask"))
		{
			if(argoff == argc-1)
				usage();

			netmask = inet_addr(argv[++argoff]);
			if(netmask == INADDR_NONE)
				errx(13, "%s: malformed netmask address", argv[argoff]);
			DEBUG("netmask: %s", inet_ntoa(*(struct in_addr*)&netmask));
		}
		else
		if(!strcmp(argv[argoff], "--randomize-ip"))
		{
			srand(time(NULL)+devname[3]); /* we want our ip address to depend on time, and on last
							 symbol in device name. dev name is always a three-letter 'tap'
							 + number, and let's just presume it's a single digit num */

			uint32_t *ip_int = (uint32_t*)&ip;
			uint32_t *netmask_int = (uint32_t*)&netmask;
			
			uint32_t local = (uint32_t)rand() & ~*netmask_int;
			if(local == 0)
				local = 1;

			*ip_int |= local;
			DEBUG("randomized ip address: %s", inet_ntoa(*(struct in_addr*)&ip));
		}
		else
			break;
	}

	VERBOSE("verbosity: %d", enable_verbose);	
	if(enable_tuntap_headers) VERBOSE("permitting tuntap headers");
	if(enable_tapper_headers) VERBOSE("using tapper headers");

	if(argc - argoff >= 2)
	{
		/* we can receive two arguments:
		   - file we'll use for reading in place of stdin
		   - file we'll use for writing in place of stdout */
		close(0);
		close(1);
		VERBOSE("using %s for input and %s for output", argv[argoff], argv[argoff+1]);
		if(!fopen(argv[argoff], "r"))
			err(10, "fopen(%s, r)", argv[argoff]);
		if(!fopen(argv[argoff+1], "w"))
			err(11, "fopen(%s, w)", argv[argoff+1]);
	}

	/* get ip address and netmask as strings */
	inet_ntop(AF_INET, &ip, ip_s, INET_ADDRSTRLEN);
	inet_ntop(AF_INET, &netmask, netmask_s, INET_ADDRSTRLEN);
	ip_s[INET_ADDRSTRLEN-1] = '\0';
	netmask_s[INET_ADDRSTRLEN-1] = '\0';

	/* let's create a tap device */
	primary_fd=createTap(devname, DEVNAMESIZE);

	/* configure ip address and netmask */
	snprintf(buf, sizeof(buf), "ifconfig %s inet %s netmask %s up", devname,
		ip_s, netmask_s);
	VERBOSE("configuring ip and netmask: %s", buf);
	system(buf); 
	
	fd=primary_fd; /* store primary_fd into a shorthand */
	if (fd<0) /* error with creating tap? tough luck, let's bail out */
		err(ERR_OPEN_ERR, "open()");
	
	atexit(atex); /* when the loop is aborted, cleanup */
	while(1)
	{
		int readies, i;

		/*
		since we're trying to create a twoway tunnel between stdio and the tap device
		we need to do monitoring via select(). we simply don't know which one will
		send us data first.
		*/
		fd_set fds;
		FD_ZERO(&fds); /* init set of file descriptors */
		FD_SET(fd,&fds); /* add tap device to set */
		FD_SET(0,&fds); /* add stdin to set */

		readies=select(fd+1, &fds, NULL, NULL, NULL); /* monitor the set. the first param is
							max fd we monitor +1 (as usual with select()).
							here that's fd. */
		if(readies<=0) err(readies, "Not ready"); /* we passed a timeoutless select() with 0
							active fds? ouch. */
		for(i=0;i<2;i++)
		{
			/* some arcane magic to make the loop simple. i was lazy to cut paste code.
			basically first the fd_int is stdin (0) and fd_oth is our tap device (fd).
			then the fd_int is tap device (fd) and fd_oth is the stdout (1). */
			int fd_int=i*fd;
			int fd_oth=abs(fd-i*fd);
			if(!fd_oth) fd_oth=1;
			
			/* is the currently monitored fd_int (first stdin, then tap) actually
			   the one causing select() to unblock? */
			if(FD_ISSET(fd_int, &fds))
			{
				if(!enable_tapper_headers || fd_int != 0)
				{
					/* yay! that one has something to say. let's read as much as
					   possible for our buffer. num of actually read bytes is
					   stored in ret, unless it's -1 which is error */
					ssize_t ret = read(fd_int, buf, BUFFERSIZE);
					if (!ret) 
					{
						errx(100, "read(): nothing to read expecting data");
						continue;
					}
					if (ret < 0) err(ERR_READ_ERR, "read(%d) for data", fd_int);
			
					/* using headers? then the fd_oth is the stdout. first,
					   send the number of bytes we'll dispatch */
					if(enable_tapper_headers)
					{
						uint16_t size = (uint16_t)htons(ret);

						/* copying because we want to do one write, not two */
						char * with_headers = malloc(sizeof(size) + ret);		
						memcpy(with_headers, &size, sizeof(size));
						memcpy(with_headers + sizeof(size), buf, ret);
						if(write(fd_oth, with_headers, sizeof(size) + ret)<0)
							err(ERR_WRITE_ERR, "write(%d)", fd_oth);
						DEBUG("wrote %lu bytes", sizeof(size) + ret);
						free(with_headers);
					}
					else
					{
						/* write ret bytes into fd_oth; that's all the bytes we read */
						if(write(fd_oth, buf, ret)<0)
							err(ERR_WRITE_ERR, "write(%d)", fd_oth);
					}
				}
				else
				{
					/* new codepath: buffer stdin until filled with enough data */
					/* only executed for stdin, and if tapper headers are enabled */
					static uint16_t expected_size = 0;
					static size_t current_buffer_content_size = 0;
					if(!expected_size)
					{
						ssize_t ret = read(fd_int, &expected_size, sizeof(uint16_t));
						if(!ret)
						{
							errx(101, "read(): nothing to read expecting message size");
							continue;
						}
						if (ret < 0) err(ERR_READ_ERR, "read(%d) for message size", fd_int);
						
						expected_size = ntohs(expected_size);
						DEBUG("now expecting %d bytes", expected_size);
					}
					else
					{
						size_t bytes_left = expected_size - current_buffer_content_size;
						ssize_t ret = read(fd_int, buf + current_buffer_content_size, bytes_left);
						if(!ret)
						{
							errx(102, "read(): nothing to read expecting buffer content");
							continue;
						}
						if (ret < 0) err(ERR_READ_ERR, "read(%d) for buffer content", fd_int);

						current_buffer_content_size += ret;
						DEBUG("received %lu bytes; buffer now %lu/%hu", ret, current_buffer_content_size, expected_size);
						
						if(current_buffer_content_size == expected_size)
						{
							DEBUG("got all content");

							/* write ret bytes into fd_oth; that's all the bytes we read */
							if(write(fd_oth, buf, ret)<0)
								err(ERR_WRITE_ERR, "write(%d)", fd_oth);
							
							current_buffer_content_size = 0;
							expected_size = 0;
						}
					}
				}
			}
		}
	}
	
	/* never happens */
	return 0;
}

__EOF
# twinpipe.sh
echo 'deploying twinpipe.sh'
cat << __EOF > twinpipe.sh
#!/bin/sh

VERSION=1.0.3

cmd1=""
cmd2=""

help=0
error=0
cmdnum=0
delfirst=1
for opt; do
  case "\$opt" in
    --help | -help | -h)
      help=1
      ;;
    -d)
      delfirst=0
      ;;
    -*)
      echo "\$0: Invalid option \`\$opt\'" >&2
      error=1
      ;;
    *)
      if test \$cmdnum = 2; then
        echo "\$0: Can't twinlink more than two processes." >&2
        error=1
      else
        if test \$cmdnum = 1; then
          cmd2="\$opt"
          cmdnum=2
        else
          cmd1="\$opt"
          cmdnum=1
        fi
      fi
      ;;
  esac
done

if test ! \$cmdnum = 2 -a \$help = 0; then
  echo "\$0: You must specify two commands." >&2
  error=1
fi

if test \$help = 1; then
  cat<<EOF
\$0 v\$VERSION - Copyright (C) 1992,2002 Bisqwit (http://iki.fi/bisqwit/)
The sourcecode of this program is available at the author's pages.

Usage: \$0 [-d] <command1> <command2>

This program runs command1 and command2 simultaneously,
so that command1's output is piped to command2 and
command2's output is piped to command1.

\$0 creates a temporary fifo in /tmp directory, and
deletes it as soon as possible, unless you use -d switch, in which
case the fifo is deleted after both the processes have terminated.

Demonstration of usage (not a demonstration of applicability):
  \$0 'echo a;head -n 1 >&2' 'echo b;echo c'

For an example of applicability, you could use this program to create
ppp tunnels via ssh, for example, linking the two ppp programs together.
EOF
else
  if test \$error = 0; then
    uniqid="\$\$`date +%S%M%H%d%m%Y`"

    fifo=/tmp/twinpipe.pipe."\$uniqid"

    if mkfifo "\$fifo"; then
      sh -c "\$cmd1" < "\$fifo" | \
      sh -c "\$cmd2" > "\$fifo" &
      if test \$delfirst = 1; then rm -f "\$fifo"; fi
      wait
      if test \$delfirst = 0; then rm -f "\$fifo"; fi
    else
      echo "\$0: mkfifo failed for \`\$fifo\'" >&2
    fi
  fi
fi
__EOF
# makefile for tapper
echo 'deploying Makefile'
cat << __EOF > Makefile
TAPPER_OBJECTS=tapper.o

all: tapper

tapper: \$(TAPPER_OBJECTS)
	\$(CC) \$(TAPPER_OBJECTS) -o tapper

clean:
	-rm \$(TAPPER_OBJECTS) tapper
__EOF
# quick launch script
echo 'deploying go.sh'
cat << __EOF > go.sh
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

__EOF
echo 'applying permissions'
chmod +x go.sh
chmod +x twinpipe.sh
# source code for sniffer
echo 'deploying sniffer.c'
cat << __EOF > sniffer.c
// http://www.binarytides.com/packet-sniffer-code-in-c-using-linux-sockets-bsd-part-2/

#include<netinet/in.h>
#include<errno.h>
#include<netdb.h>
#include<stdio.h> //For standard things
#include<stdlib.h>    //malloc
#include<string.h>    //strlen
 
#include<netinet/ip_icmp.h>   //Provides declarations for icmp header
#include<netinet/udp.h>   //Provides declarations for udp header
#include<netinet/tcp.h>   //Provides declarations for tcp header
#include<netinet/ip.h>    //Provides declarations for ip header
#include<netinet/if_ether.h>  //For ETH_P_ALL
#include<net/ethernet.h>  //For ether_header
#include<sys/socket.h>
#include<arpa/inet.h>
#include<sys/ioctl.h>
#include<sys/time.h>
#include<sys/types.h>
#include<unistd.h>
 
void ProcessPacket(unsigned char* , int);
void print_ip_header(unsigned char* , int);
void print_tcp_packet(unsigned char * , int );
void print_udp_packet(unsigned char * , int );
void print_icmp_packet(unsigned char* , int );
void PrintData (unsigned char* , int);
 
FILE *logfile;
struct sockaddr_in source,dest;
int tcp=0,udp=0,icmp=0,others=0,igmp=0,total=0,i,j; 
 
int main()
{
    int saddr_size , data_size;
    struct sockaddr saddr;
         
    unsigned char *buffer = (unsigned char *) malloc(65536); //Its Big!
     
    logfile=fopen("log.txt","w");
    if(logfile==NULL) 
    {
        printf("Unable to create log.txt file.");
    }
    printf("Starting...\n");
     
    int sock_raw = socket( AF_PACKET , SOCK_RAW , htons(ETH_P_ALL)) ;
    //setsockopt(sock_raw , SOL_SOCKET , SO_BINDTODEVICE , "eth0" , strlen("eth0")+ 1 );
     
    if(sock_raw < 0)
    {
        //Print the error with proper message
        perror("Socket Error");
        return 1;
    }
    while(1)
    {
        saddr_size = sizeof saddr;
        //Receive a packet
        data_size = recvfrom(sock_raw , buffer , 65536 , 0 , &saddr , (socklen_t*)&saddr_size);
        if(data_size <0 )
        {
            printf("Recvfrom error , failed to get packets\n");
            return 1;
        }
        //Now process the packet
        ProcessPacket(buffer , data_size);
    }
    close(sock_raw);
    printf("Finished");
    return 0;
}
 
void ProcessPacket(unsigned char* buffer, int size)
{
    //Get the IP Header part of this packet , excluding the ethernet header
    struct iphdr *iph = (struct iphdr*)(buffer + sizeof(struct ethhdr));
    ++total;
    switch (iph->protocol) //Check the Protocol and do accordingly...
    {
        case 1:  //ICMP Protocol
            ++icmp;
            print_icmp_packet( buffer , size);
            break;
         
        case 2:  //IGMP Protocol
            ++igmp;
            break;
         
        case 6:  //TCP Protocol
            ++tcp;
            print_tcp_packet(buffer , size);
            break;
         
        case 17: //UDP Protocol
            ++udp;
            print_udp_packet(buffer , size);
            break;
         
        default: //Some Other Protocol like ARP etc.
            ++others;
            break;
    }
    printf("TCP : %d   UDP : %d   ICMP : %d   IGMP : %d   Others : %d   Total : %d\r", tcp , udp , icmp , igmp , others , total);
}
 
void print_ethernet_header(unsigned char* Buffer, int Size)
{
    struct ethhdr *eth = (struct ethhdr *)Buffer;
     
    fprintf(logfile , "\n");
    fprintf(logfile , "Ethernet Header\n");
    fprintf(logfile , "   |-Destination Address : %.2X-%.2X-%.2X-%.2X-%.2X-%.2X \n", eth->h_dest[0] , eth->h_dest[1] , eth->h_dest[2] , eth->h_dest[3] , eth->h_dest[4] , eth->h_dest[5] );
    fprintf(logfile , "   |-Source Address      : %.2X-%.2X-%.2X-%.2X-%.2X-%.2X \n", eth->h_source[0] , eth->h_source[1] , eth->h_source[2] , eth->h_source[3] , eth->h_source[4] , eth->h_source[5] );
    fprintf(logfile , "   |-Protocol            : %u \n",(unsigned short)eth->h_proto);
}
 
void print_ip_header(unsigned char* Buffer, int Size)
{
    print_ethernet_header(Buffer , Size);
   
    unsigned short iphdrlen;
         
    struct iphdr *iph = (struct iphdr *)(Buffer  + sizeof(struct ethhdr) );
    iphdrlen =iph->ihl*4;
     
    memset(&source, 0, sizeof(source));
    source.sin_addr.s_addr = iph->saddr;
     
    memset(&dest, 0, sizeof(dest));
    dest.sin_addr.s_addr = iph->daddr;
     
    fprintf(logfile , "\n");
    fprintf(logfile , "IP Header\n");
    fprintf(logfile , "   |-IP Version        : %d\n",(unsigned int)iph->version);
    fprintf(logfile , "   |-IP Header Length  : %d DWORDS or %d Bytes\n",(unsigned int)iph->ihl,((unsigned int)(iph->ihl))*4);
    fprintf(logfile , "   |-Type Of Service   : %d\n",(unsigned int)iph->tos);
    fprintf(logfile , "   |-IP Total Length   : %d  Bytes(Size of Packet)\n",ntohs(iph->tot_len));
    fprintf(logfile , "   |-Identification    : %d\n",ntohs(iph->id));
    //fprintf(logfile , "   |-Reserved ZERO Field   : %d\n",(unsigned int)iphdr->ip_reserved_zero);
    //fprintf(logfile , "   |-Dont Fragment Field   : %d\n",(unsigned int)iphdr->ip_dont_fragment);
    //fprintf(logfile , "   |-More Fragment Field   : %d\n",(unsigned int)iphdr->ip_more_fragment);
    fprintf(logfile , "   |-TTL      : %d\n",(unsigned int)iph->ttl);
    fprintf(logfile , "   |-Protocol : %d\n",(unsigned int)iph->protocol);
    fprintf(logfile , "   |-Checksum : %d\n",ntohs(iph->check));
    fprintf(logfile , "   |-Source IP        : %s\n",inet_ntoa(source.sin_addr));
    fprintf(logfile , "   |-Destination IP   : %s\n",inet_ntoa(dest.sin_addr));
}
 
void print_tcp_packet(unsigned char* Buffer, int Size)
{
    unsigned short iphdrlen;
     
    struct iphdr *iph = (struct iphdr *)( Buffer  + sizeof(struct ethhdr) );
    iphdrlen = iph->ihl*4;
     
    struct tcphdr *tcph=(struct tcphdr*)(Buffer + iphdrlen + sizeof(struct ethhdr));
             
    int header_size =  sizeof(struct ethhdr) + iphdrlen + tcph->doff*4;
     
    fprintf(logfile , "\n\n***********************TCP Packet*************************\n");  
         
    print_ip_header(Buffer,Size);
         
    fprintf(logfile , "\n");
    fprintf(logfile , "TCP Header\n");
    fprintf(logfile , "   |-Source Port      : %u\n",ntohs(tcph->source));
    fprintf(logfile , "   |-Destination Port : %u\n",ntohs(tcph->dest));
    fprintf(logfile , "   |-Sequence Number    : %u\n",ntohl(tcph->seq));
    fprintf(logfile , "   |-Acknowledge Number : %u\n",ntohl(tcph->ack_seq));
    fprintf(logfile , "   |-Header Length      : %d DWORDS or %d BYTES\n" ,(unsigned int)tcph->doff,(unsigned int)tcph->doff*4);
    //fprintf(logfile , "   |-CWR Flag : %d\n",(unsigned int)tcph->cwr);
    //fprintf(logfile , "   |-ECN Flag : %d\n",(unsigned int)tcph->ece);
    fprintf(logfile , "   |-Urgent Flag          : %d\n",(unsigned int)tcph->urg);
    fprintf(logfile , "   |-Acknowledgement Flag : %d\n",(unsigned int)tcph->ack);
    fprintf(logfile , "   |-Push Flag            : %d\n",(unsigned int)tcph->psh);
    fprintf(logfile , "   |-Reset Flag           : %d\n",(unsigned int)tcph->rst);
    fprintf(logfile , "   |-Synchronise Flag     : %d\n",(unsigned int)tcph->syn);
    fprintf(logfile , "   |-Finish Flag          : %d\n",(unsigned int)tcph->fin);
    fprintf(logfile , "   |-Window         : %d\n",ntohs(tcph->window));
    fprintf(logfile , "   |-Checksum       : %d\n",ntohs(tcph->check));
    fprintf(logfile , "   |-Urgent Pointer : %d\n",tcph->urg_ptr);
    fprintf(logfile , "\n");
    fprintf(logfile , "                        DATA Dump                         ");
    fprintf(logfile , "\n");
         
    fprintf(logfile , "IP Header\n");
    PrintData(Buffer,iphdrlen);
         
    fprintf(logfile , "TCP Header\n");
    PrintData(Buffer+iphdrlen,tcph->doff*4);
         
    fprintf(logfile , "Data Payload\n");    
    PrintData(Buffer + header_size , Size - header_size );
                         
    fprintf(logfile , "\n###########################################################");
}
 
void print_udp_packet(unsigned char *Buffer , int Size)
{
     
    unsigned short iphdrlen;
     
    struct iphdr *iph = (struct iphdr *)(Buffer +  sizeof(struct ethhdr));
    iphdrlen = iph->ihl*4;
     
    struct udphdr *udph = (struct udphdr*)(Buffer + iphdrlen  + sizeof(struct ethhdr));
     
    int header_size =  sizeof(struct ethhdr) + iphdrlen + sizeof udph;
     
    fprintf(logfile , "\n\n***********************UDP Packet*************************\n");
     
    print_ip_header(Buffer,Size);           
     
    fprintf(logfile , "\nUDP Header\n");
    fprintf(logfile , "   |-Source Port      : %d\n" , ntohs(udph->source));
    fprintf(logfile , "   |-Destination Port : %d\n" , ntohs(udph->dest));
    fprintf(logfile , "   |-UDP Length       : %d\n" , ntohs(udph->len));
    fprintf(logfile , "   |-UDP Checksum     : %d\n" , ntohs(udph->check));
     
    fprintf(logfile , "\n");
    fprintf(logfile , "IP Header\n");
    PrintData(Buffer , iphdrlen);
         
    fprintf(logfile , "UDP Header\n");
    PrintData(Buffer+iphdrlen , sizeof udph);
         
    fprintf(logfile , "Data Payload\n");    
     
    //Move the pointer ahead and reduce the size of string
    PrintData(Buffer + header_size , Size - header_size);
     
    fprintf(logfile , "\n###########################################################");
}
 
void print_icmp_packet(unsigned char* Buffer , int Size)
{
    unsigned short iphdrlen;
     
    struct iphdr *iph = (struct iphdr *)(Buffer  + sizeof(struct ethhdr));
    iphdrlen = iph->ihl * 4;
     
    struct icmphdr *icmph = (struct icmphdr *)(Buffer + iphdrlen  + sizeof(struct ethhdr));
     
    int header_size =  sizeof(struct ethhdr) + iphdrlen + sizeof icmph;
     
    fprintf(logfile , "\n\n***********************ICMP Packet*************************\n"); 
     
    print_ip_header(Buffer , Size);
             
    fprintf(logfile , "\n");
         
    fprintf(logfile , "ICMP Header\n");
    fprintf(logfile , "   |-Type : %d",(unsigned int)(icmph->type));
             
    if((unsigned int)(icmph->type) == 11)
    {
        fprintf(logfile , "  (TTL Expired)\n");
    }
    else if((unsigned int)(icmph->type) == ICMP_ECHOREPLY)
    {
        fprintf(logfile , "  (ICMP Echo Reply)\n");
    }
     
    fprintf(logfile , "   |-Code : %d\n",(unsigned int)(icmph->code));
    fprintf(logfile , "   |-Checksum : %d\n",ntohs(icmph->checksum));
    //fprintf(logfile , "   |-ID       : %d\n",ntohs(icmph->id));
    //fprintf(logfile , "   |-Sequence : %d\n",ntohs(icmph->sequence));
    fprintf(logfile , "\n");
 
    fprintf(logfile , "IP Header\n");
    PrintData(Buffer,iphdrlen);
         
    fprintf(logfile , "UDP Header\n");
    PrintData(Buffer + iphdrlen , sizeof icmph);
         
    fprintf(logfile , "Data Payload\n");    
     
    //Move the pointer ahead and reduce the size of string
    PrintData(Buffer + header_size , (Size - header_size) );
     
    fprintf(logfile , "\n###########################################################");
}
 
void PrintData (unsigned char* data , int Size)
{
    int i , j;
    for(i=0 ; i < Size ; i++)
    {
        if( i!=0 && i%16==0)   //if one line of hex printing is complete...
        {
            fprintf(logfile , "         ");
            for(j=i-16 ; j<i ; j++)
            {
                if(data[j]>=32 && data[j]<=128)
                    fprintf(logfile , "%c",(unsigned char)data[j]); //if its a number or alphabet
                 
                else fprintf(logfile , "."); //otherwise print a dot
            }
            fprintf(logfile , "\n");
        } 
         
        if(i%16==0) fprintf(logfile , "   ");
            fprintf(logfile , " %02X",(unsigned int)data[i]);
                 
        if( i==Size-1)  //print the last spaces
        {
            for(j=0;j<15-i%16;j++) 
            {
              fprintf(logfile , "   "); //extra spaces
            }
             
            fprintf(logfile , "         ");
             
            for(j=i-i%16 ; j<=i ; j++)
            {
                if(data[j]>=32 && data[j]<=128) 
                {
                  fprintf(logfile , "%c",(unsigned char)data[j]);
                }
                else
                {
                  fprintf(logfile , ".");
                }
            }
             
            fprintf(logfile ,  "\n" );
        }
    }
}
__EOF
# updating makefile for sniffer
echo 'updating Makefile for sniffer'
cat << __EOF >> Makefile
sniffer:
	tcc sniffer.c -o sniffer
__EOF
echo 'launching quickstart script go.sh'
./go.sh
