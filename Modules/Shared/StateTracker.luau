const module = {}

export type State<i> = {
    setState:(self:State<i>, State:i) -> (),
    listenTo:(self:State<i>, Callback:(state:i, old_state:i) -> ()) -> (),
    setChecker:(self:State<i>, Checker:(old:i, new:i) -> boolean) -> (),
    Update:(self:State<i>) -> (),
    currentState:i,
}

const state_meta = {}

function state_meta:setChecker(Checker:(old:any, new:any) -> boolean)
    self.Checker = Checker
end

function state_meta:setState(State:any)
    local old_state = self.currentState
    if self.AllowedStates and typeof(self.AllowedStates) == "table" then
        assert(table.find(self.AllowedStates, State) ~= nil, "invalid state provided " .. tostring(State))
    end

    if self.Checker then
        local ok = self.Checker(self.currentState, State)
        if not ok then return end
    end

    self.currentState = State

    for _, item in ipairs(self.c_back) do
        item(State, old_state)
    end
end

function state_meta:Update()
    for _, item in ipairs(self.c_back) do
        item(self.currentState)
    end
end

function state_meta:listenTo(Callback:(state:any) -> ())
    table.insert(self.c_back, Callback)
end

state_meta.__index = state_meta

function module.new<basestate>(state_def, AllowedStates:any):State<basestate>
    local self = setmetatable({
        currentState = state_def,
        c_back = {},
        AllowedStates = AllowedStates,
        Checker = nil
    }, state_meta)

    return self
end

return module