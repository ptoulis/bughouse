use strict;
use warnings;

require("bug-db.pl");
require("process-bpgn.pl");

save_pgn_games("/home/ptoulis/A/data/bughouse/export2010.bpgn", 20000 * 1000);

print db_status(), "\n";
my $gameid = db_all_games()->[0];


