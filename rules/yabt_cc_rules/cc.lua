local M = {}

local path = require 'yabt.core.path'
local utils = require 'yabt.core.utils'

local function validate_table(t, config)
    config.error_level = config.error_level or 1
    config.validate_entry = config.validate_entry or function(_, _) end
    config.allow_nil = config.allow_nil or false
    if t == nil and config.allow_nil then
        return
    end
    if type(t) ~= 'table' then
        error('Expected table', config.error_level)
    end

    for _, entry in ipairs(t) do
        config.validate_entry(entry, config.error_level + 1)
    end
end

local function validate_out_path(p, error_level)
    if type(p) ~= 'table' then
        error('Expected out path but got ' .. type(p), error_level)
    end
    if getmetatable(p) ~= path.OutPath then
        error('Expected out path but got ' .. type(p), error_level)
    end
end

local function validate_path(p, error_level)
    if type(p) ~= 'table' then
        error('Expected path but got ' .. type(p), error_level)
    end
    if getmetatable(p) ~= path.InPath and getmetatable(p) ~= path.OutPath then
        error('Expected path but got ' .. type(p), error_level)
    end
end

local function validate_dep(dep, error_level)
    if type(dep) ~= 'table' then
        error('Expected Dep but got ' .. type(dep), error_level)
    end
    if type(dep.cc_library) ~= 'function' then
        error('Expected Dep but got ' .. type(dep), error_level)
    end
end

local function validate_string(s, error_level)
    if type(s) ~= 'string' then
        error('Expected string but got ' .. type(s), error_level)
    end
end

local function validate_boolean_or_nil(s, error_level)
    if type(s) ~= 'boolean' and type(s) ~= 'nil' then
        error('Expected boolean or nil but got ' .. type(s), error_level)
    end
end

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
local function file_path_to_language(path)
    local ext = path:ext()
    if ext == nil then
        error('Source path does not have an extension: ' .. path:absolute())
    end
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
        variables = {
            depfile = '$out.d',
        },
        compdb = true, -- This rule is part of the compilation database output
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
        variables = {
            depfile = '$out.d',
        },
        compdb = true, -- This rule is part of the compilation database output
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
        variables = {
            depfile = '$out.d',
        },
        compdb = true, -- This rule is part of the compilation database output
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
local function validate_object_input(obj)
    if not type(obj) == 'table' then
        error('ObjectFile:new takes a table as input', 3)
    end

    local error_level = 4
    validate_out_path(obj.out, error_level)
    validate_path(obj.src, error_level)
    validate_table(obj.includes, {
        validate_entry = validate_path,
        error_level = error_level,
        allow_nil = true,
    })
    validate_table(obj.cflags, {
        validate_entry = validate_string,
        error_level = error_level,
        allow_nil = true,
    })
    validate_table(obj.cxxflags, {
        validate_entry = validate_string,
        error_level = error_level,
        allow_nil = true,
    })
    validate_table(obj.asflags, {
        validate_entry = validate_string,
        error_level = error_level,
        allow_nil = true,
    })
    -- FIXME: Validate toolchain
end

---@param obj ObjectFile
function ObjectFile:new(obj)
    validate_object_input(obj)
    setmetatable(obj, self)
    self.__index = self
    return obj
end

local function shallow_clone_list(t)
    local r = {}
    for _, e in ipairs(t) do
        table.insert(r, e)
    end
    return r
end

---@param ctx Context
function ObjectFile:build(ctx)
    local selected_toolchain = require 'yabt_cc_rules.toolchain'.selected_toolchain()
    local toolchain = self.toolchain or selected_toolchain

    local language = file_path_to_language(self.src)
    local build_rule = build_rule_for_language_and_toolchain(language, toolchain)

    local flags = shallow_clone_list(self[lang_to_flag_member[language]] or {})
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
local function validate_lib_input(lib)
    if not type(lib) == 'table' then
        error('Library:new takes a table as input', 3)
    end

    local error_level = 4
    validate_out_path(lib.out, error_level)
    validate_table(lib.srcs, {
        validate_entry = validate_path,
        error_level = error_level,
        allow_nil = false,
    })
    validate_table(lib.deps, {
        validate_entry = validate_dep,
        error_level = error_level,
        allow_nil = true,
    })
    validate_table(lib.includes, {
        validate_entry = validate_path,
        error_level = error_level,
        allow_nil = true,
    })
    validate_table(lib.cflags, {
        validate_entry = validate_string,
        error_level = error_level,
        allow_nil = true,
    })
    validate_table(lib.cxxflags, {
        validate_entry = validate_string,
        error_level = error_level,
        allow_nil = true,
    })
    validate_table(lib.asflags, {
        validate_entry = validate_string,
        error_level = error_level,
        allow_nil = true,
    })
    -- FIXME: Validate toolchain
    validate_boolean_or_nil(lib.always_link, error_level)
