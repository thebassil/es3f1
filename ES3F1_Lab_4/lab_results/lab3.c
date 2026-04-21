/*
 *  Calulates multiplication of two matrices and measures time taken in both software
 *  and hardware implementations.
 *
 *  Author: Callum Stew
 *  Adapted from work by: Eduardo Wachter
 *  Date: 23/07/2024
 *
 *  Baud rate: 115200
 */

#include <stdio.h>
#include <stdlib.h>
#include "platform.h"
#include "xparameters.h"
#include "xil_printf.h"
#include "xiltimer.h"
#include "xaxidma.h"
#include "xarray_mult.h"

#define SIZE 5
#define ROWS SIZE
#define COLS SIZE
#define MAX_VAL 10
#define MIN_VAL 0
#define NUM_ARRAYS 5

// #define DEBUG

void generate(int *array, int num_arrays_local)
{
    int i, j, k;

    for (k = 0; k < num_arrays_local; k++) {
        for (i = 0; i < SIZE; i++) {
            for (j = 0; j < SIZE; j++) {
                // Populate rows and columns with rand() values
                array[(k*ROWS*COLS)+(i*ROWS)+j] = rand() % (MAX_VAL + 1 - MIN_VAL) + MIN_VAL;
                printf("%d\t", array[(k*ROWS*COLS)+(i*ROWS)+j]);
            }
            printf("\n\r");
        }
        printf("\n\r");
    }
};

void print_array(int *array, int num_arrays_local)
{
    int i, j,k;

    for (k = 0; k < num_arrays_local; k++) {
        for (i = 0; i < SIZE; i++) {
            for (j = 0; j < SIZE; j++) {
                printf("%d\t", array[(k*ROWS*COLS)+(i*ROWS)+j]);
            }
            printf("\n\r");
        }
        printf("\n\r");
    }
};

void multiply(int *array_x, int *array_y, int *array_z)
{
    int i, j, k, n;


    for (n = 0; n < NUM_ARRAYS; n++) {
        for (i = 0; i < SIZE; i++) {
            for (j = 0; j < SIZE; j++) {
                array_z[(n*ROWS*COLS)+i*SIZE+j] = 0;
                for (k = 0; k < SIZE; k++) {
                    array_z[(n*ROWS*COLS)+i*SIZE+j] += (array_x[(n*ROWS*COLS)+i*SIZE+k] * array_y[k*SIZE+j]);

                    #if defined(DEBUG)
                        xil_printf("z: %d = x: %d * y %d\n\r", array_x[i][j], array_x[i][k], array_y[k][j]);
                    #endif
                }
            }
        }
    }
};

