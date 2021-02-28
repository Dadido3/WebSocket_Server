# WebSocket Server

A conforming server implementation of the WebSocket standard as a module for PureBasic.

> :warning: **This is the threadless version of the WebSocket server**:  
> This version is not thread-safe. If you use threads, you have to protect the server by a single mutex.
> Also, the API is different to the threaded version, see [Usage](#Usage).

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

## Usage

Open a WebSocket-Server and define your event callback function:

``` PureBasic
*Server = WebSocket_Server::Create(8090, @WebSocket_Event())
```

Your event callback function should look similar to this:

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
  WebSocket_Server::Worker(*Server)
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

## Example

Here is an example chat application made with WebSockets.

[Dadido3/WebSocket_Server/master/HTML/Chat_Client.html](http://rawgit.com/Dadido3/WebSocket_Server/master/HTML/Chat_Client.html)

This example needs to connect to a WebSocket server.
If it doesn't connect to my server you can run your own local server.
For this you just have to compile and run `Example_Chat_Server.pb`.
