local util = {}
local ffi = require "ffi"

function util.deep_copy(tbl)
   local output = {}
   for key, value in pairs(tbl) do
      local key_type = type(key)
      if key_type == "cdata" then
         output[key] = ffi.new(ffi.typeof(value), value)
      elseif key_type == "table" then
         output[key] = util.deep_copy(tbl)
      else
         output[key] = value
      end
   end

   return output
end

return util
