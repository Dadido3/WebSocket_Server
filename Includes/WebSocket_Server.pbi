; ##################################################### License / Copyright #########################################
; 
;     The MIT License (MIT)
;     
;     Copyright (c) 2015-2021 David Vogel
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
;   - Don't break loop in Thread_Receive_Frame() after every packet
;   - Remove some commented code
;   - Add mutexless variant of Frame_Send() for internal use
;   - Fix a race condition that may happen when using Client_Disconnect()
;   - Fix a memory leak in the HTTP header receiver
;   - Get rid of pushing and popping RX_Frame
;   - Set Event_Disconnect_Manually flag inside of Frame_Send() and Frame_Send_Mutexless()
;   - Remove the Done field from Frames
;   - Add *New_RX_FRAME to client
;   - Simplify how packets are received
;   - Check result of all AllocateMemory and AllocateStructure calls
;   - Null any freed memory or structure pointer
;   - Prevent client to receive HTTP header if there is a forced disconnect
;   - Limit HTTP header allocation size
;   - Add internal function Client_Free() that frees everything that is allocated by a client

; ##################################################### Check Compiler options ######################################

CompilerIf Not #PB_Compiler_Thread
  CompilerError "Thread-Safe is not activated!"
CompilerEndIf

; ##################################################### Module ######################################################

