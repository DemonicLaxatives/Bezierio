# Bézierio

A Factorio 2.1 mod for building walls, floors, power lines and turret rows along a Bézier curve.

![Build small](https://github.com/DemonicLaxatives/Bezierio/blob/main/graphics/modpage/small-forest-wall.png)

![Build big](https://github.com/DemonicLaxatives/Bezierio/blob/main/graphics/modpage/big-editor-wall.png)

> The screenshots are from 0.1, which used a "curve projector" building driven by
> circuit signals. Since 0.2 everything is done from GUI instead.

## How to use

1. Click the **Bézierio** button in the top-left button bar to open the window.
2. **Place control points (P1–P9).**
   - Click a point button to take its pointer into your hand, then click in the world to put the point there.
   - <kbd>Alt</kbd>+<kbd>1</kbd>…<kbd>9</kbd> picks up a pointer directly. <kbd>Alt</kbd>+scroll switches between pointers.
   - You can also type coordinates into the X/Y boxes and press <kbd>Enter</kbd>.
   - Right-click a point button to delete that point. The refresh button clears all points.
   - Points are used in order and empty slots are skipped. Two points make a straight line, three a quadratic curve, and so on. Put the last point on the first one to get a closed loop.
3. Toggle **Draw** to see the curve and its control polygon.
4. **Set up layers.** Pick an item for each layer with the item button.
   - **Layer 0** runs along the middle of the curve.
   - **Layers 1, 2, …** stack to the right of the direction of travel (P1 → last point). **Layers −1, −2, …** stack to the left. Use the **+** buttons to add layers above or below.
   - **Walls and tiles** fill a band. *Radius* sets the thickness. *Checkerboard* leaves out alternating squares of the given size; the sign picks which squares.
   - **Electric poles, electric turrets and roboports** are placed every *Spacing* tiles along the middle of their band.
   - *Layer offset* leaves a gap between a layer and the one inside it. An empty layer acts as a 1-tile spacer.
5. Toggle **Preview build** to see what would be placed.
6. **Build.**
   - **Force build** places ghosts and marks trees and rocks for deconstruction. Spots blocked by anything else are skipped.
   - **Super force build** also marks your own buildings in the way for deconstruction.

   Robots, or you, then build the ghosts.

   In the map editor or with cheat mode on, both buttons build the real entities and tiles straight away. Trees, rocks and (with super force) your buildings in the way are removed instead of marked, and existing ghosts on the curve are revived.

Rails can be selected for a layer but aren't built yet.

## Compatibility

- Factorio 2.1, base game. Tested with and without Space Age, Quality and Elevated Rails.
- Quality: the quality picked in the layer's item button is used for the ghosts.

Feedback and crash logs are welcome on the mod portal or on GitHub.
