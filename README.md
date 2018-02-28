# WebSocket Server
A WebSocket-Server module for PureBasic.


## Usage (Easy: Polling for events)
The easy method of using this WebSocket server is to poll for events.
Even though this include uses threads internally, you don't have to worry about threading.
All you need is to add `WebSocket_Server::Event_Callback(*Server, *Callback)` to your own main loop, this will call your event handling function you passed in the callback parameter in the same context as your main loop.

Open a WebSocket-Server:
```
*Server = WebSocket_Server::Create(8090)
```

Receive events as callback:
```
Procedure WebSocket_Event(*Server, *Client, Event, *Event_Frame.WebSocket_Server::Event_Frame) ; no need to worry about mutexes as this call is coming from your main loop
  Select Event
    Case WebSocket_Server::#Event_Connect
      PrintN(" #### Client connected: " + *Client)
      
    Case WebSocket_Server::#Event_Disconnect
      PrintN(" #### Client disconnected: " + *Client)
      ; !!!! From the moment you receive this event the *Client can not be used anymore !!!!
      
    Case WebSocket_Server::#Event_Frame
      PrintN(" #### Frame received from " + *Client)
      
      ; #### OpCode is the type of frame you receive.
      ; #### It's either Text, Binary-Data, Ping-Frames or other stuff.
      ; #### You only need to care about text and binary frames.
      Select *Event_Frame\Opcode
        Case WebSocket_Server::#Opcode_Ping
          PrintN("      Client sent a ping frame")
        Case WebSocket_Server::#Opcode_Text
          PrintN("      Text received: " + PeekS(*Event_Frame\Payload, *Event_Frame\Payload_Size, #PB_UTF8|#PB_ByteLength))
        Case WebSocket_Server::#Opcode_Binary
          PrintN("      Binary data received")
          ; *Event_Frame\Payload contains the data, *Event_Frame\Payload_Size is the size of the data in bytes
      EndSelect
      
  EndSelect
EndProcedure
```
Your main loop:
```
Repeat
  ; Other stuff
  While WebSocket_Server::Event_Callback(*Server, @WebSocket_Event())
  Wend
  ; Other stuff
ForEver
```

Send a text-frame:
```
WebSocket_Server::Frame_Text_Send(*Server, *Client, "Hello Client!")
```

Send a binary-frame:
```
WebSocket_Server::Frame_Send(*Server, *Client, #True, 0, WebSocket_Server::#Opcode_Binary, *Data, Data_Size)
```

Close and free a WebSocket-Server:
```
Free(*Server)
```


## Usage (Advanced: Threaded callback)
It's similar to the method above, but you don't have to add anything to your own main loop.
Instead the callback will be called as soon as any event occurs.
As the callback is called from a different thread, you have to make sure everything in your callback function is threadsafe with the rest of your program.
This mode has better performance, less latency and uses less ressources.
But it may cause bugs like deadlocks if you use it wrong.

To make it clear, you only have to make sure that all the >your< ressources/lists/variables/... used in the event handler function are threadsafe with the rest of your program.
But You can still send websocket message from any thread or the event handler itself without using mutexes, as the functions of this include are already threadsafe.

Open a WebSocket-Server:
```
*Server = WebSocket_Server::Create(8090, @WebSocket_Event())
```

Receive events as callback:
```
Procedure WebSocket_Event(*Server, *Client, Event, *Event_Frame.WebSocket_Server::Event_Frame)
  Select Event
    Case WebSocket_Server::#Event_Connect
      PrintN(" #### Client connected: " + *Client)
      
    Case WebSocket_Server::#Event_Disconnect
      PrintN(" #### Client disconnected: " + *Client)
      ; !!!! From the moment you receive this event the *Client can not be used anymore !!!!
      
    Case WebSocket_Server::#Event_Frame
      PrintN(" #### Frame received from " + *Client)
      
      ; #### OpCode is the type of frame you receive.
      ; #### It's either Text, Binary-Data, Ping-Frames or other stuff.
      ; #### You only need to care about text and binary frames.
      Select *Event_Frame\Opcode
        Case WebSocket_Server::#Opcode_Ping
          PrintN("      Client sent a ping frame")
        Case WebSocket_Server::#Opcode_Text
          PrintN("      Text received: " + PeekS(*Event_Frame\Payload, *Event_Frame\Payload_Size, #PB_UTF8|#PB_ByteLength))
        Case WebSocket_Server::#Opcode_Binary
          PrintN("      Binary data received")
          ; *Event_Frame\Payload contains the data, *Event_Frame\Payload_Size is the size of the data in bytes
      EndSelect
      
  EndSelect
EndProcedure
```

Send a text-frame:
```
WebSocket_Server::Frame_Text_Send(*Server, *Client, "Hello Client!")
```

Send a binary-frame:
```
WebSocket_Server::Frame_Send(*Server, *Client, #True, 0, WebSocket_Server::#Opcode_Binary, *Data, Data_Size)
```

Close and free a WebSocket-Server:
```
Free(*Server)
```


## Example
Here is an chat-example made with WebSockets.
http://rawgit.com/Dadido3/WebSocket_Server/master/HTML/Chat_Client.html

This example needs to connect to a WebSocket server.
If it doesn't connect to my server you can run your own local server.
For this you just have to comile and run:
```
Example_Chat_Server.pb
```
