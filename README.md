# WebSocket Server

A conforming server implementation of the WebSocket standard as a module for PureBasic.

**Features:**

- Supports unfragmented and fragmented binary and text frames.
- Callback based for easy use and low latency.
- The module combines fragment frames automatically, this is on by default and can be turned off in case the application needs to handle fragmentation itself.
- Built in handling of control frames (ping, disconnect).
- Passes nearly all of [Autobahn|Testsuite](https://github.com/crossbario/autobahn-testsuite) test cases (289 / 303).

**Not supported:**

- Any sort of compression. This will not hurt compatibility, as compression is optional.
- Automatic splitting of frames into fragments, but this can be done by the application if needed.
- Any WebSocket extensions.
- TLS. Best is to use a webserver (like [Caddy](https://github.com/caddyserver/caddy)) and setup a reverse proxy to the WebSocket server. If you need to supply static files (html, js), this is the preferred way anyways.

## Usage (Easy: Polling for events)

The easier (but slower) method of using this WebSocket server is to poll for events.
Even though the server uses threads internally, you don't have to worry about race conditions, deadlocks and so on.
All you need to do is to call `WebSocket_Server::Event_Callback(*Server, *Callback)` from your own main loop, this will call your event handling function that you have passed as the `*callback` parameter in the same context as your main loop.

Open a WebSocket-Server:

``` PureBasic
*Server = WebSocket_Server::Create(8090)
```

Receive events as callback:

``` PureBasic
Procedure WebSocket_Event(*Server, *Client, Event, *Event_Frame.WebSocket_Server::Event_Frame) ; no need to worry about mutexes as this call is coming from your main loop
  Select Event
    Case WebSocket_Server::#Event_Connect
      PrintN(" #### Client connected: " + *Client)
      
    Case WebSocket_Server::#Event_Disconnect
      PrintN(" #### Client disconnected: " + *Client)
      ; !!!! From the moment you receive this event *Client must not be used anymore !!!!
      
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
          ; *Event_Frame\Payload contains the data, *Event_Frame\Payload_Size is the size of the data in bytes.
          ; !!!! Don't use the Payload after you return from this callback. If you need to do so, make a copy of the memory in here. !!!!
      EndSelect
      
  EndSelect
EndProcedure
```

Your main loop:

``` PureBasic
Repeat
  ; Other stuff
  While WebSocket_Server::Event_Callback(*Server, @WebSocket_Event())
  Wend
  ; Other stuff
ForEver
```

Send a text-frame:

``` PureBasic
WebSocket_Server::Frame_Text_Send(*Server, *Client, "Hello Client!")
```

Send a binary-frame:

``` PureBasic
WebSocket_Server::Frame_Send(*Server, *Client, #True, 0, WebSocket_Server::#Opcode_Binary, *Data, Data_Size)
```

Close and free a WebSocket-Server:

``` PureBasic
Free(*Server)
```

## Usage (Advanced: Threaded callback)

This is similar to the method above, but instead of calling `WebSocket_Server::Event_Callback()` you set your event handler callback when you create your WebSocket server.
Your event handler will be called as soon as any event occurs.
But as the callback is called from a thread, you have to make sure everything in your event handler is thread-safe with the rest of your program.
This mode has better performance, less latency and uses less resources.
But it may cause problems like deadlocks or race conditions in your code if you use it wrong.

To make it clear, you only have to make sure that all **your** resources/lists/variables/... that you access from the event handler function are thread-safe with the rest of your program.
But you can still send websocket message from any thread or the event handler itself without using mutexes, as the functions of this module are thread-safe.

Open a WebSocket-Server:

``` PureBasic
*Server = WebSocket_Server::Create(8090, @WebSocket_Event())
```

Receive events as callback:

``` PureBasic
Procedure WebSocket_Event(*Server, *Client, Event, *Event_Frame.WebSocket_Server::Event_Frame)
  Select Event
    Case WebSocket_Server::#Event_Connect
      PrintN(" #### Client connected: " + *Client)
      
    Case WebSocket_Server::#Event_Disconnect
      PrintN(" #### Client disconnected: " + *Client)
      ; !!!! From the moment you receive this event *Client must not be used anymore !!!!
      
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
          ; !!!! Don't use the Payload after you return from this callback. If you need to do so, make a copy of the memory in here. !!!!
      EndSelect
      
  EndSelect
EndProcedure
```

Send a text-frame:

``` PureBasic
WebSocket_Server::Frame_Text_Send(*Server, *Client, "Hello Client!")
```

Send a binary-frame:

``` PureBasic
WebSocket_Server::Frame_Send(*Server, *Client, #True, 0, WebSocket_Server::#Opcode_Binary, *Data, Data_Size)
```

Close and free a WebSocket-Server:

``` PureBasic
Free(*Server)
```

## Example

Here is an example chat application made with WebSockets.

[Dadido3/WebSocket_Server/master/HTML/Chat_Client.html](http://rawgit.com/Dadido3/WebSocket_Server/master/HTML/Chat_Client.html)

This example needs to connect to a WebSocket server.
If it doesn't connect to my server you can run your own local server.
For this you just have to compile and run `Example_Chat_Server.pb`.
