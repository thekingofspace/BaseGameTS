--!strict

const Config = require(script.Parent.Config)
const Level = require(script.Parent.Level)
const Types = require(script.Parent.Types)

const State = Config.State

const Throttle = {}
Throttle.__index = Throttle

const SWEEP_INTERVAL = 30

export type Verdict = "Allow" | "Duplicate" | "RateLimited" | "Sampled"

type Bucket = {
    Tokens:number,
    Last:number,
}

type Duplicate = {
    Until:number,
    Count:number,
}

type ThrottleObject = {
    _buckets:{[string]:Bucket},
    _dupes:{[string]:Duplicate},
    _lastSweep:number,
    _suppressed:number,
}

export type Throttle = {
    Admit:(self:Throttle, entry:Types.Entry) -> (boolean, Verdict),
    Suppressed:(self:Throttle) -> number,
    Reset:(self:Throttle) -> (),
}

function Throttle.new():Throttle
    const self = setmetatable({
        _buckets = {},
        _dupes = {},
        _lastSweep = os.clock(),
        _suppressed = 0,
    }, Throttle)

    return (self::any)::Throttle
end

const function sweep(self:ThrottleObject, now:number)
    if now - self._lastSweep < SWEEP_INTERVAL then
        return
    end
    self._lastSweep = now

    for fingerprint, record in pairs(self._dupes) do
        if record.Until <= now and record.Count == 0 then
            self._dupes[fingerprint] = nil
        end
    end

    for name, bucket in pairs(self._buckets) do
        if now - bucket.Last > SWEEP_INTERVAL and bucket.Tokens >= State.RateBurst then
            self._buckets[name] = nil
        end
    end
end

const function takeToken(self:ThrottleObject, key:string, now:number):boolean
    const rate = State.RateLimit
    if rate <= 0 then
        return true
    end

    local bucket = self._buckets[key]
    if bucket == nil then
        bucket = { Tokens = State.RateBurst, Last = now }
        self._buckets[key] = bucket
    end

    bucket.Tokens = math.min(State.RateBurst, bucket.Tokens + (now - bucket.Last) * rate)
    bucket.Last = now

    if bucket.Tokens < 1 then
        return false
    end

    bucket.Tokens -= 1
    return true
end

function Throttle.Admit(self:ThrottleObject, entry:Types.Entry):(boolean, Verdict)
    if entry.Level >= Level.FATAL then
        return true, "Allow"
    end

    const now = os.clock()
    sweep(self, now)

    const fraction = State.Sample[entry.Level]
    if fraction ~= nil and fraction < 1 and math.random() > fraction then
        self._suppressed += 1
        return false, "Sampled"
    end

    if State.Dedupe then
        const record = self._dupes[entry.Fingerprint]
        if record ~= nil and record.Until > now then
            record.Count += 1
            self._suppressed += 1
            return false, "Duplicate"
        end

        if record ~= nil and record.Count > 0 then
            entry.Count = record.Count + 1
            record.Count = 0
        end

        self._dupes[entry.Fingerprint] = {
            Until = now + State.DedupeWindow,
            Count = 0,
        }
    end

    if not takeToken(self, entry.Logger, now) then
        self._suppressed += 1
        return false, "RateLimited"
    end

    return true, "Allow"
end

function Throttle.Suppressed(self:ThrottleObject):number
    return self._suppressed
end

function Throttle.Reset(self:ThrottleObject)
    table.clear(self._buckets)
    table.clear(self._dupes)
    self._suppressed = 0
    self._lastSweep = os.clock()
end

return Throttle
