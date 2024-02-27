#!/usr/bin/perl
#
# folds.pl
# Read all lines file, emit files with specified number of folds.
# Test files are such that they can be catted together in lexical order
# to produce oos indicator.
# Example:
#	folds.pl --nfolds=5 --input=/media/ramdisk/train
# produces the files train0, ... train4 and test0, ... test4 in /media/ramdisk
#

use Getopt::Long; 
use File::Basename;

GetOptions("nfolds=i" => \$nfolds,
        "input=s" => \$input);

die "Error, must specify number of folds with --nfolds" unless $nfolds;
die "Error, must specify input file with --input" unless $input;

# read in the entire file
open(FH,"< $input") or die "Error, could not open $input: $!";
@lines = <FH>;
close(FH);

# line count
$nlines = 1+$#lines;

$base = basename($input);
$dir  = dirname($input);

$testsize = int($nlines/$nfolds);
$trainsize = $nlines-$testsize;

# indices for start of test and training areas
$test = 0;
$train = ($test + $testsize) % $nlines;

for ( $fold=0 ; $fold<$nfolds ; $fold++ ) {
	open(TEST,"> $dir".'/test'.$fold) or die "Error, could not open training output";
	for ( $i=0 ; $i<$testsize ; $i++ ) {
		print TEST $lines[$test+$i];
	}
	# do not close the last time through
	if ( $fold != $nfolds-1 ) {
		close(TEST);
	}
	open(TRAIN,"> $dir".'/train'.$fold) or die "Error, could not open training output";
	for ( $i=0 ; $i<$trainsize ; $i++ ) {
		print TRAIN $lines[($train+$i) % $nlines];
	}
	close(TRAIN);

	$test += $testsize;
	$train = ($test + $testsize) % $nlines;
}

# flush any extra lines to last training area
# (happens when $nlines not divisible by $nfolds)
while ( $test < $nlines ) {
	print TEST $lines[$test];
	$test++;
}
close(TRAIN);
