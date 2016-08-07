require "rails/railtie"
require "trailblazer/loader"

module Trailblazer
  class Railtie < ::Rails::Railtie
    CONCEPTS_ROOT = "app/concepts/"

    def self.load_concepts(app)
      options = {
        insert: [ModelFile, before: Loader::AddConceptFiles],
        concepts_root: CONCEPTS_ROOT
      }

      Loader.new.(options)  { |file|
        autoload_file(app, file)
      }
    end

    def self.autoload_file(app, file)
      if file.start_with?(CONCEPTS_ROOT)
        split_file = file.gsub(CONCEPTS_ROOT, '').gsub(/contracts\/|operations\//, '').split('/')
        module_list = split_file[0..-2].map(&:camelize)
        class_string = split_file[-1].gsub('.rb', '').camelize

        get_module(module_list).class_eval do
          autoload class_string, "#{app.root}/#{file}"
        end
      else
        require_dependency("#{app.root}/#{file}")
      end
    end

    def self.get_module(module_list)
      Kernel.const_get(module_list.join('::'))
    rescue
      module_compose = ''
      module_list.each do |next_module|
        previous_module = module_compose
        module_compose << "::#{next_module}"
        begin
          Kernel.const_get(module_compose)
        rescue
          klass = previous_module.empty? ? Kernel : Kernel.const_get(previous_module)
          klass.const_set(next_module, Module.new)
        end
      end
      Kernel.const_get(module_list.join('::'))
    end

    # This is to autoload Operation::Dispatch, etc. I'm simply assuming people find this helpful in Rails.
    initializer "trailblazer.library_autoloading" do
      require "trailblazer/autoloading"
    end

    # thank you, http://stackoverflow.com/a/17573888/465070
    initializer 'trailblazer.install', after: "reform.form_extensions" do |app|
      # the trb autoloading has to be run after initializers have been loaded, so we can tweak inclusion of features in
      # initializers.
      reloader_class.to_prepare do
        Trailblazer::Railtie.load_concepts(app)
      end
    end

    # initializer "trailblazer.roar" do
    #   require "trailblazer/rails/roar" #if Object.const_defined?(:Roar)
    # end

    initializer "trailblazer.application_controller" do
      ActiveSupport.on_load(:action_controller) do
        include Trailblazer::Operation::Controller
      end
    end

    # Prepend model file, before the concept files like operation.rb get loaded.
    ModelFile = ->(input, options) do
      model = "app/models/#{options[:name]}.rb"
      File.exist?(model) ? [model]+input : input
    end

    private

    def reloader_class
      # Rails 5.0.0.rc1 says:
      # DEPRECATION WARNING: to_prepare is deprecated and will be removed from Rails 5.1
      # (use ActiveSupport::Reloader.to_prepare instead)
      if Gem.loaded_specs['activesupport'].version >= Gem::Version.new('5')
        ActiveSupport::Reloader
      else
        ActionDispatch::Reloader
      end
    end
  end
end
