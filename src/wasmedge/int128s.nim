type
  uInt128t* {.importc: "unsigned __int128".} = object
    do_not_use1, do_not_use2: uint64
  int128t* {.importc: "__int128".} = object
    do_not_use1, do_not_use2: uint64
