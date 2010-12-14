module PolymorphicInclude

  def self.extended(object)
    class << object
      [:find, :find_every, :calculate].each do |func|
        alias_method_chain func, :polymorphic_include
      end
    end
  end

  define_method("calculate_with_polymorphic_include") do |*args|
    begin
      res = self.send "calculate_without_polymorphic_include", *args
    rescue ActiveRecord::EagerLoadPolymorphicError => e
      # Detect and remove all polymorphic associations
      find_args_without_poly_includes, poly_includes, scope_override = remove_polymorphic_includes(args)
      
      # Retry the original find, but apply an exclusive scope without the polymorphic includes
      res = with_exclusive_scope(:find => scope_override) do
        send "calculate_without_polymorphic_include", *find_args_without_poly_includes
      end
    end
  end

  # These are the alias method chaining for both "find" and "find_every"
  %w[find find_every].each do |func|
    define_method("#{func}_with_polymorphic_include") do |*args|
      poly_includes = {}
            
      # Try the regular find, if it throws the polymorph error, then we need to do extra processing
      begin
        res = self.send "#{func}_without_polymorphic_include", *args
      rescue ActiveRecord::EagerLoadPolymorphicError      
        # Detect and remove all polymorphic associations
        find_args_without_poly_includes, poly_includes, scope_override = remove_polymorphic_includes(args)
        
#        logger.debug{ "find_options_without_poly_includes: #{find_args_without_poly_includes}"}
#        logger.debug{ "poly_includes: #{poly_includes}"}
#        logger.debug{ "scope_override: #{scope_override}"}
        
        # Retry the original find, but apply an exclusive scope without the polymorphic includes
        res = with_exclusive_scope(:find => scope_override) do
          send "#{func}_without_polymorphic_include", *find_args_without_poly_includes
        end
      end
      add_removed_includes_to_results(res, poly_includes)
      return res
    end
  end

  private

  def remove_polymorphic_includes(find_args)
    # Extract the find options from the arguments passed to find
    find_options = find_args.extract_options!

    #        logger.debug{ "find_options #{find_options}"}
    #        logger.debug{"Model has the following polymorphic associations: #{polymorphic_reflections.keys}"}
    
    # A list we will populate with polymorphic includes we need to do
    polymorphic_includes = {}
    
    if scope(:find) and scope(:find).has_key?(:include)
      # Get the includes from the scope
      scope_override = scope(:find).dup
      scope_override[:include] = scope_override[:include].dup
    
      # Remove all polymorphic associations from the scope and remember them in the polymorphic includes list
      polymorphic_includes.merge!(remove_polymorphic_associations_from_includes!(scope_override[:include]))
      #      logger.debug{"scope_override includes: #{scope_override[:include].inspect}"}
    end
    
    
    if find_options.has_key?(:include)
      # Wrap the includes in an array so we can iterate through them easily
      find_options[:include] = [find_options[:include]] unless find_options[:include].is_a?(Array)

      # Iterate through each include and move it to the polymorphic includes if it is one
      #            logger.debug{ "find_option includes: #{find_options[:include]}"}
      polymorphic_includes.merge!(remove_polymorphic_associations_from_includes!(find_options[:include]))
    end 
    
    # Reassemble the find_args
    find_args_without_poly_includes = find_args + [find_options]
    
    # We should now be left with find_options without polymorphic includes,
    # a list of polymorphic includes, and a scope we without polymorphic includes
    # that we can use to override the original find
    return find_args_without_poly_includes, polymorphic_includes, scope_override    
  end
  
  
  # Removes all polymorphic associations from the array of +includes+
  # Returns a hash of the polymorphic includes that were present and their values
  def remove_polymorphic_associations_from_includes!(includes)
    polymorphic_includes = {}
    includes.each do |inc|
      # If the include is a hash, eg {:discussions => :comments, :projects => :members}
      # Else the include is a single association name, eg. :comments
      case inc
      when Hash
        inc.reject! do |association, value|
          if polymorphic_reflections.has_key?(association)
            polymorphic_includes[association] = value
            true
          end
        end
      else
        if polymorphic_reflections.has_key?(inc.to_sym)
          polymorphic_includes[inc] = nil
          includes.delete(inc)
        end
      end      
    end
    
    return polymorphic_includes
  end
  
  # Returns this model's polymorphic reflections
  def polymorphic_reflections
    @polymorphic_reflections ||= reflections.select{|association, reflection| reflection.options[:polymorphic]}
  end

  # for each polymorph include we removed in rescue above, query that
  # poymorph's table using the ids for the polymorph that were fetched
  # in the parent object from normal find
  def add_removed_includes_to_results(res, poly_includes)
    poly_includes.each do |sym, sub_includes|
      #      logger.debug{ " Iterating #{sym}"}
      if res.respond_to? :group_by
        res.group_by {|r| r.send "#{sym.to_s}_type"}.each do |stype, set|
          begin
            next if stype.nil?
            stype_class = Object.const_get stype
            id_sym = "#{sym.to_s}_id".to_sym
            ids = set.collect(&id_sym)
            sources = stype_class.find(ids, :include => sub_includes)
            sources = [sources] unless sources.is_a? Array
            sources_map = {}
            sources.each {|s| sources_map[s.id] = s}
            set.each do |c|
              #              logger.debug{ "assigning #{c.class} #{c.id} #{sym.to_s}=#{sources_map[c.attributes[id_sym.to_s]]}"}
              c.send("#{sym.to_s}=", sources_map[c.attributes[id_sym.to_s]])
            end
          rescue ActiveRecord::ConfigurationError => e
            # If the polymorph sub_include is for an association that is not for this
            # polymorph, remove it and try again
            assoc = e.message.match(/Association named '([^']+)'/).to_a[1]
            if assoc
              assoc = assoc.to_sym
              logger.debug { "polymorph wrong assoc for polymorph: #{assoc}, #{sub_includes.inspect}" }
              if sub_includes == assoc
                sub_includes = nil
              elsif sub_includes.is_a? Array
                sub_includes.delete_if { |k, v| k == assoc}
              elsif sub_includes.is_a? Hash
                sub_includes.delete assoc
              end
              retry
            else
              raise
            end
          end
        end
      else
        res.send sym
      end
    end
  end
end
