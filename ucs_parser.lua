--[[
Lucas UCS parser

The general assumption made by this parser is that Pump will ignore anything StepEdit Lite cannot produce.
In addition, it makes the assumption that certain malformations are acceptable.
Also chunk headers are treated as not needing to be ordered.
]]
local notedata = require "notedata_type"
local ffi_util = require "ffi_util"
--local rational = require "rational"
--local log = require "lucas_log"
--this hasn't been written yet

local library = {}
--local lines = require "lines"
local mode_definitions = {Single=5,["S-Performance"]=5,Double=10,["D-Performance"]=10}

local chunk_header_line_pattern = "^:(%a+)=([%w%p]+)"
local function is_chunk_header_line(line)
   return line:match(chunk_header_line_pattern) ~= nil
end

local step_line_pattern = "^([%.XMHW]+)"
local function is_step_line(line)
   return line:match(step_line_pattern) ~= nil
end

local note_definitions = {
   M={"HOLD_HEAD","CROSS","VISIBLE"},
   H={"HOLD_BODY","CROSS","VISIBLE"},
   W={"HOLD_TAIL","CROSS","VISIBLE"},
   X={"TAP","JUDGE","VISIBLE"},
   }

local function is_integer(text)
   local value = tonumber(text)
   return value and math.floor(value) == value and value == value and math.abs(value) ~= math.huge
end

local required_header_tags = {"BPM","Split","Delay"}

local function header_has_required_tags(header)
   for _, tag in pairs(required_header_tags) do
      if not header[tag] then
         return false
      end
   end

   return true
end


local header_tag_handlers = {
   Beat = function(chunk_def,data)
      --as far as i know, this tag doesn't do anything, but it ought to be a positive integer anyway.
      local value = tonumber(data)

      if not is_integer(value) or value < 1 then
         return report_issue("illegal Beat value: "..data)
      end

      chunk_def.Beat = value
      return true
   end;
   BPM = function(chunk_def,data)
      local value = tonumber(data)

      if not value or value <= 0 then
         return report_issue("illegal BPM value: "..data)
      end

      --this is converted to seconds per beat and beats per second as needed later
      chunk_def.BPM = value
      return true
   end;
   Delay = function(chunk_def,data)
      local value = tonumber(data)

      if not value or value < 0 then
         return report_issue("illegal Delay value: "..data)
      end
      --You can't rely on the order these are in unfortunately.
      chunk_def.Delay = value/1000
      return true
   end;
   Split = function(chunk_def, data)
      local value = tonumber(data)

      if not is_integer(value) or value < 1 then
         return report_issue("illegal Split value: "..data)
      end
      chunk_def.Split = 1/value
      return true
   end;
}

