#!/usr/bin/ruby -w

require "zlib"
require "base64"

data = File.read("build_aidl2.rb")
# Strip the initial comments (the license text), and paste it into the result.

license_end = data.index('=end') + 4
init_text = data[0..license_end]

compressed = Zlib::Deflate.deflate(data[license_end..-1], Zlib::BEST_COMPRESSION)
base64 = Base64.encode64(compressed)

File.open("build_aidl2_z.rb", "w") do |f|
    f.write(<<EOF)
#{init_text}
require "zlib"
require "base64"
eval Zlib::Inflate.inflate(Base64.decode64("#{base64}")), binding, "build_aidl.rb", #{init_text.count("\n")}
EOF
end

