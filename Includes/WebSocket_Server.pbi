; ##################################################### License / Copyright #########################################
; 
;     The MIT License (MIT)
;     
;     Copyright (c) 2015-2022 David Vogel
;     
;     Permission is hereby granted, free of charge, to any person obtaining a copy
;     of this software and associated documentation files (the "Software"), to deal
;     in the Software without restriction, including without limitation the rights
;     to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
;     copies of the Software, and to permit persons to whom the Software is
;     furnished to do so, subject to the following conditions:
;     
;     The above copyright notice and this permission notice shall be included in all
;     copies or substantial portions of the Software.
;     
;     THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;     IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;     FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
;     AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;     LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
;     OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
;     SOFTWARE.
; 
; #################################################### Documentation ################################################
; 
; #### WebSocket_Server ####
; 
; Enable Threadsafe!
; 
; - Works in unicode and ascii mode
; - Works under x86 and x64
; 
; Working OSes:
; - Windows
;   - Tested: 7 x64
;   - Tested: 10 x64
; - Linux
;   - Tested: Ubuntu 17.10 x64
; - MacOS
;   - Not tested yet
; 
; 
; 
; Version history:
; - V0.990 (05.02.2015)
;   - Everything done (Hopefully)
; 
; - V0.991 (09.02.2015)
;   - Changed endian conversion from bit-shifting to direct memory access to make the include working with x86.
; 
; - V0.992 (09.02.2015)
;   - Added #Frame_Payload_Max to prevent clients to make the server allocate a lot of memory.
;   - Some other small bugfixes.
; 
; - V0.993 (24.10.2015)
;   - Made it compatible with PB 5.40 LTS (Mainly SHA-1)
;   - Bugfix with pokes
; 
; - V0.994 (20.05.2017)
;   - Made it compatible with PB 5.60
; 
; - V0.995 (28.02.2018)
;   - Fixed possible deadlock
;   - Fixed unnecessary disconnect event
; 
; - V0.996 (01.03.2018)
;   - Fixed error on too quick disconnect
; 
; - V0.997 (02.03.2018)
;   - Use extra thread for callbacks
;   - Optimized the network event handling
;   - Fixed some leftovers when freeing the server
; 
; - V0.998 (15.11.2019)
;   - Fix missing or wrong rx frames on slower connections
; 
; - V0.999 (07.05.2020)
;   - Fix rare crash after calling CloseNetworkConnection from another thread.
; 
; - V1.000 (09.10.2020)
;   - Fix issue with some HTTP header fields and values not being treated case-insensitive.
; 
; - V1.003 (09.02.2021)
;   - Fix typos and misspelled words
;   - Remove Event_Disconnect field from client
;   - Don't break loop in Thread_Receive_Frame() after every frame
;   - Remove some commented code
;   - Add mutexless variant of Frame_Send() for internal use
;   - Fix a race condition that may happen when using Client_Disconnect()
;   - Fix a memory leak in the HTTP header receiver
;   - Get rid of pushing and popping RX_Frame
;   - Set Event_Disconnect_Manually flag inside of Frame_Send() and Frame_Send_Mutexless()
;   - Remove the Done field from Frames
;   - Add *New_RX_FRAME to client
;   - Simplify how frames are received
;   - Check result of all AllocateMemory and AllocateStructure calls
;   - Null any freed memory or structure pointer
;   - Prevent client to receive HTTP header if there is a forced disconnect
;   - Limit HTTP header allocation size
;   - Add internal function Client_Free() that frees everything that is allocated by a client
; 
; - V1.004 (11.02.2021)
;   - Use Autobahn|Testsuite for fuzzing
;   - Fix most test cases
;   - Fix how server closes the connection on client request
;   - Fix data frame length encoding for transmitted frames
;   - Limit the payload size of control frames (defined by websocket standard)
;   - Free semaphore right before the server thread ends, not when the event thread ends
;   - Move built in frame actions (ping and disconnect request handling) into Event_Callback so the actions stay in sync with everything else
;   - Send signal to event thread every time a frame has been sent
;   - Use local pointer to frame data in Event_Callback
;   - Get rid of unnecessary second FirstElement()
;   - Check if control frames are fragmented
;   - Don't execute frame actions on malformed frames
;   - Add a fragmented payload limit
;   - Add a FrameData field that contains the raw frame Data
;   - Add HandleFragmentation parameter to Create
;   - Add Fragments List to client, that stores a fragment frame series
;   - Add logic to combine fragmented frames
;   - Allow fragmented messages to have a payload of 0 length
;   - Add close status code enumeration
;   - Add status code and reason to client disconnect
;   - Add Client_Disconnect_Mutexless
;   - Use default disconnect reason of 0, which means no reason at all
;   - Remove all other (unsent) TX_Frame elements before sending a disconnect control frame
;   - Add reason to Client_Disconnect
;   - Close connection with correct status code in case of error
; 
; - V1.005 (28.02.2021)
;   - Use suggested min. size for Base64EncoderBuffer output buffer
;   - Add connect (handshake) and disconnect timeouts
;   - Read http header in bigger chunks, assume that clients don't send any data after #CRLF$ #CRLF$
;   - Implement client queue instead of iterating over all clients every event
;   - On forced connection close, dump incoming network data into dummy buffer
;   - Enqueue client on every possible action that needs to trigger a Event_Callback call
;   - Throttle network thread when client queue is too large, this gives Event_Callback more processing time
;   - Use allocation dumper to find memory leaks and other memory problems
;   - Fix possible memory leak in Client_Disconnect_Mutexless()
; 
; - V1.006 (05.12.2022)
;   - Add Get_HTTP_Header function and make HTTP_Header structure public

; ##################################################### Check Compiler options ######################################

CompilerIf Not #PB_Compiler_Thread
  CompilerError "Thread-Safe is not activated!"
CompilerEndIf

; ##################################################### Module ######################################################

