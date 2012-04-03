#!/usr/bin/perl

use strict;
use warnings;
use Carp;
use File::Monitor;

$| = 1;

my $monitor = File::Monitor->new;

push @ARGV, '.' unless @ARGV;

while ( my $obj = shift ) {
    $monitor->watch(
        {
            name    => $obj,
            recurse => 1
        }
    );
}

my @attr = qw(
  deleted mtime ctime uid gid mode
  size files_created files_deleted
);

while ( 1 ) {
    sleep 1;
    for my $change ( $monitor->scan ) {
        print $change->name, " changed\n";
        for my $attr ( @attr ) {
            my $val;
            if ( $attr =~ /^files_/ ) {
                my @val = $change->$attr;
                $val = join( ' ', @val );
            }
            else {
                $val = $change->$attr;
            }
            if ( $val ) {
                printf( "%14s = %s\n", $attr, $val );
            }

        }
    }
}