end

---@param lib Library
function Library:new(lib)
    validate_lib_input(lib)
    lib.module_path = path.InPath:new_relative(MODULE_PATH .. '/include')
    setmetatable(lib, self)
    self.__index = self
    lib:resolve()
    return lib
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

        table.insert(all_deps, lib)

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

-- Resolves the missing library bits at lib declaration time
function Library:resolve()
    local selected_toolchain = require 'yabt_cc_rules.toolchain'.selected_toolchain()
    self.toolchain = self.toolchain or selected_toolchain
    local dep_libs = collect_deps_recursively(self.toolchain, self.deps, self.toolchain.stddeps)

    self.includes = shallow_clone_list(self.includes or {})

    local function add_include(include)
        if not utils.table_contains(self.includes, include) then
            table.insert(self.includes, include)
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
end

---@return Library
function Library:cc_library()
    return self
end

---@param ctx Context
function Library:build(ctx)
    local objs = {}
    for _, src in ipairs(self.srcs) do
        local obj = ObjectFile:new({
            out = src:withExt('o'),
            src = src,
            includes = self.includes,
            cxxflags = self.cxxflags,
            cflags = self.cflags,
            asflags = self.asflags,
            toolchain = self.toolchain,
        })
        obj:build(ctx)
        table.insert(objs, obj.out)
    end

    local build_rule = ar_rule_for_toolchain(self.toolchain)
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

---@param bin Binary
local function validate_bin_input(bin)
    if not type(bin) == 'table' then
        error('Library:new takes a table as input', 3)
    end

    local error_level = 4
    validate_out_path(bin.out, error_level)
    validate_table(bin.srcs, {
        validate_entry = validate_path,
        error_level = error_level,
        allow_nil = false,
    })
    validate_table(bin.deps, {
        validate_entry = validate_dep,
        error_level = error_level,
        allow_nil = true,
    })
    validate_table(bin.includes, {
        validate_entry = validate_path,
        error_level = error_level,
        allow_nil = true,
    })
    validate_table(bin.cflags, {
        validate_entry = validate_string,
        error_level = error_level,
        allow_nil = true,
    })
    validate_table(bin.cxxflags, {
        validate_entry = validate_string,
        error_level = error_level,
        allow_nil = true,
    })
    validate_table(bin.asflags, {
        validate_entry = validate_string,
        error_level = error_level,
        allow_nil = true,
    })
    validate_table(bin.ldflags, {
        validate_entry = validate_string,
        error_level = error_level,
        allow_nil = true,
    })
    validate_table(bin.ldflags_post, {
        validate_entry = validate_string,
        error_level = error_level,
        allow_nil = true,
    })
    -- FIXME: Validate toolchain
end

---@param bin Binary
function Binary:new(bin)
    validate_bin_input(bin)
    bin.module_path = path.InPath:new_relative(MODULE_PATH .. '/include')
    setmetatable(bin, self)
    self.__index = self
    bin:resolve()
    return bin
end

-- Resolves the missing library bits at lib declaration time
function Binary:resolve()
    local selected_toolchain = require 'yabt_cc_rules.toolchain'.selected_toolchain()
    self.toolchain = self.toolchain or selected_toolchain
    local dep_libs = collect_deps_recursively(self.toolchain, self.deps, self.toolchain.stddeps)

    self.includes = self.includes or {}

    local function add_include(include)
        if not utils.table_contains(self.includes, include) then
            table.insert(self.includes, include)
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
