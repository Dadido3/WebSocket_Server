# WebSocket Server
A WebSocket-Server module for PureBasic.

## Usage
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
      
      Select *Event_Frame\Opcode
        ; #### OpCode is the type of frame you receive.
        ; #### Either Text, Binary-Data, Ping-Frames or other stuff.
        ; #### You only need to care about text and binary frames.
      EndSelect
      
  EndSelect
EndProcedure
```

Send a text-frame:
```
WebSocket_Server::Frame_Text_Send(*Server, *Client, "Hello Client!")
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
