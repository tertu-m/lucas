local rational = require "rational"

local value = rational.new(1,2)
for i=2,20 do
   local new_value = rational.new(1,2^i)
   value = value:add(new_value)
end
print(value.numerator, value.denominator)
