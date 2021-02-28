; #### Silly include to dump memory and structure allocations by Dadido3
; #### No support for flags yet

Global MemoryAllocationMutex = CreateMutex()
Structure MemoryAllocation
  Line.i
  Size.i
EndStructure
Global NewMap MemoryAllocations.MemoryAllocation()

Procedure __AllocateStructure(*mem, line.i)
  If *mem
    LockMutex(MemoryAllocationMutex)
    MemoryAllocations(Str(*mem))\Line = line
    UnlockMutex(MemoryAllocationMutex)
  Else
    Debug "Failed to allocate structure at line " + line
  EndIf
  ProcedureReturn *mem
EndProcedure
Macro _AllocateStructure(struct) ; #### It's not possible to override AllocateStructure, please replace all AllocateStructure with _AllocateStructure in your code.
  __AllocateStructure(AllocateStructure(struct), #PB_Compiler_Line)
EndMacro

Procedure _FreeStructure(*mem, line.i)
  If Not *mem
    Debug "Trying to free null pointer structure at line " + line
  EndIf
  LockMutex(MemoryAllocationMutex)
  If FindMapElement(MemoryAllocations(), Str(*mem))
    DeleteMapElement(MemoryAllocations())
  Else
    Debug "Freed an unknown structure address at line " + line
  EndIf
  UnlockMutex(MemoryAllocationMutex)
  FreeStructure(*mem)
EndProcedure
Macro FreeStructure(mem)
  _FreeStructure(mem, #PB_Compiler_Line)
EndMacro

Procedure _AllocateMemory(size.i, line.i)
  Protected *mem = AllocateMemory(size)
  If *mem
    LockMutex(MemoryAllocationMutex)
    MemoryAllocations(Str(*mem))\Line = line
    MemoryAllocations()\Size = size
    UnlockMutex(MemoryAllocationMutex)
  Else
    Debug "Failed to allocate mem at line " + line
  EndIf
  ProcedureReturn *mem
EndProcedure
Macro AllocateMemory(size)
  _AllocateMemory(size, #PB_Compiler_Line)
EndMacro

Procedure _ReAllocateMemory(*mem, size.i, line.i)
  If Not *mem
    Debug "Trying to reallocate null pointer memory at line " + line
  EndIf
  LockMutex(MemoryAllocationMutex)
  ;If FindMapElement(MemoryAllocations(), Str(*mem))
  ;  MemoryAllocations()\State = 1
  ;EndIf
  Protected *newMem = ReAllocateMemory(*mem, size)
  ;If FindMapElement(MemoryAllocations(), Str(*mem))
  ;  MemoryAllocations()\State = 2
  ;EndIf
  If *newMem
    If FindMapElement(MemoryAllocations(), Str(*mem))
      DeleteMapElement(MemoryAllocations())
    Else
      Debug "Reallocated an unknown memory address at line " + line
    EndIf
    MemoryAllocations(Str(*newMem))\Line = line
    MemoryAllocations()\Size = size
  Else
    Debug "Couldn't reallocate memory at line " + line
  EndIf
  UnlockMutex(MemoryAllocationMutex)
  ProcedureReturn *newMem
EndProcedure
Macro ReAllocateMemory(mem, size)
  _ReAllocateMemory(mem, size, #PB_Compiler_Line)
EndMacro

Procedure _FreeMemory(*mem, line.i)
  If Not *mem
    Debug "Trying to free null pointer memory at line " + line
  EndIf
  LockMutex(MemoryAllocationMutex)
  ;If FindMapElement(MemoryAllocations(), Str(*mem))
  ;  MemoryAllocations()\State = 1
  ;EndIf
  ;If FindMapElement(MemoryAllocations(), Str(*mem))
  ;  MemoryAllocations()\State = 2
  ;EndIf
  If FindMapElement(MemoryAllocations(), Str(*mem))
    DeleteMapElement(MemoryAllocations())
  Else
    Debug "Freed an unknown memory address at line " + line
  EndIf
  UnlockMutex(MemoryAllocationMutex)
  FreeMemory(*mem)
EndProcedure
Macro FreeMemory(mem)
  _FreeMemory(mem, #PB_Compiler_Line)
EndMacro

Procedure AllocationDumper_Output()
  LockMutex(MemoryAllocationMutex)
  Debug "---- Allocations: " + MapSize(MemoryAllocations()) + " ----"
  ForEach MemoryAllocations()
    Debug "  - Line: " + MemoryAllocations()\Line + " Size: " + MemoryAllocations()\Size
  Next
  UnlockMutex(MemoryAllocationMutex)
EndProcedure

Procedure AllocationDumper_Thread(*Dummy)
  Repeat
    AllocationDumper_Output()
    
    Delay(10000)
  ForEver
EndProcedure

CreateThread(@AllocationDumper_Thread(), #Null)
; IDE Options = PureBasic 5.72 (Windows - x64)
; CursorPosition = 104
; FirstLine = 75
; Folding = ---
; EnableXP