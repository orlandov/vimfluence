# This -*- perl -*- script writes the Makefile for this package.

require 5.004_04;
use strict;

my %requires;

# Subroutine to check for installed modules.
sub check_version
{
  my ($pkg, $wanted, $msg) = @_;

  local($|) = 1;
  print "Checking for $pkg...";

  eval { my $p; ($p = $pkg . ".pm") =~ s#::#/#g; require $p; };

  no strict 'refs';

  my $vstr = ${"${pkg}::VERSION"} ? "found v" . ${"${pkg}::VERSION"}
                                 : "not found";
  my $vnum = ${"${pkg}::VERSION"} || 0;

  my $ok = $vnum >= $wanted;
  print $ok ? "ok\n" : " " . $vstr . "\n";

  $requires{$pkg} = $wanted if !$ok;
  return $ok;
}

# Check for needed modules.
if ($^O eq 'MSWin32') {
  check_version('Win32::Process' => '0.04') or
    warn  "\n"
        . "*** For Proc:Background you require version 0.04, or later, of\n"
        . "    Win32::Process from CPAN/authors/id/GSAR/libwin32-x.x.tar.gz\n\n";
}

#--- Configuration section ---

my @programs_to_install = qw(timed-process);

#--- End Configuration - You should not have to change anything below this line

# Allow us to suppress all program installation with the -n (library only)
# option.  This is for those that don't want to mess with the configuration
# section of this file.
use Getopt::Std;
use vars qw($opt_n);
unless (getopts('n')) {
  die "Usage: $0 [-n]\n";
}
@programs_to_install = () if $opt_n;

use ExtUtils::MakeMaker;

WriteMakefile(
  NAME		=> 'Proc::Background',
  VERSION_FROM	=> 'lib/Proc/Background.pm',
  PL_FILES	=> { map {("bin/$_.PL" => "bin/$_")} @programs_to_install },
  EXE_FILES	=> [map {"bin/$_"} @programs_to_install ],
  'clean'	=> {FILES => '$(EXE_FILES)' },
  'dist'        => {
    'COMPRESS'  => 'gzip',
    'SUFFIX'    => 'gz'
  },
  PREREQ_PM => \%requires,
);
