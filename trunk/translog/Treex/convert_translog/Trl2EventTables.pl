#!/usr/bin/perl -w

use strict;
use warnings;
use open IN  => ":crlf";

use File::Copy;
use Data::Dumper; $Data::Dumper::Indent = 1;
sub d { print STDERR Data::Dumper->Dump([ @_ ]); }

binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";


# Escape characters 
my $map = { map { $_ => 1 } split( //o, "\\<> \t\n\r\f\"" ) };


my $usage =
  "Extract R tables from Translog file: \n".
  "  -T in:  Translog XML file <filename>\n".
  "  -O out: Write output   <filename>.{kd,fd,fu,pu,st}\n".
  "Options:\n".
  "  -v verbose mode [0 ... ]\n".
  "  -h this help \n".
  "\n";

use vars qw ($opt_O $opt_T $opt_v $opt_h);

use Getopt::Std;
getopts ('T:O:p:v:h');

die $usage if defined($opt_h);

my $SRC = undef;
my $KEY = undef;
my $FIX = undef;
my $FU = undef;
my $PU = undef;
my $Verbose = 0;
        
my $MaxFixGap = 400;
my $MaxKeyGap = 1000;


if (defined($opt_v)) {$Verbose = $opt_v;}


### Read and Tokenize Translog log file
if (defined($opt_T) && defined($opt_O)) {
  ReadTranslog($opt_T);
  if(!defined($FU)) { FixationUnits();}
  if(!defined($PU)) { ProductionUnits();}
  Parallel();

  PrintFU("$opt_O.fu");
  PrintPU("$opt_O.pu");
  PrintFD("$opt_O.fd");
  PrintKD("$opt_O.kd");
  PrintST("$opt_O.st");
  exit;
}

printf STDERR "No Output produced\n";
die $usage;

exit;

############################################################
# escape
############################################################

sub escape {
  my ($in) = @_;
#printf STDERR "in: $in\n";
  $in =~ s/(.)/exists($map->{$1})?sprintf('\\%04x',ord($1)):$1/egos;
  return $in;
}

sub unescape {
  my ($in) = @_;
  $in =~ s/\\([0-9a-f]{4})/sprintf('%c',hex($1))/egos;
  return $in;
}

sub MSunescape {
  my ($in) = @_;

  $in =~ s/&amp;/\&/g;
  $in =~ s/&gt;/\>/g;
  $in =~ s/&lt;/\</g;
  $in =~ s/&#xA;/\n/g;
  $in =~ s/&#xD;/\r/g;
  $in =~ s/&#x9;/\t/g;
  $in =~ s/&quot;/"/g;
  $in =~ s/&nbsp;/ /g;
  return $in;
}

## escape for R tables
sub Rescape {
  my ($in) = @_;

  $in =~ s/([ \t\n\r\f\#])/_/g;
# Hack  R does not understand unicode: all -> .
  $in =~ s/([^a-zA-Z0-9 '"_.;:|!@#$%^&*()+=\\|}{\[\]-])/./g;
#  $in =~ s/(.)/ToUniCode($1)/ego;

#  $in =~ s/([^\p{IsAlnum} '"_.;:|!@#$%^&*()+=\\|}{\[\]-])/./g;
  $in =~ s/(['"])/\\$1/g;
  return $in;
}

##########################################################
# Read Translog Logfile
##########################################################

## SourceText Positions
sub ReadTranslog {
  my ($fn) = @_;
  my ($type, $time, $cur);

  my $n = 0;

#  open(FILE, $fn) || die ("cannot open file $fn");
  open(FILE, '<:encoding(utf8)', $fn) || die ("cannot open file $fn");

  $type = 0;
  while(defined($_ = <FILE>)) {
#printf STDERR "Translog: %s\n",  $_;

    if(/<SourceToken>/)     {$type = 1; }
    elsif(/<Fixations>/)    {$type = 2; }
    elsif(/<Modifications>/){$type = 3; }
    elsif(/<ProdUnits>/)    {$type = 4; }
    elsif(/<FixUnits>/)     {$type = 5; }
	
    if($type == 1 && /<Token/) {
      if(/cur="([0-9][0-9]*)"/) {$cur =$1;}
      if(/tok="([^"]*)"/)   {$SRC->{$cur}{tok} = Rescape(MSunescape($1));}
      if(/space="([^"]*)"/) {$SRC->{$cur}{space} = Rescape(MSunescape($1));}
      if(/ id="([^"]*)"/)    {$SRC->{$cur}{id} = $1;}
    }
    elsif($type == 2 && /<Fix /) {
#printf STDERR "Translog: %s",  $_;
      if(/time="([0-9][0-9]*)"/) {$time =$1;}
      if(/win="([^"]*)"/)        {$FIX->{$time}{'win'} = $1;}
      if(/dur="([0-9][0-9]*)"/)  {$FIX->{$time}{'dur'} = $1;}
      if(/cur="([-0-9][0-9]*)"/) {$FIX->{$time}{'cur'} = $1;}
      if(/ id="([^"]*)"/)         {$FIX->{$time}{'id'} = $1;}
      if(/sid="([^"]*)"/)        {$FIX->{$time}{'sid'} = $1;}
      if($FIX->{$time}{'sid'} eq '') {$FIX->{$time}{'sid'} = -1;}

    }
    elsif($type == 3 && /<Mod /) {
      if(/time="([0-9][0-9]*)"/) {$time =$1;}
      if(/cur="([0-9][0-9]*)"/)  {$KEY->{$time}{'cur'} = $1;}
      if(/chr="([^"]*)"/)        {$KEY->{$time}{'char'} = Rescape(Rescape(MSunescape($1)));}
      if(/type="([^"]*)"/)       {$KEY->{$time}{'type'} = $1;}
      if(/ id="([^"]*)"/)        {$KEY->{$time}{'tid'} = $1;}
      if(/sid="([^"]*)"/)        {$KEY->{$time}{'sid'} = $1;}
      if($KEY->{$time}{'sid'} eq '') {$KEY->{$time}{'sid'} = -1;}
    }
