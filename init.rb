# Include hook code here
require 'polymorphic_include'

ActiveRecord::Base.extend(PolymorphicInclude)
