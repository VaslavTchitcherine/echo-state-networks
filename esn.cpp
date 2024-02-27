
/*
 * esn.cpp
 * Echo State Network in Arrayfire.
 * Equations from Lukosevicius PracticalESN.pdf (doi:10.1007/978-3-642-35289-8-36)
 * Outputs the reservoir states at each timestep.
 * In this implementation there is no network of output weights, 
 * we will use a linear svm on reservoir states.
 * Example:
 	logrel.pl <data/btcusd_hourly | normalize_tanh.pl >/tmp/logrel
 	sed '1h;1d;$G' </tmp/logrel | awk '{if ($1>0) print "+1"; else print "-1"}' | tail -n +101  >/tmp/class
 	esn --seed=11 --wscale=1.7 --radius=0.56 --leakage=0.31 --input=/tmp/logrel >/tmp/state
 	paste -d' ' /tmp/class /tmp/state >/tmp/train
	/home/egullich/svm/liblinear-multicore-2.43-2/train -s 2 -C /tmp/train
 */

#include <stdio.h>
#include <stdlib.h>
#include <arrayfire.h>
#include <getopt.h>
#include <string.h>
#include <strings.h>
#include <values.h>
#include <fcntl.h>
#include <unistd.h>

// for ArrayFire objects
using namespace af;

// default ESN parameters
long nneurons = 1000;	// number of neurons in reservoir (max is about 2500 on laptop GPU)
double a = 0.3;         // leak rate
double wscale = 1.0;	// scaling for weights in Win
double radius = 1.25;   // spectral radius of W
double sparsity = 10.0/nneurons; // each neuron connected to 10 others (PracticalESN.pdf sec 3.2.2)
int seed=0;				// random seed (0 for nondeterministic default)
long warmup = 100;		// warmup period to discard

long ninputs;		// number of inputs (# cols in input file)

char *infile=NULL;		// input data file
char *statefile=NULL;	// initialize reservior activations from end of this file

// to read input data from a file
extern "C" {
extern double *readmatrix(int *rows, int *cols, const char *filename);
}

// retain only a fraction of entries of matrix m, 
// other elements are zeroed
array sparsify(array m, double sparsity)
{
	// mask indicating which elements should be zeroed
	array zeroit = randu(m.dims(0),m.dims(1),f64) < sparsity;

	// matrix of zeros
	array zeros = constant(0.0, m.dims(0), m.dims(1), f64);

	// replace masked elements with zero
	replace(m, zeroit, zeros);

	return m;
}

// get random seed from entropy pool, used to initialize the ArrayFire RNG
int randseed()
{
	int randomfd;
	int seed;
			
	if ( 0 > (randomfd = open("/dev/urandom",O_RDONLY)) ) {
		fprintf(stderr,"Couldn't open /dev/urandom\n");
		exit(-1);
	}
	if ( 4 != read(randomfd,&seed,4) ) {
		fprintf(stderr,"Couldn't read 4 bytes from /dev/urandom\n");
		exit(-1);
	}
	close(randomfd);

	return seed;
}

void scanargs(int argc, char *argv[])
{
	int i;
	int c;

    while (1) {
    static struct option long_options[] =
        {
            {"input",	required_argument,	0, 'i'},
            {"size",	required_argument,	0, 's'},
            {"wscale",	required_argument,	0, 'w'},
            {"seed",	required_argument,	0, 'e'},
            {"radius",	required_argument,	0, 'r'},
            {"leakage",	required_argument,	0, 'a'},
            {"sparsity",required_argument,	0, 'S'},
            {"statefile",required_argument,	0, 'l'},
            {"warmup",	required_argument,	0, 'W'},
            {0, 0, 0, 0}
        };

    int option_index = 0;
    // opterr=0 supress "unrecognized option" error
    extern int opterr; opterr=0;  // This must be always set to 0

	c = getopt_long_only(argc, argv, "i:s:w:e:r:a:S:l:W:",
                       long_options, &option_index);

        /* Detect the end of the options. */
        if (c == -1)
            break;

        switch (c) {

		case 'i':		// name of timeseries input file
			infile = (char*)malloc(1+strlen(optarg));
			strcpy(infile, optarg);
            break;

		case 's':		// reservoir size
			nneurons = atol(optarg);
            break;

		case 'w':		// Win weight scaling
			wscale = atof(optarg);
            break;

		case 'e':		// random seed
			seed = atoi(optarg);
            break;

		case 'r':		// spectral radius
			radius = atof(optarg);
            break;

		case 'a':		// leakage EMA constant
			a = atof(optarg);
            break;

		case 'S':		// reservoir sparsity [0.0,1.0], 1.0 for dense
			sparsity = atof(optarg);
            break;

		case 'l':		// load reservoir activation state from this file
			statefile = (char*)malloc(1+strlen(optarg));
			strcpy(statefile, optarg);
			break;

		case 'W':		// warmup period
			warmup = atoi(optarg);
            break;

        default:
			fprintf(stderr,"Error, unknown option in scanargs: %c\n",c);
			exit(-1);
        }
	}

	// Print any remaining command line arguments (not options)
	if ( optind < argc ) {
		printf ("Unknown cmdline argument: ");
		while (optind < argc) 
			printf("%s ", argv[optind++]); 
		putchar ('\n');
		exit(-1);
	}

	// no input timeseries -i specified
    if ( !infile ) {
		fprintf(stderr,"Must specify an input series with -i\n");
		exit(-1);
	}
}
	
