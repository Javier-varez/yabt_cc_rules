local M = {
    _toolchains = {}
}

---@class Toolchain
---@field name string
---@field ccompiler string
---@field cxxcompiler string
---@field assembler string
---@field archiver string
---@field linker string
---@field cflags string[]
---@field cxxflags string[]
---@field asflags string[]
---@field ldflags string[]
---@field stddeps string[]
---@field ldscripts string[]

---@param toolchain Toolchain
function M.register_toolchain(toolchain)
    M._toolchains[toolchain.name] = toolchain
end

---@param toolchain Toolchain
function M.register_toolchain_as_default(toolchain)
    M._toolchains[toolchain.name] = toolchain
    M._defaultToolchain = toolchain
end

---@return Toolchain # The selected toolchain or the default if none is selected.
function M.selected_toolchain ()
    -- FIXME: At this time, flags are not implemented, so we only support default toolchain
    return M._defaultToolchain
end

return M
