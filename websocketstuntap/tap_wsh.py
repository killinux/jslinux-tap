import sys, os, struct, select
import base64
netBufferExpected = 0
def web_socket_do_extra_handshake(request):
    """Received Sec-WebSocket-Extensions header value is parsed into
    request.ws_requested_extensions. pywebsocket creates extension
    processors using it before do_extra_handshake call and never looks at it
    after the call.
    To reject requested extensions, clear the processor list.
    """
    # for easier debugging:
    request.ws_extension_processors = []

def web_socket_transfer_data(request):
    print("web_socket_transfer_data--->");
    """Echo. Same as echo_wsh.py."""
    #global tuntapFD
    tuntapFD, x, y = setupTUNTAP()
    # FIXME according to this post from 2010:
    #   https://groups.google.com/forum/#!topic/pywebsocket/MY6HoG4KRCA
    # this method for fetching requestFD only works for standalone server
    requestFD = request.connection._request_handler.rfile._sock.fileno()
    print("requestFD:"+str(requestFD))
    print("tuntapFD:"+str(tuntapFD))
    socketlist = {
        requestFD:'websocket',
        #sys.stdin:'stdio',
        tuntapFD: 'tuntap'
    }
    netBuffer = ""
    while True:
        inputSockets = socketlist.keys()
        #print("inputSockets length:"+ str(len(inputSockets)))
        #print("inputSockets :"+ str(inputSockets))
        outputSockets = []
        errorSockets = []
        (inputReady, outputReady, errorOccurred) = select.select(inputSockets, outputSockets, errorSockets, 1)
        for each in inputReady:
            if socketlist[each] == 'websocket':
                netBuffer = process_requestFD(request, netBuffer,tuntapFD)
            elif socketlist[each] == 'tuntap':
                output = os.read(tuntapFD, 8192)
                output = struct.pack('!H', len(output)) + output # network byte order short is "tapper"'s header
                request.ws_stream.send_message(output, binary=True)
 
def process_requestFD(request, netBuffer,tuntapFD):
    global netBufferExpected
    message = request.ws_stream.receive_message()
    if message is None:
        return netBuffer
    if isinstance(message, unicode):
        # text message - ignore it
        incomingData = base64.decodestring(message)
        pass
    else:
        incomingData = message #base64.decodestring(aNode.getCDATA())
    if 1: # temp
        netBuffer += incomingData
        while len(netBuffer) >= netBufferExpected:
            if len(netBuffer) > 0 and netBufferExpected > 0:
                print " GOT ALL DATA!"
                try:
                    dataToWrite = netBuffer[:netBufferExpected]
                    print "  (writing " + str(len(dataToWrite)) + " bytes)"
                    os.write(tuntapFD, dataToWrite)
                    netBuffer = netBuffer[netBufferExpected:]
                    netBufferExpected = 0
                    print "  (data remaining in buffer: " + str(len(netBuffer)) + ")"
                except Exception, e:
                    print "problem"
                    print e

            if len(netBuffer) > 2:
                netBufferExpected = struct.unpack('!H', netBuffer[0:2])[0]
                #netBufferExpected = socket.ntohs(netBufferExpected)
                netBuffer = netBuffer[2:]
                print " NOW EXPECTING " + str(netBufferExpected)
                if netBufferExpected > 1500 * 2: # more than 2x MTU? something is wrong
                    print "  (which is more than 2x MTU, so giving up)"
                    netBuffer = ""
                    netBufferExpected = 0

            if len(netBuffer) == 0 and netBufferExpected == 0:
                break
    return netBuffer

def setupTUNTAP():
    tuntapDevice = "net/tun"
    ipAddress = "10.0.2.1"
    tuntapFD = os.open("/dev/" + tuntapDevice, os.O_RDWR)
    if tuntapDevice == "net/tun":
        # Linux specific code
        TUNSETIFF = 0x400454ca
        IFF_TUN   = 0x0001
        IFF_TAP   = 0x0002
        IFF_NO_PI = 0x1000
        TUNMODE = IFF_TAP
        TUNMODE |= IFF_NO_PI # do not prepend protocol information
        from fcntl import ioctl
        ifs = ioctl(tuntapFD, TUNSETIFF, struct.pack("16sH", "websockettunt%d", TUNMODE))
        tuntapDevice = ifs[:16].strip("\x00")
        sys.stderr.write("tuntapdevice: " + tuntapDevice + "\n")
    #os.system("ifconfig " + tuntapDevice + " inet " + ipAddress)
    os.system("ip link set " + tuntapDevice + " up ")
    os.system("brctl addif br1 " + tuntapDevice )
    return (tuntapFD, tuntapDevice, ipAddress)
# vi:sts=4 sw=4 et
