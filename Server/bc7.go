package main

import (
	"image"
	"image/color"
)

// BC7 block-compression decoder (DXGI formats 98/99: BC7_UNORM / BC7_UNORM_SRGB)
// Reference: https://learn.microsoft.com/en-us/windows/win32/direct3d11/bc7-format

// ---------------------------------------------------------------------------
// Partition tables (from DirectXTex / D3D11 spec)
// ---------------------------------------------------------------------------

// bc7Part2[shape][pixel] — subset index (0 or 1) for 2-subset partitions
var bc7Part2 = [64][16]uint8{
	{0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1},
	{0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1},
	{0, 1, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1},
	{0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 1, 1, 1},
	{0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 1},
	{0, 0, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1},
	{0, 0, 0, 1, 0, 0, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1},
	{0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 0, 1, 1, 1},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1},
	{0, 0, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1},
	{0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 1, 1, 1, 1, 1, 1},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 1, 1},
	{0, 0, 0, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1},
	{0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1},
	{0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1},
	{0, 0, 0, 0, 1, 0, 0, 0, 1, 1, 1, 0, 1, 1, 1, 1},
	{0, 1, 1, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 1, 1, 0},
	{0, 1, 1, 1, 0, 0, 1, 1, 0, 0, 0, 1, 0, 0, 0, 0},
	{0, 0, 1, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 1, 0, 0, 0, 1, 1, 0, 0, 1, 1, 1, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 1, 0, 0},
	{0, 1, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 0, 1},
	{0, 0, 1, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0},
	{0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 1, 0, 0},
	{0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0},
	{0, 0, 1, 1, 0, 1, 1, 0, 0, 1, 1, 0, 1, 1, 0, 0},
	{0, 0, 0, 1, 0, 1, 1, 1, 1, 1, 1, 0, 1, 0, 0, 0},
	{0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0},
	{0, 1, 1, 1, 0, 0, 0, 1, 1, 0, 0, 0, 1, 1, 1, 0},
	{0, 0, 1, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 1, 0, 0},
	{0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1},
	{0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1},
	{0, 1, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1, 1, 0, 1, 0},
	{0, 0, 1, 1, 0, 0, 1, 1, 1, 1, 0, 0, 1, 1, 0, 0},
	{0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0},
	{0, 1, 0, 1, 0, 1, 0, 1, 1, 0, 1, 0, 1, 0, 1, 0},
	{0, 1, 1, 0, 1, 0, 0, 1, 0, 1, 1, 0, 1, 0, 0, 1},
	{0, 1, 0, 1, 1, 0, 1, 0, 1, 0, 1, 0, 0, 1, 0, 1},
	{0, 1, 1, 1, 0, 0, 1, 1, 1, 1, 0, 0, 1, 1, 1, 0},
	{0, 0, 0, 1, 0, 0, 1, 1, 1, 1, 0, 0, 1, 0, 0, 0},
	{0, 0, 1, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 1, 0, 0},
	{0, 0, 1, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1, 1, 0, 0},
	{0, 1, 1, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0, 1, 1, 0},
	{0, 0, 1, 1, 1, 1, 0, 0, 1, 1, 0, 0, 0, 0, 1, 1},
	{0, 1, 1, 0, 0, 1, 1, 0, 1, 0, 0, 1, 1, 0, 0, 1},
	{0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 0, 0, 0},
	{0, 1, 0, 0, 1, 1, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0},
	{0, 0, 1, 0, 0, 1, 1, 1, 0, 0, 1, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 1, 0, 0, 1, 0},
	{0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 1, 0, 0, 1, 0, 0},
	{0, 1, 1, 0, 1, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 1},
	{0, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 0, 1, 0, 0, 1},
	{0, 1, 1, 0, 0, 0, 1, 1, 1, 0, 0, 1, 1, 1, 0, 0},
	{0, 0, 1, 1, 1, 0, 0, 1, 1, 1, 0, 0, 0, 1, 1, 0},
	{0, 1, 1, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 0, 0, 1},
	{0, 1, 1, 0, 0, 0, 1, 1, 0, 0, 1, 1, 1, 0, 0, 1},
	{0, 1, 1, 1, 1, 1, 1, 0, 1, 0, 0, 0, 0, 0, 0, 1},
	{0, 0, 0, 1, 1, 0, 0, 0, 1, 1, 1, 0, 0, 1, 1, 1},
	{0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1},
	{0, 0, 1, 1, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0},
	{0, 0, 1, 0, 0, 0, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0},
	{0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 1, 1, 0, 1, 1, 1},
}

