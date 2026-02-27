local M = {}

local path = require 'yabt.core.path'
local utils = require 'yabt.core.utils'

local fileExtToLangMap = {
    ['cc'] = 'C++',
    ['cpp'] = 'C++',
    ['hh'] = 'C++',
    ['hpp'] = 'C++',
    ['c'] = 'C',
    ['h'] = 'C',
    ['s'] = 'Asm',
    ['S'] = 'Asm',
}

---@param ext string
local function file_extension_to_language(ext)
    local lang = fileExtToLangMap[ext]
    if lang == nil then
        error('Unknown language for extension ' .. ext)
    end
    return lang
end

---@param toolchain Toolchain
---@return BuildRule # Build rule for the given toolchain
local function cxx_rule_for_toolchain(toolchain)
    return {
        name = toolchain.name .. '-cxx',
        cmd = toolchain.cxxcompiler ..
            ' -c ' .. table.concat(toolchain.cxxflags, ' ') .. ' $flags -o $out ' .. '-MD -MF $out.d -pipe $in',
        descr = 'CXX (toolchain: ' .. toolchain.name .. ') $out',
    }
end

---@param toolchain Toolchain
---@return BuildRule # Build rule for the given toolchain
local function c_rule_for_toolchain(toolchain)
    return {
        name = toolchain.name .. '-c',
        cmd = toolchain.ccompiler ..
            ' -c ' .. table.concat(toolchain.cflags, ' ') .. ' $flags -o $out ' .. '-MD -MF $out.d -pipe $in',
        descr = 'C (toolchain: ' .. toolchain.name .. ') $out',
    }
end

---@param toolchain Toolchain
---@return BuildRule # Build rule for the given toolchain
local function asm_rule_for_toolchain(toolchain)
    return {
        name = toolchain.name .. '-as',
        cmd = toolchain.assembler ..
            ' -c ' .. table.concat(toolchain.asflags, ' ') .. ' $flags -o $out ' .. '-MD -MF $out.d -pipe $in',
        descr = 'ASM (toolchain: ' .. toolchain.name .. ') $out',
    }
end

---@param toolchain Toolchain
---@return BuildRule # Build rule for the given toolchain
local function ar_rule_for_toolchain(toolchain)
    return {
        name = toolchain.name .. '-ar',
        cmd = 'rm -f $out 2> /dev/null; ' .. toolchain.archiver .. ' rcsT $out $in',
        descr = 'AR (toolchain: ' .. toolchain.name .. ') $out',
    }
end

---@param toolchain Toolchain
---@return BuildRule # Build rule for the given toolchain
local function ld_rule_for_toolchain(toolchain)
    return {
        name = toolchain.name .. '-ld',
        cmd = toolchain.linker ..
            ' ' .. table.concat(toolchain.ldflags, ' ') .. ' $ldflags -o $out $objs $libs $ldflags_post',
        descr = 'LD (toolchain: ' .. toolchain.name .. ') $out',
    }
end

local lang_to_rule_generator = {
    ['C++'] = cxx_rule_for_toolchain,
    ['C'] = c_rule_for_toolchain,
    ['Asm'] = asm_rule_for_toolchain,
}

---@param language string
---@return BuildRule
local function build_rule_for_language_and_toolchain(language, toolchain)
    local rule = lang_to_rule_generator[language]
    if rule == nil then
        error('Unknown language' .. language)
    end
    return rule(toolchain)
end

local lang_to_flag_member = {
    ['C++'] = 'cxxflags',
    ['C'] = 'cflags',
    ['Asm'] = 'asflags',
}

---@class ObjectFile
---@field out OutPath
---@field src Path
---@field includes ?Path[]
---@field cflags ?string[]
---@field cxxflags ?string[]
---@field asflags ?string[]
---@field toolchain ?Toolchain
local ObjectFile = {}

---@param obj ObjectFile
function ObjectFile:new(obj)
    setmetatable(obj, self)
    self.__index = self
    return obj
end

---@param ctx Context
function ObjectFile:build(ctx)
    local selected_toolchain = require 'yabt_cc_rules.toolchain'.selected_toolchain()
    local toolchain = self.toolchain or selected_toolchain

    local language = file_extension_to_language(self.src:ext())
    local build_rule = build_rule_for_language_and_toolchain(language, toolchain)

    local flags = self[lang_to_flag_member[language]] or {}
    if self.includes ~= nil then
        for _, inc in ipairs(self.includes) do
            table.insert(flags, '-I' .. inc:absolute())
        end
    end

    local build_step = {
        outs = { self.out },
        ins = { self.src },
        rule_name = build_rule.name,
        variables = {
            flags = table.concat(flags, ' '),
        },
    }

    ctx.add_build_step_with_rule(build_step, build_rule)
end

---@class Dep
---@field cc_library fun(self: Dep, toolchain: Toolchain): Library

---@class Library
---@field out OutPath
---@field srcs ?Path[]
---@field deps ?Dep[]
---@field includes ?Path[]
---@field cflags ?string[]
---@field cxxflags ?string[]
---@field asflags ?string[]
---@field toolchain ?Toolchain
---@field always_link ?boolean
---@field private module_path ?Path
local Library = {}

---@param lib Library
function Library:new(lib)
    lib.module_path = path.InPath:new_relative(MODULE_PATH .. '/include')
    setmetatable(lib, self)
    self.__index = self
    return lib
end

