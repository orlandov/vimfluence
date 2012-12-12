package File::Monitor::Object;

use strict;
use warnings;
use Carp;
use File::Spec;
use Scalar::Util qw(weaken);
use Fcntl ':mode';

use File::Monitor::Delta;

use base qw(File::Monitor::Base);

our $VERSION = '1.00';

my @STAT_FIELDS;
my @INFO_FIELDS;
my $CLASS;

BEGIN {

  @STAT_FIELDS = qw(
   dev inode mode num_links uid gid rdev size atime mtime ctime
   blk_size blocks
  );

  @INFO_FIELDS = (
    @STAT_FIELDS, qw(
     error
     )
  );

  no strict 'refs';

  # Accessors for info
  for my $info ( @INFO_FIELDS ) {
    *$info = sub {
      my $self = shift;
      croak "$info attribute is read-only" if @_;
      return $self->{_info}->{$info};
    };
  }
}

sub owner {
  my $self = shift;
  croak "name attribute is read-only" if @_;
  return $self->{owner};
}

sub name {
  my $self = shift;
  croak "name attribute is read-only" if @_;
  return $self->owner->_make_absolute( $self->{name} );
}

sub files {
  my $self = shift;
  croak "files attribute is read-only" if @_;
  my $monitor = $self->owner;
  return
   map { $monitor->_make_absolute( $_ ) }
   @{ $self->{_info}->{files} || [] };
}

sub _initialize {
  my $self = shift;
  my $args = shift;

  # Normalize the args

  $self->SUPER::_initialize( $args );
  $self->_install_callbacks( $args );

  $self->{_info}->{virgin} = 1;

  my $name = delete $args->{name}
   or croak "The name option must be supplied";

  $self->{owner} = delete $args->{owner}
   or croak "A " . __PACKAGE__ . " must have an owner";

  # Build our object
  $self->{name} = $self->owner->_canonical_name( $name );

  # Avoid circular references
  weaken $self->{owner};

  for my $opt ( qw(files recurse) ) {
    $self->{_options}->{$opt} = delete $args->{$opt};
  }

  $self->_report_extra( $args );
}

sub _read_dir {
  my $self = shift;
  my $dir  = shift;

  opendir( my $dh, $dir ) or die "Can't read $dir ($!)";
  my @files = map { File::Spec->catfile( $dir, $_ ) }
   sort
   grep { $_ !~ /^[.]{1,2}$/ } readdir( $dh );
  closedir( $dh );

  return @files;
}

sub _stat {
  my $self = shift;
  my $name = shift;

  return stat $name;
}

# Scan our target object
sub _scan_object {
  my $self = shift;
  my $name = $self->name;
  my %info;

  eval {
    @info{@STAT_FIELDS} = $self->_stat( $name );

    if ( defined $info{mode} && S_ISDIR( $info{mode} ) ) {
      my $monitor = $self->owner;

      # Do directory specific things
      if ( $self->{_options}->{files} ) {

        # Expand one level
        $info{files} = [ map { $monitor->_make_relative( $_ ) }
           $self->_read_dir( $name ) ];
      }
      elsif ( $self->{_options}->{recurse} ) {

        # Expand whole directory tree
        my @work = $self->_read_dir( $name );
        while ( my $obj = shift @work ) {
          push @{ $info{files} }, $monitor->_make_relative( $obj );
          if ( -d $obj ) {

            # Depth first to simulate recursion
            unshift @work, $self->_read_dir( $obj );
          }
        }
      }
    }
  };

  $info{error} = $@;

  return \%info;
}

sub scan {
  my $self = shift;

  my $info    = $self->_scan_object;
  my $name    = $self->name;
  my @changes = ();

  unless ( delete $self->{_info}->{virgin} ) {

    # Already done one scan, so now we compute deltas
    my $change = File::Monitor::Delta->new(
      {
        object   => $self,
        old_info => $self->{_info},
        new_info => $info
      }
    );

    if ( $change->is_change ) {
      $self->_make_callbacks( $change );
      push @changes, $change;
    }
  }

  $self->{_info} = $info;

  return @changes;
}

1;

=head1 NAME

File::Monitor::Object - Monitor a filesystem object for changes.

=head1 VERSION

This document describes File::Monitor::Object version 1.00

=head1 SYNOPSIS

