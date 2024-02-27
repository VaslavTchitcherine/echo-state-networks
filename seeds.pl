#!/usr/bin/perl
#
#
# seeds.pl
# When a run has done well with certain parameters,
# repeat the run with the same params, different seeds.
# Example:
#	seeds.pl data/btcusd_hourly >results/btcusd_hourly_seeds
#


$| = 1;

($data) = @ARGV;

# normalized log relative returns
# (note that avg and variance from the future are used for normalization)
`./logrel.pl <$data | ./normalize_stdev.pl --outlier=3.0 >/tmp/logrel`;
# perhaps wscale takes care of scaling ???
###`./logrel.pl <$data >/tmp/logrel`;

# Direction of next move, classification training value.
# The tail removes the initial values corresponding to --startup
`sed '1h;1d;\$G' </tmp/logrel | awk '{if (\$1>0) print "+1"; else print "-1"}' | tail -n +101  >/tmp/class`;

# for randwalk2
###$wscale = 0.707312808072684;
###$radius = 2.39414185261944;
###$leak = 0.0791278697265745;

# for btcusd_hourly
$wscale = 0.208811070044039;
$radius = 1.76640605340035;
$leak = 0.112697065428667;

for ( $i=0 ; $i<100 ; $i++ ) {

	# random esn params
	$seed = int(rand(1000000));

	# run ESN, dump reservoir states
	$cmd = "./esn --seed=$seed --wscale=$wscale --radius=$radius --leakage=$leak --input=/tmp/logrel >/tmp/state";
	print "$cmd\n";
	`$cmd`;

	# paste on classification values for liblinear
	`paste -d' ' /tmp/class /tmp/state >/tmp/train`;

	# run the svm training with cross validation
	print `/home/egullich/svm/liblinear-multicore-2.43-2/train -s 2 -C /tmp/train`;
}