// bc7Part3[shape][pixel] — subset index (0, 1, or 2) for 3-subset partitions
var bc7Part3 = [64][16]uint8{
	{0, 0, 1, 1, 0, 0, 1, 1, 0, 2, 2, 1, 2, 2, 2, 2},
	{0, 0, 0, 1, 0, 0, 1, 1, 2, 2, 1, 1, 2, 2, 2, 1},
	{0, 0, 0, 0, 2, 0, 0, 1, 2, 2, 1, 1, 2, 2, 1, 1},
	{0, 2, 2, 2, 0, 0, 2, 2, 0, 0, 1, 1, 0, 1, 1, 1},
	{0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 1, 1, 2, 2},
	{0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 2, 2, 0, 0, 2, 2},
	{0, 0, 2, 2, 0, 0, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1},
	{0, 0, 1, 1, 0, 0, 1, 1, 2, 2, 1, 1, 2, 2, 1, 1},
	{0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2},
	{0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2},
	{0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2},
	{0, 0, 1, 2, 0, 0, 1, 2, 0, 0, 1, 2, 0, 0, 1, 2},
	{0, 1, 1, 2, 0, 1, 1, 2, 0, 1, 1, 2, 0, 1, 1, 2},
	{0, 1, 2, 2, 0, 1, 2, 2, 0, 1, 2, 2, 0, 1, 2, 2},
	{0, 0, 1, 1, 0, 1, 1, 2, 1, 1, 2, 2, 1, 2, 2, 2},
	{0, 0, 1, 1, 2, 0, 0, 1, 2, 2, 0, 0, 2, 2, 2, 0},
	{0, 0, 0, 1, 0, 0, 1, 1, 0, 1, 1, 2, 1, 1, 2, 2},
	{0, 1, 1, 1, 0, 0, 1, 1, 2, 0, 0, 1, 2, 2, 0, 0},
	{0, 0, 0, 0, 1, 1, 2, 2, 1, 1, 2, 2, 1, 1, 2, 2},
	{0, 0, 2, 2, 0, 0, 2, 2, 0, 0, 2, 2, 1, 1, 1, 1},
	{0, 1, 1, 1, 0, 1, 1, 1, 0, 2, 2, 2, 0, 2, 2, 2},
	{0, 0, 0, 1, 0, 0, 0, 1, 2, 2, 2, 1, 2, 2, 2, 1},
	{0, 0, 0, 0, 0, 0, 1, 1, 0, 1, 2, 2, 0, 1, 2, 2},
	{0, 0, 0, 0, 1, 1, 0, 0, 2, 2, 1, 0, 2, 2, 1, 0},
	{0, 1, 2, 2, 0, 1, 2, 2, 0, 0, 1, 1, 0, 0, 0, 0},
	{0, 0, 1, 2, 0, 0, 1, 2, 1, 1, 2, 2, 2, 2, 2, 2},
	{0, 1, 1, 0, 1, 2, 2, 1, 1, 2, 2, 1, 0, 1, 1, 0},
	{0, 0, 0, 0, 0, 1, 1, 0, 1, 2, 2, 1, 1, 2, 2, 1},
	{0, 0, 2, 2, 1, 1, 0, 2, 1, 1, 0, 2, 0, 0, 2, 2},
	{0, 1, 1, 0, 0, 1, 1, 0, 2, 0, 0, 2, 2, 2, 2, 2},
	{0, 0, 1, 1, 0, 1, 2, 2, 0, 1, 2, 2, 0, 0, 1, 1},
	{0, 0, 0, 0, 2, 0, 0, 0, 2, 2, 1, 1, 2, 2, 2, 1},
	{0, 0, 0, 0, 0, 0, 0, 2, 1, 1, 2, 2, 1, 2, 2, 2},
	{0, 2, 2, 2, 0, 0, 2, 2, 0, 0, 1, 2, 0, 0, 1, 1},
	{0, 0, 1, 1, 0, 0, 1, 2, 0, 0, 2, 2, 0, 2, 2, 2},
	{0, 1, 2, 0, 0, 1, 2, 0, 0, 1, 2, 0, 0, 1, 2, 0},
	{0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 0, 0, 0, 0},
	{0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2, 0},
	{0, 1, 2, 0, 2, 0, 1, 2, 1, 2, 0, 1, 0, 1, 2, 0},
	{0, 0, 1, 1, 2, 2, 0, 0, 1, 1, 2, 2, 0, 0, 1, 1},
	{0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 0, 0, 0, 0, 1, 1},
	{0, 1, 0, 1, 0, 1, 0, 1, 2, 2, 2, 2, 2, 2, 2, 2},
	{0, 0, 0, 0, 0, 0, 0, 0, 2, 1, 2, 1, 2, 1, 2, 1},
	{0, 0, 2, 2, 1, 1, 2, 2, 0, 0, 2, 2, 1, 1, 2, 2},
	{0, 0, 2, 2, 0, 0, 1, 1, 0, 0, 2, 2, 0, 0, 1, 1},
	{0, 2, 2, 0, 1, 2, 2, 1, 0, 2, 2, 0, 1, 2, 2, 1},
	{0, 1, 0, 1, 2, 2, 2, 2, 2, 2, 2, 2, 0, 1, 0, 1},
	{0, 0, 0, 0, 2, 1, 2, 1, 2, 1, 2, 1, 2, 1, 2, 1},
	{0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 2, 2, 2, 2},
	{0, 2, 2, 2, 0, 1, 1, 1, 0, 2, 2, 2, 0, 1, 1, 1},
	{0, 0, 0, 2, 1, 1, 1, 2, 0, 0, 0, 2, 1, 1, 1, 2},
	{0, 0, 0, 0, 2, 1, 1, 2, 2, 1, 1, 2, 2, 1, 1, 2},
	{0, 2, 2, 2, 0, 1, 1, 1, 0, 1, 1, 1, 0, 2, 2, 2},
	{0, 0, 0, 2, 1, 1, 1, 2, 1, 1, 1, 2, 0, 0, 0, 2},
	{0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 2, 2, 2, 2},
	{0, 0, 0, 0, 0, 0, 0, 0, 2, 1, 1, 2, 2, 1, 1, 2},
	{0, 1, 1, 0, 0, 1, 1, 0, 2, 2, 2, 2, 2, 2, 2, 2},
	{0, 0, 2, 2, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 2, 2},
	{0, 0, 2, 2, 1, 1, 2, 2, 1, 1, 2, 2, 0, 0, 2, 2},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 1, 1, 2},
	{0, 0, 0, 2, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 1},
	{0, 2, 2, 2, 1, 2, 2, 2, 0, 2, 2, 2, 1, 2, 2, 2},
	{0, 1, 0, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2},
	{0, 1, 1, 1, 2, 0, 1, 1, 2, 2, 0, 1, 2, 2, 2, 0},
}

