require 'active_support/core_ext/class/attribute'
require 'active_support/core_ext/module/deprecation'
require 'active_support/core_ext/object/inclusion'

module ActiveRecord
  # = Active Record Reflection
  module Reflection # :nodoc:
    extend ActiveSupport::Concern

    included do
      class_attribute :reflections
      self.reflections = {}
    end

    # Reflection enables to interrogate Active Record classes and objects
    # about their associations and aggregations. This information can,
    # for example, be used in a form builder that takes an Active Record object
    # and creates input fields for all of the attributes depending on their type
    # and displays the associations to other objects.
    #
    # MacroReflection class has info for AggregateReflection and AssociationReflection
    # classes.
    module ClassMethods
      def create_reflection(macro, name, options, active_record)
        case macro
          when :has_many, :belongs_to, :has_one, :has_and_belongs_to_many
            klass = options[:through] ? ThroughReflection : AssociationReflection
            reflection = klass.new(macro, name, options, active_record)
          when :composed_of
            reflection = AggregateReflection.new(macro, name, options, active_record)
        end

        self.reflections = self.reflections.merge(name => reflection)
        reflection
      end

      # Returns an array of AggregateReflection objects for all the aggregations in the class.
      def reflect_on_all_aggregations
        reflections.values.grep(AggregateReflection)
      end

      # Returns the AggregateReflection object for the named +aggregation+ (use the symbol).
      #
      #   Account.reflect_on_aggregation(:balance) # => the balance AggregateReflection
      #
      def reflect_on_aggregation(aggregation)
        reflections[aggregation].is_a?(AggregateReflection) ? reflections[aggregation] : nil
      end

      # Returns an array of AssociationReflection objects for all the
      # associations in the class. If you only want to reflect on a certain
      # association type, pass in the symbol (<tt>:has_many</tt>, <tt>:has_one</tt>,
      # <tt>:belongs_to</tt>) as the first parameter.
      #
      # Example:
      #
      #   Account.reflect_on_all_associations             # returns an array of all associations
      #   Account.reflect_on_all_associations(:has_many)  # returns an array of all has_many associations
      #
      def reflect_on_all_associations(macro = nil)
        association_reflections = reflections.values.grep(AssociationReflection)
        macro ? association_reflections.select { |reflection| reflection.macro == macro } : association_reflections
      end

      # Returns the AssociationReflection object for the +association+ (use the symbol).
      #
      #   Account.reflect_on_association(:owner)             # returns the owner AssociationReflection
      #   Invoice.reflect_on_association(:line_items).macro  # returns :has_many
      #
      def reflect_on_association(association)
        reflections[association].is_a?(AssociationReflection) ? reflections[association] : nil
      end

      # Returns an array of AssociationReflection objects for all associations which have <tt>:autosave</tt> enabled.
      def reflect_on_all_autosave_associations
        reflections.values.select { |reflection| reflection.options[:autosave] }
      end
    end


    # Abstract base class for AggregateReflection and AssociationReflection. Objects of
    # AggregateReflection and AssociationReflection are returned by the Reflection::ClassMethods.
    class MacroReflection
      attr_reader :active_record

      def initialize(macro, name, options, active_record)
        @macro, @name, @options, @active_record = macro, name, options, active_record
      end

      # Returns the name of the macro.
      #
      # <tt>composed_of :balance, :class_name => 'Money'</tt> returns <tt>:balance</tt>
      # <tt>has_many :clients</tt> returns <tt>:clients</tt>
      attr_reader :name

      # Returns the macro type.
      #
      # <tt>composed_of :balance, :class_name => 'Money'</tt> returns <tt>:composed_of</tt>
      # <tt>has_many :clients</tt> returns <tt>:has_many</tt>
      attr_reader :macro

      # Returns the hash of options used for the macro.
      #
      # <tt>composed_of :balance, :class_name => 'Money'</tt> returns <tt>{ :class_name => "Money" }</tt>
      # <tt>has_many :clients</tt> returns +{}+
      attr_reader :options

      # Returns the class for the macro.
      #
      # <tt>composed_of :balance, :class_name => 'Money'</tt> returns the Money class
      # <tt>has_many :clients</tt> returns the Client class
      def klass
        @klass ||= class_name.constantize
      end

      # Returns the class name for the macro.
      #
      # <tt>composed_of :balance, :class_name => 'Money'</tt> returns <tt>'Money'</tt>
      # <tt>has_many :clients</tt> returns <tt>'Client'</tt>
      def class_name
        @class_name ||= options[:class_name] || derive_class_name
      end

      # Returns +true+ if +self+ and +other_aggregation+ have the same +name+ attribute, +active_record+ attribute,
      # and +other_aggregation+ has an options hash assigned to it.
      def ==(other_aggregation)
        other_aggregation.kind_of?(self.class) && name == other_aggregation.name && other_aggregation.options && active_record == other_aggregation.active_record
      end

      def sanitized_conditions #:nodoc:
        @sanitized_conditions ||= klass.send(:sanitize_sql, options[:conditions]) if options[:conditions]
      end

      private
        def derive_class_name
          name.to_s.camelize
        end
    end


    # Holds all the meta-data about an aggregation as it was specified in the
    # Active Record class.
    class AggregateReflection < MacroReflection #:nodoc:
    end

    # Holds all the meta-data about an association as it was specified in the
    # Active Record class.
    class AssociationReflection < MacroReflection #:nodoc:
      # Returns the target association's class.
      #
      #   class Author < ActiveRecord::Base
      #     has_many :books
      #   end
      #
      #   Author.reflect_on_association(:books).klass
      #   # => Book
      #
      # <b>Note:</b> Do not call +klass.new+ or +klass.create+ to instantiate
      # a new association object. Use +build_association+ or +create_association+
      # instead. This allows plugins to hook into association object creation.
      def klass
        @klass ||= active_record.send(:compute_type, class_name)
      end

      def initialize(macro, name, options, active_record)
        super
        @collection = macro.in?([:has_many, :has_and_belongs_to_many])
      end

      # Returns a new, unsaved instance of the associated class. +options+ will
      # be passed to the class's constructor.
      def build_association(*options)
        klass.new(*options)
      end

      # Creates a new instance of the associated class, and immediately saves it
      # with ActiveRecord::Base#save. +options+ will be passed to the class's
      # creation method. Returns the newly created object.
      def create_association(*options)
        klass.create(*options)
      end

      # Creates a new instance of the associated class, and immediately saves it
      # with ActiveRecord::Base#save!. +options+ will be passed to the class's
      # creation method. If the created record doesn't pass validations, then an
      # exception will be raised.
      #
      # Returns the newly created object.
      def create_association!(*options)
        klass.create!(*options)
      end

      def table_name
        @table_name ||= klass.table_name
      end

      def quoted_table_name
        @quoted_table_name ||= klass.quoted_table_name
      end

      def foreign_key
        @foreign_key ||= options[:foreign_key] || derive_foreign_key
      end

      def primary_key_name
        foreign_key
      end
      deprecate :primary_key_name => :foreign_key

      def foreign_type
        @foreign_type ||= options[:foreign_type] || "#{name}_type"
      end

      def type
        @type ||= options[:as] && "#{options[:as]}_type"
      end

      def primary_key_column
        @primary_key_column ||= klass.columns.find { |c| c.name == klass.primary_key }
      end

      def association_foreign_key
        @association_foreign_key ||= options[:association_foreign_key] || class_name.foreign_key
      end

      def association_primary_key
        @association_primary_key ||=
          options[:primary_key] ||
          !options[:polymorphic] && klass.primary_key ||
          'id'
      end

      def active_record_primary_key
        @active_record_primary_key ||= options[:primary_key] || active_record.primary_key
      end

      def counter_cache_column
        if options[:counter_cache] == true
          "#{active_record.name.demodulize.underscore.pluralize}_count"
        elsif options[:counter_cache]
          options[:counter_cache]
        end
      end

      def columns(tbl_name, log_msg)
        @columns ||= klass.connection.columns(tbl_name, log_msg)
      end

      def reset_column_information
        @columns = nil
      end

      def check_validity!
        check_validity_of_inverse!
      end

      def check_validity_of_inverse!
        unless options[:polymorphic]
          if has_inverse? && inverse_of.nil?
            raise InverseOfAssociationNotFoundError.new(self)
          end
        end
      end

      def through_reflection
        nil
      end

      def source_reflection
        nil
      end

      # A chain of reflections from this one back to the owner. For more see the explanation in
      # ThroughReflection.
      def chain
        [self]
      end

      # An array of arrays of conditions. Each item in the outside array corresponds to a reflection
      # in the #chain. The inside arrays are simply conditions (and each condition may itself be
      # a hash, array, arel predicate, etc...)
      def conditions
        [[options[:conditions]].compact]
      end

      alias :source_macro :macro

      def has_inverse?
        @options[:inverse_of]
      end

      def inverse_of
        if has_inverse?
          @inverse_of ||= klass.reflect_on_association(options[:inverse_of])
        end
      end

      def polymorphic_inverse_of(associated_class)
        if has_inverse?
          if inverse_relationship = associated_class.reflect_on_association(options[:inverse_of])
            inverse_relationship
          else
            raise InverseOfAssociationNotFoundError.new(self, associated_class)
          end
        end
      end

      # Returns whether or not this association reflection is for a collection
      # association. Returns +true+ if the +macro+ is either +has_many+ or
      # +has_and_belongs_to_many+, +false+ otherwise.
      def collection?
        @collection
      end

      # Returns whether or not the association should be validated as part of
      # the parent's validation.
      #
      # Unless you explicitly disable validation with
      # <tt>:validate => false</tt>, validation will take place when:
      #
      # * you explicitly enable validation; <tt>:validate => true</tt>
      # * you use autosave; <tt>:autosave => true</tt>
      # * the association is a +has_many+ association
      def validate?
        !options[:validate].nil? ? options[:validate] : (options[:autosave] == true || macro == :has_many)
      end

      # Returns +true+ if +self+ is a +belongs_to+ reflection.
      def belongs_to?
        macro == :belongs_to
      end

      def association_class
        case macro
        when :belongs_to
          if options[:polymorphic]
            Associations::BelongsToPolymorphicAssociation
          else
            Associations::BelongsToAssociation
          end
        when :has_and_belongs_to_many
          Associations::HasAndBelongsToManyAssociation
        when :has_many
          if options[:through]
            Associations::HasManyThroughAssociation
          else
            Associations::HasManyAssociation
          end
        when :has_one
          if options[:through]
            Associations::HasOneThroughAssociation
          else
            Associations::HasOneAssociation
          end
        end
      end

      private
        def derive_class_name
          class_name = name.to_s.camelize
          class_name = class_name.singularize if collection?
          class_name
        end

        def derive_foreign_key
          if belongs_to?
            "#{name}_id"
          elsif options[:as]
            "#{options[:as]}_id"
          else
            active_record.name.foreign_key
          end
        end
    end

    # Holds all the meta-data about a :through association as it was specified
    # in the Active Record class.
    class ThroughReflection < AssociationReflection #:nodoc:
      delegate :foreign_key, :foreign_type, :association_foreign_key,
               :active_record_primary_key, :type, :to => :source_reflection

      # Gets the source of the through reflection.  It checks both a singularized
      # and pluralized form for <tt>:belongs_to</tt> or <tt>:has_many</tt>.
      #
      #   class Post < ActiveRecord::Base
      #     has_many :taggings
      #     has_many :tags, :through => :taggings
      #   end
      #
      def source_reflection
        @source_reflection ||= source_reflection_names.collect { |name| through_reflection.klass.reflect_on_association(name) }.compact.first
      end

      # Returns the AssociationReflection object specified in the <tt>:through</tt> option
      # of a HasManyThrough or HasOneThrough association.
      #
      #   class Post < ActiveRecord::Base
      #     has_many :taggings
      #     has_many :tags, :through => :taggings
      #   end
      #
      #   tags_reflection = Post.reflect_on_association(:tags)
      #   taggings_reflection = tags_reflection.through_reflection
      #
      def through_reflection
        @through_reflection ||= active_record.reflect_on_association(options[:through])
      end

      # Returns an array of reflections which are involved in this association. Each item in the
      # array corresponds to a table which will be part of the query for this association.
      #
      # The chain is built by recursively calling #chain on the source reflection and the through
      # reflection. The base case for the recursion is a normal association, which just returns
      # [self] as its #chain.
      def chain
        @chain ||= begin
          chain = source_reflection.chain + through_reflection.chain
          chain[0] = self # Use self so we don't lose the information from :source_type
          chain
        end
      end

      # Consider the following example:
      #
      #   class Person
      #     has_many :articles
      #     has_many :comment_tags, :through => :articles
      #   end
      #
      #   class Article
      #     has_many :comments
      #     has_many :comment_tags, :through => :comments, :source => :tags
      #   end
      #
      #   class Comment
      #     has_many :tags
      #   end
      #
      # There may be conditions on Person.comment_tags, Article.comment_tags and/or Comment.tags,
      # but only Comment.tags will be represented in the #chain. So this method creates an array
      # of conditions corresponding to the chain. Each item in the #conditions array corresponds
      # to an item in the #chain, and is itself an array of conditions from an arbitrary number
      # of relevant reflections, plus any :source_type or polymorphic :as constraints.
      def conditions
        @conditions ||= begin
          conditions = source_reflection.conditions

          # Add to it the conditions from this reflection if necessary.
          conditions.first << options[:conditions] if options[:conditions]

          through_conditions = through_reflection.conditions

          if options[:source_type]
            through_conditions.first << { foreign_type => options[:source_type] }
          end

          # Recursively fill out the rest of the array from the through reflection
          conditions += through_conditions

          # And return
          conditions
        end
      end

      # The macro used by the source association
      def source_macro
        source_reflection.source_macro
      end

      # A through association is nested iff there would be more than one join table
      def nested?
        chain.length > 2 || through_reflection.macro == :has_and_belongs_to_many
      end

      # We want to use the klass from this reflection, rather than just delegate straight to
      # the source_reflection, because the source_reflection may be polymorphic. We still
      # need to respect the source_reflection's :primary_key option, though.
      def association_primary_key
        @association_primary_key ||= begin
          # Get the "actual" source reflection if the immediate source reflection has a
          # source reflection itself
          source_reflection = self.source_reflection
          while source_reflection.source_reflection
            source_reflection = source_reflection.source_reflection
          end

          source_reflection.options[:primary_key] || klass.primary_key
        end
      end

      # Gets an array of possible <tt>:through</tt> source reflection names:
      #
      #   [:singularized, :pluralized]
      #
      def source_reflection_names
        @source_reflection_names ||= (options[:source] ? [options[:source]] : [name.to_s.singularize, name]).collect { |n| n.to_sym }
      end

      def source_options
        source_reflection.options
      end

      def through_options
        through_reflection.options
      end

      def check_validity!
        if through_reflection.nil?
          raise HasManyThroughAssociationNotFoundError.new(active_record.name, self)
        end

        if through_reflection.options[:polymorphic]
          raise HasManyThroughAssociationPolymorphicThroughError.new(active_record.name, self)
        end

        if source_reflection.nil?
          raise HasManyThroughSourceAssociationNotFoundError.new(self)
        end

        if options[:source_type] && source_reflection.options[:polymorphic].nil?
          raise HasManyThroughAssociationPointlessSourceTypeError.new(active_record.name, self, source_reflection)
        end

        if source_reflection.options[:polymorphic] && options[:source_type].nil?
          raise HasManyThroughAssociationPolymorphicSourceError.new(active_record.name, self, source_reflection)
        end

        if macro == :has_one && through_reflection.collection?
          raise HasOneThroughCantAssociateThroughCollection.new(active_record.name, self, through_reflection)
        end

        check_validity_of_inverse!
      end

      private
        def derive_class_name
          # get the class_name of the belongs_to association of the through reflection
          options[:source_type] || source_reflection.class_name
        end
    end
  end
end
