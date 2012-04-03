package File::Monitor::Delta;

use strict;
use warnings;
use Carp;

use base qw(File::Monitor::Base);

our $VERSION = '1.00';

my %TAXONOMY;

BEGIN {
  my $created = sub {
    my ( $this, $old, $new, $key ) = @_;
    return ( !defined $old->{mode} && defined $new->{mode} ) || 0;
  };

  my $deleted = sub {
    my ( $this, $old, $new, $key ) = @_;
    return $created->( $this, $new, $old, $key );
  };

  my $num_diff = sub {
    my ( $this, $old, $new, $key ) = @_;
    return ( $new->{$key} || 0 ) - ( $old->{$key} || 0 );
  };

  my $bit_diff = sub {    # XOR
    my ( $this, $old, $new, $key ) = @_;
    return ( $new->{$key} || 0 ) ^ ( $old->{$key} || 0 );
  };

  my $nop = sub {         # Just return value
    my ( $this, $old, $new, $key ) = @_;
    return $this->{delta}->{$key};
  };

  %TAXONOMY = (
    change => {
      created  => $created,
      deleted  => $deleted,
      metadata => {
        time => {
          mtime => $num_diff,
          ctime => $num_diff,
        },
        perms => {
          uid => $num_diff,
          gid => $num_diff,

          # Bit delta
          mode => $bit_diff,
        },

        # Value delta
        size => $num_diff,
      },
      directory => {

        # List delta
        files_created => $nop,
        files_deleted => $nop
      }
    }
  );

  my @OBJ_ATTR = qw(
   dev inode mode num_links uid gid rdev size mtime ctime
   blk_size blocks error files
  );

  my $IS_ARRAY = qr/^files_/;

  no strict 'refs';

  # Accessors for old/new attributes
  for my $pfx ( qw(old new) ) {
    for my $attr ( @OBJ_ATTR ) {
      my $func_name = "${pfx}_${attr}";
      *$func_name = sub {
        my $self = shift;
        croak "$func_name is read-only" if @_;
        return $self->{ $pfx . '_info' }->{$attr};
      };
    }
  }

  # Accessors for deltas are named after the leaf keys in the taxonomy
  my @work = \%TAXONOMY;
  while ( my $obj = shift @work ) {
    while ( my ( $n, $v ) = each %$obj ) {
      my $is_name = "is_$n";
      *$is_name = sub {
        my $self = shift;
        return $self->is_event( $n );
      };

      if ( ref $v eq 'CODE' ) {

        # Got a leaf item -> make an accessor
        my $func_name = $n;
        if ( $n =~ $IS_ARRAY ) {
          *$func_name = sub {
            my $self = shift;
            croak "$func_name is read-only" if @_;
            return @{ $self->{delta}->{$func_name} || [] };
          };
        }
        else {
          *$func_name = sub {
            my $self = shift;
            croak "$func_name is read-only" if @_;
            return $self->{delta}->{$func_name};
          };
        }
      }
      elsif ( ref $v eq 'HASH' ) {
        push @work, $v;
      }
      else {
        die "\%TAXONOMY contains a ", ref $v;
      }
    }
  }
}

sub _initialize {
  my $self = shift;
  my $args = shift;

  $self->SUPER::_initialize( $args );

  for my $attr ( qw(object old_info new_info) ) {
    croak "You must supply a value for $attr"
     unless exists $args->{$attr};
    $self->{$attr} = delete $args->{$attr};
  }

  $self->_report_extra( $args );

  if ( !$self->_deep_compare( $self->{old_info}, $self->{new_info} ) ) {
    $self->_compute_delta;
  }
}

sub object {
  my $self = shift;
  croak "object is read-only" if @_;
  return $self->{object};
}

sub name {
  my $self = shift;
  return $self->object->name( @_ );
}

sub _deep_compare {
  my ( $self, $this, $that ) = @_;
  use Storable qw/freeze/;
  local $Storable::canonical = 1;
  return freeze( $this ) eq freeze( $that );
}

sub _diff_list {
  my ( $this, $that ) = @_;

  my %which = map { $_ => 1 } @$this;
  $which{$_} |= 2 for @$that;

  my @diff = ( [], [] );
  while ( my ( $v, $w ) = each %which ) {
    push @{ $diff[ $w - 1 ] }, $v if $w < 3;
  }

  return @diff;
}

