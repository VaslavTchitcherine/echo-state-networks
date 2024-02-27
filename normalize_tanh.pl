#!/usr/bin/perl
#
# normalize_tanh.pl
# Normalize into [-1,1] using online mean and stdev
# (Welford's algorithm) and squash outliers with tanh.
# If there are many cols, each is normalized independently.
# PERHAPS SHOULD USE SLIDING RATHER THAN GROWING WINDOW?
# Example:
#	logrel.pl <data/btcusd_hourly | ./normalize_tanh.pl >/tmp/logrel
#

use Statistics::Welford;
use Math::Complex;

@line = split(' ',<>);

# for each field
$n = 0;
foreach $x (@line) {
	# create a welford object
	push(@welford, Statistics::Welford->new);
	# and add first data point to this object
	$welford[$n++]->add($x);
	# print 0 for first output
	print "0.0 ";
}
print "\n";

while ( @line = split(' ',<>) ) {

	$n = 0;
	foreach $x (@line) {
		$welford[$n]->add($x);

		# current running mean and stdev
		$mean = $welford[$n]->mean;
		$stdev = $welford[$n]->standard_deviation;

		# sanity check
		if ( $welford[$n]->standard_deviation == 0.0 ) {
			print '0.0 ';
		}
		else {
			print tanh(($x - $welford[$n]->mean)/$welford[$n]->standard_deviation), ' ';
		}

		$n++;
	}
	print "\n";
}
