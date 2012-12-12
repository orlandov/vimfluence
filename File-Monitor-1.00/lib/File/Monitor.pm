package File::Monitor;

use warnings;
use strict;
use Carp;

use base qw(File::Monitor::Base);

use File::Monitor::Object;

use vars qw( $VERSION );
$VERSION = '1.00';

sub _initialize {
  my $self = shift;
  my $args = shift || {};

  $self->SUPER::_initialize( $args );
  $self->_install_callbacks( $args );

  if ( my $base = delete $args->{base} ) {
    $self->base( $base );
  }

  $self->_report_extra( $args );

  $self->{_monitors} = {};
}

sub has_monitors {
  my $self = shift;
  return 1 if exists $self->{_monitors} && %{ $self->{_monitors} };
  return;
}

sub base {
  my $self     = shift;
  my $cur_base = $self->{_base};
  return $cur_base unless @_;
  my $new_base = shift or croak "Can't unset base directory";

  if ( !defined $cur_base && $self->has_monitors ) {
    croak "Can't make a non-empty absolute "
     . __PACKAGE__
     . " relative";
  }

  $self->{_base}
   = File::Spec->canonpath( File::Spec->rel2abs( $new_base ) );
}

sub _set_watcher {
  my $self   = shift;
  my $object = shift;

  my $name = $self->_make_relative( $object->name );
  return $self->{_monitors}->{$name} = $object;
}

sub watch {
  my $self = shift;

  my $args;

  if ( ref $_[0] eq 'HASH' ) {

    # Hash ref containing all arguments
    $args = shift;

    croak "When options are supplied as a hash "
     . "there may be no other arguments"
     if @_;
  }
  else {

    # File/dir name, optional callback
    my $name = shift or croak "A filename must be specified";
    my $callback = shift;

    $args = { name => $name };

    # If a callback is defined install it for all changes
    $args->{callback}->{change} = $callback
     if defined $callback;
  }

  $args->{owner} = $self;

  return $self->_set_watcher( File::Monitor::Object->new( $args ) );
}

sub unwatch {
  my $self = shift;
  my $name = shift || croak "A filename must be specified";

  $name = $self->_make_relative( $self->_canonical_name( $name ) );
  delete $self->{_monitors}->{$name};
}

sub scan {
  my $self    = shift;
  my @changed = ();

  for my $obj ( values %{ $self->{_monitors} } ) {
    push @changed, $obj->scan;
  }

  for my $change ( @changed ) {
    $self->_make_callbacks( $change );
  }

  return @changed;
}

sub _canonical_name {
  my $self = shift;
  my $name = shift;
  return $self->_make_relative(
    File::Spec->canonpath( File::Spec->rel2abs( $name ) ) );
}

# Make a filename (relative or absolute) relative to the base
# directory if any.
sub _make_relative {
  my $self = shift;
  my $name = shift;

  if ( my $base = $self->base ) {
    return File::Spec->abs2rel( $name, $base );
  }

  return $name;
}

# Make a filename relative to the base directory absolute.
sub _make_absolute {
  my $self = shift;
  my $name = shift;

  if ( my $base = $self->base ) {
    return File::Spec->rel2abs( $name, $base );
  }

  return $name;
}

1;
__END__

=head1 NAME

File::Monitor - Monitor files and directories for changes.

=head1 VERSION

This document describes File::Monitor version 1.00

=head1 SYNOPSIS

    use File::Monitor;

    my $monitor = File::Monitor->new();

    # Just watch
    $monitor->watch('somefile.txt');

    # Watch with callback
    $monitor->watch('otherfile.txt', sub {
        my ($name, $event, $change) = @_;
        # Do stuff
    });

    # Watch a directory
    $monitor->watch( {
        name        => 'somedir',
        recurse     => 1,
        callback    => {
            files_created => sub {
                my ($name, $event, $change) = @_;
                # Do stuff
            }
        }
    } );

    # First scan just finds out about the monitored files. No changes
    # will be reported.
    $object->scan;

    # Later perform a scan and gather any changes
    my @changes = $object->scan;

=head1 DESCRIPTION

