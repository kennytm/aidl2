require "rake/clean"

rule /\.rl\.rb\z/ => proc { |f| File.basename(f, '.rb') } do |t|
    sh "ragel -s -L -F1 -R -o #{t.name} #{t.source}"
end

file "inlined_files.tmp.rb" => FileList["*.erb", "known_parcelables.txt"] do |t|
    File.open(t.name, "w") do |f|
        f.write(<<EOF)
#!/usr/bin/ruby -w

# This is a generated file. DO NOT EDIT.
# Checkout <https://github.com/kennytm/aidl2> instead.

=begin GPLv3

build_aidl2.rb --- AIDL with more options.

Copyright (C) 2013  HiHex Ltd.

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program.  If not, see <http://www.gnu.org/licenses/>.

=end

require \"set\"

def require_unless_inlined(mod)
end

STATIC_ERBS = {}

EOF

        t.prerequisites.each do |fn|
            if fn.end_with?('.erb')
                f.write("STATIC_ERBS[#{fn.inspect}] = #{File.read(fn).inspect}\n")
            elsif fn == "known_parcelables.txt"
                f.write("PARCELABLE_TYPES = Set.new(%w(#{File.read(fn)}))\n")
            end
        end
    end
end

file "build_aidl2.rb" => %w(inlined_files.tmp.rb lexer.rl.rb parser.rl.rb
                            java_types.rb java_writer.rb main.rb) do |t|
    File.open(t.name, "w", 0755) do |f|
        t.prerequisites.each do |fn|
            f.write(File.read(fn))
        end
    end
end

file "sample/build_aidl2.rb" => "build_aidl2.rb" do |t|
    cp "build_aidl2.rb", t.name
end

task :default => ["sample/build_aidl2.rb", "build_aidl2.rb"]

CLEAN.include(["*.rl.rb", "*.tmp.rb"])
CLOBBER.include("build_aidl2.rb")

