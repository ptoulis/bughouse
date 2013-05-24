use Storable;

# Each game will take almost 0.5KB in space.
# Functions
#1. _load_corpus()
#2. db_min_game()
#3. db_all_games()
#4. db_game_meta()
#5. db_game_aborted()
#6. db_game_exists()
#7. db_game_result()
#11. db_save_game_opening()
#. _save_game_meta()
#12. save_dbs()


##  DB does not load games.


my $OPEN_RAW_DIR = 

## Linux Box.
#my $DB_FILENAME  = "/home/winotgr/A/data/bughouse/meta.db";
#my $OPEN_BOOK_FILENAME =  "/home/winotgr/A/data/bughouse/book.db";


##  meta_db = meta-data database
# e.g.  db = { game_id => { Date=> "2005.02.11", Time=>"22:11:00", BughouseDBGameNo => "17", 
		#	WhiteA =>"JellyRoll", WhiteAElo=>"1756", BlackA=> "oub", BlackAElo => "1619",
		# WhiteB =>"riceman", WhiteBElo=>"2145", BlackB =>"FdTurbo", BlackBElo =>"1989", Result => "*"}
my $meta_db = empty_meta_db();

# open_db = { corpus=> "<game_id, e4 e5,....." }
my $open_db = empty_open_db();
our $TIME0 = time;

# Check if game exists in database.
sub db_game_exists {
	my $gid = shift;
	return exists $meta_db->{$gid}; 
}
## Return ids of all games.
sub db_all_games {
	my @x = sort grep { /\d/  } keys %$meta_db;
	@x = grep { !db_game_aborted($_) } @x;
	return \@x;
}
## Total no. of ids.
sub db_ngames {
    return scalar @{db_all_games()};
}
## Result of the game (did the A team won)
sub db_game_result {
	my $gid = shift;
	if( ! db_game_exists($gid) ) {
		db_say("Error: game $gid not exists.");
		return -1;
	}
	if(! exists $meta_db->{$gid}{Result}) {
		db_say("Error. Game $gid does not have a result field.");
		return -2;
	}
	return ($meta_db->{$gid}{Result} eq "1-0" ? 1 : 0);
}
## Retrieve the meta-info of game.
sub db_game_meta {
	my $gid = shift;
	if( ! db_game_exists($gid) ) {
		print "No game $gid in db.";
		return {};
	}
	return $meta_db->{$gid};
}
# Was a game aborted?
sub db_game_aborted { 
	my $gid = shift;
	return $meta_db->{$gid}{Aborted};
}
## Retrieves the game opening.
sub db_game_opening {
    my ($gameid, $board) = @_;
    print "Game $gameid opening";
    ## Board A or Board B
    if(! db_game_exists($gameid)) {
        db_say("Game $gameid does not exist.");
        return(-1);
    }
    $open_db->{corpus} =~ /<$gameid,(.*?)>/;
    my $game = $1;
    #print $game,"\n\n";
    $game =~ /(.*?)W(.*?)$/g;
    
    return $1 if($board eq "A") ;
    return $2 if ($board eq "B");

}



###  SAVING   things   ####
## Converts a PGN object to an opening object.
sub min {
    my ($a, $b) = @_;
    return ($a > $b ? $b : $a);
}
## Given a PGN object, saves it to the DB
sub db_save_game_opening {
	my $pgn_obj = shift;
    my $gameid = $pgn_obj->{BughouseDBGameNo};
    ## Check if game already exists.
    if(db_game_exists( $gameid ) )
        {
            db_say("Game $gameid exists.");
            return;
        }
    db_say("Saving game $gameid");
	## Retrieve games in both boards. Take 30 first moves.
	my @gameA = @{$pgn_obj->{GameA}};
	@gameA = @gameA[0..min(scalar @gameA -1., 30)];
	my @gameB = @{$pgn_obj->{GameB}};
	@gameB = @gameB[0..min(scalar @gameB -1., 30)];
	## The format is   <GAMEID, move1 ...., move1 ......>  etc.
	$open_db->{corpus} = $open_db->{corpus}."<". $pgn_obj->{BughouseDBGameNo}.",". join(" ", @gameA)."W". join(" ", @gameB).">";
	push @{$open_db->{games}}, $pgn_obj->{BughouseDBGameNo};
    _save_game_meta($pgn_obj);
    #save_dbs();
    my $n = db_ngames();
    db_say("Game saved. Total $n [Rate = ". sprintf("%.2f", (1.0 * $n / (time-$TIME0)))." games/sec]") if(time-$TIME0>0);
    if($n==2000) {
            ##  Flush out
            _flush_out();
            $meta_db = empty_meta_db();
            $open_db = empty_open_db();
    }
	return 1;
}
## Saves the game in the meta-DB
sub _flush_out { 
    my $random = int(1000000 * rand() );
    
    print "\n\t****    FLUSHING  OUT   ******\n";
    my $metaname = $OPEN_RAW_DIR."meta-".$random.".bh";
    #print "\nMeta name is ",$metaname;
    my $opename = $OPEN_RAW_DIR."open-".$random.".bh";
    store($meta_db, $metaname);
    open FILE,">", $opename;
    print FILE $open_db->{corpus};
    close FILE;
    $TIME0 = time;
}
sub _save_game_meta {
	my $pgn_obj = shift;
	my $gid = $pgn_obj->{BughouseDBGameNo};
	delete $pgn_obj->{GameA};
	delete $pgn_obj->{GameB};
	$meta_db->{$gid}  = $pgn_obj;
}
my $last_time = time;
sub db_say {
	my $msg = shift;
    my $t1 = time;
    return if ($t1-$last_time<1);
    $last_time = $t1;
	print sprintf("[%ds-\t%-50s\t]\n", ($t1-$TIME0), $msg);
}
sub empty_meta_db {
    return {}
}
sub empty_open_db {
    return {corpus=>""}
}



