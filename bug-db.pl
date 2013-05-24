use Storable;
 use List::Util qw(min);
# Each game will take almost 0.5KB in space.
#  db_meta -- meta-database
# Functions
# -------------------------
# db_game_* = db_game_aborted, db_game_exists, db_game_group, db_game_meta, db_game_opening, db_game_result
# db_group* = db_group_games,  db_groups
# db_ngames()
# db_search_opening(..)
# db_status()
# db_say()

##  DB does not load games.

## LOADS settings.
my %SETTINGS;
open FILE, "<", "bug.settings";
my @lines = <FILE>;
for my $line(@lines) {
  chomp $line;
  my @terms = split(/=/, $line);
  $SETTINGS{$terms[0]} = $terms[1];
}
my $OPEN_RAW_DIR = $SETTINGS{openrawdir};
close FILE;

##  db_meta = meta-data database  (entire object in-memory)
# keys db = idx, rev_idx, meta
# e.g.  db = {  idx=>{ gid => file },  rev_idx=>{file => gid },
    # meta => { game_id => { Date=> "2005.02.11", Time=>"22:11:00", BughouseDBGameNo => "17", 
		#	WhiteA =>"JellyRoll", WhiteAElo=>"1756", BlackA=> "oub", BlackAElo => "1619",
		# WhiteB =>"riceman", WhiteBElo=>"2145", BlackB =>"FdTurbo", BlackBElo =>"1989", Result => "*"} }
my $db_meta = load_db_meta();

my $corpus = "";
my $_game_counter = 0;


our $TIME0 = time;

# Check if game exists in database.
sub db_game_exists {
	my $gid = shift;
	return exists $db_meta->{idx}{$gid}; 
}
## Retrieve the meta-info of game.
sub db_game_meta {
	my $gid = shift;
	if( ! db_game_exists($gid) ) {
		print "No game $gid in db.";
		return {};
	}
	return $db_meta->{meta}{$gid};
}

## Return ids of all games.
sub db_all_games {
	my @x = sort grep { /\d/  } keys %{ $db_meta->{idx}   };
	return \@x;
}
sub db_group_games {
  my $gid = shift;
  return $db_meta->{rev_idx}{$gid};
}
sub db_status {
  my @all = @{ db_all_games() }; 
	@x = grep { !db_game_aborted($_) } @all;
	my @y = grep { db_game_aborted($_) } @all;
	my $str = "\n----- DB INFO   -----\nTotal games " . (scalar @x). "(valid)"."/ " . (scalar @y). "(aborted)";
  my @groups = keys %{ $db_meta->{rev_idx}  };
	
	my @idx_keys  = keys %{$db_meta->{idx}};
	my $str3 = "Total " . scalar @idx_keys. " idx games in ". (scalar @groups). " groups.";
	return($str. "\n".$str. "\n" . $str3. "\n");
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
	if(! exists db_game_meta($gid)->{Result}) {
		db_say("Error. Game $gid does not have a result field.");
		return -2;
	}
	return (db_game_meta($gid)->{Result} eq "1-0" ? 1 : 0);
}

# Was a game aborted?
sub db_game_aborted { 
	my $gid = shift;
	return db_game_meta($gid)->{Aborted};
}
sub db_game_group {
  my $game_id = shift;
  if(not exists $db_meta->{idx}{$game_id}) {
      print "\n\tERROR: Could not retrieve group for game $game_id.";
      return -1;
  }
  return $db_meta->{idx}{$game_id};
}
## TODO(ptoulis): Implement this.
## Retrieves the game opening.
sub db_game_opening {
    my ($game_id, $board) = @_;
  
    ## Board A or Board B
    if( not db_game_exists($game_id)) {
        db_say("Game $game_id does not exist.");
        return(-1);
    }
    my $group_id = db_game_group($game_id);
    return -1 unless $group_id >0;
    my $filename = get_group_filename($group_id);
    
    if(not -f $filename) {
      print "Filename ". $filename." was not found. Aborting game lookup";
      return -1;
    }
    open FILE,"<", $filename;
    my $line = <FILE>;
    chomp $line;
    close FILE;
    
    $line =~ /<$game_id,(.*?)>/;
    print $line,"\n\n";
    
    my $game = $1;
    print $game_id,"\n\n", $game,"\n";
    $game =~ /(.*?)W(.*?)$/g;
    
    return $1 if($board eq "A") ;
    return $2 if ($board eq "B");
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
	
	## 1. Update the corpus.
	## The format is   <GAMEID, move1 ...., move1 ......>  etc.
	$corpus = $corpus."<". $pgn_obj->{BughouseDBGameNo}.",". join(" ", @gameA)."W". join(" ", @gameB).">";

  ## 2.  Save game meta-information (saves in db_meta->{meta})
   _save_game_meta($pgn_obj);

  ## 3. "Stage" the game (currently in the active set)
  push @{ $db_meta->{staged} }, $gameid;
  my $n = scalar @{$db_meta->{staged}};
  db_say("Game saved. Total $n [Rate = ". sprintf("%.2f", (1.0 * $n / (time-$TIME0)))." games/sec]") if(time-$TIME0>0);
  
  # 4. If reached the 2000-limit, the flush out the results.
  if( $n == 2000) {
    ##  Flush out
    _flush_out();
  }
  
	return 1;
}

## Saves the game in the meta-DB
sub _flush_out { 
    my $group_id = int(1000000 * rand() );
    print "\n\t****    FLUSHING  OUT   ******\n";
   
    open FILE,">", get_group_filename($group_id);
    print FILE $corpus;
    close FILE;
    my @games = @{$db_meta->{staged}};
    #print join(",", @games);
    # Update the idx, and the reverse-idx
    for my $gid (@games) {
      $db_meta->{idx}{$gid} = $group_id;
    }
    $db_meta->{rev_idx}{$group_id} = \@games;
    ##  Clear out the corpus
    $db_meta->{staged} = [];
    store($db_meta, get_meta_filename() );
    
    $corpus = "";
    
    $TIME0 = time;
}

## Saves meta information of the PGN into the meta-db
sub _save_game_meta {
	my $pgn_obj = shift;
	my $gid = $pgn_obj->{BughouseDBGameNo};
	delete $pgn_obj->{GameA};
	delete $pgn_obj->{GameB};
	
	$db_meta->{meta}{$gid}  = $pgn_obj;
}

my $last_time = time;
sub db_say {
	my $msg = shift;
    my $t1 = time;
    return if ($t1-$last_time<1);
    $last_time = $t1;
	print sprintf("[%ds-\t%-50s\t]\n", ($t1-$TIME0), $msg);
}
sub load_db_meta {
    db_say("Loading meta-db information");
    my $empty =  {idx=>{}, rev_idx=>{}, meta=>{}, staged=>[]};
    my $mf = get_meta_filename();
    return retrieve($mf) if -f $mf;
    
    store($empty, $mf);
    return load_db_meta();    
}

sub get_meta_filename {
  my $meta_filename =  $OPEN_RAW_DIR."_meta.obj";
  return $meta_filename;
}
sub get_group_filename {
  my $gid = shift;
  my $filename = $OPEN_RAW_DIR."db-".$gid.".bh";
  return $filename;
}