// bc7Fix2[shape] — fixup pixel for subset 1 in 2-subset partitions (subset 0 fixup is always 0)
var bc7Fix2 = [64]uint8{
	15, 15, 15, 15, 15, 15, 15, 15,
	15, 15, 15, 15, 15, 15, 15, 15,
	15, 2, 8, 2, 2, 8, 8, 15,
	2, 8, 2, 2, 8, 8, 2, 2,
	15, 15, 6, 8, 2, 8, 15, 15,
	2, 8, 2, 2, 2, 15, 15, 6,
	6, 2, 6, 8, 15, 15, 2, 2,
	15, 15, 15, 15, 15, 2, 2, 15,
}

// bc7Fix3[shape][2] — fixup pixels for subsets 1 and 2 in 3-subset partitions
var bc7Fix3 = [64][2]uint8{
	{3, 15}, {3, 8}, {15, 8}, {15, 3}, {8, 15}, {3, 15}, {15, 3}, {15, 8},
	{8, 15}, {8, 15}, {6, 15}, {6, 15}, {6, 15}, {5, 15}, {3, 15}, {3, 8},
	{3, 15}, {3, 8}, {8, 15}, {15, 3}, {3, 15}, {3, 8}, {6, 15}, {10, 8},
	{5, 3}, {8, 15}, {8, 6}, {6, 10}, {8, 15}, {5, 15}, {15, 10}, {15, 8},
	{8, 15}, {15, 3}, {3, 15}, {5, 10}, {6, 10}, {10, 8}, {8, 9}, {15, 10},
	{15, 6}, {3, 15}, {15, 8}, {5, 15}, {15, 3}, {15, 6}, {15, 6}, {15, 8},
	{3, 15}, {15, 3}, {5, 15}, {5, 15}, {5, 15}, {8, 15}, {5, 15}, {10, 15},
	{5, 15}, {10, 15}, {8, 15}, {13, 15}, {15, 3}, {12, 15}, {3, 15}, {3, 8},
}

// ---------------------------------------------------------------------------
// Interpolation weight tables
// ---------------------------------------------------------------------------

var bc7W2 = [4]uint32{0, 21, 43, 64}
var bc7W3 = [8]uint32{0, 9, 18, 27, 37, 46, 55, 64}
var bc7W4 = [16]uint32{0, 4, 9, 13, 17, 21, 26, 30, 34, 38, 43, 47, 51, 55, 60, 64}

