local M = {}

local function exec(cmd)
    local f = assert(io.popen(cmd, 'r'))
    local s = assert(f:read('*a'))
    f:close()
    return s
end

function M.get_compile_flags(lib)
    local result = exec('pkg-config --cflags ' .. lib)
    local tab = {}
    for w in string.gmatch(result, "%S+") do table.insert(tab, w) end
    return tab
end

function M.get_link_flags(lib)
    local result = exec('pkg-config --libs ' .. lib)
    local tab = {}
    for w in string.gmatch(result, "%S+") do table.insert(tab, w) end
    return tab
end

return M
