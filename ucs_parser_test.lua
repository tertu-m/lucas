--This parses a UCS file and outputs a CSV of it for further examination offline.

local ucs_parser = require "ucs_parser"

local test_path = "test assets/d18_plutz.ucs"
print("parsing UCS file "..test_path)
local x = os.clock()
local cols, rows, notes, scroll_defs = ucs_parser.load "test assets/d18_plutz.ucs"
local y = os.clock()
print("parse took "..1000* (y- x).."ms cpu time")


local num_rows = rows[2]
local num_notes = notes[2]
local num_scroll_defs = scroll_defs[2]
print(string.format("overall statistics: %d rows, %d notes, %d scroll_defs\n",num_rows,num_notes,num_scroll_defs))

local int_float_float_format = [[%d,%f,%f]]

for i=0,num_scroll_defs-1 do
    local def = scroll_defs[1][i]
    print(string.format(int_float_float_format i, def.scroll_rate, def.flash_rate, def.row_index))
end

local vla_rows = rows[1]
local vla_notes = notes[1]

for i=0,num_rows-1 do
    local row = vla_rows[i]
    print(string.format(int_float_float_format, i, row.visual_position, row.time_position))
end
