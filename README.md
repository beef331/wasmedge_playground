# wasmedge_playground

This is mostly a place for me to play with wasm interop in an easy and portable way(soon to be :P ).

`wasmsources` contains modules that are to be  compiled to wasm.
Using the `wasmedge/exporter` module you can easily export procedures and then just compile the module.

To use this repo you will need to make a `nim.cfg` with `--define:wasmedgePath:"/path/to/wasmedge/"`.
On my system that's `--define:wasmedgePath:"/home/jason/.wasmedge/"`
