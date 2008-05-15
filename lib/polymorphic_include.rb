# PolymorphicInclude
module PolymorphicInclude

 def self.extended(object)
   class << object
     alias_method :find_without_polymorphic_include, :find unless method_defined?(:find_without_polymorphic_include)
     alias_method :find, :find_with_polymorphic_include
     
     alias_method :find_every_without_polymorphic_include, :find_every unless method_defined?(:find_every_without_polymorphic_include)
     alias_method :find_every, :find_every_with_polymorphic_include
    end
  end
  
  ### FIXME
  # find_every_with_polymorphic_include and find_with_polymorphic_include are the same method, cut and paste
  # how do we dynamically generate it?
  ### FIXME
  
  def find_every_with_polymorphic_include(*args)
    options = args.last.is_a?(Hash) ? args.last : {}
    poly_includes = {}
    # Try the regular find, if it throws the polymorph error, then we need to do extra processing
    begin
      res = find_every_without_polymorphic_include(*args)
    rescue ActiveRecord::EagerLoadPolymorphicError => e
      # remove the polymorph :includes and retry regular find
      sym = e.message.split.last.sub(/^:/,'').to_sym
      inc = options[:include]
      logger.debug { "Content polymorph find triggered on: #{sym}, #{inc.inspect}" }
      # we preserve any sub_includes for the polymorph for use when doing the
      # polymorph find.  This doesn't support recursive polymorph structures
      poly_sub_includes = nil
      if inc.is_a?(Array)
        if inc.first.is_a?(Hash)
          poly_sub_includes = inc.first.delete(sym)
        else
          poly_sub_includes = inc.delete(sym)
        end
      else
        options.delete(:include)
      end
      logger.debug { "Content polymorph sub_includes: #{poly_sub_includes.inspect}" }
      poly_includes[sym] = poly_sub_includes
      if inc.blank? || (inc.respond_to?(:first) && inc.first.blank?)
        options.delete(:include)
      end
      retry
    end
    # for each polymorph include we removed in rescue above, query that
    # poymorph's table using the ids for the polymorph that were fetched
    # in the parent object from normal find
    poly_includes.each do |sym, sub_includes|
      if res.respond_to? :group_by
        res.group_by {|r| r.send "#{sym.to_s}_type"}.each do |stype, set|
          begin
            stype_class = Object.const_get stype
            id_sym = "#{sym.to_s}_id".to_sym
            ids = set.collect(&id_sym)
            sources = stype_class.find(ids, :include => sub_includes)
            sources = [sources] unless sources.is_a? Array
            sources_map = {}
            sources.each {|s| sources_map[s.id] = s}
            set.each { |c| c.send("#{sym.to_s}=", sources_map[c.attributes[id_sym.to_s]]) }
          rescue ActiveRecord::ConfigurationError => e
            # If the polymoprh sub_inlcude is for an association that is not for this
            # polymorph, remove it and try again
            assoc = e.message.match(/Association named '([^']+)'/).to_a[1]
            if assoc
              logger.debug { "Content polymorph wrong assoc for polymorph: #{assoc}, #{sub_includes.inspect}" }
              assoc = assoc.to_sym
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
    return res
  end
  
  def find_with_polymorphic_include(*args)
    options = args.last.is_a?(Hash) ? args.last : {}
    poly_includes = {}
    # Try the regular find, if it throws the polymorph error, then we need to do extra processing
    begin
      res = find_without_polymorphic_include(*args)
    rescue ActiveRecord::EagerLoadPolymorphicError => e
      # remove the polymorph :includes and retry regular find
      sym = e.message.split.last.sub(/^:/,'').to_sym
      inc = options[:include]
      logger.debug { "Content polymorph find triggered on: #{sym}, #{inc.inspect}" }
      # we preserve any sub_includes for the polymorph for use when doing the
      # polymorph find.  This doesn't support recursive polymorph structures
      poly_sub_includes = nil
      if inc.is_a?(Array)
        if inc.first.is_a?(Hash)
          poly_sub_includes = inc.first.delete(sym)
        else
          poly_sub_includes = inc.delete(sym)
        end
      else
        options.delete(:include)
      end
      logger.debug { "Content polymorph sub_includes: #{poly_sub_includes.inspect}" }
      poly_includes[sym] = poly_sub_includes
      if inc.blank? || inc.first.blank?
        options.delete(:include)
      end
      retry
    end
    # for each polymorph include we removed in rescue above, query that
    # poymorph's table using the ids for the polymorph that were fetched
    # in the parent object from normal find
    poly_includes.each do |sym, sub_includes|
      if res.respond_to? :group_by
        res.group_by {|r| r.send "#{sym.to_s}_type"}.each do |stype, set|
          begin
            stype_class = Object.constant_get stype
            id_sym = "#{sym.to_s}_id".to_sym
            ids = set.collect(&id_sym)
            sources = stype_class.find(ids, :include => sub_includes)
            sources = [sources] unless sources.is_a? Array
            sources_map = {}
            sources.each {|s| sources_map[s.id] = s}
            set.each { |c| c.send("#{sym.to_s}=", sources_map[c.attributes[id_sym.to_s]]) }
          rescue ActiveRecord::ConfigurationError => e
            # If the polymoprh sub_inlcude is for an association that is not for this
            # polymorph, remove it and try again
            assoc = e.message.match(/Association named '([^']+)'/).to_a[1]
            if assoc
              logger.debug { "Content polymorph wrong assoc for polymorph: #{assoc}, #{sub_includes.inspect}" }
              assoc = assoc.to_sym
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
    return res
  end

end