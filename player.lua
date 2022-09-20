--[[
Lucas Player's "player"
i.e. the part of the engine that handles more or less game neutral aspects of drawing and judgment.
While some of the terminology (calling this player, tracks) are inspired by StepMania, this is really not much
like StepMania's Player, in part because it doesn't really know any game rules.
]]

local library = {}
local notedata = require "notedata_type"
local notedata_util = notedata.util
local getTime = love.timer.getTime

local player_mt = {__index=library}

library.new = function(track_count,rows,scroll_defs,speed_defs,notes,max_judge_distance,use_earliest_note,autoplay_filter)
   local output = {}

   local function fail(reason)

   end

   output.current_scroll_def = 0
   output.current_speed_def = 0
   output.first_note = 0
   output.track_states = {}
   output.judgment_callbacks = {}
   --inefficient values but it should be good
   output.before_distance = 10
   output.after_distance = 10
   output.visual_distance_uses_time = false
   output.track_count = track_count
   
   for i=1,output.track_count do
      output.track_states[i] = false
   end
   
   output.start_time = nil
   
   output.rows_array, output.num_rows = unpack(rows)
   output.notes_array, output.num_notes = unpack(notes)
   output.scroll_defs_array, output.num_scroll_defs = unpack(scroll_defs)
   --Yes, you always need speed defs, even if there's only one of them.
   output.speed_defs_array, output.num_speed_defs = unpack(speed_defs)
   output.judge_queues={hit={},miss={}}
   output.use_earliest_note = use_earliest_note
   output.autoplay_filter = autoplay_filter
   output.drawables_list = {}

   --This isn't actually needed by player but player provides it to the judgment code because judgment code does care about it.
   local notes_per_judgment_group = {}
   local notes_array = output.notes_array
   for i=0,output.num_notes-1 do
      local note = notes_array[i]
      local row_idx = note.row_index
      local judgment_group = note.judgment_group
      local groups_this_row = notes_per_judgment_group[row_idx]
      if groups_this_row == nil then
         groups_this_row = {}
         notes_per_judgment_group[row_idx] = groups_this_row
      end
      local notes_this_group = groups_this_row[judgment_group] or 0
      groups_this_row[judgment_group] = notes_this_group + 1
   end
   output.notes_per_judgment_group = notes_per_judgment_group
         
   output.max_judge_distance = max_judge_distance
   setmetatable(output, player_mt)

   return output
end

--NB: player runs judgment callbacks in an arbitrary order. If the order matters, you'll have
--to figure out some way to handle that outside of player.
--Also, your function will be called in the player thread. This means it's OK to write to the
--notes if you want, but also means you need to use cross-thread communication methods to talk
--to the main thread.
--callback parameters: whether the callback is being called to handle a miss, the note that was hit, a reference to the notes_per_row table
library.register_judgment_callback = function(self,callback)
   if self.judgment_callbacks[callback] then return false end
   self.judgment_callbacks[callback] = true
   return true
end

library.unregister_judgment_callback = function(self,callback)
   if not self.judgment_callbacks[callback] then return false end
   self.judgment_callbacks[callback] = nil
   return true
end

library.set_visual_distance_uses_time = function(self,new_value)
   local old_value = self.visual_distance_uses_time
   self.visual_distance_uses_time = new_value
   return old_value
end

--the distance value is in visual units, which is to say beats
library.set_before_distance = function(self,distance)
   assert(tonumber(distance) and distance > 0, "invalid distance value")
   self.before_distance = distance
end

library.set_after_distance = function(self,distance)
   assert(tonumber(distance) and distance > 0, "invalid distance value")
   self.after_distance = distance
end

library.start = function(self)
   self.start_time = getTime()
end

library.is_started = function(self)
   return self.start_time == nil
end

--This function handles the logic for determining whether a note that is within the valid judgment range should be hit.
--For autoplay, this is decided based on the autoplay filter if set, except that fakes don't even get this far.
--If there is no autoplay filter, every note is hit.
--In normal play, this is decided based on the judgment mode. As above, fakes excluded.
local function did_note_trigger(note, track_state, track_edge, autoplay)
   if autoplay then
      if self.autoplay_filter == nil then
         return true
      else
         return self.autoplay_filter(note)
      end
   end

   local judge_mode = note.judgment_mode
   if judge_mode == "AUTO" then
      return true
   elseif judge_mode == "CROSS" then
      return track_state
   elseif track_edge then
      return judge_mode == "LIFT" and (not track_state) or track_state
   end

   --normal note or lift, but the track state didn't change this update
   return false
end

