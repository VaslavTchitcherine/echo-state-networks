#!/usr/bin/perl
#
# study_rand_classify.pl
# esnregress.cpp random parameter study
# FIX HARDCODED TRAINLEN
# Example:
#	study_rand_classify.pl data/btcusd_hourly >results/rand_classify_btcusd_hourly
#

$| = 1;

# data file is the one cmdline argument
($input) = @ARGV;

# normalized log returns
`./logrel.pl <$input | normalize_tanh.pl >/media/ramdisk/logrel`;

for ( $i=0 ; $i<1000 ; $i++ ) {

	# random esn params
	$seed = time ^ $$ ^ unpack "%32L*", `ps axww | gzip`;
	$wscale = 0.1 + rand(1.9);
	$radius = 0.1 + rand(1.9);
	$leakage = 0.01 + rand(0.99);
	###$reg = int(-1000.0 + rand(1010));
	$reg = int(-10.0 + rand(10));

	$cmd = "./esnclassify --seed=$seed --wscale=$wscale --radius=$radius --leakage=$leakage --reg=$reg --trainlen=6000 --testlen=535 --input=/media/ramdisk/logrel";
	chomp($hitrate = `$cmd`);
	###print("$cmd\n");
	print("$hitrate $seed $wscale $radius $leakage $reg\n");
}