This module provides a simple interface for monitoring one or more files
or directories and reporting any changes that are made to them.

It can

=over

=item * monitor existing files for changes to any of the attributes
        returned by the C<stat> function

=item * monitor files that don't yet exist and notify you if they
        are created

=item * notify when a monitored file is deleted

=item * notify when files are added or removed from a directory

=back

Some possible applications include

=over

=item * monitoring the configuration file(s) of a long running process
        so they can be automatically re-read if they change

=item * implementing a 'drop box' directory that receives files to be
        processed in some way

=item * automatically rebuilding a cached object that depends on a
        number of files if any of those files changes

=back

In order to monitor a single file create a new monitor object:

    my $monitor = File::Monitor->new();

Add the file to it:

    $monitor->watch( 'somefile.txt' );

And then call C<scan> periodically to check for changes:

    my @changes = $monitor->scan;

The first call to C<scan> will never report any changes; it captures a
snapshot of the state of all monitored files and directories so that
subsequent calls to C<scan> can report any changes.

Note that C<File::Monitor> doesn't provide asynchronous notifications
of file changes; you have to call C<scan> to learn if there have been
any changes.

To monitor multiple files call C<watch> for each of them:

    for my $file ( @files ) {
        $monitor->watch( $file );
    }

If there have been any changes C<scan> will return a list of
L<File::Monitor::Delta> objects.

    my @changes = $monitor->scan;
    for my $change (@changes) {
        warn $change->name, " has changed\n";
    }

Consult the documentation for L<File::Monitor::Delta> for more
information.

If you prefer you may register callbacks to be triggered when
changes occur.

    # Gets called for all changes
    $monitor->callback( sub {
        my ($file_name, $event, $change) = @_;
        warn "$file_name has changed\n";
    } );

    # Called when file size changes
    $monitor->callback( size => sub {
        my ($file_name, $event, $change) = @_;
        warn "$file_name has changed size\n";
    } );

See L<File::Monitor::Delta> for more information about the various event
types for which callbacks may be registered.

You may register callbacks for a specific file or directory.

    # Gets called for all changes to server.conf
    $monitor->watch( 'server.conf', sub {
        my ($file_name, $event, $change) = @_;
        warn "Config file $file_name has changed\n";
    } );

    # Gets called if the owner of server.conf changes
    $monitor->watch( {
        name        => 'server.conf',
        callback    => {
            uid => sub {
                my ($file_name, $event, $change) = @_;
                warn "$file_name has changed owner\n";
            }
        }
    } );

This last example shows the canonical way of specifying the arguments to
C<watch> as a hash reference. See C<watch> for more details.

=head2 Directories

When monitoring a directory you can choose to ignore its contents, scan
its contents one level deep or perform a recursive scan of all its
subdirectories.

See L<File::Monitor::Object> for more information and caveats.

=head1 INTERFACE

=over

=item C<< new( %args ) >>

