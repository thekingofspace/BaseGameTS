--!strict

export type Frame = {
    Source:string,
    Line:number,
    Name:string?,
    What:string,
}

export type Trace = {
    Frames:{Frame},
    Raw:string?,
}

export type Fault = {
    Kind:string,
    Message:string,
    Details:{[string]:any},
    Trace:Trace?,
    Cause:Fault?,
    Time:number,
    Clock:number,
    Retryable:boolean,
    Handled:boolean,
    Fingerprint:string,

    Is:(self:Fault, kind:string) -> boolean,
    Wrap:(self:Fault, kind:string, message:string?, details:{[string]:any}?) -> Fault,
    Detail:(self:Fault, key:string, value:any) -> Fault,
    Root:(self:Fault) -> Fault,
    Chain:(self:Fault) -> {Fault},
    ToString:(self:Fault) -> string,
    ToTable:(self:Fault) -> {[string]:any},
    Throw:(self:Fault) -> (),
}

export type Breadcrumb = {
    Message:string,
    Category:string,
    Fields:{[string]:any}?,
    Clock:number,
}

export type Entry = {
    Level:number,
    LevelName:string,
    Logger:string,
    Message:string,
    Fields:{[string]:any}?,
    Fault:Fault?,
    Trace:Trace?,
    Breadcrumbs:{Breadcrumb}?,
    Time:number,
    Clock:number,
    Fingerprint:string,
    TraceId:string?,
    SpanId:string?,
    Span:string?,
    Context:"Server" | "Client",
    Count:number,
}

export type Sink = {
    Name:string,
    Level:number,
    Enabled:boolean,
    Write:(self:Sink, entry:Entry) -> (),
    Filter:((self:Sink, entry:Entry) -> boolean)?,
    Flush:((self:Sink) -> ())?,
    Close:((self:Sink) -> ())?,
}

export type Hook = (entry:Entry) -> boolean?

export type SpanHandle = {
    Stop:(self:SpanHandle, fields:{[string]:any}?) -> number,
    Annotate:(self:SpanHandle, fields:{[string]:any}) -> (),
    Id:string,
    Name:string,
    TraceId:string,
}

export type Logger = {
    Name:string,
    Level:number?,

    Trace:(self:Logger, message:string, fields:{[string]:any}?) -> (),
    Debug:(self:Logger, message:string, fields:{[string]:any}?) -> (),
    Info:(self:Logger, message:string, fields:{[string]:any}?) -> (),
    Warn:(self:Logger, message:string, fields:{[string]:any}?) -> (),
    Error:(self:Logger, message:string, fields:{[string]:any}?) -> (),
    Fatal:(self:Logger, message:string, fields:{[string]:any}?) -> (),

    Exception:(self:Logger, err:any, message:string?, fields:{[string]:any}?) -> Fault,
    Log:(self:Logger, level:string | number, message:string, fields:{[string]:any}?) -> (),
    Ensure:(self:Logger, condition:any, message:string, fields:{[string]:any}?) -> boolean,

    Child:(self:Logger, name:string, fields:{[string]:any}?) -> Logger,
    With:(self:Logger, fields:{[string]:any}) -> Logger,

    SetLevel:(self:Logger, level:(string | number)?) -> Logger,
    EffectiveLevel:(self:Logger) -> number,
    IsEnabled:(self:Logger, level:string | number) -> boolean,

    AddSink:(self:Logger, sink:Sink) -> Sink,
    RemoveSink:(self:Logger, sink:Sink | string) -> boolean,
    Use:(self:Logger, hook:Hook) -> () -> (),

    Breadcrumb:(self:Logger, message:string, category:string?, fields:{[string]:any}?) -> (),
    Span:(self:Logger, name:string, fields:{[string]:any}?) -> SpanHandle,
    Scope:(self:Logger, name:string, fn:(...any) -> ...any, ...any) -> ...any,
    Time:(self:Logger, name:string, fn:(...any) -> ...any, ...any) -> ...any,

    Flush:(self:Logger) -> (),
    Destroy:(self:Logger) -> (),
}

export type ConsoleOptions = {
    ShowTime:boolean?,
    ShowLevel:boolean?,
    ShowLogger:boolean?,
    ShowFields:boolean?,
    ShowSpan:boolean?,
    Multiline:boolean?,
    Glyphs:boolean?,
    Traceback:boolean?,
    UseTestService:boolean?,
}

export type Config = {
    Level:(string | number)?,
    Console:ConsoleOptions?,
    TraceLevel:(string | number)?,
    BreadcrumbLevel:(string | number)?,
    BreadcrumbLimit:number?,
    HistoryLimit:number?,
    MaxDepth:number?,
    MaxEntries:number?,
    MaxStringLength:number?,
    RedactKeys:{string}?,
    Dedupe:boolean?,
    DedupeWindow:number?,
    RateLimit:number?,
    RateBurst:number?,
    Sample:{[string]:number}?,
    CaptureGlobalErrors:boolean?,
    CaptureOutput:boolean?,
    Tags:{[string]:any}?,
}

return true
