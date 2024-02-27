
#
# Makefile for echo state networks in Arrayfire
# (LD_LIBRARY_PATH must include /opt/arrayfire/lib64)
#

# choose one of these, CUDA is about 6x as fast on GTX1070
#LIBS = -lafcpu
LIBS = -lafcuda

INCLUDES = -I/opt/arrayfire/include
LIB_PATHS = -L/opt/arrayfire/lib64

CPP = g++ 
CC = gcc
CFLAGS = -g $(INCLUDES)

all: esn esnregress esnclassify deepesn logrel ngrc

# emit reservoir states
esn: esn.o readmatrix.o
	$(CPP) $(CFLAGS) -o esn esn.o readmatrix.o $(LIB_PATHS) $(LIBS)

# emit reservoir states
deepesn: deepesn.o readmatrix.o
	$(CPP) $(CFLAGS) -o deepesn deepesn.o readmatrix.o $(LIB_PATHS) $(LIBS)

# regression, compute mean squared error between prediction and actual series.
# (Prediction can be generative or 1 step ahead)
esnregress: esnregress.o readmatrix.o
	$(CPP) $(CFLAGS) -o esnregress esnregress.o readmatrix.o $(LIB_PATHS) $(LIBS)

# classification, compute directional hitrate for 1 step ahead prediction
esnclassify: esnclassify.o readmatrix.o
	$(CPP) $(CFLAGS) -o esnclassify esnclassify.o readmatrix.o $(LIB_PATHS) $(LIBS)

# log relative returns for specified delta
logrel: logrel.o readmatrix.o
	$(CC) $(CFLAGS) -o logrel logrel.o readmatrix.o -lm

# next generation reservoir computer
ngrc: ngrc.o readmatrix.o
	$(CC) $(CFLAGS) -o ngrc ngrc.o readmatrix.o -lm

.cpp.o:
	$(CPP) $(CFLAGS) -c $< -o $*.o

.c.o:
	$(CC) $(CFLAGS) -c $< -o $*.o

clean:
	rm -f *.o core esn readmatrix esnregress esnclassify logrel ngrc
