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
  return p.tools[cfg.toolset]
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

function m.getFileTool(prj, cfg, node)
  local compileLang = m.getCompileLang(prj,node)
  if     compileLang == "cpp" then return iif(cfg.toolset == "msc", "clang-cl", m.getToolset(cfg).gettoolname(cfg, "cxx"))
  elseif compileLang == "c"   then return iif(cfg.toolset == "msc", "clang-cl", m.getToolset(cfg).gettoolname(cfg, "cc"))
  else                             error("Invalid file: " .. node.abspath) end
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
  project.getrelative = function(prj, dir) return dir end
  local toolset = m.getToolset(projCfg)

  local function perConfigFlags(fileCfg_or_projCfg)
    local retFlags = {}
    retFlags = table.join(retFlags, toolset.getdefines(fileCfg_or_projCfg.defines))
    retFlags = table.join(retFlags, toolset.getundefines(fileCfg_or_projCfg.undefines))
    retFlags = table.join(retFlags, toolset.getincludedirs(fileCfg_or_projCfg, fileCfg_or_projCfg.includedirs, fileCfg_or_projCfg.sysincludedirs))
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
  local fcfg = p.fileconfig.getconfig(node, projCfg)
  if fcfg then flags = table.join(flags, perConfigFlags(fcfg)) end

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
    command = m.getFileTool(prj, cfg, node) .. ' '.. table.concat(m.getFileFlags(prj, cfg, node), ' ')
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
      if not m.shouldInclude(cfg, prj, node, depth) then
        return
      end
      table.insert(cmds, m.generateCompileCommand(prj, cfg, node))
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
    p.generate(wks, outfile, function(wks)
      p.push('[')
      for i = 1, #cmds do
        local item = cmds[i]
        p.push('{')
        p.x('"directory": "%s", ', item.directory)
        p.x('"file":      "%s", ', item.file)
        p.x('"command":   "%s"  ', item.command)
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
