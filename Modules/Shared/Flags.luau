const Flags = {
    NetworkResponse = {
        OK = "",
        Recieved = "",
        Bad = "",
        Debounced = "",
    }
}
for key, arg in pairs(Flags) do
    for Code:string, _ in pairs(arg) do
        arg[Code] = `Flags.{key}.{Code}`
    end
    Flags[key] = table.freeze(arg)
end
table.freeze(Flags)
return Flags::typeof(Flags)