var tuntapWS_connection = false;
var tuntapWS_canSend = false;


function tuntapWS_connect()
{
	//tuntapWS_connection = new WebSocket('ws://www.hackernel.com:3000/tap', []);
	tuntapWS_connection = new WebSocket('ws://212.129.249.212:3000/tap', []);
	//console.log("tuntapWS_connect--->");
	//tuntapWS_connection = new WebSocket('ws://killinux.com:3000/tap', []);
	tuntapWS_connection.onopen = tuntapWS_onOpen;
	tuntapWS_connection.onerror = tuntapWS_onError;
	tuntapWS_connection.onmessage = tuntapWS_onMessage;

//	tuntapWS_connection.binaryType = "arraybuffer";
}
function tuntapWS_sendData(data)
{

	if(1)
	{
		data = window.btoa(data);
	}
	else
	{
		//	var buf = new ArrayBuffer(data.length);
		//	var data2 = new Uint8Array(buf);
		var data2 = new Uint8Array(data.length);

		for(var i = 0; i < data.length; i++)
		{
			data2[i] = data.charCodeAt(i);
		}
		data = data2;
	}
	
//	data = new Blob([data]);
	//console.log("tuntapWS_sendData():");
	//console.log(data);
	if(tuntapWS_canSend)
		try
		{
			tuntapWS_connection.send(data); //, binary=true);
		}
		catch(e)
		{
			console.error(e);
		}
	else
		console.log("Dropped data: websockets connection not open");
}

var tuntapWS_onOpen = function tuntapWS_onOpen ()
{
	tuntapWS_canSend = true;
}

// Log errors
var tuntapWS_onError = function tuntapWS_onError (error)
{
	console.log('WebSocket Error ' + error);
}

// Log messages from the server
var tuntapWS_onMessage = function tuntapWS_onMessage (msg)
{
//	console.log('Server: ' + msg.data);
	
	var blob = msg.data;
	//var arrayBuffer = readAsArrayBuffer(blob);;
	var filereader = new FileReader();
	filereader.onload = function(evt) {
		var bytes = evt.target.result;
		//console.log('Bytes: ');
		//console.log(bytes);
		net_handler(bytes);
	}
	filereader.readAsBinaryString(blob);
	
	//	var bytes = window.atob(window.btoa(arrayBuffer));
	//	var bytes = window.atob(bytes);
}

