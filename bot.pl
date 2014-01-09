use FindBin;
use lib "$FindBin::RealBin/lib";

use Bawt;
use warnings;
use strict;

my $bot = Bawt->new($ARGV[0] || "config.json");
$bot->run();
