#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use File::Monitor;
use File::Monitor::Object;
use File::Monitor::Delta;

plan tests => 384;

my @tests = (
  {
    name     => 'No files',
    old_info => {
      mode      => 0x000081a4,
      atime     => 1170281355,
      ctime     => 1170281355,
      mtime     => 1170281355,
      blk_size  => 4096,
      blocks    => 0,
      dev       => 234881026,
      gid       => 0,
      uid       => 501,
      inode     => 2828759,
      num_links => 1,
      rdev      => 0,
      size      => 0,
      error     => '',
    },
    new_info => {
      mode      => 0x000040c9,
      atime     => 1170281385,
      ctime     => 1170281365,
      mtime     => 1170281315,
      blk_size  => 4096,
      blocks    => 0,
      dev       => 234881026,
      gid       => 501,
      uid       => 0,
      inode     => 2828759,
      num_links => 1,
      rdev      => 0,
      size      => 123,
      error     => '',
    },
    expect => {
      mode          => 0x000081a4 ^ 0x000040c9,
      ctime         => 10,
      mtime         => -40,
      gid           => 501,
      uid           => -501,
      size          => 123,
      files_created => [],
      files_deleted => [],
    }
  },
  {
    name     => 'All files deleted',
    old_info => {
      mode      => 0x000040c9,
      atime     => 1170281385,
      ctime     => 1170281365,
      mtime     => 1170281315,
      blk_size  => 4096,
      blocks    => 0,
      dev       => 234881026,
      gid       => 501,
      uid       => 0,
      inode     => 2828759,
      num_links => 1,
      rdev      => 0,
      size      => 123,
      error     => '',
      files     => [ 'a', 'b', 'c' ],
    },
    new_info => {
      mode      => 0x000081a4,
      atime     => 1170281355,
      ctime     => 1170281355,
      mtime     => 1170281355,
      blk_size  => 4096,
      blocks    => 0,
      dev       => 234881026,
      gid       => 0,
      uid       => 501,
      inode     => 2828759,
      num_links => 1,
      rdev      => 0,
      size      => 0,
      error     => '',

      # files missing
    },
    expect => {
      mode          => 0x000081a4 ^ 0x000040c9,
      ctime         => -10,
      mtime         => 40,
      gid           => -501,
      uid           => 501,
      size          => -123,
      files_created => [],
      files_deleted => [ 'a', 'b', 'c' ],
    }
  },
  {
    name     => 'Deleted and created',
    old_info => {
      mode      => 0x000040c9,
      atime     => 1170281385,
      ctime     => 1170281365,
      mtime     => 1170281315,
      blk_size  => 4096,
      blocks    => 0,
      dev       => 234881026,
      gid       => 501,
      uid       => 0,
      inode     => 2828759,
      num_links => 1,
      rdev      => 0,
      size      => 123,
      error     => '',
      files     => [ 'b', 'a', 'd', 'c', 'e' ],
    },
    new_info => {
      mode      => 0x000081a4,
      atime     => 1170281355,
      ctime     => 1170281355,
      mtime     => 1170281355,
      blk_size  => 4096,
      blocks    => 0,
      dev       => 234881026,
      gid       => 0,
      uid       => 501,
      inode     => 2828759,
      num_links => 1,
      rdev      => 0,
      size      => 0,
      error     => '',
      files     => [ 'g', 'f', 'z', 'a', 'd', 'e' ],
    },
    expect => {
      files_created => [ 'f', 'g', 'z' ],
      files_deleted => [ 'b', 'c' ],
    }
  }
);

my @read_only_attr = qw(
 old_dev old_inode old_mode old_num_links old_uid old_gid old_rdev
 old_size old_mtime old_ctime old_blk_size old_blocks old_error
 old_files new_dev new_inode new_mode new_num_links new_uid new_gid
 new_rdev new_size new_mtime new_ctime new_blk_size new_blocks
 new_error new_files created deleted mtime ctime uid gid mode size
 files_created files_deleted name
);

for my $test ( @tests ) {
  my $test_name = $test->{name};

  ok my $monitor = File::Monitor->new;
  ok my $object
   = File::Monitor::Object->new( { name => '.', owner => $monitor } );
  isa_ok $object, 'File::Monitor::Object';

  ok my $change = File::Monitor::Delta->new(
    {
      object   => $object,
      old_info => $test->{old_info},
      new_info => $test->{new_info}
    }
  );

  isa_ok $change, 'File::Monitor::Delta';

  for my $ro ( @read_only_attr ) {
    can_ok $change, $ro;
    eval { $change->$ro() };
    ok !$@, "read $ro OK";
    eval { $change->$ro( 'ouch' ) };
    like $@, qr/read\W+only/, "can't write $ro";
  }

  while ( my ( $attr, $value ) = each %{ $test->{expect} } ) {
    if ( $attr =~ /^files_/ ) {
      my @got = $change->$attr();
      is_deeply \@got, $value, "$test_name: $attr OK";
    }
    else {
      my $got = $change->$attr();
      is_deeply $got, $value, "$test_name: $attr OK";
    }
  }
}