#    <PU start="10685" dur="7049" pause="2719" parallel="69.1587" ins="34" del="0" src="3+4" tgt="1+3+4" str="Mordersygeplejerske&nbsp;modtager&nbsp;fire&nbsp;" />

    #ProdUnits
    elsif($type == 4 && /<PU /) {
      if(/start="([0-9][0-9]*)"/) {$time =$1;}
      if(/dur="([0-9][0-9]*)"/)   {$PU->{$time}{'dur'} = $1;}
      if(/pause="([0-9][0-9]*)"/) {$PU->{$time}{'pause'} = $1;}
      if(/parallel="([^"]*)"/)    {$PU->{$time}{'par'} = $1;}
      if(/ins="([-0-9][0-9]*)"/)  {$PU->{$time}{'ins'} = $1;}
      if(/del="([-0-9][0-9]*)"/)  {$PU->{$time}{'del'} = $1;}
      if(/src="([^"]*)"/)         {$PU->{$time}{'sid'} = $1;}
      if(/tgt="([^"]*)"/)         {$PU->{$time}{'tid'} = $1;}
      if(/str="([^"]*)"/)         {$PU->{$time}{'str'} = Rescape(Rescape(MSunescape($1)));}
      if($PU->{$time}{'sid'} eq '') {$PU->{$time}{'sid'} = -1;}
      if($PU->{$time}{'tid'} eq '') {$PU->{$time}{'tid'} = -1;}
      if($PU->{$time}{'str'} eq '') {$PU->{$time}{'str'} = '_';}
    }
