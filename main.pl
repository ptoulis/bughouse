require("terminology.pl");

my $x = generate_DBug("/home/winotgr/A/data/bughouse/export2011.bpgn", 10000);
my $y = search_db($x, 'w:p@h6    e: 1800 2100');
print "\nGames found= \n", $y->[0], " ", $y->[1], " ", $y->[2],"\n";
