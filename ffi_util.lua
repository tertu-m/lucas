local library = {}
local ffi = require"ffi"

library.repack_as_vla = function(type_string, array)
   return {ffi.new(type_string.."[?]", #array, array), #array}
end

local repack_as_vla = library.repack_as_vla

local function repack_arrays_as_vla(type_string, array, ...)
   if type_string == nil or array == nil then
      return error("missing argument")
   end
   if ... == nil then
      return repack_as_vla(type_string, array)
   else
      return repack_as_vla(type_string, array), repack_arrays_as_vla(...)
   end
end

library.repack_arrays_as_vla = repack_arrays_as_vla

return library
