require "rbconfig"

module RSpec
  module Core
    class Configuration
      include RSpec::Core::Hooks

      def self.add_setting(name, opts={})
        if opts[:alias]
          alias_method name, opts[:alias]
          alias_method "#{name}=", "#{opts[:alias]}="
          alias_method "#{name}?", "#{opts[:alias]}?"
        else
          define_method("#{name}=") {|val| settings[name] = val}
          define_method(name)       { settings.has_key?(name) ? settings[name] : opts[:default] }
          define_method("#{name}?") { send name }
        end
      end

      add_setting :error_stream
      add_setting :output_stream
      add_setting :output, :alias => :output_stream
      add_setting :out, :alias => :output_stream
      add_setting :drb
      add_setting :drb_port
      add_setting :profile_examples
      add_setting :fail_fast
      add_setting :run_all_when_everything_filtered
      add_setting :filter
      add_setting :exclusion_filter
      add_setting :filename_pattern, :default => '**/*_spec.rb'
      add_setting :files_to_run
      add_setting :include_or_extend_modules
      add_setting :backtrace_clean_patterns
      add_setting :tty
      add_setting :treat_symbols_as_metadata_keys_with_true_values, :default => false
      add_setting :expecting_with_rspec

      def initialize
        @color_enabled = false
        self.include_or_extend_modules = []
        self.files_to_run = []
        self.backtrace_clean_patterns = [
          /\/lib\d*\/ruby\//,
          /bin\//,
          /gems/,
          /spec\/spec_helper\.rb/,
          /lib\/rspec\/(core|expectations|matchers|mocks)/
        ]

        filter_run_excluding(
          :if     => lambda { |value, metadata| metadata.has_key?(:if) && !value },
          :unless => lambda { |value| value }
        )
      end

      # :call-seq:
      #   add_setting(:name)
      #   add_setting(:name, :default => "default_value")
      #   add_setting(:name, :alias => :other_setting)
      #
      # Use this to add custom settings to the RSpec.configuration object.
      #
      #   RSpec.configuration.add_setting :foo
      #
      # Creates three methods on the configuration object, a setter, a getter,
      # and a predicate:
      #
      #   RSpec.configuration.foo=(value)
      #   RSpec.configuration.foo()
      #   RSpec.configuration.foo?() # returns true if foo returns anything but nil or false
      #
      # Intended for extension frameworks like rspec-rails, so they can add config
      # settings that are domain specific. For example:
      #
      #   RSpec.configure do |c|
      #     c.add_setting :use_transactional_fixtures, :default => true
      #     c.add_setting :use_transactional_examples, :alias => :use_transactional_fixtures
      #   end
      #
      # == Options
      #
      # +add_setting+ takes an optional hash that supports the following
      # keys:
      #
      #   :default => "default value"
      #
      # This sets the default value for the getter and the predicate (which
      # will return +true+ as long as the value is not +false+ or +nil+).
      #
      #   :alias => :other_setting
      #
      # Aliases its setter, getter, and predicate, to those for the
      # +other_setting+.
      def add_setting(name, opts={})
        self.class.add_setting(name, opts)
      end

      def puts(message)
        output_stream.puts(message)
      end

      def settings
        @settings ||= {}
      end

      def clear_inclusion_filter # :nodoc:
        self.filter = nil
      end

      def cleaned_from_backtrace?(line)
        backtrace_clean_patterns.any? { |regex| line =~ regex }
      end

      # Returns the configured mock framework adapter module
      def mock_framework
        settings[:mock_framework] ||= begin
                                        require 'rspec/core/mocking/with_rspec'
                                        RSpec::Core::MockFrameworkAdapter
                                      end
      end

      # Delegates to mock_framework=(framework)
      def mock_with(framework)
        self.mock_framework = framework
      end

      # Sets the mock framework adapter module.
      #
      # +framework+ can be a Symbol or a Module.
      #
      # Given any of :rspec, :mocha, :flexmock, or :rr, configures the named
      # framework.
      #
      # Given :nothing, configures no framework. Use this if you don't use any
      # mocking framework to save a little bit of overhead.
      #
      # Given a Module, includes that module in every example group. The module
      # should adhere to RSpec's mock framework adapter API:
      #
      #   setup_mocks_for_rspec
      #     - called before each example
      #
      #   verify_mocks_for_rspec
      #     - called after each example. Framework should raise an exception
      #       when expectations fail
      #
      #   teardown_mocks_for_rspec
      #     - called after verify_mocks_for_rspec (even if there are errors)
      def mock_framework=(framework)
        case framework
        when Module
          settings[:mock_framework] = framework
        when String, Symbol
          require case framework.to_s
                  when /rspec/i
                    'rspec/core/mocking/with_rspec'
                  when /mocha/i
                    'rspec/core/mocking/with_mocha'
                  when /rr/i
                    'rspec/core/mocking/with_rr'
                  when /flexmock/i
                    'rspec/core/mocking/with_flexmock'
                  else
                    'rspec/core/mocking/with_absolutely_nothing'
                  end
          settings[:mock_framework] = RSpec::Core::MockFrameworkAdapter
        else
        end
      end

      # Returns the configured expectation framework adapter module(s)
      def expectation_frameworks
        expect_with :rspec unless settings[:expectation_frameworks]
        settings[:expectation_frameworks]
      end

      # Delegates to expect_with([framework])
      def expectation_framework=(framework)
        expect_with([framework])
      end

      # Sets the expectation framework module(s).
      #
      # +frameworks+ can be :rspec, :stdlib, or both 
      #
      # Given :rspec, configures rspec/expectations.
      # Given :stdlib, configures test/unit/assertions
      # Given both, configures both
      def expect_with(*frameworks)
        settings[:expectation_frameworks] = []
        frameworks.each do |framework|
          case framework
          when Symbol
            case framework
            when :rspec
              require 'rspec/core/expecting/with_rspec'
              self.expecting_with_rspec = true
            when :stdlib
              require 'rspec/core/expecting/with_stdlib'
            else
              raise ArgumentError, "#{framework.inspect} is not supported"
            end
            settings[:expectation_frameworks] << RSpec::Core::ExpectationFrameworkAdapter
          end
        end
      end

      def full_backtrace=(bool)
        settings[:backtrace_clean_patterns] = []
      end

      def color_enabled
        @color_enabled && output_to_tty?
      end

      def color_enabled?
        color_enabled
      end

      def color_enabled=(bool)
        return unless bool
        @color_enabled = true
        if bool && ::RbConfig::CONFIG['host_os'] =~ /mswin|mingw/
          unless ENV['ANSICON']
            warn "You must use ANSICON 1.31 or later (http://adoxa.110mb.com/ansicon/) to use colour on Windows"
            @color_enabled = false
          end
        end
      end

      def libs=(libs)
        libs.map {|lib| $LOAD_PATH.unshift lib}
      end

      def requires=(paths)
        paths.map {|path| require path}
      end

      def debug=(bool)
        return unless bool
        begin
          require 'ruby-debug'
          Debugger.start
        rescue LoadError
          raise <<-EOM

