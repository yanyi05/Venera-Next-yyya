# Automatic reading

Start automatic reading from the reader menu, or set the long-press action to “Start or stop automatic reading” in reading settings. Gallery mode follows the page interval; continuous and waterfall modes use smooth or step scrolling.

By default, automatic reading waits for images to load, including failed images that need a manual retry. Enable “Skip unavailable images during automatic reading” under Settings → Reading or the comic's reading settings to continue past unavailable images. Failed images advance at the normal reading pace. Loading images wait for the configured time before reading continues. The default wait is 10 seconds, adjustable from 1 to 60 seconds.

The image wait counts active foreground reading time. Active touch/zoom gestures, long presses, opening a menu, and switching to the background pause advancement. Waiting restarts after a pause without counting time in the background. Continuous and waterfall modes resume scrolling while zoomed after the gesture ends, preserve the configured screen-space speed, and finish the clipped tail before stopping or crossing chapters. Gallery mode still pauses automatic page turns while zoomed. A different page or group of visible images starts a new wait, as does retrying a failed image.

“Continue automatically to the next chapter” controls chapter boundaries. Skipping applies to images; failures loading chapter lists or chapter content still require a retry. Global, device, and comic settings follow the existing inheritance rules.
