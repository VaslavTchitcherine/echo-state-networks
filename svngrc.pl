#!/usr/bin/perl
#
# svngrc.pl
# Support vector next generation reservoir computer.
# Run ngrc.c, use liblinear for next direction supervised learning.
# Hitrate for crossvalidation folds and test set is written to stdout.
# Example:
#	svngrc.pl --nlags=4.0 --dim=1.0 --log2c=-14 --train=6000.0 --input=data/btcusd_hourly
#

use Getopt::Long;

$| = 1;

# how many crossvalidation folds
$nfolds = 5;

# default params
$nlags = 5;		# number of lags
$dim = 2;		# 1 for linear ngrc features, 2 for quadratic			
$log2c = 0;		# log2 of liblinear cost param

GetOptions(
	"input=s" => \$input,		# training file
	"train=f" => \$train,		# length of training data
	"nlags=f" => \$nlags,
	"dim=f" => \$dim,
	"log2c=f" => \$log2c,
);

die "Error, must specify input file with --input" unless $input;
die "Error, must specify training length with --train" unless $train;
die "Error, input file does not exist" unless -e $input;

# convert to integer the params that were float for the sake of ga.pl
$train = int(0.5+$train);
$nlags = int(0.5+$nlags);
$dim = int(0.5+$dim);

# normalized log relative return lags
`./logrel.pl <$input | ./makelags.pl --nlags $nlags | ./normalize_tanh.pl >/media/ramdisk/logrel`;

# run ngrc, dumping "reservoir" states for svm training
$cmd = "./ngrc --dim=$dim </media/ramdisk/logrel >/media/ramdisk/state";
###print STDERR "$cmd\n";
`$cmd`;

# Direction of next move, classification training value.
# If multivariate input, the first col instrument is used for classification.
`sed '1h;1d;\$G' </media/ramdisk/logrel | awk '{if (\$1>0) print "+1"; else print "-1"}' >/media/ramdisk/class`;

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

