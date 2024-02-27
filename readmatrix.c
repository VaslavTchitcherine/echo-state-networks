
/*
 * readmatrix.c
 * read file of unknown size into a 2d matrix of doubles, returns dimensions
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

#define BUFSIZE 1024

double *readmatrix(int *rows, int *cols, const char *filename)
{
	FILE *fp;
    double *matrix=NULL;
    char line[BUFSIZE];

    *rows = 0;
    *cols = 0;

	if ( !strcmp(filename,"stdin") ) {
		fp = stdin;
	}
	else {
    	fp = fopen(filename, "r");
    	if ( !fp ) {
        	fprintf(stderr, "Error, could not open %s: %s\n", filename, strerror(errno));
        	exit(-1);
    	}
	}

    while ( fgets(line, BUFSIZE, fp) ) {

		// first time through, count the cols
        if ( *cols == 0 ) {
            char *scan = line;
            double dummy;
            int offset = 0;
            while ( 1 == sscanf(scan, "%lf%n", &dummy, &offset) ) {
                scan += offset;
                (*cols)++;
            }
        }

		// grow the matrix by one line
        matrix = realloc(matrix, (*rows+1)*(*cols)*sizeof(double));

		// sanity
        if ( !matrix ) {
            fprintf(stderr, "Error, realloc failed\n");
			exit(-1);
        }

		// read all the cols into the current row
        int offset = 0;
        char *scan = line;
        for ( int j = 0; j < *cols; j++ ) {
            if ( 1 == sscanf(scan, "%lf%n", &matrix[(*rows)*(*cols) + j], &offset) )
                scan += offset;
            else {
            	fprintf(stderr, "Error, sccanf failed\n");
				exit(-1);
			}
        }

        // increment row index
        (*rows)++;
    }

    fclose(fp);

    return matrix;
}
