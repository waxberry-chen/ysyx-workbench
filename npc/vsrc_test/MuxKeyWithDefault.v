module MuxKeyWithDefault #(NR_KEY = 2, KEY_LEN = 1, DATA_LEN = 1)(
    input [KEY_LEN-1 : 0] key,
    input [DATA_LEN-1 : 0] default_out,
    input [NR_KEY*(KEY_LEN+DATA_LEN)-1 : 0] lut,
    output [DATA_LEN-1 : 0] out
);
    MuxKeyInternal #(NR_KEY, KEY_LEN, DATA_LEN, 1) i0 (
    .key(key),
    .default_out(default_out),
    .lut(lut),
    .out(out)
    );
endmodule
