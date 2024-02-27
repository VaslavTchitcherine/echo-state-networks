#!/usr/bin/perl
#
# study_trainsize.pl
# Using good params (from ga) vary training length
# Example:
#	study_trainsize.pl >/tmp/tr
#	 p "/tmp/tr" u 1:2,"" u 1:3
#

$| = 1;

for ( $train=1000.0 ; $train<=6000.0 ; $train+=100.0 ) {
	#$cmd = "./svesn.pl --wscale=1.7 --radius=0.56 --leakage=0.31 --log2c=-6.4 --train=$train --input=data/btcusd_hourly";
	$cmd = "./svesn.pl --wscale=1.05 --radius=1.51 --leakage=0.704 --log2c=-13 --train=$train --input=data/ethusd_hourly";
	chomp(($train_hit,$test_hit) = `$cmd`);
	print "$train $train_hit $test_hit\n";
}

