#!/usr/bin/perl
#
# study_rand.pl
# svesn.pl random parameter study
# Example:
#	study_rand.pl data/btcusd_hourly >results/rand_btcusd_hourly_deep
#

$| = 1;

# data file is the one cmdline argument
($input) = @ARGV;

for ( $i=0 ; $i<10000 ; $i++ ) {

	# random esn params
	$seed = time ^ $$ ^ unpack "%32L*", `ps axww | gzip`;
	$wscale = 0.1 + rand(1.9);
	$radius = 0.1 + rand(1.9);
	$leakage = 0.01 + rand(0.99);
	$log2c = int(-20.0 + rand(30));
	$depth = int(1+rand(5));

	$cmd = "./svesn.pl --seed=$seed --depth=$depth --wscale=$wscale --radius=$radius --leakage=$leakage --log2c=$log2c --input=$input";
	chomp($hitrate = `$cmd`);
	print("OUT $hitrate $seed $depth $wscale $radius $leakage $log2c\n");
}