// ---------------------------------------------------------------------------
// Mode table
// ---------------------------------------------------------------------------

type bc7ModeInfo struct {
	ns, pb, rb, isb, cb, ab, epb, spb, ib, ib2 int
}

var bc7Modes = [8]bc7ModeInfo{
	{3, 4, 0, 0, 4, 0, 1, 0, 3, 0}, // mode 0: 3 subsets, RGBA only color (no alpha), P-bit per endpoint
	{2, 6, 0, 0, 6, 0, 0, 1, 3, 0}, // mode 1: 2 subsets, shared P-bit per subset
	{3, 6, 0, 0, 5, 0, 0, 0, 2, 0}, // mode 2: 3 subsets, no P-bits
	{2, 6, 0, 0, 7, 0, 1, 0, 2, 0}, // mode 3: 2 subsets, P-bit per endpoint
	{1, 0, 2, 1, 5, 6, 0, 0, 2, 3}, // mode 4: 1 subset, rotation + index-sel, dual index
	{1, 0, 2, 0, 7, 8, 0, 0, 2, 2}, // mode 5: 1 subset, rotation, dual index
	{1, 0, 0, 0, 7, 7, 1, 0, 4, 0}, // mode 6: 1 subset, P-bit per endpoint, 4-bit index
	{2, 6, 0, 0, 5, 5, 1, 0, 2, 0}, // mode 7: 2 subsets, RGBA, P-bit per endpoint
}

// ---------------------------------------------------------------------------
// Helper functions
// ---------------------------------------------------------------------------

// bc7Expand expands v from 'bits' bits to 8 bits by bit replication
func bc7Expand(v uint8, bits int) uint8 {
	if bits <= 0 {
		return 0
	}
	if bits >= 8 {
		return v
	}
	return uint8((uint32(v) << uint(8-bits)) | (uint32(v) >> uint(2*bits-8)))
}

// bc7Lerp interpolates between e0 and e1 using a wBits-bit weight index w
func bc7Lerp(e0, e1 uint8, w uint32, wBits int) uint8 {
	var wt uint32
	switch wBits {
	case 2:
		wt = bc7W2[w&3]
	case 3:
		wt = bc7W3[w&7]
	case 4:
		wt = bc7W4[w&15]
	default:
		return e0
	}
	return uint8((uint32(e0)*(64-wt) + uint32(e1)*wt + 32) >> 6)
}

// bc7BR is a LSB-first bit reader over a 16-byte BC7 block
type bc7BR struct {
	data [16]byte
	pos  uint
}

func (r *bc7BR) read(n uint) uint32 {
	var result uint32
	for i := uint(0); i < n; i++ {
		byteIdx := (r.pos + i) / 8
		bitIdx := (r.pos + i) % 8
		if byteIdx < 16 && (r.data[byteIdx]>>bitIdx)&1 != 0 {
			result |= 1 << i
		}
	}
	r.pos += n
	return result
}

// ---------------------------------------------------------------------------
// Block decoder
// ---------------------------------------------------------------------------

