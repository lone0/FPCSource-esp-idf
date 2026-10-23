{
    This file is part of the Free Pascal run time library.
    Copyright (c) 2002 by Peter Vreman,
    member of the Free Pascal development team.

    FreeRTOS threading support implementation

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}

{ resourcestrings are not supported by the system unit,
  they are in the objpas unit and not available for fpc/tp modes }
const
  SNoThreads = 'This binary has no thread support compiled in.';
  SRecompileWithThreads = 'Recompile the application with a thread-driver in the program uses clause before other units using thread.';

Procedure NoThreadError;
  begin
  {$ifdef FPC_HAS_FEATURE_CONSOLEIO}
    If IsConsole then
      begin
      Writeln(StdErr,SNoThreads);
      Writeln(StdErr,SRecompileWithThreads);
      end;
  {$endif FPC_HAS_FEATURE_CONSOLEIO}
    RunError(232)
  end;


function  NoGetCurrentThreadId : TThreadID;
  begin
    if IsMultiThread then
      NoThreadError
    else
      ThreadingAlreadyUsed:=true;
    result:=TThreadID(1);
  end;


function NoBeginThread(sa : Pointer;stacksize : PtrUInt;
                     ThreadFunction : tthreadfunc;p : pointer;
                     creationFlags : dword; var ThreadId : TThreadID) : TThreadID;
  begin
    NoThreadError;
    result:=tthreadid(-1);
  end;


procedure SysInitCriticalSection(var cs);
  begin
  end;


procedure SysDoneCriticalSection(var cs);
  begin
  end;


procedure SysEnterCriticalSection(var cs);
  begin
  end;


function SysTryEnterCriticalSection(var cs):longint;
  begin
  end;


procedure SysLeaveCriticalSection(var cs);
  begin
  end;

function  SysRTLEventCreate : PRTLEvent;
  begin
    { Only creation is benign: units like Classes create an (internal,
      never-used) event during initialization (TMultiReadExclusiveWrite-
      Synchronizer.Create) and must not die at startup. The non-waiting
      manipulators (destroy/set/reset) stay no-op as well; ONLY the
      waiting entries keep the loud NoThreadError stub. }
    Result := nil;
  end;

procedure SysRTLEventNoOp(AEvent : PRTLEvent);
  begin
    { Benign for the whole non-waiting event surface:
      - destroy of the nil event created above (unit finalizations
        e.g. Classes.CommonDone must run to the end),
      - set/reset: TMultiReadExclusiveWriteSynchronizer.Create calls
        RTLEventResetEvent on its fresh event during Classes unit
        initialization, we must stay quiet here.
      ONLY the waiting entries below stay loud (NoThreadError). }
  end;

function  SysBasicEventCreate(EventAttributes : Pointer;
          AManualReset, InitialState : Boolean; const Name : ansistring) : pEventState;
  begin
    { same contract as SysRTLEventCreate: benign creation for unit
      initialization; explicit use fails loud. }
    Result := nil;
  end;

procedure SysBasicEventNoOp(state : pEventState);
  begin
    { benign counterpart of SysRTLEventNoOp: destroy + set/reset stay
      no-op for unit initialization/teardown housekeeping. }
  end;

const
  FreeRTOSThreadManager : TThreadManager = (
    InitManager            : Nil;
    DoneManager            : Nil;
    { while this is pretty hacky, it reduces the size of typical embedded programs
     and works fine on arm and avr }
    BeginThread            : @NoBeginThread;
    EndThread              : TEndThreadHandler(@NoThreadError);
    SuspendThread          : TThreadHandler(@NoThreadError);
    ResumeThread           : TThreadHandler(@NoThreadError);
    KillThread             : TThreadHandler(@NoThreadError);
    CloseThread            : TThreadHandler(@NoThreadError);
    ThreadSwitch           : TThreadSwitchHandler(@NoThreadError);
    WaitForThreadTerminate : TWaitForThreadTerminateHandler(@NoThreadError);
    ThreadSetPriority      : TThreadSetPriorityHandler(@NoThreadError);
    ThreadGetPriority      : TThreadGetPriorityHandler(@NoThreadError);
    GetCurrentThreadId     : @NoGetCurrentThreadId;
    SetThreadDebugNameA    : TThreadSetThreadDebugNameHandlerA(@NoThreadError);
    {$ifdef FPC_HAS_FEATURE_UNICODESTRINGS}
    SetThreadDebugNameU    : TThreadSetThreadDebugNameHandlerU(@NoThreadError);
    {$endif FPC_HAS_FEATURE_UNICODESTRINGS}
    InitCriticalSection    : @SysInitCriticalSection;
    DoneCriticalSection    : @SysDoneCriticalSection;
    EnterCriticalSection   : @SysEnterCriticalSection;
    TryEnterCriticalSection: @SysTryEnterCriticalSection;
    LeaveCriticalSection   : @SysLeaveCriticalSection;
    InitThreadVar          : TInitThreadVarHandler(@NoThreadError);
    RelocateThreadVar      : TRelocateThreadVarHandler(@NoThreadError);
    AllocateThreadVars     : @NoThreadError;
    ReleaseThreadVars      : @NoThreadError;
    BasicEventCreate       : TBasicEventCreateHandler(@SysBasicEventCreate);
    BasicEventdestroy      : TBasicEventHandler(@SysBasicEventNoOp);
    BasicEventResetEvent   : TBasicEventHandler(@SysBasicEventNoOp);
    BasicEventSetEvent     : TBasicEventHandler(@SysBasicEventNoOp);
    BasicEventWaitFor      : TBasicEventWaitForHandler(@NoThreadError);
    RTLEventCreate         : TRTLCreateEventHandler(@SysRTLEventCreate);
    RTLEventdestroy        : TRTLEventHandler(@SysRTLEventNoOp);
    RTLEventSetEvent       : TRTLEventHandler(@SysRTLEventNoOp);
    RTLEventResetEvent     : TRTLEventHandler(@SysRTLEventNoOp);
    RTLEventWaitFor        : TRTLEventHandler(@NoThreadError);
    RTLEventwaitfortimeout : TRTLEventHandlerTimeout(@NoThreadError);
  );

Procedure InitSystemThreads;
  begin
    SetThreadManager(FreeRTOSThreadManager);
  end;


