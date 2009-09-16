PolymorphicInclude
==================

Eager loading of polymorphic associations doesn't work in Rails <2.1 and
only works in 2.1 if rails doesn't have to fall back on left outer joins
for the :include.

This plugin allows eager loading in all situations in rails.

It assumes you are using the default "_type" suffix. With this code you can just
use a :include directive in your finds and it will return your associations
instead of throwing an exception.


Example
=======

Stolen from Rails documentation

class Address < ActiveRecord::Base
  belongs_to :addressable, :polymorphic => true
end

# A call that tries to eager load the addressable model
Address.find(:all, :include => :addressable)


Copyright (c) 2008 Jason Haruska, released under the MIT license
