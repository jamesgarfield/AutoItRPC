var net = require('net');

var HOST = '127.0.0.1';
var PORT = 6542;

var client = new net.Socket();
client.connect(PORT, HOST, function() {

    console.log('CONNECTED TO: ' + HOST + ':' + PORT);
   
   	AutoItRPC(client, "WinList") 
});


function AutoItRPC(client, cmd, args) {
	client.write(make_packet(make_message(cmd, args)))
}


function make_message(cmd, args) {
	var $GS = String.fromCharCode(29);
	if (args) {
		return [cmd, serialize_array(args)].join($GS);	
	}
	return cmd;
}

function make_packet(message) {
	var $FS = String.fromCharCode(28)
	return [message.length, message].join($FS)
}


function serialize_array(a) {
	var $STX = String.fromCharCode(2),
		$ETX = String.fromCharCode(3),
		$RS = String.fromCharCode(30);

	return [$STX, a.map(serialize_value).join($RS), $ETX].join('');
}

function serialize_value(v) {
	var $STX = String.fromCharCode(2),
		$ETX = String.fromCharCode(3),
		$US = String.fromCharCode(31)

	if (v instanceof Array) {
		return serialize_array(a);
	}

	var typevalue
	switch (typeof v) {
		case 'number':
			if (Math.floor(v) == v) {
				typevalue = ['i32', parseInt(v, 10)].join($US);
			}
			typevalue =  ['num', v].join($US);
			break;

		case 'string':
			typevalue =  ['str', v].join($US);
			break;
	}

	if (!typevalue) {
		return null
	}

	return [$STX, typevalue, $ETX].join('');
}

// Add a 'data' event handler for the client socket
// data is what the server sent to this socket
client.on('data', function(data) {
    
    console.log('DATA: ' + data);
    // Close the client socket completely
    client.destroy();
    
});

// Add a 'close' event handler for the client socket
client.on('close', function() {
    console.log('Connection closed');
});