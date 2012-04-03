#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 464;
use File::Path;
use File::Spec;
use Cwd;
use File::Monitor;
use File::Monitor::Object;
use Data::Dumper;
use Storable;
use Fcntl ':mode';

sub empty_dir {
  my $dir = shift;

  rmtree( $dir );
}

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

my @events = qw(
 change created deleted metadata time mtime ctime perms uid gid
 mode size directory files_created files_deleted
);

my %test_map = (
  true => sub {
    my ( $name, $change, $opts ) = @_;

    for my $field ( @$opts ) {
      my $value = $change->$field();
      ok $value, "$name: $field is true"
       or warn Dumper( $change );
    }
  },

  false => sub {
    my ( $name, $change, $opts ) = @_;

    for my $field ( @$opts ) {
      my $value = $change->$field();
      ok !$value, "$name: $field is false"
       or warn Dumper( $change );
    }
  },

  positive => sub {
    my ( $name, $change, $opts ) = @_;

    for my $field ( @$opts ) {
      my $value = $change->$field();
      cmp_ok $value, '>', 0, "$name: $field is > 0"
       or warn Dumper( $change );
    }
  },

  deeply => sub {
    my ( $name, $change, $opts ) = @_;

    while ( my ( $field, $value ) = each %$opts ) {
      my @got = $change->$field();
      is_deeply \@got, $value, "$name: $field matches"
       or warn Dumper( $change );
    }
  },

  is_event => sub {
    my ( $name, $change, $opts ) = @_;

    for my $event ( @$opts ) {
      ok $change->is_event( $event ), "$name: is_event('$event') OK"
       or warn Dumper( $change );
    }
  },

  is_not_event => sub {
    my ( $name, $change, $opts ) = @_;

    for my $event ( @$opts ) {
      ok !$change->is_event( $event ), "$name: !is_event('$event') OK"
       or warn Dumper( $change );
    }
  },
);

