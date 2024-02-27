
/*
 * logrel.c
 * Relativize prices, turn table of prices into log relative prices.
 * Each col can be a separate instrument.
 * An optional --lag parameter specifies how many timesteps we look back.
 * Example:
 *	logrel --delta=1 <data/btcusd_hourly | normalize_tanh.pl >/tmp/logrel
 *
 */

#include <stdio.h>
#include <stdlib.h>
#include <getopt.h>
#include <math.h>

extern double *readmatrix(int *rows, int *cols, const char *filename);

long delta=1;			// lag from how many timesteps ago

void scanargs(int argc, char *argv[])
{
	int i;
	int c;

    while (1) {
    static struct option long_options[] =
        {
            {"delta",	required_argument,	0, 'd'},
            {0, 0, 0, 0}
        };

    int option_index = 0;
    // opterr=0 supress "unrecognized option" error
    extern int opterr; opterr=0;  // This must be always set to 0

	c = getopt_long_only(argc, argv, "d:",
                       long_options, &option_index);

        /* Detect the end of the options. */
        if (c == -1)
            break;

        switch (c) {

		case 'd':
			delta = atol(optarg);
            break;
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
}
	
int main(int argc, char** argv)
{
	long r,c;

	// process cmdline args
	scanargs(argc,argv);

	// read input data into 2d host matrix
	int rows,cols;
	double *in = readmatrix(&rows, &cols, "stdin");

	// prehistoric values are not known, just print log(1)
	for ( r=0 ; r<delta ; r++ ) {
		for ( c=0 ; c<cols ; c++ ) {
			printf("0.0 ");
		}
		printf("\n");
	}

	for ( r=delta ; r<rows ; r++ ) {
		for ( c=0 ; c<cols ; c++ ) {
			printf("%lf ",log(in[r*cols+c] / in[(r-delta)*cols+c]));
		}
		printf("\n");
	}

	// free the matrix
    free(in);
}
