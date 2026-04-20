#include "xparameters.h"
#include "xil_io.h"
#include "xuartps.h"
#include "sleep.h"

#include "ov5640/OV5640.h"
#include "ov5640/ScuGicInterruptController.h"
#include "ov5640/PS_GPIO.h"
#include "ov5640/AXI_VDMA.h"
#include "ov5640/PS_IIC.h"

#include "MIPI_D_PHY_RX.h"
#include "MIPI_CSI_2_RX.h"


#define IRPT_CTL_DEVID 		XPAR_PS7_SCUGIC_0_DEVICE_ID
#define GPIO_DEVID			XPAR_PS7_GPIO_0_DEVICE_ID
#define GPIO_IRPT_ID		XPAR_PS7_GPIO_0_INTR
#define CAM_I2C_DEVID		XPAR_PS7_I2C_0_DEVICE_ID
#define CAM_I2C_IRPT_ID		XPAR_PS7_I2C_0_INTR
#define VDMA_DEVID			XPAR_AXIVDMA_0_DEVICE_ID
#define VDMA_MM2S_IRPT_ID	XPAR_FABRIC_AXI_VDMA_0_MM2S_INTROUT_INTR
#define VDMA_S2MM_IRPT_ID	XPAR_FABRIC_AXI_VDMA_0_S2MM_INTROUT_INTR
#define CAM_I2C_SCLK_RATE	100000

#define DDR_BASE_ADDR		XPAR_DDR_MEM_BASEADDR
#define MEM_BASE_ADDR		(DDR_BASE_ADDR + 0x0A000000)

#define GAMMA_BASE_ADDR     XPAR_AXI_GAMMACORRECTION_0_BASEADDR

// ============================================================================
// Compositor AXI GPIO registers
// ============================================================================
#define COMP_GPIO_BASE      XPAR_AXI_GPIO_0_BASEADDR   // axi_gpio_0
#define ROI_GPIO_BASE       XPAR_AXI_GPIO_1_BASEADDR   // axi_gpio_1

// Xilinx AXI GPIO register offsets (PG144)
#define GPIO_DATA_OFF       0x00    // Channel 1 data
#define GPIO_TRI_OFF        0x04    // Channel 1 tri-state control
#define GPIO2_DATA_OFF      0x08    // Channel 2 data
#define GPIO2_TRI_OFF       0x0C    // Channel 2 tri-state control

// COMP_GPIO_BASE Channel 1 bit fields:
//   [2:0]   comp_mode (0=full-filt, 1=full-orig, 2=split, 3=wipe, 4=ROI, 5=overlay)
//   [5:3]   filter_sel_a (0=pass, 1=bright, 2=gamma, 3=thresh, 4=invert)
//   [8:6]   filter_sel_b (0=pass, 1=sobel, 2=erosion, 3=dilation)
//   [9]     branch_sel (0=A, 1=B)
//   [10]    auto_demo_en
//   [11]    sw_override (1=software control, 0=buttons)
//   [19:12] edge_thresh
// COMP_GPIO_BASE Channel 2:
//   [10:0]  wipe_pos (0-1919)

// ROI_GPIO_BASE Channel 1:
//   [10:0]  roi_x
//   [26:16] roi_y
// ROI_GPIO_BASE Channel 2:
//   [10:0]  roi_w
//   [26:16] roi_h

// ============================================================================
// Compositor control helpers
// ============================================================================

static uint32_t comp_ctrl_reg = 0;   // shadow of COMP_GPIO Ch1

static void comp_write_ctrl(void) {
	Xil_Out32(COMP_GPIO_BASE + GPIO_DATA_OFF, comp_ctrl_reg);
}

static void set_comp_mode(uint8_t mode) {
	comp_ctrl_reg = (comp_ctrl_reg & ~0x07u) | (mode & 0x07u);
	comp_write_ctrl();
}

static void set_filter_a(uint8_t filt) {
	comp_ctrl_reg = (comp_ctrl_reg & ~(0x07u << 3)) | ((filt & 0x07u) << 3);
	comp_write_ctrl();
}

static void set_filter_b(uint8_t filt) {
	comp_ctrl_reg = (comp_ctrl_reg & ~(0x07u << 6)) | ((filt & 0x07u) << 6);
	comp_write_ctrl();
}

