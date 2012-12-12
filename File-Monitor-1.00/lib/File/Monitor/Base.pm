package File::Monitor::Base;
use strict;
use warnings;
use Carp;
use File::Spec;

our $VERSION = '1.00';

sub new {
  my $class = shift;
  my $self = bless {}, $class;
  $self->_initialize( @_ );
  return $self;
}

sub _report_extra {
  my $self  = shift;
  my $args  = shift;
  my @extra = keys %$args;
  croak "The following options are not recognised: ",
   join( ' ', sort @extra )
   if @extra;
}

sub _initialize {
  my $self = shift;
}

sub _install_callbacks {
  my $self = shift;
  my $args = shift;

  # Install callbacks
  if ( my $callback = delete $args->{callback} ) {
    if ( ref $callback eq 'CODE' ) {
      $self->callback( 'change', $callback );
    }
    elsif ( ref $callback eq 'HASH' ) {
      while ( my ( $event, $cb ) = each %$callback ) {
        $self->callback( $event, $cb );
      }
    }
    else {
      croak "A callback must be a code reference "
       . "or a hash of code references";
    }
  }
}

sub _make_callbacks {
  my $self   = shift;
  my $change = shift;
  $change->_trigger_callbacks( $self->{_callbacks} );
}

sub callback {
  my $self  = shift;
  my $event = shift;
  my $code  = shift;

  # Allow event to be omitted
  if ( ref $event eq 'CODE' && !defined $code ) {
    ( $code, $event ) = ( $event, 'changed' );
  }

  croak "Callback must be a code references"
   unless ref $code eq 'CODE';

  $self->{_callbacks}->{$event} = $code;
}

1;

=head1 NAME

File::Monitor::Base - Common base class for file monitoring.

=head1 VERSION

This document describes File::Monitor::Base version 1.00

=head1 DESCRIPTION

Don't use this class directly. See L<File::Monitor> and
L<File::Monitor::Object> for the public interface.

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
