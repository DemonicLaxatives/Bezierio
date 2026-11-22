import datetime
import numpy as np
import matplotlib.pyplot as plt

R = 5

xx, yy = np.mgrid[-R-1:R+2, -R-1:R+2]
mask = xx**2 + yy**2 <= R**2

fig, ax = plt.subplots(1, 1)
ax.set_aspect('equal')
ax.set_axis_off()
ax.pcolormesh(xx, yy, mask, cmap='gray')
