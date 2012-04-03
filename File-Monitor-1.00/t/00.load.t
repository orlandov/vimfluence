use Test::More tests => 3;

BEGIN {
  use_ok( 'File::Monitor' );
  use_ok( 'File::Monitor::Delta' );
  use_ok( 'File::Monitor::Object' );
}

diag( "Testing File::Monitor $File::Monitor::VERSION" );
