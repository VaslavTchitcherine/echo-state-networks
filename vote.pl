#!/usr/bin/perl
#
# vote.pl
# Initial experiment with voting committees of svesn 
# Perhaps read in params from output of ga run.
# Ensemble size should be odd, to avoid ties.
# Example:
#	head -3 results/ga_btcusd_hourly_wscale1 | cut -d' ' -f1 --complement | vote.pl --input=data/btcusd_hourly
#

use Getopt::Long;

GetOptions("input=s" => \$input);
die "Error, must specify input file with --input" unless $input;

# normalized log relative returns
`./logrel.pl <$input | ./normalize_tanh.pl >/media/ramdisk/logrel`;

# Direction of next move, classification training value.
# If multivariate input, the first col instrument is used for classification.
# The tail removes the initial values corresponding to --startup
`sed '1h;1d;\$G' </media/ramdisk/logrel | awk '{if (\$1>0) print "+1"; else print "-1"}' | tail -n +101  >/media/ramdisk/class`;

$nlines = 0 + `wc /media/ramdisk/class`;

while ( <> ) {
	($wscale,$radius,$leakage,$log2c) = split(' ');

	# run svesn with good params, random seed
	$cmd = "./svesn.pl --wscale=$wscale --radius=$radius --leakage=$leakage --log2c=$log2c --input=$input";
	##print "$cmd\n";
	`$cmd`;

	# hitrate for this indicator
	$hits = 0+`paste -d' ' /media/ramdisk/class /media/ramdisk/out | awk '{print \$1==\$2}' | paste -sd+ | bc`;
	print $hits/$nlines,"\n";

	# read back the indicator
	@ind = `cat /media/ramdisk/out`;

	# sum elementwise
	@sum = map { $sum[$_] + $ind[$_] } 0..$#ind;
}

# vote
open(FH,">/media/ramdisk/vote");
foreach $x (@sum) {
	if ( $x > 0 ) {
		print FH "1\n";
	}
	else {
		print FH "-1\n";
	}
}
close(FH);

# hitrate for the avg indicator
$hits = 0+`paste -d' ' /media/ramdisk/class /media/ramdisk/vote | awk '{print \$1==\$2}' | paste -sd+ | bc`;
print "Ensembled: ",$hits/$nlines,"\n";
