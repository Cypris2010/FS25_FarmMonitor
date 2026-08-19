//go:build !windows

package main

// windowsDocumentsDir is only meaningful on Windows; other platforms don't
// need Known Folder resolution since defaultDataDir() uses fixed paths there.
func windowsDocumentsDir() string {
	return ""
}
