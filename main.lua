print("starting lucas 0.0")
local ucs_parser = require "ucs_parser"
local player = require "player"
local util = require "util"
local obelisque, obelisque_bg, ucs_data, the_player, states

local calls = 0
local notes = 0
local function judgment_callback(miss, list)
   calls = calls + 1
   notes = notes + #list
end

function love.load()
   ucs_data = {ucs_parser.load("test assets/d18_plutz.ucs")}
   print("loaded ucs")
   print(unpack(ucs_data))
   love.graphics.setScissor(0,0,1600,900)
   states={}
   for i=1,ucs_data[1] do
      states[i] = false
   end
   the_player = player.new(ucs_data[1], ucs_data[2], ucs_data[4], {}, ucs_data[3], 0.5, false, nil)
   the_player:register_judgment_callback(judgment_callback)
   obelisque = love.audio.newSource("test assets/Obelisque.mp3", "stream")
   obelisque_bg = love.graphics.newImage("test assets/Obelisque.png")
   the_player:start()
   obelisque:play()
end

local drawables
local updates = {}
local update_idx = 1

local psyor_colors = {
   {252/255, 173/255, 58/255},
   {70/255, 202/255, 247/255},
   {1, 1, 63/255}
}

local function update_receptor_colors(source_table, dest_table, boost_amount)
    local base_component = 0.5
    for color=1,3 do
        local source_color = source_table[color]
        local dest_color = dest_table[color]
        for component=1,3 do
            dest_color[component] = (1+source_color[component])/2 * (1-boost_amount) + base_component * boost_amount
        end
    end
end

local gray_colors = util.deep_copy(psyor_colors)
local black = {0,0,0}
local dim = {0.5,0.5,0.5}
local speed_mod = 1

function love.update()
   local time = love.timer.getTime()
   local flash_level
   the_player:set_before_distance(2/speed_mod)
   the_player:set_after_distance(8/speed_mod)
   drawables, flash_level = the_player:update(states, true)


   update_receptor_colors(psyor_colors, gray_colors, flash_level)
   --[[local next_time = (love.timer.getTime() - time) * 1000
   if update_idx <= 500 then
      updates[update_idx] = next_time
      update_idx = update_idx + 1
   end
   if update_idx > 500 then
      local total = 0
      local peak = 0
      for i=1,500 do
         local update = updates[i]
         peak = math.max(peak, update)
         total = total + update
      end
      print("mean update time in ms: "..total/500)
      print("peak update time in ms: "..peak)
      print(calls.." calls", notes.." notes")
      update_idx = 1
   end]]
   collectgarbage 'step'
end

--[[
Psyor colors
orange: 252 173 58
blue: 70 202 247
yellow: 255 255 63
]]--

local scale_factor = 1.875
local note_size = 112
local column_spacing = 120
local column_offsets = {}
local half_note_size = note_size / 2
local target_y = note_size * 0.75
for i=1,10 do
   column_offsets[i] = (i-5.5)*column_spacing + 800 - half_note_size
end
--1 is orange, 2 is blue, 3 is yellow
local palette = {2,1,3,1,2}
local track_hold_mode = {}
local hold_blue = {81/255, 143/255, 184/255}

function love.draw()
   local function column_color_lookup(color_table,column)
      return color_table[palette[(column-1)%5+1]]
   end
   local note_colors = psyor_colors
   local receptor_colors = gray_colors
   
   local rect = love.graphics.rectangle
   local setColor = love.graphics.setColor
   love.graphics.discard()
   setColor(dim)
   love.graphics.draw(obelisque_bg, 0, 0, 0, 5/6)
   for column, offset in ipairs(column_offsets) do
      setColor(column_color_lookup(receptor_colors, column))
      rect('fill', offset, target_y, note_size, note_size)
   end
   for i=1,#drawables do
      local drawable = drawables[i]
      if drawable then
         local column = drawable[2]
         if drawable[1] < 1 then
            setColor(column_color_lookup(note_colors, column))
         else
            setColor(hold_blue)
         end
         local x = column_offsets[column]
         local y = math.floor(target_y+note_size*drawable[3]*speed_mod)
         rect('fill', x, y, note_size, note_size)
         if drawable[1] == 0 then
         setColor(black)
         rect('line', x, y, note_size, note_size)
         end
      end
   end
   setColor(1,1,1)
   love.graphics.print(love.timer.getFPS(), 10, 10)
end

function love.textinput(text)
    local number = tonumber(text)
    if number then
        if number == 0 then
            number = 10
        end
        speed_mod = number
    end
end
