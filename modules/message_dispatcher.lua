local ph = require('protocol_handler/protocol_handler')
local module = { mt = { __index = { } } }
local fbuffer_mt = { __index = { } }
local fstream_mt = { __index = { } }

function module.FileStorage(filename)
  local res = {}
  res.filename = filename
  res.protocol_handler = ph.ProtocolHandler()
  res.wfd = io.open(filename, "w")
  res.rfd = io.open(filename, "r")
  setmetatable(res, fbuffer_mt)
  return res
end
function module.FileStream(filename, sessionId, service, bandwidth, chunksize)
  local res = { }
  res.filename = filename
  res.service = service
  res.sessionId = sessionId
  res.bandwidth = bandwidth
  res.bytesSent = 0
  res.ts = timestamp()
  res.chunksize = chunksize or 1488
  res.protocol_handler = ph.ProtocolHandler()
  res.messageId = 1
  res.rfd, errmsg = io.open(filename, "r")
  if not res.rfd then error (errmsg) end
  setmetatable(res, fstream_mt)
  return res
end
function fbuffer_mt.__index:KeepMessage(msg)
  self.keep = msg
end
function fstream_mt.__index:KeepMessage(msg)
  self.keep = msg
end
function fbuffer_mt.__index:WriteMessage(msg)
  self.wfd:write(string.char(bit32.band(#msg, 0xff),
      bit32.band(bit32.rshift(#msg, 8), 0xff),
      bit32.band(bit32.rshift(#msg, 16), 0xff),
      bit32.band(bit32.rshift(#msg, 24), 0xff)))
  self.wfd:write(msg)
end
function fbuffer_mt.__index:Flush()
  self.wfd:flush()
end
function fstream_mt.__index:GetMessage()
  local timespan = timestamp() - self.ts
  local header = {}
  if timespan == 0 then return end
  if timespan > 5000 then
    self.ts = self.ts + timespan - 1000
    self.bytesSent = self.bytesSent / (timespan / 1000)
    timespan = 1000
  end
  if (self.bytesSent + self.chunksize) / (timespan / 1000) > self.bandwidth then
    return header, nil, 200
  end
  local res = nil
  if self.keep then
    res = self.keep
    self.keep = nil
    return header, res
  end
  local data = self.rfd:read(self.chunksize)
  if data then
    self.bytesSent = self.bytesSent + #data
    self.messageId = self.messageId + 1

    header =
    {
      version = config.defaultProtocolVersion or 2,
      encryption = false,
      sessionId = self.sessionId,
      frameInfo = 0,
      frameType = 1,
      serviceType = self.service,
      binaryData = data,
      messageId = self.messageId
    }

    res = table.concat(self.protocol_handler:Compose(header))
  end
  return header, res
end
function fbuffer_mt.__index:GetMessage()
  local header = {}
  if self.keep then
    local res = self.keep
    header = self.protocol_handler:Parse(self.keep)
    self.keep = nil
    return header, res
  end
  local len = self.rfd:read(4)
  if len then
    len = bit32.lshift(string.byte(string.sub(len, 4, 4)), 24) +
    bit32.lshift(string.byte(string.sub(len, 3, 3)), 16) +
    bit32.lshift(string.byte(string.sub(len, 2, 2)), 8) +
    string.byte(string.sub(len, 1, 1))
    local frame = self.rfd:read(len)
    local doNotValidateJson = true
    header = self.protocol_handler:Parse(frame, doNotValidateJson)
    return header, frame
  end
  return header, nil
end
function module.MessageDispatcher(connection)
  local res = {}
  res._d = qt.dynamic()
  res.generators = { }
  res.idx = 0
  res.connection = connection
  res.bufferSize = 8192
  res.mapped = { }
  res.timer = timers.Timer()
  res.timer:setSingleShot(true)
  function res._d:timeout()
    self:bytesWritten(0)
  end
  res.sender = qt.dynamic()
  function res.sender:SignalMessageSent() end

  function res._d:bytesWritten(c)
    if #res.generators == 0 then return end
    res.bufferSize = res.bufferSize + c
    for i = 1, #res.generators do
      if res.idx < #res.generators then
        res.idx = res.idx + 1
      else
        res.idx = 1
      end
      local header, msg, timeout = res.generators[res.idx]:GetMessage()
      if header and header.messageId then
        xmlReporter:LOG("SDLtoMOB", header)         
      end
      if msg and #msg > 0 then
        if res.bufferSize > #msg then
          res.bufferSize = res.bufferSize - #msg
          res.connection:Send({ msg })
          break
        else
          res.generators[res.idx]:KeepMessage(msg)
        end
      elseif timeout then
        res.timer:start(timeout)
      end
    end
  end
  res.connection:OnDataSent(function(self, num) res._d:bytesWritten(num) end)
  qt.connect(res.timer, "timeout()", res._d, "timeout()")
  setmetatable(res, module.mt)
  return res
end

function module.mt.__index:OnMessageSent(func)
  local d = qt.dynamic()
  function d:SlotMessageSent(v)
    func(v)
  end
  qt.connect(self.sender, "SignalMessageSent(int)", d, "SlotMessageSent(int)")
end

function module.mt.__index:MapFile(filebuffer)
  self.mapped[filebuffer.filename] = filebuffer
  table.insert(self.generators, filebuffer)
end
function module.mt.__index:UnmapFile(filebuffer)
  if not filebuffer then
    error("File was not mapped")
  end
  self.mapped[filebuffer.filename] = nil
  for i, g in ipairs(self.generators) do
    if g == filebuffer then
      table.remove(self.generators, i)
      break
    end
  end
end
function module.mt.__index:Pulse()
  self._d:bytesWritten(0)
end
return module