---@return Library
function Library:cc_library()
    return self
end

---@param deps Dep[]
---@param stddeps Dep[]
---@param toolchain Toolchain
---@return Library[]
local function collect_deps_recursively(toolchain, deps, stddeps)
    local all_deps = {}
    local contained = {}

    ---@param dep Dep
    local function collect_inner(dep)
        local lib = dep:cc_library(toolchain)
        local libpath = lib.out:absolute()
        if contained[libpath] == 'inprogress' then
            error("Circular dependency loop found!")
        end

        if contained[libpath] == 'done' then
            return
        end

        table.insert(all_deps, 1, lib)

        contained[libpath] = 'inprogress'

        if lib.deps then
            for _, d in ipairs(lib.deps) do
                collect_inner(d)
            end
        end

        contained[libpath] = 'done'
    end

    if deps then
        for _, dep in ipairs(deps) do
            collect_inner(dep)
        end
    end
    if stddeps then
        for _, dep in ipairs(stddeps) do
            collect_inner(dep)
        end
    end
    return all_deps
end

---@param ctx Context
function Library:build(ctx)
    local selected_toolchain = require 'yabt_cc_rules.toolchain'.selected_toolchain()
    local toolchain = self.toolchain or selected_toolchain
    local dep_libs = collect_deps_recursively(toolchain, self.deps, toolchain.stddeps)

    local includes = self.includes or {}

    local function add_include(include)
        if not utils.table_contains(includes, include) then
            table.insert(includes, include)
        end
    end

    local function add_includes(more)
        if more == nil then return end
        for _, include in ipairs(more) do
            add_include(include)
        end
    end

    add_include(self.module_path)

    for _, lib in ipairs(dep_libs) do
        add_includes(lib.includes)
    end

    local objs = {}
    for _, src in ipairs(self.srcs) do
        local obj = ObjectFile:new({
            out = src:withExt('o'),
            src = src,
            includes = includes,
            cxxflags = self.cxxflags,
            cflags = self.cflags,
            asflags = self.asflags,
            toolchain = self.toolchain,
        })
        obj:build(ctx)
        table.insert(objs, obj.out)
    end

    local build_rule = ar_rule_for_toolchain(toolchain)
    local build_step = {
        outs = { self.out },
        ins = objs,
        rule_name = build_rule.name,
    }
    ctx.add_build_step_with_rule(build_step, build_rule)
end

---@class Binary
---@field out OutPath
---@field srcs ?Path[]
---@field deps ?Dep[]
---@field includes ?Path[]
---@field cflags ?string[]
---@field cxxflags ?string[]
---@field asflags ?string[]
---@field ldflags ?string[]
---@field ldflags_post ?string[]
---@field toolchain ?Toolchain
---@field private module_path ?Path
local Binary = {}

---@param lib Binary
function Binary:new(lib)
    lib.module_path = path.InPath:new_relative(MODULE_PATH .. '/include')
    setmetatable(lib, self)
    self.__index = self
    return lib
end

---@param ctx Context
function Binary:build(ctx)
    local selected_toolchain = require 'yabt_cc_rules.toolchain'.selected_toolchain()
    local toolchain = self.toolchain or selected_toolchain
    local dep_libs = collect_deps_recursively(toolchain, self.deps, toolchain.stddeps)

    local includes = self.includes or {}
    local function add_include(include)
        if not utils.table_contains(includes, include) then
            table.insert(includes, include)
        end
    end

    local function add_includes(more)
        if not more then return end
        for _, include in ipairs(more) do
            add_include(include)
        end
    end

    add_include(self.module_path)

    for _, lib in ipairs(dep_libs) do
        add_includes(lib.includes)
    end

    ---@type Path[]
    local objs = {}
    for _, src in ipairs(self.srcs) do
        local obj = ObjectFile:new({
            out = src:withExt('o'),
            src = src,
            includes = includes,
            cxxflags = self.cxxflags,
            cflags = self.cflags,
            asflags = self.asflags,
            toolchain = self.toolchain,
        })
        obj:build(ctx)
        table.insert(objs, obj.out)
    end

    local libs_str = '-Wl,--whole-archive'
    for _, lib in ipairs(dep_libs) do
        if lib.always_link then
            libs_str = libs_str .. ' ' .. lib.out:absolute()
        end
    end
    libs_str = libs_str .. ' -Wl,--no-whole-archive'
    for _, lib in ipairs(dep_libs) do
        if not lib.always_link then
            libs_str = libs_str .. ' ' .. lib.out:absolute()
        end
    end

    ---@type Path[]
    local ins = {}
    local objs_str = ''
    for _, obj in ipairs(objs) do
        table.insert(ins, obj)
        objs_str = objs_str .. ' ' .. obj:absolute()
    end
    for _, dep in ipairs(dep_libs) do
        table.insert(ins, dep.out)
    end

    local build_rule = ld_rule_for_toolchain(toolchain)
    local build_step = {
        outs = { self.out },
        ins = ins,
        rule_name = build_rule.name,
        variables = {
            ldflags = table.concat(self.ldflags or {}, ' '),
            ldflags_post = table.concat(self.ldflags_post or {}, ' '),
            libs = libs_str,
            objs = objs_str
        }
    }
    ctx.add_build_step_with_rule(build_step, build_rule)
end

M.ObjectFile = ObjectFile
M.Library = Library
M.Binary = Binary

return M
