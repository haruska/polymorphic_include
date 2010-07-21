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
      remove_polymorphic_includes('calculate', args, e)
      retry
    end
  end

  # These are the alias method chaining for both "find" and "find_every"
  %w[find find_every].each do |func|
    define_method("#{func}_with_polymorphic_include") do |*args|
      poly_includes = {}

      # Try the regular find, if it throws the polymorph error, then we need to do extra processing
      begin
        res = self.send "#{func}_without_polymorphic_include", *args
      rescue ActiveRecord::EagerLoadPolymorphicError => e
        poly_includes = remove_polymorphic_includes(func, args, e)
        retry
      end
      add_removed_includes_to_results(res, poly_includes)
      return res
    end
  end

  private

  # remove the polymorph :includes and retry regular find
  def remove_polymorphic_includes(func, args, e)
    poly_includes = {}
    options = args.last.is_a?(::Hash) ? args.last : {}

    scope_includes = scope(:find)[:include] if scope(:find) and scope(:find).has_key?(:include)
    sym = e.message.split.last.sub(/^:/,'').to_sym
    inc = options[:include] || scope_includes

    logger.debug { "polymorph find triggered on: #{sym}, #{inc.inspect}" }
    logger.debug {"#{func} couldn't find :include; so far #{poly_includes.inspect} from args #{args.inspect}"} if inc.nil?

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
    logger.debug { "polymorph sub_includes: #{poly_sub_includes.inspect}" }
    poly_includes[sym] = poly_sub_includes
    if inc.blank? || (inc.respond_to?(:first) && inc.first.blank?)
      options.delete(:include)
    end

    return poly_includes
  end

  # for each polymorph include we removed in rescue above, query that
  # poymorph's table using the ids for the polymorph that were fetched
  # in the parent object from normal find
  def add_removed_includes_to_results(res, poly_includes)
    poly_includes.each do |sym, sub_includes|
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
            set.each { |c| c.send("#{sym.to_s}=", sources_map[c.attributes[id_sym.to_s]]) }
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
