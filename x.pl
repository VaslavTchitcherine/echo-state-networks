#!/usr/bin/perl
#

$| = 1;

for ( $train=1000.0 ; $train<=6000.0 ; $train+=100.0 ) {
	$cmd = "./svesn.pl --wscale=1.7 --radius=0.56 --leakage=0.31 --log2c=-6.4 --train=$train --input=data/btcusd_hourly";
	chomp(($train_hit,$test_hit) = `$cmd`);
	print "$train $train_hit $test_hit\n";
}

