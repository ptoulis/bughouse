use strict;
use warnings;

require("bug-db.pl");
require("process-bpgn.pl");

print db_status(), "\n";
my $gameid = db_all_games()->[0];


