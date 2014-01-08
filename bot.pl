BEGIN { unshift @INC, 'lib'; }

use Bawt;
use warnings;
use strict;

my $bot = Bawt->new($ARGV[0] || "config.json");
$bot->run();
