; Just a test to see how well the purifier works with ReAllocateMemory

EnableExplicit

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
; CursorPosition = 15
; Folding = -
; EnableAsm
; EnableThread
; EnableXP
; EnableOnError
; EnablePurifier