static void set_branch_sel(uint8_t branch) {
	comp_ctrl_reg = (comp_ctrl_reg & ~(1u << 9)) | ((branch & 0x01u) << 9);
	comp_write_ctrl();
}

static void set_auto_demo_en(uint8_t en) {
	comp_ctrl_reg = (comp_ctrl_reg & ~(1u << 10)) | ((en & 0x01u) << 10);
	comp_write_ctrl();
}

static void set_sw_override(uint8_t en) {
	comp_ctrl_reg = (comp_ctrl_reg & ~(1u << 11)) | ((en & 0x01u) << 11);
	comp_write_ctrl();
}

static void set_edge_thresh(uint8_t thresh) {
	comp_ctrl_reg = (comp_ctrl_reg & ~(0xFFu << 12)) | ((uint32_t)thresh << 12);
	comp_write_ctrl();
}

static void set_wipe_pos(uint16_t pos) {
	Xil_Out32(COMP_GPIO_BASE + GPIO2_DATA_OFF, pos & 0x7FFu);
}

static void set_roi(uint16_t x, uint16_t y, uint16_t w, uint16_t h) {
	Xil_Out32(ROI_GPIO_BASE + GPIO_DATA_OFF,
			  (x & 0x7FFu) | (((uint32_t)(y & 0x7FFu)) << 16));
	Xil_Out32(ROI_GPIO_BASE + GPIO2_DATA_OFF,
			  (w & 0x7FFu) | (((uint32_t)(h & 0x7FFu)) << 16));
}

// ============================================================================
// Auto-demo state
// ============================================================================
static int auto_demo_active = 0;
static uint16_t demo_wipe = 0;
static int16_t demo_wipe_dir = 8;
static uint32_t demo_filter_tick = 0;
static uint8_t demo_filter_idx = 0;

#define DEMO_FILTER_CYCLE_TICKS  120  // ~2 sec at 60 Hz update rate

static void auto_demo_step(void) {
	// Sweep wipe position
	demo_wipe += demo_wipe_dir;
	if (demo_wipe >= 1912) {
		demo_wipe = 1912;
		demo_wipe_dir = -8;
	} else if ((int16_t)demo_wipe <= 0) {
		demo_wipe = 0;
		demo_wipe_dir = 8;
	}
	set_wipe_pos(demo_wipe);

	// Cycle filters
	demo_filter_tick++;
	if (demo_filter_tick >= DEMO_FILTER_CYCLE_TICKS) {
		demo_filter_tick = 0;
		demo_filter_idx = (demo_filter_idx + 1) % 7;
		// Filters: 0=pass, 1-4=A filters, 5-7=B filters
		if (demo_filter_idx < 4) {
			set_branch_sel(0);
			set_filter_a(demo_filter_idx + 1); // 1=bright, 2=gamma, 3=thresh, 4=invert
		} else {
			set_branch_sel(1);
			set_filter_b(demo_filter_idx - 3); // 1=sobel, 2=erode, 3=dilate
		}
	}
}

// ============================================================================

using namespace digilent;

void pipeline_mode_change(AXI_VDMA<ScuGicInterruptController>& vdma_driver, OV5640& cam, VideoOutput& vid, Resolution res, OV5640_cfg::mode_t mode)
{
	//Bring up input pipeline back-to-front
	{
		vdma_driver.resetWrite();
		MIPI_CSI_2_RX_mWriteReg(XPAR_MIPI_CSI_2_RX_0_S_AXI_LITE_BASEADDR, CR_OFFSET, (CR_RESET_MASK & ~CR_ENABLE_MASK));
		MIPI_D_PHY_RX_mWriteReg(XPAR_MIPI_D_PHY_RX_0_S_AXI_LITE_BASEADDR, CR_OFFSET, (CR_RESET_MASK & ~CR_ENABLE_MASK));
		cam.reset();
	}

	{
		vdma_driver.configureWrite(timing[static_cast<int>(res)].h_active, timing[static_cast<int>(res)].v_active);
		Xil_Out32(GAMMA_BASE_ADDR, 3); // Set Gamma correction factor to 1/1.8
		//TODO CSI-2, D-PHY config here
		cam.init();
	}

	{
		vdma_driver.enableWrite();
		MIPI_CSI_2_RX_mWriteReg(XPAR_MIPI_CSI_2_RX_0_S_AXI_LITE_BASEADDR, CR_OFFSET, CR_ENABLE_MASK);
		MIPI_D_PHY_RX_mWriteReg(XPAR_MIPI_D_PHY_RX_0_S_AXI_LITE_BASEADDR, CR_OFFSET, CR_ENABLE_MASK);
		cam.set_mode(mode);
		cam.set_awb(OV5640_cfg::awb_t::AWB_ADVANCED);
	}

	//Bring up output pipeline back-to-front
	{
		vid.reset();
		vdma_driver.resetRead();
	}

	{
		vid.configure(res);
		vdma_driver.configureRead(timing[static_cast<int>(res)].h_active, timing[static_cast<int>(res)].v_active);
	}

	{
		vid.enable();
		vdma_driver.enableRead();
	}
}

