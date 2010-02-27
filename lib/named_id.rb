module NamedID
  
  def self.included(base)
    base.extend NamedID::ClassMethods
    
  end
  
  module ClassMethods
    
    def named_id(options = {})
      # initialize with source column, slug column, scope, and before filters
      cattr_accessor :source_column, :slug_column, :slug_scope, :before_slug
      self.source_column  = (options[:source_column] || :name).to_s
      self.slug_column    = (options[:slug_column]   || :url_slug).to_s
      self.slug_scope     = options[:slug_scope]
      self.before_slug    = options[:before_slug]
      
      validates_uniqueness_of slug_column.intern, :on => :save, :message => "is already taken", :scope => slug_scope
      scope :sluggable,  lambda {|slugs| where("#{quoted_table_name}.`#{slug_column}` in (?)", [*slugs])}
      
      class_eval <<-EOV
      
        # Setup the callbacks and generation of slug
        before_validation #{[(before_slug.inspect if before_slug), :create_slug.inspect].compact.join(', ')}
      
        # The items our unique slug is scoped to.  The first where() elminates the current record from the search
        # since it is OK for us to keep the same slug
        def scope_condition
          #{name}.
            where(['#{quoted_table_name}.`#{primary_key}` <> ?', (#{primary_key} || -1)]).
            where(#{slug_scope.is_a?(Symbol) ? %({:#{slug_scope} => #{slug_scope}}) : slug_scope.inspect})
        end
        
        def to_param
          #{slug_column}
        end
        
        def slug_source
          #{source_column}
        end
        
        def slug_source?
          #{source_column}?
        end
        
        # This references either the original slug (if it exists) or the computes current slug.
        def slug
          #{slug_column}_changed? ? #{slug_column}_change.first : #{slug_column}
        end
        
        def slug=(_slug)
          self.#{slug_column} = _slug.blank? ? (slug || build_slug) : _slug
        end
        
        # If the slug is blank or the source column has changed in a way that updates the base_slug
        # we will need to update
        def slug_needs_update?
          slug.blank? || (#{source_column}_changed? and base_slug != slug.gsub(/\-[0-9]+$/,''))
        end
        
        # Find all items using the same base slug with the highest (or most recent) one first. 
        def similar          
          scope_condition.
            where("#{quoted_table_name}.`#{slug_column}` REGEXP '^\#\{base_slug\}(-[0-9]+)\?$'").
            order("length(#{quoted_table_name}.`#{slug_column}`) DESC, #{quoted_table_name}.`#{slug_column}` DESC") if base_slug
        end
                
      EOV
      
    end
    
    def find(*args)      
      # Check to see if you are attempting to find by the real ID or the slug      
      if NamedID.should_find_by_slug?(args.first)
        options = args.extract_options!
        sluggable(args.first).send((args.first.class == Array ? 'all' : 'first'), options)
      else        
        super
      end
    end
    
        
    def named(*args)
      if NamedID.should_find_by_slug?(args.first)
        options = args.extract_options!
        sluggable(args.first).send((args.first.class == Array ? 'all' : 'first'), options)
      else
        find *args
      end
    end
    
  end
    
  # assign the slug
  def create_slug
    self.slug = build_slug if slug_needs_update?
  end

  # compute the slug
  def build_slug
    [base_slug, suffix].compact.join '-' if slug_source?
  end

  # clean the source column of html and 
  # other characters first
  def base_slug
    slug_source.strip.downcase.
      gsub(/<[^>]*>/,   '').
      gsub(/[^a-z0-9\:]/, '-').
      gsub(/\-{2,}/,    '-').
      gsub(/\-$/,       '') if slug_source?
  end
  
  def suffix
    next_suffix if similar.any?
  end

  # the compute the next suffix for the base slug
  def next_suffix
    (last_suffix.to_i + 1).to_s
  end
  
  # the last used suffix for this base_slug
  def last_suffix
    similar.first.try(slug_column).to_s.match(%r(#{base_slug}-([0-9]+)$)).to_a.last
  end
  
  # Look at the arguments for the find method and determine
  # if the user is searching by the slug or bye the base ID #
  def self.should_find_by_slug?(item = nil)
    case item.class.name
    when 'Array'
      # If we've got an array, get the very first item 
      # and check that
      should_find_by_slug? item.flatten.first
      
    when 'String'
      # We need to check the numericality of a string because
      # things like delayed_job will give us a number that 
      # should be used on the real ID column.  
      !Float(item) rescue true
      
    when 'Float', 'Fixnum', 'Symbol'
      # if the argument is a number, so we shouldn't search by the slug
      # if it is a symbol, it is :all, :first, etc. so pass to super
      false      
    end
  end
  
end

