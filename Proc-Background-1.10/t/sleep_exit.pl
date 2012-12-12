use strict;

$| = 1;

my ($sleep, $exit_status) = @ARGV;
$sleep       = 1 unless defined $sleep;
$exit_status = 0 unless defined $exit_status;

if ($ENV{VERBOSE}) {
  print STDERR "$0: sleep $sleep and exit $exit_status.\n";
}

sleep $sleep;

if ($ENV{VERBOSE}) {
  print STDERR "$0 now exiting.\n";
}

exit $exit_status;
