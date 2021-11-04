-- local inspect = require 'inspect'
-- function dump(obj) print(inspect(obj)) end
-- dumpToStr = inspect
-- local function dumpTable(obj) table.foreachi(obj, dump) end

local p = premake

newoption {
  trigger     = "compilecommands-bldcfg",
  value       = "Debug",
  description = "Build Config to export",
  default     = "Debug"
}
newoption {
  trigger     = "compilecommands-outpath",
  value       = "./",
  description = "Output directory of compile_commands.json"
}

p.modules.export_compile_commands = {}
local m = p.modules.export_compile_commands

local workspace = p.workspace
local project = p.project

function m.getToolset(cfg)
  if string.startswith(cfg.toolset, "msc") then
    -- Shims for msc toolset to play nice with clang-cl
    local msc_orig = p.tools.msc
    local toolset = {}
    toolset.version = msc_orig.version
    toolset.gettoolname = function(cfg,tool)
      if tool == "cc" or tool == "cxx" then
        return "clang-cl" end
      return nil
    end
    toolset.getcppflags = msc_orig.getcppflags
    toolset.getdefines = msc_orig.getdefines
    toolset.getundefines = msc_orig.getundefines
    toolset.getincludedirs = msc_orig.getincludedirs
    toolset.getforceincludes = msc_orig.getforceincludes
    toolset.getcxxflags = function(cfg)
      local clang_cxxflags = {
        cppdialect = {
          ["C++98"]     = "/std:c++98",
          ["C++0x"]     = "/std:c++0x",
          ["C++11"]     = "/std:c++11",
          ["C++1y"]     = "/std:c++1y",
          ["C++14"]     = "/std:c++14",
          ["C++1z"]     = "/std:c++1z",
          ["C++17"]     = "/std:c++17",
          ["C++2a"]     = "/std:c++2a",
          ["C++20"]     = "/std:c++20",
          ["gnu++98"]   = "/std:gnu++98",
          ["gnu++0x"]   = "/std:gnu++0x",
          ["gnu++11"]   = "/std:gnu++11",
          ["gnu++1y"]   = "/std:gnu++1y",
          ["gnu++14"]   = "/std:gnu++14",
          ["gnu++1z"]   = "/std:gnu++1z",
          ["gnu++17"]   = "/std:gnu++17",
          ["gnu++2a"]   = "/std:gnu++2a",
          ["gnu++20"]   = "/std:gnu++20",
          ["C++latest"] = "/std:c++20",
        }
      }
      local flags =  msc_orig.getcxxflags(cfg)
      flags = table.join(flags, p.config.mapFlags(cfg, clang_cxxflags))
      return flags
    end
    toolset.getcflags = function(cfg)
      local clang_cflags = {
        cdialect = {
          ["C89"]   = "/std:c89",
          ["C90"]   = "/std:c90",
          ["C99"]   = "/std:c99",
          ["C11"]   = "/std:c11",
          ["gnu89"] = "/std:gnu89",
          ["gnu90"] = "/std:gnu90",
          ["gnu99"] = "/std:gnu99",
          ["gnu11"] = "/std:gnu11",
        }
      }
		  local flags = msc_orig.getcflags(cfg)
      flags = table.join(flags,p.config.mapFlags(cfg, clang_cflags))
      return flags
    end
    return toolset
  else
      local tool, version = p.config.toolset(cfg)
      return tool
  end
end

function m.getCompileLang(prj, node)
  if     p.languages.iscpp(node.compileas) then return "cpp"
  elseif p.languages.isc(node.compileas)   then return "c"
  elseif path.iscppfile(node.abspath)      then return "cpp"
  elseif path.iscfile(node.abspath)        then return "c"
  elseif project.iscpp(prj)                then return "cpp"
  elseif project.isc(prj)                  then return "c"
  else                                     return nil end
end

function m.getToolName(prj, cfg, node)
  local compileLang = m.getCompileLang(prj,node)
  local tool = m.getToolset(cfg)
  if     compileLang == "cpp" then return tool.gettoolname(cfg, "cxx")
  elseif compileLang == "c"   then return tool.gettoolname(cfg, "cc")
  else                        error("Invalid file: " .. node.abspath) end
end

-- function m.getIncludeDirs(cfg)
--   local function singleQuoted(value)
--     local q = value:find(" ", 1, true)
--     if not q then
--       q = value:find("$%(.-%)", 1)
--     end
--     if q then
--       value = "'" .. value .. "'"
--     end
--     return value
--   end
--   local flags = {}
--   for _, dir in ipairs(cfg.includedirs) do
--   --print("include: "..dir)
--     table.insert(flags, '-I' .. singleQuoted(dir))
--   end
--   for _, dir in ipairs(cfg.sysincludedirs or {}) do
--     print("sysinclude: " .. '-isystem ' .. singleQuoted(dir))
--     table.insert(flags, '-isystem ' .. singleQuoted(dir))
--   end
--   return flags
-- end

