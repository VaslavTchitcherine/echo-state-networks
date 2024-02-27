#!/usr/bin/python
#
# fieldvis.py
# 3d visualization of esn parameter study
# (http://docs.enthought.com/mayavi/mayavi/mlab.html) 
#
# Example:
#  study_grid.pl data/btcusd_hourly >results/grid_btcusd_hourly
#  fieldvis.py <results/grid_btcusd_hourly
#

from mayavi import mlab
import numpy as np
import sys

# first line header is array dimensions
line = sys.stdin.readline()
(nx,ny,nz) = line.split()
nx = np.int(nx);
ny = np.int(ny);
nz = np.int(nz);

# create empty array of specified dimensions
s = np.empty((np.int(nx),np.int(ny),np.int(nz)))

# read data from into array s
for z in range(0,nz):
	for x in range(0,nx):
		for y in range(0,ny):
			line = sys.stdin.readline()
			(v,x,y,z) = line.split()
			s[x,y,z] = v

# isosurfaces
#mlab.contour3d(s,contours=8,opacity=0.3)

# volume rendering
#mlab.pipeline.volume(mlab.pipeline.scalar_field(s))

# cut planes
mlab.pipeline.image_plane_widget(mlab.pipeline.scalar_field(s),
                            plane_orientation='x_axes',
                            slice_index=np.int(nx/2)
                        )
mlab.pipeline.image_plane_widget(mlab.pipeline.scalar_field(s),
                            plane_orientation='y_axes',
                            slice_index=np.int(ny/2)
                        )
mlab.pipeline.image_plane_widget(mlab.pipeline.scalar_field(s),
                            plane_orientation='z_axes',
                            slice_index=np.int(nz/2)
                        )
mlab.outline()

mlab.show()
