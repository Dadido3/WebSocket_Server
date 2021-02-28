XIncludeFile "../Includes/WebSocket_Server.pbi"

Procedure WebSocket_Event(*Server, *Client, Event, *Event_Frame.WebSocket_Server::Event_Frame)
  Protected Message.s
  
  Select Event
    Case WebSocket_Server::#Event_Connect
      ;PrintN("Client connected:    " + *Client)
      
    Case WebSocket_Server::#Event_Disconnect
      ;PrintN("Client disconnected: " + *Client)
      
    Case WebSocket_Server::#Event_Frame
      Select *Event_Frame\Opcode
        Case WebSocket_Server::#Opcode_Ping
          ;PrintN(" Ping from:          " + *Client)
          ; #### Pong is sent by the server automatically
          
        Case WebSocket_Server::#Opcode_Pong
          ;PrintN(" Pong from:          " + *Client)
          
        Case WebSocket_Server::#Opcode_Connection_Close
          ;PrintN(" Close request from: " + *Client)
          
        Case WebSocket_Server::#Opcode_Text
          Message = PeekS(*Event_Frame\Payload, *Event_Frame\Payload_Size, #PB_UTF8|#PB_ByteLength)
          ;If Len(Message) >= 60
          ;  PrintN(" Echo message from:  " + *Client + " (" + Left(Message, 60-3) + "...)")
          ;Else
          ;  PrintN(" Echo message from:  " + *Client + " (" + Message + ")")
          ;EndIf
          ;If CountString(Message, "�")
            ; #### Invalid string, disconnect client. This will cause another test case to fail. Best would be to have something that checks UTF-8 string for validity.
          ;  WebSocket_Server::Client_Disconnect(*Server, *Client, WebSocket_Server::#CloseStatusCode_1007)
          ;Else
            WebSocket_Server::Frame_Text_Send(*Server, *Client, Message)
          ;EndIf
          
        Case WebSocket_Server::#Opcode_Binary
          ;PrintN(" Echo binary from:   " + *Client + " (" + *Event_Frame\Payload_Size + " bytes)")
          WebSocket_Server::Frame_Send(*Server, *Client, #True, 0, WebSocket_Server::#Opcode_Binary, *Event_Frame\Payload, *Event_Frame\Payload_Size)
          
      EndSelect
      
  EndSelect
EndProcedure

OpenConsole()

*Server = WebSocket_Server::Create(8090, @WebSocket_Event())

Repeat
  Delay(10)
ForEver

; IDE Options = PureBasic 5.72 (Windows - x64)
; CursorPosition = 49
; FirstLine = 2
; Folding = -
; EnableThread
; EnableXP
; Executable = stress-test-server.exe
; Debugger = Standalone
; EnablePurifier = 32,32,4096,2
; EnableUnicode