DeclareModule WebSocket_Server
  
  ; ##################################################### Public Constants ############################################
  
  #Version = 1006
  
  Enumeration
    #Event_None
    #Event_Connect
    #Event_Disconnect
    #Event_Frame
  EndEnumeration
  
  Enumeration
    #Opcode_Continuation
    #Opcode_Text
    #Opcode_Binary
    
    #Opcode_Connection_Close = 8
    #Opcode_Ping
    #Opcode_Pong
  EndEnumeration
  
  Enumeration
    #CloseStatusCode_Normal = 1000      ; indicates a normal closure, meaning that the purpose for which the connection was established has been fulfilled.
    #CloseStatusCode_GoingAway          ; indicates that an endpoint is "going away", such as a server going down or a browser having navigated away from a page.
    #CloseStatusCode_ProtocolError      ; indicates that an endpoint is terminating the connection due to a protocol error.
    #CloseStatusCode_UnhandledDataType  ; indicates that an endpoint is terminating the connection because it has received a type of data it cannot accept (e.g., an endpoint that understands only text data MAY send this if it receives a binary message).
    #CloseStatusCode_1004               ; Reserved.  The specific meaning might be defined in the future.
    #CloseStatusCode_NoStatusCode       ; is a reserved value and MUST NOT be set as a status code in a Close control frame by an endpoint.  It is designated for use in applications expecting a status code to indicate that no status code was actually present.
    #CloseStatusCode_AbnormalClose      ; is a reserved value and MUST NOT be set as a status code in a Close control frame by an endpoint.  It is designated for use in applications expecting a status code to indicate that the connection was closed abnormally, e.g., without sending or receiving a Close control frame.
    #CloseStatusCode_1007               ; indicates that an endpoint is terminating the connection because it has received data within a message that was not consistent with the type of the message (e.g., non-UTF-8 [RFC3629] data within a text message).
    #CloseStatusCode_PolicyViolation    ; indicates that an endpoint is terminating the connection because it has received a message that violates its policy.  This is a generic status code that can be returned when there is no other more suitable status code (e.g., 1003 or 1009) or if there is a need to hide specific details about the policy.
    #CloseStatusCode_SizeLimit          ; indicates that an endpoint is terminating the connection because it has received a message that is too big for it to process.
    #CloseStatusCode_1010
    #CloseStatusCode_1011
    #CloseStatusCode_1015
  EndEnumeration
  
  #RSV1 = %00000100
  #RSV2 = %00000010
  #RSV3 = %00000001
  
  #Frame_Payload_Max = 10000000             ; Default max. size of an incoming frame's payload. If the payload exceeds this value, the client will be disconnected.
  #Frame_Fragmented_Payload_Max = 100000000 ; Default max. size of the total payload of a series of frame fragments. If the payload exceeds this value, the client will be disconnected. If the user/application needs more, it has To handle fragmentation on its own.
  #Frame_Control_Payload_Max = 125          ; Max. allowed amount of bytes in the payload of control frames. This is defined by the websocket standard.
  
  #ClientDisconnectTimeout = 5000 ; Maximum duration in ms a client waits to send all queued outgoing frames on connection closure.
  #ClientConnectTimeout = 45000 ; Maximum duration in ms a client is allowed to take for connection and handshake related activities.
  
  ; ##################################################### Public Structures ###########################################
  
  Structure Event_Frame
    Fin.a                 ; #True if this is the final frame of a series of frames.
    RSV.a                 ; Extension bits: RSV1, RSV2, RSV3.
    Opcode.a              ; Opcode.
    
    *Payload
    Payload_Size.i
    
    *FrameData            ; Raw frame data. don't use this, you should use the *Payload instead.
  EndStructure
  
  Structure HTTP_Header
    *Data
    RX_Pos.i
    
    Request.s     ; The HTTP request that was originally sent by the client.
    Map Field.s() ; The HTTP header key value pairs originally sent by the client.
  EndStructure
  
  ; ##################################################### Public Variables ############################################
  
  ; ##################################################### Public Prototypes ###########################################
  
  Prototype   Event_Callback(*Object, *Client, Event.i, *Custom_Structure=#Null)
  
  ; ##################################################### Public Procedures (Declares) ################################
  
  Declare.i Create(Port, *Event_Thread_Callback.Event_Callback=#Null, Frame_Payload_Max.q=#Frame_Payload_Max, HandleFragmentation=#True) ; Creates a new WebSocket server. *Event_Thread_Callback is the callback which will be called out of the server thread.
  Declare   Free(*Object)                                                                           ; Closes the WebSocket server.
  
  Declare   Frame_Text_Send(*Object, *Client, Text.s)                                               ; Sends a text-frame.
  Declare   Frame_Send(*Object, *Client, FIN.a, RSV.a, Opcode.a, *Payload, Payload_Size.q)          ; Sends a frame. FIN, RSV and Opcode can be freely defined. Normally you should use #Opcode_Binary.
  
  Declare   Event_Callback(*Object, *Callback.Event_Callback)                                       ; Checks for events, and calls the *Callback function if there are any.
  
  Declare.i Get_HTTP_Header(*Client)                                                                ; Returns a pointer to the HTTP_Header structure that contains the parsed HTTP request of the given client.
  
  Declare   Client_Disconnect(*Object, *Client, statusCode.u=0, reason.s="")                        ; Disconnects the specified *Client.
  
EndDeclareModule

; ##################################################### Module (Private Part) #######################################

Module WebSocket_Server
  
  EnableExplicit
  
  ; #### Only use this for debugging purposes.
  ;XIncludeFile "AllocationDumper.pbi"
  
  InitNetwork()
  UseSHA1Fingerprint()
  
  ; ##################################################### Constants ###################################################
  
  #Frame_Data_Size_Min = 2048
  
  #HTTP_Header_Data_Read_Step = 1024
  #HTTP_Header_Data_Size_Step = 2048
  #HTTP_Header_Data_Size_Max = 8192
  
  #GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
  
  Enumeration
    #Mode_Handshake
    #Mode_Frames
  EndEnumeration
  
  ; ##################################################### Structures ##################################################
  
  Structure Eight_Bytes
    Byte.a[8]
  EndStructure
  
  Structure Frame_Header_Length
    Dummy.a
    Length.a
    Extended.a[8]
  EndStructure
  
  Structure Frame_Header
    StructureUnion
      Byte.a[14]            ; Size of the header is 14B max.
      Length.Frame_Header_Length
    EndStructureUnion
  EndStructure
  
  Structure Frame
    *Data.Frame_Header
    
    RxTx_Pos.i              ; Current position while receiving or sending the frame.
    RxTx_Size.i             ; Size of the frame (Header + Payload).
    
    Payload_Pos.i
    Payload_Size.q          ; Quad, because a frame can be 2^64B large.
  EndStructure
  
  Structure Client
    ID.i                    ; Client ID. Is set to #Null when the TCP connection closes. The user can still read all incoming frames, though.
    
    HTTP_Header.HTTP_Header
    
    *New_RX_FRAME.Frame     ; A frame that is currently being received.
    
    List RX_Frame.Frame()   ; List of fully received incoming frames (They need to be passed to the user of this library).
    List TX_Frame.Frame()   ; List of outgoing frames. First one is currently being sent.
    
    List Fragments.Event_Frame()  ; List of (parsed) fragment frames. A series of fragments will be stored here temporarily.
    Fragments_Size.q              ; Total size sum of all fragments.
    
    Mode.i
    
    Event_Connect.i               ; #True --> Generate connect callback.
    Event_Disconnect_Manually.i   ; #True --> Generate disconnect callback and delete client as soon as all data is sent and read by the application. (This gets set by the application or websocket protocol, there is possibly still a TCP connection)
    DisconnectTimeout.q           ; When Event_Disconnect_Manually is #True: Point in time when the server forcefully disconnects the client, no matter if all packets have been sent or not.
    ConnectTimeout.q              ; Point in time when a client will be disconnected. Reset after the handshake was successful.
    
    Enqueued.i              ; #True --> This client is already inside the ClientQueue of the server.
    
    External_Reference.i    ; #True --> An external reference was given to the application (via event). If the connection closes, there must be a closing event.
  EndStructure
  
  Structure Object
    Server_ID.i
    
    Network_Thread_ID.i     ; Thread handling in and outgoing data.
    
    Event_Thread_ID.i       ; Thread handling event callbacks and client deletions.
    
    List Client.Client()
    List *ClientQueue.Client() ; A queue of clients that need to be processed in Event_Callback().
    ClientQueueSemaphore.i     ; Semaphore for the client queue.
    
    *Event_Thread_Callback.Event_Callback
    
    Frame_Payload_Max.q     ; Max-Size of an incoming frame's payload. If the frame exceeds this value, the client will be disconnected.
    HandleFragmentation.i   ; Let the library handle frame fragmentation. If set to true, the user/application will only receive coalesced frames. If set to false, the user/application has to handle fragmentation (By checking the Fin flag and #Opcode_Continuation)
    
    Mutex.i
    
    Free_Event.i            ; Free the event thread and its semaphore.
    Free.i                  ; Free the main networking thread and all the resources.
  EndStructure
  
  ; ##################################################### Variables ###################################################
  
  Global DummyMemorySize = 1024
  Global *DummyMemory = AllocateMemory(DummyMemorySize)
  
  ; ##################################################### Declares ####################################################
  
  Declare   Frame_Send_Mutexless(*Object.Object, *Client.Client, FIN.a, RSV.a, Opcode.a, *Payload, Payload_Size.q)
  Declare   Client_Disconnect_Mutexless(*Object.Object, *Client.Client, statusCode.u=0, reason.s="")
  
  ; ##################################################### Procedures ##################################################
  
  Procedure Client_Select(*Object.Object, ID.i)
    If Not ID
      ProcedureReturn #False
    EndIf
    
    ForEach *Object\Client()
      If *Object\Client()\ID = ID
        ProcedureReturn #True
      EndIf
    Next
    
    ProcedureReturn #False
  EndProcedure
  
  Procedure ClientQueueEnqueue(*Object.Object, *Client.Client, signal=#True)
    If *Client\Enqueued
      ProcedureReturn #True
    EndIf
    
    LastElement(*Object\ClientQueue())
    If AddElement(*Object\ClientQueue())
      *Client\Enqueued = #True
      *Object\ClientQueue() = *Client
      
      If *Object\ClientQueueSemaphore And signal
        ; #### Set semaphore to 1, but don't increase count above 1.
        TrySemaphore(*Object\ClientQueueSemaphore)
        SignalSemaphore(*Object\ClientQueueSemaphore)
      EndIf
      
      ProcedureReturn #True
    EndIf
    
    ProcedureReturn #False
  EndProcedure
  
  Procedure ClientQueueDequeue(*Object.Object)
    Protected *Client.Client
    
    If FirstElement(*Object\ClientQueue())
      *Client = *Object\ClientQueue()
      DeleteElement(*Object\ClientQueue())
      *Client\Enqueued = #False
      ProcedureReturn *Client
    EndIf
    
    ProcedureReturn #Null
  EndProcedure
  
  Procedure ClientQueueRemove(*Object.Object, *Client.Client)
    If Not *Client\Enqueued
      ProcedureReturn #True
    EndIf
    
    ForEach *Object\ClientQueue()
      If *Object\ClientQueue() = *Client
        DeleteElement(*Object\ClientQueue())
        *Client\Enqueued = #False
        ProcedureReturn #True
      EndIf
    Next
    
    ProcedureReturn #False
  EndProcedure
  
  Procedure ClientQueueWait(*Object.Object)
    ; #### Wait for signal.
    WaitSemaphore(*Object\ClientQueueSemaphore)
  EndProcedure
  
  Procedure Client_Free(*Client.Client)
    ; #### Free all RX_Frames()
    While FirstElement(*Client\RX_Frame())
      If *Client\RX_Frame()\Data
        FreeMemory(*Client\RX_Frame()\Data) : *Client\RX_Frame()\Data = #Null
      EndIf
      DeleteElement(*Client\RX_Frame())
    Wend
    
    ; #### Free all TX_Frames()
    While FirstElement(*Client\TX_Frame())
      If *Client\TX_Frame()\Data
        FreeMemory(*Client\TX_Frame()\Data) : *Client\TX_Frame()\Data = #Null
      EndIf
      DeleteElement(*Client\TX_Frame())
    Wend
    
    ; #### Free all Fragments()
    While FirstElement(*Client\Fragments())
      If *Client\Fragments()\FrameData
        FreeMemory(*Client\Fragments()\FrameData) : *Client\Fragments()\FrameData = #Null
      EndIf
      DeleteElement(*Client\Fragments())
    Wend
    
    ; #### Free HTTP header data, if still present
    If *Client\HTTP_Header\Data
       FreeMemory(*Client\HTTP_Header\Data) : *Client\HTTP_Header\Data = #Null
    EndIf
    
    ; #### Free temporary RX frame
    If *Client\New_RX_FRAME
      If *Client\New_RX_FRAME\Data
        FreeMemory(*Client\New_RX_FRAME\Data) : *Client\New_RX_FRAME\Data = #Null
      EndIf
      FreeStructure(*Client\New_RX_FRAME) : *Client\New_RX_FRAME = #Null
    EndIf
  EndProcedure
  
  Procedure.s Generate_Key(Client_Key.s)
    Protected *Temp_Data_2, *Temp_Data_3
    Protected Temp_String.s
    Protected Temp_SHA1.s
    Protected i
    Protected Result.s
    
    Temp_String.s = Client_Key + #GUID
    
    ; #### Generate the SHA1
    *Temp_Data_2 = AllocateMemory(20)
    If Not *Temp_Data_2
      ProcedureReturn ""
    EndIf
    Temp_SHA1.s = StringFingerprint(Temp_String, #PB_Cipher_SHA1, 0, #PB_Ascii)
    ;Debug Temp_SHA1
    For i = 0 To 19
      PokeA(*Temp_Data_2+i, Val("$"+Mid(Temp_SHA1, 1+i*2, 2)))
    Next
    
    ; #### Encode the SHA1 as Base64
    *Temp_Data_3 = AllocateMemory(64) ; Expected max. size of Base64 encoded string is 27 bytes. But Base64EncoderBuffer has a min. output buffer size of 64 bytes.
    If Not *Temp_Data_3
      FreeMemory(*Temp_Data_2)
      ProcedureReturn ""
    EndIf
    CompilerIf #PB_Compiler_Version < 560
      Base64Encoder(*Temp_Data_2, 20, *Temp_Data_3, 64)
    CompilerElse
      Base64EncoderBuffer(*Temp_Data_2, 20, *Temp_Data_3, 64)
    CompilerEndIf
    
    Result = PeekS(*Temp_Data_3, -1, #PB_Ascii)
    
    FreeMemory(*Temp_Data_2)
    FreeMemory(*Temp_Data_3)
    
    ProcedureReturn Result
  EndProcedure
  
  Procedure Thread_Receive_Handshake(*Object.Object, *Client.Client)
    Protected Result.i
    Protected *Temp_Data
    Protected Temp_Text.s
    Protected Temp_Line.s
    Protected Temp_Key.s
    Protected Response.s
    Protected i
    
    If *Client\Event_Disconnect_Manually
      ; #### Read data into dummy memory to dump it. Otherwise this will be called over and over again, as there is "new" data.
      While ReceiveNetworkData(*Client\ID, *DummyMemory, DummyMemorySize) > 0
      Wend
      ProcedureReturn #False
    EndIf
    
    Repeat
    
      ; #### Limit memory usage.
      If *Client\HTTP_Header\RX_Pos > #HTTP_Header_Data_Size_Max
        *Client\Event_Disconnect_Manually = #True : ClientQueueEnqueue(*Object, *Client)
        ProcedureReturn #False
      EndIf
      
      ; #### Manage memory
      If Not *Client\HTTP_Header\Data
        *Client\HTTP_Header\Data = AllocateMemory(#HTTP_Header_Data_Size_Step) ; This will be purged when the header got fully parsed, when the client is deleted or when the server is released.
        If Not *Client\HTTP_Header\Data
          *Client\Event_Disconnect_Manually = #True : ClientQueueEnqueue(*Object, *Client)
          ProcedureReturn #False
        EndIf
      EndIf
      If MemorySize(*Client\HTTP_Header\Data) < *Client\HTTP_Header\RX_Pos + #HTTP_Header_Data_Read_Step
        *Temp_Data = ReAllocateMemory(*Client\HTTP_Header\Data, ((*Client\HTTP_Header\RX_Pos + #HTTP_Header_Data_Read_Step) / #HTTP_Header_Data_Size_Step + 1) * #HTTP_Header_Data_Size_Step)
        If *Temp_Data
          *Client\HTTP_Header\Data = *Temp_Data
        Else
          *Client\Event_Disconnect_Manually = #True : ClientQueueEnqueue(*Object, *Client)
          ProcedureReturn #False
        EndIf
      EndIf
      
      ; #### Receive a chunk of data.
      Result = ReceiveNetworkData(*Client\ID, *Client\HTTP_Header\Data + *Client\HTTP_Header\RX_Pos, #HTTP_Header_Data_Read_Step)
      If Result > 0
        *Client\HTTP_Header\RX_Pos + Result
      ElseIf Result = 0
        Break
      Else
        *Client\Event_Disconnect_Manually = #True : ClientQueueEnqueue(*Object, *Client)
        ProcedureReturn #False
      EndIf
      
      ; #### Check if the header ends
      If *Client\HTTP_Header\RX_Pos >= 4
        If PeekL(*Client\HTTP_Header\Data + *Client\HTTP_Header\RX_Pos - 4) = 168626701 ; ### CR LF CR LF
          
          Temp_Text = PeekS(*Client\HTTP_Header\Data, *Client\HTTP_Header\RX_Pos-2, #PB_Ascii)
          FreeMemory(*Client\HTTP_Header\Data) : *Client\HTTP_Header\Data = #Null
          
          *Client\HTTP_Header\Request = StringField(Temp_Text, 1, #CRLF$)
          
          For i = 2 To CountString(Temp_Text, #CRLF$)
            Temp_Line = StringField(Temp_Text, i, #CRLF$)
            *Client\HTTP_Header\Field(LCase(StringField(Temp_Line, 1, ":"))) = Trim(StringField(Temp_Line, 2, ":"))
          Next
          
          ; #### Check if the request is correct
          ;TODO: Check if this mess works with most clients/browsers!
          If StringField(*Client\HTTP_Header\Request, 1, " ") = "GET"
            If LCase(*Client\HTTP_Header\Field("upgrade")) = "websocket"
              If FindString(LCase(*Client\HTTP_Header\Field("connection")), "upgrade")
                If Val(*Client\HTTP_Header\Field("sec-websocket-version")) = 13 And FindMapElement(*Client\HTTP_Header\Field(), "sec-websocket-key")
                  *Client\Mode = #Mode_Frames
                  *Client\Event_Connect = #True : ClientQueueEnqueue(*Object, *Client)
                  Response = "HTTP/1.1 101 Switching Protocols" + #CRLF$ +
                             "Upgrade: websocket" + #CRLF$ +
                             "Connection: Upgrade" + #CRLF$ +
                             "Sec-WebSocket-Accept: " + Generate_Key(*Client\HTTP_Header\Field("sec-websocket-key")) + #CRLF$ +
                             #CRLF$
                Else
                  *Client\Event_Disconnect_Manually = #True : ClientQueueEnqueue(*Object, *Client)
                  Response = "HTTP/1.1 400 Bad Request" + #CRLF$ +
                             "Content-Type: text/html" + #CRLF$ +
                             "Content-Length: 63" + #CRLF$ +
                             #CRLF$ +
                             "<html><head></head><body><h1>400 Bad Request</h1></body></html>"
                EndIf
              Else
                *Client\Event_Disconnect_Manually = #True : ClientQueueEnqueue(*Object, *Client)
                Response = "HTTP/1.1 400 WebSocket Upgrade Failure" + #CRLF$ +
                           "Content-Type: text/html" + #CRLF$ +
                           "Content-Length: 77" + #CRLF$ +
                           #CRLF$ +
                           "<html><head></head><body><h1>400 WebSocket Upgrade Failure</h1></body></html>"
              EndIf
            Else
              *Client\Event_Disconnect_Manually = #True : ClientQueueEnqueue(*Object, *Client)
              Response = "HTTP/1.1 404 Not Found" + #CRLF$ +
                         "Content-Type: text/html" + #CRLF$ +
                         "Content-Length: 61" + #CRLF$ +
                         #CRLF$ +
                         "<html><head></head><body><h1>404 Not Found</h1></body></html>"
            EndIf
          Else
            *Client\Event_Disconnect_Manually = #True : ClientQueueEnqueue(*Object, *Client)
            Response = "HTTP/1.1 405 Method Not Allowed" + #CRLF$ +
                       "Content-Type: text/html" + #CRLF$ +
                       "Content-Length: 70" + #CRLF$ +
                       #CRLF$ +
                       "<html><head></head><body><h1>405 Method Not Allowed</h1></body></html>"
          EndIf
          
          ; #### Misuse a frame for the HTTP response
          LastElement(*Client\TX_Frame())
          If AddElement(*Client\TX_Frame())
            
            *Client\TX_Frame()\RxTx_Size = StringByteLength(Response, #PB_Ascii)
            *Client\TX_Frame()\Data = AllocateMemory(*Client\TX_Frame()\RxTx_Size)
            If Not *Client\TX_Frame()\Data
              *Client\Event_Disconnect_Manually = #True : ClientQueueEnqueue(*Object, *Client)
              DeleteElement(*Client\TX_Frame())
              ProcedureReturn #False
            EndIf
            
            PokeS(*Client\TX_Frame()\Data, Response, -1, #PB_Ascii | #PB_String_NoZero)
            
          EndIf
          
          ProcedureReturn #True
        EndIf
      EndIf
      
    ForEver
    
    ProcedureReturn #True
  EndProcedure
  
  Procedure Thread_Receive_Frame(*Object.Object, *Client.Client)
    Protected Receive_Size.i
    Protected Result.i
    Protected *Temp_Data
    Protected Mask.l, *Pointer_Mask.Long
    Protected *Eight_Bytes.Eight_Bytes
    Protected *TempFrame.Frame
    Protected i
    
    If *Client\Event_Disconnect_Manually
      ; #### Read data into dummy memory to dump it. Otherwise this will be called over and over again, as there is "new" data.
      While ReceiveNetworkData(*Client\ID, *DummyMemory, DummyMemorySize) > 0
      Wend
      ProcedureReturn #False
    EndIf
    
    Repeat
      
      ; #### Create new temporary frame if there is none yet.
      If Not *Client\New_RX_FRAME
        *Client\New_RX_FRAME = AllocateStructure(Frame) ; This will be purged when the frame is fully received, when the client is deleted or when the server is freed.
        If Not *Client\New_RX_FRAME
          *Client\Event_Disconnect_Manually = #True : ClientQueueEnqueue(*Object, *Client)
          ProcedureReturn #False
        EndIf
        *Client\New_RX_FRAME\RxTx_Size = 2
      EndIf
      
      *TempFrame = *Client\New_RX_FRAME
      
      ; #### Check if the frame exceeds the max. frame-size.
      If *TempFrame\Payload_Size > *Object\Frame_Payload_Max
        Client_Disconnect_Mutexless(*Object, *Client, #CloseStatusCode_SizeLimit)
        ProcedureReturn #False
      EndIf
      
      ; #### Check if a control frame exceeds the max. payload size.
      If *TempFrame\Payload_Size > #Frame_Control_Payload_Max
        ; #### Control frames are identified by opcodes where the most significant bit of the opcode is 1.
        If *TempFrame\RxTx_Pos >= 1 And *TempFrame\Data\Byte[0] & %00001000 = %1000
          Client_Disconnect_Mutexless(*Object, *Client, #CloseStatusCode_ProtocolError)
          ProcedureReturn #False
        EndIf
      EndIf
      
      ; #### Manage memory
      If Not *TempFrame\Data
        *TempFrame\Data = AllocateMemory(#Frame_Data_Size_Min) ; This will be purged when the client is deleted or when the server is freed, otherwise it will be reused in RX_Frame.
        If Not *TempFrame\Data
          *Client\Event_Disconnect_Manually = #True : ClientQueueEnqueue(*Object, *Client)
          ProcedureReturn #False
        EndIf
      EndIf
      If MemorySize(*TempFrame\Data) < *TempFrame\RxTx_Size + 3                   ; #### Add 3 bytes so that the (de)masking doesn't write outside of the buffer
        *Temp_Data = ReAllocateMemory(*TempFrame\Data, *TempFrame\RxTx_Size + 3)
        If *Temp_Data
          *TempFrame\Data = *Temp_Data
        Else
          *Client\Event_Disconnect_Manually = #True : ClientQueueEnqueue(*Object, *Client)
          ProcedureReturn #False
        EndIf
      EndIf
      
      ; #### Calculate how many bytes need to be received
      Receive_Size = *TempFrame\RxTx_Size - *TempFrame\RxTx_Pos
      
      ; #### Receive...
      Result = ReceiveNetworkData(*Client\ID, *TempFrame\Data + *TempFrame\RxTx_Pos, Receive_Size)
      If Result > 0
        *TempFrame\RxTx_Pos + Result
      Else
        ProcedureReturn #False
      EndIf
      
      ; #### Recalculate the size of the current frame (Only if all data is received)
      If *TempFrame\RxTx_Pos >= *TempFrame\RxTx_Size
        
        ; #### Size of the first 2 byte in the header
        *TempFrame\RxTx_Size = 2
        
        ; #### Determine the length of the payload
        Select *TempFrame\Data\Length\Length & %01111111
          Case 0 To 125
            *TempFrame\Payload_Size = *TempFrame\Data\Length\Length & %01111111
            
          Case 126
            *TempFrame\RxTx_Size + 2
            If *TempFrame\RxTx_Pos = *TempFrame\RxTx_Size
              *Eight_Bytes = @*TempFrame\Payload_Size
              *Eight_Bytes\Byte[1] = *TempFrame\Data\Length\Extended[0]
              *Eight_Bytes\Byte[0] = *TempFrame\Data\Length\Extended[1]
            EndIf
            
          Case 127
            *TempFrame\RxTx_Size + 8
            If *TempFrame\RxTx_Pos = *TempFrame\RxTx_Size
              *Eight_Bytes = @*TempFrame\Payload_Size
              *Eight_Bytes\Byte[7] = *TempFrame\Data\Length\Extended[0]
              *Eight_Bytes\Byte[6] = *TempFrame\Data\Length\Extended[1]
              *Eight_Bytes\Byte[5] = *TempFrame\Data\Length\Extended[2]
              *Eight_Bytes\Byte[4] = *TempFrame\Data\Length\Extended[3]
              *Eight_Bytes\Byte[3] = *TempFrame\Data\Length\Extended[4]
              *Eight_Bytes\Byte[2] = *TempFrame\Data\Length\Extended[5]
              *Eight_Bytes\Byte[1] = *TempFrame\Data\Length\Extended[6]
              *Eight_Bytes\Byte[0] = *TempFrame\Data\Length\Extended[7]
            EndIf
            
        EndSelect
        
        If *TempFrame\RxTx_Pos >= *TempFrame\RxTx_Size
          
          ; #### Add the payload length to the size of the frame data
          *TempFrame\RxTx_Size + *TempFrame\Payload_Size
          
          ; #### Check if there is a mask
          If *TempFrame\Data\Byte[1] & %10000000
            *TempFrame\RxTx_Size + 4
          EndIf
          
          *TempFrame\Payload_Pos = *TempFrame\RxTx_Size - *TempFrame\Payload_Size
          
        EndIf
        
      EndIf
      
      ; #### Check if the frame is received completely.
      If *TempFrame\RxTx_Pos >= *TempFrame\RxTx_Size
        
        ; #### (De)masking
        If *TempFrame\Data\Byte[1] & %10000000
          ; #### Get mask
          Mask = PeekL(*TempFrame\Data + *TempFrame\Payload_Pos - 4)
          
          ; #### XOr mask
          *Pointer_Mask = *TempFrame\Data + *TempFrame\Payload_Pos
          For i = 0 To *TempFrame\Payload_Size-1 Step 4
            *Pointer_Mask\l = *Pointer_Mask\l ! Mask
            *Pointer_Mask + 4
          Next
          
        EndIf
        
        ; #### Move this frame into the RX_Frame list.
        LastElement(*Client\RX_Frame())
        If AddElement(*Client\RX_Frame())
          *Client\RX_Frame()\Data = *TempFrame\Data
          *Client\RX_Frame()\Payload_Pos = *TempFrame\Payload_Pos
          *Client\RX_Frame()\Payload_Size = *TempFrame\Payload_Size
          *Client\RX_Frame()\RxTx_Pos = *TempFrame\RxTx_Pos
          *Client\RX_Frame()\RxTx_Size = *TempFrame\RxTx_Size
        EndIf
        
        ClientQueueEnqueue(*Object, *Client)
        
        ; #### Remove temporary frame, but don't free the memory, as it is used in the RX_Frame list now.
        FreeStructure(*Client\New_RX_FRAME) : *Client\New_RX_FRAME = #Null
        
      EndIf
      
    ForEver
    
    ProcedureReturn #True
  EndProcedure
  
  Procedure Thread_Transmit(*Object.Object, *Client.Client)
    Protected Transmit_Size.i
    Protected Result.i
    
    While FirstElement(*Client\TX_Frame())
      
      Transmit_Size = *Client\TX_Frame()\RxTx_Size - *Client\TX_Frame()\RxTx_Pos
      
      If Transmit_Size > 0
        ; #### Some data needs to be sent
        Result = SendNetworkData(*Client\ID, *Client\TX_Frame()\Data + *Client\TX_Frame()\RxTx_Pos, Transmit_Size)
        If Result > 0
          *Client\TX_Frame()\RxTx_Pos + Result
        Else
          ProcedureReturn #False
        EndIf
      EndIf
      
      Transmit_Size = *Client\TX_Frame()\RxTx_Size - *Client\TX_Frame()\RxTx_Pos
      
      If Transmit_Size <= 0
        ; #### Frame can be deleted
        FreeMemory(*Client\TX_Frame()\Data) : *Client\TX_Frame()\Data = #Null
        DeleteElement(*Client\TX_Frame())
        
        ; #### The event thread may have to handle stuff, send a signal.
        If ListSize(*Client\TX_Frame()) = 0
          ClientQueueEnqueue(*Object, *Client)
        EndIf
      EndIf
      
    Wend
    
    ProcedureReturn #True
  EndProcedure
  
  Procedure Thread(*Object.Object)
    Protected Busy, Counter, ms
    Protected *Client.Client
    
    Repeat
      ; #### Network Events
      Counter = 0
      Repeat
        LockMutex(*Object\Mutex)
        Select NetworkServerEvent(*Object\Server_ID)
          Case #PB_NetworkEvent_None
            UnlockMutex(*Object\Mutex)
            Break
            
          Case #PB_NetworkEvent_Connect
            LastElement(*Object\Client())
            If AddElement(*Object\Client())
              *Object\Client()\ConnectTimeout = ElapsedMilliseconds() + #ClientConnectTimeout
              *Object\Client()\ID = EventClient()
            EndIf
            Counter + 1
            
          Case #PB_NetworkEvent_Disconnect
            If Client_Select(*Object, EventClient())
              *Object\Client()\ID = #Null : ClientQueueEnqueue(*Object, *Object\Client()) ; #### The application can still read all incoming frames. The client will be deleted after all incoming frames have been read.
            EndIf
            Counter + 1
            
          Case #PB_NetworkEvent_Data
            If Client_Select(*Object, EventClient())
              Select *Object\Client()\Mode
                Case #Mode_Handshake  : Thread_Receive_Handshake(*Object, *Object\Client())
                Case #Mode_Frames     : Thread_Receive_Frame(*Object, *Object\Client())
              EndSelect
            EndIf
            Counter + 1
            
        EndSelect
        UnlockMutex(*Object\Mutex)
        
        If ListSize(*Object\ClientQueue()) > 100
          Delay(1)
        EndIf
        
      Until Counter > 10
      
      ; #### Busy when there was at least one network event
      Busy = Bool(Counter > 0)
      
      ;While Event_Callback(*Object, *Object\Event_Thread_Callback)
      ;Wend
      
      LockMutex(*Object\Mutex)
      ;Debug "Queue: " + ListSize(*Object\ClientQueue()) + "  Clients: " + ListSize(*Object\Client())
      ms = ElapsedMilliseconds()
      ForEach *Object\Client()
        *Client = *Object\Client()
        
        ; #### Send Data.
        If *Client\ID
          Busy | Bool(Thread_Transmit(*Object, *Client) = #False)
        EndIf
        
        ; #### Handle timeouts: Check if a client timed out before the handshake was successful.
        If *Client\ConnectTimeout And *Client\ConnectTimeout <= ms
          ClientQueueEnqueue(*Object, *Client)
        EndIf
        
        ; #### Handle timeouts: Disconnect timeout, so the client has some time to receive its disconnect message.
        If *Client\DisconnectTimeout And *Client\DisconnectTimeout <= ms
          ClientQueueEnqueue(*Object, *Client)
        EndIf
      Next
      UnlockMutex(*Object\Mutex)
      
      ; #### Delay only if there is nothing to do
      If Not Busy
        Delay(1)
      EndIf
      
    Until *Object\Free
    
    CloseNetworkServer(*Object\Server_ID) : *Object\Server_ID = #Null
    
    ; No need to care about the event thread, as it is shut down before cleanup happens here
    ForEach *Object\Client()
      ClientQueueRemove(*Object, *Object\Client())
      Client_Free(*Object\Client())
    Next
    
    If *Object\ClientQueueSemaphore
      FreeSemaphore(*Object\ClientQueueSemaphore) : *Object\ClientQueueSemaphore = #Null
    EndIf
    
    FreeMutex(*Object\Mutex) : *Object\Mutex = #Null
    FreeStructure(*Object)
  EndProcedure
  
  Procedure Thread_Events(*Object.Object)
    Repeat
      ; #### Wait for client queue entries.
      ClientQueueWait(*Object)
      
      ;Debug "New events to process"
      
      ; #### Process all events and callbacks. It's important that all events are processed.
      While Event_Callback(*Object, *Object\Event_Thread_Callback) And Not *Object\Free_Event
        ;Debug "Processed one event"
      Wend
      ;Debug "Processed all events"
    Until *Object\Free_Event
  EndProcedure
  
  Procedure Frame_Send_Mutexless(*Object.Object, *Client.Client, FIN.a, RSV.a, Opcode.a, *Payload, Payload_Size.q)
    Protected *Pointer.Ascii
    Protected *Eight_Bytes.Eight_Bytes
    
    If Not *Object
      ProcedureReturn #False
    EndIf
    
    If Not *Client
      ProcedureReturn #False
    EndIf
    
    If Not *Client\ID Or *Client\Event_Disconnect_Manually
      ProcedureReturn #False
    EndIf
    
    If Payload_Size < 0
      ProcedureReturn #False
    EndIf
    
    If Not *Payload
      Payload_Size = 0
    EndIf
    
    ; #### Special case: Connection close request (or answer).
    If Opcode = #Opcode_Connection_Close
      *Client\Event_Disconnect_Manually = #True : ClientQueueEnqueue(*Object, *Client)
      
      ; #### Remove all TX_Frame elements (Except the one that is being sent right now).
      While LastElement(*Client\TX_Frame()) And ListIndex(*Client\TX_Frame()) > 0
        If *Client\TX_Frame()\Data
          FreeMemory(*Client\TX_Frame()\Data) : *Client\TX_Frame()\Data = #Null
        EndIf
        DeleteElement(*Client\TX_Frame())
      Wend
    EndIf
    
    LastElement(*Client\TX_Frame())
    If AddElement(*Client\TX_Frame())
      
      *Client\TX_Frame()\Data = AllocateMemory(10 + Payload_Size)
      If Not *Client\TX_Frame()\Data
        *Client\Event_Disconnect_Manually = #True : ClientQueueEnqueue(*Object, *Client)
        ProcedureReturn #False
      EndIf
      
      ; #### FIN, RSV and Opcode
      *Pointer = *Client\TX_Frame()\Data
      *Pointer\a = (FIN & 1) << 7 | (RSV & %111) << 4 | (Opcode & %1111) : *Pointer + 1
      *Client\TX_Frame()\RxTx_Size + 1
      
      ; #### Payload_Size and extended stuff
      Select Payload_Size
        Case 0 To 125
          *Pointer\a = Payload_Size       : *Pointer + 1
          *Client\TX_Frame()\RxTx_Size + 1
        Case 126 To 65535
          *Eight_Bytes = @Payload_Size
          *Pointer\a = 126                  : *Pointer + 1
          *Pointer\a = *Eight_Bytes\Byte[1] : *Pointer + 1
          *Pointer\a = *Eight_Bytes\Byte[0] : *Pointer + 1
          *Client\TX_Frame()\RxTx_Size + 3
        Default
          *Eight_Bytes = @Payload_Size
          *Pointer\a = 127                  : *Pointer + 1
          *Pointer\a = *Eight_Bytes\Byte[7] : *Pointer + 1
          *Pointer\a = *Eight_Bytes\Byte[6] : *Pointer + 1
          *Pointer\a = *Eight_Bytes\Byte[5] : *Pointer + 1
          *Pointer\a = *Eight_Bytes\Byte[4] : *Pointer + 1
          *Pointer\a = *Eight_Bytes\Byte[3] : *Pointer + 1
          *Pointer\a = *Eight_Bytes\Byte[2] : *Pointer + 1
          *Pointer\a = *Eight_Bytes\Byte[1] : *Pointer + 1
          *Pointer\a = *Eight_Bytes\Byte[0] : *Pointer + 1
          *Client\TX_Frame()\RxTx_Size + 9
      EndSelect
      
      If *Payload
        CopyMemory(*Payload, *Pointer, Payload_Size)
        ;*Pointer + Payload_Size
        *Client\TX_Frame()\RxTx_Size + Payload_Size
      EndIf
      
      ProcedureReturn #True
    EndIf
    
    ProcedureReturn #False
  EndProcedure
  
  Procedure Frame_Send(*Object.Object, *Client.Client, FIN.a, RSV.a, Opcode.a, *Payload, Payload_Size.q)
    Protected Result
    
    If Not *Object
      ProcedureReturn #False
    EndIf
    
    LockMutex(*Object\Mutex)
    Result = Frame_Send_Mutexless(*Object, *Client, FIN, RSV, Opcode, *Payload, Payload_Size)
    UnlockMutex(*Object\Mutex)
    
    ProcedureReturn Result
  EndProcedure
  
  Procedure Frame_Text_Send(*Object.Object, *Client.Client, Text.s)
    Protected *Temp, Temp_Size.i
    Protected Result
    
    Temp_Size = StringByteLength(Text, #PB_UTF8)
    If Temp_Size = 0
      ProcedureReturn Frame_Send(*Object, *Client, #True, 0, #Opcode_Text, #Null, 0)
    EndIf
    If Temp_Size < 0
      ProcedureReturn #False
    EndIf
    *Temp = AllocateMemory(Temp_Size)
    If Not *Temp
      *Client\Event_Disconnect_Manually = #True : ClientQueueEnqueue(*Object, *Client)
      ProcedureReturn #False
    EndIf
    
    PokeS(*Temp, Text, -1, #PB_UTF8 | #PB_String_NoZero)
    
    Result = Frame_Send(*Object, *Client, #True, 0, #Opcode_Text, *Temp, Temp_Size)
    
    FreeMemory(*Temp)
    
    ProcedureReturn Result
  EndProcedure
  
  Procedure Event_Callback(*Object.Object, *Callback.Event_Callback)
    Protected Event_Frame.Event_Frame
    Protected *Client.Client
    Protected *Frame_Data.Frame_Header
    Protected MalformedFrame.i
    Protected TempOffset.i
    
    If Not *Object
      ProcedureReturn #False
    EndIf
    
    If Not *Callback
      ProcedureReturn #False
    EndIf
    
    LockMutex(*Object\Mutex)
    
    *Client = ClientQueueDequeue(*Object)
    If Not *Client
      UnlockMutex(*Object\Mutex)
      ProcedureReturn #False
    EndIf
    
    Repeat
      
      ; #### Event: Client connected and handshake was successful.
      If *Client\Event_Connect
        *Client\Event_Connect = #False
        *Client\ConnectTimeout = 0
        *Client\External_Reference = #True
        ClientQueueEnqueue(*Object, *Client)
        UnlockMutex(*Object\Mutex)
        *Callback(*Object, *Client, #Event_Connect)
        LockMutex(*Object\Mutex)
        Continue
      EndIf
      
      ; #### Connect and handshake timeout. The client will be enqueued for this in Thread().
      If *Client\ConnectTimeout And *Client\ConnectTimeout <= ElapsedMilliseconds()
        *Client\Event_Disconnect_Manually = #True
      EndIf
      
      ; #### Event: Client disconnected (TCP connection got terminated) (Only return this event if there are no incoming frames left to be read by the application)
      If *Client\ID = #Null And ListSize(*Client\RX_Frame()) = 0
        If *Client\External_Reference
          UnlockMutex(*Object\Mutex)
          *Callback(*Object, *Client, #Event_Disconnect)
          LockMutex(*Object\Mutex)
        EndIf
        ; #### Delete the client and all its data.
        ClientQueueRemove(*Object, *Client)
        Client_Free(*Client)
        ChangeCurrentElement(*Object\Client(), *Client)
        DeleteElement(*Object\Client())
        Break
      EndIf
      
      ; #### Disconnect timeout. The client will be enqueued for this in Thread().
      If *Client\Event_Disconnect_Manually And Not *Client\DisconnectTimeout
        *Client\DisconnectTimeout = ElapsedMilliseconds() + #ClientDisconnectTimeout
      EndIf
      
      ; #### Event: Close connection (By the user of the library, by any error that forces a disconnect or by an incoming disconnect request of the client via ws control frame) (Only close the connection if there are no frames left)
      If *Client\Event_Disconnect_Manually And (ListSize(*Client\TX_Frame()) = 0 Or *Client\DisconnectTimeout <= ElapsedMilliseconds()) And ListSize(*Client\RX_Frame()) = 0
        ; #### Forward event to application, but only if there was a connect event for this client before
        If *Client\External_Reference
          UnlockMutex(*Object\Mutex)
          *Callback(*Object, *Client, #Event_Disconnect)
          LockMutex(*Object\Mutex)
        EndIf
        If *Client\ID
          CloseNetworkConnection(*Client\ID) : *Client\ID = #Null
        EndIf
        ; #### Delete the client and all its data.
        ClientQueueRemove(*Object, *Client)
        Client_Free(*Client)
        ChangeCurrentElement(*Object\Client(), *Client)
        DeleteElement(*Object\Client())
        Break
      EndIf
      
      ; #### Event: Frame available
      If FirstElement(*Client\RX_Frame())
        *Frame_Data = *Client\RX_Frame()\Data : *Client\RX_Frame()\Data = #Null
        
        Event_Frame\Fin = *Frame_Data\Byte[0] >> 7 & %00000001
        Event_Frame\RSV = *Frame_Data\Byte[0] >> 4 & %00000111
        Event_Frame\Opcode = *Frame_Data\Byte[0] & %00001111
        Event_Frame\Payload = *Frame_Data + *Client\RX_Frame()\Payload_Pos
        Event_Frame\Payload_Size = *Client\RX_Frame()\Payload_Size
        Event_Frame\FrameData = *Frame_Data : *Frame_Data = #Null
        
        ; #### Remove RX_Frame. Its data is either freed below, after it has been read by the user/application, or it is freed in the fragmentation handling code, or when the user is deleted, or when the server is freed.
        DeleteElement(*Client\RX_Frame())
        
        ; #### Enqueue again. Either because there are still frames to be read by the user, or because there are no frames anymore and the client can disconnect.
        ClientQueueEnqueue(*Object, *Client)
        
        ; #### Check if any extension bit is set. This lib doesn't support any extensions.
        If Event_Frame\RSV <> 0
          MalformedFrame = #True
        EndIf
        
        ; #### Check if a control frame is being fragmented.
        If Bool(Event_Frame\Opcode & %1000) And Event_Frame\Fin = #False
          MalformedFrame = #True
        EndIf
        
        ; #### Do default actions for specific opcodes.
        If Not MalformedFrame
          Select Event_Frame\Opcode
            Case #Opcode_Continuation       ; continuation frame
            Case #Opcode_Text               ; text frame
              ; TODO: Check if payload is a valid UTF-8 string and contains valid code points (There may be a corner case when frame fragments are split between code points)
            Case #Opcode_Binary             ; binary frame
            Case #Opcode_Connection_Close   ; connection close
              Protected statusCode.u, reason.s
              If Event_Frame\Payload_Size >= 2
                statusCode = PeekU(Event_Frame\Payload)
                statusCode = ((statusCode & $FF00) >> 8) | ((statusCode & $FF) << 8)
                reason = PeekS(Event_Frame\Payload + 2, Event_Frame\Payload_Size - 2, #PB_UTF8 | #PB_ByteLength)
              EndIf
              ; TODO: Check if status code is valid
              ; TODO: Check if reason is a valid UTF-8 string and contains valid code points
              Client_Disconnect_Mutexless(*Object, *Client, statusCode, reason)
            Case #Opcode_Ping               ; ping
              Frame_Send_Mutexless(*Object, *Client, #True, 0, #Opcode_Pong, Event_Frame\Payload, Event_Frame\Payload_Size)
            Case #Opcode_Pong               ; pong
            Default                         ; undefined
              MalformedFrame = #True
          EndSelect
        EndIf
        
        ; #### Coalesce frame fragments. This will prevent the application/user from receiving fragmented frames.
        ; #### Messy code, i wish there was something like go's defer and some other things.
        If Not MalformedFrame And *Object\HandleFragmentation
          If Not Event_Frame\Fin
            
            If Event_Frame\Opcode = #Opcode_Continuation
              ; #### This frame is in the middle of a fragment series.
              If Not LastElement(*Client\Fragments()) Or Not AddElement(*Client\Fragments())
                MalformedFrame = #True
              Else
                *Client\Fragments() = Event_Frame : Event_Frame\FrameData = #Null : Event_Frame\Payload = #Null
                *Client\Fragments_Size + Event_Frame\Payload_Size
                
                If *Client\Fragments_Size > #Frame_Fragmented_Payload_Max
                  MalformedFrame = #True
                Else
                  Continue ; Don't forward the frame to the user/application.
                EndIf
              EndIf
            Else
              ; #### This frame is the beginning of a fragment series.
              If ListSize(*Client\Fragments()) > 0
                ; #### Another fragment series is already started. Interleaving with other fragments is not allowed.
                MalformedFrame = #True
              Else
                LastElement(*Client\Fragments())
                If Not AddElement(*Client\Fragments())
                  MalformedFrame = #True
                Else
                  *Client\Fragments() = Event_Frame : Event_Frame\FrameData = #Null : Event_Frame\Payload = #Null
                  *Client\Fragments_Size + Event_Frame\Payload_Size
                  
                  If *Client\Fragments_Size > #Frame_Fragmented_Payload_Max
                    MalformedFrame = #True
                  Else
                    Continue ; Don't forward the frame to the user/application.
                  EndIf
                EndIf
              EndIf
            EndIf
          Else
            If Event_Frame\Opcode = #Opcode_Continuation
              ; #### This frame is the end of a fragment series.
              LastElement(*Client\Fragments())
              If Not AddElement(*Client\Fragments())
                MalformedFrame = #True
              Else
                *Client\Fragments() = Event_Frame : Event_Frame\FrameData = #Null : Event_Frame\Payload = #Null
                *Client\Fragments_Size + Event_Frame\Payload_Size
                
                If *Client\Fragments_Size > #Frame_Fragmented_Payload_Max
                  MalformedFrame = #True
                Else
                  
                  ; #### Combine fragments, overwrite Event_Frame to simulate one large incoming frame.
                  If FirstElement(*Client\Fragments())
                    If *Client\Fragments()\Opcode <> #Opcode_Binary And *Client\Fragments()\Opcode <> #Opcode_Text
                      MalformedFrame = #True
                    Else
                      Event_Frame\Fin = #True
                      Event_Frame\RSV = 0
                      Event_Frame\Opcode = *Client\Fragments()\Opcode
                      Event_Frame\FrameData = AllocateMemory(*Client\Fragments_Size+1)
                      Event_Frame\Payload = Event_Frame\FrameData
                      Event_Frame\Payload_Size = *Client\Fragments_Size
                      If Not Event_Frame\FrameData
                        MalformedFrame = #True
                      Else
                        While FirstElement(*Client\Fragments())
                          CopyMemory(*Client\Fragments()\Payload, Event_Frame\Payload + TempOffset, *Client\Fragments()\Payload_Size) : TempOffset + *Client\Fragments()\Payload_Size
                          FreeMemory(*Client\Fragments()\FrameData) : *Client\Fragments()\FrameData = #Null
                          DeleteElement(*Client\Fragments())
                        Wend
                      EndIf
                    EndIf
                  EndIf
                  
                EndIf
              EndIf
            Else
              ; #### This frame is a normal unfragmented frame.
              If Not Bool(Event_Frame\Opcode & %1000) And ListSize(*Client\Fragments()) > 0
                ; #### This frame is not a control frame, but there is a started series of fragmented frames.
                MalformedFrame = #True
              EndIf
            EndIf
           EndIf
        EndIf
        
        If MalformedFrame
          ; #### Close connection as the frame is malformed in some way.
          Client_Disconnect_Mutexless(*Object, *Client, #CloseStatusCode_ProtocolError)
        Else
          ; #### Forward event to application/user.
          UnlockMutex(*Object\Mutex)
          *Callback(*Object, *Client, #Event_Frame, Event_Frame)
          LockMutex(*Object\Mutex)
        EndIf
        
        If Event_Frame\FrameData
          FreeMemory(Event_Frame\FrameData) : Event_Frame\FrameData = #Null
        EndIf
        
        Continue
      EndIf
      
      Break
    ForEver
    
    UnlockMutex(*Object\Mutex)
    ProcedureReturn #True
  EndProcedure
  
  Procedure.i Get_HTTP_Header(*Client.Client)
    If Not *Client
      ProcedureReturn #Null
    EndIf
    
    ProcedureReturn *Client\HTTP_Header
  EndProcedure
  
  Procedure Client_Disconnect_Mutexless(*Object.Object, *Client.Client, statusCode.u=0, reason.s="")
    If Not *Object
      ProcedureReturn #False
    EndIf
    
    If Not *Client
      ProcedureReturn #False
    EndIf
    
    If statusCode
      Protected tempSize = 2 + StringByteLength(reason, #PB_UTF8)
      Protected *tempMemory = AllocateMemory(tempSize)
      If Not *tempMemory
        *Client\Event_Disconnect_Manually = #True : ClientQueueEnqueue(*Object, *Client)
        ProcedureReturn #False
      EndIf
      PokeU(*tempMemory, ((statusCode & $FF00) >> 8) | ((statusCode & $FF) << 8))
      If StringByteLength(reason, #PB_UTF8) > 0
        PokeS(*tempMemory + 2, reason, -1, #PB_UTF8 | #PB_String_NoZero)
      EndIf
      Frame_Send_Mutexless(*Object, *Client, 1, 0, #Opcode_Connection_Close, *tempMemory, tempSize) ; This will also set the \Event_Disconnect_Manually flag
      FreeMemory(*tempMemory)
    Else
      Frame_Send_Mutexless(*Object, *Client, 1, 0, #Opcode_Connection_Close, #Null, 0) ; This will also set the \Event_Disconnect_Manually flag
    EndIf
    
    ProcedureReturn #True
  EndProcedure
  
  Procedure Client_Disconnect(*Object.Object, *Client.Client, statusCode.u=0, reason.s="")
    Protected Result
    
    If Not *Object
      ProcedureReturn #False
    EndIf
    
    LockMutex(*Object\Mutex)
    Result = Client_Disconnect_Mutexless(*Object, *Client, statusCode, reason)
    UnlockMutex(*Object\Mutex)
    
    ProcedureReturn Result
  EndProcedure
  
  Procedure Create(Port, *Event_Thread_Callback.Event_Callback=#Null, Frame_Payload_Max.q=#Frame_Payload_Max, HandleFragmentation=#True)
    Protected *Object.Object
    
    *Object = AllocateStructure(Object)
    If Not *Object
      ProcedureReturn #Null
    EndIf
    
    *Object\Frame_Payload_Max = Frame_Payload_Max
    *Object\HandleFragmentation = HandleFragmentation
    *Object\Event_Thread_Callback = *Event_Thread_Callback
    
    *Object\Mutex = CreateMutex()
    If Not *Object\Mutex
      FreeStructure(*Object)
      ProcedureReturn #Null
    EndIf
    
    If *Event_Thread_Callback
      *Object\ClientQueueSemaphore = CreateSemaphore()
      If Not *Object\ClientQueueSemaphore
        FreeMutex(*Object\Mutex) : *Object\Mutex = #Null
        FreeStructure(*Object)
        ProcedureReturn #Null
      EndIf
    EndIf
    
    *Object\Server_ID = CreateNetworkServer(#PB_Any, Port, #PB_Network_TCP)
    If Not *Object\Server_ID
      FreeMutex(*Object\Mutex) : *Object\Mutex = #Null
      If *Object\ClientQueueSemaphore : FreeSemaphore(*Object\ClientQueueSemaphore) : *Object\ClientQueueSemaphore = #Null : EndIf
      FreeStructure(*Object)
      ProcedureReturn #Null
    EndIf
    
    *Object\Network_Thread_ID = CreateThread(@Thread(), *Object)
    If Not *Object\Network_Thread_ID
      FreeMutex(*Object\Mutex) : *Object\Mutex = #Null
      If *Object\ClientQueueSemaphore : FreeSemaphore(*Object\ClientQueueSemaphore) : *Object\ClientQueueSemaphore = #Null : EndIf
      CloseNetworkServer(*Object\Server_ID) : *Object\Server_ID = #Null
      FreeStructure(*Object)
      ProcedureReturn #Null
    EndIf
    
    If *Event_Thread_Callback
      *Object\Event_Thread_ID = CreateThread(@Thread_Events(), *Object)
      If Not *Object\Event_Thread_ID
        *Object\Free = #True
        ProcedureReturn #Null
      EndIf
    EndIf
    
    ProcedureReturn *Object
  EndProcedure
  
  Procedure Free(*Object.Object)
    If Not *Object
      ProcedureReturn #False
    EndIf
    
    ; #### Fetch thread ID here, because the *Object is invalid some time after *Object\Free is set true
    Protected Network_Thread_ID.i = *Object\Network_Thread_ID
    
    If *Object\Event_Thread_ID
      *Object\Free_Event = #True
      SignalSemaphore(*Object\ClientQueueSemaphore) ; Misuse the semaphore to get the event thread to quit.
      WaitThread(*Object\Event_Thread_ID)
    EndIf
    *Object\Free = #True
    If Network_Thread_ID
      WaitThread(Network_Thread_ID)
    EndIf
    
    ProcedureReturn #True
  EndProcedure
  
EndModule

; IDE Options = PureBasic 6.00 LTS (Windows - x64)
; CursorPosition = 142
; FirstLine = 120
; Folding = ----
; EnableThread
; EnableXP
; EnablePurifier = 1,1,1,1
; EnableUnicode