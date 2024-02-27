#!/usr/bin/perl
#
# ga.pl
# Genetic algorithm for optimization of svesn.pl parameters.
# Params to be optimized are specified as variables preceeded by '%', with an optional range.
# Example:
#	nohup ga.pl "svesn.pl --wscale=%wscale=[0.1,2.0] --radius=%radius=[0.1,2.0] --leakage=%leakage=[0.01,0.99] --log2c=%log2c=[-20.0,10.0] --train=%train=[1000,6000] --input=data/btcusd_hourly" >results/ga_btcusd_hourly &
#	nohup ga.pl "svngrc.pl --nlags=%nlags=[2,10] --dim=%dim=[1.0,2.0] --log2c=%log2c=[-20.0,10.0] --train=6000.0 --input=data/btcusd_hourly" >results/ga_btcusd_hourly &
#

use FileHandle;
use Tie::IxHash;

# GA parameters
$popsize = 100;				# size of GA population
$maxgens = 5;				# number of generations of GA evolution 
$crossover_prop = 1.0;		# probability of crossover [0.9,1.0]
$mutate_prob = 0.05;		# probability of mutation [0.0,0.05]

$verbose = 0;

$| = 1;

($runcmd) = join(' ',@ARGV);

# so hashes are enumerated in insertion order
tie %param, "Tie::IxHash";

# parse the % params to be genetically optimized
&parseparams;
$nparams = keys %param;

# random seed for rand() random number generator
srand(time ^ $$ ^ unpack "%32L*", `ps axww | gzip`);
#srand(100);

# initialize genetic population
# (an array of anonymous arrays of params, with fitness prepended to
# each param vector, for ease of sorting)
@pop = &initialize_pop;

# evaluate fitness for each individual in initial population
for ( $i=0 ;  $i<=$#pop ; $i++ ) {
	# fitness is special first element in param vector, it gets set
	$pop[$i]->[0] = &eval_fitness(@{$pop[$i]});
}
	
# evolve for the requested number of generations
for ( $gen=0 ; $gen<$maxgens ; $gen++ ) {

	# sort population based on fitness (descending order)
	@pop = sort { $b->[0] <=> $a->[0] } @pop;

	# calculate average population fitness
	$sumfitness = 0.0;
	for ( $i=0 ; $i<=$#pop ; $i++ ) {
		$sumfitness += $pop[$i]->[0];
	}

	# print some stats about GA progress
	###print "gen $gen best: $pop[0]->[0], avg: ",$sumfitness/(1+$#pop),"\n";

	# EARLY TERMINATION ON POPULATION CONVERGENCE???

	# population for next generation initially empty
	@newpop = ();

	# elitism: always copy over best member of old population
	push(@newpop, $pop[0]);

	# add children to new population
	while ( $#newpop < $popsize-1 ) {
		# select 2 individuals to breed (references are returned)
		($parent1,$parent2) = select_parents(@pop);

		# breed (crossover), returning references to children
		($child1,$child2) = breed($parent1,$parent2);

		# sometimes mutate
		if ( rand(1) < $mutate_prob ) {
			# randomly choose one child to mutate
			if ( rand(1) < 0.5 ) {
				&mutate($child1);
			}
			else {
				&mutate($child2);
			}
		}

		# evaluate fitness of children (fitness is stored in the 0th element)
		$child1->[0] = &eval_fitness(@$child1);
		$child2->[0] = &eval_fitness(@$child2);

		# add copies of children to population
		push(@newpop, [@$child1]);
		push(@newpop, [@$child2]);
	}

	# sort new population based on fitness (descending order)
	@newpop = sort { $b->[0] <=> $a->[0] } @newpop;

	# elitism has added an extra member to the pop, remove the
	# least fit member (from the end)
	$#newpop = $#pop;

	# and copy new generation over old
	@pop = @newpop;
}

# dump the entire population, sorted by fitness
foreach $p (@pop) {
	print join(' ',@{$p}),"\n";
}

exit;

#########################################################################

