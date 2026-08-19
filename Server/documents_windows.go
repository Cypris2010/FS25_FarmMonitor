//go:build windows

package main

import (
	"syscall"
	"unsafe"
)

// FOLDERID_Documents = {FDD39AD0-238F-46AF-ADB4-6C85480369C7}
var folderIDDocuments = syscall.GUID{
	Data1: 0xFDD39AD0,
	Data2: 0x238F,
	Data3: 0x46AF,
	Data4: [8]byte{0xAD, 0xB4, 0x6C, 0x85, 0x48, 0x03, 0x69, 0xC7},
}

// windowsDocumentsDir resolves the user's real Documents folder via the
// Windows Known Folder API. Unlike joining "Documents" onto the home
// directory, this correctly follows folder redirection (e.g. Documents
// moved to a different drive), which plain os.UserHomeDir()-based guessing
// gets wrong.
func windowsDocumentsDir() string {
	shell32 := syscall.NewLazyDLL("shell32.dll")
	ole32 := syscall.NewLazyDLL("ole32.dll")
	procGetKnownFolderPath := shell32.NewProc("SHGetKnownFolderPath")
	procCoTaskMemFree := ole32.NewProc("CoTaskMemFree")

	var pathPtr uintptr
	ret, _, _ := procGetKnownFolderPath.Call(
		uintptr(unsafe.Pointer(&folderIDDocuments)),
		0,
		0,
		uintptr(unsafe.Pointer(&pathPtr)),
	)
	if ret != 0 || pathPtr == 0 {
		return ""
	}
	defer procCoTaskMemFree.Call(pathPtr)

	// Convert the returned UTF-16 string to a Go string.
	var chars []uint16
	for i := 0; ; i++ {
		c := *(*uint16)(unsafe.Pointer(pathPtr + uintptr(i)*2))
		if c == 0 {
			break
		}
		chars = append(chars, c)
	}
	return syscall.UTF16ToString(chars)
}