func writeBC7Block(block []byte, img *image.RGBA, bx, by, imgW, imgH int) {
	var br bc7BR
	copy(br.data[:], block[:16])

	// Mode: position of first set bit in bits 0..7
	mode := -1
	for i := 0; i < 8; i++ {
		if br.read(1) != 0 {
			mode = i
			break
		}
	}
	if mode < 0 {
		return
	}

	m := bc7Modes[mode]
	numEP := m.ns * 2

	// Partition, rotation, index selection
	partIdx := 0
	rotation := 0
	idxSel := 0
	if m.pb > 0 {
		partIdx = int(br.read(uint(m.pb)))
	}
	if m.rb > 0 {
		rotation = int(br.read(uint(m.rb)))
	}
	if m.isb > 0 {
		idxSel = int(br.read(uint(m.isb)))
	}

	// Color endpoints (R, G, B interleaved by component across all endpoints)
	var epR, epG, epB [6]uint8
	for i := 0; i < numEP; i++ {
		epR[i] = uint8(br.read(uint(m.cb)))
	}
	for i := 0; i < numEP; i++ {
		epG[i] = uint8(br.read(uint(m.cb)))
	}
	for i := 0; i < numEP; i++ {
		epB[i] = uint8(br.read(uint(m.cb)))
	}

	// Alpha endpoints
	var epA [6]uint8
	if m.ab > 0 {
		for i := 0; i < numEP; i++ {
			epA[i] = uint8(br.read(uint(m.ab)))
		}
	}

	// P-bits
	cbFull := m.cb
	abFull := m.ab
	if m.epb > 0 {
		// one P-bit per endpoint
		var pb [6]uint8
		for i := 0; i < numEP; i++ {
			pb[i] = uint8(br.read(1))
		}
		for i := 0; i < numEP; i++ {
			epR[i] = (epR[i] << 1) | pb[i]
			epG[i] = (epG[i] << 1) | pb[i]
			epB[i] = (epB[i] << 1) | pb[i]
			if m.ab > 0 {
				epA[i] = (epA[i] << 1) | pb[i]
			}
		}
		cbFull = m.cb + 1
		if m.ab > 0 {
			abFull = m.ab + 1
		}
	} else if m.spb > 0 {
		// one shared P-bit per subset
		var pb [3]uint8
		for s := 0; s < m.ns; s++ {
			pb[s] = uint8(br.read(1))
		}
		for i := 0; i < numEP; i++ {
			s := i / 2
			epR[i] = (epR[i] << 1) | pb[s]
			epG[i] = (epG[i] << 1) | pb[s]
			epB[i] = (epB[i] << 1) | pb[s]
		}
		cbFull = m.cb + 1
	}

	// Expand endpoints to 8 bits
	for i := 0; i < numEP; i++ {
		epR[i] = bc7Expand(epR[i], cbFull)
		epG[i] = bc7Expand(epG[i], cbFull)
		epB[i] = bc7Expand(epB[i], cbFull)
		if m.ab > 0 {
			epA[i] = bc7Expand(epA[i], abFull)
		} else {
			epA[i] = 255
		}
	}

	// Fixup pixels (each subset's first pixel stores one fewer index bit)
	var isFixup [16]bool
	isFixup[0] = true // subset 0 fixup is always pixel 0
	if m.ns == 2 {
		isFixup[bc7Fix2[partIdx]] = true
	} else if m.ns == 3 {
		isFixup[bc7Fix3[partIdx][0]] = true
		isFixup[bc7Fix3[partIdx][1]] = true
	}

	// Primary indices
	var idx0 [16]uint32
	for i := 0; i < 16; i++ {
		bits := uint(m.ib)
		if isFixup[i] {
			bits--
		}
		idx0[i] = br.read(bits)
	}

	// Secondary indices (dual-index modes 4 and 5)
	var idx1 [16]uint32
	if m.ib2 > 0 {
		for i := 0; i < 16; i++ {
			bits := uint(m.ib2)
			if i == 0 { // NS=1 in all dual-index modes, fixup is always pixel 0
				bits--
			}
			idx1[i] = br.read(bits)
		}
	}

	// Subset assignment per pixel
	var subsets [16]int
	if m.ns == 2 {
		for i := range subsets {
			subsets[i] = int(bc7Part2[partIdx][i])
		}
	} else if m.ns == 3 {
		for i := range subsets {
			subsets[i] = int(bc7Part3[partIdx][i])
		}
	}
	// ns == 1: subsets stays all-zero

	// Decode and write pixels
	for py := 0; py < 4; py++ {
		for px := 0; px < 4; px++ {
			i := py*4 + px
			s := subsets[i]
			ep0, ep1 := s*2, s*2+1

			// Determine color/alpha index and interpolation bit width
			var colorIdx, alphaIdx uint32
			ibColor, ibAlpha := m.ib, m.ib
			if m.ib2 == 0 {
				colorIdx = idx0[i]
				alphaIdx = idx0[i]
			} else if idxSel == 0 {
				colorIdx, ibColor = idx0[i], m.ib
				alphaIdx, ibAlpha = idx1[i], m.ib2
			} else {
				colorIdx, ibColor = idx1[i], m.ib2
				alphaIdx, ibAlpha = idx0[i], m.ib
			}

			r := bc7Lerp(epR[ep0], epR[ep1], colorIdx, ibColor)
			g := bc7Lerp(epG[ep0], epG[ep1], colorIdx, ibColor)
			b := bc7Lerp(epB[ep0], epB[ep1], colorIdx, ibColor)
			var a uint8 = 255
			if m.ab > 0 {
				a = bc7Lerp(epA[ep0], epA[ep1], alphaIdx, ibAlpha)
			}

			// Rotation swaps one color channel with alpha
			switch rotation {
			case 1:
				r, a = a, r
			case 2:
				g, a = a, g
			case 3:
				b, a = a, b
			}

			dstX, dstY := bx+px, by+py
			if dstX < imgW && dstY < imgH {
				img.SetRGBA(dstX, dstY, color.RGBA{r, g, b, a})
			}
		}
	}
}
