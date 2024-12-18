local Cache = require('utils/Cache')
local Voice = require('player/Voice')
local Player = require('player/Player')

local class = require('class')
local enums = require('enums')
local Events = require('const').Events
local VoiceState = enums.VoiceState
local PlayerState = enums.PlayerState

local PlayerManager, get = class('PlayerManager', Cache)

function PlayerManager:init(lunalink)
  Cache.init(self)
  self._lunalink = lunalink
end

function get:lunalink()
  return self._lunalink
end

function PlayerManager:create(options)
  -- Check player exist
  local created_player = self:get(options.guildId)
  if created_player then return created_player end

  -- Check voice
  local get_curr_voice = self._lunalink.voices:get(options.guildId)
  if get_curr_voice then
		get_curr_voice:disconnect()
		self._lunalink.voices:delete(options.guildId)
  end

  -- Create voice handler
  local voice_handler = Voice(self._lunalink, options)
  self._lunalink.voices:set(options.guildId, voice_handler)
  voice_handler:connect()

  -- Get node
  local get_custom_node = self._lunalink.nodes:get(options.nodeName and options.nodeName or '')
  local node_list = self._lunalink.nodes:full()
  local reigoned_node_list = self:_filter(node_list, function (data)
    return data[2].node.options.region
  end)
	local reigoned_node = self:_map(reigoned_node_list, function (data)
    return data[2]
  end)

  if not get_custom_node and voice_handler.region and #reigoned_node ~= 0 then
    local nodes = self:_filter(reigoned_node, function (node)
      return node.options.region == voice_handler.region
    end)
    if #nodes then get_custom_node = self._lunalink.nodes:getLeastUsed(nodes) end
  end

  local node = get_custom_node and get_custom_node or self._lunalink.nodes:getLeastUsed()
  assert(node, 'Can\'t find any nodes to connect on')

  -- Create players
  local custom_player =
    (self._lunalink.options.config.structures and
    self._lunalink.options.config.structures.player)

  local player = custom_player
    and self._lunalink.options.config.structures.player(self._lunalink, voice_handler, node)
    or Player(self._lunalink, voice_handler, node)

  self:set(player.guildId, player)

  -- Send server update
  player:sendServerUpdate()
  voice_handler:on('connectionUpdate', function (state)
    if state ~= VoiceState.SESSION_READY then return end
    player:sendServerUpdate()
  end)

  -- Finishing up
  player.state = PlayerState.CONNECTED
  self:debug('Player created at ' .. options.guildId)
  self._lunalink:emit(Events.PlayerCreate, player)
end

function PlayerManager:destroy(guildId)
  local player = self:get(guildId)
  if player then player:destroy() end
end


function PlayerManager:_filter(t, func)
  local out = {}
  for k, v in pairs(t) do
    if func(v, k, t) then
      table.insert(out, v)
    end
  end
  return out
end

function PlayerManager:_map(tbl, func)
  local result = {}
  for i, v in ipairs(tbl) do
      result[i] = func(v, i, tbl)  -- Apply the function to each element
  end
  return result
end

function PlayerManager:debug(logs, ...)
	local pre_res = string.format(logs, ...)
	local res = string.format('[Rainlink] / [PlayerManager] | %s', pre_res)
	self._lunalink:emit(Events.Debug, res)
end

return PlayerManager