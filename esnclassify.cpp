
/*
 * esnclassify.cpp
 * Echo State Network in Arrayfire, uses least squares to compute output weights.
 * Returns hit rate for 1 step ahead direction prediction.
 * DOES NOT WORK AS WELL AS LINEAR SVM CLASSIFIER.
 * Examples:
 *	esnclassify --reg=-8 --wscale=0.5 --trainlen=2000 --testlen=2000 --input=data/mackeyglass_t17.txt -d >/tmp/d
 *	esnclassify --wscale=0.1 --radius=1.1 --reg=-3 -leakage=0.91 --trainlen=8000 --testlen=1000 --input=data/laser -d >/tmp/d
 *
 	logrel.pl <data/btcusd_hourly | normalize_tanh.pl >/tmp/logrel
 	esnclassify --seed=3339881004 --wscale=1.79766148655796 --radius=1.95042593935705 --leakage=0.0164957244518442 --reg=-3 --trainlen=6000 --testlen=535 --input=/tmp/logrel -d >/tmp/d
 	esnclassify --seed=1661813142 --wscale=0.289132015674502 --radius=1.86110802739177 --leakage=0.187609999818802 --reg=-3 --trainlen=6000 --testlen=535 --input=/tmp/logrel -d >/tmp/d
 	esnclassify --seed=485544591 --wscale=1.73024601877102 --radius=1.98299229910553 --leakage=0.37308164834003 --reg=-8 --trainlen=6000 --testlen=535 --input=/tmp/logrel -d >/tmp/d
 *
 *
 */

#include <stdio.h>
#include <arrayfire.h>
#include <getopt.h>
#include <string.h>
#include <strings.h>
#include <values.h>
#include <fcntl.h>
#include <unistd.h>

#define BUFSIZE 1024

// for ArrayFire objects
using namespace af;

// default ESN parameters
long nneurons = 1000;    // number of neurons in reservoir (max is about 2500 on laptop GPU)
double a = 0.3;         // leak rate
double wscale = 1.0;	// scaling for input weights Win
double radius = 1.0;   // spectral radius of W
double reg = 1.0e-8;	// Tikhonov regulatization constant
double sparsity = 10.0/nneurons; // each neuron connected to 10 others (PracticalESN.pdf sec 3.2.2)
int seed=0;				// random seed (0 for nondeterministic default)

// training parameters
long trainlen = 0;		// train esn over this many steps
long testlen = 0;		// compute hitrate over this many subsequent steps
long startup = 100;		// warmup period to discard

long ninputs;       // number of inputs (# cols in input file)

// dump actual and predicted values to stdout for plotting
char dump=0;

