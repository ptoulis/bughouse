use strict;
use warnings;
$|=1;

use strict;
use warnings;
$|=1;


## Contains functions that process the BPGN format.

##  Given the input database file, it will parse the PGNs and then store them locally
##  using the bug-db   module.
sub save_pgn_games {
    my ($filename, $limit) = @_;
    open ORIG, "<", $filename or die $!;
    print "Opening raw bpgn file $filename \n";
    ## "s" will be the string of the bug game. 
    my $s = "";
    my $counter = 0;
    
    while( (my $line = <ORIG>)) {
        chomp $line;
        
        if($line=~/\[Event/) {
             db_save_game_opening(pgn_to_obj($s)) if(length($s)>0);
             $s = "";
             last if(++$counter == $limit);
             print "\n\t--> $counter \n"  if($counter % 10000==0)
        }
        else {
            $s = $s . "  ".$line;
        }
    }
    print "Closing bpgn file.\n";
    close ORIG;
}

sub extract_pgn_objects {
    my $filename = shift;
    open FILE, "<", $filename;
    my $s = "";
    my @games = ();
    print "\tLoading PGNs...";
    
    while( (my $line = <FILE>)) {
        chomp $line;
        if($line=~/\[Event/) {
             push @games, pgn_to_obj($s) if(length($s)>0);
             $s = "";
        }
        else {
            $s = $s . "  ".$line;
        }
        my $n  = scalar @games;
         if ( $n>0 && $n % 10000 ==0) {
            print $n.", " ;
                  
        }
    }
    
    close FILE;
    return \@games;
}

##  Given some text of the game, will convert to hash object:
## Keys WhiteBElo, Time, BlackA, BlackB, WhiteA, Aborted, WhiteAElo, WhiteB, Result, TimeControl, GameB, BughouseDBGameNo, BlackBElo, GameA, Date, BlackAE
sub pgn_to_obj {
	my $text = shift;
    my %hash = $text =~ /\[(.*?) \"(.*?)\"\]/gs;
    if($text =~ /aborted/is) {
		$hash{Aborted} = 1;
	} else {
		$hash{Aborted} =  0;
	}
	
	$text =~ s/\{.*?\}//gs;
	$text =~ s/\[.*?\]//gs;
    $text =~ s/\+//gs;
	my @B = $text =~ /\d+?[Bb]\.\s(.*?)\s/gs;
	my @A = $text =~ /\d+?[Aa]\.\s(.*?)\s/gs;
	$hash{GameA} = \@A;	## the two games are denoted as A, B
	$hash{GameB} = \@B;
	# these 3 are not important..
	delete $hash{Event};
	delete $hash{Site};
	delete $hash{Lag};
	return \%hash;
}

sub print_hash {
    my $x = shift;
    print(join(", ", keys %$x) )
}

1;

1;
