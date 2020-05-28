_GOODBYE_MESSAGE = u'Goodbye'
def web_socket_do_extra_handshake(request):
    print("web_socket_do_extra_handshake--->")
    print(request)
    print(dir(request))
    pass  # Always accept.

def web_socket_transfer_data(request):
    while True:
        line = request.ws_stream.receive_message()
        if line is None:
            return
        if isinstance(line, unicode):
            print("send message--->")
            request.ws_stream.send_message(line, binary=False)
            if line == _GOODBYE_MESSAGE:
                return
        else:
            request.ws_stream.send_message(line, binary=True)
