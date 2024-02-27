#!/usr/bin/perl
#
# gorand.pl
# esn parameter study, random search
#
# Example:
#	gorand.pl data/btcusd_hourly >/tmp/results
#	grep Best /tmp/results | sed "s/.*= //" | sed "s/%//" | sort -nr | head -10
#


$| = 1;

($data) = @ARGV;

# normalized log relative returns
# (note that avg and variance from the future are used for normalization)
###`./logrel.pl <$data | ./normalize_stdev.pl --outlier=3.0 >/tmp/logrel`;
# perhaps wscale takes care of scaling ???
`./logrel.pl <$data | normalize_tanh.pl >/tmp/logrel`;

# Direction of next move, classification training value.
# The tail removes the initial values corresponding to --startup
`sed '1h;1d;\$G' </tmp/logrel | awk '{if (\$1>0) print "+1"; else print "-1"}' | tail -n +101  >/tmp/class`;

for ( $i=0 ; $i<10000 ; $i++ ) {

	# random esn params
	$wscale = 0.1 + rand(1.9);
	$radius = 0.1 + rand(1.9);
	$leak = 0.01 + rand(0.99);
	$seed = int(rand(1000000));

	# run ESN, dump reservoir states
	$cmd = "./esn --seed=$seed --wscale=$wscale --radius=$radius --leakage=$leak --input=/tmp/logrel >/tmp/state";
	print "$cmd\n";
	`$cmd`;

	# paste on classification values for liblinear
	`paste -d' ' /tmp/class /tmp/state >/tmp/train`;

	# run the svm training with cross validation
	#print `/home/egullich/svm/liblinear-2.43/train -s 2 -C /tmp/train`;
	print `/home/egullich/svm/liblinear-multicore-2.43-2/train -s 2 -C /tmp/train`;
}
