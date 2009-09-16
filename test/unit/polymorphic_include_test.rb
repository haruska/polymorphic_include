require File.join(File.dirname(__FILE__), '..', 'test_helper')
require File.join(File.dirname(__FILE__), '..', '..', 'init')

class PolymorphicIncludeTest < Test::Unit::TestCase

  def test_strip_of_polymorphic_include
    mother = Mother.create
    child = Child.new :parent => mother
    assert child.valid?
    child.save

    assert_nothing_raised { Child.find(:all, :include => [:parent]) }
  end
end