# <FU start="272970" win="2" dur="3429" pause="0" parallel="100.0000" id="1+150" src="" />
  
    #FixUnits
    elsif($type == 5 && /<FU /) {
      if(/start="([0-9][0-9]*)"/) {$time =$1;}
      if(/win="([^"]*)"/)         {$FU->{$time}{'win'} = $1;}
      if(/dur="([0-9][0-9]*)"/)   {$FU->{$time}{'dur'} = $1;}
      if(/pause="([0-9][0-9]*)"/) {$FU->{$time}{'pause'} = $1;}
      if(/parallel="([^"]*)"/)   {$FU->{$time}{'par'} = $1;}
      if(/id="([-0-9][0-9]*)"/)   {$FU->{$time}{'id'} = $1;}
      else {$FU->{$time}{'id'} = -1;}
      if(/src="([^"]*)"/)         {$FU->{$time}{'sid'} = $1;}
      if($FU->{$time}{'sid'} eq '') {$FU->{$time}{'sid'} = -1;}
    }

    if(/<\/SourceToken>/)  {$type = 0; }
    if(/<\/Fixations>/)    {$type = 0; }
    if(/<\/Modifications>/){$type = 0; }
    if(/<\/ProdUnits>/)    {$type = 0; }
    if(/<\/FixUnits>/)     {$type = 0; }
  }
  close(FILE);
}

#################################################
##### FIXATION UNITS 

sub FixationUnits {

  my $start = 0;
  my $end = 0;
  my $win = 0;
  my $FUlength = 0;
  my $SID = {};
  my $ID = {};

  foreach my $t (sort  {$a <=> $b} keys %{$FIX}) {
#printf STDERR "AAAAA\n";
#d($FIX->{$t});
    if($FIX->{$t}{'win'} <= 0 ) { next;}

    if($start != 0 && ((($t - $end) > $MaxFixGap) || ($FIX->{$t}{'win'} != $win))) {
      if($FUlength > 2 ) { 
        my $sid = "";
        my $id = "";
        my $n =0;
        foreach my $s (sort  {$a <=> $b} keys %{$SID}) { if($n++>0) {$sid .= "+";} $sid .= "$s"; } 
        $n =0;
        foreach my $s (sort  {$a <=> $b} keys %{$ID}) { if($n++>0) {$id .= "+";} $id .= "$s"; } 
        $FU->{$start}{dur} =$end - $start;
        $FU->{$start}{pause} =$t - $end;
        $FU->{$start}{win} =$win;
        $FU->{$start}{id} =$id;
        $FU->{$start}{sid} =$sid;
#printf STDERR "AAAAA\n";
#d($FU->{$start});
      }
      $start = 0;
    }
    if($start == 0) {$SID = {}; $ID = {}; $start = $t;  $FUlength=0;}
    if(defined($FIX->{$t}{'id'})) {
      foreach my $i (split(/\+/, $FIX->{$t}{'id'})) {$ID->{$i}++; } 
    }
    if(defined($FIX->{$t}{'sid'})) {
      foreach my $i (split(/\+/, $FIX->{$t}{'sid'})) {$SID->{$i}++; } 
    }
    $end = $t + $FIX->{$t}{'dur'};
    $FUlength ++;
    $win = $FIX->{$t}{'win'};
  }
  my $sid = "";
  my $id = "";
  my $n =0;
  foreach my $s (sort  {$a <=> $b} keys %{$SID}) { if($n++>0) {$sid .= "+";} $sid .= "$s"; } 
  $n =0;
  foreach my $s (sort  {$a <=> $b} keys %{$ID}) { if($n++>0) {$id .= "+";} $id .= "$s"; } 
  $FU->{$start}{dur} =$end - $start;
  $FU->{$start}{pause} = 0;
  $FU->{$start}{win} =$win;
  $FU->{$start}{id} =$id;
  $FU->{$start}{sid} =$sid;
}

