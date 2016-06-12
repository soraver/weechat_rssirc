#!/usr/bin/perl
#
# This is an rss to irc script.
# It uses outside curl binary so it can fork itself using weechat functions
# Its dirty and poorly coded but it works.
#
# Config file example:
# BUFFER|NAME|URL
#
# tech|slashdot|http://rss.slashdot.org/Slashdot/slashdot
# news|somename|http://url.tothefeed.com/rss/
#
# soraver@dotteam.gr
# 20150703
#

my $script_name = "rssirc";
my $agent = "rss to irc bot v0.3";
my $listoflinks = ".weechat/rssirc.conf";

use open qw/:std :utf8/;
use DBI;
#use strict;
use Encode;
use LWP::Simple;

use URI::Escape;

my $driver   = "SQLite"; 
my $database = ".weechat/rssirc.db";
my $dsn = "DBI:$driver:dbname=$database";
my $userid = "";
my $password = "";

my %color=();
my %feeds = ();


# CONNECT TO THE DATABASE

# delete the old db file
unlink $database;

# connect to the db
my $dbh = DBI->connect($dsn, $userid, $password) 
                      or die $DBI::errstr;
# create the table
my $stmt = qq(CREATE TABLE URL
      (URL	TEXT	NOT NULL,
       TITLE	TEXT	NOT NULL,
       TIME	INT	NOT NULL););
my $rv = $dbh->do($stmt);
print $DBI::errstr if($rv < 0);


# SUBROUTINES
# check if thw object exists in the db
sub ri_checkexist {
  my $url = $_[0];
  my $sth = $dbh->prepare("SELECT count(*) from URL WHERE URL=?");
  my $rv = $sth->execute($url) or die $DBI::errstr;
  print $DBI::errstr if $rv < 0;
  my $o=0;
  $o=1 if ($sth->fetchrow_array);
  $sth->finish;
  return $o;
}


# add values
sub ri_addvalues {
  my $url = $_[0];
  my $title = $_[1];
  my $sth = $dbh->prepare("INSERT INTO URL (URL,TITLE,TIME) VALUES (?,?,?)");
  my $rv = $sth->execute($url,$title,time) or die $DBI::errstr;
  return;
}


# download the xml/parse and print to the channel
sub ri_xmlget {
  my @colors = ("cyan","magenta","green","brown","lightblue","default",
    "lightcyan","lightmagenta","lightgreen","blue","31","35","38","40","49",
    "63","70","80","92","99","112","126","130","138","142","148","160","162",
    "167","169","174","176","178","184","186","210","212","215","247",
    "cyan","magenta","green","brown","lightblue","default",
    "lightcyan","lightmagenta","lightgreen","blue","31","35","38","40","49",
    "63","70","80","92","99","112","126","130","138","142","148","160","162",
    "167","169","174","176","178","184","186","210","212","215","247");
  my $i=0;
  open FILE, $listoflinks or die $!;

  while(<FILE>) {
    chomp;
    next unless /\|/;
    my($buffer_name,$name,$url) = split ('\|', $_);
    $color{"$name"} = $colors[$i];
    $i++;
    # Hook the process
    my $hook = weechat::hook_process(
      '/usr/bin/curl -s -k '.$url,
#'/home/janitor/curllog.sh '.$url,

      10000,
      "ri_process_callback",
      $buffer_name."|".$name
    );
  }
  close FILE;
  return weechat::WEECHAT_RC_OK;
}

sub ri_process_callback {
  my ($output, $command, $returncode, $out, $err) = @_; 
  if ($out) {
    $out =~ s/\r\n/\n/g;
    $out =~ s/\n/ /g;
    $out =~ s/<\!\[CDATA\[(.*?)\]\]>/$1/g;

    while ($out =~ m!<item.*?<title>(.*?)</title>.*?<link>(.*?)</link>.*?</item>!gs) { 
      my $title = $1;#$title =~ s/^\s+|\s+$//g;
      my $link = $2;
      unless(ri_checkexist($link)){
        ri_addvalues($link,$title);
        ri_output_channel($output,$link,$title);
      }#unless exists
    }#while regex
    while ($out =~ m!<item.*?<link>(.*?)</link>.*?<title>(.*?)</title>.*?</item>!gs) {
      my $title = $2;#$title =~ s/^\s+|\s+$//g;
      my $link = $1;
      unless(ri_checkexist($link)){
        ri_addvalues($link,$title);
        ri_output_channel($output,$link,$title);
      }#unless exists
    }#while regex

    while ($out =~ m!<entry.*?<link.*?href="(.*?)".*?>.*?<title>(.*?)</title>.*?</entry>!gs) {
      my $title = $2;#$title =~ s/^\s+|\s+$//g;
      my $link = $1;
      unless(ri_checkexist($link)){
        ri_addvalues($link,$title);
        ri_output_channel($output,$link,$title);
      }#unless exists
    }#while regex

  }#if out
  return weechat::WEECHAT_RC_OK;
}
 
sub debg{
  my ($out) = @_;
  my $buffer = weechat::buffer_search('perl', $buffer_name);
  weechat::print($buffer,$out);
}

sub ri_output_channel {
  my ($bufnam,$link,$title) = @_;
  my($buffer_name,$name) = split ('\|', $bufnam);
  my $buffer = weechat::buffer_search('perl', $buffer_name);
  $name = decode_utf8($name);
  $name = weechat::color($color{"$name"}).$name;
  $link = decode_utf8($link);
#  $link = uri_unescape($link);
  $title = decode_utf8($title);
#  my $tiny = tinyurl($link);
  weechat::print($buffer,$name."\t".weechat::color('white')."$title\n\t$link\n");
}

sub timer_cb {
  my ($data, $remaining_calls) = @_;
  ri_xmlget;
  return weechat::WEECHAT_RC_OK;
}

sub tinyurl {
  my $url = $_[0];
  my $urllength = length($url);
  my $maxlength = maxlength();
  my $shorten = $url;
  $shorten = get('http://tinyurl.com/api-create.php?url='.$url) if $maxlength < $urllength;
  return $shorten;
}

sub maxlength {
  my $current_window_width = weechat::window_get_integer(weechat::current_window(), "win_chat_width");
  $current_window_width = $current_window_width - 26;
  return $current_window_width;
}

sub ri_buildbuffers {
  open FILE, $listoflinks or die $!;
  #debg('mphke');
  my $i = 2; #buffers position
  my %a;
  while(<FILE>) {
    chomp;
    next unless /\|/;
    my($buffer_name,$name,$url) = split ('\|', $_);
    next if exists($a{$buffer_name});
    next if weechat::buffer_search('perl', $buffer_name);

    my $buffer = weechat::buffer_new($buffer_name, "", "", "", "");
    $a{$buffer_name} = 1;
    $buffer_name = ucfirst($buffer_name)." ";
    weechat::buffer_set($buffer, "localvar_set_no_log", "1");
    weechat::buffer_set($buffer, "title", $buffer_name);
    weechat::buffer_set($buffer, 'number', $i++);
  }
  return weechat::WEECHAT_RC_OK;
}


weechat::register($script_name, "soraver", "0.3", "GPL3", "RSS to IRC", "", "");
ri_buildbuffers;
weechat::hook_timer(300000, 0, 0, "ri_buildbuffers", "");
weechat::hook_timer(300000, 0, 0, "timer_cb", "");
timer_cb;

weechat::print("", "RSS to IRC script loaded!");
