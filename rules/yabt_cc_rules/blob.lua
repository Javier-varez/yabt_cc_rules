local M = {}

local path = require 'yabt.core.path'
local toolchain = require 'yabt_cc_rules.toolchain'
local cc = require 'yabt_cc_rules.cc'

---@param toolchain Toolchain
---@return BuildRule # Build rule for the given toolchain
local function blob_rule_for_toolchain(toolchain)
    return {
        name = toolchain.name .. '-blob',
        cmd = 'cd $base && ' .. toolchain.raw_linker ..
            ' -z noexecstack -m $machine -r -b binary -o $out $inp',
        descr = 'LD (toolchain: ' .. toolchain.name .. ') $out',
    }
end

---@class Blob
---@field out OutPath
---@field inp Path
---@field base Path
---@field toolchain ?Toolchain
---@field lib ?Library
local Blob = {}

---@param blob Blob
local function validate_blob_input(blob)
    if not type(blob) == 'table' then
        error('Blob:new takes a table as input', 3)
    end

    if not path.is_out_path(blob.out) then
        error('Expected `out` to be an out path but got ' .. type(blob.out), 3)
    end

    if not path.is_path(blob.inp) then
        error('Expected `inp` to be a path but got ' .. type(blob.inp), 3)
    end

    if not path.is_path(blob.base) then
        error('Expected `base` to be a path but got ' .. type(blob.base), 3)
    end
end

---@param blob Blob
function Blob:new(blob)
    validate_blob_input(blob)
    setmetatable(blob, self)
    self.__index = self
    blob:resolve()
    return blob
end

-- Resolves the missing library bits at lib declaration time
function Blob:resolve()
    local selected_toolchain = toolchain.selected_toolchain()
    self.toolchain = self.toolchain or selected_toolchain
    self.lib = cc.Library:new {
        out = self.out:with_ext('a'),
        objs = { self.out },
    }
end

local function machine_to_ld_emulation_mode(machine)
    if machine == 'x86_64' then
        return 'elf_x86_64'
    elseif machine == 'aarch64' then
        return 'aarch64linux'
    else
        error('Unsupported machine architecture: ' .. machine)
    end
end

function Blob:build(ctx)
    local build_rule = blob_rule_for_toolchain(self.toolchain)
    local build_step = {
        outs = { self.out },
        ins = { self.inp },
        rule_name = build_rule.name,
        variables = {
            machine = machine_to_ld_emulation_mode(self.toolchain.machine),
            base = self.base:absolute(),
            inp = self.inp:relative_to(self.base),
        }
    }
    ctx.add_build_step_with_rule(build_step, build_rule)
    self.lib:build(ctx)
end

---@return Library
function Blob:cc_library()
    return self.lib
end

M.Blob = Blob

return M
