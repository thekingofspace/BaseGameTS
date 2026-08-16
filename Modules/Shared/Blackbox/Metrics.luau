--!strict

const Metrics = {}

const RESERVOIR = 256

type Histogram = {
    Count:number,
    Sum:number,
    Min:number,
    Max:number,
    Samples:{number},
}

const Counters:{[string]:number} = {}
const Gauges:{[string]:number} = {}
const Histograms:{[string]:Histogram} = {}

export type HistogramSummary = {
    Count:number,
    Sum:number,
    Min:number,
    Max:number,
    Mean:number,
    P50:number,
    P95:number,
    P99:number,
}

export type Snapshot = {
    Counters:{[string]:number},
    Gauges:{[string]:number},
    Histograms:{[string]:HistogramSummary},
}

const function key(name:string, tags:{[string]:any}?):string
    if tags and next(tags) ~= nil then
        const parts:{string} = {}
        for tag, value in pairs(tags) do
            table.insert(parts, `{tag}={tostring(value)}`)
        end
        table.sort(parts)
        return name .. "{" .. table.concat(parts, ",") .. "}"
    end
    return name
end

Metrics.Key = key

function Metrics.Increment(name:string, delta:number?, tags:{[string]:any}?):number
    const id = key(name, tags)
    const value = (Counters[id] or 0) + (delta or 1)
    Counters[id] = value
    return value
end

function Metrics.Counter(name:string, tags:{[string]:any}?):number
    return Counters[key(name, tags)] or 0
end

function Metrics.Set(name:string, value:number, tags:{[string]:any}?)
    Gauges[key(name, tags)] = value
end

function Metrics.Gauge(name:string, tags:{[string]:any}?):number?
    return Gauges[key(name, tags)]
end

function Metrics.Observe(name:string, value:number, tags:{[string]:any}?)
    const id = key(name, tags)
    local histogram = Histograms[id]

    if histogram == nil then
        histogram = {
            Count = 0,
            Sum = 0,
            Min = math.huge,
            Max = -math.huge,
            Samples = {},
        }
        Histograms[id] = histogram
    end

    histogram.Count += 1
    histogram.Sum += value
    histogram.Min = math.min(histogram.Min, value)
    histogram.Max = math.max(histogram.Max, value)

    if #histogram.Samples < RESERVOIR then
        table.insert(histogram.Samples, value)
    else
        const slot = math.random(histogram.Count)
        if slot <= RESERVOIR then
            histogram.Samples[slot] = value
        end
    end
end

const function quantile(sorted:{number}, fraction:number):number
    const count = #sorted
    if count == 0 then
        return 0
    end
    const index = math.clamp(math.ceil(fraction * count), 1, count)
    return sorted[index]
end

function Metrics.Summary(name:string, tags:{[string]:any}?):HistogramSummary?
    const histogram = Histograms[key(name, tags)]
    if histogram == nil then
        return nil
    end

    const sorted = table.clone(histogram.Samples)
    table.sort(sorted)

    return {
        Count = histogram.Count,
        Sum = histogram.Sum,
        Min = histogram.Min,
        Max = histogram.Max,
        Mean = if histogram.Count > 0 then histogram.Sum / histogram.Count else 0,
        P50 = quantile(sorted, 0.50),
        P95 = quantile(sorted, 0.95),
        P99 = quantile(sorted, 0.99),
    }
end

export type Stopwatch = {
    Stop:(self:Stopwatch) -> number,
    Elapsed:(self:Stopwatch) -> number,
    Name:string,
}

const Stopwatch = {}
Stopwatch.__index = Stopwatch

function Stopwatch.Elapsed(self:any):number
    return os.clock() - self._start
end

function Stopwatch.Stop(self:any):number
    if self._stopped then
        return self._elapsed
    end
    self._stopped = true
    self._elapsed = os.clock() - self._start
    Metrics.Observe(self.Name, self._elapsed, self._tags)
    return self._elapsed
end

function Metrics.Start(name:string, tags:{[string]:any}?):Stopwatch
    return (setmetatable({
        Name = name,
        _tags = tags,
        _start = os.clock(),
        _stopped = false,
        _elapsed = 0,
    }, Stopwatch)::any)::Stopwatch
end

function Metrics.Time<A..., R...>(name:string, fn:(A...) -> R..., ...:A...):R...
    const watch = Metrics.Start(name)
    const results = table.pack(pcall(fn::any, ...))
    watch:Stop()

    if not results[1] then
        Metrics.Increment(`{name}.failed`)
        error(results[2], 0)
    end
    return table.unpack(results, 2, results.n)
end

function Metrics.Snapshot():Snapshot
    const histograms:{[string]:HistogramSummary} = {}
    for id in pairs(Histograms) do
        const summary = Metrics.Summary(id)
        if summary then
            histograms[id] = summary
        end
    end

    return {
        Counters = table.clone(Counters),
        Gauges = table.clone(Gauges),
        Histograms = histograms,
    }
end

function Metrics.Format():string
    const snapshot = Metrics.Snapshot()
    const lines:{string} = {}

    const function section(title:string, names:{string})
        if #names == 0 then
            return
        end
        table.sort(names)
        table.insert(lines, title)
        for _, name in ipairs(names) do
            if title == "counters" then
                table.insert(lines, `  {name} = {snapshot.Counters[name]}`)
            elseif title == "gauges" then
                table.insert(lines, `  {name} = {snapshot.Gauges[name]}`)
            else
                const summary = snapshot.Histograms[name]
                table.insert(lines, string.format(
                    "  %s n=%d mean=%.3fms p95=%.3fms max=%.3fms",
                    name, summary.Count, summary.Mean * 1000, summary.P95 * 1000, summary.Max * 1000
                ))
            end
        end
    end

    const function names(source:{[string]:any}):{string}
        const out:{string} = {}
        for name in pairs(source) do
            table.insert(out, name)
        end
        return out
    end

    section("counters", names(snapshot.Counters))
    section("gauges", names(snapshot.Gauges))
    section("timings", names(snapshot.Histograms))

    if #lines == 0 then
        return "no metrics recorded"
    end
    return table.concat(lines, "\n")
end

function Metrics.Reset()
    table.clear(Counters)
    table.clear(Gauges)
    table.clear(Histograms)
end

return Metrics
