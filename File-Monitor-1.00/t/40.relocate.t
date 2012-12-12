#!/usr/bin/perl

use strict;
use warnings;
use File::Spec;
use File::Path;
use File::Monitor;
use Data::Dumper;
use Test::More tests => 11;

sub with_open {
  my ( $name, $mode, $cb ) = @_;
  if ( $mode =~ />/ ) {

    # Writing so make sure the directory exists
    my ( $vol, $dir, $leaf ) = File::Spec->splitpath( $name );
    my $new_dir = File::Spec->catpath( $vol, $dir, '' );
    mkpath( $new_dir );
  }

  open( my $fh, $mode, $name )
   or die "Can't open \"$name\" for $mode ($!)\n";
  $cb->( $fh );
  close( $fh );
}

sub touch_file {
  my $name = shift;
  with_open( $name, '>>', sub { } );
}

sub sort_arrays {
  my $obj = shift;

  if ( ref $obj eq 'ARRAY' ) {
    return sort @$obj;
  }
  elsif ( ref $obj eq 'HASH' ) {
    while ( my ( $n, $v ) = each %$obj ) {
      $obj->{$n} = sort_arrays( $v );
    }
  }
  else {
    $obj ||= '(undef)';
    die "Can't sort $obj\n";
  }
}

SKIP: {
  my $tmp_dir = File::Spec->tmpdir;

  skip "Can't find temporary directory", 11
   unless defined $tmp_dir;

  my $test_base = File::Spec->catdir( $tmp_dir, "fmtest-$$" );

  my $next_suff = 1;

  my $next_dir = sub {
    return File::Spec->catdir( $test_base,
      sprintf( "dir%03d", $next_suff++ ) );
  };

  my $test_dir = $next_dir->();

  my $fix_name = sub {
    my $name = shift;
    return File::Spec->catfile( $test_dir, split( /\//, $name ) );
  };

  my $fix_dir = sub {
    my $name = shift;
    return File::Spec->catdir( $test_dir, split( /\//, $name ) );
  };

  my %change = ();

  my %action = (
    add_dir => sub {
      my $dirs = shift;
      for my $dir ( @$dirs ) {
        my $name = $fix_dir->( $dir );
        mkpath( $name );
      }
    },
    add_file => sub {
      my $files = shift;
      for my $file ( @$files ) {
        my $name = $fix_name->( $file );
        touch_file( $name );
      }
    },
    rm_dir => sub {
      my $dirs = shift;
      for my $dir ( @$dirs ) {
        my $name = $fix_dir->( $dir );
        rmtree( $name );
      }
    },
    rm_file => sub {
      my $files = shift;
      for my $file ( @$files ) {
        my $name = $fix_name->( $file );
        unlink $name or die "Can't delete $name ($!)\n";
      }
    },
  );

  my @schedule = (
    {
      name    => 'Create directories',
      add_dir => [qw( a b/c d/e/f )],
    },
    {
      name     => 'Create files',
      add_file => [qw( a/f1 b/c/f2 d/e/f/f3 )],
    },
    {
      name    => 'Create more directories',
      add_dir => [qw( g/h i )],
    },
    {
      name    => 'Delete files',
      rm_file => [qw( b/c/f2 d/e/f/f3)],
    },
    {
      name   => 'Delete directories',
      rm_dir => [qw( g/h i /b/c d/e/f)],
    },
  );

  my $monitor = File::Monitor->new( { base => $test_dir } );
  $monitor->watch( { name => $test_dir, recurse => 1 } );

  my @changed = $monitor->scan;
  is_deeply \@changed, [], 'first scan, no changes';

  for my $test ( @schedule ) {
    %change = ();
    my $name = delete $test->{name};
    while ( my ( $act, $arg ) = each %$test ) {
      my $code = $action{$act} || die "No action $act defined";
      $code->( $arg );
      push @{ $change{$act} }, @$arg;
    }

    # Relocate the test directory
    my $new_dir = $next_dir->();
    rename( $test_dir, $new_dir )
     or die "Can't rename $test_dir to $new_dir ($!)\n";
    $monitor->base( $new_dir );
    $test_dir = $new_dir;

    is $monitor->base, $test_dir, "$name: monitor relocated";

    my %expect = ();

    # Get the expected changes
    for
     my $mode ( [ 'add', 'files_created' ], [ 'rm', 'files_deleted' ] )
    {
      my ( $act, $key ) = @$mode;
      for my $type ( [ 'dir', $fix_dir ], [ 'file', $fix_name ] ) {
        my ( $typ, $fix ) = @$type;
        push @{ $expect{$key} },
         map { $fix->( $_ ) } @{ $change{"${act}_${typ}"} || [] };
      }
    }

    # Get the changes
    my %got     = ();
    my @changes = $monitor->scan();
    for my $change ( @changes ) {
      for my $meth ( qw ( files_created files_deleted ) ) {
        push @{ $got{$meth} }, $change->$meth;
      }
    }

    my $r_got    = sort_arrays( \%got );
    my $r_expect = sort_arrays( \%expect );
    unless ( is_deeply $r_got, $r_expect, "$name: changes match" ) {
      diag( Data::Dumper->Dump( [$r_got],    ['$got'] ) );
      diag( Data::Dumper->Dump( [$r_expect], ['$expect'] ) );
    }
  }

  rmtree( $test_base );

}
