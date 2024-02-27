
/*
 * deepesn.cpp
 * Echo State Network in Arrayfire, deep like Gallichio
 * Outputs the reservoir states (from neurons at all levels) at each timestep
 * (No network of output weights, we will use a linear svm on reservoir states.)
 * Example:
    logrel.pl <data/btcusd_hourly | normalize_tanh.pl >/tmp/logrel
    sed '1h;1d;$G' </tmp/logrel | awk '{if ($1>0) print "+1"; else print "-1"}' | tail -n +101  >/tmp/class
    deepesn --depth=1 --seed=11 --wscale=0.3 --radius=1.9 --leakage=0.17 --input=/tmp/logrel >/tmp/state
    paste -d' ' /tmp/class /tmp/state >/tmp/train
    /home/egullich/svm/liblinear-multicore-2.43-2/train -s 2 -C /tmp/train
 */

#include <stdio.h>
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
long depth = 1;				// default is shallow ESN
long nneurons = 1000/depth;	// number of neurons in each reservoir
double a = 0.3;				// leak rate
double wscale = 1.0;		// scaling for weights in Win
double radius = 1.25;		// spectral radius of W
double sparsity = 10.0/nneurons; // each neuron connected to 10 others (PracticalESN.pdf sec 3.2.2)
int seed=0;				// random seed (0 for nondeterministic default)

long startup = 100;		// warmup period to discard

long ninputs;		// number of inputs (# cols in input file)

char *infile=NULL;		// input data file

// to read input data from a file
extern "C" {
extern double *readmatrix(int *rows, int *cols, const char *filename);
}

// retain only a fraction of entries of 3d matrix m, other elements are zeroed
array sparsify(array m, double sparsity)
{
	// mask indicating which elements should be zeroed
	array zeroit = randu(m.dims(0), m.dims(1), depth, f64) < sparsity;

	// matrix of zeros
	array zeros = constant(0.0, m.dims(0), m.dims(1), depth, f64);

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
            {"leakage",	required_argument,	0, 'l'},
            {"sparsity",required_argument,	0, 'S'},
            {"depth",	required_argument,	0, 'd'},
            {0, 0, 0, 0}
        };

    int option_index = 0;
    // opterr=0 supress "unrecognized option" error
    extern int opterr; opterr=0;  // This must be always set to 0

	c = getopt_long_only(argc, argv, "i:s:w:e:r:l:s:",
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

		case 'l':		// leakage EMA constant
			a = atof(optarg);
            break;

		case 'S':		// reservoir sparsity [0.0,1.0], 1 for dense
			sparsity = atof(optarg);
            break;

		case 'd':		// deepesn depth
			depth = atoi(optarg);
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

	// number of neurons in each reservoir
	nneurons = 1000/depth;
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

// output state of all reservoirs to stdout, for liblinear supervised class learning 
// SHOULD WE ALSO OUTPUT THE CURRENT INPUT DATA FOR THIS TIME t ?
void output(array x)
{
	// copy array to host
	double *host_x = x.host<double>();
	
	for ( int i=0 ; i<nneurons*depth ; i++ ) {
		printf("%d:%.4lf ",i+1, host_x[i]);
	}
	printf("\n");
}


int main(int argc, char** argv)
{
	array Winter;	// inter-layer random weights (nneurons x nneurons)

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
	array Win = wscale * 2.0 * (randu(nneurons,ninputs,f64) - 0.5);

	// W is random matrix [-1.0,1.0] of reservoir weights, dimensions nneurons x nneurons x depth
	// The depth dimension is last so we can take 2d slices (e.g. W(span,span,0)) without moddims
	array W = 2.0 * (randu(nneurons,nneurons,depth,f64) - 0.5);

	// Winter are interlayer random matrices [-1.0,1.0] of weights
	if ( depth > 1 ) {
		// really only need depth-1 of these
		Winter = 2.0 * (randu(nneurons,nneurons,depth,f64) - 0.5);
	}

	// sparsify the array W
	W = sparsify(W, sparsity);

	// scale each reservoir to desired spectral radius
	for ( int d=0 ; d<depth ; d++ ) {
		// find spectral radius (absval of largest eigen value) of this layer of W 
		double rho = spectralradius(W(span,span,d));

		// scale W to desired spectral radius
		W(span,span,d) *= radius / rho;
		// sanity check that spectral radius is correct (might need to use f64)
		//printf("%f\n",spectralradius(W(span,span,d)));
	}

	// reservoir activations at current time t, initially all 0
	// (3d matrix: nneurons x 1 x depth)
	array x = constant(0.0, nneurons, 1, depth, f64);

	// run all data through the reservoir, collecting the reservoir states
	for ( int t=0 ; t<data.dims(0) ; t++ ) {
		// data row for this timestep (transposed to col vector for the matmul)
		array u = transpose(data(t,span));
		// input layer (gallichio20.pdf eqn. 1)
		x(span,span,0) = (1-a)*x(span,span,0) + a*tanh(matmul(Win,u) + matmul(W(span,span,0),x(span,span,0)));
		// deep layers (gallichio20.pdf eqn. 2)
		for ( int d=1 ; d<depth ; d++ ) {
			x(span,span,d) = (1-a)*x(span,span,d) + a*tanh(matmul(Winter(span,span,d),x(span,span,d-1)) + matmul(W(span,span,d),x(span,span,d)));
		}

		// discard output transients during warmup period
		if ( t >= startup ) {
        	output(flat(x));
		}
	}
}