#{'*'*50}
You must install ruby-debug to run rspec with the --debug option.

If you have ruby-debug installed as a ruby gem, then you need to either
require 'rubygems' or configure the RUBYOPT environment variable with
the value 'rubygems'.
#{'*'*50}
EOM
        end
      end

      def line_number=(line_number)
        filter_run({ :line_number => line_number.to_i }, true)
      end

      def full_description=(description)
        filter_run({ :full_description => /#{description}/ }, true)
      end

      def add_formatter(formatter_to_use, output=nil)
        formatter_class =
          built_in_formatter(formatter_to_use) ||
          custom_formatter(formatter_to_use) ||
          (raise ArgumentError, "Formatter '#{formatter_to_use}' unknown - maybe you meant 'documentation' or 'progress'?.")

        formatters << formatter_class.new(output ? File.new(output, 'w') : self.output)
      end

      alias_method :formatter=, :add_formatter

      def formatters
        @formatters ||= []
      end

      def reporter
        @reporter ||= begin
                        add_formatter('progress') if formatters.empty?
                        Reporter.new(*formatters)
                      end
      end

      def files_or_directories_to_run=(*files)
        self.files_to_run = files.flatten.collect do |file|
          if File.directory?(file)
            filename_pattern.split(",").collect do |pattern|
              Dir["#{file}/#{pattern.strip}"]
            end
          else
            if file =~ /(\:(\d+))$/
              self.line_number = $2
              file.sub($1,'')
            else
              file
            end
          end
        end.flatten
      end

      # E.g. alias_example_to :crazy_slow, :speed => 'crazy_slow' defines
      # crazy_slow as an example variant that has the crazy_slow speed option
      def alias_example_to(new_name, extra_options={})
        RSpec::Core::ExampleGroup.alias_example_to(new_name, extra_options)
      end

      # Define an alias for it_should_behave_like that allows different
      # language (like "it_has_behavior" or "it_behaves_like") to be
      # employed when including shared examples.
      #
      # Example:
      #
      #     alias_it_should_behave_like_to(:it_has_behavior, 'has behavior:')
      #
      # allows the user to include a shared example group like:
      #
      #     describe Entity do
      #       it_has_behavior 'sortability' do
      #         let(:sortable) { Entity.new }
      #       end
      #     end
      #
      # which is reported in the output as:
      #
      #     Entity
      #       has behavior: sortability
      #         # sortability examples here
      def alias_it_should_behave_like_to(new_name, report_label = '')
        RSpec::Core::ExampleGroup.alias_it_should_behave_like_to(new_name, report_label)
      end

      def filter_run_including(options={}, force_overwrite = false)
        if filter and filter[:line_number] || filter[:full_description]
          warn "Filtering by #{options.inspect} is not possible since " \
               "you are already filtering by #{filter.inspect}"
        else
          if force_overwrite
            self.filter = options
          else
            self.filter = (filter || {}).merge(options)
          end
        end
      end

      alias_method :filter_run, :filter_run_including

      def filter_run_excluding(options={})
        self.exclusion_filter = (exclusion_filter || {}).merge(options)
      end

      def include(mod, filters={})
        include_or_extend_modules << [:include, mod, filters]
      end

      def extend(mod, filters={})
        include_or_extend_modules << [:extend, mod, filters]
      end

      def configure_group(group)
        modules = {
          :include => group.included_modules.dup,
          :extend  => group.ancestors.dup
        }

        include_or_extend_modules.each do |include_or_extend, mod, filters|
          next unless filters.empty? || group.apply?(:any?, filters)
          group.send(include_or_extend, mod)
        end
      end

      # Extend groups matching submitted metadata with methods, subject declarations
      # and let/let! declarations.
      #
      # Example:
      #
      #   RSpec.configure do |c|
      #     c.for_matching_groups :type => :model do
      #       def a_method
      #         "a value"
      #       end
      #       subject { Factory described_class.to_s.underscore }
      #       let(:valid_attributes) { Factory.attributes_for described_class.to_sym }
      #     end
      #   end
      def for_groups_matching(filters = {}, &block)
        mod = Module.new
        (class << mod; self; end).send(:define_method, :extended) do |host|
          host.class_eval(&block)
        end
        self.extend(mod, filters)
      end

      def configure_mock_framework
        RSpec::Core::ExampleGroup.send(:include, mock_framework)
      end

      def configure_expectation_framework
        expectation_frameworks.each do |framework|
          RSpec::Core::ExampleGroup.send(:include, framework)
        end
      end

      def load_spec_files
        files_to_run.map {|f| load File.expand_path(f) }
        raise_if_rspec_1_is_loaded
      end

    private

      def raise_if_rspec_1_is_loaded
        if defined?(Spec) && defined?(Spec::VERSION::MAJOR) && Spec::VERSION::MAJOR == 1
          raise <<-MESSAGE

#{'*'*80}
  You are running rspec-2, but it seems as though rspec-1 has been loaded as
  well.  This is likely due to a statement like this somewhere in the specs:

      require 'spec'

  Please locate that statement, remove it, and try again.
#{'*'*80}
MESSAGE
        end
      end

      def output_to_tty?
        begin
          output_stream.tty? || tty?
        rescue NoMethodError
          false
        end
      end

      def built_in_formatter(key)
        case key.to_s
        when 'd', 'doc', 'documentation', 's', 'n', 'spec', 'nested'
          require 'rspec/core/formatters/documentation_formatter'
          RSpec::Core::Formatters::DocumentationFormatter
        when 'h', 'html'
          require 'rspec/core/formatters/html_formatter'
          RSpec::Core::Formatters::HtmlFormatter
        when 't', 'textmate'
          require 'rspec/core/formatters/text_mate_formatter'
          RSpec::Core::Formatters::TextMateFormatter
        when 'p', 'progress'
          require 'rspec/core/formatters/progress_formatter'
          RSpec::Core::Formatters::ProgressFormatter
        end
      end

      def custom_formatter(formatter_ref)
        if Class === formatter_ref
          formatter_ref
        elsif string_const?(formatter_ref)
          begin
            eval(formatter_ref)
          rescue NameError
            require path_for(formatter_ref)
            eval(formatter_ref)
          end
        end
      end

      def string_const?(str)
        str.is_a?(String) && /\A[A-Z][a-zA-Z0-9_:]*\z/ =~ str
      end

      def path_for(const_ref)
        underscore_with_fix_for_non_standard_rspec_naming(const_ref)
      end

      def underscore_with_fix_for_non_standard_rspec_naming(string)
        underscore(string).sub(%r{(^|/)r_spec($|/)}, '\\1rspec\\2')
      end

      # activesupport/lib/active_support/inflector/methods.rb, line 48
      def underscore(camel_cased_word)
        word = camel_cased_word.to_s.dup
        word.gsub!(/::/, '/')
        word.gsub!(/([A-Z]+)([A-Z][a-z])/,'\1_\2')
        word.gsub!(/([a-z\d])([A-Z])/,'\1_\2')
        word.tr!("-", "_")
        word.downcase!
        word
      end
    end
  end
end
