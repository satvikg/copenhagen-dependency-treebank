#!/usr/bin/perl

use strict;
use warnings;

use File::Slurp qw( :edit );

my $datadir = '../../data/';
my $regexp_mask = $ARGV[0] || '.';

foreach my $filename (grep {/$regexp_mask/} glob "$datadir/tag-format/*/*tag") {
    edit_file {
        s/ (\w+)=([^"'\s\>]+)/ $1="$2"/g;
    }
        $filename;
}