# Parse the params to be genetically optimized:
# arrays are set, and the global $runcmd string is modified
# to be a format string for the substitution of parameters
sub parseparams {
	# loop to find and replace each % parameter
	while ( $runcmd =~ m/\%[a-z0-9]+/ ) {
    	# first try to match with parameter range specification
    	if (  $runcmd =~ m/\%([a-z0-9]+)=\[(-?[0-9]+\.?[0-9]*),(-?[0-9]+\.?[0-9]*)\]/ ) {
        	###print "matched var: $1, lo: $2 , hi: $3\n";
        	$runcmd =~ s/\%([a-z0-9]+)=\[(-?[0-9]+\.?[0-9]*),(-?[0-9]+\.?[0-9]*)\]/#f/;
        	###print "DEBUG1: $runcmd\n";
			$param{$1} = [$2,$3];
		}
		# when no parameter range is specified (which is probably a bad idea),
		# a huge range [-1.0e10,1.0e10] is then the default
    	else {
        	$runcmd =~ s/\%([a-z0-9]+)/#f/;
        	###print "matched var: $1\n";
			$param{$1} = [-1.0e10,1.0e10];
        	###print "DEBUG2: $runcmd\n";
    	}
	}   

	# replace all the '#' with '%' (which would have interfered with parsing)
	$runcmd =~ s/\#/\%/g;
###print "$runcmd\n";
}


# Initialize the genetic population of parameter vectors,
# returned as a list of references to lists.
# Each list element contains the fitness, followed by the param vector.
sub initialize_pop {

	# delete the hash storing param vectors we have evaluated
	undef(%seen);

	my(@pop) = ();

	# randomize hyperparameter values, if the hyperparam name appears on
	# the @params list of parameters we wish to optimize in this run
	for ( my $i=0 ; $i<$popsize ; $i++ ) {
		# The first element, fitness, is initially 0.0
		# as it has not yet been evaluated.
		my @individual = (0.0);

		foreach $p (keys %param) {
			
#print $p,' ',$param{$p}->[0],' ',$param{$p}->[1],"\n";
			# random parameter value in specified range
			$v = $param{$p}->[0] + rand($param{$p}->[1]-$param{$p}->[0]);
			push(@individual,$v);
		}
#print join(' ',@individual); exit;
		# Add reference to this new random param vector to population array 
		push(@pop,\@individual);
	}

	return @pop;
}

			
# call run.pl to evaluate training fitness for the supplied param
# values, which are passed in as an array, @params
sub eval_fitness {
	my(@params) = @_;

	# remove the fitness value, which is a special first value in params
	shift(@params);

	# plug these params into the format string
	$cmd = sprintf($runcmd,@params);

	if ( $verbose ) {
		print "$cmd\n"
	}

	# execute svesn.pl with these params
	chomp(($train,$test) = `$cmd`);
###print STDERR "$cmd\n";
###print STDERR "$train $test\n";

	return $train;
}

# select 2 individuals to breed
# uses fitness-proportionate selection
sub select_parents {
	my(@pop) = @_;

	# use an exponential deviate to favor selection of fitter parents
	# (or could use tournament instead, see gp.c)
    do {
        $parentidx1 = int($#pop * -0.5 * log(rand(1.0)));
    }
    while ( $parentidx1 > $#pop );
    do {
        $parentidx2 = int($#pop * -0.5 * log(rand(1.0)));
    }
    while ( $parentidx2 > $#pop or $parentidx1 == $parentidx2 );

	$parent1 = $pop[$parentidx1];
	$parent2 = $pop[$parentidx2];

	return $parent1,$parent2;
}

# Breed 2 parents, to produce 2 children. (1 point crossover)
# Parents are passed in, and children returned, as references to arrays.
# This is a perlism necessary to keep the arrays distict.
sub breed {
    my($parent1,$parent2) = @_;

    # occasionally we just copy into next generation, with no crossover
    if ( rand(1) > $crossover_prop ) {
        return $parent1,$parent2;
    }

	# crossover point 
	# (the 1+ is because of the prepended fitness value, before the params)
    my $crossoveridx=int(1+rand($nparams));
    
    @child1 = (@$parent1[0..$crossoveridx],
                    @$parent2[$crossoveridx+1..1+$nparams]);
    @child2 = (@$parent2[0..$crossoveridx],
                    @$parent1[$crossoveridx+1..1+$nparams]);

    return \@child1,\@child2;
}

# given reference to an incipient mutant, mutate.
# SHOULD WE ANNEAL, DECREASE MUTATION AMOUNT WITH INCREASING GEN NUMBER?
sub mutate {
	my($mutant) = @_;

	# random parameter index for which mutation occurs
	my $i=int(0.5+rand($nparams));

	# note the 1+ to avoid first element of array,
	# which is the fitness, not a param
	$mutant->[$i+1] = $param{(keys %param)[$i]}->[0] + rand($param{(keys %param)[$i]}->[1]-$param{(keys %param)[$i]}->[0]);
}
