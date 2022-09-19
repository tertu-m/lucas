--a rational number library for luajit using the ffi.
--The numerator and denominator mu

local ffi = require "ffi"
ffi.cdef [[

typedef struct {
   int64_t numerator;
   int64_t denominator;
} rational;
]]

local c_rational = ffi.typeof "rational"

local function gcd(a, b)
   if a < 0 then a = -a end
   if b < 0 then b = -b end
   if a==0 then return b
   elseif b==0 then return a
   else return gcd(b, a % b)
   end
end

local int64 = ffi.typeof("int64_t")
local minimum = int64(-(2^52))
local maximum = int64(2^52)
local function too_large(number)
   return number > maximum or number < minimum
end

local function normalize(numerator, denominator)
   if too_large(numerator) or too_large(denominator) then
      error(numerator.."/"..denominator.." cannot be represented exactly",2)
   end
   
   if denominator < 0 then
      denominator = -denominator
      numerator = -numerator
   end
   local gcd = gcd(numerator, denominator)
   numerator, denominator = numerator/gcd, denominator/gcd

   return numerator, denominator
end

local function assert_rational(a)
   if not ffi.istype(c_rational, a) then
      error(tostring(a) .. " is not a rational", 2)
   end
end

--As basically every binary operator works the same way, this is here to remove boilerplate.
--The function is passed a_numerator, b_numerator, a_denominator, b_denominator and returns
--numerator, denominator.
local function define_binary_operator(processor)
   return function(a,b)
      assert_rational(a); assert_rational(b)
      local numerator, denominator = normalize(processor(a.numerator, b.numerator, a.denominator, b.denominator))
      
      return c_rational(numerator, denominator)
   end
end

local rational_lib = {}

--Not sure if this is useful.
rational_lib.normalize = function(a)
   assert_rational(a)
   a.numerator, a.denominator = normalize(a.numerator, a.denominator)
end
rational_lib.mul = define_binary_operator(function(an, bn, ad, bd) return an*bn, ad*bd end)
rational_lib.add = define_binary_operator(function(an, bn, ad, bd) return an*bd+bn*ad, ad*bd end)
rational_lib.sub = define_binary_operator(function(an, bn, ad, bd) return an*bd-bn*ad, ad*bd end)
rational_lib.div = define_binary_operator(function(an, bn, ad, bd)
      if bn == 0 then error("tried to divide by zero", 3) end; return an*bd, ad*bn end)
rational_lib.negate = function(a)
   assert_rational(a)
   local numerator, denominator = normalize(-a.numerator, a.denominator)
   return c_rational(numerator, denominator)
end
rational_lib.new = function(numerator, denominator)
   assert(denominator ~= 0, "denominator may not be 0")
   assert(numerator == numerator and denominator == denominator, "nan is not an acceptable value")
   numerator, denominator = normalize(numerator, denominator)
   return c_rational(numerator, denominator)
end
rational_lib.copy = function(rational)
   assert_rational(rational)
   return c_rational(rational.numerator, rational.denominator)
end
rational_lib.tonumber = function(a)
   return tonumber(a.numerator)/tonumber(a.denominator)
end

ffi.metatype(c_rational, {__index=rational_lib})

return c_rational
