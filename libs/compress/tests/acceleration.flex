// Test-only dispatch controls; these fields are private to this codec.
fn test_acceleration(c,encoder) {
 let mode=h_getenv("FLEX_ZSTD_ACCELERATION");if !mode {return 0;}
 if h_equal(mode,"0") {if encoder {zstd_encoder_acceleration(c,0);}else {zstd_decoder_acceleration(c,0);}}
 else if h_equal(mode,"baseline") && !encoder && load64(c+1760) {store64(c+2024,load64(c+328));store64(c+1768,load64(c+336));store64(c+344,0);}
 return 0;
}
