/*
 *  HLS testbench for matrix multiplication accelerator
 *
 *  Updated by: Callum Stew
 *  Adapted from work by: Eduardo Wachter
 *  Date: 23/07/2024
 */

#include "matrix_mult.h"
#include <stdio.h>
#include <ctime>

#define BIT_W_TB BIT_W

typedef ap_axis<BIT_W_TB,0,0,0> packet_tb;
typedef ap_int<BIT_W_TB> data_tb;
typedef hls::stream<packet_tb> stream_data_tb;

void generate(data_tb array[ROWS*COLS])
{
    int i, j;

    for (i = 0; i < SIZE; i++) {
        for (j = 0; j < SIZE; j++) {
            // Populate rows and columns with rand() values
            array[i*ROWS+j] = rand() % (MAX_VAL + 1 - MIN_VAL) + MIN_VAL;
            printf("%d\t", (int) array[i*ROWS+j]);
        }
        printf("\n\r");
    }
    printf("\n\r");
};

void print_array(data_tb array[ROWS*COLS]) 
{
    int i, j;

    for (i = 0; i < SIZE; i++) {
        for (j = 0; j < SIZE; j++) {
            printf("%d\t", (int)array[i*ROWS+j]);
        }
        printf("\n\r");
    }
    printf("\n\r");
};

int main()
{
    int i,j,k;
    int mult_acc;
    int error_flag=0;
    data_tb in_a_tb[ROWS*MULT_ACC], mult_func_exp[ROWS*COLS];
    data_tb in_b_tb[MULT_ACC*COLS];
    packet_tb in_a_tb_axis[SIZE*SIZE];
    packet_tb mult_func_tb_axis[SIZE*SIZE];
    stream_data_tb in_a_tb_stream;
    stream_data_tb mult_func_tb_stream;

    time_t t;
    t=1549294172;
    // time(&t));
    srand((unsigned) t);
    printf("Random seed: %ld\n", t);

    generate(in_a_tb);
    generate(in_b_tb);

    for (i = 0; i < ROWS; i++) {
        for (j = 0; j < COLS; j++){
            in_a_tb_axis[i*ROWS+j].data=in_a_tb[i*ROWS+j];
        }
    }

    // Send in_a to stream
    for (i = 0; i < SIZE*SIZE; i++) {
        in_a_tb_stream.write(in_a_tb_axis[i]);
    }

    array_mult(in_a_tb_stream, (data_tb *)in_b_tb, mult_func_tb_stream); // Calls the function in the source file

    // Read result from stream
    for (i = 0; i < SIZE*SIZE; i++) {
        mult_func_tb_stream.read(mult_func_tb_axis[i]);
    }

    // Calculates the expected result and makes the comparison with the one from the source file.
    int acc_tb,acc_exp;
    acc_exp=0;
    ROWS_LOOP: for (i=0;i<ROWS;i++) {
        COLS_LOOP: for (j=0;j<COLS;j++) {
            mult_acc=0;
            MULT_ACC_LOOP: for (k=0;k<MULT_ACC;k++) {
                mult_acc+=in_a_tb[i*ROWS+k]*in_b_tb[k*ROWS+j];
            }

            mult_func_exp[i*ROWS+j]=mult_acc;
            if (mult_func_exp[i*ROWS+j]!=mult_func_tb_axis[i*ROWS+j].data) {
                error_flag=1;
            }
        }
    }

    printf("Expected array:\n");
    print_array(mult_func_exp);
    printf("Array accelerator:\n");
    for (i = 0; i < SIZE; i++) {
        for (j = 0; j < SIZE; j++) {
            printf("%d\t", mult_func_tb_axis[i*ROWS+j].data.to_int());
        }
        printf("\n\r");
    }
    printf("\n\r");

    if (error_flag==0) {
        return 0;
    } else {
        return 1;
    }
}
