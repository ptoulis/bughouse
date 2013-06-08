use strict;
use warnings;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use JSON;
$|=1;
require("bug-db.pl");
my %settings = %{ db_read_settings() };
##  OBJECTS
##  db_search = { group_id =>  <73823, e4 e6 ...>  OPENING_STR
##  response = [ {move=>"e4", hits=>20, score=>1.2, games=>[{gameid=>1212, opening=>....]}, ... }
##  search_filter = {  players=>[], elo=>[] }
our $db_search = {};

load_engine();

##   Loads the search engine.
## Fills the db_search  HASH 
sub load_engine {
  my @groups = @{db_groups()};
  my $n = scalar @groups;
  my $chars = 40;
  db_say("Loading engine...", 1);
  print "\n\t|";
  my $progress_str = "";
  my $counter = 0;
  for my $groupid (@groups) {
    $db_search->{$groupid} = db_group_opening($groupid);
    $counter++;
    my $cnt =  $chars * (1.0 * $counter) / (1.0 * $n);
    $progress_str = "=" x int($cnt);
    print "\r\t|".$progress_str;
  }
  print "\n";
  db_say(" Engine loaded.", 1);
}

# For groupid/gameid  it will return the opening in a specific format 
# Returns string of the form 1A. e4 1a. e5 ... which can be read by the "bughouse game viewer"
# (see the server implementation for details)
sub get_opening {
  my ($groupid, $gameid, $board)= @_;
  my $opening = $db_search->{$groupid};
  $opening =~ /<$gameid,(.*?)W(.*?)>/;
  my $boardA = $1;
  my $boardB = $2;
  my @movesA = split(/ /, $boardA);
  my @movesB = split(/ /, $boardB);
  my $strA = "";
  my $strB = "";
  my $cnt = 0;
  for my $move(@movesA) {
    $cnt++;
    if($cnt % 2==1) {
       my $i = ($cnt+1)/2;
      $strA .= $i."A.".$move." ";
    } else {
      $strA .= ($cnt/2)."a.".$move." ";
    }
  }
  $cnt=0;
  for my $move(@movesB) {
    $cnt++;
    if($cnt % 2==1) {
      my $i = ($cnt+1)/2;
      $strB .= $i."B.".$move." ";
    } else {
      $strB .= ($cnt/2)."b.".$move." ";
    }
  }
  return $strA if $board eq "A";
  return $strB if $board eq "B";
}

sub example_response {
 my $resp = [];
  $resp->[0] = {move=>"e4", hits=>1030, score=>0.95, games=>[{gameid=>1212, opening=>"1B. a4{118.609} 1b. a6{119.900} 2B. e5{118.312}"} ]} ;
  $resp->[1] = {move=>"Nf6", hits=>50, score=>0.5, games=>[ {gameid=>112, opening=>"1B. e4{118.092} 1A. d4{119.433} 1b. Nc6{119.900} 1a. d5{119.359} 2A. Nf3{119.333} 2a. Nf6{119.259} 2B. Nf3{116.942} 3A. Bf4{118.967}"}] };
  return $resp;
}