char infile[BUFSIZE]={'\0'};

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
            {"reg",	required_argument,	0, 'r'},
            {"seed",	required_argument,	0, 'e'},
            {"radius",	required_argument,	0, 'R'},
            {"leakage",	required_argument,	0, 'l'},
            {"sparsity",required_argument,	0, 'S'},
            {"trainlen",required_argument,	0, 't'},
            {"testlen",required_argument,	0, 'T'},
            {"dump",	no_argument,	0, 'd'},
            {"verbose",	no_argument,  0, 'v'},
            {0, 0, 0, 0}
        };

    int option_index = 0;
    // opterr=0 supress "unrecognized option" error
    extern int opterr; opterr=0;  // This must be always set to 0

	c = getopt_long_only(argc, argv, "i:s:w:r:e:R:l:S:t:T:dv",
                       long_options, &option_index);

        /* Detect the end of the options. */
        if (c == -1)
            break;

        switch (c) {

		case 'i':		// name of timeseries input file
			strcpy(infile, optarg);
            break;

		case 's':		// reservoir size
			nneurons = atol(optarg);
            break;

		case 'w':		// Win weight scaling
			wscale = atof(optarg);
            break;

		case 'r':		// log Tikhonov regularization coefficient
			reg = pow(10,atof(optarg));
            break;

		case 'e':		// random seed
			seed = atoi(optarg);
            break;

		case 'R':		// spectral radius
			radius = atof(optarg);
            break;

		case 'l':		// leakage
			a = atof(optarg);
            break;

		case 'S':		// reservoir sparsity coefficient (1.0 for dense)
			sparsity = atof(optarg);
            break;

		case 't':
			trainlen = atol(optarg);
            break;

		case 'T':
			testlen = atol(optarg);
            break;

		case 'd':		// dump
			dump = 1;
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
	if ( infile[0] == '\0' ) {
		fprintf(stderr,"Must specify an input series with -i\n");
		exit(-1);
	}

	if ( !trainlen ) {
		fprintf(stderr,"Must specify an training length with --trainlen\n");
		exit(-1);
	}

	if ( !testlen ) {
		fprintf(stderr,"Must specify an testing length with --testlen\n");
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

int main(int argc, char** argv)
{
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

	//timer::start();
	
	// Win is random matrix [-wscale,wscale] of input weights, dimensions nneurons x (insize+1)
	// (The additional col is because there is always a constant 1 input to the reservoir.)
	array Win = wscale * 2.0 * (randu(nneurons,1+ninputs,f64) - 0.5);

	// W is random matrix [-1.0,1.0] of reservoir weights, dimensions nneurons x nneurons
	array W = 2.0 * (randu(nneurons,nneurons,f64) - 0.5);

	// sparsify the array W
	W = sparsify(W, sparsity);
	
	// find spectral radius of W (absval of largest eigen value)
	double rho = spectralradius(W);

	// scale W to desired spectral radius
	W *= radius / rho;
	// sanity check that spectral radius is correct (might need to use f64)
	//printf("%f\n",spectralradius(W));

	// reservoir activations at current time t, initially all 0
	// SHOULD THIS BE 1d rather than a col vector ???
	array x = constant(0.0, nneurons, 1, f64);

	// catenate a constant col of 1s (for bias input) to the data matrix
	array ones = constant(1.0, data.dims(0), 1, f64);
	array data1 = join(1,ones,data);

	// Allocate memory for the design (collected states) matrix.
	// Timesteps are in cols, each col has: constant bias 1, input data vector, reservoir activations x
	array X = constant(0.0, 1+ninputs+nneurons, trainlen-startup, f64);

	// run training data through the reservoir, collecting the reservoir states
	for ( int t=0 ; t<trainlen ; t++ ) {
		// data row for this timestep (transposed for the matmul)
		array u = transpose(data1(t,span));
		// compute new reservoir activations, applying leakage
		// (PracticalESN.pdf, eqns 2 and 3)
		x = (1-a)*x + a*tanh(matmul(Win,u) + matmul(W,x));
		// discard output during warmup
		if ( t >= startup ) {
			// (PracticalESN.pdf, eqn 4)
        	X(span,t-startup) = join(0,u,x);
		}
	}

	// set the target matrix (desired outputs) directly,
	// note this looks ahead one timestep 
	array Yt = data(seq(startup+1,trainlen),span);		// note not trainlen+1 as in python
	// transpose to a column vector (NEEDED?)
	Yt = transpose(Yt);

#ifdef PSEUDOINVERSE
	// Solve for output weights Wout, using Moore-Penrose pseudoinverse
	// Needs arrayfire >=3.7.0
	// No regularization needed, but be sure 1+ninputs+nneurons << trainlen.
	// Wout dimensions are 1 x 1+ninputs+nneurons
	// DOES NOT WORK WELL, LARGE MSE DEVELOPS QUICKLY WHEN FREE RUNNING
	array Wout = matmul(Yt, pinverse(X));
#else

	// ridge regression, Tikhonov regularization coefficient
	// (PracticalESN.pdf eqn 9)
	array Wout = matmul(matmul(Yt,transpose(X)), inverse(matmul(X,transpose(X)) + reg*identity(1+ninputs+nneurons,1+ninputs+nneurons,f64)));
#endif // PSEUDOINVERSE

	// if weights of Wout are too large, something is wrong
	// (Implies poor generalization to test data unless the latter come from exactly the
	// same (deterministic) source as the training data.)
	//fprintf(stderr,"avg Wout: %lf ", sum<double>(abs(Wout))/Wout.dims(1));

	// data row for current timestep (transposed for the matmul)
	array u = transpose(data1(trainlen,span));

	long hitrate=0;
	double actual,actual1,predicted,predicted1;

	// run the trained ESN in a generative mode.
	// No need to initialize here, x is initialized with training data and we continue from there.
	for ( int t=0 ; t<testlen ; t++ ) {
    	// update the reservoir output vector x
		x = (1-a)*x + a*tanh(matmul(Win,u) + matmul(W,x));

    	// run x through the output network to get prediction y
		// (this is really just a dot product, both args are 1d so output is scalar)
    	array y = matmul(Wout, join(0,u,x));

// probably never want generative for classification
#ifdef GENERATIVE
    	// free running generative mode, next input is our current prediction fed back
		// (need to prepend the constant 1)
    	u = join(0,constant(1.0,1,f64), y);
#else
    	// for 1 step ahead prediction, set u to actual next value,
		// rather than predicted value
    	u = transpose(data1(trainlen+t+1,span));
#endif // GENERATIVE

		// actual and predicted values for the next timestep, host side
		actual = data(trainlen+t+1,0).scalar<double>();
		predicted = y.scalar<double>();
		
		// if direction of both actual and predicted agree, we score a hit
		if ( actual>0.0 && predicted>0.0 )
			hitrate++;
		if ( actual<0.0 && predicted<0.0 )
			hitrate++;

		// to dump actual and predicted values for plotting
		if ( dump ) {
			printf("%lf %lf\n",predicted,actual);
		}

		// age values
		actual1 = actual;
		predicted1 = predicted;
	}

    // print hitrate
	printf("%g\n", (float)hitrate/(float)testlen);
	//fprintf(stderr,"elapsed seconds: %g\n", timer::stop());
}
