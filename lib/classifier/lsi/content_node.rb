# Author::    David Fayram  (mailto:dfayram@lensmen.net)
# Copyright:: Copyright (c) 2005 David Fayram II
# License::   LGPL

module Classifier
  class LSI
    
    # This is an internal data structure class for the LSI node. Save for 
    # raw_vector_with, it should be fairly straightforward to understand.
    # You should never have to use it directly.
    class ContentNode
      attr_accessor :raw_vector, :raw_norm, :lsi_vector, :lsi_norm
      attr_reader :lsi
      
      # Finds all nodes matching the conditions.
      def self.filter(db, conditions={})
        db[:content_nodes].filter(conditions)
      end
      
      # Finds a node by its retrieval key.
      def self.find(db, key)
        filter(db, :retrieval_key => key)
      end
      
      # Find a node by its source content.
      def self.find_by_content(db, content)
        filter(db, :source => content)
      end
      
      # Find a node's key by its content.
      def self.find_key_by_content(db, content)
        find_by_content(db, content).map { |n| n[:retrieval_key] }.first
      end
      
      # Removes the node and returns its old ID.
      def self.destroy(db, key)
        return unless record = find(db, key)
        
        record_id = record[:id]
        filter(db, :retrieval_key => key).delete
        record_id
      end
      
      # Options:
      #  - key (unique identifier)
      #  - categories (array)
      def initialize( lsi, source, options={} )
        @lsi = lsi
        
        source = source.to_s
        options[:persist] = true unless options.has_key?(:persist)
        options[:categories] ||= []
        options[:key] ||= source.to_s
        
        if options[:persist]
          source = source.to_s
          @db_id = db[:content_nodes].insert(
            :source => source,
            :retrieval_key => options[:key]
          )
        else
          @db_id = nil
          @source = source
          @key = options[:key]
        end
        
        self.categories = options[:categories]
        self.words = source
      end
      
      def id
        @db_id
      end
      
      def persisted?
        !!@db_id
      end
      
      # The database record associated with this node.
      def record
        db[:content_nodes][:id => @db_id]
      end
      
      # The record's unique key, or the original text if no key was provided.
      def key
        @key || record[:retrieval_key]
      end
      
      alias :to_s :key
      
      # The original text.
      def content
        @source || record[:source]
      end
      
      # List all categories for this node.
      def categories
        (@categories || category_records.map { |c| c[:name] }).sort
      end
      
      def categories=(list=[])
        return @categories = [*list] unless @db_id
        
        db[:categories_content_nodes].filter(:content_node_id => self.id).delete
        [*list].each { |category| add_category(category) }
      end
      
      # Add a category to this node. Adding categories does not invalidate
      # the index.
      def add_category(category)
        if @categories
          @categories << category
          return @categories.sort!
        end
        
        conditions = { :name => category }
        category_id =
          db[:categories].filter(conditions).map { |a| a[:id] }.first ||
          db[:categories].insert(conditions)
        
        db[:categories_content_nodes].insert(
          :content_node_id => self.id,
          :category_id => category_id
        )
        
        categories
      end
      
      # List all stemmed words for this node. Mostly for debugging.
      def words
        @words ||
        Hash[ word_records.map { |w| [ w[:stem], w[:frequency] ] }.sort ]
      end
      
      def stems
        @words.keys || word_records.map { |w| w[:stem] }.sort
      end
      
      # Use this to fetch the appropriate search vector.
      def search_vector
        @lsi_vector || @raw_vector
      end
      
      # Use this to fetch the appropriate search vector in normalized form.
      def search_norm
        @lsi_norm || @raw_norm
      end
      
      # Creates the raw vector using all words in the classifier as the
      # key for mapping the vector space.
      def generate_raw_vector
        vec = $GSL ?
          GSL::Vector.alloc(lsi_words.size) : 
          Array.new(lsi_words.size, 0)
        
        words.each do |word, frequency|
          vec[ lsi_words[word] ] = frequency if lsi_words.includes?(word)
        end
        
        # Perform the scaling transform
        total_words = vec.sum
        
        # Perform first-order association transform if this vector has more
        # than one word in it. 
        if total_words > 1.0
          weighted_t = 0.0
          vec.each do |term|
            if term > 0
              weighted_t += (term / total_words) * Math.log(term / total_words)
            end
          end
          vec = vec.collect { |val| Math.log( val + 1 ) / -weighted_t }
        end
        
        if $GSL
          @raw_norm   = vec.normalize
          @raw_vector = vec
        else
          @raw_norm   = Vector[*vec].normalize
          @raw_vector = Vector[*vec]
        end
      end
      
      
      private
      
      def db
        @lsi.db
      end
      
      def lsi_words
        @lsi.word_list
      end
      
      def words=(source="")
        return @words = WordHash.new(source) unless @db_id
        
        WordHash.new(source).each do |word, frequency|
          conditions = { :stem => word }
          word_id =
            db[:words].filter(conditions).map { |a| a[:id] }.first ||
            db[:words].insert(conditions)
            
          db[:word_lists].insert(
            :content_node_id => self.id,
            :word_id => word_id,
            :frequency => frequency
          )
        end
      end
      
      def category_records
        db[:categories_content_nodes].
          filter(:content_node_id => self.id).
          join(:categories, :id => :category_id)
      end
      
      def word_records
        db[:word_lists].
          filter(:content_node_id => self.id).
          join(:words, :id => :word_id)
      end
    end
    
  end
end