Create a new C<File::Monitor> object. Any options should be passed as a
reference to a hash as follows:

    my $monitor = File::Monitor->new( {
        base     => $some_dir,
        callback => {
            uid => sub {
                my ($file_name, $event, $change) = @_;
                warn "$file_name has changed owner\n";
            },
            size => sub {
                my ($file_name, $event, $change) = @_;
                warn "$file_name has changed size\n";
            }
    } );

Both options (C<base> and C<callback>) are optional.

The C<base> option specifies a base directory. When a base directory has
been specified all pathnames will internally be stored relative to it.
This doesn't affect the public interface which still uses absolute paths
but it does makes it possible to relocate a File::Monitor if the
directory it's watching is moved.

The C<callback> option must be a reference to a hash that maps event
types to handler subroutines. See L<File::Monitor::Delta> for a full
list of available event types.

=item C<< watch( $name, $callback | { args } ) >>

Create a new L<File::Monitor::Object> and add it to this monitor.

The passed hash reference contains various options as follows:

    $monitor->watch( {
        name        => $file_or_directory_name,
        recurse     => $should_recurse_directory,
        files       => $should_read_files_in_directory,
        callback    => {
            $some_event => sub {
                # Handler for $some_event
            },
            $other_event => sub {
                # Handler for $other_event
            }
        }
    } );

Here are those options in more detail:

=over

=item C<name>

The name of the file or directory to be monitored. Relative paths will
be made absolute relative to the current directory at the time of the
call. This option is mandatory; C<new> will croak if it is missing.

=item C<recurse>

If this is a directory and C<recurse> is true monitor the entire
directory tree below this directory.

=item C<files>

If this is a directory and C<files> is true monitor the files and
directories immediately below this directory but don't recurse down the
directory tree.

Note that if you specify C<recurse> or C<files> only the I<names> of
contained files will be monitored. Changes to the contents of contained
files are not detected.

=item C<callback>

Provides a reference to a hash of callback handlers the keys of which
are the names of events as described in L<File::Monitor::Delta>.

=back

Callback subroutines are called with the following arguments:

=over

=item C<$name>

The name of the file or directory that has changed.

=item C<$event>

The type of change. If the callback was registered for a specific event
it will be passed here. The actual event may be one of the events below
the specified event in the event hierarchy. See L<File::Monitor::Delta>
for more details.

=item C<$delta>

The L<File::Monitor::Delta> object that describes this change.

=back

As a convenience C<watch> may be called with a simpler form of arguments:

    $monitor->watch( $name );

is equivalent to

    $monitor->watch( {
        name    => $name
    } );

And

    $monitor->watch( $name, $callback );

is eqivalent to

    $monitor->watch( {
        name        => $name
        callback    => {
            change      => $callback
        }
    } );

=item C<< unwatch( $name ) >>

Remove the watcher (if any) that corresponds with the specified file or
directory.

    my $file = 'config.cfg';
    $monitor->watch( $file );       # Now we're watching it

    $monitor->unwatch( $file );     # Now we're not

=item C<< scan() >>

Perform a scan of all monitored files and directories and return a list
of changes. Any callbacks that are registered will have been triggered
before C<scan> returns.

When C<scan> is first called the current state of the various monitored
files and directories will be captured but no changes will be reported.

The return value is a list of L<File::Monitor::Delta> objects, one for
each changed file or directory.

    my @changes = $monitor->scan;

    for my $change ( @changes ) {
        warn $change->name, " changed\n";
    }

=item C<< callback( [ $event, ] $coderef ) >>

Register a callback. If C<$event> is omitted the callback will be called
for all changes. Specify C<$event> to limit the callback to certain event
types. See L<File::Monitor::Delta> for a full list of events.

    $monitor->callback( sub {
        # called for all changes
    } );

    $monitor->callback( metadata => sub {
        # called for changes to file/directory metatdata
    } );

The callback subroutine will be called with the following arguments:

=over

=item C<$name>

The name of the file or directory that has changed.

=item C<$event>

The type of change. If the callback was registered for a specific event
it will be passed here. The actual event may be one of the events below
the specified event in the event hierarchy. See L<File::Monitor::Delta>
for more details.

=item C<$delta>

The L<File::Monitor::Delta> object that describes this change.

=back

=item C<< base >>

Get or set the base directory. This allows the entire monitor tree to be
relocated.

    # Create a monitor and watch a couple of files
    my $monitor = File::Monitor->new( { base => $some_dir } );
    $monitor->watch( "$some_dir/source.c" );
    $monitor->watch( "$some_dir/notes.text" );
    
    # Now move the directory and patch up the monitor
    rename( $some_dir, $other_dir );
    $monitor->base( $other_dir );

    # Still works
    my @changes = $monitor->scan;

If you are going to specify a base directory you must do so before any
watches are added.

=item C<< has_monitors >>

Returns true if this File::Monitor has any monitors attached to it. Used
internally to police the restriction that a base directory may not be
set when monitors have been added.

=back

=head1 DIAGNOSTICS

=over

=item C<< A filename must be specified >>

You must pass C<unwatch> the name of a file or directory to stop watching.

=back

=head1 CONFIGURATION AND ENVIRONMENT

File::Monitor requires no configuration files or environment variables.

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
