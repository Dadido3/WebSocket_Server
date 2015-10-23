var wsUri = ["ws://localhost:8090", "ws://192.168.1.100:8090", "ws://D3nexus.de:8090"];
var websocket;
var wsUri_Counter = 0;

function Chat_WebSocket_Connect() {
	$("#Chat_Disconnected div").text('Trying to connect to "' + wsUri[wsUri_Counter] + '"')
	
	websocket = new WebSocket(wsUri[wsUri_Counter]);
	websocket.onopen = function (evt) { onOpen(evt); };
	websocket.onclose = function (evt) { onClose(evt); };
	websocket.onmessage = function (evt) { onMessage(evt); };
	websocket.onerror = function (evt) { onError(evt); };
	
	wsUri_Counter += 1;
	if (wsUri_Counter >= wsUri.length) {
		wsUri_Counter = 0;
	}
}

function onOpen(evt) {
	chat_bubble_add("Info", "Info", "Connection established!", Date.now());
	
	$("#Chat_Disconnected").fadeOut();
	
	var obj = new Object();
	obj.Type = "Username_Change";
	obj.Username = document.getElementById('Chat_Author').value;
	var jsonString= JSON.stringify(obj);
	websocket.send(jsonString);
}

function onClose(evt) {
	//chat_bubble_add("Warning", "Warning", "Connection lost! Trying again!", Date.now());
	
	Chat_WebSocket_Connect();
	
	$("#Chat_Disconnected").fadeIn();
}

function onMessage(evt) {
	var arr_from_json = JSON.parse( evt.data );
	
	switch(arr_from_json.Type){
		case "Message":
		case "Info":
		case "Error":
			if (arr_from_json.Author === document.getElementById('Chat_Author').value)
				arr_from_json.Type = "Own_Message";
			chat_bubble_add(arr_from_json.Type, arr_from_json.Author, arr_from_json.Message, arr_from_json.Timestamp * 1000);
			break;
			
		case "Userlist":
			var cList = $('#Chat_Userlist');
			cList.empty();
			$.each(arr_from_json.Username, function(i)
			{
				var li = $('<li/>')
					.attr('role', 'menuitem')
					.appendTo(cList);
				var aaa = $('<a/>')
					.text(arr_from_json.Username[i])
					.appendTo(li);
			});
			
			break;
	}
}

function onError(evt) {
	//chat_bubble_add("Error", "Error", evt.data, Date.now());
}

function chat_bubble_add(Type, Author, Message, Timestamp) {
	var chat_bubbles = document.getElementById('Chat_Bubbles');
	var message_container = document.createElement("div");
	var message_author = document.createElement("div");
	var message = document.createElement("div");
	var message_text = document.createElement("div");
	var message_timestamp = document.createElement("div");
	
	switch(Type) {
		case "Message":
			message_container.className = "Message_Container";
			$("#Audio_Click")[0].play();
			break;
		case "Own_Message":
			message_container.className = "Message_Container Own_Message";
			break;
		case "Info":
			message_container.className = "Message_Container Info";
			break;
		case "Warning":
			message_container.className = "Message_Container Warning";
			break;
		case "Error":
			message_container.className = "Message_Container Error";
			break;
	}
	
	var date = new Date(Timestamp);
	var hours = date.getHours();
	var minutes = date.getMinutes();
	
	message_author.className = "Author";
	message.className = "Message";
	message_timestamp.className = "Timestamp";
	
	$(message_author).text(Author);
	$(message).text(Message);
	$(message_timestamp).text(hours.padLeft() + ":" + minutes.padLeft());
	
	message_container.appendChild(message_author);
	message_container.appendChild(message);
	message.appendChild(message_text);
	message.appendChild(message_timestamp);
	chat_bubbles.appendChild(message_container);
	
	$("#Chat_Bubbles").animate({
	  scrollTop: $('#Chat_Bubbles')[0].scrollHeight - $('#Chat_Bubbles')[0].clientHeight
	}, 200);
	//$('#Chat_Bubbles').scrollTop($('#Chat_Bubbles').height())
}

function doSendInput() {
	
	if (($("#Chat_Message_Text").val() !== "") && ($("#Chat_Author").val() !== "")) {
		var obj = new Object();
		obj.Type = "Message";
		obj.Author = document.getElementById('Chat_Author').value;
		obj.Message = document.getElementById('Chat_Message_Text').value;
		obj.Timestamp = Math.floor(Date.now() / 1000);
		var jsonString= JSON.stringify(obj);
		
		websocket.send(jsonString);
		
		$("#Chat_Message_Text").val("");
	}
}

function Chat_Init() {
	
	$("#Chat_Message_Text").keydown(function(e){
		if (e.keyCode == 13 && !e.shiftKey)
		{
			e.preventDefault();
			doSendInput();
		}
	});
	
	$("#Chat_Author").val("GUEST_" + (Math.random() * 10000).toFixed());
	
	Chat_WebSocket_Connect();
}

function toggleUserlist() {
	$("#Chat_Userlist_Container").fadeToggle();
}

function changeUsername() {
	var obj = new Object();
	obj.Type = "Username_Change";
	obj.Username = document.getElementById('Chat_Author').value;
	var jsonString= JSON.stringify(obj);
	websocket.send(jsonString);
}

$(document).ready(function() {
	$("#Chat_Userlist_Container").hide();
})

window.addEventListener("load", Chat_Init, false);

Number.prototype.padLeft = function(base,chr){
    var  len = (String(base || 10).length - String(this).length)+1;
    return len > 0? new Array(len).join(chr || '0')+this : this;
}