Created by L<File::Monitor> to monitor a single file or directory.

    use File::Monitor;
    use File::Monitor::Object;

    my $monitor = File::Monitor->new();

    for my $file ( @files ) {
        $monitor->watch( $file );
    }

    # First scan just finds out about the monitored files. No changes
    # will be reported.
    $monitor->scan;

    # Later perform a scan and gather any changes
    for my $change ( $monitor->scan ) {
        # $change is a File::Monitor::Delta
    }

=head1 DESCRIPTION

Monitors changes to a single file or directory. Don't create a
C<File::Monitor::Object> directly; instead call C<watch> on
L<File::Monitor>.

A C<File::Monitor::Object> represents a single file or directory. The
corresponding file or directory need not exist; a file being created is
one of the events that is monitored for. Similarly if the file or directory
is deleted that will be reported as a change.

Changes of state are returned as a L<File::Monitor::Delta> object.

The state of the monitored file or directory at the time of the last
C<scan> can be queried. Before C<scan> is called these methods will all
return C<undef>. The following methods return the value of the
corresponding field from L<perlfunc/stat>:

    dev inode mode num_links uid gid rdev size
    atime mtime ctime blk_size blocks

For example:

    my $file_size = $object->size;
    my $modified  = $object->mtime;

If any error occured during the previous C<scan> it may be retrieved like this:

    my $last_error = $obj->error;

It is not an error for the file being monitored not to exist.

Finally if a directory is being monitored and the C<files> or C<recurse>
option was specified the list of files in the directory may be retrieved
like this:

    my @contained_files = $obj->files;

If C<files> was specified this will return the files and directories
immediately below the monitored directory but not the contents of any
subdirectories. If C<recurse> was specified the entire directory tree
below this directory will be returned.

In either case the returned filenames will be complete absolute paths.

=head2 Caveat for Directories

Note that C<File::Monitor::Object> has no magical way to quickly perform
a recursive scan of a directory. If you point it at a directory
containing 1,000,000 files and specify the C<recurse> option directory
scans I<will> take a long time.

=head1 INTERFACE

=over

=item C<< new( $args ) >>

Create a new C<File::Monitor::Object>. Don't call C<new> directly; use
instead L<< File::Monitor->watch >>.

=item C<< scan() >>

Perform a scan of the monitored file or directory and return a list
of changes. The returned list will contain either a single
L<File::Monitor::Delta> object describing all changes or will be empty
if no changes occurred.

    if ( my $change = $object->scan ) {
        # $change is a File::Monitor::Delta that describes all the
        # changes to the monitored file or directory.
    }

When C<scan> is first called the current state of the monitored
file/directory will be captured but no change will be reported.

=item C<< callback( [ $event, ] $coderef ) >>

Register a callback. If C<$event> is omitted the callback will be called
for all changes. Specify C<$event> to limit the callback to certain event
types. See L<File::Monitor::Delta> for a full list of events.

    $object->callback( sub {
        # called for all changes
    } );

    $object->callback( metadata => sub {
        # called for changes to file/directory metatdata
    } );

See L<File::Monitor::Delta> for a full list of events that can be
monitored.

=item C<< name >>

Returns the absolute name of the file or directory being monitored. If
C<new> was passed a relative path it is resolved relative to the current
directory at the time of object creation to make it absolute.

=item C<< files >>

If monitoring a directory and the C<recurse> or C<files> options were
specified to C<new>, C<files> returns a list of contained files. The
returned filenames will be absolute paths.

=back

=head2 Other Accessors

In addition to the above the following methods may be called to return
the value of the corresponding field from L<perlfunc/stat>:

    dev inode mode num_links uid gid rdev size
    atime mtime ctime blk_size blocks

For example:

    my $inode = $obj->inode;

Check the documentation for L<perlfunc/stat> to discover which fields
are valid on your platform.

=head1 DIAGNOSTICS

=over

=item C<< %s is read-only >>

You have attempted to modify a read-only accessor. It may be tempting
for example to attempt to change the name of the monitored file or
directory like this:

    # Won't work
    $obj->name( 'somefile.txt' );

All of the attributes exposed by C<File::Monitor::Object> are read-only.

=item C<< When options are supplied as a hash there may be no other arguments >>

When creating a new C<File::Monitor::Object> you must either supply
C<new> with a reference to a hash of options or, as a special case, pass
a filename and optionally a callback.

=item C<< The name option must be supplied >>

The options hash must contain a key called C<name> that specifies the
name of the file or directory to be monitored.

=item C<< A filename must be specified >>

You must suppy C<new> with the name of the file or directory to be
monitored.

=back

=head1 CONFIGURATION AND ENVIRONMENT

File::Monitor::Object requires no configuration files or environment variables.

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