## Returns a SearchResponse object.
sub search_opening {

  my ($query, $filter) = @_;
  # the response ARRAY
  my $response = [];
  # next moves given the query. keys will be moves (STRING)
  my %next_moves = ();
  # max # of games to return per next_move
  my $CAP_RESULT_GAMES = 2; 
  db_say("Running query. please wait..", 1);
  # Random number from 0.. MAX-1
  my $random_position = sub {
     my $random_number = int(rand($CAP_RESULT_GAMES));
    return $random_number;
  };
  # How many games have we generated for this move?
  my $moves_size = sub {
    my $move = shift;
    return scalar @{$next_moves{$move}{games}};
  };
  ## Will add a game to the next_move only if CAP has not been reached.
  my $add_opening_maybe = sub {
    my ($move, $gameid, $groupid, $board) = @_;
    my $obj = {gameid=> $gameid, opening=>get_opening($groupid, $gameid, $board)};
    if( $moves_size->($move) >= $CAP_RESULT_GAMES ) {
      $next_moves{$move}{games}[ $random_position->() ] = $obj;
      
    } else {
      push @{$next_moves{$move}{games}}, $obj;
     }
  };
  
  chomp $query;
  ## Iterate over all groups 
  ## TODO(ptoulis): Probably not a good idea.
  my @groups  = shuffle(keys %$db_search);
  for my $groupid (@groups) {
    my $game = $db_search->{$groupid};
    my %boardsA = $game =~ /<(\d+),\s?$query\s?([^>]*?)\s/g;
    my %boardsB = $game =~ /<(\d+),[^>]*?W$query\s([^>]*?)\s/g; 
   
    for my $gameid (keys %boardsA) {
      my $move = $boardsA{$gameid};
      $next_moves{$move} = {hits=>0, score=>0.0, games=>[]} unless exists $next_moves{$move};
      $next_moves{$move}{hits}++;
      
      $add_opening_maybe->($move, $gameid, $groupid, "A");
    }
    for my $gameid (keys %boardsB) {
      my $move = $boardsB{$gameid};
      $next_moves{$move} = {hits=>0, score=>0.0, games=>[]} unless exists $next_moves{$move};
      $next_moves{$move}{hits}++;
      
      $add_opening_maybe->($move, $gameid, $groupid, "B");
    }
    
  }# for all groups.
  
  my @sorted_moves = reverse sort { $next_moves{$a}{hits} <=> $next_moves{$b}{hits} } keys %next_moves;
  for my $move (@sorted_moves) {
    push @$response, {move=>$move, hits=>$next_moves{$move}{hits}, score=>$next_moves{$move}{score}, games=>$next_moves{$move}{games} };
  }
  
  my $resp_filename = $settings{hdocs}."response.txt";
  open FILE, ">" , $resp_filename;
  print FILE to_json($response);
  close FILE;
  
  db_say("Query executed.");
  return $resp_filename;
  
}

use strict;
use warnings;
use HTTP::Daemon;
use HTTP::Status;
 
my $d = HTTP::Daemon->new(LocalPort => $settings{port}, ReuseAddr => 1) || die;
db_say("Bug Server running at <URL:". $d->url. ">", 1);

##  Several weird things
##  1.  If you don't include "else" then ur doomed
##  2.  If the .ajax call from jQuery does not have "async" to false then BOOM server is out.
##  3.  The example code in http://search.cpan.org/~gaas/HTTP-Daemon-6.01/lib/HTTP/Daemon.pm is bad
##      Had to remove the loop in get_request.
while (my $c = $d->accept) {
    db_say("Waiting for requests..");
    my $r = $c->get_request;
    $r->uri->path =~ /\/(.*?)$/;
    my $filename = $settings{hdocs}.$1;
    db_say("Path = <". $r->uri->path."> File=<$filename>",1 );
    
    ## Main server branching
    if ($r->method eq "GET" && $r->uri->path eq "/") {
      $c->send_file_response($settings{hdocs}."index.html");
    } 
    elsif($r->method eq "GET" && $r->uri->path =~ /\/q=(.*?)$/) {
      my $bugquery = $1;
      db_say("Asking for bug opening " . $bugquery, 1);
      $bugquery = join(" ", split(/%20/, $bugquery));
      db_say("Beautified " . $bugquery, 1);
      # remember, this is *not* recommended practice :-)
      my $json_response = search_opening($bugquery);
      print "\n\tFilename ", $json_response, "\n";
      $c->send_file_response($json_response);
    } 
    elsif ($r->method eq 'GET' && -f $filename) {
      $c->send_file_response($filename);
    }
    else { 
      $c->send_error(RC_FORBIDDEN)    
    }
    $c->close;
    undef($c);
}





1;
