local util = {}
local ffi = require "ffi"

function util.deep_copy(tbl)
   local output = {}
   for key, value in pairs(tbl) do
      local value_type = type(value)
      if value_type == "cdata" then
         output[key] = ffi.new(ffi.typeof(value), value)
      elseif value_type == "table" then
         output[key] = util.deep_copy(value)
      else
         output[key] = value
      end
   end

   return output
end

return util
