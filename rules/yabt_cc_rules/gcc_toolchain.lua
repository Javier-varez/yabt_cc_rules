require 'yabt_cc_rules.toolchain'.register_toolchain_as_default{
    name = 'GCC',
    ccompiler = 'gcc',
    cxxcompiler = 'g++',
    assembler = 'as',
    archiver = 'ar',
    linker = 'g++',
    cflags = { '-Wall', '-Wextra', '-Werror', '-std=c17', '-O2', '-gdwarf-3' },
    cxxflags = { '-Wall', '-Wextra', '-Werror', '-std=c++20', '-O2', '-gdwarf-3' },
    asflags = {},
    ldflags = {},
    stddeps = {},
    ldscripts = {},
}
