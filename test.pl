#!/usr/bin/perl
#
# test.pl
# Test oos, run after svesn.pl has left files in /media/ramdisk.
# Should use the same params as for svesn.pl.
#	svesn.pl --wscale=1.7 --radius=0.56 --leakage=0.31 --log2c=-6.4 --input=data/btcusd_hourly
#	test.pl --wscale=1.7 --radius=0.56 --leakage=0.31 --log2c=-6.4 --input=data/btcusd_hourly_test
#

use Getopt::Long;

$| = 1;

# defaults
$depth = 1;                 # default is shallow ESN
$size = 1000;               # reservoir size
$leakage = 0.3;             # integration ema
$wscale = 1.0;              # scaling for Win weights
$radius = 1.25;             # spectral radius of W
$sparsity = 10.0/$size;     # each neuron connected to 10 others
$log2c = 0;                 # log2 of liblinear cost param

GetOptions(
    "input=s" => \$input,
    "size=i" => \$size,
    "depth=i" => \$depth,
    "wscale=f" => \$wscale,
    "seed=i" => \$seed,
    "radius=f" => \$radius,
    "leakage=f" => \$leakage,
    "sparsity=f" => \$sparsity,
    "log2c=f" => \$log2c
);

die "Error, must specify input file with --input" unless $input;
die "Error, input file does not exist" unless -e $input;

# normalized log relative returns
`./logrel.pl <$input | ./normalize_tanh.pl >/media/ramdisk/logrel`;

# run ESN, dump reservoir states
# SHOULD INITIALIZE WITH TRAINED RESERVOIR
$cmd = "./esn --seed=$seed --wscale=$wscale --radius=$radius --leakage=$leakage --sparsity=$sparsity --size=$size --input=/media/ramdisk/logrel >/media/ramdisk/state";
###$cmd = "./deepesn --depth=$depth --seed=$seed --wscale=$wscale --radius=$radius --leakage=$leakage --sparsity=$sparsity --size=$size --input=/media/ramdisk/logrel >/media/ramdisk/state";
###print STDERR "$cmd\n";
`$cmd`;

# Direction of next move, training value for linear svm classification of next move direction.
# If multivariate input, the first col instrument is used for classification.
# The tail removes the initial values corresponding to --startup
`sed '1h;1d;\$G' </media/ramdisk/logrel | awk '{if (\$1>0) print "+1"; else print "-1"}' | tail -n +101  >/media/ramdisk/class`;

# paste on classification values for liblinear
`paste -d' ' /media/ramdisk/class /media/ramdisk/state >/media/ramdisk/test`;

# train svm on training data (all of it, no folds) and save the model
$c = 2.0 ** $log2c;
`/home/egullich/svm/liblinear-2.43/train -s 2 -c $c /media/ramdisk/train /media/ramdisk/model`;

# run trained model on oos test data, indicator is left in out file
$out = `/home/egullich/svm/liblinear-2.43/predict /media/ramdisk/test /media/ramdisk/model /media/ramdisk/out`;
$out =~ m/(\d+(?:\.\d+)?)/;

$hitrate += $1;
print "$hitrate\n";
