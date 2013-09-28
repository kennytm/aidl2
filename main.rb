#!/usr/bin/ruby -w

#{{{ Extensions

require "pathname"
require "fileutils"

class Pathname # :nodoc:
    # Ruby 1.8 doesn't have #sub_ext.
    unless self.method_defined?(:sub_ext)
        ##
        # Replace the extension of the path.
        def sub_ext(repl)
            self.class.new(@path.chomp(self.extname) + repl)
        end
    end
end

#}}}

##
# Equivalent to require_relative, but is a no-op after we inline everything.
unless defined?(require_unless_inlined)
    def require_unless_inlined(mod)
        if Object.new.respond_to?(:require_relative, true)
            require_relative mod
        else
            require File.expand_path(mod, File.dirname(__FILE__))
        end
    end
end

require_unless_inlined "lexer.rl"
require_unless_inlined "parser.rl"
require_unless_inlined "generic.rl"
require_unless_inlined "java_types"
require_unless_inlined "java_writer"



Options = Struct.new(:project, :updated, :removed)

##
# Parse the command line options.
def parse_options(args)
    res = Options.new(nil, [], [])

    symbol_to_set = nil
    args.each do |arg|
        case arg
        when "--prefix"; symbol_to_set = :project
        when "--update"; symbol_to_set = :updated
        when "--remove"; symbol_to_set = :removed
        else
            if symbol_to_set == :project
                res.project = Pathname.new(arg)
            else
                res[symbol_to_set] << Pathname.new(arg)
            end
        end
    end

    res
end


##
# Filter all `*.aidl2` files in place. The files must be inside the `src/`
# folder in `prefix`.
def filter_aidl2(filenames, prefix)
    src_folder = prefix + "src"
    filenames.map! do |fn|
        rel_path = fn.relative_path_from(src_folder)
        if rel_path.fnmatch?("../bin/classes/*.aidl2", File::FNM_CASEFOLD)
            # Some Eclipse quirks.
            parts = rel_path.enum_for(:each_filename).drop(3)
            Pathname.new(File.join(parts))
        elsif rel_path.fnmatch?("..*")
            nil
        elsif rel_path.fnmatch?("*.aidl2", File::FNM_CASEFOLD)
            rel_path
        end
    end
    filenames.compact!
end


##
# Obtain the absolute path name to place the generated `*.java` file.
def to_gen_pathname(rel_pathname, prefix)
    (prefix + "gen" + rel_pathname).sub_ext(".java")
end


##
# Obtain the absolute path name of the real `*.aidl2` source file.
def to_src_pathname(rel_pathname, prefix)
    prefix + "src" + rel_pathname
end


def create_java(rel_pathname, prefix)
    src_pathname = to_src_pathname(rel_pathname, prefix)
    gen_pathname = to_gen_pathname(rel_pathname, prefix)

    content = File.read(src_pathname)
    return if content.empty?

    token_list = Tokenizer.tokenize(content, rel_pathname)
    interface = Parser.parse(token_list)
    return if interface.nil?

    # Sanity check.
    expected_package_name = []
    package_dir = rel_pathname.dirname
    package_dir.each_filename { |part| expected_package_name << part }
    unless interface.package == expected_package_name.join(".")
        msg = "Wrong package '#{interface.package}' under folder '#{package_dir}'."
        raise ParseError.new(msg, rel_pathname)
    end

    unless interface.name == rel_pathname.basename(".*").to_s
        msg = "Wrong interface name '#{interface.name}' in file '#{rel_pathname.basename}'."
        raise ParseError.new(msg, rel_pathname)
    end

    writer = JavaWriter.new(interface, prefix)
    res = writer.encode_interface
    FileUtils.mkdir_p File.dirname(gen_pathname)
    File.open(gen_pathname, "w") { |f| f.write(res) }
end



def main(args=ARGV)
    ns = parse_options(args)

    filter_aidl2 ns.updated, ns.project
    filter_aidl2 ns.removed, ns.project

    ns.updated.each {|pn| create_java pn, ns.project }

    ns.removed.each do |pn|
        begin
            to_gen_pathname(pn, ns.project).delete
        rescue Errno::ENOENT
            # ignore
        end
    end
rescue ParseError => e
    $stderr.puts e
end



main