sub ProductionUnits {

  my $start = 0;
  my $end = 0;
  my $win = 0;
  my $type = 'ins';
  my ($str, $ins, $del, $SRC, $TGT);

  foreach my $t (sort  {$a <=> $b} keys %{$KEY}) {

    if($type ne $KEY->{$t}{type} && $KEY->{$t}{type} eq 'ins') {  $str .= ']';}

    if($start != 0 && ($t - $end) > $MaxKeyGap) {
#printf STDERR "$FUidx\t$start\t$dur\t$win\t$pause\t---\t$fix\n";
      my $src = "";
      my $tgt = "";
      my $n =0;
      foreach my $s (sort  {$a <=> $b} keys %{$SRC}) { if($n++>0) {$src .= "+";} $src .= "$s"; }
      $n =0;
      foreach my $s (sort  {$a <=> $b} keys %{$TGT}) { if($n++>0) {$tgt .= "+";} $tgt .= "$s"; }
      $PU->{$start}{str} =$str;
      $PU->{$start}{pause} =$t - $end;
      $PU->{$start}{dur} =$end - $start;
      $PU->{$start}{ins} =$ins;
      $PU->{$start}{del} =$del;
      $PU->{$start}{tid} =$tgt;
      $PU->{$start}{sid} =$src;
      $start = 0;
    }
    if($start == 0) {$start=$t; $ins=0; $del=0; $str = '';  $SRC={}; $TGT={};}

    if($KEY->{$t}{type} eq 'ins') {$ins ++;}
    if($KEY->{$t}{type} eq 'del') {$del ++;}
    if($type ne $KEY->{$t}{type} && $KEY->{$t}{type} eq 'del') {  $str .= '[';}
    $str .= $KEY->{$t}{char};

    if(defined($KEY->{$t}{'tid'})) { foreach my $i (split(/\+/, $KEY->{$t}{'tid'})) {$TGT->{$i}++; } }
    if(defined($KEY->{$t}{'sid'})) { foreach my $i (split(/\+/, $KEY->{$t}{'sid'})) {$SRC->{$i}++; } }
    $type = $KEY->{$t}{type};
    $end = $t;
  }
  if($type eq 'del') {  $str .= ']';}
  my $src = "";
  my $tgt = "";
  my $n =0;
  foreach my $s (sort  {$a <=> $b} keys %{$SRC}) { if($n++>0) {$src .= "+";} $src .= "$s"; }
  $n =0;
  foreach my $s (sort  {$a <=> $b} keys %{$TGT}) { if($n++>0) {$tgt .= "+";} $tgt .= "$s"; }
  $PU->{$start}{str} =$str;
  $PU->{$start}{pause} = 0;
  $PU->{$start}{dur} =$end - $start;
  $PU->{$start}{tid} =$tgt;
  $PU->{$start}{sid} =$src;
  $PU->{$start}{ins} =$ins;
  $PU->{$start}{del} =$del;
}