--in case of a parse failure, this returns nil and a string representing why.
library.load = function(path)
   local beats = 0
   local beat_increment = nil
   local column_count = nil
   --I don't know how delays work. racerxdl implements them as taking up
   --an amount of beat space equal to their duration, which sounds OK to me.
   --For this implementation, that means we will convert the delay to beats and
   --add that as a "bias".
   local current_chunk_timings = nil

   local line_number = 0
   local state = nil

   local function report_issue(reason,not_ignoring)
      local suffix = not_ignoring and "" or ", ignoring"
      print(("UCS WARNING %s: line %d: %s"):format(path, line_number, reason..suffix))
   end

   local function fail(reason)
      return nil, ("UCS ERROR %s: line %d: %s. Loading aborted."):format(path, line_number, reason)
   end

   local current_chunk_header = {}

   local output_scroll_def_for_this_chunk
   local rows = {}
   local notes = {}
   local scroll_defs = {}
   
   --These must be present before the first step line or the UCS will be rejected as invalid.
   local seen_format_tag = false
   local current_mode_columns = nil

   for line in io.lines(path) do
      --Whitespace with the exception of newlines does not appear to be significant in the UCS format.
      line:gsub("%s","")

      line_number = line_number + 1

      --Don't even bother commenting on blank lines.
      if #line == 0 then goto next_line end

      if is_chunk_header_line(line) then
         --Handle starting a new chunk.
         if state == "steps" or state == nil then
            current_chunk_header = {}
         end
         local tag, data = line:match(chunk_header_line_pattern)

         --NB: this parser treats the *first* tag it sees of these types as the only one.
         if tag == "Format" then
            --Both UCS formats that we plan to support (Andamiro and Nysatia) label themselves as version 1.
            if not seen_format_tag then
               if tonumber(data) ~= 1 then
                  return fail("unsupported UCS format "..data)
               end
               seen_format_tag = true
            else
               report_issue "duplicate Format tag"
            end
         elseif tag == "Mode" then
            if not current_mode_columns then
               local mode_columns = mode_definitions[data]
               if mode_columns then
                  current_mode_columns = mode_columns
               else
                  return fail("unrecognized Mode "..data)
               end
            else
               report_issue "duplicate Mode tag"
            end
         else
            local tag_handler = header_tag_handlers[tag]

            if tag_handler then
               tag_already_defined = current_chunk_header[tag]
               --This line also reads data from the tag as a side effect.
               --Warning on invalid values is handled in each tag handler.
               if tag_handler(current_chunk_header,data) and tag_already_defined then
                  report_issue("tag for value \""..tag.."\" already existed, using new value",true)
               end
            else
               report_issue("unrecognized tag \""..tostring(tag)..'"')
            end
         end
            
         state = "header"
      elseif is_step_line(line) then
         --strip the trailing newline. If this is not done, the gmatch thing done below doesn't work.
         line = line:sub(1,-2)

         if state == "header" or state == nil then
            if not (current_mode_columns and seen_format_tag) then
               return fail "Mode and/or Format tag missing"
            elseif not header_has_required_tags(current_chunk_header) then
               return fail "Missing chunk tag"
            end

            --what goes in this structure:
            --1: SPB (makes some math nicer), 2: total delay in beats, 3: elapsed time at start of chunk,
            --4: row beats at start of chunk, 5: this chunk's delay in seconds, 6: the total delay in beats before this chunk
            local last_chunk_timings = current_chunk_timings
            current_chunk_timings = {}
            current_chunk_timings[1] = 60/current_chunk_header.BPM
            --this right now is this chunk's delay in beats
            current_chunk_timings[2] = current_chunk_header.Delay / current_chunk_timings[1]
            --to clarify what "row beats" are, they are the number of beats contributed by every UCS row in the chart.
            --this is needed so we can calculate timestamps.
            current_chunk_timings[4] = beats
            --and this is this chunk's delay in seconds, also needed so we can calculate timestamps
            current_chunk_timings[5] = current_chunk_header.Delay
            
            --accumulate previous timing adjustments, if there are any
            if last_chunk_timings then
               current_chunk_timings[6] = last_chunk_timings[2]
               --add the delay in beats from all previous chunks
               current_chunk_timings[2] = current_chunk_timings[2] + last_chunk_timings[2]
               --take the last chunk's start time, add the number of seconds all row beats took up, and finally add
               --that chunk's delay
               current_chunk_timings[3] = last_chunk_timings[3]
                  + (beats - last_chunk_timings[4]) * last_chunk_timings[1]
                  + last_chunk_timings[5]
            else
               current_chunk_timings[3] = 0
               current_chunk_timings[6] = 0
            end
            output_scroll_def_for_this_chunk = false
            beat_increment = current_chunk_header.Split
         end

         if #line ~= current_mode_columns then
            return fail("Step line has "..#line.." columns, should have "..current_mode_columns)
         end

         --this allows us to not create empty rows.
         local row_index

         --This calculates the beat and time position for a row, creates the row, and returns its index.
         local function create_row(is_header_row)
            local delay_beats, delay_seconds

            --The way we do Pump delays is they are a spacing in beats inserted before the first row of the chunk.
            --For that reason, if this is the header row, the space taken up by the delay should not be factored
            --into the visual or time position.
            if is_header_row then
               delay_beats = current_chunk_timings[6]
               delay_seconds = 0
            else
               delay_beats = current_chunk_timings[2]
               delay_seconds = current_chunk_timings[5]
            end

            --this formula is (number of row beats since chunk started) * seconds per beat + (chunk delay in seconds)
            local time_since_chunk_start = (beats - current_chunk_timings[4])*current_chunk_timings[1]+delay_seconds
            local row = notedata.row(beats+delay_beats,time_since_chunk_start+current_chunk_timings[3])
            --These arrays are all transformed into LuaJIT FFI arrays at the end of the function, which are 0 indexed,
            --so just giving the number of rows before the new row is added as the index is correct.
            local new_row_index = #rows
            rows[new_row_index+1] = row
            return new_row_index
         end

         --scroll defs hold the information required to handle BPM changes (and stops) at runtime
         if not output_scroll_def_for_this_chunk then
            local def_row_index = create_row(true)
            if current_chunk_timings[5] == 0 then
               row_index = def_row_index
            end
            local bps = current_chunk_header.BPM / 60
            scroll_defs[#scroll_defs+1] = notedata.scroll_def(bps, bps, def_row_index)
            output_scroll_def_for_this_chunk = true
         end
         
         local note_column = 1
         for char in line:gmatch('(.)') do
            if char ~= '.' then
               if row_index == nil then
                  row_index = create_row()
               end
               local note_type, judge_mode, visibility = unpack(note_definitions[char])
               local note_struct = notedata.note(note_type, 0, 0, 0, note_column, -32768, judge_mode, visibility, row_index)
               notes[#notes+1] = note_struct
            end
            note_column = note_column + 1
         end
         --do this now so the next line is at the correct beats number
         beats = beats + beat_increment 
         
         state = "steps"
      else
         report_issue('unrecognized line format "'..line..'"')
      end
      ::next_line::
   end

  return current_mode_columns, ffi_util.repack_arrays_as_vla('row', rows, 'note', notes, 'scroll_def', scroll_defs)
   
end


return library
