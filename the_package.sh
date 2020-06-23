# source code for tapper
echo 'deploying tapper.c'
cat << __EOF > tapper.c

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
# updating makefile for sniffer
echo 'launching quickstart script go.sh'
./go.sh
