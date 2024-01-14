local fs = require "bee.filesystem"
local fsutil = require "fsutil"
local lua_def = require "lua_def"
local globals = require "globals"
local inited_rule = false
local inited_version = {}

local function copy_dir(from, to)
    fs.create_directories(to)
    for file, status in fs.pairs(from) do
        if not status:is_directory() then
            fs.copy_file(file, to / file:filename(), fs.copy_options.update_existing)
        end
    end
end

local function init_rule(ninja)
    if inited_rule then
        return
    end
    inited_rule = true
    if globals.compiler == "msvc" then
        local msvc = require "env.msvc"
        ninja:rule("luadeps", ([[lib /nologo /machine:%s /def:$in /out:$out]]):format(msvc.archAlias(globals.arch)),
            {
                description = "Lua import lib $out"
            })
    else
        ninja:rule("luadeps", [[dlltool -d $in -l $out]],
            {
                description = "Lua import lib $out"
            })
    end
end

local function init_version(ninja, loaded, luadir, luaversion)
    if inited_version[luaversion] then
        return
    end
    inited_version[luaversion] = true
    lua_def(fsutil.join(package.procdir, "tools", luaversion))
    local libname
    if globals.compiler == "msvc" then
        libname = luadir.."/lua-"..globals.arch..".lib"
        loaded["__"..luaversion.."__"] = {
            input = { libname }
        }
    else
        libname = luadir.."/liblua.a"
        loaded["__"..luaversion.."__"] = {
            implicit_inputs = { libname },
            ldflags = {
                "-L"..luadir,
                "-llua",
            }
        }
    end
    ninja:build(libname, luadir.."/lua.def")
end

local function windows_deps(name, attribute, luaversion)
    local ldflags = attribute.ldflags or {}
    local deps = attribute.deps or {}
    if globals.compiler == "msvc" then
        if attribute.export_luaopen ~= "off" then
            ldflags[#ldflags+1] = "/EXPORT:luaopen_"..name
        end
    end
    deps[#deps+1] = "__"..luaversion.."__"
    attribute.ldflags = ldflags
    attribute.deps = deps
end

return function (ninja, loaded, rule, name, attribute)
    local luaversion = attribute.luaversion or "lua54"
    if rule == "shared_library" and globals.os == "windows" then
        local luadir = "$builddir/"..luaversion
        init_rule(ninja)
        init_version(ninja, loaded, luadir, luaversion)
        windows_deps(name, attribute, luaversion)
    end
    local includes = attribute.includes or {}
    if globals.prebuilt then
        includes[#includes+1] = "tools/"..luaversion
    else
        includes[#includes+1] = "$builddir/"..luaversion
        copy_dir(
            fsutil.join(package.procdir, "tools", luaversion),
            fsutil.join(WORKDIR, globals.builddir, luaversion)
        )
    end
    attribute.includes = includes
end
