--fake getTime function to make player happy.
--jit.off()
jit.on()
local fake_timer = 0
love = {}
love.timer = {}
function love.timer.getTime()
    return fake_timer
end

local ucs_parser = require "ucs_parser"
local player = require "player"

local ucs_data = {ucs_parser.load("test assets/d18_plutz.ucs")}
local rows = ucs_data[2]
local stop_time = rows[1][rows[2]-1].time_position
local the_player = player.new(ucs_data[1], ucs_data[2], ucs_data[4], {}, ucs_data[3], 0.5, false, nil)
states={}
for i=1,ucs_data[1] do
   states[i] = false
end

the_player:set_before_distance(2)
the_player:set_after_distance(8)


local calls = 0
local notes = 0
local drawable_count = 0
local nil_drawables = 0

local anti_optimization = 0

local function judgment_callback(miss, list)
    calls = calls + 1
    notes = notes + #list
 end

 the_player:register_judgment_callback(judgment_callback)

local drawables
local start_time = os.clock()
the_player:start()
while fake_timer < stop_time do
    local speep = math.random(1,10)
    the_player:set_before_distance(2/speep)
    the_player:set_after_distance(8/speep)
    drawables, flash_level = the_player:update(states, true)
    fake_timer = fake_timer + 0.1
    for i=1,#drawables do
        local drawable = drawables[i]
        if drawables[i] == nil then
            nil_drawables = nil_drawables + 1
        else
            anti_optimization = anti_optimization + drawable[1] + drawable[2] + drawable[3]
        end
    end
    drawable_count = drawable_count + #drawables
end
local elapsed_time = os.clock() - start_time
local output_format = "ran "..stop_time.." game seconds in %f cpu ms (avg %f us), %d calls, %d notes, %d drawables"
print(output_format:format(elapsed_time*1000,elapsed_time/calls*1000000, calls, notes, drawable_count))
print("anti-optimization constant: ".. anti_optimization.. ", nil drawables: "..nil_drawables)