SKIP: {
  my $tmp_dir = File::Spec->tmpdir;

  skip "Can't find temporary directory", 464
   unless defined $tmp_dir;

  my $test_dir = File::Spec->catdir( $tmp_dir, "fmtest-$$" );

  for my $set_base ( 0 .. 1 ) {

    my $fix_name = sub {
      my $name = shift;
      return File::Spec->catfile( $test_dir, split( /\//, $name ) );
    };

    my $fix_dir = sub {
      my $name = shift;
      return File::Spec->catdir( $test_dir, split( /\//, $name ) );
    };

    # Forward slashes in names are converted to platform
    # local path separator
    my @files = map { $fix_name->( $_ ) } qw(
     test0 test1 test2 test3 test4
     a/long/dir/name/test5
     a/long/time/ago/test6
    );

    my @schedule = (
      {
        name   => 'Create one file',
        action => sub {
          touch_file( $files[0] );
        },
        expect => {
          $files[0] => {
            true   => ['created'],
            false  => ['deleted'],
            deeply => {
              files_created => [],
              files_deleted => []
            },
            is_event     => [ 'change', 'created' ],
            is_not_event => [
              'deleted',       'directory',
              'files_created', 'files_deleted'
            ],
          }
        },
        callbacks => {
          $files[0] => [
            'ctime',   'change',   'mode', 'time',
            'created', 'metadata', 'perms'
          ]
        },
      },
      {
        name   => 'Create two files',
        action => sub {
          touch_file( $files[1] );
          touch_file( $files[2] );
        },
        expect => {
          $files[1] => {
            true         => ['created'],
            false        => ['deleted'],
            is_event     => [ 'change', 'created' ],
            is_not_event => [
              'deleted',       'directory',
              'files_created', 'files_deleted'
            ],
          },
          $files[2] => {
            true   => ['created'],
            false  => ['deleted'],
            deeply => {
              files_created => [],
              files_deleted => []
            },
            is_event     => [ 'change', 'created' ],
            is_not_event => [
              'deleted',       'directory',
              'files_created', 'files_deleted'
            ],
          }
        },
        callbacks => {
          $files[1] => [
            'ctime',   'change',   'mode', 'time',
            'created', 'metadata', 'perms'
          ],
          $files[2] => [
            'ctime',   'change',   'mode', 'time',
            'created', 'metadata', 'perms'
          ],
        }
      },
      {
        name   => 'Create another file',
        action => sub {
          touch_file( $files[3] );
        },
        expect => {
          $files[3] => {
            true   => ['created'],
            false  => ['deleted'],
            deeply => {
              files_created => [],
              files_deleted => []
            },
            is_event     => [ 'change', 'created' ],
            is_not_event => [
              'deleted',       'directory',
              'files_created', 'files_deleted'
            ],
          }
        },
        callbacks => {
          $files[3] => [
            'ctime', 'change',, 'mode',
            'time', 'created', 'metadata', 'perms'
          ],
        },
      },
      {
        name   => 'Extend file',
        action => sub {
          with_open(
            $files[1],
            '>>',
            sub {
              my $fh = shift;
              print $fh 'something';
            }
          );
        },
        expect => {
          $files[1] => {
            false    => [ 'created', 'deleted' ],
            positive => ['size'],
            deeply   => {
              files_created => [],
              files_deleted => []
            },
            is_event     => [ 'change', 'metadata', 'size' ],
            is_not_event => [
              'created',   'deleted',
              'directory', 'files_created',
              'files_deleted'
            ],
          }
        },
        callbacks => { $files[1] => [ 'change', 'metadata', 'size' ], },
      },
      {
        name   => 'Create file in monitored directories',
        action => sub {
          touch_file( $files[6] );
        },
        expect => {
          $files[6] => {
            true         => ['created'],
            false        => ['deleted'],
            is_event     => [ 'change', 'created' ],
            is_not_event => [
              'deleted',       'directory',
              'files_created', 'files_deleted'
            ],
          },
          $fix_dir->( 'a' ) => {
            deeply => {
              files_created => [
                $fix_dir->( 'a/long' ),
                $fix_dir->( 'a/long/time' ),
                $fix_dir->( 'a/long/time/ago' ),
                $fix_dir->( 'a/long/time/ago/test6' )
              ],
              files_deleted => []
            },
            true  => ['created'],
            false => ['deleted'],
            is_event =>
             [ 'change', 'directory', 'files_created', 'created' ],
            is_not_event => [ 'deleted', 'files_deleted' ],
          },
          $fix_dir->( 'a/long/time/ago' ) => {
            deeply => {
              files_created => [ $files[6] ],
              files_deleted => []
            },
            true  => ['created'],
            false => ['deleted'],
            is_event =>
             [ 'change', 'directory', 'files_created', 'created' ],
            is_not_event => [ 'deleted', 'files_deleted' ],
          }
        },
        callbacks => {
          $files[6] => [
            'ctime', 'change',, 'mode',
            'time', 'created', 'metadata', 'perms'
          ],
        }
      },
      {
        name   => 'More files in monitored directories',
        action => sub {
          touch_file( $files[5] );
        },
        expect => {
          $files[5] => {
            true         => ['created'],
            false        => ['deleted'],
            is_event     => [ 'change', 'created' ],
            is_not_event => [
              'deleted',       'directory',
              'files_created', 'files_deleted'
            ],
          },
          $fix_dir->( 'a' ) => {
            deeply => {
              files_created => [
                $fix_dir->( 'a/long/dir' ),
                $fix_dir->( 'a/long/dir/name' ),
                $fix_dir->( 'a/long/dir/name/test5' )
              ],
              files_deleted => []
            },
            false        => [ 'deleted', 'created' ],
            is_event     => [ 'change',  'directory', 'files_created' ],
            is_not_event => [ 'deleted', 'created', 'files_deleted' ],
          },
          $fix_dir->( 'a/long/dir/name' ) => {
            deeply => {
              files_created => [ $files[5] ],
              files_deleted => []
            },
            true  => ['created'],
            false => ['deleted'],
            is_event =>
             [ 'change', 'directory', 'files_created', 'created' ],
            is_not_event => [ 'deleted', 'files_deleted' ],
          }
        },
        callbacks => {
          $files[5] => [
            'ctime', 'change',, 'mode',
            'time', 'created', 'metadata', 'perms'
          ],
        }
      },
      {
        name   => 'Delete file',
        action => sub {
          unlink( $files[5] )
           or die "Can't delete ", $files[5], " ($!)\n";
        },
        expect => {
          $files[5] => {
            false        => ['created'],
            true         => ['deleted'],
            is_event     => [ 'change', 'deleted' ],
            is_not_event => [
              'created',       'directory',
              'files_created', 'files_deleted'
            ],
          },
          $fix_dir->( 'a' ) => {
            deeply => {
              files_deleted =>
               [ $fix_dir->( 'a/long/dir/name/test5' ) ],
              files_created => []
            },
            false        => [ 'deleted', 'created' ],
            is_event     => [ 'change',  'directory', 'files_deleted' ],
            is_not_event => [ 'deleted', 'created', 'files_created' ],
          },
          $fix_dir->( 'a/long/dir/name' ) => {
            deeply => {
              files_deleted => [ $files[5] ],
              files_created => []
            },
            false        => [ 'deleted', 'created' ],
            is_event     => [ 'change',  'directory', 'files_deleted' ],
            is_not_event => [ 'deleted', 'created', 'files_created' ],
          }
        },
        callbacks => {
          $files[5] => [
            'ctime',   'change',   'mode', 'time',
            'deleted', 'metadata', 'perms'
          ],
        }
      },
      {
        name   => 'Delete directory',
        action => sub {
          rmtree( $fix_dir->( 'a/long/dir' ) );
        },
        expect => {
          $fix_dir->( 'a' ) => {
            deeply => {
              files_deleted => [
                $fix_dir->( 'a/long/dir' ),
                $fix_dir->( 'a/long/dir/name' ),
              ],
              files_created => []
            },
            false => [ 'deleted', 'created' ],
          },
          $fix_dir->( 'a/long/dir/name' ) => {
            false        => ['created'],
            true         => ['deleted'],
            is_event     => [ 'change', 'deleted' ],
            is_not_event => [
              'directory',     'created',
              'files_created', 'files_deleted'
            ],
          }
        }
      },
    );

    my $args = {};

    if ( $set_base ) {
      $args->{base} = $test_dir;
    }

    my $monitor = File::Monitor->new( $args );

    my $cb_recorder = {};

    # Add files. None of them exist yet
    for my $file ( @files ) {

      my $args = { name => $file };

      for my $ev ( @events ) {
        $args->{callback}->{$ev} = sub {
          my ( $name, $event, $change ) = @_;
          $cb_recorder->{$name}->{$event}++;
         }
      }

      $monitor->watch( $args );
    }

    # Add some directories
    $monitor->watch(
      {
        name    => $fix_dir->( 'a' ),
        recurse => 1
      }
    );

    $monitor->watch(
      {
        name  => $fix_dir->( 'a/long/dir/name' ),
        files => 1
      }
    );

    $monitor->watch(
      {
        name    => $fix_dir->( 'a/long/time/ago' ),
        recurse => 1,
        files   => 1
      }
    );

    my @changed = $monitor->scan;
    is_deeply \@changed, [], 'first scan, no changes';

    for my $item ( @schedule ) {
      my $test_name = $item->{name};
      $item->{action}->();

      $cb_recorder = {};
      my @ch = $monitor->scan;

      if ( my $cb_spec = $item->{callbacks} ) {
        while ( my ( $file, $cbs ) = each %$cb_spec ) {
          for my $cb ( @$cbs ) {
            cmp_ok $cb_recorder->{$file}->{$cb}, '==', 1,
             "$test_name: callback for $file, $cb OK"
             or warn Dumper( $cb_recorder );
          }
        }
      }

      CH:
      for my $change ( @ch ) {
        my $name    = $change->name;
        my $caption = "$test_name($name)";
        my $expect  = delete $item->{expect}->{$name};

        ok $expect, "$caption: change expected for $name"
         or warn Dumper( $change );

        while ( my ( $test, $opts ) = each %$expect ) {
          my $func = $test_map{$test}
           || die "Test $test undefined";
          $func->( $caption, $change, $opts );
        }
      }

      # Check we used up all the items
      is_deeply $item->{expect}, {},
       "$test_name: all expected changes matched";

      # Make sure another scan returns no changes
      @ch = $monitor->scan;
      is_deeply \@ch, [], "$test_name: no change";

    }

    #diag( Dumper( $monitor ) );

    rmtree $test_dir;
  }
}
