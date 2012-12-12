#!perl -T

use Test::More;
eval "use Test::Pod::Coverage 1.04";
plan skip_all =>
 "Test::Pod::Coverage 1.04 required for testing POD coverage"
 if $@;
all_pod_coverage_ok(
  {
    private => [ qr{^_}, ],
    trustme => [
      qr{^(?:files_)?(?:created|deleted)$},
      qr{^is_\w+$},
      qr{^(?:new_|old_|)(?:files|atime|blk_size|blocks|ctime|dev|error|gid|inode|mode|mtime|num_links|owner|rdev|size|uid)$},
      qr{^(?:new|callback)$},
    ]
  }
);
