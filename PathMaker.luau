local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local LehuaClass = require(ReplicatedStorage.Shared.LehuaClass)
local PROBE_UP = 5
local PROBE_DOWN = 160

local SEARCH_RINGS = {4, 8, 12, 16, 20, 24, 28, 32}
local SEARCH_SPOKES = 12
local SEARCH_BUCKET = 4
local SEARCH_TRIES = 16
local MAX_CLIMB = 64
local FLY_STEP = 2
local FLY_MAX_STEPS = 512
local FLY_SIMPLIFY = 0.35
local RESUME_EVERY = 4
local RESUME_TRIES = 8

local SNAP_UP = 2
local SNAP_DOWN = 2.5
local CLIP_LIFT = 0.5
local CLIP_SKIN = 0.5
local DECLIP_DEPTH = 6
local PROBE_NUDGE = 0.15
local SUPPORT_STEP = 2
local SUPPORT_HEIGHT = 2.5

local DROP_BUDGET = 16
local MAX_WALK_SLOPE = math.rad(60)

local WATER_PROBE = 20
local FLUSH_LINKS = 8

export type Options = {
    CanFly: boolean?,
    OnWater: boolean?,
    Offset: number?,
    Clearance: number?,
    Ignore: {Instance}?,
    AgentRadius: number?,
    AgentHeight: number?,
    AgentCanJump: boolean?,
    AgentCanClimb: boolean?,
    WaypointSpacing: number?,
    Costs: {[string]: number}?,
}

export type StandardClass = {
    CanFly: boolean,
    OnWater: boolean,
    Offset: number,
    Clearance: number,
    Modes: {[string]: boolean},
    InitPath: (self: StandardClass, Origin: Vector3, Options: Options?) -> (),
    Push: (self: StandardClass, Position: Vector3) -> boolean,
    Pop: (self: StandardClass) -> Vector3?,
    Next: (self: StandardClass) -> Vector3?,
    Peek: (self: StandardClass) -> Vector3?,
    Get: (self: StandardClass) -> {Vector3},
    Clear: (self: StandardClass) -> (),
    Flush: (self: StandardClass, Force: boolean?) -> boolean,
    Finished: (self: StandardClass) -> boolean,
    SetOrigin: (self: StandardClass, Position: Vector3) -> (),
    SetIgnore: (self: StandardClass, Instances: {Instance}) -> (),
}

local function Lerp(A: number, B: number, T: number): number
    return A + (B - A) * T
end
local function SurfaceY(self, X: number, Z: number, TopY: number, BottomY: number): number?
    local Hit = Workspace:Raycast(Vector3.new(X, TopY, Z), Vector3.new(0, BottomY - TopY, 0), self.RayParams)
    return if Hit then Hit.Position.Y else nil
end
local function SnapDown(self, Position: Vector3): Vector3
    local Y = SurfaceY(self, Position.X, Position.Z, Position.Y + PROBE_UP, Position.Y - PROBE_DOWN)
    return if Y then Vector3.new(Position.X, Y, Position.Z) else Position
