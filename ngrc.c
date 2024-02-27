
/*
 * ngrc.c
 * Next generation reservoir computing.
 * (https://www.nature.com/articles/s41467-021-25801-2)
 * Example:
	logrel <data/btcusd_hourly | makelags.pl -nlags 3 | normalize_tanh.pl >/tmp/in
 	sed '1h;1d;$G' </tmp/in | awk '{if ($1>0) print "+1"; else print "-1"}' >/tmp/class
 	ngrc --dim=2 </tmp/in >/tmp/state
 	paste -d' ' /tmp/class /tmp/state >/tmp/train
	/home/egullich/svm/liblinear-multicore-2.43-2/train -s 2 -C /tmp/train
 */

#include <stdio.h>
#include <stdlib.h>
#include <getopt.h>

// default is linear outputs only
double dim=1.0;

extern double *readmatrix(int *rows, int *cols, const char *filename);

void scanargs(int argc, char *argv[])
{
	int i;
	int c;

    while (1) {
    static struct option long_options[] =
        {
            {"dim",	required_argument,	0, 'd'},
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
			dim = atof(optarg);
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
}
	
int main(int argc, char** argv)
{
	int rows,cols,r,c,c1,c2;
	int n;

	// process cmdline args
	scanargs(argc,argv);

	// read input data into 2d matrix
	double *m = readmatrix(&rows, &cols, "stdin");

	for ( r=0 ; r<rows ; r++ ) {
		n = 1;
		// linear outputs
		for ( c=0 ; c<cols ; c++ ) {
			printf("%d:%.4lf ",n++, m[r*cols+c]);
		}

		// outer product for all quadratic nonlinear outputs
		if ( dim > 1 ) {
			for ( c1=0 ; c1<cols ; c1++ ) {
				for ( c2=c1 ; c2<cols ; c2++ ) {
					printf("%d:%.4lf ",n++, m[r*cols+c1]*m[r*cols+c2]);
				}
			}
		}

		printf("\n");
	}

    free(m);
}

