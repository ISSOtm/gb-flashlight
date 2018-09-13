
# gb-flashlight

Some ASM code that allows "flashlight" masking on Game Boy.

(c) 2018 Eldred Habert.


Note: this ASM is using the RGBDS syntax, and compiles fine under RGBDS 0.3.7; ports to other ASM syntaxes are allowed if the license is preserved (including inclusion of the notice in the source code) and a link to this repo (the original code).


## Including

The code is licensed using the MIT license, so you're clear to include this code. However, the process is not straightforward.

There are three pieces of code: the VBlank handler, the STAT handler, and the main loop.

- The STAT handler **has** to be copied as-is. Attempting to alter it will screw up timings, most likely.
- The VBlank handler code does not have to be copied as-is, but you need to run this code every VBlank. It's **critical** that this code is run every frame while the effect is going on. Note that the joypad-reading code isn't part of the effect itself. You may need to modify the code and/or your code as well, for example to modify how the OAM is DMA'd.
- The code in MainLoop should be put in the effect's main loop. (Not including the code that reads the joypad and updates flashlight parameters.) This code doesn't need to run on every frame.


## Known bugs

This is a list of bugs I know about but did not fix, for various reasons. This list also includes non-bugs that might be considered as such.

- **Sprite clipping doesn't work with row above rectangle.** Not fixed because it's late and I'm not sure how exactly to fix the problem. Also fixing it might break starting on line 0. Basically the only glitch I'm aware of that may be fixable... sounds promising for the rest of the list, eh?
- **Rectangle glitches out if left edge is too close to right of screen, or if there are many sprites on the same line.** Known bug, but unfixable. This occurs when the STAT interrupt terminates too late, and the following interrupt gets delayed because of that. Fixing it would require removing as much cycles as possible between the BGP write and the final `reti`. I have done my best towards that effort, but this is the best I can do!
- **Sprite clipping may screw up if last line of rectangle has many sprites.** Occurs when the last HBlank is skipped due to lag mentioned above. Sadly I'm not sure how to fix this.
- **Lag when the rectangle's bottom edge touches the last scanline.** I'm not sure exactly why it happens nor how to fix it.
- **Sprites disappear when rectangle is too wide.** Not a bug because the Game Boy has a 10-sprite-per-line limit, which can be hit because of the rectangle, since it uses sprites for the left edge, and more sprites when a sprite is overlapping the right edge.
- **Sprites disappear when right edge is 1 pixel away from screen.** Due to a bug in the Game Boy hardware, sprites are required to form the right edge when it's just 1 pixel thick. These sprites count towards the 10-sprite limit.
- **Sprites disappear when some sprites overlap with the right edge.** Again, the 10-sprite limit shows up - due to how BG-to-sprite and sprite-to-sprite priority work on GB, it's required to use one extra sprite for each sprite overlapping the right edge. Of course, this doesn't play well with the sprite limit.
- **Does not work in a GBC-enabled game.** Not a bug - the left edge of the rectangle is composed of a hardware bug exploit: rewriting the BG palette mid-*scanline*. This is not possible to do with GBC palettes. The code could be adapted to use sprites instead, but the 10-sprite limit would be pretty problematic then.
