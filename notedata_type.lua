local ffi = require "ffi"

local output = {}

ffi.cdef[[
typedef enum {TAP,HOLD_HEAD,HOLD_BODY,HOLD_TAIL,ROLL_HEAD,ROLL_TAIL,MINE,POTION,HEART,HOLD_TAIL_LIFT,FLASH,VELOCITY} note_type;

typedef enum {JUDGE,BONUS,AUTO,NO_JUDGE,CROSS,LIFT} note_judge_mode;
typedef enum {VISIBLE,FADE_IN,FADE_OUT,INVISIBLE} note_visibility;

typedef struct {
    double visual_position;
    double time_position;
} row;
]]

ffi.cdef[[
typedef struct note {
    note_type main_type;
    uint32_t extra_data; //type dependent
    uint8_t judgment_group;
    uint8_t noteskin;
    uint8_t track;
    int16_t judgment; //special value = INT16_T_MIN, meaning unjudged
    note_judge_mode judgment_mode;
    note_visibility visibility;
    uint32_t row_index;
} note;

typedef struct scroll_def {
    double scroll_rate;
    double flash_rate;
    uint32_t row_index;
} scroll_def;

typedef struct speed_def {
    double start_speed;
    double end_speed;
    double lerp_time;
    uint32_t row_index;
} speed_def;
]]

local note_mt ={
__index={
    judge_together = function(a,b) return a.row_def == b.row_def and a.judgment_group == b.judgment_group end,
    needs_judgment = function(a) return a.judgment == -32768 and a.judgment_mode ~= "NO_JUDGE" end
},
}

local note = ffi.metatype("note", note_mt)
local output = {}
output.note = note
output.row = ffi.typeof("row")
output.scroll_def = ffi.typeof("scroll_def")
output.speed_def = ffi.typeof("speed_def")

local util = {}
output.util = {}

--This is a slightly modified binary search variant that instead returns the first def before
--or at the present.
util.find_active_def_index = function(defs_array,num_defs,rows_array,num_rows,time,start_position)
   start_position = start_position or 0
   end_position = num_defs
   local row_time_position
   
   while start_position < end_position do
      local target = math.floor((start_position + end_position)/2)
      row_time_position = rows_array[defs_array[target].row_idx].time_position
      if row_time_position < time then
         end_position = target
      else start_position = target + 1
      end
   end
   
   return start_position
end

util.type_is_hold_part = function(note_type)
   return type == "HOLD_HEAD" or type == "HOLD_BODY" or type == "HOLD_TAIL"
end

return output