function m.getConfigFlags(prj, projCfg, node)
  -- some tools that consumes compile_commands.json have problems with relative include paths
  local old_getrelative = project.getrelative
  project.getrelative = function(_, dir) return dir end
  local toolset = m.getToolset(projCfg)

  local function perConfigFlags(fileCfg_or_projCfg)
    if not fileCfg_or_projCfg then return {} end
    local retFlags = {}
    retFlags = table.join(retFlags, toolset.getdefines(fileCfg_or_projCfg.defines))
    retFlags = table.join(retFlags, toolset.getundefines(fileCfg_or_projCfg.undefines))
    if not (table.isempty(fileCfg_or_projCfg.includedirs) or table.isempty(fileCfg_or_projCfg.sysincludedirs)) then
      retFlags = table.join(retFlags, toolset.getincludedirs(fileCfg_or_projCfg, fileCfg_or_projCfg.includedirs, fileCfg_or_projCfg.sysincludedirs))
    end
    retFlags = table.join(retFlags, toolset.getforceincludes(fileCfg_or_projCfg))

    local compileLang = m.getCompileLang(prj, node)
    if     compileLang == "cpp" then retFlags = table.join(retFlags, toolset.getcxxflags(fileCfg_or_projCfg))
    elseif compileLang == "c"   then retFlags = table.join(retFlags, toolset.getcflags(fileCfg_or_projCfg))
    else                             error("Invalid file: " .. node.abspath) end

    retFlags = table.join(retFlags, fileCfg_or_projCfg.buildoptions)
    return retFlags
  end
  local flags = toolset.getcppflags(projCfg)
  flags = table.join(flags, perConfigFlags(projCfg))
  flags = table.join(flags, perConfigFlags(p.fileconfig.getconfig(node, projCfg)))
  project.getrelative = old_getrelative
  return flags
end

function m.getObjectPath(prj, cfg, node)
  return path.join(cfg.objdir, path.appendExtension(node.objname, '.o'))
end

function m.getDependenciesPath(prj, cfg, node)
  return path.join(cfg.objdir, path.appendExtension(node.objname, '.d'))
end

function m.getFileFlags(prj, cfg, node)
  return table.join(m.getConfigFlags(prj, cfg, node), {
    '-o', m.getObjectPath(prj, cfg, node),
    '-MF', m.getDependenciesPath(prj, cfg, node),
    '-c', node.abspath})
end

function m.generateCompileCommand(prj, cfg, node)
  -- if not doonce then
  --   local toolset = m.getToolset(cfg)
  --   doonce  = true
  --   print("---------------------------------\n")
  --   printf("toolset [%s:%s]: \n", prj.name, cfg.shortname)
  --   printf("  dump: \n%s" , dumpToStr(toolset))
  --   printf("  cfg: %s \n", dumpToStr(toolset.gettoolname()))
  --   printf("  version: %s \n", dumpToStr(toolset.version))
  --   print("---------------------------------\n")
  -- end


  return {
    directory = prj.location,
    file = node.abspath,
    command = m.getToolName(prj, cfg, node) .. ' '.. table.concat(m.getFileFlags(prj, cfg, node), ' ')
  }
end

function m.shouldInclude(cfg, prj, node, depth)
  local fcfg = p.fileconfig.getconfig(node, cfg)
  local exclFromBld = iif(fcfg, fcfg.flags.ExcludeFromBuild, false)
  -- incorrect as afaik, compile_commands shouldn't include header files
  -- local compileLang = m.getCompileLang(prj,node)
  -- return (not exclFromBld) and ( (compileLang == "cpp") or (compileLang == "c"))
  return (not exclFromBld) and ( path.iscfile(node.abspath) or path.iscppfile(node.abspath))
end

function m.getProjectConfig(prj)
  if _OPTIONS['compilecommands-bldcfg'] then
    return project.findClosestMatch(prj, _OPTIONS['compilecommands-bldcfg'])
  end
  for cfg in project.eachconfig(prj) do
    -- just use the first configuration which is usually "Debug"
    return cfg
  end
end

function m.getProjectCommands(prj, cfg)
  local tr = project.getsourcetree(prj)
  local cmds = {}
  p.tree.traverse(tr, {
    onleaf = function(node, depth)
      if m.shouldInclude(cfg, prj, node, depth) then
        table.insert(cmds, m.generateCompileCommand(prj, cfg, node))
      end
    end
  })
  return cmds
end

function m.esc(str)
  return (str:gsub('\\', '\\\\')
             :gsub('"',  '\\"'))
end

function m.onWorkspace(wks)
  local cfgCmds = {}
  for prj in workspace.eachproject(wks) do
    -- for cfg in project.eachconfig(prj) do
      local cfg = m.getProjectConfig(prj)
      local cfgKey = string.format('%s', cfg.shortname)
      if not cfgCmds[cfgKey] then
        cfgCmds[cfgKey] = {}
      end
      cfgCmds[cfgKey] = table.join(cfgCmds[cfgKey], m.getProjectCommands(prj, cfg))
    -- end
  end

  for cfgKey,cmds in pairs(cfgCmds) do
    outfile_path = iif(_OPTIONS['compilecommands-outpath'], _OPTIONS['compilecommands-outpath'], cfgCmds[cfgKey])
    local outfile = path.normalize(path.join(outfile_path, "compile_commands.json"))
    printf("Writing CompileCommands [%s]: %s", cfgKey, outfile)

    p.escaper(m.esc)
    p.generate(wks, outfile, function()
      p.push('[')
      for i = 1, #cmds do
        local item = cmds[i]
        p.push('{')
        p.x('"directory": "%s",', item.directory)
        p.x('"file":      "%s",', item.file)
        p.x('"command":   "%s" ', item.command)
        if i ~= #cmds then
          p.pop('},')
        else
          p.pop('}')
        end
      end
      p.pop(']')
    end)
  end
end

newaction {
  trigger = 'export-compile-commands',
  description = 'Export compiler commands in JSON Compilation Database Format',
  onProject = function(prj)
    -- for cfg in project.eachconfig(prj) do
      local cfg = m.getProjectConfig(prj)
      printf("Gathering includes for [%s::%s]", prj.name, cfg.shortname)
      -- dump(prj.includedirs)
    -- end
  end,
  onWorkspace = m.onWorkspace,
}

return m
