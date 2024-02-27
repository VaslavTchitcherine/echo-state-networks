#!/usr/bin/perl
#
# makelags.pl
#
# Filter takes a file and lags the rows.
# (The initial nlags-1 rows have bogus lags, not fully initialized,
# and should probably be trimmed by the caller.)
#
# e.g.  makelags.pl -nlags 8 < rawdata/eurusd_oanda
#

use Getopt::Long;

GetOptions("nlags=i" => \$nlags);
die "Must specify number of lags with -nlags\n" if !$nlags;

@lags = ();
chop($firstval = <>);
for ( $i=0 ; $i<$nlags-1 ; $i++ ) {
	$lags[$i] = $firstval;
}
print $firstval,' ',join(' ',@lags),"\n";

while ( <> ) {
	chop;
	print $_,' ',join(' ',@lags),"\n";
	unshift @lags,$_;
	pop @lags;
}

