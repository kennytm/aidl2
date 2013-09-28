#!/usr/bin/ruby -w

require "erb"

unless defined?(STATIC_ERBS)
    STATIC_ERBS = Hash.new do |h, fn|
        h[fn] = File.read(File.join(File.dirname(__FILE__), fn))
    end
end


class ERB
    ##
    # Evaluate the ERB template, in the context of the given instance.
    #
    # * `inst` --- The instance to provide the binding.
    # * `_self` --- Just an arbitrary variable, which can be refered from the
    #   ERB named "_self".
    #
    # ## Example
    #
    # ```ruby
    # erb = ERB.new("<%= upcase %>/<%= _self %>")
    # erb.result_of("foo", "bar") #=> "FOO/bar"
    # ```
    #
    def result_of(inst, _self)
        self.result(inst.instance_eval { binding })
    end

    ##
    # Create an ERB template from a static file. The constructed template will
    # assume the "-" trimming mode.
    #
    # This is provided mainly for our custom Rakefile to inline all external
    # ERBs into a single file. This method will first look into the
    # `STATIC_ERBS` hash. If an entry already exists, that cached value will be
    # returned instead.
    def self.import(filename)
        template = STATIC_ERBS[filename]
        erb = ERB.new(template, nil, "-")
        erb.filename = filename
        erb
    end
end


##
# A class which converts an AIDL2Interface into Java code.
class JavaWriter
    attr_reader :prefix, :generic, :generic_arguments

    METHOD_SIGNATURE_ERB = ERB.import("method_signature.erb")
    TRANSACTION_ERB = ERB.import("transaction.erb")
    INTERFACE_ERB = ERB.import("interface.erb")
    PROXY_ERB = ERB.import("proxy.erb")

    def initialize(interface, prefix)
        @interface = interface
        @prefix = prefix
        if interface.generic.nil?
            @generic = []
            @generic_arguments = ""
        else
            @generic = GenericParser.parse(interface.generic)
            @generic_arguments = "<#{@generic.map(&:name).join(', ')}>"
        end
    end

    def encode_interface
        path = typename_to_path(@interface.name, prefix, package, ".aidl2")
        _self = self
        INTERFACE_ERB.result(@interface.instance_eval { binding })
    end

    def tokens
        @interface.tokens
    end

    def package
        @interface.package
    end

    def imports
        @interface.imports
    end
end

