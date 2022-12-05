Structure Chat_Message
  Type.s
  Author.s
  Message.s
  Timestamp.q
EndStructure

Structure Chat_Username_Change
  Type.s
  Username.s
EndStructure

Structure Chat_Userlist
  Type.s
  
  List Username.s()
EndStructure

Structure Client
  *WebSocket_Client
  
  Username.s
EndStructure

Global NewList Client.Client()

XIncludeFile "Includes/WebSocket_Server.pbi"

Procedure WebSocket_Event(*Server, *Client, Event, *Event_Frame.WebSocket_Server::Event_Frame)
  Protected Chat_Message.Chat_Message
  Protected Chat_Username_Change.Chat_Username_Change
  Protected Chat_Userlist.Chat_Userlist
  Protected JSON_ID.i
  Protected JSON2_ID.i
  Protected JSON_String.s
  
  Select Event
    Case WebSocket_Server::#Event_Connect
      PrintN(" #### Client connected: " + *Client)
      AddElement(Client())
      Client()\WebSocket_Client = *Client
      
      JSON2_ID = CreateJSON(#PB_Any)
      If JSON2_ID
        
        Chat_Userlist\Type = "Userlist"
        ForEach Client()
          AddElement(Chat_Userlist\UserName())
          Chat_Userlist\UserName() = Client()\Username
        Next
        
        InsertJSONStructure(JSONValue(JSON2_ID), Chat_Userlist, Chat_Userlist)
        
        WebSocket_Server::Frame_Text_Send(*Server, *Client, ComposeJSON(JSON2_ID))
        
        FreeJSON(JSON2_ID)
      EndIf
      
    Case WebSocket_Server::#Event_Disconnect
      PrintN(" #### Client disconnected: " + *Client)
      ForEach Client()
        If Client()\WebSocket_Client = *Client
          DeleteElement(Client())
          Break
        EndIf
      Next
      
      JSON2_ID = CreateJSON(#PB_Any)
      If JSON2_ID
        
        Chat_Userlist\Type = "Userlist"
        ForEach Client()
          AddElement(Chat_Userlist\UserName())
          Chat_Userlist\UserName() = Client()\Username
        Next
        
        InsertJSONStructure(JSONValue(JSON2_ID), Chat_Userlist, Chat_Userlist)
        
        JSON_String = ComposeJSON(JSON2_ID)
        ForEach Client()
          WebSocket_Server::Frame_Text_Send(*Server, Client()\WebSocket_Client, JSON_String)
        Next
        
        FreeJSON(JSON2_ID)
      EndIf
      
    Case WebSocket_Server::#Event_Frame
      Select *Event_Frame\Opcode
        Case WebSocket_Server::#Opcode_Ping
          PrintN(" #### Ping from *Client " + *Client)
        Case WebSocket_Server::#Opcode_Text
          JSON_ID = ParseJSON(#PB_Any, PeekS(*Event_Frame\Payload, *Event_Frame\Payload_Size, #PB_UTF8|#PB_ByteLength))
          If JSON_ID
            
            Select GetJSONString(GetJSONMember(JSONValue(JSON_ID), "Type"))
              Case "Message"
                ExtractJSONStructure(JSONValue(JSON_ID), Chat_Message, Chat_Message)
                PrintN(Chat_Message\Author + ": " + Chat_Message\Message)
                
                Debug PeekS(*Event_Frame\Payload, *Event_Frame\Payload_Size, #PB_UTF8|#PB_ByteLength)
                
                JSON2_ID = CreateJSON(#PB_Any)
                If JSON2_ID
                  
                  ForEach Client()
                    If Client()\WebSocket_Client = *Client
                      Chat_Message\Author = Client()\Username
                      ;Chat_Message\Timestamp = Date()
                      Break
                    EndIf
                  Next
                  
                  InsertJSONStructure(JSONValue(JSON2_ID), Chat_Message, Chat_Message)
                  
                  JSON_String = ComposeJSON(JSON2_ID)
                  ;Debug JSON_String
                  ForEach Client()
                    WebSocket_Server::Frame_Text_Send(*Server, Client()\WebSocket_Client, JSON_String)
                  Next
                  
                  FreeJSON(JSON2_ID)
                EndIf
                
              Case "Username_Change"
                ExtractJSONStructure(JSONValue(JSON_ID), Chat_Username_Change, Chat_Username_Change)
                ForEach Client()
                  If Client()\WebSocket_Client = *Client
                    Client()\Username = Chat_Username_Change\Username
                    Break
                  EndIf
                Next
                
                JSON2_ID = CreateJSON(#PB_Any)
                If JSON2_ID
                  
                  Chat_Userlist\Type = "Userlist"
                  ForEach Client()
                    AddElement(Chat_Userlist\UserName())
                    Chat_Userlist\UserName() = Client()\Username
                  Next
                  
                  InsertJSONStructure(JSONValue(JSON2_ID), Chat_Userlist, Chat_Userlist)
                  
                  JSON_String = ComposeJSON(JSON2_ID)
                  ForEach Client()
                    WebSocket_Server::Frame_Text_Send(*Server, Client()\WebSocket_Client, JSON_String)
                  Next
                  
                  FreeJSON(JSON2_ID)
                EndIf
                
            EndSelect
            
            FreeJSON(JSON_ID)
          EndIf
      EndSelect
      
  EndSelect
EndProcedure

OpenConsole()

*Server = WebSocket_Server::Create(8090)

Repeat
  While WebSocket_Server::Event_Callback(*Server, @WebSocket_Event())
  Wend
  
  Delay(10)
ForEver

; IDE Options = PureBasic 6.00 LTS (Windows - x64)
; CursorPosition = 160
; FirstLine = 115
; Folding = -
; EnableThread
; EnableXP