int main()
{

	ScuGicInterruptController irpt_ctl(IRPT_CTL_DEVID);
	PS_GPIO<ScuGicInterruptController> gpio_driver(GPIO_DEVID, irpt_ctl, GPIO_IRPT_ID);
	PS_IIC<ScuGicInterruptController> iic_driver(CAM_I2C_DEVID, irpt_ctl, CAM_I2C_IRPT_ID, 100000);

	OV5640 cam(iic_driver, gpio_driver);
	AXI_VDMA<ScuGicInterruptController> vdma_driver(VDMA_DEVID, MEM_BASE_ADDR, irpt_ctl,
			VDMA_MM2S_IRPT_ID,
			VDMA_S2MM_IRPT_ID);
	VideoOutput vid(XPAR_VTC_0_DEVICE_ID, XPAR_VIDEO_DYNCLK_DEVICE_ID);

	pipeline_mode_change(vdma_driver, cam, vid, Resolution::R1920_1080_60_PP, OV5640_cfg::mode_t::MODE_1080P_1920_1080_30fps);

	// Initialise compositor GPIO tri-state: all outputs (0 = output for PS→PL)
	Xil_Out32(COMP_GPIO_BASE + GPIO_TRI_OFF, 0x00000000);
	Xil_Out32(COMP_GPIO_BASE + GPIO2_TRI_OFF, 0x00000000);
	Xil_Out32(ROI_GPIO_BASE + GPIO_TRI_OFF, 0x00000000);
	Xil_Out32(ROI_GPIO_BASE + GPIO2_TRI_OFF, 0x00000000);

	// Set sensible defaults
	set_comp_mode(0);          // full-screen filtered
	set_filter_a(0);           // passthrough
	set_filter_b(0);           // passthrough
	set_branch_sel(0);         // path A
	set_sw_override(0);        // buttons control by default
	set_edge_thresh(64);       // moderate edge threshold
	set_wipe_pos(960);         // midpoint
	set_roi(640, 270, 640, 540); // centred box

	xil_printf("Video init done.\r\n");


	// Liquid lens control
	uint8_t read_char0 = 0;
	uint8_t read_char1 = 0;
	uint8_t read_char2 = 0;
	uint8_t read_char4 = 0;
	uint8_t read_char5 = 0;
	uint16_t reg_addr;
	uint8_t reg_value;

	while (1) {

		// Auto-demo tick (non-blocking)
		if (auto_demo_active) {
			auto_demo_step();
			usleep(16000); // ~60 Hz
			// Check for keypress to exit demo
			// (non-blocking check not available on bare-metal xil_printf,
			//  so demo runs until next menu cycle when user presses any key)
		}

		xil_printf("\r\n\r\n\r\nPcam 5C MAIN OPTIONS\r\n");
		xil_printf("\r\nPlease press the key corresponding to the desired option:");
		xil_printf("\r\n  a. Change Resolution");
		xil_printf("\r\n  b. Change Liquid Lens Focus");
		xil_printf("\r\n  d. Change Image Format (Raw or RGB)");
		xil_printf("\r\n  e. Write a Register Inside the Image Sensor");
		xil_printf("\r\n  f. Read a Register Inside the Image Sensor");
		xil_printf("\r\n  g. Change Gamma Correction Factor Value");
		xil_printf("\r\n  h. Change AWB Settings");
		xil_printf("\r\n  --- Compositor Controls ---");
		xil_printf("\r\n  i. Set Compositor Mode");
		xil_printf("\r\n  j. Set Wipe Position");
		xil_printf("\r\n  k. Set ROI Box");
		xil_printf("\r\n  l. Select Filter (software override)");
		xil_printf("\r\n  m. Toggle Auto-Demo");
		xil_printf("\r\n  n. Set Edge Overlay Threshold\r\n\r\n");

		read_char0 = getchar();
		getchar();
		xil_printf("Read: %d\r\n", read_char0);

		switch(read_char0) {

		case 'a':
			xil_printf("\r\n  Please press the key corresponding to the desired resolution:");
			xil_printf("\r\n    1. 1280 x 720, 60fps");
			xil_printf("\r\n    2. 1920 x 1080, 15fps");
			xil_printf("\r\n    3. 1920 x 1080, 30fps");
			read_char1 = getchar();
			getchar();
			xil_printf("\r\nRead: %d", read_char1);
			switch(read_char1) {
			case '1':
				pipeline_mode_change(vdma_driver, cam, vid, Resolution::R1280_720_60_PP, OV5640_cfg::mode_t::MODE_720P_1280_720_60fps);
				xil_printf("Resolution change done.\r\n");
				break;
			case '2':
				pipeline_mode_change(vdma_driver, cam, vid, Resolution::R1920_1080_60_PP, OV5640_cfg::mode_t::MODE_1080P_1920_1080_15fps);
				xil_printf("Resolution change done.\r\n");
				break;
			case '3':
				pipeline_mode_change(vdma_driver, cam, vid, Resolution::R1920_1080_60_PP, OV5640_cfg::mode_t::MODE_1080P_1920_1080_30fps);
				xil_printf("Resolution change done.\r\n");
				break;
			default:
				xil_printf("\r\n  Selection is outside the available options! Please retry...");
			}
			break;

		case 'b':
			xil_printf("\r\n\r\nPlease enter value of liquid lens register, in hex, with small letters: 0x");
			//A, B, C,..., F need to be entered with small letters
			while (read_char1 < 48) {
				read_char1 = getchar();
			}
			while (read_char2 < 48) {
				read_char2 = getchar();
			}
			getchar();
			// If character is a digit, convert from ASCII code to a digit between 0 and 9
			if (read_char1 <= 57) {
				read_char1 -= 48;
			}
			// If character is a letter, convert ASCII code to a number between 10 and 15
			else {
				read_char1 -= 87;
			}
			// If character is a digit, convert from ASCII code to a digit between 0 and 9
			if (read_char2 <= 57) {
				read_char2 -= 48;
			}
			// If character is a letter, convert ASCII code to a number between 10 and 15
			else {
				read_char2 -= 87;
			}
			cam.writeRegLiquid((uint8_t) (16*read_char1 + read_char2));
			xil_printf("\r\nWrote to liquid lens controller: %x", (uint8_t) (16*read_char1 + read_char2));
			break;

		case 'd':
			xil_printf("\r\n  Please press the key corresponding to the desired setting:");
			xil_printf("\r\n    1. Select image format to be RGB, output still Raw");
			xil_printf("\r\n    2. Select image format & output to both be Raw");
			read_char1 = getchar();
			getchar();
			xil_printf("\r\nRead: %d", read_char1);
			switch(read_char1) {
			case '1':
				cam.set_isp_format(OV5640_cfg::isp_format_t::ISP_RGB);
				xil_printf("Settings change done.\r\n");
				break;
			case '2':
				cam.set_isp_format(OV5640_cfg::isp_format_t::ISP_RAW);
				xil_printf("Settings change done.\r\n");
				break;
			default:
				xil_printf("\r\n  Selection is outside the available options! Please retry...");
			}
			break;

		case 'e':
			xil_printf("\r\nPlease enter address of image sensor register, in hex, with small letters: \r\n");
			//A, B, C,..., F need to be entered with small letters
			while (read_char1 < 48) {
				read_char1 = getchar();
			}
			while (read_char2 < 48) {
				read_char2 = getchar();
			}
			while (read_char4 < 48) {
				read_char4 = getchar();
			}
			while (read_char5 < 48) {
				read_char5 = getchar();
			}
			getchar();
			// If character is a digit, convert from ASCII code to a digit between 0 and 9
			if (read_char1 <= 57) {
				read_char1 -= 48;
			}
			// If character is a letter, convert ASCII code to a number between 10 and 15
			else {
				read_char1 -= 87;
			}
			// If character is a digit, convert from ASCII code to a digit between 0 and 9
			if (read_char2 <= 57) {
				read_char2 -= 48;
			}
			// If character is a letter, convert ASCII code to a number between 10 and 15
			else {
				read_char2 -= 87;
			}
			// If character is a digit, convert from ASCII code to a digit between 0 and 9
			if (read_char4 <= 57) {
				read_char4 -= 48;
			}
			// If character is a letter, convert ASCII code to a number between 10 and 15
			else {
				read_char4 -= 87;
			}
			// If character is a digit, convert from ASCII code to a digit between 0 and 9
			if (read_char5 <= 57) {
				read_char5 -= 48;
			}
			// If character is a letter, convert ASCII code to a number between 10 and 15
			else {
				read_char5 -= 87;
			}
			reg_addr = 16*(16*(16*read_char1 + read_char2)+read_char4)+read_char5;
			xil_printf("Desired Register Address: %x\r\n", reg_addr);

			read_char1 = 0;
			read_char2 = 0;
			xil_printf("\r\nPlease enter value of image sensor register, in hex, with small letters: \r\n");
			//A, B, C,..., F need to be entered with small letters
			while (read_char1 < 48) {
				read_char1 = getchar();
			}
			while (read_char2 < 48) {
				read_char2 = getchar();
			}
			getchar();
			// If character is a digit, convert from ASCII code to a digit between 0 and 9
			if (read_char1 <= 57) {
				read_char1 -= 48;
			}
			// If character is a letter, convert ASCII code to a number between 10 and 15
			else {
				read_char1 -= 87;
			}
			// If character is a digit, convert from ASCII code to a digit between 0 and 9
			if (read_char2 <= 57) {
				read_char2 -= 48;
			}
			// If character is a letter, convert ASCII code to a number between 10 and 15
			else {
				read_char2 -= 87;
			}
			reg_value = 16*read_char1 + read_char2;
			xil_printf("Desired Register Value: %x\r\n", reg_value);
			cam.writeReg(reg_addr, reg_value);
			xil_printf("Register write done.\r\n");

			break;

		case 'f':
			xil_printf("Please enter address of image sensor register, in hex, with small letters: \r\n");
			//A, B, C,..., F need to be entered with small letters
			while (read_char1 < 48) {
				read_char1 = getchar();
			}
			while (read_char2 < 48) {
				read_char2 = getchar();
			}
			while (read_char4 < 48) {
				read_char4 = getchar();
			}
			while (read_char5 < 48) {
				read_char5 = getchar();
			}
			getchar();
			// If character is a digit, convert from ASCII code to a digit between 0 and 9
			if (read_char1 <= 57) {
				read_char1 -= 48;
			}
			// If character is a letter, convert ASCII code to a number between 10 and 15
			else {
				read_char1 -= 87;
			}
			// If character is a digit, convert from ASCII code to a digit between 0 and 9
			if (read_char2 <= 57) {
				read_char2 -= 48;
			}
			// If character is a letter, convert ASCII code to a number between 10 and 15
			else {
				read_char2 -= 87;
			}
			// If character is a digit, convert from ASCII code to a digit between 0 and 9
			if (read_char4 <= 57) {
				read_char4 -= 48;
			}
			// If character is a letter, convert ASCII code to a number between 10 and 15
			else {
				read_char4 -= 87;
			}
			// If character is a digit, convert from ASCII code to a digit between 0 and 9
			if (read_char5 <= 57) {
				read_char5 -= 48;
			}
			// If character is a letter, convert ASCII code to a number between 10 and 15
			else {
				read_char5 -= 87;
			}
			reg_addr = 16*(16*(16*read_char1 + read_char2)+read_char4)+read_char5;
			xil_printf("Desired Register Address: %x\r\n", reg_addr);

			cam.readReg(reg_addr, reg_value);
			xil_printf("Value of Desired Register: %x\r\n", reg_value);

			break;

		case 'g':
			xil_printf("  Please press the key corresponding to the desired Gamma factor:\r\n");
			xil_printf("    1. Gamma Factor = 1\r\n");
			xil_printf("    2. Gamma Factor = 1/1.2\r\n");
			xil_printf("    3. Gamma Factor = 1/1.5\r\n");
			xil_printf("    4. Gamma Factor = 1/1.8\r\n");
			xil_printf("    5. Gamma Factor = 1/2.2\r\n");
			read_char1 = getchar();
			getchar();
			xil_printf("Read: %d\r\n", read_char1);
			// Convert from ASCII to numeric
			read_char1 = read_char1 - 48;
			if ((read_char1 > 0) && (read_char1 < 6)) {
				Xil_Out32(GAMMA_BASE_ADDR, read_char1-1);
				xil_printf("Gamma value changed to 1.\r\n");
			}
			else {
				xil_printf("  Selection is outside the available options! Please retry...\r\n");
			}
			break;

		case 'h':
			xil_printf("  Please press the key corresponding to the desired AWB change:\r\n");
			xil_printf("    1. Enable Advanced AWB\r\n");
			xil_printf("    2. Enable Simple AWB\r\n");
			xil_printf("    3. Disable AWB\r\n");
			read_char1 = getchar();
			getchar();
			xil_printf("Read: %d\r\n", read_char1);
			switch(read_char1) {
			case '1':
				cam.set_awb(OV5640_cfg::awb_t::AWB_ADVANCED);
				xil_printf("Enabled Advanced AWB\r\n");
				break;
			case '2':
				cam.set_awb(OV5640_cfg::awb_t::AWB_SIMPLE);
				xil_printf("Enabled Simple AWB\r\n");
				break;
			case '3':
				cam.set_awb(OV5640_cfg::awb_t::AWB_DISABLED);
				xil_printf("Disabled AWB\r\n");
				break;
			default:
				xil_printf("  Selection is outside the available options! Please retry...\r\n");
			}
			break;

		// ==================================================================
		// Compositor Controls
		// ==================================================================

		case 'i': // Compositor mode
			xil_printf("  Select compositor mode:\r\n");
			xil_printf("    0. Full-screen filtered\r\n");
			xil_printf("    1. Full-screen original\r\n");
			xil_printf("    2. Split-screen (original | filtered)\r\n");
			xil_printf("    3. Wipe (original | filtered, movable)\r\n");
			xil_printf("    4. ROI spotlight\r\n");
			xil_printf("    5. Edge overlay (comic mode)\r\n");
			read_char1 = getchar();
			getchar();
			read_char1 -= 48;
			if (read_char1 <= 5) {
				set_sw_override(1);
				set_comp_mode(read_char1);
				xil_printf("Compositor mode set to %d\r\n", read_char1);
			} else {
				xil_printf("  Invalid selection!\r\n");
			}
			break;

		case 'j': // Wipe position
			xil_printf("  Enter wipe position (0-1919):\r\n");
			xil_printf("    1. Left quarter (480)\r\n");
			xil_printf("    2. Centre (960)\r\n");
			xil_printf("    3. Right quarter (1440)\r\n");
			read_char1 = getchar();
			getchar();
			switch(read_char1) {
			case '1':
				set_wipe_pos(480);
				xil_printf("Wipe pos = 480\r\n");
				break;
			case '2':
				set_wipe_pos(960);
				xil_printf("Wipe pos = 960\r\n");
				break;
			case '3':
				set_wipe_pos(1440);
				xil_printf("Wipe pos = 1440\r\n");
				break;
			default:
				xil_printf("  Invalid selection!\r\n");
			}
			break;

		case 'k': // ROI box
			xil_printf("  Select ROI preset:\r\n");
			xil_printf("    1. Centre 640x480\r\n");
			xil_printf("    2. Centre 320x240\r\n");
			xil_printf("    3. Top-left quarter\r\n");
			xil_printf("    4. Full-screen (960x540 centred)\r\n");
			read_char1 = getchar();
			getchar();
			switch(read_char1) {
			case '1':
				set_roi(640, 300, 640, 480);
				xil_printf("ROI: 640x480 centred\r\n");
				break;
			case '2':
				set_roi(800, 420, 320, 240);
				xil_printf("ROI: 320x240 centred\r\n");
				break;
			case '3':
				set_roi(0, 0, 960, 540);
				xil_printf("ROI: top-left quarter\r\n");
				break;
			case '4':
				set_roi(480, 270, 960, 540);
				xil_printf("ROI: 960x540 centred\r\n");
				break;
			default:
				xil_printf("  Invalid selection!\r\n");
			}
			break;

		case 'l': // Filter select (software override)
			xil_printf("  Select branch and filter:\r\n");
			xil_printf("    Branch A (single-pixel):\r\n");
			xil_printf("      1. Brightness/Contrast\r\n");
			xil_printf("      2. Gamma (darken)\r\n");
			xil_printf("      3. Binary Threshold\r\n");
			xil_printf("      4. Invert\r\n");
			xil_printf("    Branch B (multi-pixel):\r\n");
			xil_printf("      5. Sobel Edge Detect\r\n");
			xil_printf("      6. Erosion\r\n");
			xil_printf("      7. Dilation\r\n");
			xil_printf("      0. Passthrough (no filter)\r\n");
			read_char1 = getchar();
			getchar();
			read_char1 -= 48;
			set_sw_override(1);
			if (read_char1 == 0) {
				set_filter_a(0);
				set_filter_b(0);
				xil_printf("Passthrough (no filter)\r\n");
			} else if (read_char1 >= 1 && read_char1 <= 4) {
				set_branch_sel(0);
				set_filter_a(read_char1);
				xil_printf("Branch A, filter %d\r\n", read_char1);
			} else if (read_char1 >= 5 && read_char1 <= 7) {
				set_branch_sel(1);
				set_filter_b(read_char1 - 4);
				xil_printf("Branch B, filter %d\r\n", read_char1 - 4);
			} else {
				xil_printf("  Invalid selection!\r\n");
			}
			break;

		case 'm': // Auto-demo toggle
			auto_demo_active = !auto_demo_active;
			if (auto_demo_active) {
				set_sw_override(1);
				set_comp_mode(3); // wipe mode
				demo_wipe = 0;
				demo_wipe_dir = 8;
				demo_filter_tick = 0;
				demo_filter_idx = 0;
				set_auto_demo_en(1);
				xil_printf("Auto-demo STARTED. Press any key to return to menu.\r\n");
				// Run demo loop until keypress
				while (auto_demo_active) {
					auto_demo_step();
					usleep(16000);
					// Check for UART input (polling)
					if (XUartPs_IsReceiveData(STDIN_BASEADDRESS)) {
						getchar(); // consume the char
						auto_demo_active = 0;
					}
				}
				set_auto_demo_en(0);
				xil_printf("Auto-demo STOPPED.\r\n");
			} else {
				set_auto_demo_en(0);
				xil_printf("Auto-demo STOPPED.\r\n");
			}
			break;

		case 'n': // Edge threshold
			xil_printf("  Select edge overlay threshold:\r\n");
			xil_printf("    1. Low (32) - many edges\r\n");
			xil_printf("    2. Medium (64)\r\n");
			xil_printf("    3. High (128) - fewer edges\r\n");
			xil_printf("    4. Very high (192) - strong edges only\r\n");
			read_char1 = getchar();
			getchar();
			switch(read_char1) {
			case '1':
				set_edge_thresh(32);
				xil_printf("Edge threshold = 32\r\n");
				break;
			case '2':
				set_edge_thresh(64);
				xil_printf("Edge threshold = 64\r\n");
				break;
			case '3':
				set_edge_thresh(128);
				xil_printf("Edge threshold = 128\r\n");
				break;
			case '4':
				set_edge_thresh(192);
				xil_printf("Edge threshold = 192\r\n");
				break;
			default:
				xil_printf("  Invalid selection!\r\n");
			}
			break;

		default:
			xil_printf("  Selection is outside the available options! Please retry...\r\n");
		}

		read_char1 = 0;
		read_char2 = 0;
		read_char4 = 0;
		read_char5 = 0;
	}

	return 0;
}