int main()
{
    init_platform();

    usleep(1); // Neded to get timer to work

    XTime tSeed, tStart_sw, tEnd_sw;
    XTime tStart_hw, tEnd_hw;

    // Use start time as a seed for rand()
    XTime_GetTime(&tSeed);
    srand((unsigned) tSeed);

    int rows = SIZE, cols = SIZE, num_arrays=NUM_ARRAYS, i, j, n;
    int *x, *y, *z, *hw_res;

    // Allocate the array in memory
    x = malloc(num_arrays*rows*cols * sizeof *x);
    y = malloc(rows*cols * sizeof *y);
    z = malloc(num_arrays*rows*cols * sizeof *z);

    hw_res = malloc(num_arrays*rows*cols * sizeof *hw_res);

    // Initialising the accelerator
    XArray_mult array_mult_hw; // Instantiation struct for the unoptmized accelerator
    XArray_mult_Config *array_mult_hw_cfg; // Configuration struct pointer for the ununoptmized accelerator
    int status;

    array_mult_hw_cfg = XArray_mult_LookupConfig(XPAR_ARRAY_MULT_0_BASEADDR); // Loads the configuration of the accelerator
    if (!array_mult_hw_cfg) { // Checks that the configuration has been loaded
        xil_printf("Error loading the configuration of the accelerator\n\r");
    }

    status = XArray_mult_CfgInitialize(&array_mult_hw, array_mult_hw_cfg); // Initilises the accelerator
    if (status != XST_SUCCESS) { // Checks that the accelerator has been initialized
        xil_printf("Error initializing the accelerator\n\r");
    }

    // Initialing the axi dma
    XAxiDma axiDMA;
    XAxiDma_Config *axiDMA_cfg;

    axiDMA_cfg = XAxiDma_LookupConfig(XPAR_AXI_DMA_0_BASEADDR);
    if (axiDMA_cfg) {
        int status = XAxiDma_CfgInitialize(&axiDMA, axiDMA_cfg);
        if(status != XST_SUCCESS){
            printf("Error Initializing AXI DMA core\n");
        }
    }

    xil_printf("Generating Matrices X, Y & Z...\n\n\r");

    xil_printf("Matrix X\n\r");
    generate(x, NUM_ARRAYS);

    xil_printf("Matrix Y\n\r");
    generate(y, 1);

    xil_printf("Multiplying X & Y and starting timer...\n\n\r");
    // Get time at start of multiplication
    XTime_GetTime(&tStart_sw);

    // No print statements within this function
    multiply(x, y, z);

    // Get time at end of multiplication
    XTime_GetTime(&tEnd_sw);
    xil_printf("Stopping timer...\n\n\r");

    xil_printf("Result Matrix Z\n\r");
    for (n = 0; n < NUM_ARRAYS; n++) {
        for (i = 0; i < SIZE; i++) {
            for (j = 0; j < SIZE; j++) {
                xil_printf("%d\t", z[(n*ROWS*COLS)+i*SIZE+j]);
            }
            xil_printf("\n\r");
        }
        xil_printf("\n\r");
	}

    XArray_mult_Write_in_b_Bytes(&array_mult_hw, 0, y, sizeof(y)*(rows*cols));

    Xil_DCacheFlushRange((u32)x, (num_arrays*rows*cols)*sizeof(int));
    Xil_DCacheFlushRange((u32)hw_res, (num_arrays*rows*cols)*sizeof(int));

    XArray_mult_Start(&array_mult_hw); // Starts the accelerator
    XArray_mult_EnableAutoRestart(&array_mult_hw);


    XTime_GetTime(&tStart_hw);
    XAxiDma_SimpleTransfer(&axiDMA, (u32)x, (num_arrays*rows*cols)*sizeof(int), XAXIDMA_DMA_TO_DEVICE);
    while (XAxiDma_Busy(&axiDMA, XAXIDMA_DMA_TO_DEVICE));

    XAxiDma_SimpleTransfer(&axiDMA, (u32)hw_res, (num_arrays*rows*cols)*sizeof(int), XAXIDMA_DEVICE_TO_DMA);
    while (XAxiDma_Busy(&axiDMA, XAXIDMA_DEVICE_TO_DMA));
    XTime_GetTime(&tEnd_hw);

    Xil_DCacheInvalidateRange((u32)hw_res, (num_arrays*rows*cols)*sizeof(int));

    printf("Results\n");

    int error_flag=0;
    for (n = 0; n < NUM_ARRAYS; n++) {
        for (i = 0; i < SIZE; i++) {
            for (j = 0; j < SIZE; j++) {
                xil_printf("%d\t", hw_res[(n*ROWS*COLS)+i*SIZE+j]);
                if (hw_res[(n*ROWS*COLS)+i*SIZE+j]!=z[(n*ROWS*COLS)+i*SIZE+j]) { // Checks the results
                    error_flag=1;
                }
            }
            xil_printf("\n\r");
        }
        xil_printf("\n\r");
    }

    if (error_flag) {
        xil_printf("The arrays do NOT match\n\r");
    } else {
        xil_printf("The arrays match\n\r");
    }

    #if !defined(DEBUG)
        printf("\nSW start: %llu\n", tStart_sw);
        printf("SW end:   %llu\n\r", tEnd_sw);
        printf("Multiplication of X & Y in SW took %lld clocks.\n", (tStart_sw - tEnd_sw));
        printf("\nHW start: %llu\n\r", tStart_hw);
        printf("HW end:   %llu\n\r", tEnd_hw);
        printf("Multiplication of X & Y in HW took %lld clock clocks.\n", (tStart_hw - tEnd_hw));
    #else
        // Printing text over serial is clock cycle expensive and introduces additional overhead
        printf("\nMultiplication was run under DEBUG, timer is no longer accurate.\n\r");
    #endif

    cleanup_platform();
    return 0;
}