DeclareModule WebSocket_Server
  
  ; ##################################################### Public Constants ############################################
  
  #Version = 1003
  
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
  
  #RSV1 = %00000100
  #RSV2 = %00000010
  #RSV3 = %00000001
  
  #Frame_Payload_Max = 10000000  ; Default max. size of an incoming frame's payload. If the payload exceeds this value, the client will be disconnected.
  
  ; ##################################################### Public Structures ###########################################
  
  Structure Event_Frame
    Fin.a                 ; #True if this is the final frame of a series of frames.
    RSV.a                 ; Extension bits: RSV1, RSV2, RSV3.
    Opcode.a              ; Opcode.
    
    *Payload
    Payload_Size.i
  EndStructure
  
  ; ##################################################### Public Variables ############################################
  
  ; ##################################################### Public Prototypes ###########################################
  
  Prototype   Event_Callback(*Object, *Client, Event.i, *Custom_Structure=#Null)
  
  ; ##################################################### Public Procedures (Declares) ################################
  
  Declare.i Create(Port, *Event_Thread_Callback.Event_Callback=#Null, Frame_Payload_Max.q=#Frame_Payload_Max) ; Creates a new WebSocket server. *Event_Thread_Callback is the callback which will be called out of the server thread.
  Declare   Free(*Object)                                                                   ; Closes the WebSocket server.
  
  Declare   Frame_Text_Send(*Object, *Client, Text.s)                                       ; Sends a text-frame.
  Declare   Frame_Send(*Object, *Client, FIN.a, RSV.a, Opcode.a, *Payload, Payload_Size.q)  ; Sends a frame. FIN, RSV and Opcode can be freely defined. Normally you should use #Opcode_Binary.
   
  Declare   Event_Callback(*Object, *Callback.Event_Callback)                               ; Checks for events, and calls the *Callback function if there are any.
  
  Declare   Client_Disconnect(*Object, *Client)                                             ; Disconnects the specified *Client.
  
EndDeclareModule

; ##################################################### Module (Private Part) #######################################

Module WebSocket_Server
  
  EnableExplicit
  
  InitNetwork()
  UseSHA1Fingerprint()
  
  ; ##################################################### Constants ###################################################
  
  #Frame_Data_Size_Min = 2048
  
  #HTTP_Header_Data_Size_Step = 2048
  #HTTP_Header_Data_Size_Max = 4096
  
  #GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
  
  Enumeration
    #Mode_Handshake
    #Mode_Frames
  EndEnumeration
  
  ; ##################################################### Structures ##################################################
  
  Structure Eight_Bytes
    Byte.a[8]
  EndStructure
  
  Structure HTTP_Header
    *Data
    
    RX_Pos.i
    
    Request.s
    Map Field.s()
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
    
    Mode.i
    
    Event_Connect.i               ; #True --> Generate connect callback.
    Event_Disconnect_Manually.i   ; #True --> Generate disconnect callback and delete client as soon as all data is sent and read by the application. (This gets set by the application or websocket protocol, there is possibly still a TCP connection)
    
    External_Reference.i    ; #True --> An external reference was given to the application (via event). If the connection closes, there must be a closing event.
  EndStructure
  
  Structure Object
    Server_ID.i
    
    Network_Thread_ID.i     ; Thread handling in and outgoing data.
    
    Event_Thread_ID.i       ; Thread handling event callbacks and client deletions.
    Event_Semaphore.i       ; Semaphore for the event thread.
    ; TODO: Create a queue, so the event thread doesn't have to iterate through all clients
    
    List Client.Client()
    
    *Event_Thread_Callback.Event_Callback
    
    Frame_Payload_Max.q     ; Max-Size of a incoming frames payload. If the frame exceeds this value, the client will be disconnected.
    
    Mutex.i
    
    Free_Event.i            ; Free the event thread and its semaphore.
    Free.i                  ; Free the main networking thread and all the resources.
  EndStructure
  
  ; ##################################################### Variables ###################################################
  
  ; ##################################################### Declares ####################################################
  
  Declare   Frame_Send_Mutexless(*Object, *Client, FIN.a, RSV.a, Opcode.a, *Payload, Payload_Size.q)
  
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
    *Temp_Data_3 = AllocateMemory(30)
    If Not *Temp_Data_3
    	FreeMemory(*Temp_Data_2)
    	ProcedureReturn ""
    EndIf
    CompilerIf #PB_Compiler_Version < 560
      Base64Encoder(*Temp_Data_2, 20, *Temp_Data_3, 30)
    CompilerElse
      Base64EncoderBuffer(*Temp_Data_2, 20, *Temp_Data_3, 30)
    CompilerEndIf
    
    Result = PeekS(*Temp_Data_3, -1, #PB_Ascii)
    
    FreeMemory(*Temp_Data_2)
    FreeMemory(*Temp_Data_3)
    
    ProcedureReturn Result
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
  
  Procedure Thread_Receive_Handshake(*Object.Object, *Client.Client)
    Protected Result.i
    Protected *Temp_Data
    Protected Temp_Text.s
    Protected Temp_Line.s
    Protected Temp_Key.s
    Protected Response.s
    Protected i
    
    If *Client\Event_Disconnect_Manually
      ProcedureReturn #False
    EndIf
    
    Repeat
    
    	; #### Limit memory usage.
    	If *Client\HTTP_Header\RX_Pos > #HTTP_Header_Data_Size_Max
    		*Client\Event_Disconnect_Manually = #True
        ProcedureReturn #False
    	EndIf
      
      ; #### Manage memory
      If Not *Client\HTTP_Header\Data
        *Client\HTTP_Header\Data = AllocateMemory(#HTTP_Header_Data_Size_Step) ; This will be purged when the header got fully parsed, when the client is deleted or when the server is released.
        If Not *Client\HTTP_Header\Data
        	*Client\Event_Disconnect_Manually = #True
          ProcedureReturn #False
        EndIf
      EndIf
      If MemorySize(*Client\HTTP_Header\Data) < *Client\HTTP_Header\RX_Pos + 1
        *Temp_Data = ReAllocateMemory(*Client\HTTP_Header\Data, (*Client\HTTP_Header\RX_Pos / #HTTP_Header_Data_Size_Step + 1) * #HTTP_Header_Data_Size_Step)
        If *Temp_Data
          *Client\HTTP_Header\Data = *Temp_Data
        Else
        	*Client\Event_Disconnect_Manually = #True
          ProcedureReturn #False
        EndIf
      EndIf
      
      ; #### Receive one byte
      Result = ReceiveNetworkData(*Client\ID, *Client\HTTP_Header\Data + *Client\HTTP_Header\RX_Pos, 1)
      If Result > 0
        *Client\HTTP_Header\RX_Pos + Result
      ElseIf Result = 0
        Break
      Else
        *Client\Event_Disconnect_Manually = #True
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
                  *Client\Event_Connect = #True
                  Response = "HTTP/1.1 101 Switching Protocols" + #CRLF$ +
                             "Upgrade: websocket" + #CRLF$ +
                             "Connection: Upgrade" + #CRLF$ +
                             "Sec-WebSocket-Accept: " + Generate_Key(*Client\HTTP_Header\Field("sec-websocket-key")) + #CRLF$ +
                             #CRLF$
                Else
                  *Client\Event_Disconnect_Manually = #True
                  Response = "HTTP/1.1 400 Bad Request" + #CRLF$ +
                             "Content-Type: text/html" + #CRLF$ +
                             "Content-Length: 63" + #CRLF$ +
                             #CRLF$ +
                             "<html><head></head><body><h1>400 Bad Request</h1></body></html>"
                EndIf
              Else
                *Client\Event_Disconnect_Manually = #True
                Response = "HTTP/1.1 400 WebSocket Upgrade Failure" + #CRLF$ +
                           "Content-Type: text/html" + #CRLF$ +
                           "Content-Length: 77" + #CRLF$ +
                           #CRLF$ +
                           "<html><head></head><body><h1>400 WebSocket Upgrade Failure</h1></body></html>"
              EndIf
            Else
              *Client\Event_Disconnect_Manually = #True
              Response = "HTTP/1.1 404 Not Found" + #CRLF$ +
                         "Content-Type: text/html" + #CRLF$ +
                         "Content-Length: 61" + #CRLF$ +
                         #CRLF$ +
                         "<html><head></head><body><h1>404 Not Found</h1></body></html>"
            EndIf
          Else
            *Client\Event_Disconnect_Manually = #True
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
            	*Client\Event_Disconnect_Manually = #True
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
      ProcedureReturn #False
    EndIf
    
    Repeat
    	
    	; #### Create new temporary frame if there is none yet.
    	If Not *Client\New_RX_FRAME
	    	*Client\New_RX_FRAME = AllocateStructure(Frame) ; This will be purged when the packet is fully received, when the client is deleted or when the server is freed.
	    	If Not *Client\New_RX_FRAME
	    		*Client\Event_Disconnect_Manually = #True
	    		ProcedureReturn #False
	    	EndIf
	      *Client\New_RX_FRAME\RxTx_Size = 2
	    EndIf
	    
	    *TempFrame = *Client\New_RX_FRAME
      
      ; #### Check if the frame exceeds the max. frame-size
      If *TempFrame\Payload_Size > *Object\Frame_Payload_Max
        *Client\Event_Disconnect_Manually = #True
        ProcedureReturn #False
      EndIf
      
      ; #### Manage memory
      If Not *TempFrame\Data
        *TempFrame\Data = AllocateMemory(#Frame_Data_Size_Min) ; This will be purged when the client is deleted or when the server is freed, otherwise it will be reused in RX_Frame.
        If Not *TempFrame\Data
        	*Client\Event_Disconnect_Manually = #True
          ProcedureReturn #False
        EndIf
      EndIf
      If MemorySize(*TempFrame\Data) < *TempFrame\RxTx_Size + 3                   ; #### Add 3 bytes so that the (de)masking doesn't write outside of the buffer
        *Temp_Data = ReAllocateMemory(*TempFrame\Data, *TempFrame\RxTx_Size + 3)
        If *Temp_Data
          *TempFrame\Data = *Temp_Data
        Else
          *Client\Event_Disconnect_Manually = #True
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
        
        ; #### Check type of frame.
        Select *TempFrame\Data\Byte[0] & %00001111
          Case #Opcode_Continuation       ; continuation frame
          Case #Opcode_Text               ; text frame
          Case #Opcode_Binary             ; binary frame
          Case #Opcode_Connection_Close   ; connection close
            *Client\Event_Disconnect_Manually = #True
            ; #### Still forward the frame to the user/application.
          Case #Opcode_Ping               ; ping
            Frame_Send_Mutexless(*Object, *Client, #True, 0, #Opcode_Pong, *TempFrame\Data + *TempFrame\Payload_Pos, *TempFrame\Payload_Size)
          Case #Opcode_Pong               ; pong
          Default                         ; undefined
            Frame_Send_Mutexless(*Object, *Client, #True, 0, #Opcode_Connection_Close, #Null, 0) ; This will also set the \Event_Disconnect_Manually flag
            ProcedureReturn #False
        EndSelect
        
        ; #### Move this frame into the RX_Frame list.
        LastElement(*Client\RX_Frame())
        AddElement(*Client\RX_Frame())
        *Client\RX_Frame()\Data = *TempFrame\Data
        *Client\RX_Frame()\Payload_Pos = *TempFrame\Payload_Pos
        *Client\RX_Frame()\Payload_Size = *TempFrame\Payload_Size
        *Client\RX_Frame()\RxTx_Pos = *TempFrame\RxTx_Pos
        *Client\RX_Frame()\RxTx_Size = *TempFrame\RxTx_Size
        
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
      EndIf
      
    Wend
    
    ProcedureReturn #True
  EndProcedure
  
  Procedure Thread(*Object.Object)
    Protected Busy, Counter
    
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
            AddElement(*Object\Client())
            *Object\Client()\ID = EventClient()
            Counter + 1
            
          Case #PB_NetworkEvent_Disconnect
            If Client_Select(*Object, EventClient())
              *Object\Client()\ID = #Null ; #### The application can still read all incoming frames. The client will be deleted after all incoming frames have been read.
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
      Until Counter > 10
      
      ; #### Busy when there was at least one network event
      Busy = Bool(Counter > 0)
      
      ; #### Signal that there >may< be events to be handled by the event thread
      If *Object\Event_Semaphore And Busy
        SignalSemaphore(*Object\Event_Semaphore)
      EndIf
      
      ; #### Send Data
      LockMutex(*Object\Mutex)
      ForEach *Object\Client()
        If *Object\Client()\ID
          Busy | Bool(Thread_Transmit(*Object, *Object\Client()) = #False)
        EndIf
      Next
      UnlockMutex(*Object\Mutex)
      
      ; #### Delay only if there is nothing to do
      If Not Busy
        Delay(10)
      EndIf
      
    Until *Object\Free
    
    CloseNetworkServer(*Object\Server_ID) : *Object\Server_ID = #Null
    
    ; No need to care about the event thread, as it is shut down before cleanup happens here
    ForEach *Object\Client()
      Client_Free(*Object\Client())
    Next
    
    FreeMutex(*Object\Mutex) : *Object\Mutex = #Null
    FreeStructure(*Object)
  EndProcedure
  
  Procedure Thread_Events(*Object.Object)
    Repeat
      ; #### Wait for signal and completely empty semaphore
      WaitSemaphore(*Object\Event_Semaphore)
      While TrySemaphore(*Object\Event_Semaphore)
      Wend
      
      ; #### Process all events and callbacks
      While Event_Callback(*Object, *Object\Event_Thread_Callback) And Not *Object\Free_Event
      Wend
    Until *Object\Free_Event
    
    FreeSemaphore(*Object\Event_Semaphore) : *Object\Event_Semaphore = #Null
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
    
    If Opcode = #Opcode_Connection_Close
    	*Client\Event_Disconnect_Manually = #True
    EndIf
    
    LastElement(*Client\TX_Frame())
    If AddElement(*Client\TX_Frame())
      
      *Client\TX_Frame()\Data = AllocateMemory(10 + Payload_Size)
      If Not *Client\TX_Frame()\Data
      	*Client\Event_Disconnect_Manually = #True
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
        Case 126 To 65536
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
    Protected *Pointer.Ascii
    Protected *Eight_Bytes.Eight_Bytes
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
    If Temp_Size <= 0
      ProcedureReturn #False
    EndIf
    *Temp = AllocateMemory(Temp_Size)
    If Not *Temp
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
    
    If Not *Object
      ProcedureReturn #False
    EndIf
    
    If Not *Callback
      ProcedureReturn #False
    EndIf
    
    LockMutex(*Object\Mutex)
    
    ForEach *Object\Client() ; TODO: Don't iterate through all objects, but use a queue. Elements last in this list can be underprivileged in some cases
      
      *Client = *Object\Client()
      
      ; #### Event: Client connected and handshake was successful
      If *Client\Event_Connect
        *Client\Event_Connect = #False
        *Client\External_Reference = #True
        UnlockMutex(*Object\Mutex)
        *Callback(*Object, *Client, #Event_Connect)
        ProcedureReturn #True
      EndIf
      
      ; #### Event: Client disconnected (TCP connection got terminated) (Only return this event if there are no incoming frames left to be read by the application)
      If *Client\ID = #Null And ListSize(*Client\RX_Frame()) = 0
        If *Client\External_Reference
          UnlockMutex(*Object\Mutex)
          *Callback(*Object, *Client, #Event_Disconnect)
          LockMutex(*Object\Mutex)
          ChangeCurrentElement(*Object\Client(), *Client) ; It may be possible that the current element got changed while the mutex was unlocked
        EndIf
        ; #### Delete the client and all its data.
        Client_Free(*Client)
        DeleteElement(*Object\Client())
        UnlockMutex(*Object\Mutex)
        ProcedureReturn #True
      EndIf
      
      ; #### Event: Close connection (By the user of the library, by any error that forces a disconnect or by an incoming disconnect request of the client via ws packet) (Only close the connection if there are no frames left)
      If *Client\Event_Disconnect_Manually And ListSize(*Client\TX_Frame()) = 0 And ListSize(*Client\RX_Frame()) = 0
        ; #### Forward event to application, but only if there was a connect event for this client before
        If *Client\External_Reference
          UnlockMutex(*Object\Mutex)
          *Callback(*Object, *Client, #Event_Disconnect)
          LockMutex(*Object\Mutex)
          ChangeCurrentElement(*Object\Client(), *Client) ; It may be possible that the current element got changed while the mutex was unlocked
        EndIf
        If *Client\ID
          CloseNetworkConnection(*Client\ID)
        EndIf
        ; #### Delete the client and all its data.
        Client_Free(*Client)
        DeleteElement(*Object\Client())
        UnlockMutex(*Object\Mutex)
        ProcedureReturn #True
      EndIf
      
      ; #### Event: Frame available
      If FirstElement(*Client\RX_Frame())
        Event_Frame\Fin = *Client\RX_Frame()\Data\Byte[0] >> 7 & %00000001
        Event_Frame\RSV = *Client\RX_Frame()\Data\Byte[0] >> 4 & %00000111
        Event_Frame\Opcode = *Client\RX_Frame()\Data\Byte[0] & %00001111
        Event_Frame\Payload = *Client\RX_Frame()\Data + *Client\RX_Frame()\Payload_Pos
        Event_Frame\Payload_Size = *Client\RX_Frame()\Payload_Size
        
        UnlockMutex(*Object\Mutex)
        *Callback(*Object, *Client, #Event_Frame, Event_Frame)
        LockMutex(*Object\Mutex)
        
        FirstElement(*Client\RX_Frame()) ; Restore frame that may be changed while the mutex was unlocked. New elements are appended to the list, and the first element will only be deleted here. So FirstElement() will change to the same element as previously.
        If *Client\RX_Frame()\Data
        	FreeMemory(*Client\RX_Frame()\Data) : *Client\RX_Frame()\Data = #Null
        EndIf
        DeleteElement(*Client\RX_Frame())
        
        UnlockMutex(*Object\Mutex)
        ProcedureReturn #True
      EndIf
      
    Next
    
    UnlockMutex(*Object\Mutex)
    ProcedureReturn #False
  EndProcedure
  
  Procedure Client_Disconnect(*Object.Object, *Client.Client)
    If Not *Object
      ProcedureReturn #False
    EndIf
    
    If Not *Client
      ProcedureReturn #False
    EndIf
    
    Frame_Send(*Object, *Client, 1, 0, #Opcode_Connection_Close, #Null, 0) ; This will also set the \Event_Disconnect_Manually flag
    
    ; #### Signal that there >may< be events to be handled by the event thread
    If *Object\Event_Semaphore
      SignalSemaphore(*Object\Event_Semaphore)
    EndIf
    
    ProcedureReturn #True
  EndProcedure
  
  Procedure Create(Port, *Event_Thread_Callback.Event_Callback=#Null, Frame_Payload_Max.q=#Frame_Payload_Max)
    Protected *Object.Object
    
    *Object = AllocateStructure(Object)
    If Not *Object
      ProcedureReturn #Null
    EndIf
    
    *Object\Mutex = CreateMutex()
    If Not *Object\Mutex
      FreeStructure(*Object)
      ProcedureReturn #Null
    EndIf
    
    If *Event_Thread_Callback
      *Object\Event_Semaphore = CreateSemaphore()
      If Not *Object\Event_Semaphore
        FreeMutex(*Object\Mutex) : *Object\Mutex = #Null
        FreeStructure(*Object)
        ProcedureReturn #Null
      EndIf
    EndIf
    
    *Object\Server_ID = CreateNetworkServer(#PB_Any, Port, #PB_Network_TCP)
    If Not *Object\Server_ID
      FreeMutex(*Object\Mutex) : *Object\Mutex = #Null
      If *Object\Event_Semaphore : FreeSemaphore(*Object\Event_Semaphore) : *Object\Event_Semaphore = #Null : EndIf
      FreeStructure(*Object)
      ProcedureReturn #Null
    EndIf
    
    *Object\Network_Thread_ID = CreateThread(@Thread(), *Object)
    If Not *Object\Network_Thread_ID
      FreeMutex(*Object\Mutex) : *Object\Mutex = #Null
      If *Object\Event_Semaphore : FreeSemaphore(*Object\Event_Semaphore) : *Object\Event_Semaphore = #Null : EndIf
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
    
    *Object\Frame_Payload_Max = Frame_Payload_Max
    *Object\Event_Thread_Callback = *Event_Thread_Callback
    
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
      SignalSemaphore(*Object\Event_Semaphore)
      WaitThread(*Object\Event_Thread_ID)
    EndIf
    *Object\Free = #True
    If Network_Thread_ID
      WaitThread(Network_Thread_ID)
    EndIf
    
    ProcedureReturn #True
  EndProcedure
  
EndModule

; IDE Options = PureBasic 5.72 (Windows - x64)
; CursorPosition = 975
; FirstLine = 946
; Folding = ---
; EnableThread
; EnableXP
; EnablePurifier = 1,1,1,1
; EnableUnicode