sub Parallel {
  my $m = 0;

  foreach my $fu (sort {$a<=>$b} keys %{$FU}) {
    my $common = 0;
    foreach my $pu (sort {$a<=>$b} keys %{$PU}) {
      if($pu+$PU->{$pu}{dur} < $fu) {next;}
      if($pu > $fu+$FU->{$fu}{dur}) {last;}

# printf STDERR "FU:%s--%s\tPU:%s--%s\t%s\n", $fu, $fu+$FU->{$fu}{dur}, $pu, $pu+$PU->{$pu}{dur}, $common;
      ## FU inside PU
      if($pu <= $fu && $pu+$PU->{$pu}{dur} >= $fu+$FU->{$fu}{dur}) {$common += $FU->{$fu}{dur};}
      ## PU overlap start of FU
      elsif($pu <= $fu && $pu+$PU->{$pu}{dur} < $fu+$FU->{$fu}{dur}) {$common += $pu+$PU->{$pu}{dur}-$fu;}
      ## PU overlap end of FU
      elsif($pu > $fu && $pu+$PU->{$pu}{dur} >= $fu+$FU->{$fu}{dur}) {$common += $fu+$FU->{$fu}{dur} - $pu;}
      ## PU inside FU
      elsif($pu > $fu && $pu+$PU->{$pu}{dur} < $fu+$FU->{$fu}{dur}) {$common += $PU->{$pu}{dur};}
      else { print STDERR "Parallel: Error2\n";}
    }

    if($common == 0) { $FU->{$fu}{par} = 0;}
    else {$FU->{$fu}{par} = sprintf("%4.2f", 100*$common/$FU->{$fu}{dur}); }
# printf STDERR "\tcommon: %s\n", $FU->{$fu}{par};
  }

  foreach my $pu (sort {$a<=>$b} keys %{$PU}) {
    my $common = 0;
    foreach my $fu (sort {$a<=>$b} keys %{$FU}) {
      if($fu+$FU->{$fu}{dur} < $pu) {next;}
      if($fu > $pu+$PU->{$pu}{dur}) {last;}

# printf STDERR "FU:%s--%s\tPU:%s--%s\t%s\n", $fu, $fu+$FU->{$fu}{dur}, $pu, $pu+$PU->{$pu}{dur}, $common;
      ## FU inside PU
      if($fu <= $pu && $fu+$FU->{$fu}{dur} >= $pu+$PU->{$pu}{dur}) {$common += $PU->{$pu}{dur};}
      ## PU overlap start of FU
      elsif($fu <= $pu && $fu+$FU->{$fu}{dur} < $pu+$PU->{$pu}{dur}) {$common += $fu+$FU->{$fu}{dur}-$pu;}
      ## PU overlap end of FU
      elsif($fu > $pu && $fu+$FU->{$fu}{dur} >= $pu+$PU->{$pu}{dur}) {$common += $pu+$PU->{$pu}{dur} - $fu;}
      ## PU inside FU
      elsif($fu > $pu && $fu+$FU->{$fu}{dur} < $pu+$PU->{$pu}{dur}) {$common += $FU->{$fu}{dur};}
      else { print STDERR "Parallel: Error3\n";}
    }
    if($common == 0) { $PU->{$pu}{par} = 0;}
    else {$PU->{$pu}{par} = sprintf("%4.2f", 100*$common/$PU->{$pu}{dur});}

# printf STDERR "\tcommon: %s\n", $PU->{$pu}{par};
  }
}

################################################################
## Print table with (wnr, token) 
sub PrintST {
  my ($fn) = @_;
  my ($f, $s);

#source file (.src)
  if(!defined( $SRC )) {
    printf STDERR "PrintST: undefined SOURCE\n";
    return ;
  }
  if(!open(FILE, ">:encoding(utf8)", $fn)) {
    printf STDERR "cannot open: $fn\n";
    return ;
  }

  printf FILE "id\ttoken\n";
  foreach $f (sort {$a <=> $b} keys %{$SRC}) {
    if(!defined($SRC->{$f}{'tok'})) { next;}

    printf FILE "%d\t%s\n", $SRC->{$f}{'id'}, $SRC->{$f}{'tok'};
  }
  close (FILE);
}


sub PrintKD {
  my ($fn) = @_;

  if(!defined( $KEY )) {
    printf STDERR "PrintKD: undefined Keyboard data \n";
    return ;
  }
  if(!open(FILE, ">:encoding(utf8)", $fn)) {
    printf STDERR "cannot open: $fn\n";
    return ;
  }
#    <Mod time="10685" type="ins" cur="0" chr="M" sid="1+2" id="1" />


  my $n = 0;
#  printf STDERR "n\ttime\ttype\tcur\tchr\tsrc\ttgt\n";
  printf FILE "n\ttime\ttype\tcur\tchr\ttid\tsid\n";
  foreach my $t (sort  {$a <=> $b} keys %{$KEY}) {
#    print STDERR "$n\t$t\t$KEY->{$t}{'type'}\t$KEY->{$t}{'cur'}\t$KEY->{$t}{'char'}\t$KEY->{$t}{'tid'}\t$KEY->{$t}{'sid'}\n";
    print FILE "$n\t$t\t$KEY->{$t}{'type'}\t$KEY->{$t}{'cur'}\t$KEY->{$t}{'char'}\t$KEY->{$t}{'tid'}\t$KEY->{$t}{'sid'}\n";
    $n++;
  }
  close (FILE);
}

