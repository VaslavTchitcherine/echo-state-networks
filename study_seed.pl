#!/usr/bin/perl
#
# study_seed.pl
# svesn.pl random seed study.
# Example:
#	study_seed.pl
#

$| = 1;

# data file is the one cmdline argument
($input) = @ARGV;

for ( $i=0 ; $i<100 ; $i++ ) {

	# random esn params
	$seed = time ^ $$ ^ unpack "%32L*", `ps axww | gzip`;

	# best params from ga
	$cmd = "./svesn.pl --seed=$seed --wscale=1.7 --radius=0.56 --leakage=0.31 --log2c=-6.4 --input=data/btcusd_hourly";
	chomp($hitrate = `$cmd`);
	print "$hitrate\n";
}
