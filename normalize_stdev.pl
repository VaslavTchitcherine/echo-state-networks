#!/usr/bin/perl
#
# normalize_stdev.pl
# Normalize a series into [-1,1] using z-score
#

use Getopt::Long;

# default threshold for removal of wild outliers
$outlier = 3.0;

GetOptions("train=s" => \$train,
		"outlier=f" => \$outlier);

# read in the entire series
@ind = <STDIN>;

# if training range was specified
if ( $train =~ m/([0-9]*)\/([0-9]*)/ ) {
	($trainstart,$trainstop) = ($1,$2);
}
else {
	$trainstart = 0;
	$trainstop = 1+$#ind;
}

# compute avg and variance
$sum = 0.0;
for ( $i=$trainstart ; $i<$trainstop ; $i++ ) {
	$sum += $ind[$i];
}
$avg = $sum / ($trainstop-$trainstart);
$variance = 0.0;
for ( $i=$trainstart ; $i<$trainstop ; $i++ ) {
	$variance += ($ind[$i]-$avg)*($ind[$i]-$avg);
}
$variance /= ($trainstop-$trainstart-1);
$stdev = sqrt($variance);

print STDERR "For normalization avg: $avg  stdev $stdev\n";

$outliercount = 0;
# subtract mean and scale difference series by stdev
for ( $i=0 ; $i<=$#ind ; $i++ ) {
	$ind[$i] = ($ind[$i]-$avg) / $stdev;

	# outlier removal
	#if ( abs($ind[$i]) > $outlier and $i>=$trainstart and $i<$trainstop ) {
	if ( abs($ind[$i]) > $outlier ) {
		# clamp all outliers to $outlier or -$outlier
		if ( $ind[$i] > $outlier ) {
			$ind[$i] = $outlier;
		}
		if ( $ind[$i] < -$outlier ) {
			$ind[$i] = -$outlier;
		}
		$outliercount++;
	}
}

# dump scaled series to stdout
# should we divide by $outlier to ensure all points lie in [-1,1] ?
for ( $i=0 ; $i<=$#ind ; $i++ ) {
	print $ind[$i]/$outlier,"\n";
	###print $ind[$i],"\n";
}

print STDERR "Number of outliers: $outliercount\n";
