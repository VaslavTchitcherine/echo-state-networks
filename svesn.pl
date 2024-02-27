#!/usr/bin/perl
#
# svesn.pl
# Support vector echo state network.
# Run esn.cpp reservoir, use liblinear for next direction supervised learning.
# Hitrate for crossvalidated test sets is written to stdout.
# Example:
#	svesn.pl --wscale=1.7 --radius=0.56 --leakage=0.31 --log2c=-6.4 --train=6000.0 --input=data/btcusd_hourly
# for DETERMINSITIC esn:
#	svesn.pl --wscale=0.7646 --radius=1.08 --leakage=0.76 --log2c=-19.47 --train=5000.0 --input=data/btcusd_hourly
#

use Getopt::Long;

$| = 1;

# how many crossvalidation folds
$nfolds = 5;

# defaults
$depth = 1;					# default is shallow ESN
$size = 1000;				# reservoir size
$leakage = 0.3;				# integration ema
$wscale = 1.0;				# scaling for Win weights
$radius = 1.25;				# spectral radius of W
$sparsity = 10.0/$size;		# each neuron connected to 10 others 
$log2c = 0;					# log2 of liblinear cost param

# random seed
$seed = time ^ $$ ^ unpack "%32L*", `ps axww | gzip`;

GetOptions(
	"input=s" => \$input,			# training file
	"test=s" => \$test,				# optional test file
	"size=i" => \$size,				# # of neurons
	"depth=i" => \$depth,			# depth if deepesn
	"wscale=f" => \$wscale,			# input weight scaling
	"seed=i" => \$seed,				# random seed
	"radius=f" => \$radius,			# spectral radius
	"leakage=f" => \$leakage,		# ema constant
	"sparsity=f" => \$sparsity,		# fraction of dense
	"log2c=f" => \$log2c,			# log of svm cost param
	"train=f" => \$train			# length of training data
);

die "Error, must specify input file with --input" unless $input;
die "Error, must specify training length with --train" unless $train;
die "Error, input file does not exist" unless -e $input;

# was float for the sake of ga.pl
$train = int($train);

# normalized log relative returns
`./logrel.pl <$input | ./normalize_tanh.pl >/media/ramdisk/logrel`;

# run ESN, dumping reservoir states for svm training
$cmd = "./esn --seed=$seed --wscale=$wscale --radius=$radius --leakage=$leakage --sparsity=$sparsity --size=$size --input=/media/ramdisk/logrel >/media/ramdisk/state";
###$cmd = "./deepesn --depth=$depth --seed=$seed --wscale=$wscale --radius=$radius --leakage=$leakage --sparsity=$sparsity --size=$size --input=/media/ramdisk/logrel >/media/ramdisk/state";
###print STDERR "$cmd\n";
`$cmd`;

# Direction of next move, classification training value.
# If multivariate input, the first col instrument is used for classification.
# The tail removes the initial values, +101 means start at line 101
# (because the first 100 were removed by default --warmup).
`sed '1h;1d;\$G' </media/ramdisk/logrel | awk '{if (\$1>0) print "+1"; else print "-1"}' | tail -n +101  >/media/ramdisk/class`;

# paste on classification values for liblinear
`paste -d' ' /media/ramdisk/class /media/ramdisk/state >/media/ramdisk/data`;

# separate into training and test regions
`head -$train /media/ramdisk/data >/media/ramdisk/train`;
`tail -n +$train /media/ramdisk/data >/media/ramdisk/test`;

# create training and test files for the crossvalidation folds
`./folds.pl --nfolds=5 --input=/media/ramdisk/train`;

# run liblinear crossvalidated on training data
$c = 2.0 ** $log2c;
$training_hitrate = 0;
for ( $i=0 ; $i<$nfolds ; $i++ ){

	# train on fold i
	`/home/egullich/svm/liblinear-2.43/train -s 2 -c $c /media/ramdisk/train$i /media/ramdisk/model`;
	###`/home/egullich/svm/cuda/LIBLINEAR.gpu-master/train -s 2 -c $c /media/ramdisk/train$i /media/ramdisk/model`;

	# run on corresponding validation set
	$out = `/home/egullich/svm/liblinear-2.43/predict /media/ramdisk/test$i /media/ramdisk/model /media/ramdisk/out$i`;
	$out =~ m/(\d+(?:\.\d+)?)/;
	die if $1 == 0.0;	# sanity
	$training_hitrate += $1;
}

# average hit rate across test folds
$training_hitrate /= $nfolds;

# run trained model on test data, indicator is left in out file
$out = `/home/egullich/svm/liblinear-2.43/predict /media/ramdisk/test /media/ramdisk/model /media/ramdisk/outtest`;
$out =~ m/(\d+(?:\.\d+)?)/;
$test_hitrate = $1;

print "$training_hitrate $test_hitrate\n";

exit;

# in case we want to assemble the training output files for ensembling
$cmd = 'cat ';
for ( $i=0 ; $i<$nfolds ; $i++ ){
    $cmd .= "/media/ramdisk/out$i ";
}
$cmd .= '> /media/ramdisk/outtrain';
`$cmd`;