--This function handles moving through the lists of scroll definitions and speed definitions.
local function get_new_timing_def_index(now, current_def_index, defs_array, num_defs, rows_array)
   while current_def_index < num_defs-2 do
      local temp_def_index = current_def_index + 1
      if rows_array[defs_array[temp_def_index].row_index].time_position > now then
         break
      else
         current_def_index = temp_def_index
      end
   end
   return current_def_index
end

library.update = function(self, new_track_states, autoplay)
   --collectgarbage()
   local start_time = self.start_time
   if start_time == nil then
      error("start your players before you update them!",2)
   end

   local max_judge_distance = self.max_judge_distance

   local now = getTime() - start_time

   --values for controlling visual properties
   local before_distance = self.before_distance
   local after_distance = self.after_distance
   --i.e. Cmods
   local visual_distance_uses_time = self.visual_distance_uses_time
   
   local track_states = self.track_states
   local track_edges = {}

   local use_earliest_note = self.use_earliest_note

   --local function is_new_judgment_target(new_note_time, old_note_time)
   --   if use_earliest_note then
   --      return new_note_time < old_note_time
   --   else
   --      return math.abs(new_note_time - now) < math.abs(old_note_time - now)
   --   end
   --end

   --For taps, among other things, we care whether the track was changed this update.
   for track, state in ipairs(track_states) do
      track_edges[track] = new_track_states[track] ~= state
   end

   local rows_array = self.rows_array
   local notes_array, num_notes = self.notes_array, self.num_notes

   local current_scroll_def = self.current_scroll_def
   local scroll_defs_array = self.scroll_defs_array
   local new_scroll_def = get_new_timing_def_index(now, current_scroll_def, scroll_defs_array, self.num_scroll_defs, rows_array)
   if new_scroll_def ~= current_scroll_def then self.current_scroll_def = new_scroll_def end

   local current_scroll_def_data = scroll_defs_array[new_scroll_def]
   local current_scroll_def_row = rows_array[current_scroll_def_data.row_index]
   local time_since_scroll_def_start = now - current_scroll_def_row.time_position
   local visual_now = current_scroll_def_data.scroll_rate
      * time_since_scroll_def_start
      + current_scroll_def_row.visual_position
   local flash_now = current_scroll_def_data.flash_rate * time_since_scroll_def_start
   flash_now = flash_now - math.floor(flash_now)

   local drawables_list = self.drawables_list
   local original_drawables_length = #drawables_list
   local current_drawable_idx = 1
   local current_row, visual_distance, time_distance

   local judgment_list, miss_list = {}, {}
   for note_idx=self.first_note,num_notes-1 do
      local this_note = notes_array[note_idx]
      local row_index = this_note.row_index
      local track = this_note.track

      if current_row ~= row_index then
         current_row = row_index
         local row = rows_array[row_index]
         time_distance = row.time_position - now

         if visual_distance_uses_time then
            visual_distance = time_distance
         else
            visual_distance = row.visual_position - visual_now
         end
         if visual_distance > after_distance and time_distance > max_judge_distance then
            break
         end
      end

      local visibility = this_note.visibility

      if this_note:needs_judgment() then
         --handle miss. will never happen rn
         if time_distance < -max_judge_distance then
            miss_list[#miss_list+1] = this_note
         --here's some temporary autoplay-only code
         elseif time_distance < 0.0005 then
            this_note.judgment = 0
            judgment_list[#judgment_list+1] = this_note
            this_note.visibility = "INVISIBLE"
         end
      elseif self.first_note == note_idx and (visibility == "INVISIBLE" or -visual_distance > before_distance)
      then
         self.first_note = note_idx + 1
         goto next_note
      end

      --XXX: handle fade in and out
      if visibility == "VISIBLE" then
         local list_entry = drawables_list[current_drawable_idx]
         if not list_entry then
            list_entry = {}
            drawables_list[current_drawable_idx] = list_entry
         end
         list_entry[1] = tonumber(this_note.main_type)
         list_entry[2] = tonumber(this_note.track)
         list_entry[3] = tonumber(visual_distance)
         current_drawable_idx = current_drawable_idx + 1
      end

      ::next_note::
   end

   for i=current_drawable_idx,#drawables_list do
      drawables_list[i] = nil
   end

   local notes_per_judgment_group = self.notes_per_judgment_group
   if #judgment_list > 0 then
         --XXX also autoplay only
      for callback, _ in pairs(self.judgment_callbacks) do
         callback(false, judgment_list, notes_per_judgment_group)
      end
   end
   
   return drawables_list, flash_now
end

return library
