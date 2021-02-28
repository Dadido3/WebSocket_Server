; Just a test to see how well the purifier works with ReAllocateMemory

EnableExplicit

;Procedure _ReAllocateMemory(*mem, newSize.i)
;  Protected *newMem = AllocateMemory(newSize)
;  If Not *newMem
;    ProcedureReturn *mem
;  EndIf
;  
;  Protected oldSize.i = MemorySize(*mem)
;  If oldSize < newSize
;    CopyMemory(*mem, *newMem, oldSize)
;  Else
;    CopyMemory(*mem, *newMem, newSize)
;  EndIf
;  
;  FreeMemory(*mem)
;  ProcedureReturn *newMem
;EndProcedure
;Macro ReAllocateMemory(mem, newSize)
;  _ReAllocateMemory(mem, newSize)
;EndMacro

;Global allocationMutex = CreateMutex()

Procedure TestThread(*Dummy)
  Protected *testMem = AllocateMemory(1000)
  Protected *newMem
  Protected newSize.i
  
  Repeat
    newSize = Random(4096, 1000)
    ;LockMutex(allocationMutex)
    *newMem = ReAllocateMemory(*testMem, newSize)
    ;UnlockMutex(allocationMutex)
    If Not *newMem
      FreeMemory(*testMem)
      Debug "ReAllocateMemory failed"
      Break
    EndIf
    *testMem = *newMem
    
    Debug *testMem
    
  ForEver
EndProcedure

Define i
For i = 1 To 10
  CreateThread(@TestThread(), #Null)
Next

OpenConsole()
Input()

; IDE Options = PureBasic 5.72 (Windows - x64)
; CursorPosition = 13
; Folding = -
; EnableThread
; EnablePurifier = 1,1,64,64