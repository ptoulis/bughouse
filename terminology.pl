# Terminology for the Bughouse project.

#  pgnObject
#     Representation of a game. There are two boards denoted by A and B.
#     HASH with keys: WhiteBElo, Time, BlackA, BlackB, WhiteA, Aborted, WhiteAElo, WhiteB, Result, TimeControl, GameB, BughouseDBGameNo, BlackBElo, GameA, Date, BlackA
#        GameA = sequence of moves in board A
#        GameB = sequence of moves in board B
#        Result = STR e.g. "1-0" meaning that the White/Black in A/B win.
#        Other keys have meta-information, e.g. WhiteBElo = the ELO of the White in the B board.
#
#  DBug
#     Database of bughouse games of one specific year.
#     HASH indexed by gameid pointing to "pgnObject"s i.e. { gameid => { pgnObject } }
#        SHOULD be gameid==BughouseDBGameNo
#
#  gameSearch_str
#     Search string for games. Has the form:
#        w: <moves> b: <moves> p: <handles> e: <eloWhite/eloBlack>
#     denoting that the games should contain the specified moves for white and black.
#     e.g. w: d4 Ne5 b: bxc6 p:Combokid e:2000/1800 indicating we want to see the game with that particular variation
#        has player Combokid and elos of opponents around 2000/1800. The latter will not be a *hard* filter
#        but it will be used in ranking the results.
#
#  FUNCTIONS
#     * pgn_to_obj(text) - Will convert the text to a pgnObject
#     * generate_DBug(filename) - Will run through all games in filename and return a DBug object.
#        Uses pgn_to_object() function.
#     * search_db(gameSearch_str) - Searches the database for the particular search string.
#        Returns an ordered list of game ids that match the search criteria.
use List::Util qw(first max maxstr min minstr reduce shuffle sum);

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

sub generate_DBug {
  my ($filename, $limit) = @_;
  open ORIG, "<", $filename or die $!;
  print "Opening raw bpgn file $filename \n";
  my $game_str = "";
  my $counter = 0;  # counts #games we have processed
  my %dbug = ();
  
  while( (my $line = <ORIG>)) {
    chomp $line;
    if($line=~/\[Event/) {
     if(length($game_str) > 0) {
      my $pgnObj = pgn_to_obj($game_str);
      # Save the pgnObj
      $dbug{$pgnObj->{BughouseDBGameNo}} = $pgnObj;
     }
     $game_str = "";
     last if(++$counter == $limit);
     print "\n\tcounter=$counter \n"  if($counter % 10000==0)
    }
    else {
      $game_str = $game_str . "  ".$line;
    }
  }
  print "Closing bpgn file.\n";
  close ORIG;
  return(\%dbug);
}

sub search_db {
   my ($dbug, $search_str) = @_;
   my @keywords = $search_str=~/(\w:)/g;
   my @items = split(/\w:\s*/, $search_str);
   # 1. Populate the search parameters.
   my @moves = ();
   my @players = ();
   my @elos = ();
   # print join("\n", @items) ,"\n\n";
   for(my $i=1; $i <= $#items; $i++) {
      my @terms = split(/\s+/, $items[$i]);
      my $keyw = $keywords[$i-1];
      if($keyw eq "w:" or $keyw eq "b:") {
         push @moves, @terms;
      }
      if($keyw eq "p:") {
         push @players, @terms;
      }
      if($keyw eq "e:") {
         push @elos, @terms;
      }
   }

   my @search_results = ();
   my @games = keys %$dbug;
   if($verbose) {
      print "\nmoves=\n", join("\n", @moves), "\nDone with moves.\n";
      print "players=\n", join("\n", @players), "\nDone with players.\n\n";
      print "elos =\n", join("\n", @elos), "\nDone with elos.\n\n";
   }
   # Quick checks
   if(@elos > 0 && @elos !=2) {
      print "ERROR: ELOs have to be 2.\n";
      exit;
   }
   
   for my $gid(keys %$dbug) {
      my $pngObj = $dbug->{$gid};
      
      if(@players > 0) {
         my $gamePlayers = $pngObj->{WhiteA}."  ".$pngObj->{WhiteB}."  ".$pngObj->{BlackA}."  ".$pngObj->{BlackB};
      
         # print($playersStr);
         my $containsPlayers = map { $gamePlayers =~ /$_/i } @players;
         # print "\n\tContains players ? =", $containsPlayers;
         next if (!$containsPlayers);
      }
      
      if(@moves > 0) {
         my $gameStr = join(" ", @{$pngObj->{GameA}}, @{$pngObj->{GameB}});
         # print "\n", $gameStr;
         my @containsMoves = map { $gameStr =~ /$_/i } @moves;
         my $N1 = sum(@containsMoves);
         my $N2 = @moves;
         next if ($N1!=$N2);
      }
      
      # 3. Push results
      push @search_results, $gid;
   }
   if(@elos > 0) {
      my %game_dist_elos = ();
      for my $gid(sort keys %$dbug) {
         my @game_dist = ();
         push @game_dist, abs($dbug->{$gid}{WhiteAElo} - $elos[0]) + abs($dbug->{$gid}{BlackAElo} - $elos[1]);
         push @game_dist, abs($dbug->{$gid}{BlackAElo} - $elos[0]) + abs($dbug->{$gid}{WhiteAElo} - $elos[1]);
         push @game_dist, abs($dbug->{$gid}{WhiteBElo} - $elos[0]) + abs($dbug->{$gid}{BlackBElo} - $elos[1]);
         push @game_dist, abs($dbug->{$gid}{BlackBElo} - $elos[0]) + abs($dbug->{$gid}{WhiteBElo} - $elos[1]);
         $game_dist_elos{$gid} = min(@game_dist);
         # print "\nFor game $gid min dist=", min(@game_dist);
      }
      @search_results = sort { $game_dist_elos{$a} <=> $game_dist_elos{$b} } @search_results;
   }
   return(\@search_results);   
}

1;






