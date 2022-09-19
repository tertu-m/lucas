local ucs_parser = require "ucs_parser"



--print(ucs_parser.load("/home/tertu/Downloads/CS288(1).ucs"))
local x = os.clock()
local cols, rows, notes, scroll_defs = ucs_parser.load "test assets/d23.ucs"
print(1000* (os.clock() - x))
local num_rows = rows[2]
local num_notes = notes[2]
local num_scroll_defs = scroll_defs[2]
local vla_rows = rows[1]
local vla_notes = notes[1]
print(num_rows, num_notes, num_scroll_defs,cols)
print(vla_rows[num_rows-1].time_position)
print(vla_rows[num_rows-1].visual_position)
print(vla_notes[num_notes-1].row_index)
