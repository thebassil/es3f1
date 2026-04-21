/*
 *  HLS Matrix multiplication accelerator
 *
 *  Updated by: Callum Stew
 *  Adapted from work by: Eduardo Wachter
 *  Date: 23/07/2024
 *
 *  Baud rate: 115200
 */

#include "ap_axi_sdata.h"
#include "hls_stream.h"
#include "ap_int.h"

#define SIZE 5
#define ROWS SIZE
#define COLS SIZE
#define MULT_ACC SIZE

#define MAX_VAL 10
#define MIN_VAL 0

#define BIT_W 16

typedef ap_axis<BIT_W,0,0,0> packet;
typedef ap_int<BIT_W> data;
typedef hls::stream<packet> stream_data;

void array_mult (stream_data &in_a, data in_b[ROWS*COLS], stream_data &result);
