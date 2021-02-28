# Test 2

`Thread(*Client)` is called from the main thread, and `Event_Callback()` is called from inside the `Thread()` function:

``` PureBasic
;*Object\Network_Thread_ID = CreateThread(@Thread(), *Object)
;If Not *Object\Network_Thread_ID
;  FreeMutex(*Object\Mutex) : *Object\Mutex = #Null
;  If *Object\ClientQueueSemaphore : FreeSemaphore(*Object\ClientQueueSemaphore) : *Object\ClientQueueSemaphore = #Null : EndIf
;  CloseNetworkServer(*Object\Server_ID) : *Object\Server_ID = #Null
;  FreeStructure(*Object)
;  ProcedureReturn #Null
;EndIf

;If *Event_Thread_Callback
;  *Object\Event_Thread_ID = CreateThread(@Thread_Events(), *Object)
;  If Not *Object\Event_Thread_ID
;    *Object\Free = #True
;  ProcedureReturn #Null
;  EndIf
;EndIf

Thread(*Object)
```

``` PureBasic
; #### Busy when there was at least one network event
Busy = Bool(Counter > 0)

While Event_Callback(*Object, *Object\Event_Thread_Callback)
Wend

LockMutex(*Object\Mutex)
;Debug "Queue: " + ListSize(*Object\ClientQueue()) + "  Clients: " + ListSize(*Object\Client())
```

No crash occurred after bombarding the server with 250 clients reconnecting and sending packets non stop for ~9 hours.