sub _walk_taxo {
  my $self = shift;
  my $taxo = shift;

  my $change_found = 0;

  while ( my ( $n, $v ) = each %$taxo ) {
    if ( ref $v eq 'CODE' ) {
      my $diff
       = $v->( $self, $self->{old_info}, $self->{new_info}, $n );
      if ( $diff ) {
        $self->{delta}->{$n} = $diff;
        $self->{"_is_event"}->{$n}++;
        $change_found++;
      }
    }
    else {
      if ( $self->_walk_taxo( $v ) ) {
        $self->{"_is_event"}->{$n}++;
        $change_found++;
      }
    }
  }

  return $change_found;
}

sub _compute_delta {
  my $self = shift;

  # Compute the file list deltas as a special case first
  my @df = _diff_list(
    $self->{old_info}->{files} || [],
    $self->{new_info}->{files} || []
  );

  my $monitor = $self->object->owner;
  for my $attr ( qw(files_deleted files_created) ) {
    my @ar = map { $monitor->_make_absolute( $_ ) } sort @{ shift @df };
    $self->{delta}->{$attr} = \@ar if @ar;
  }

  $self->{_is_event} = {};

  # Now do everything else
  $self->_walk_taxo( \%TAXONOMY );
}

sub is_event {
  my $self  = shift;
  my $event = shift;

  return $self->{_is_event}->{$event};
}

sub _trigger_callbacks {
  my $self      = shift;
  my $callbacks = shift || {};
  my $name      = $self->name;

  if ( $self->is_change ) {
    while ( my ( $event, $cb ) = each %$callbacks ) {
      if ( $self->is_event( $event ) ) {
        $cb->( $name, $event, $self );
      }
    }
  }
}

1;

=head1 NAME

File::Monitor::Delta - Encapsulate a change to a file or directory

=head1 VERSION

This document describes File::Monitor::Delta version 1.00

=head1 SYNOPSIS

    use File::Monitor;

    my $monitor = File::Monitor->new();

    # Watch some files
    for my $file (qw( myfile.txt yourfile.txt otherfile.txt some_directory )) {
        $monitor->watch( $file );
    }

    # First scan just finds out about the monitored files. No changes
    # will be reported.
    $object->scan;

    # After the first scan we get a list of File::Monitor::Delta objects
    # that describe any changes
    my @changes = $object->scan;

    for my $change (@changes) {
        # Call methods on File::Monitor::Delta to discover what changed
        if ($change->is_size) {
            my $name     = $change->name;
            my $old_size = $change->old_size;
            my $new_size = $change->new_size;
            print "$name has changed size from $old_size to $new_size\n";
        }
    }

=head1 DESCRIPTION

When L<File::Monitor> or L<File::Monitor::Object> detects a change to a
file or directory it packages the details of the change in a
C<File::Monitor::Delta> object.

Methods exist to discover the nature of the change (C<is_event> et al.),
retrieve the attributes of the file or directory before and after the
change (C<old_mtime>, C<old_mode>, C<new_mtime>, C<new_mode> etc),
retrieve details of the change in a convenient form (C<files_created>,
C<files_deleted>) and gain access to the L<File::Monitor::Object> for
which the change was observed (C<object>).

Unless you are writing a subclass of C<File::Monitor::Object> it
isn't normally necessary to instantiate C<File::Monitor::Delta>
objects directly.

=head2 Changes Classified

Various types of change are identified and classified into the following
hierarchy:

    change
        created
        deleted
        metadata
            time
                mtime
                ctime
            perms
                uid
                gid
                mode
            size
        directory
            files_created
            files_deleted

The terminal nodes of that tree (C<created>, C<deleted>, C<mtime>,
C<ctime>, C<uid>, C<gid>, C<mode>, C<size>, C<files_created> and
C<files_deleted>) represent actual change events. Non terminal nodes
represent broader classifications of events. For example if a file's
mtime changes the resulting C<File::Monitor::Delta> object will return
true for each of

    $delta->is_mtime;       # The actual change
    $delta->is_time;        # One of the file times changed
    $delta->is_metadata;    # The file's metadata changed
    $delta->is_change;      # This is true for any change

This event classification is used to target callbacks at specific events
or categories of events. See L<File::Monitor> and
L<File::Monitor::Object> for more information about callbacks.

=head2 Accessors

Various accessors allow the state of the object before and after the
change and the details of the change to be queried.

These accessors return information about the state of the file or
directory before the detected change:

    old_dev old_inode old_mode old_num_links old_uid old_gid
    old_rdev old_size old_mtime old_ctime old_blk_size old_blocks
    old_error old_files

For example:

    my $mode_was = $delta->old_mode;

These accessors return information about the state of the file or
directory after the detected change:

    new_dev new_inode new_mode new_num_links new_uid new_gid
    new_rdev new_size new_mtime new_ctime new_blk_size new_blocks
    new_error new_files

