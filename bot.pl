BEGIN { unshift @INC, 'lib'; }

use Bawt;
use warnings;
use strict;

my $bot = Bawt->new();
$bot->run();
