#!/usr/bin/perl
#
# study_grid.pl
# svesn.pl parameter study, grid search
# Example:
#	study_grid.pl data/btcusd_hourly >results/grid_btcusd_hourly
#

$| = 1;

# data file is the one cmdline argument
($input) = @ARGV;

# hardcoded seed, same for all runs
$seed = 111;

# run through reasonable values of the important params
# (PracticalESN.pdf, sec 3.3.1)
for ( $wscale=0.1; $wscale<=2.0 ; $wscale+=0.2 ) {
for ( $radius=0.1; $radius<=2.0 ; $radius+=0.2 ) {
for ( $leakage=0.01 ; $leakage<=0.99 ; $leakage+=0.02 ) {
for ( $log2c=-20.0 ; $log2c<=10.0 ; $log2c+=1.0 ) {

	$cmd = "./svesn.pl --seed=$seed --wscale=$wscale --radius=$radius --leakage=$leakage --log2c=$log2c --input=$input";
	chomp($hitrate = `$cmd`);
	print("$hitrate $wscale $radius $leakage $log2c\n");

}
}
}
