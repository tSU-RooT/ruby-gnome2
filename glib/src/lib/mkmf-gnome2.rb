require 'mkmf'
require 'shellwords'

module PKGConfig
  @@cmd = with_config('pkg-config', ENV["PKG_CONFIG"] ||  'pkg-config')
  if /mswin32/ =~ RUBY_PLATFORM and /^cl\b/ =~ Config::CONFIG['CC']
    @@cmd += ' --msvc-syntax'
  end

  module_function
  def exist?(pkg)
    system("#{@@cmd} --exists #{pkg}")
  end

  def libs(pkg)
    `#{@@cmd} --libs #{pkg}`.chomp
  end

  def libs_only_L(pkg)
    `#{@@cmd} --libs-only-L #{pkg}`.chomp
  end

  def libs_only_l(pkg)
    `#{@@cmd} --libs-only-l #{pkg}`.chomp
  end

  def cflags(pkg)
    `#{@@cmd} --cflags #{pkg}`.chomp
  end

  def variable(pkg, var)
    `#{@@cmd} --variable=#{var} #{pkg}`.chomp
  end

  def modversion(pkg)
    `#{@@cmd} --modversion #{pkg}`.chomp
  end

  def check_version?(pkg, major = 0, minor = 0, micro = 0)
    return false unless exist?(pkg)
    ver = modversion(pkg).split(".").collect{|item| item.to_i}
    (0..2).each {|i| ver[i] = 0 unless ver[i]}

    (ver[0] > major ||
     (ver[0] == major && ver[1] > minor) ||
     (ver[0] == major && ver[1] == minor &&
      ver[2] >= micro))
  end

  def have_package(pkg, major = 0, minor = 0, micro = 0)
    if major > 0
      STDOUT.print("checking for #{pkg} version (>= #{major}.#{minor}.#{micro})... ")
    else
      STDOUT.print("checking for #{pkg}... ")
    end
    STDOUT.flush
    if check_version?(pkg, major, minor, micro)
      STDOUT.print "yes\n"
      libs = libs_only_l(pkg)
      ldflags = libs(pkg)
      ldflags = (Shellwords.shellwords(ldflags) - Shellwords.shellwords(libs)).map{|s| /\s/ =~ s ? "\"#{s}\"" : s }.join(' ')
      $libs   += ' ' + libs
      $LDFLAGS += ' ' + ldflags
      $CFLAGS += ' ' + cflags(pkg)
      true
    else
      STDOUT.print "no\n"
      false
    end
  end
end

unless defined? macro_defined?
  def macro_defined?(macro, src, opt="")
    try_cpp(src + <<EOP, opt)
#ifndef #{macro}
# error
#endif
EOP
  end
end


STDOUT.print("checking for GCC... ")
STDOUT.flush
if macro_defined?("__GNUC__", "")
  STDOUT.print "yes\n"
  $CFLAGS += ' -Wall' 
  $cc_is_gcc = true
else
  STDOUT.print "no\n"
  $cc_is_gcc = false
end


def check_win32()
  $G_PLATFORM_WIN32 = false
  $G_OS_WIN32       = false
  $G_WITH_CYGWIN    = false

  STDOUT.print("checking for G_PLATFORM_WIN32... ")
  STDOUT.flush
  if macro_defined?('G_PLATFORM_WIN32', "#include <glibconfig.h>\n")
    STDOUT.print "yes\n"
    $G_PLATFORM_WIN32 = true
  else
    STDOUT.print "no\n"
  end

  if $G_PLATFORM_WIN32
    STDOUT.print("checking for G_OS_WIN32... ")
    STDOUT.flush
    if macro_defined?('G_OS_WIN32', "#include <glibconfig.h>\n")
      STDOUT.print "yes\n"
      $G_OS_WIN32 = true
      if $cc_is_gcc
	if /^2\./ =~ `#{Config::CONFIG['CC']} -dumpversion`.chomp
	  $CFLAGS += ' -fnative-struct'
	else
	  $CFLAGS += ' -mms-bitfields'
	end
      end
    else
      STDOUT.print "no\n"
    end

#    STDOUT.print("checking for G_WITH_CYGWIN... ")
#    STDOUT.flush
#    if macro_defined?('G_WITH_CYGWIN', "#include <glibconfig.h>\n")
#      STDOUT.print "yes\n"
#      $G_WITH_CYGWIN = true
#    else
#      STDOUT.print "no\n"
#    end
  end

  nil
end


def set_output_lib(filename)
  if /cygwin|mingw/ =~ RUBY_PLATFORM
    if RUBY_VERSION > "1.8.0"
      $DLDFLAGS << ",--out-implib=#{filename}" if filename
    elsif RUBY_VERSION > "1.8"
      CONFIG["DLDFLAGS"].gsub!(/ -Wl,--out-implib=[^ ]+/, '')
      CONFIG["DLDFLAGS"] << " -Wl,--out-implib=#{filename}" if filename
    else
      CONFIG["DLDFLAGS"].gsub!(/ --output-lib\s+[^ ]+/, '')
      CONFIG["DLDFLAGS"] << " --output-lib #{filename}" if filename
    end
  end
end

$CPPFLAGS << " -I$(sitearchdir) "

def create_top_makefile(sub_dirs = ["src"])
  mfile = File.open("Makefile", "w")
=begin
  if /mswin32/ =~ RUBY_PLATFORM
    mfile.print <<END

all:
		@cd src
		@nmake -nologo

install:
		@cd src
		@nmake -nologo install DESTDIR=$(DESTDIR)

site-install:
		@cd src
		@nmake -nologo site-install DESTDIR=$(DESTDIR)

clean:
		@cd src
		@nmake -nologo clean
		@cd ..
		@-rm -f Makefile extconf.h conftest.*
		@-rm -f *.lib *~
END
  else
=end
    mfile.print <<END
all:
#{sub_dirs.map{|d| "	@cd #{d}; make all\n"}.join('')}

install:
#{sub_dirs.map{|d| "	@cd #{d}; make install\n"}.join('')}
site-install:
#{sub_dirs.map{|d| "	@cd #{d}; make site-install\n"}.join('')}
clean:
#{sub_dirs.map{|d| "	@cd #{d}; make clean\n"}.join('')}
distclean:	clean
#{sub_dirs.map{|d| "	@cd #{d}; make distclean\n"}.join('')}
	@rm -f Makefile extconf.h conftest.*
	@rm -f core *~ mkmf.log
END
#  end
  mfile.close
end

#Other options
have_func("rb_define_alloc_func") # for ruby-1.8
have_func("rb_block_proc") # for ruby-1.8

STDOUT.print("checking for new allocation framework... ") # for ruby-1.7
if Object.respond_to? :allocate
  STDOUT.print "yes\n"
  $defs << "-DHAVE_OBJECT_ALLOCATE"
else
  STDOUT.print "no\n"
end
                                                                                              
STDOUT.print("checking for attribute assignment... ") # for ruby-1.7
STDOUT.flush
if defined? try_compile and try_compile <<SRC
#include "ruby.h"
#include "node.h"
int node_attrasgn = (int)NODE_ATTRASGN;
SRC
  STDOUT.print "yes\n"
  $defs << "-DHAVE_NODE_ATTRASGN"
else
  STDOUT.print "no\n"
end

def add_obj(name)
  $objs << name unless $objs.index(name)
end
