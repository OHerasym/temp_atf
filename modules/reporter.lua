local xml = require('xml')
local io = require('atf.stdlib.std.io')
local sdl_log = require('sdl_logger')
local atf_log = require('atf_logger')
local ford_constants = require("protocol_handler/ford_protocol_constants")

local module = {
  -- logLevel = 1, --see log level comment
  timestamp='',
  script_file_name = '',
  ndoc = {},
  curr_node={},
  root = {},
  curr_report_name = {},
  full_sdlLog_name ='' ,
  mt={_index={}}
}

local escape_lua_pattern
do
  local matches =
  {
    ["'"] = "%'";
    ["#"] = "";
    ["&"] = "";
  }

  escape_lua_pattern = function(s)
    return (s:gsub(".", matches))
  end
end

local function dump(o)
  if type(o) == 'table' then
    local s = '{ '
    for k,v in pairs(o) do
      if type(k) ~= 'number' then k = '\''..k..'\'' end
      s = s .. '['..k..'] = \'' .. dump(v) .. '\','
    end
    return s .. '}'
  elseif string.match(tostring(o),'[%Wxyz]') then
    return escape_lua_pattern(tostring(o))
  end
  return tostring(o)
end

function module.AddCase(name)
  if(not config.excludeReport) then
    module.curr_node = module.root:addChild(name)
    module.ndoc:write(module.curr_report_name)
  end
  module:LOGTestCaseStart(name)
end

function module.AddMessage(name,funcName,...)
  if(not config.excludeReport) then
    local attrib = table.pack(...)[1]
    local msg = module.curr_node:addChild(name)

    if (type(funcName) ~= 'table') then
      msg:attr('FunctionName',funcName)
    else
      for an, av in pairs(funcName) do
        msg:attr(an,av)
      end
    end
    if (type(attrib) == 'table') then
      msg:text(dump(attrib))
    elseif(attrib ~= nil) then
      msg:text(attrib)
    end
    module.ndoc:write(module.curr_report_name)
  end
end

function module.CaseMessageTotal(name, ... )
  if(not config.excludeReport) then
    local attrib = table.pack(...)[1]
    for attr_n,attr_v in pairs(attrib) do
      if (type(attr_v) == 'table') then attr_v = table.concat(attr_v, ';')
      elseif (type(attr_v) ~= 'string') then attr_v = tostring(attr_v)
      end
      module.curr_node:attr(attr_n, attr_v)
    end
  end
end

function module.finalize()
  if(not config.excludeReport) then
    module.ndoc:write(module.curr_report_name)
    if (config.storeFullSDLLogs) then sdl_log.close() end
  end
end

local function get_script_name(str)
  local tbl = table.pack(string.match(str, '(.-)([^/]-([^%.]+))$'))
  local name = tbl[#tbl-1]:gsub('%.'..tbl[#tbl]..'$', '')
  return name
end

function module.init(script_file_name)
  module.script_file_name = script_file_name
  if(config.excludeReport) then return module end
  if (module.timestamp == '') then module.timestamp = tostring(os.date('%Y%m%d%H%M%S', os.time())) end
  local dir_name = './' .. script_file_name
  local curr_report_dir = ''
  if (config.reportPath ~= nil and config.reportPath ~= '') then
    curr_report_dir = config.reportPath .. '/TestingReports'
  else
    curr_report_dir = 'TestingReports'
  end
  local curr_report_path = io.catdir(curr_report_dir ..'_'..module.timestamp, io.catdir(io.dirname(dir_name)))
  local report_header_name = ''
  if (config.reportMark ~= nil and config.reportMark ~= '' ) then
    module.curr_report_name = io.catfile(curr_report_path,get_script_name(dir_name) ..'_'..module.timestamp ..'_'..config.reportMark .. '.xml')
    report_header_name = script_file_name:gsub('.lua', '') .. '_' .. module.timestamp .. '_' .. config.reportMark
  else
    module.curr_report_name = io.catfile(curr_report_path,get_script_name(dir_name) ..'_'..module.timestamp .. '.xml')
    report_header_name = script_file_name:gsub('.lua', '') .. '_' .. module.timestamp
  end
  os.execute('mkdir -p "'.. curr_report_path .. '"')
  module.ndoc = xml.new()
  local alias = report_header_name:gsub('%.', '_'):gsub('/','_')
  module.root = module.ndoc:createRootNode(alias)
  module:initATFLOG(module.timestamp)
  module:initFullATFLOG(module.timestamp)
  return module
end

function module:initSDLLOG(timestamp)
  if (config.storeFullSDLLogs) then
    local full_sdlLog_name = module:getLogFileName(timestamp, "SDLLogs")
    module.full_sdlLog_name = full_sdlLog_name .. ".log"
    sdl_log.close()
    sdl_log.Connect(sdl_log.init(config.sdl_logs_host, config.sdl_logs_port, module.full_sdlLog_name))
  end
end

function module:getLogFileName(timestamp, log_file_type)
  local dir_name = './' .. module.script_file_name
  local script_name = get_script_name(dir_name)
  if not timestamp then timestamp = tostring(os.date('%Y%m%d%H%M%S', os.time())) end
  if (config.reportPath == nil or config.reportPath == '') then
    config.reportPath = "."
  end
  local reportMark = config.reportMark
  if (reportMark == nil) then reportMark = ''
  else reportMark = "_" .. reportMark end
  local curr_log_dir = config.reportPath .. '/' .. log_file_type
  local curr_log_path = io.catdir(curr_log_dir ..'_'.. timestamp, io.catdir(io.dirname(dir_name)))
  local full_log_name = io.catfile(curr_log_path, script_name ..'_'..module.timestamp .. reportMark)
  os.execute('mkdir -p "'.. curr_log_path .. '"')
  return full_log_name
end

function module:initATFLOG(timestamp)
  if not self.atf_log then
    local atf_log_name = self:getLogFileName(timestamp, "ATFLogs")
    atf_log_name = atf_log_name .. ".txt"
    module.atf_log = atf_log:New(atf_log_name)
  end
end

function module:initFullATFLOG(timestamp)
  if config.storeFullATFLogs and not self.full_atf_log then
    local full_atf_log_name = self:getLogFileName(timestamp, "ATFLogs")
    full_atf_log_name = full_atf_log_name .. "_full.txt"
    module.full_atf_log = atf_log:New(full_atf_log_name)
  end
end

function module:closeSDLlogSocket()
  if (config.storeFullSDLLogs) then sdl_log.close() end
  os.execute('bash ./WaitClosingSocket.sh '..config.sdl_logs_port)
end

function module:LOGTestCaseStart(test_case)
  if config.excludeReport then return end
  if config.storeFullATFLogs then
    module:initFullATFLOG(module.timestamp)
    module.full_atf_log:StartTestCase(test_case)
  end
  module.atf_log:StartTestCase(test_case)
end

function module:LOG(tract, message)
  if config.excludeReport then return end
  if (config.storeFullATFLogs) then
    module:initFullATFLOG(module.timestamp)
    module.full_atf_log[tract](module.full_atf_log, message)
  end
  if string.find(tract, "HMI") or
  (message.frameType ~= ford_constants.FRAME_TYPE.CONTROL_FRAME) and
  (message.serviceType ~= ford_constants.SERVICE_TYPE.PCM) and
  (message.serviceType ~= ford_constants.SERVICE_TYPE.VIDEO) then
    module.atf_log[tract](module.atf_log, message)
  end
end

return module