For example:

    my $new_size = $delta->new_size;

These accessors return a value that reflects the change in the
corresponding attribute:

    created deleted mtime ctime uid gid mode size

With the exception of C<mode>, C<created> and C<deleted> they return
the difference between the old value and the new value. This is only
really useful in the case of C<size>:

    my $grown_by = $delta->size;

Is equivalent to

    my $grown_by = $delta->new_size - $delta->old_size;

For the other values the subtraction is performed merely to ensure that
these values are non-zero.

    # Get the difference between the old and new UID. Unlikely to be
    # interesting.
    my $delta_uid = $delta->uid;

As a special case the delta value for C<mode> is computed as old_mode ^
new_mode. The old mode is XORed with the new mode so that

    my $bits_changed = $delta->mode;

gets a bitmask of the mode bits that have changed.

If the detected change was the creation or deletion of a file C<created>
or C<deleted> respectively will be true.

    if ( $delta->created ) {
        print "Yippee! We exist\n";
    }

    if ( $delta->deleted ) {
        print "Boo! We got deleted\n";
    }

For a directory which is being monitored with the C<recurse> or C<files>
options (see L<File::Monitor::Object> for details) C<files_created> and
C<files_deleted> will contain respectively the list of new files below
this directory and the list of files that have been deleted.

    my @new_files = $delta->files_created;

    for my $file ( @new_files ) {
        print "$file created\n";
    }

    my @gone_away = $delta->files_deletedl

    for my $file ( @gone_away ) {
        print "$file deleted\n";
    }

=head1 INTERFACE

=over

=item C<< new( $args ) >>

Create a new C<File::Monitor::Delta> object. You don't normally need to
do this; deltas are created as necessary by L<File::Monitor::Object>.

The single argument is a reference to a hash that must contain the
following keys:

=over

=item object

The L<File::Monitor::Object> for which this change is being reported.

=item old_info

A hash describing the state of the file or directory before the change.

=item new_info

A hash describing the state of the file or directory after the change.

=back

=item C<< is_event( $event ) >>

Returns true if this delta represents the specified event. For example,
if a file's size changes the following will all return true:

    $delta->is_event('size');        # The actual change
    $delta->is_event('metadata');    # The file's metadata changed
    $delta->is_event('change');      # This is true for any change

Valid eventnames are

    change created deleted metadata time mtime ctime perms uid gid
    mode size directory files_created files_deleted

As an alternative interface you may call C<is_>I<eventname> directly.
For example

    $delta->is_size;
    $delta->is_metadata;
    $delta->is_change;

Unless the event you wish to test for is variable this is a cleaner,
less error prone interface.

Normally your code won't see a C<File::Monitor::Delta> for which
C<is_change> returns false. Any change causes C<is_change> to be true
and the C<scan> methods of C<File::Monitor> and C<File::Monitor::Object>
don't return deltas for unchanged files.

=item C<< name >>

The name of the file for which the change is being reported. Read only.

=item C<< object >>

The L<File::Monitor::Object> for which this change is being reported.

=back

=head2 Other methods

As mentioned above a large number of other accessors are provided to get
the state of the object before and after the change and query details of
the change:

    old_dev old_inode old_mode old_num_links old_uid old_gid old_rdev
    old_size old_mtime old_ctime old_blk_size old_blocks old_error
    old_files new_dev new_inode new_mode new_num_links new_uid new_gid
    new_rdev new_size new_mtime new_ctime new_blk_size new_blocks
    new_error new_files created deleted mtime ctime uid gid mode size
    files_created files_deleted name

See L</Accessors> for details of these.

=head1 DIAGNOSTICS

=over

=item C<< %s is read-only >>

C<File::Monitor::Delta> is an immutable description of a change in a
file's state. None of its accessors allow values to be changed.

=item C<< You must supply a value for %s >>

The three options that C<new> (C<old_info>, C<new_info> and C<object>)
are all mandatory.

=back

=head1 CONFIGURATION AND ENVIRONMENT

File::Monitor::Delta requires no configuration files or environment variables.

=head1 DEPENDENCIES

None.

=head1 INCOMPATIBILITIES

None reported.

=head1 BUGS AND LIMITATIONS

No bugs have been reported.

Please report any bugs or feature requests to
C<bug-file-monitor@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.

=head1 AUTHOR

Andy Armstrong  C<< <andy@hexten.net> >>

Faycal Chraibi originally registered the File::Monitor namespace and
then kindly handed it to me.

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2007, Andy Armstrong C<< <andy@hexten.net> >>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.

=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.
