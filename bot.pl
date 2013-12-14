BEGIN { unshift @INC, 'lib'; }

use Bawt;
use warnings;
use strict;

my $bot = Bawt->new("config.json");
$bot->run();
