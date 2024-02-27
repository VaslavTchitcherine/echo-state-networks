#!/usr/bin/perl
#
# logrel.pl
# relativize prices:  turn table of prices into log relative prices,
# Each col can be a separate instrument.
# An optional --lag parameter specifies how many timesteps we look back.
# Example:
# 	logrel.pl <data/btcusd_hourly | normalize_tanh.pl >/tmp/logrel
#

# read first line (can have one or many cols)
@in1 = split(' ',<>);

# prehistoric values are not known, just print log(1)
for ( $i=0 ; $i<1+$#in1 ; $i++ ) {
	print "0.0 ";
}
print "\n";

while ( @in = split(' ',<>) ) {
	for ( $i=0 ; $i<1+$#in1 ; $i++ ) {
		print log($in[$i] / $in1[$i]),' ';
	}
	print "\n";
	@in1 = @in;
}

