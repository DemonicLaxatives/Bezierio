# Bezierio
A factorio mod for building parametrically defined defenses.


![Build small](https://github.com/DemonicLaxatives/Bezierio/blob/main/graphics/modpage/small-forest-wall.png)

Build small.


![Build big](https://github.com/DemonicLaxatives/Bezierio/blob/main/graphics/modpage/big-editor-wall.png)

Build big.


![Build with this](https://github.com/DemonicLaxatives/Bezierio/blob/main/graphics/modpage/curve-projector.png)

Build defenses with curve projector.

# How to:
1. Research the curve projector
2. Place it
3. Connect signal wires to the connectors on either side of the projector, they need X, Y, U, V signals. X,Y signify the position of the control point, U, V signify the control vector at that point.
4. Connect a signal wire to the connector in the middle of the projector, send it signal 
    - D to **D**raw the curve,
    - signal B to **B**uild it
    - signal T to set the **T**hickness (default is 1) 
    - and a signal of *most placable item like tiles or entites to set what to build, walls by default, it will pick a **valid signal with the highest signal value.
5. Gaze at the beutiful curves (squinting advised).

\* Some items like rails and hazard concrete will not work.

\*\* It will fail with aformentioned items and raise a warning.

------------
This is an early release of the mod, I'm only releasing it now to see if there would be any interest for something like this.

There other features planned for the future, but right now it has only one. Feel free to share your thoughts and crashlogs on the modpage or github.