sub PrintFD {
  my ($fn) = @_;

  if(!defined( $FIX )) {
    printf STDERR "PrintFD: undefined Keyboard data \n";
    return ;
  }
  if(!open(FILE, ">:encoding(utf8)", $fn)) {
    printf STDERR "cannot open: $fn\n";
    return ;
  }

  my $n = 0;
  printf FILE "n\ttime\twin\tdur\tchr\tid\tsid\n";
#  printf STDERR "n\ttime\twin\tdur\tcur\tid\tsid\n";

  foreach my $t (sort  {$a <=> $b} keys %{$FIX}) {
    my $SID = [split(/\+/, $FIX->{$t}{'sid'})];
#print STDERR "$n\t$t\t$FIX->{$t}{'win'}\t$FIX->{$t}{'dur'}\t$FIX->{$t}{'cur'}\t$FIX->{$t}{'id'}\t$FIX->{$t}{'sid'}\n";
#d($FIX->{$t});
    print FILE "$n\t$t\t$FIX->{$t}{'win'}\t$FIX->{$t}{'dur'}\t$FIX->{$t}{'cur'}\t$FIX->{$t}{'id'}\t$SID->[0]\n";
    $n++;
  }
  close (FILE);
}


sub PrintFU {
  my ($fn) = @_;

  if(!defined( $FU )) {
    printf STDERR "PrintFU: undefined Keyboard data \n";
    return ;
  }
  if(!open(FILE, ">:encoding(utf8)", $fn)) {
    printf STDERR "cannot open: $fn\n";
    return ;
  }

  my $n = 0;
  printf FILE "n\tstart\tdur\twin\tpause\tpar\tid\n";
#  printf STDERR "n\tstart\tdur\twin\tpause\tpar\tfixes\n";

  foreach my $t (sort  {$a <=> $b} keys %{$FU}) {
#print STDERR "$n\t$t\t$FU->{$t}{'dur'}\t$FU->{$t}{'win'}\t$FU->{$t}{'pause'}\t$FU->{$t}{'par'}\t$FU->{$t}{'id'}\n";
#d($FU->{$t});
    print FILE "$n\t$t\t$FU->{$t}{'dur'}\t$FU->{$t}{'win'}\t$FU->{$t}{'pause'}\t$FU->{$t}{'par'}\t$FU->{$t}{'id'}\n";
    $n++;
  }
  close (FILE);
}

sub PrintPU {
  my ($fn) = @_;

  if(!defined( $PU )) {
    printf STDERR "PrintPU: undefined Keyboard data \n";
    return ;
  }
  if(!open(FILE, ">:encoding(utf8)", $fn)) {
    printf STDERR "cannot open: $fn\n";
    return ;
  }

  my $n = 0;
  printf FILE "n\tstart\tdur\tpause\tpar\tins\tdel\tsid\ttid\tstr\n";
#  printf STDERR "n\tstart\tdur\tpause\tpar\tins\tdel\tsrc\ttgt\tstr\n";

  foreach my $t (sort  {$a <=> $b} keys %{$PU}) {
#print STDERR "$n\t$t\t$PU->{$t}{'dur'}\t$PU->{$t}{'pause'}\t$PU->{$t}{'par'}\t$PU->{$t}{'ins'}\t$PU->{$t}{'del'}\t$PU->{$t}{'sid'}\t$PU->{$t}{'tid'}\t$PU->{$t}{'str'}\n";
#d($PU->{$t});
    print FILE "$n\t$t\t$PU->{$t}{'dur'}\t$PU->{$t}{'pause'}\t$PU->{$t}{'par'}\t$PU->{$t}{'ins'}\t$PU->{$t}{'del'}\t$PU->{$t}{'sid'}\t$PU->{$t}{'tid'}\t$PU->{$t}{'str'}\n";
    $n++;
  }
  close (FILE);
}

