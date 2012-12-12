use Config;
use File::Basename qw(basename dirname);
chdir(dirname($0));
($file = basename($0)) =~ s/\.PL$//;
$file =~ s/\.pl$//
        if ($Config{'osname'} eq 'VMS' or
            $Config{'osname'} eq 'OS2');  # "case-forgiving"
open OUT,">$file" or die "Can't create $file: $!";
chmod(0755, $file);
print "Extracting $file (with variable substitutions)\n";

print OUT <<"!GROK!THIS!";
$Config{'startperl'} -w

!GROK!THIS!

print OUT <<'!NO!SUBS!';
=head1 NAME

timed-process - Run background process for limited amount of time

=head1 SYNOPSIS

    timed-process [-e exit_status] timeout command [<arg> [<arg> ...]]

=head1 DESCRIPTION

This script runs I<command> for a specified amount of time and if it
doesn't finish, it kills the process.  If I<command> runs and exits
before the given timeout, B<timed-process> returns the exit value of
I<command>.  If I<command> did not exit before I<timeout> seconds,
then B<timed-process> will kill the process and returns an exit value
of 255, unless the -e command line option is set, which instructs
B<timed-process> to return a different exit value.  This allows the
user of B<timed-process> to determine if the process ended normally or
was killed.

=cut

use strict;
use Proc::Background 1.04 qw(timeout_system);
use Getopt::Long;

$0 =~ s:.*/::;

sub usage {
  print <<END;
usage: $0 [-e exit_status] timeout command [<arg> [<arg> ...]]

This script runs command for a specified amount of time and if it
doesn't finish, it kills the process.  If command runs and exits
before the given timeout, timed-process returns the exit value of
command.  If command did not exit before timeout seconds, then
timed-process will kill the process and returns an exit value of 255,
unless the -e command line option is set, which instructs
timed-process to return a different exit value.  This allows the user
of timed-process to determine if the process ended normally or was
killed.
END
  exit 1;
}

my $exit_status = 255;
Getopt::Long::Configure('require_order');
GetOptions('exit-status=i', => \$exit_status) or
  usage;
if ($exit_status < 0) {
  die "$0: exit status value `$exit_status' cannot be negative.\n";
}

@ARGV > 1 or usage;

my @result = timeout_system(@ARGV);

if ($result[1]) {
  exit $exit_status;
} else {
  exit $result[0] >> 8;
}

!NO!SUBS!