end
local function LastPoint(self): Vector3
    return self.Points[#self.Points] or self.Origin
end
local function SnapToSurface(self, Point: Vector3): Vector3
    local Y = SurfaceY(self, Point.X, Point.Z, Point.Y + SNAP_UP, Point.Y - SNAP_DOWN)
    return if Y then Vector3.new(Point.X, Y, Point.Z) else Point
end
local function WaypointsToPoints(self, Waypoints): {Vector3}
    local Points = table.create(math.max(#Waypoints - 1, 0))
    for Index = 2, #Waypoints do
        Points[Index - 1] = SnapToSurface(self, Waypoints[Index].Position)
    end
    return Points
end
local function EnsurePath(self)
    if self.PathFor == self.CanFly then
        return self.Path
    end
    local Agent = table.clone(self.Agent)
    if Agent.AgentCanJump == nil then
        Agent.AgentCanJump = self.CanFly
    end
    if Agent.AgentCanClimb == nil then
        Agent.AgentCanClimb = self.CanFly
    end

    self.PathFor = self.CanFly
    self.Path = PathfindingService:CreatePath(Agent)
    return self.Path
end

local function ComputeGround(self, From: Vector3, To: Vector3): ({Vector3}?, boolean)
    local Path = EnsurePath(self)
    local Ok = pcall(Path.ComputeAsync, Path, From, To)
    if not Ok or Path.Status ~= Enum.PathStatus.Success then
        return nil, false
    end

    local Points = WaypointsToPoints(self, Path:GetWaypoints())
    if #Points == 0 then
        Points[1] = To
    end
    return Points, true
end
local function ComputeBest(self, From: Vector3, To: Vector3): ({Vector3}?, boolean)
    local Points, Reached = ComputeGround(self, From, To)
    if Reached then
        return Points, true
    end
    local Candidates = {}
    for Ring, Radius in ipairs(SEARCH_RINGS) do
        for Spoke = 1, SEARCH_SPOKES do
            local Angle = (Spoke / SEARCH_SPOKES) * math.pi * 2 + Ring * 0.37
            local Spot = To + Vector3.new(math.cos(Angle) * Radius, 0, math.sin(Angle) * Radius)
            table.insert(Candidates, SnapDown(self, Spot))
        end
    end
    table.sort(Candidates, function(A, B)
        local NearA = math.round((A - To).Magnitude / SEARCH_BUCKET)
        local NearB = math.round((B - To).Magnitude / SEARCH_BUCKET)
        if NearA ~= NearB then
            return NearA < NearB
        end
        return (A - From).Magnitude < (B - From).Magnitude
    end)
    for Index = 1, math.min(#Candidates, SEARCH_TRIES) do
        local Fallback, Ok = ComputeGround(self, From, Candidates[Index])
        if Ok then
            return Fallback, false
        end
    end
    return nil, false
end

local function RollingMax(Heights: {number}, Index: number, Window: number): number
    local Best = Heights[Index]
    for Scan = math.max(1, Index - Window), math.min(#Heights, Index + Window) do
        if Heights[Scan] > Best then
            Best = Heights[Scan]
        end
    end
    return Best
end
local function FlyLeg(self, From: Vector3, To: Vector3): ({Vector3}?, boolean)
    local Flat = Vector3.new(To.X - From.X, 0, To.Z - From.Z)
    local Distance = Flat.Magnitude
    if Distance < 1e-3 then
        return {To}, true
    end
    local Steps = math.clamp(math.ceil(Distance / FLY_STEP), 1, FLY_MAX_STEPS)
    local Direction = Flat.Unit
    local TopY = math.max(From.Y, To.Y) + MAX_CLIMB
    local BottomY = math.min(From.Y, To.Y) - PROBE_DOWN
    local Samples = table.create(Steps + 1)
    local Heights = table.create(Steps + 1)
    for Step = 0, Steps do
        local Alpha = Step / Steps
        local Point = From + Direction * (Distance * Alpha)
        local Ground = SurfaceY(self, Point.X, Point.Z, TopY, BottomY)
        Samples[Step + 1] = Point
        Heights[Step + 1] = Ground or (Lerp(From.Y, To.Y, Alpha) - self.Clearance)
    end
    local Window = math.max(1, math.ceil((self.Agent.AgentRadius + FLY_STEP) / FLY_STEP))
    local Altitudes = table.create(Steps + 1)
    for Index = 1, Steps + 1 do
        Altitudes[Index] = RollingMax(Heights, Index, Window) + self.Clearance
    end
    local Points = {}
    local KeptAt = 1
    local Airborne = false
    local Peak = Heights[1]
    local Tries = 0
    for Index = 2, Steps + 1 do
        local Sample = Samples[Index]
        local Altitude = Altitudes[Index]
        local Surface = Heights[Index]
        local Hugging = Altitude <= Surface + self.Clearance + 1e-3
        if not Hugging then
            Airborne = true
        end
        if Surface > Peak then
            Peak = Surface
        end

        local Landed = Airborne and Hugging and Surface < Peak - self.Clearance
        if Landed and Tries < RESUME_TRIES and (Index % RESUME_EVERY == 0 or Index == Steps + 1) then
            Tries += 1
            local Landing = Vector3.new(Sample.X, Surface, Sample.Z)
            local Ground, Ok = ComputeGround(self, Landing, To)
            if Ok and Ground then
                table.insert(Points, Vector3.new(Sample.X, Altitude, Sample.Z))
                table.insert(Points, Landing)
                table.move(Ground, 1, #Ground, #Points + 1, Points)
                return Points, true
            end
        end

        local Ahead = Altitudes[Index + 1]
        local MidRun = Ahead ~= nil
            and math.abs(Altitude - Altitudes[KeptAt]) <= FLY_SIMPLIFY
            and math.abs(Ahead - Altitude) <= FLY_SIMPLIFY
        if not MidRun then
            table.insert(Points, Vector3.new(Sample.X, Altitude, Sample.Z))
            KeptAt = Index
        end
    end

    table.insert(Points, To)
    return Points, true
end

local function LinkHit(self, A: Vector3, B: Vector3): (Vector3?, boolean)
    local Lift = Vector3.new(0, CLIP_LIFT, 0)
    local From = A + Lift
    local Delta = (B + Lift) - From
    local Span = Delta.Magnitude
    if Span <= CLIP_SKIN * 2 then
        return nil, false
    end
    local Direction = Delta / Span
    local Reach = Direction * (Span - CLIP_SKIN * 2)
    local Forward = Workspace:Raycast(From + Direction * CLIP_SKIN, Reach, self.RayParams)
    if Forward then
        return Forward.Position, false
    end

    local Backward = Workspace:Raycast(From + Direction * (Span - CLIP_SKIN), -Reach, self.RayParams)
    return if Backward then Backward.Position else nil, true
end
local function FarLip(self, Start: Vector3, B: Vector3, Top: number): Vector3?
    local Flat = Vector3.new(B.X - Start.X, 0, B.Z - Start.Z)
    local Span = Flat.Magnitude
    if Span < 1e-3 then
        return nil
    end
    local Direction = Flat / Span
    local function OnTop(Distance: number): boolean
        local Probe = Start + Direction * Distance
        return SurfaceY(self, Probe.X, Probe.Z, Top + PROBE_UP, Top - 1) ~= nil
    end
    local Good, Bad = 0, nil
    local Distance = 1
    while Distance < Span do
        if OnTop(Distance) then
            Good = Distance
        else
            Bad = Distance
            break
        end
        Distance += 1
    end
    if not Bad then
        if OnTop(Span) then
            return nil
        end
        Bad = Span
    end
    for _ = 1, 8 do
        local Half = (Good + Bad) / 2
        if OnTop(Half) then
            Good = Half
        else
            Bad = Half
        end
    end
    if Good <= 0 then
        return nil
    end
    local Probe = Start + Direction * Good
    local Y = SurfaceY(self, Probe.X, Probe.Z, Top + PROBE_UP, Top - 1)
    return Vector3.new(Probe.X, Y or Top, Probe.Z)
end

local function PointBuried(self, Point: Vector3): boolean
    local Hits = Workspace:GetPartBoundsInBox(
        CFrame.new(Point + Vector3.new(0, CLIP_LIFT, 0)),
        Vector3.one * 0.1,
        self.Overlap
    )
    return #Hits > 0
end

local function Resolve(self, A: Vector3, B: Vector3, Depth: number, Out: {Vector3}): boolean
    local Hit, FromFar = LinkHit(self, A, B)
    if not Hit then
        if PointBuried(self, B) then
            return false
        end
        table.insert(Out, B)
        return true
    end
    if Depth <= 0 then
        return false
    end

    local Flat = Vector3.new(B.X - A.X, 0, B.Z - A.Z)
    local Inward = if Flat.Magnitude > 1e-3
        then Flat.Unit * (if FromFar then -PROBE_NUDGE else PROBE_NUDGE)
        else Vector3.zero
    local Top = SurfaceY(self, Hit.X + Inward.X, Hit.Z + Inward.Z, math.max(A.Y, B.Y) + MAX_CLIMB, Hit.Y - 1)
    if not Top then
        return false
    end
    local Mid = Vector3.new(Hit.X, Top, Hit.Z)
    if (Mid - B).Magnitude <= CLIP_SKIN then
        return false
    end
    if (Mid - A).Magnitude <= CLIP_SKIN then

        local Lip = FarLip(self, Mid, B, Top)
        if not Lip or (Lip - A).Magnitude <= CLIP_SKIN then
            return false
        end
        Mid = Lip
    end
    return Resolve(self, A, Mid, Depth - 1, Out) and Resolve(self, Mid, B, Depth - 1, Out)
end
local function DeClip(self, Anchor: Vector3, Points: {Vector3}): ({Vector3}, boolean)
    local Out = {}
    local Previous = Anchor
    for _, Target in ipairs(Points) do
        if not Resolve(self, Previous, Target, DECLIP_DEPTH, Out) then
            return Out, false
        end
        Previous = Target
    end
    return Out, true
end
local function GateSlope(self, Anchor: Vector3, Points: {Vector3}): ({Vector3}, boolean)
    local Previous = Anchor
    for Index, Point in ipairs(Points) do
        local Delta = Point - Previous
        local Flat = Vector3.new(Delta.X, 0, Delta.Z).Magnitude
        local Breaks = false
        if Delta.Y > -CLIP_LIFT then
            Breaks = Delta.Y > CLIP_LIFT and math.atan2(Delta.Y, Flat) > MAX_WALK_SLOPE
            if not Breaks then

                local Steps = math.max(1, math.ceil(Delta.Magnitude / SUPPORT_STEP))
                for Step = 1, Steps - 1 do
                    local Sample = Previous + Delta * (Step / Steps)
                    local Ground = SurfaceY(self, Sample.X, Sample.Z, Sample.Y + 1, Sample.Y - (SUPPORT_HEIGHT + 1))
                    if not Ground or Sample.Y - Ground > SUPPORT_HEIGHT then
                        Breaks = true
                        break
                    end
                end
            end
        end
        if Breaks then
            return table.move(Points, 1, Index - 1, 1, {}), false
        end
        Previous = Point
    end
    return Points, true
end
local function SquareDrops(self, Anchor: Vector3, Points: {Vector3}): {Vector3}
    local Out = {}
    local Previous = Anchor
    local Budget = DROP_BUDGET
    local Index = 1
    while Index <= #Points do
        local Point = Points[Index]
        local Drop = Previous.Y - Point.Y
        local Flat = Vector3.new(Point.X - Previous.X, 0, Point.Z - Previous.Z)
        local Reshaped = false
        if Budget > 0 and Drop > SUPPORT_HEIGHT and Flat.Magnitude > 1 then
            local Direction = Flat.Unit
            local GroundA = SurfaceY(
                self,
                Previous.X - Direction.X * PROBE_NUDGE,
                Previous.Z - Direction.Z * PROBE_NUDGE,
                Previous.Y + 1,
                Previous.Y - (SUPPORT_HEIGHT + 1)
            )
            if GroundA then
                local Hover = math.max(Previous.Y - GroundA, 0)
                local Lip: Vector3?
                local Ahead = SurfaceY(
                    self,
                    Previous.X + Direction.X * PROBE_NUDGE * 2,
                    Previous.Z + Direction.Z * PROBE_NUDGE * 2,
                    GroundA + PROBE_UP,
                    GroundA - 1
                )
                if Ahead == nil then
                    Lip = Vector3.new(Previous.X, GroundA, Previous.Z)
                else
                    Lip = FarLip(self, Vector3.new(Previous.X, GroundA, Previous.Z), Point, GroundA)
                end
                if Lip then
                    local DropX = Lip.X + Direction.X * PROBE_NUDGE * 2
                    local DropZ = Lip.Z + Direction.Z * PROBE_NUDGE * 2
                    local Lower = SurfaceY(self, DropX, DropZ, Lip.Y - 0.1, Lip.Y - PROBE_DOWN)
                    if Lower and Lip.Y - Lower > SUPPORT_HEIGHT then
                        Budget -= 1
                        Reshaped = true
                        if Vector3.new(Lip.X - Previous.X, 0, Lip.Z - Previous.Z).Magnitude > 0.05 then
                            table.insert(Out, Vector3.new(Lip.X, Lip.Y + Hover, Lip.Z))
                        end
                        local Landing = Vector3.new(DropX, Lower + Hover, DropZ)
                        table.insert(Out, Landing)
                        Previous = Landing
                    end
                end
            end
        end
        if not Reshaped then
            table.insert(Out, Point)
            Previous = Point
            Index += 1
        end
    end
    return Out
end
local function PinToWater(self, Point: Vector3): Vector3?
    local Hit = Workspace:Raycast(
        Vector3.new(Point.X, Point.Y + WATER_PROBE, Point.Z),
        Vector3.new(0, -(WATER_PROBE + PROBE_DOWN), 0),
        self.RayParams
    )
    if not Hit or Hit.Material ~= Enum.Material.Water then
        return nil
    end
    return Vector3.new(Point.X, Hit.Position.Y, Point.Z)
end
local function GateWater(self, Points: {Vector3}): ({Vector3}, boolean)
    for Index, Point in ipairs(Points) do
        local Pinned = PinToWater(self, Point)
        if not Pinned then
            return table.move(Points, 1, Index - 1, 1, {}), false
        end
        Points[Index] = Pinned
    end
    return Points, true
end
local function RunStage(self, Stage: {any}, Anchor: Vector3, Points: {Vector3}): ({Vector3}, boolean)
    local Cut = false
    for _, Gate in ipairs(Stage) do
        local Whole
        Points, Whole = Gate(self, Anchor, Points)
        if not Whole then
            Cut = true
        end
    end
    return Points, Cut
end
local function BuildLeg(self, From: Vector3, To: Vector3): ({Vector3}?, boolean)
    local Points, Reached = ComputeBest(self, From, To)
    if Reached then
        return Points, Reached
    end
    for _, Extend in ipairs(self._extend) do
        local Carried, Ok = Extend(self, From, To, Points)
        if Ok then
            return Carried, true
        end
    end
    return Points, Reached
end
local function Rebuild(self): boolean
    local Here = self.Points[self.Cursor] or self.Origin
    local Goals = {}
    local Walked = 0
    for _, Leg in ipairs(self.Legs) do
        if Walked + Leg.Count > self.Cursor then
            table.insert(Goals, Leg.Goal)
        end
        Walked += Leg.Count
    end

    self.Rebuilding = true
    self:SetOrigin(Here)
    for _, Goal in ipairs(Goals) do
        self:Push(Goal)
    end
    self.Rebuilding = false
    return #self.Points > 0
end

local Pathing = LehuaClass.Trait {
    Name = "Pathing",

    MergedPublic = { Modes = {} },
    MergedPrivate = {
        _stages = { PreClip = {}, PostClip = {}, Final = {} },
        _extend = {},
    },
    Private = {
        Points = {},
        Legs = {},
        Cursor = 0,
        Sweep = 0,
        Rebuilding = false,
        Origin = Vector3.zero,
        Path = LehuaClass.None,
        PathFor = LehuaClass.None,
        RayParams = LehuaClass.SetValue(function()
            local Params = RaycastParams.new()
            Params.FilterType = Enum.RaycastFilterType.Exclude
            Params.FilterDescendantsInstances = {}
            Params.IgnoreWater = false
            return Params
        end),
        Overlap = LehuaClass.SetValue(function()
            local Params = OverlapParams.new()
            Params.FilterType = Enum.RaycastFilterType.Exclude
            Params.FilterDescendantsInstances = {}
            return Params
        end),
        Agent = LehuaClass.SetValue(function()
            return {
                AgentRadius = 2,
                AgentHeight = 5,
                WaypointSpacing = 4,
            }
        end),
    },
    Public = {
        Offset = 0,
        Clearance = 2,
        CanFly = LehuaClass.ControlSpecifier {
            Get = function(self): boolean
                return self.Modes.Air == true
            end,
            Set = function(self, Value: boolean)
                self.Modes.Air = Value == true
            end,
        },
        OnWater = LehuaClass.ControlSpecifier {
            Get = function(self): boolean
                return self.Modes.Water == true
            end,
            Set = function(self, Value: boolean)
                self.Modes.Water = Value == true
            end,
        },
        Push = function(self, Position: Vector3): boolean
            local Goal = SnapDown(self, Position)
            local From = LastPoint(self)
            local Points, Reached = BuildLeg(self, From, Goal)
            if not Points or #Points == 0 then
                return false
            end
            local Cut
            Points, Cut = RunStage(self, self._stages.PreClip, From, Points)
            if Cut then
                Reached = false
            end

            local Clean
            Points, Clean = DeClip(self, From, Points)
            if not Clean then
                Reached = false
            end
            Points, Cut = RunStage(self, self._stages.PostClip, From, Points)
            if Cut then
                Reached = false
            end
            Points = SquareDrops(self, From, Points)

            Points, Cut = RunStage(self, self._stages.Final, From, Points)
            if Cut then
                Reached = false
            end
            if #Points == 0 then
                return false
            end

            table.insert(self.Legs, {Goal = Goal, Reached = Reached, Count = #Points})
            table.move(Points, 1, #Points, #self.Points + 1, self.Points)
            return Reached
        end,
        Pop = function(self): Vector3?
            local Leg = table.remove(self.Legs)
            if not Leg then
                return nil
            end

            for _ = 1, Leg.Count do
                table.remove(self.Points)
            end
            if self.Cursor > #self.Points then
                self.Cursor = #self.Points
            end
            return Leg.Goal
        end,

        Next = function(self): Vector3?
            if self.Rebuilding then
                return nil
            end

            for _ = 1, 2 do
                if self.Cursor >= #self.Points then
                    return nil
                end
                local Here = self.Points[self.Cursor] or self.Origin
                local Target = self.Points[self.Cursor + 1]
                if not LinkHit(self, Here, Target) and not PointBuried(self, Target) then
                    self.Cursor += 1
                    return Target + Vector3.new(0, self.Offset, 0)
                end
                if not Rebuild(self) then
                    return nil
                end
            end
            self:Clear()
            return nil
        end,
        Flush = function(self, Force: boolean?): boolean
            if self.Rebuilding or self.Cursor >= #self.Points then
                return false
            end
            local Stale = Force == true
            if not Stale then
                local Index = math.max(self.Sweep, self.Cursor)
                for _ = 1, FLUSH_LINKS do
                    if Index >= #self.Points then
                        break
                    end
                    local From = self.Points[Index] or self.Origin
                    local Target = self.Points[Index + 1]
                    if LinkHit(self, From, Target) or PointBuried(self, Target) then
                        Stale = true
                        break
                    end
                    Index += 1
                end
                self.Sweep = if Index >= #self.Points then 0 else Index
            end
            if not Stale then
                return false
            end
            if not Rebuild(self) then

                self:Clear()
            end
            return true
        end,
        Peek = function(self): Vector3?
            local Point = self.Points[self.Cursor + 1]
            return if Point then Point + Vector3.new(0, self.Offset, 0) else nil
        end,
        Get = function(self): {Vector3}
            local Points = table.create(#self.Points - self.Cursor)
            for Index = self.Cursor + 1, #self.Points do
                Points[Index - self.Cursor] = self.Points[Index] + Vector3.new(0, self.Offset, 0)
            end
            return Points
        end,
        Finished = function(self): boolean
            return not self.Rebuilding and self.Cursor >= #self.Points
        end,
        SetIgnore = function(self, Instances: {Instance})
            self.RayParams.FilterDescendantsInstances = Instances
            self.Overlap.FilterDescendantsInstances = Instances
        end,
        Clear = function(self)
            table.clear(self.Points)
            table.clear(self.Legs)
            self.Cursor = 0
            self.Sweep = 0
        end,
        SetOrigin = function(self, Position: Vector3)
            self:Clear()
            self.Origin = SnapDown(self, Position)
        end,
        InitPath = function(self, Origin: Vector3, Options: Options?)
            local Config: Options = Options or {}
            local Ignore = Config.Ignore or {}
            self.RayParams.FilterDescendantsInstances = Ignore
            self.Overlap.FilterDescendantsInstances = Ignore

            if Config.CanFly ~= nil then
                self.CanFly = Config.CanFly == true
            end
            if Config.OnWater ~= nil then
                self.OnWater = Config.OnWater == true
            end

            self.Offset = Config.Offset or 0
            self.Clearance = Config.Clearance or 2

            self.Agent = {
                AgentRadius = Config.AgentRadius or 2,
                AgentHeight = Config.AgentHeight or 5,
                AgentCanJump = Config.AgentCanJump,
                AgentCanClimb = Config.AgentCanClimb,
                WaypointSpacing = Config.WaypointSpacing or 4,
                Costs = Config.Costs or (if self.OnWater then {Water = 0.5} else nil),
            }

            self.Path = nil
            self.PathFor = nil
            self:Clear()
            self.Origin = SnapDown(self, Origin)
        end,
    },
}
local Grounded = LehuaClass.Trait {
    Name = "PathGrounded",
    Uses = { Pathing },
    MergedPublic = { Modes = { Ground = true } },
    MergedPrivate = {
        _stages = {
            Final = {
                function(self, Anchor: Vector3, Points: {Vector3}): ({Vector3}, boolean)
                    if self.CanFly then
                        return Points, true
                    end
                    return GateSlope(self, Anchor, Points)
                end,
            },
        },
    },
}
local Airborne = LehuaClass.Trait {
    Name = "PathAirborne",
    Uses = { Pathing },
    MergedPublic = { Modes = { Air = true } },
    MergedPrivate = {
        _extend = {
            function(self, From: Vector3, To: Vector3, Points: {Vector3}?): ({Vector3}?, boolean)
                if not self.CanFly then
                    return Points, false
                end
                local Launch = if Points and #Points > 0 then Points[#Points] else From
                local Flight = FlyLeg(self, Launch, To)
                if not Flight then
                    return Points, false
                end
                local Merged = Points or {}
                table.move(Flight, 1, #Flight, #Merged + 1, Merged)
                return Merged, true
            end,
        },
    },
}

local WaterGate = function(self, _Anchor: Vector3, Points: {Vector3}): ({Vector3}, boolean)
    return GateWater(self, Points)
end
local Floating = LehuaClass.Trait {
    Name = "PathFloating",
    Uses = { Pathing },
    MergedPublic = { Modes = { Water = true } },
    MergedPrivate = {
        _stages = {
            PreClip = { WaterGate },
            PostClip = { WaterGate },
        },
    },
}

return {
    Pathing = Pathing,
    Grounded = Grounded,
    Airborne = Airborne,
    Floating = Floating,
}
