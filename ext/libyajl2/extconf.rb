exit(0) if ENV["USE_SYSTEM_LIBYAJL2"]

require 'rbconfig'
require 'fileutils'
require 'mkmf'

module Libyajl2Build
  class BuildError < StandardError; end

  LIBYAJL2_VENDOR_DIR = File.expand_path("../vendor/yajl", __FILE__).freeze

  PREFIX = File.expand_path("../../../lib/libyajl2/vendored-libyajl2", __FILE__).freeze

  def self.windows?
    !!(RUBY_PLATFORM =~ /mswin|mingw|windows/)
  end

  def self.libyajl2_vendor_dir
    LIBYAJL2_VENDOR_DIR
  end

  def self.prefix
    PREFIX
  end

  def self.setup_env
    RbConfig::MAKEFILE_CONFIG['CC'] = ENV['CC'] if ENV['CC']

    # set some sane defaults
    if RbConfig::MAKEFILE_CONFIG['CC'] =~ /gcc|clang/
      # magic flags copied from upstream yajl build system (-std=c99 is necessary for older gcc)
      $CFLAGS << " -std=c99 -pedantic -Wpointer-arith -Wno-format-y2k -Wstrict-prototypes -Wmissing-declarations -Wnested-externs -Wextra  -Wundef -Wwrite-strings -Wold-style-definition -Wredundant-decls -Wno-unused-parameter -Wno-sign-compare -Wmissing-prototypes"
      $CFLAGS << " -O2"  # match what the upstream uses for optimization

      # create the implib on windows
      if windows?
        $LDFLAGS << " -Wl,--export-all-symbols -Wl,--enable-auto-import -Wl,--out-implib=libyajldll.a -Wl,--output-def,libyajl.def"
      end
    end

    $CFLAGS << " -DNDEBUG"
  end

  def self.makemakefiles
    setup_env
    dir_config("libyajl")
    create_makefile("libyajl")

    # on windows the Makefile will try to export Init_libyajl which is wrong because we aren't a ruby lib.
    # i could not figure out how to tell mkmf.rb to stop being so helpful, so instead will just patch it here.
    if windows?
      makefile = IO.read("Makefile")
      makefile.gsub!(/\$\(DEFFILE\)/, '')
      File.open("Makefile", 'w+') {|f| f.write(makefile) }
    end

    system("pwd")
    # we cheat and build it right away...
    system("make >make.out 2>&1") || raise # rubinius doesn't like the output this generates
    # ...so we can hack up what install does later and copy over the include files

    # not sure why ruby windows produces .so's instead of .dll's
    if windows?
      FileUtils.mv "libyajl.so", "yajl.dll"
    end

    File.open("Makefile", "w+") do |f|
      f.write <<EOF
TARGET = libyajl
DLLIB = $(TARGET).#{RbConfig::MAKEFILE_CONFIG['DLEXT']}
all:

EOF
      if windows?
        f.write <<EOF
install:
\tmkdir -p #{prefix}/lib
\tcp yajl.dll #{prefix}/lib/yajl.dll
\tcp libyajldll.a #{prefix}/lib/libyajldll.a
\tcp libyajl.def #{prefix}/lib/libyajl.def
\tmkdir -p #{prefix}/include/yajl
\tcp yajl/*.h #{prefix}/include/yajl
EOF
      else
        f.write <<EOF
install:
\tmkdir -p #{prefix}/lib
\tcp $(DLLIB) #{prefix}/lib/$(DLLIB)
\tmkdir -p #{prefix}/include/yajl
\tcp yajl/*.h #{prefix}/include/yajl
EOF
      end
    end
  end
end

Libyajl2Build.makemakefiles