// power method to compute principal eigenvalue
double spectralradius(array m)
{
	double oldlen=0.0,len=FLT_MAX;

	// initial eigenvector estimate, all 1.0
	array v = constant(1.0, m.dims(1), f64);

	// tolerance is somewhat sloppy, but OK for our purpose
	while ( fabs(len-oldlen) > 1.0e-4 ) {
		v = matmul(m,v);
		oldlen = len;
		len = sqrt(sum<double>(v*v));
		v = v / len;
	}

	return len;
}

// output reservoir state to stdout for liblinear
// SHOULD WE ALSO OUTPUT THE CURRENT INPUT DATA FOR THIS TIME t ?
void output(array x)
{
	// copy array to host
	double *host_x = x.host<double>();
	
	for ( int i=0 ; i<nneurons ; i++ ) {
		printf("%d:%.4lf ",i+1, host_x[i]);
	}
	printf("\n");
}

// Load reservoir state from previous output file.
// Used to initialize reservoir for test data
array loadstate(char *filename)
{
	char cmd[1024];
	double x_host[nneurons];

	// remove labels from last line of state file
	sprintf(cmd, "tail -1 %s | sed \"s/[0-9]*://g\" >/media/ramdisk/lastline", filename);
	system(cmd);

	FILE *fp = fopen("/media/ramdisk/lastline" , "r");
    if ( !fp ) {
        fprintf(stderr, "Error, could not open /media/ramdisk/lastline\n");
        exit(-1);
    }

	for ( int i=0 ; i<nneurons ; i++ ) {
		fscanf(fp, "%lf", &x_host[i]);
	}

	fclose(fp);

	// convert to arrayfile array
	array state(nneurons, x_host);
	return state;
}

int main(int argc, char** argv)
{
	array x;	// activations of reservoir neurons

	// process cmdline args
	scanargs(argc,argv);

	// read input data into 2d host matrix
	int rows,cols;
	double *matrix = readmatrix(&rows, &cols, infile);

	// copy into 2d arrayfire array, one col per input variable
	array data(rows, cols, matrix);

	// free the host data
    free(matrix);

	// one input for each column in the input file
	ninputs = cols;

	// if --seed was specified (i.e. is not the default value of zero),
	// initialize ArrayFire random number generator with a random seed from the entropy pool
	if ( seed==0 ) {
		seed = randseed();
	}
	setSeed(seed);
	setDefaultRandomEngineType(AF_RANDOM_ENGINE_THREEFRY);

	// Win is random matrix [-wscale,wscale] of input weights, dimensions nneurons x ninputs
#ifdef BIAS
	// additional col for constant 1 bias input to the reservoir
	array Win = wscale * 2.0 * (randu(nneurons,1+ninputs,f64) - 0.5);
#else
	array Win = wscale * 2.0 * (randu(nneurons,ninputs,f64) - 0.5);
#endif // BIAS

#define DETERMINISTIC
#ifdef DETERMINISTIC
	// deterministic ESN, delay line (DLR)
	// (Deterministic_Echo_State_Networks_Based_Stock_Pric.pdf)
	array W = constant(0.0, nneurons, nneurons, f64);
	for ( int i=0 ; i<nneurons-1 ; i++ ) {
		// DLR (delay line reservoir)
		W(i,i+1) = 0.5;
		// uncomment this line for DLRB (DLR with back connections)
		W(i+1,i) = 0.05;
		// uncomment this line for SCR (simple cycle reservoir)
		W(0,nneurons-1) = 0.5;
		// or leave them all uncommented, seems to work OK
	}
#else
	// W is random matrix [-1.0,1.0] of reservoir weights, dimensions nneurons x nneurons
	array W = 2.0 * (randu(nneurons,nneurons,f64) - 0.5);
	// sparsify the array W
	W = sparsify(W, sparsity);
#endif // DETERMINISTIC
	
	// find spectral radius of W (absval of largest eigen value)
	double rho = spectralradius(W);

	// scale W to desired spectral radius
	W *= radius / rho;
	// sanity check that spectral radius is correct (might need to use f64)
	//printf("%f\n",spectralradius(W));

	// when --statefile is specified, initialize reservior with state at end of specified file
	// Note this assumes test data temporally follows end of training data
	if ( statefile ) {
		x = loadstate(statefile);
	}
	else {
		// vector of reservoir activations at current time t, initially all 0
		x = constant(0.0, nneurons, f64);
	}

#ifdef BIAS
	array ones = constant(1.0, data.dims(0), f64);
	array data1 = join(1,ones,data);
#endif // BIAS

	// run all data through the reservoir, collecting the reservoir states
	for ( int t=0 ; t<data.dims(0) ; t++ ) {
		// data row for this timestep (transposed for the matmul)
#ifdef BIAS
		array u = transpose(data1(t,span));
#else
		array u = transpose(data(t,span));
#endif // BIAS
		// compute new reservoir activations, applying leakage
		// (PracticalESN.pdf, eqns 2 and 3)
		x = (1-a)*x + a*tanh(matmul(Win,u) + matmul(W,x));
		// discard output transients until system stable
		if ( t >= warmup ) {
        	output(x);
		}
	}
}
