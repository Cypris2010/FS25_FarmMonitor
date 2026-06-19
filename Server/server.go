package main

import (
	"archive/zip"
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"encoding/json"
	"encoding/xml"
	"embed"
	"flag"
	"fmt"
	"image"
	"image/color"
	"image/draw"
	"image/png"
	"io"
	"io/fs"
	"strconv"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"sync"
	"time"
)

//go:embed static
var staticFiles embed.FS

// set via -ldflags "-X main.serverVersion=x.x.x"
var serverVersion string

// ---------------------------------------------------------------------------
// SSE broker
// ---------------------------------------------------------------------------

type broker struct {
	mu      sync.Mutex
	clients map[chan struct{}]struct{}
}

func newBroker() *broker {
	return &broker{clients: make(map[chan struct{}]struct{})}
}

func (b *broker) subscribe() chan struct{} {
	ch := make(chan struct{}, 1)
	b.mu.Lock()
	b.clients[ch] = struct{}{}
	b.mu.Unlock()
	return ch
}

func (b *broker) unsubscribe(ch chan struct{}) {
	b.mu.Lock()
	delete(b.clients, ch)
	b.mu.Unlock()
}

func (b *broker) broadcast() {
	b.mu.Lock()
	defer b.mu.Unlock()
	for ch := range b.clients {
		select {
		case ch <- struct{}{}:
		default:
		}
	}
}

// ---------------------------------------------------------------------------
// File watcher
// ---------------------------------------------------------------------------

func watchFiles(files []string, interval time.Duration, b *broker) {
	modTimes := make(map[string]time.Time, len(files))
	for _, f := range files {
		if info, err := os.Stat(f); err == nil {
			modTimes[f] = info.ModTime()
		}
	}

	for range time.Tick(interval) {
		changed := false
		for _, f := range files {
			info, err := os.Stat(f)
			if err != nil {
				continue
			}
			if info.ModTime().After(modTimes[f]) {
				modTimes[f] = info.ModTime()
				changed = true
			}
		}
		if changed {
			b.broadcast()
		}
	}
}

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

func settingsPath() string {
	configDir, err := os.UserConfigDir()
	if err != nil {
		return ""
	}
	return filepath.Join(configDir, "FS25_FarmMonitor", "settings.json")
}

func handleSettings() http.HandlerFunc {
	path := settingsPath()

	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Access-Control-Allow-Origin", "*")

		switch r.Method {
		case http.MethodGet:
			data, err := os.ReadFile(path)
			if err != nil {
				w.Write([]byte("{}"))
				return
			}
			w.Write(data)

		case http.MethodPut:
			var raw json.RawMessage
			if err := json.NewDecoder(r.Body).Decode(&raw); err != nil {
				http.Error(w, "invalid JSON", http.StatusBadRequest)
				return
			}
			if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
				http.Error(w, "cannot create config dir", http.StatusInternalServerError)
				return
			}
			if err := os.WriteFile(path, raw, 0644); err != nil {
				http.Error(w, "cannot write settings", http.StatusInternalServerError)
				return
			}
			w.Write(raw)

		default:
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		}
	}
}

func savegamePath(savegameID string) string {
	configDir, err := os.UserConfigDir()
	if err != nil {
		return ""
	}
	sum := sha256.Sum256([]byte(savegameID))
	filename := fmt.Sprintf("%x.json", sum[:16])
	return filepath.Join(configDir, "FS25_FarmMonitor", "savegames", filename)
}

func handleSavegame() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		savegameID := r.PathValue("savegameId")
		if savegameID == "" || len(savegameID) > 512 {
			http.Error(w, "invalid savegameId", http.StatusBadRequest)
			return
		}

		path := savegamePath(savegameID)
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Access-Control-Allow-Origin", "*")

		switch r.Method {
		case http.MethodGet:
			data, err := os.ReadFile(path)
			if err != nil {
				w.Write([]byte("{}"))
				return
			}
			w.Write(data)

		case http.MethodPut:
			var raw json.RawMessage
			if err := json.NewDecoder(r.Body).Decode(&raw); err != nil {
				http.Error(w, "invalid JSON", http.StatusBadRequest)
				return
			}
			if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
				http.Error(w, "cannot create savegames dir", http.StatusInternalServerError)
				return
			}
			if err := os.WriteFile(path, raw, 0644); err != nil {
				http.Error(w, "cannot write savegame settings", http.StatusInternalServerError)
				return
			}
			w.Write(raw)

		default:
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		}
	}
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

// xmlSeconds is a helper to parse <element seconds="N"/> attributes.
type xmlSeconds struct {
	Seconds int `xml:"seconds,attr"`
}
type xmlValue struct {
	Value int `xml:"value,attr"`
}
type xmlEnabled struct {
	Enabled string `xml:"enabled,attr"`
}

// modConfigXML is used only for XML parsing (nested attribute structs).
type modConfigXML struct {
	ExportIntervals struct {
		Main     xmlSeconds `xml:"main"`
		Vehicles xmlSeconds `xml:"vehicles"`
		Fields   xmlSeconds `xml:"fields"`
		Weather  xmlSeconds `xml:"weather"`
		Commands xmlSeconds `xml:"commands"`
	} `xml:"exportIntervals"`
	SoilMap struct {
		Resolution  xmlValue `xml:"resolution"`
		RowsPerTick xmlValue `xml:"rowsPerTick"`
	} `xml:"soilMap"`
	PerformanceLog xmlEnabled `xml:"performanceLog"`
}

// modConfig is the flat struct used for JSON and runtime logic.
type modConfig struct {
	ExportIntervals struct {
		Main     int `json:"mainSeconds"`
		Vehicles int `json:"vehicleSeconds"`
		Fields   int `json:"fieldSeconds"`
		Weather  int `json:"weatherSeconds"`
		Commands int `json:"commandSeconds"`
	} `json:"exportIntervals"`
	SoilMap struct {
		Resolution  int `json:"resolution"`
		RowsPerTick int `json:"rowsPerTick"`
	} `json:"soilMap"`
	PerfLog bool `json:"perfLog"`
}

var modConfigDefaults = modConfig{}

func init() {
	modConfigDefaults.ExportIntervals.Main = 10
	modConfigDefaults.ExportIntervals.Vehicles = 2
	modConfigDefaults.ExportIntervals.Fields = 60
	modConfigDefaults.ExportIntervals.Weather = 30
	modConfigDefaults.ExportIntervals.Commands = 1
	modConfigDefaults.SoilMap.Resolution = 128
	modConfigDefaults.SoilMap.RowsPerTick = 2
}

func readModConfig(dataDir string) modConfig {
	cfg := modConfigDefaults
	data, err := os.ReadFile(filepath.Join(dataDir, "config.xml"))
	if err != nil {
		return cfg
	}
	var parsed modConfigXML
	if err := xml.Unmarshal(data, &parsed); err != nil {
		return cfg
	}
	if parsed.ExportIntervals.Main.Seconds > 0     { cfg.ExportIntervals.Main = parsed.ExportIntervals.Main.Seconds }
	if parsed.ExportIntervals.Vehicles.Seconds > 0 { cfg.ExportIntervals.Vehicles = parsed.ExportIntervals.Vehicles.Seconds }
	if parsed.ExportIntervals.Fields.Seconds > 0   { cfg.ExportIntervals.Fields = parsed.ExportIntervals.Fields.Seconds }
	if parsed.ExportIntervals.Weather.Seconds > 0  { cfg.ExportIntervals.Weather = parsed.ExportIntervals.Weather.Seconds }
	if parsed.ExportIntervals.Commands.Seconds > 0 { cfg.ExportIntervals.Commands = parsed.ExportIntervals.Commands.Seconds }
	if parsed.SoilMap.Resolution.Value > 0         { cfg.SoilMap.Resolution = parsed.SoilMap.Resolution.Value }
	if parsed.SoilMap.RowsPerTick.Value > 0        { cfg.SoilMap.RowsPerTick = parsed.SoilMap.RowsPerTick.Value }
	cfg.PerfLog = parsed.PerformanceLog.Enabled == "true"
	return cfg
}

func writeModConfig(dataDir string, cfg modConfig) error {
	lines := []string{
		`<?xml version="1.0" encoding="utf-8"?>`,
		`<farmMonitor>`,
		`    <!-- Export intervals in seconds -->`,
		`    <exportIntervals>`,
		fmt.Sprintf(`        <main seconds="%d"/>`, cfg.ExportIntervals.Main),
		fmt.Sprintf(`        <vehicles seconds="%d"/>`, cfg.ExportIntervals.Vehicles),
		fmt.Sprintf(`        <fields seconds="%d"/>`, cfg.ExportIntervals.Fields),
		fmt.Sprintf(`        <weather seconds="%d"/>`, cfg.ExportIntervals.Weather),
		fmt.Sprintf(`        <commands seconds="%d"/>`, cfg.ExportIntervals.Commands),
		`    </exportIntervals>`,
		`    <!-- Soil map quality: resolution 64/128/256, rowsPerTick 1-8 -->`,
		`    <soilMap>`,
		fmt.Sprintf(`        <resolution value="%d"/>`, cfg.SoilMap.Resolution),
		fmt.Sprintf(`        <rowsPerTick value="%d"/>`, cfg.SoilMap.RowsPerTick),
		`    </soilMap>`,
		fmt.Sprintf(`    <performanceLog enabled="%v"/>`, cfg.PerfLog),
		`</farmMonitor>`,
	}
	content := strings.Join(lines, "\n") + "\n"
	return os.WriteFile(filepath.Join(dataDir, "config.xml"), []byte(content), 0644)
}

// --- Perf Export ---

func runSysCmd(name string, args ...string) string {
	out, err := exec.Command(name, args...).Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

func parseWmicField(output, field string) string {
	for _, line := range strings.Split(output, "\n") {
		line = strings.TrimSpace(strings.ReplaceAll(line, "\r", ""))
		if strings.HasPrefix(line, field+"=") {
			return strings.TrimPrefix(line, field+"=")
		}
	}
	return ""
}

type perfSysInfo struct {
	OS    string
	CPU   string
	Cores string
	RAM   string
	GPU   string
}

func collectGPUDarwin() string {
	out, err := exec.Command("system_profiler", "SPDisplaysDataType", "-json").Output()
	if err != nil {
		return ""
	}
	var result struct {
		SPDisplaysDataType []map[string]interface{} `json:"SPDisplaysDataType"`
	}
	if err := json.Unmarshal(out, &result); err != nil || len(result.SPDisplaysDataType) == 0 {
		return ""
	}
	if v, ok := result.SPDisplaysDataType[0]["spdisplays_chipset-model"].(string); ok {
		return v
	}
	return ""
}

func collectPerfSysInfo() perfSysInfo {
	var info perfSysInfo
	switch runtime.GOOS {
	case "darwin":
		ver := runSysCmd("sw_vers", "-productVersion")
		info.OS = fmt.Sprintf("macOS %s (%s/%s)", ver, runtime.GOOS, runtime.GOARCH)
		cpu := runSysCmd("sysctl", "-n", "machdep.cpu.brand_string")
		if cpu == "" {
			cpu = runSysCmd("sysctl", "-n", "hw.model")
		}
		info.CPU = cpu
		phys := runSysCmd("sysctl", "-n", "hw.physicalcpu")
		logi := runSysCmd("sysctl", "-n", "hw.logicalcpu")
		info.Cores = fmt.Sprintf("%s physisch / %s logisch", phys, logi)
		var ramBytes int64
		fmt.Sscanf(runSysCmd("sysctl", "-n", "hw.memsize"), "%d", &ramBytes)
		info.RAM = fmt.Sprintf("%.1f GB", float64(ramBytes)/(1<<30))
		info.GPU = collectGPUDarwin()
	case "windows":
		cpuOut := runSysCmd("wmic", "cpu", "get", "Name,NumberOfCores,NumberOfLogicalProcessors", "/value")
		info.CPU = parseWmicField(cpuOut, "Name")
		info.Cores = fmt.Sprintf("%s physisch / %s logisch",
			parseWmicField(cpuOut, "NumberOfCores"),
			parseWmicField(cpuOut, "NumberOfLogicalProcessors"))
		osOut := runSysCmd("wmic", "os", "get", "Caption,Version", "/value")
		info.OS = fmt.Sprintf("%s %s (%s/%s)",
			parseWmicField(osOut, "Caption"),
			parseWmicField(osOut, "Version"),
			runtime.GOOS, runtime.GOARCH)
		var ramBytes int64
		fmt.Sscanf(parseWmicField(runSysCmd("wmic", "computersystem", "get", "TotalPhysicalMemory", "/value"), "TotalPhysicalMemory"), "%d", &ramBytes)
		info.RAM = fmt.Sprintf("%.1f GB", float64(ramBytes)/(1<<30))
		info.GPU = parseWmicField(runSysCmd("wmic", "path", "win32_VideoController", "get", "Name", "/value"), "Name")
	default:
		info.OS = fmt.Sprintf("%s/%s", runtime.GOOS, runtime.GOARCH)
	}
	return info
}

func readPerfLines(logPath string) []string {
	data, err := os.ReadFile(logPath)
	if err != nil {
		return nil
	}
	var lines []string
	for _, line := range strings.Split(string(data), "\n") {
		if strings.Contains(line, "[FarmMonitor] PERF") {
			lines = append(lines, strings.TrimSpace(line))
		}
	}
	return lines
}

func readModVersion(dataDir string) string {
	data, err := os.ReadFile(filepath.Join(dataDir, "modInfo.json"))
	if err != nil {
		return "unknown"
	}
	var info struct {
		Version string `json:"version"`
	}
	if err := json.Unmarshal(data, &info); err != nil {
		return "unknown"
	}
	return info.Version
}

func handlePerfExport(dataDir string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		if r.Method != http.MethodPost {
			http.Error(w, "POST only", http.StatusMethodNotAllowed)
			return
		}

		sys := collectPerfSysInfo()
		cfg := readModConfig(dataDir)
		modVersion := readModVersion(dataDir)
		logPath := filepath.Join(filepath.Dir(filepath.Dir(dataDir)), "log.txt")
		perfLines := readPerfLines(logPath)

		var sb strings.Builder
		sb.WriteString("=== FarmMonitor Performance Export ===\n")
		sb.WriteString(fmt.Sprintf("Erstellt:         %s\n", time.Now().Format("2006-01-02T15:04:05")))
		sb.WriteString(fmt.Sprintf("Server-Version:   %s\n", serverVersion))
		sb.WriteString(fmt.Sprintf("Mod-Version:      %s\n", modVersion))
		sb.WriteString("\n=== System ===\n")
		sb.WriteString(fmt.Sprintf("OS:               %s\n", sys.OS))
		sb.WriteString(fmt.Sprintf("CPU:              %s (%s)\n", sys.CPU, sys.Cores))
		sb.WriteString(fmt.Sprintf("GPU:              %s\n", sys.GPU))
		sb.WriteString(fmt.Sprintf("RAM:              %s\n", sys.RAM))
		sb.WriteString("\n=== Mod-Konfiguration ===\n")
		sb.WriteString(fmt.Sprintf("Haupt-Export:     %d s\n", cfg.ExportIntervals.Main))
		sb.WriteString(fmt.Sprintf("Fahrzeuge:        %d s\n", cfg.ExportIntervals.Vehicles))
		sb.WriteString(fmt.Sprintf("Felder:           %d s\n", cfg.ExportIntervals.Fields))
		sb.WriteString(fmt.Sprintf("Wetter:           %d s\n", cfg.ExportIntervals.Weather))
		sb.WriteString(fmt.Sprintf("IPC-Commands:     %d s\n", cfg.ExportIntervals.Commands))
		sb.WriteString(fmt.Sprintf("Soil-Auflösung:   %d px\n", cfg.SoilMap.Resolution))
		sb.WriteString(fmt.Sprintf("Soil-RowsPerTick: %d\n", cfg.SoilMap.RowsPerTick))
		sb.WriteString(fmt.Sprintf("\n=== Performance-Messungen (%d Einträge) ===\n", len(perfLines)))
		for _, line := range perfLines {
			sb.WriteString(line + "\n")
		}

		exportPath := filepath.Join(dataDir, "perf_export.txt")
		if err := os.WriteFile(exportPath, []byte(sb.String()), 0644); err != nil {
			http.Error(w, "cannot write export file", http.StatusInternalServerError)
			return
		}
		json.NewEncoder(w).Encode(map[string]string{"path": exportPath})
	}
}

func handleModConfig(dataDir string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, PUT, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}

		switch r.Method {
		case http.MethodGet:
			cfg := readModConfig(dataDir)
			json.NewEncoder(w).Encode(cfg)

		case http.MethodPut:
			var cfg modConfig
			if err := json.NewDecoder(r.Body).Decode(&cfg); err != nil {
				http.Error(w, "invalid JSON", http.StatusBadRequest)
				return
			}
			if err := writeModConfig(dataDir, cfg); err != nil {
				http.Error(w, "cannot write config.xml", http.StatusInternalServerError)
				return
			}
			json.NewEncoder(w).Encode(cfg)

		default:
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		}
	}
}

// --- commands.xml shared types + atomic appender ---------------------------

type xmlCommand struct {
	XMLName         xml.Name `xml:"command"`
	ID              string   `xml:"id,attr"`
	Cmd             string   `xml:"cmd,attr"`
	UniqueID        string   `xml:"uniqueId,attr"`
	NetID           string   `xml:"netId,attr"` // NetworkUtil object ID — MP-safe vehicle lookup
	FillType        string   `xml:"fillType,attr"`
	Mode            string   `xml:"mode,attr"`
	Amount          string   `xml:"amount,attr"`
	X               string   `xml:"x,attr"`
	Y               string   `xml:"y,attr"`
	Z               string   `xml:"z,attr"`
	Marker1         string   `xml:"marker1,attr"`
	Marker2         string   `xml:"marker2,attr"`
	ObjectInfoIndex string   `xml:"objectInfoIndex,attr"`
	Value           string   `xml:"value,attr"`   // for AD speed/loop/setting commands
	Setting         string   `xml:"setting,attr"` // for autodrive.setting
	Layers          string   `xml:"layers,attr"`  // for soilScan.setLayers (comma-separated)
}

type xmlCommands struct {
	XMLName  xml.Name     `xml:"commands"`
	Count    int          `xml:"count,attr"`
	Commands []xmlCommand `xml:"command"`
}

var commandsMu sync.Mutex

// appendCommand appends a command to commands.xml atomically, preserving any
// commands Lua hasn't polled yet. Safe for concurrent callers (handleCommand,
// soil presence union).
func appendCommand(dataDir string, newCmd xmlCommand) error {
	commandsMu.Lock()
	defer commandsMu.Unlock()

	cmdPath := filepath.Join(dataDir, "commands.xml")
	var allCmds []xmlCommand
	if existing, err := os.ReadFile(cmdPath); err == nil {
		var existingXML xmlCommands
		if err2 := xml.Unmarshal(existing, &existingXML); err2 == nil {
			allCmds = existingXML.Commands
		}
	}
	allCmds = append(allCmds, newCmd)

	xmlData, err := xml.MarshalIndent(xmlCommands{Count: len(allCmds), Commands: allCmds}, "", "  ")
	if err != nil {
		return err
	}

	// Write to a temp file first, then rename atomically — ensures Lua never
	// reads a partially-written file (os.Rename is atomic on POSIX).
	payload := append([]byte(xml.Header), xmlData...)
	tmpPath := cmdPath + ".tmp"
	if err := os.WriteFile(tmpPath, payload, 0644); err != nil {
		return err
	}
	if err := os.Rename(tmpPath, cmdPath); err != nil {
		_ = os.Remove(tmpPath)
		return err
	}
	return nil
}

func handleCommand(dataDir string) http.HandlerFunc {
	type jsonCommand struct {
		ID              string `json:"id"`
		Cmd             string `json:"cmd"`
		UniqueID        string `json:"uniqueId,omitempty"`
		NetID           string `json:"netId,omitempty"`     // NetworkUtil object ID — MP-safe vehicle lookup
		FillType        string `json:"fillType,omitempty"`
		Mode            string `json:"mode,omitempty"`
		Amount          string `json:"amount,omitempty"`
		X               string `json:"x,omitempty"`
		Y               string `json:"y,omitempty"`
		Z               string `json:"z,omitempty"`
		Marker1         string `json:"marker1,omitempty"`
		Marker2         string `json:"marker2,omitempty"`
		ObjectInfoIndex string `json:"objectInfoIndex,omitempty"`
		Value           string `json:"value,omitempty"`   // for AD speed/loop/setting commands
		Setting         string `json:"setting,omitempty"` // for autodrive.setting
		Layers          string `json:"layers,omitempty"`  // for soilScan.setLayers (comma-separated)
	}

	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}

		var cmd jsonCommand
		if err := json.NewDecoder(r.Body).Decode(&cmd); err != nil {
			http.Error(w, "invalid JSON", http.StatusBadRequest)
			return
		}
		log.Printf("[command] received: cmd=%s uniqueId=%s netId=%s mode=%s marker1=%s marker2=%s", cmd.Cmd, cmd.UniqueID, cmd.NetID, cmd.Mode, cmd.Marker1, cmd.Marker2)
		if cmd.ID == "" {
			cmd.ID = fmt.Sprintf("%d", time.Now().UnixNano())
		}

		newCmd := xmlCommand{
			ID:              cmd.ID,
			Cmd:             cmd.Cmd,
			UniqueID:        cmd.UniqueID,
			NetID:           cmd.NetID,
			FillType:        cmd.FillType,
			Mode:            cmd.Mode,
			Amount:          cmd.Amount,
			X:               cmd.X,
			Y:               cmd.Y,
			Z:               cmd.Z,
			Marker1:         cmd.Marker1,
			Marker2:         cmd.Marker2,
			ObjectInfoIndex: cmd.ObjectInfoIndex,
			Value:           cmd.Value,
			Setting:         cmd.Setting,
			Layers:          cmd.Layers,
		}

		if err := appendCommand(dataDir, newCmd); err != nil {
			http.Error(w, "write error", http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"id": cmd.ID})
	}
}

// ---------------------------------------------------------------------------
// Soil-layer presence — aggregates which soil overlays are currently shown
// across all connected browsers and tells Lua to scan only those (on-demand).
// ---------------------------------------------------------------------------

var validSoilLayers = map[string]bool{
	"weed": true, "stone": true, "plow": true, "spray": true,
	"lime": true, "mulch": true, "roller": true,
}

const soilPresenceTTL = 45 * time.Second // a client expires after this without a heartbeat

type soilClient struct {
	layers   map[string]bool
	lastSeen time.Time
}

type soilPresence struct {
	mu        sync.Mutex
	dataDir   string
	clients   map[string]*soilClient
	lastUnion string // sorted comma list last written to Lua; "" = none active
}

func newSoilPresence(dataDir string) *soilPresence {
	sp := &soilPresence{dataDir: dataDir, clients: map[string]*soilClient{}}
	// Background reconcile so the union shrinks when clients stop heartbeating
	// (left the map view / closed tab) even without new POSTs arriving.
	go func() {
		t := time.NewTicker(15 * time.Second)
		defer t.Stop()
		for range t.C {
			sp.reconcile()
		}
	}()
	return sp
}

// unionLocked prunes stale clients and returns the sorted union of active layers.
// Caller must hold sp.mu.
func (sp *soilPresence) unionLocked() string {
	now := time.Now()
	set := map[string]bool{}
	for id, c := range sp.clients {
		if now.Sub(c.lastSeen) > soilPresenceTTL {
			delete(sp.clients, id)
			continue
		}
		for l := range c.layers {
			set[l] = true
		}
	}
	names := make([]string, 0, len(set))
	for l := range set {
		names = append(names, l)
	}
	sort.Strings(names)
	return strings.Join(names, ",")
}

// reconcile recomputes the union; if it changed since the last write, it emits a
// soilScan.setLayers command for Lua.
func (sp *soilPresence) reconcile() {
	sp.mu.Lock()
	union := sp.unionLocked()
	changed := union != sp.lastUnion
	if changed {
		sp.lastUnion = union
	}
	sp.mu.Unlock()
	if !changed {
		return
	}
	cmd := xmlCommand{
		ID:     fmt.Sprintf("soil-%d", time.Now().UnixNano()),
		Cmd:    "soilScan.setLayers",
		Layers: union,
	}
	if err := appendCommand(sp.dataDir, cmd); err != nil {
		log.Printf("[soil] failed to write setLayers command: %v", err)
		return
	}
	log.Printf("[soil] active layers union → %q", union)
}

func (sp *soilPresence) handler() http.HandlerFunc {
	type req struct {
		ClientID string   `json:"clientId"`
		Layers   []string `json:"layers"`
	}
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		var body req
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			http.Error(w, "invalid JSON", http.StatusBadRequest)
			return
		}
		if body.ClientID == "" {
			http.Error(w, "missing clientId", http.StatusBadRequest)
			return
		}
		layers := map[string]bool{}
		for _, l := range body.Layers {
			if validSoilLayers[l] {
				layers[l] = true
			}
		}
		sp.mu.Lock()
		if len(layers) == 0 {
			delete(sp.clients, body.ClientID) // no layers → drop client immediately
		} else {
			sp.clients[body.ClientID] = &soilClient{layers: layers, lastSeen: time.Now()}
		}
		sp.mu.Unlock()

		sp.reconcile()
		w.WriteHeader(http.StatusNoContent)
	}
}

// ---------------------------------------------------------------------------
// DDS decoder (DXT1 / DXT5 / BC7)
// ---------------------------------------------------------------------------

func rgb565(v uint16) (r, g, b uint8) {
	r5, g6, b5 := uint8(v>>11), uint8((v>>5)&0x3F), uint8(v&0x1F)
	return (r5 << 3) | (r5 >> 2), (g6 << 2) | (g6 >> 4), (b5 << 3) | (b5 >> 2)
}

func dxt1Colors(v0, v1 uint16, force4 bool) [4]color.RGBA {
	r0, g0, b0 := rgb565(v0)
	r1, g1, b1 := rgb565(v1)
	var c [4]color.RGBA
	c[0] = color.RGBA{r0, g0, b0, 255}
	c[1] = color.RGBA{r1, g1, b1, 255}
	if v0 > v1 || force4 {
		c[2] = color.RGBA{uint8((2*int(r0) + int(r1) + 1) / 3), uint8((2*int(g0) + int(g1) + 1) / 3), uint8((2*int(b0) + int(b1) + 1) / 3), 255}
		c[3] = color.RGBA{uint8((int(r0) + 2*int(r1) + 1) / 3), uint8((int(g0) + 2*int(g1) + 1) / 3), uint8((int(b0) + 2*int(b1) + 1) / 3), 255}
	} else {
		c[2] = color.RGBA{uint8((int(r0) + int(r1)) / 2), uint8((int(g0) + int(g1)) / 2), uint8((int(b0) + int(b1)) / 2), 255}
		c[3] = color.RGBA{0, 0, 0, 0}
	}
	return c
}

func writeDXT1Block(block []byte, img *image.RGBA, bx, by, imgW, imgH int, force4 bool) {
	v0 := binary.LittleEndian.Uint16(block[0:2])
	v1 := binary.LittleEndian.Uint16(block[2:4])
	colors := dxt1Colors(v0, v1, force4)
	bits := binary.LittleEndian.Uint32(block[4:8])
	for py := 0; py < 4; py++ {
		for px := 0; px < 4; px++ {
			x, y := bx+px, by+py
			if x >= imgW || y >= imgH {
				continue
			}
			img.SetRGBA(x, y, colors[(bits>>(uint(py*4+px)*2))&3])
		}
	}
}

func writeDXT5Block(block []byte, img *image.RGBA, bx, by, imgW, imgH int) {
	a0, a1 := block[0], block[1]
	var alphas [8]uint8
	alphas[0], alphas[1] = a0, a1
	if a0 > a1 {
		for i := 2; i < 8; i++ {
			alphas[i] = uint8((int(a0)*(8-i) + int(a1)*(i-1)) / 7)
		}
	} else {
		for i := 2; i < 6; i++ {
			alphas[i] = uint8((int(a0)*(6-i) + int(a1)*(i-1)) / 5)
		}
		alphas[6], alphas[7] = 0, 255
	}
	abits := uint64(block[2]) | uint64(block[3])<<8 | uint64(block[4])<<16 |
		uint64(block[5])<<24 | uint64(block[6])<<32 | uint64(block[7])<<40
	writeDXT1Block(block[8:16], img, bx, by, imgW, imgH, true)
	for py := 0; py < 4; py++ {
		for px := 0; px < 4; px++ {
			x, y := bx+px, by+py
			if x >= imgW || y >= imgH {
				continue
			}
			c := img.RGBAAt(x, y)
			c.A = alphas[(abits>>(uint(py*4+px)*3))&7]
			img.SetRGBA(x, y, c)
		}
	}
}

func decodeDDS(data []byte) (image.Image, error) {
	if len(data) < 128 || string(data[0:4]) != "DDS " {
		return nil, fmt.Errorf("not a DDS file")
	}
	imgH := int(binary.LittleEndian.Uint32(data[12:16]))
	imgW := int(binary.LittleEndian.Uint32(data[16:20]))
	if imgW <= 0 || imgH <= 0 || imgW > 8192 || imgH > 8192 {
		return nil, fmt.Errorf("invalid dimensions %dx%d", imgW, imgH)
	}
	fourCC := string(data[84:88])
	img := image.NewRGBA(image.Rect(0, 0, imgW, imgH))
	numBX, numBY := (imgW+3)/4, (imgH+3)/4
	off := 128
	switch fourCC {
	case "DXT1":
		for y := 0; y < numBY; y++ {
			for x := 0; x < numBX; x++ {
				if off+8 > len(data) {
					return img, nil
				}
				writeDXT1Block(data[off:off+8], img, x*4, y*4, imgW, imgH, false)
				off += 8
			}
		}
	case "DXT5":
		for y := 0; y < numBY; y++ {
			for x := 0; x < numBX; x++ {
				if off+16 > len(data) {
					return img, nil
				}
				writeDXT5Block(data[off:off+16], img, x*4, y*4, imgW, imgH)
				off += 16
			}
		}
	case "DX10":
		if len(data) < 148 {
			return nil, fmt.Errorf("DDS DX10 header too short")
		}
		dxgi := binary.LittleEndian.Uint32(data[128:132])
		if dxgi != 98 && dxgi != 99 {
			return nil, fmt.Errorf("unsupported DXGI format %d", dxgi)
		}
		off = 148
		for y := 0; y < numBY; y++ {
			for x := 0; x < numBX; x++ {
				if off+16 > len(data) {
					return img, nil
				}
				writeBC7Block(data[off:off+16], img, x*4, y*4, imgW, imgH)
				off += 16
			}
		}
	default:
		return nil, fmt.Errorf("unsupported DDS format %q", fourCC)
	}
	return img, nil
}

// ---------------------------------------------------------------------------
// Map image cache
// ---------------------------------------------------------------------------

type mapCache struct {
	mu          sync.RWMutex
	overviewPNG []byte
	lastMeta    string // overviewDdsPath from last successful load
}

func newMapCache() *mapCache { return &mapCache{} }

func (c *mapCache) getPNG() []byte {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.overviewPNG
}

// readOverviewDDS reads the map overview image from disk.
// FS25 mods are often installed as zips — the game loads them directly without
// extracting. missionInfo.baseDirectory returns a folder path without ".zip".
// We walk up the directory tree looking for a .zip sibling, because the image
// may live in a subdirectory inside the zip (e.g. NFMarsch/pda_map_H.dds inside
// FS25_NFMarsch4fach.zip).
func readOverviewDDS(ddsPath string) ([]byte, error) {
	// Fast path: file exists directly
	if data, err := os.ReadFile(ddsPath); err == nil {
		return data, nil
	}
	base := filepath.Base(ddsPath)
	// Walk up the directory tree — try dir.zip, then parent.zip, etc.
	dir := filepath.Dir(ddsPath)
	for {
		zipPath := dir + ".zip"
		if zr, err := zip.OpenReader(zipPath); err == nil {
			for _, f := range zr.File {
				// Match by filename only — ignore sub-directory prefix inside zip
				if strings.EqualFold(filepath.Base(f.Name), base) {
					rc, err := f.Open()
					if err != nil {
						zr.Close()
						return nil, fmt.Errorf("zip open %s: %w", f.Name, err)
					}
					data, err := io.ReadAll(rc)
					rc.Close()
					zr.Close()
					return data, err
				}
			}
			zr.Close()
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	return nil, fmt.Errorf("map overview %q not found on disk or in any parent zip", base)
}

func (c *mapCache) rebuild(metaPath string) {
	raw, err := os.ReadFile(metaPath)
	if err != nil {
		return
	}
	var meta struct {
		OverviewDdsPath string `json:"overviewDdsPath"`
	}
	if err := json.Unmarshal(raw, &meta); err != nil || meta.OverviewDdsPath == "" {
		return
	}
	c.mu.RLock()
	same := c.lastMeta == meta.OverviewDdsPath
	c.mu.RUnlock()
	if same {
		return
	}
	ddsData, err := readOverviewDDS(meta.OverviewDdsPath)
	if err != nil {
		log.Printf("[map] cannot read overview.dds: %v", err)
		return
	}
	img, err := decodeDDS(ddsData)
	if err != nil {
		log.Printf("[map] DDS decode failed: %v", err)
		return
	}
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		log.Printf("[map] PNG encode failed: %v", err)
		return
	}
	c.mu.Lock()
	c.overviewPNG = buf.Bytes()
	c.lastMeta = meta.OverviewDdsPath
	c.mu.Unlock()
	log.Printf("[map] overview.dds loaded and cached (%d bytes PNG)", buf.Len())
}

func watchAndRebuildMap(metaPath string, cache *mapCache) {
	var lastMod time.Time
	if info, err := os.Stat(metaPath); err == nil {
		lastMod = info.ModTime()
		cache.rebuild(metaPath)
	}
	for range time.Tick(5 * time.Second) {
		info, err := os.Stat(metaPath)
		if err != nil {
			continue
		}
		if info.ModTime().After(lastMod) {
			lastMod = info.ModTime()
			go cache.rebuild(metaPath)
		}
	}
}

// ── AutoDrive icon cache ──────────────────────────────────────────────────────

type adIconCache struct {
	mu     sync.Mutex
	icons  map[string][]byte
	loaded bool
}

func newADIconCache() *adIconCache { return &adIconCache{icons: map[string][]byte{}} }

func (c *adIconCache) reload(modsDir string) {
	c.mu.Lock()
	c.loaded = false
	c.icons = map[string][]byte{}
	c.mu.Unlock()
	c.load(modsDir)
}

// defaultModsDir derives the FS25 mods directory from the data directory.
// dataDir is .../modSettings/FS25_FarmMonitor → parent is FarmingSimulator2025 → mods sibling.
func defaultModsDir(dataDir string) string {
	return filepath.Join(filepath.Dir(filepath.Dir(dataDir)), "mods")
}

// gameSettingsModsDir reads modsDirectoryOverride from gameSettings.xml.
// Returns "" if not active or file not found.
func gameSettingsModsDir(dataDir string) string {
	gsPath := filepath.Join(filepath.Dir(filepath.Dir(dataDir)), "gameSettings.xml")
	data, err := os.ReadFile(gsPath)
	if err != nil {
		return ""
	}
	type override struct {
		Active    string `xml:"active,attr"`
		Directory string `xml:"directory,attr"`
	}
	type gameSettings struct {
		Override override `xml:"modsDirectoryOverride"`
	}
	var gs gameSettings
	if err := xml.Unmarshal(data, &gs); err != nil {
		return ""
	}
	if gs.Override.Active == "true" && gs.Override.Directory != "" {
		return gs.Override.Directory
	}
	return ""
}

// resolveModsDir returns the effective mods directory.
// Priority: manual setting > gameSettings.xml override (if active) > default.
func resolveModsDir(manualMods, dataDir string) string {
	if manualMods != "" {
		return manualMods
	}
	if d := gameSettingsModsDir(dataDir); d != "" {
		return d
	}
	return defaultModsDir(dataDir)
}

// watchSavegameChange watches fields.json for savegame ID changes and reloads
// AD icons with the then-current mods directory when a change is detected.
func watchSavegameChange(dataDir, manualMods string, adIcons *adIconCache) {
	fieldsPath := filepath.Join(dataDir, "fields.json")
	currentID := ""
	// Initial load
	modsDir := resolveModsDir(manualMods, dataDir)
	adIcons.load(modsDir)
	for {
		time.Sleep(5 * time.Second)
		data, err := os.ReadFile(fieldsPath)
		if err != nil {
			continue
		}
		var obj struct {
			SavegameId string `json:"savegameId"`
		}
		if err := json.Unmarshal(data, &obj); err != nil || obj.SavegameId == "" {
			continue
		}
		if obj.SavegameId == currentID {
			continue
		}
		currentID = obj.SavegameId
		newModsDir := resolveModsDir(manualMods, dataDir)
		log.Printf("[ad-icons] savegame changed (%s) → reloading icons from %s", obj.SavegameId, newModsDir)
		adIcons.reload(newModsDir)
	}
}

// readZipEntry reads a file from an open zip.ReadCloser by lowercase name match.
func readZipEntry(zr *zip.ReadCloser, name string) ([]byte, error) {
	lower := strings.ToLower(name)
	for _, f := range zr.File {
		if strings.ToLower(f.Name) == lower {
			rc, err := f.Open()
			if err != nil {
				return nil, err
			}
			defer rc.Close()
			return io.ReadAll(rc)
		}
	}
	return nil, fmt.Errorf("%q not found in zip", name)
}

// parseADGuiXML parses ad_gui.xml and returns a map of slice name → image.Rectangle.
// UV format in the XML: "Xpx Ypx Wpx Hpx"
func parseADGuiXML(data []byte) (map[string]image.Rectangle, error) {
	type Slice struct {
		ID  string `xml:"id,attr"`
		UVs string `xml:"uvs,attr"`
	}
	type Root struct {
		Slices []Slice `xml:"slices>slice"`
	}
	var root Root
	if err := xml.Unmarshal(data, &root); err != nil {
		return nil, err
	}
	result := make(map[string]image.Rectangle, len(root.Slices))
	for _, s := range root.Slices {
		clean := strings.ReplaceAll(s.UVs, "px", "")
		parts := strings.Fields(clean)
		if len(parts) != 4 {
			continue
		}
		vals := [4]int{}
		ok := true
		for i, p := range parts {
			n, err := strconv.Atoi(strings.TrimSpace(p))
			if err != nil {
				ok = false
				break
			}
			vals[i] = n
		}
		if ok {
			result[s.ID] = image.Rect(vals[0], vals[1], vals[0]+vals[2], vals[1]+vals[3])
		}
	}
	return result, nil
}

func (c *adIconCache) load(modsDir string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.loaded {
		return
	}
	c.loaded = true

	zipPath := filepath.Join(modsDir, "FS25_AutoDrive.zip")
	zr, err := zip.OpenReader(zipPath)
	if err != nil {
		log.Printf("[ad-icons] FS25_AutoDrive.zip not found (%v)", err)
		return
	}
	defer zr.Close()

	xmlData, err := readZipEntry(zr, "textures/ad_gui.xml")
	if err != nil {
		log.Printf("[ad-icons] textures/ad_gui.xml: %v", err)
		return
	}
	ddsData, err := readZipEntry(zr, "textures/ad_gui.dds")
	if err != nil {
		log.Printf("[ad-icons] textures/ad_gui.dds: %v", err)
		return
	}

	sheet, err := decodeDDS(ddsData)
	if err != nil {
		log.Printf("[ad-icons] decode ad_gui.dds: %v", err)
		return
	}

	slices, err := parseADGuiXML(xmlData)
	if err != nil {
		log.Printf("[ad-icons] parse ad_gui.xml: %v", err)
		return
	}

	for name, rect := range slices {
		cropped := image.NewRGBA(image.Rect(0, 0, rect.Dx(), rect.Dy()))
		draw.Draw(cropped, cropped.Bounds(), sheet, rect.Min, draw.Src)
		replaceADGreen(cropped)
		var buf bytes.Buffer
		if err := png.Encode(&buf, cropped); err == nil {
			c.icons[name] = buf.Bytes()
		}
	}
	log.Printf("[ad-icons] %d icons cached from FS25_AutoDrive.zip", len(c.icons))
}

// replaceADGreen replaces the FS25 green in AutoDrive icons with the AD brand green (#14bf6c).
// Green-dominant pixels (G > R+25, G > B+25, G > 80) are remapped to rgb(20,191,108),
// scaled by the original G channel to preserve brightness variation.
func replaceADGreen(img *image.RGBA) {
	b := img.Bounds()
	for y := b.Min.Y; y < b.Max.Y; y++ {
		for x := b.Min.X; x < b.Max.X; x++ {
			c := img.RGBAAt(x, y)
			if c.A < 10 {
				continue
			}
			r, g, bv := int(c.R), int(c.G), int(c.B)
			if g > r+25 && g > bv+25 && g > 80 {
				img.SetRGBA(x, y, color.RGBA{R: 20, G: 191, B: 108, A: c.A})
			}
		}
	}
}

func (c *adIconCache) get(name string) []byte {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.icons[name]
}

func handleADIcons(cache *adIconCache) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		name := r.PathValue("name")
		data := cache.get(name)
		if data == nil {
			http.NotFound(w, r)
			return
		}
		sum := sha256.Sum256(data)
		etag := fmt.Sprintf(`"%x"`, sum[:8])
		w.Header().Set("Content-Type", "image/png")
		w.Header().Set("Cache-Control", "no-cache")
		w.Header().Set("ETag", etag)
		if r.Header.Get("If-None-Match") == etag {
			w.WriteHeader(http.StatusNotModified)
			return
		}
		w.Write(data)
	}
}

func handleADIconsPreview(cache *adIconCache) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		cache.mu.Lock()
		names := make([]string, 0, len(cache.icons))
		for k := range cache.icons {
			names = append(names, k)
		}
		cache.mu.Unlock()
		sort.Strings(names)
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		fmt.Fprintf(w, `<!DOCTYPE html><html><head><meta charset="utf-8"><title>AD Icons Preview</title>
<style>body{background:#111;color:#eee;font-family:monospace;padding:20px}
.grid{display:flex;flex-wrap:wrap;gap:12px}
.item{display:flex;flex-direction:column;align-items:center;gap:4px;background:#1e1e1e;padding:8px;border-radius:6px;width:100px}
.item img{width:48px;height:48px;image-rendering:pixelated}
.item span{font-size:9px;color:#888;word-break:break-all;text-align:center}
</style></head><body>
<h2 style="color:#14bf6c">AD Icons (%d) — green replaced with #14bf6c</h2>
<div class="grid">`, len(names))
		ts := time.Now().Unix()
		for _, name := range names {
			fmt.Fprintf(w, `<div class="item"><img src="/api/ad-icons/%s?v=%d"><span>%s</span></div>`, name, ts, name)
		}
		fmt.Fprintf(w, `</div></body></html>`)
	}
}

func handleVehicles(dataDir string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Cache-Control", "no-store")
		data, err := os.ReadFile(filepath.Join(dataDir, "vehicles.json"))
		if err != nil {
			w.Write([]byte("null"))
			return
		}
		w.Write(data)
	}
}

func handleVehicleEvents(b *broker) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		flusher, ok := w.(http.Flusher)
		if !ok {
			http.Error(w, "SSE not supported", http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "text/event-stream")
		w.Header().Set("Cache-Control", "no-cache")
		w.Header().Set("Connection", "keep-alive")
		w.Header().Set("Access-Control-Allow-Origin", "*")
		fmt.Fprintf(w, "data: connected\n\n")
		flusher.Flush()
		ch := b.subscribe()
		defer b.unsubscribe(ch)
		for {
			select {
			case <-ch:
				fmt.Fprintf(w, "data: update\n\n")
				flusher.Flush()
			case <-r.Context().Done():
				return
			}
		}
	}
}

func handleMapOverview(cache *mapCache) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		data := cache.getPNG()
		if data == nil {
			http.Error(w, "overview not available yet", http.StatusNotFound)
			return
		}
		w.Header().Set("Content-Type", "image/png")
		w.Header().Set("Cache-Control", "public, max-age=300")
		w.Write(data)
	}
}

func handleMapHeightmap(dataDir string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		metaPath := filepath.Join(dataDir, "mapMeta.json")
		raw, err := os.ReadFile(metaPath)
		if err != nil {
			http.Error(w, "mapMeta.json not found", http.StatusNotFound)
			return
		}
		var meta struct {
			SavegameDir string `json:"savegameDir"`
		}
		if err := json.Unmarshal(raw, &meta); err != nil || meta.SavegameDir == "" {
			http.Error(w, "savegameDir not set", http.StatusNotFound)
			return
		}
		hmPath := filepath.Join(meta.SavegameDir, "terrain.heightmap.png")
		data, err := os.ReadFile(hmPath)
		if err != nil {
			http.Error(w, "heightmap not found", http.StatusNotFound)
			return
		}
		w.Header().Set("Content-Type", "image/png")
		w.Header().Set("Cache-Control", "public, max-age=60")
		w.Write(data)
	}
}

var validLayers = map[string]bool{
	"weed": true, "stone": true, "plow": true,
	"spray": true, "lime": true, "mulch": true, "roller": true,
}

func handleMapLayer(dataDir string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		name := r.PathValue("name")
		if !validLayers[name] {
			http.Error(w, "unknown layer", http.StatusNotFound)
			return
		}
		data, err := os.ReadFile(filepath.Join(dataDir, "layer_"+name+".json"))
		if err != nil {
			http.Error(w, "layer not available", http.StatusNotFound)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "public, max-age=55")
		w.Write(data)
	}
}

var iconVer = fmt.Sprintf("%d", time.Now().Unix())

func handleDashboard(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	data, err := staticFiles.ReadFile("static/dashboard.html")
	if err != nil {
		http.Error(w, "dashboard not found", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	html := strings.Replace(string(data), "</head>",
		fmt.Sprintf(`<script>window._adIconVer="%s";</script></head>`, iconVer), 1)
	w.Write([]byte(html))
}

func handleData(dataDir string) http.HandlerFunc {
	type payload struct {
		Silos       json.RawMessage `json:"silos"`
		Productions json.RawMessage `json:"productions"`
		Husbandries json.RawMessage `json:"husbandries"`
		FillTypes   json.RawMessage `json:"fillTypes"`
		AnimalFood  json.RawMessage `json:"animalFood"`
		Goods       json.RawMessage `json:"goods"`
		Fields      json.RawMessage `json:"fields"`
		FruitTypes  json.RawMessage `json:"fruitTypes"`
		MapMeta     json.RawMessage `json:"mapMeta"`
		Hotspots    json.RawMessage `json:"hotspots"`
		Vehicles          json.RawMessage `json:"vehicles"`
		VehicleMeta       json.RawMessage `json:"vehicleMeta"`
		VehicleCategories json.RawMessage `json:"vehicleCategories"`
		AutoDriveMarkers  json.RawMessage `json:"autoDriveMarkers"`
		ModInfo           json.RawMessage `json:"modInfo"`
		Weather           json.RawMessage `json:"weather"`
		ServerVersion     string          `json:"serverVersion"`
	}

	readFile := func(name string) json.RawMessage {
		data, err := os.ReadFile(filepath.Join(dataDir, name))
		if err != nil {
			return json.RawMessage("null")
		}
		return json.RawMessage(data)
	}

	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Access-Control-Allow-Origin", "*")
		json.NewEncoder(w).Encode(payload{
			Silos:       readFile("silos.json"),
			Productions: readFile("productions.json"),
			Husbandries: readFile("husbandries.json"),
			FillTypes:   readFile("fillTypes.json"),
			AnimalFood:  readFile("animalFood.json"),
			Goods:       readFile("goods.json"),
			Fields:      readFile("fields.json"),
			FruitTypes:  readFile("fruitTypes.json"),
			MapMeta:     readFile("mapMeta.json"),
			Hotspots:    readFile("hotspots.json"),
			Vehicles:          readFile("vehicles.json"),
			VehicleMeta:       readFile("vehicleMeta.json"),
			VehicleCategories: readFile("vehicleCategories.json"),
			AutoDriveMarkers:  readFile("autoDriveMarkers.json"),
			ModInfo:           readFile("modInfo.json"),
			Weather:           readFile("weather.json"),
			ServerVersion:     serverVersion,
		})
	}
}

func handleEvents(b *broker) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		flusher, ok := w.(http.Flusher)
		if !ok {
			http.Error(w, "SSE not supported", http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "text/event-stream")
		w.Header().Set("Cache-Control", "no-cache")
		w.Header().Set("Connection", "keep-alive")
		w.Header().Set("Access-Control-Allow-Origin", "*")

		// Send an initial ping so the client knows it's connected.
		fmt.Fprintf(w, "data: connected\n\n")
		flusher.Flush()

		ch := b.subscribe()
		defer b.unsubscribe(ch)

		for {
			select {
			case <-ch:
				fmt.Fprintf(w, "data: update\n\n")
				flusher.Flush()
			case <-r.Context().Done():
				return
			}
		}
	}
}

// ---------------------------------------------------------------------------
// Startup settings
// ---------------------------------------------------------------------------

type serverConfig struct {
	Port *int    `json:"port,omitempty"`
	Host *string `json:"host,omitempty"`
	Data *string `json:"data,omitempty"`
	Mods *string `json:"mods,omitempty"`
}

type settingsFile struct {
	Server *serverConfig `json:"server,omitempty"`
}

func loadStartupSettings() settingsFile {
	data, err := os.ReadFile(settingsPath())
	if err != nil {
		return settingsFile{}
	}
	var s settingsFile
	json.Unmarshal(data, &s)
	return s
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

func defaultDataDir() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	switch runtime.GOOS {
	case "darwin":
		return filepath.Join(home, "Library", "Application Support", "FarmingSimulator2025", "modSettings", "FS25_FarmMonitor")
	case "windows":
		return filepath.Join(home, "Documents", "My Games", "FarmingSimulator2025", "modSettings", "FS25_FarmMonitor")
	default:
		return filepath.Join(home, ".local", "share", "FarmingSimulator2025", "modSettings", "FS25_FarmMonitor")
	}
}

func main() {
	port := flag.Int("port", 8080, "HTTP port")
	host := flag.String("host", "127.0.0.1", "Listen address (use 0.0.0.0 for LAN access)")
	data := flag.String("data", "", "Path to the directory containing the JSON data files (default: auto-detect from modSettings)")
	mods := flag.String("mods", "", "Path to the FS25 mods directory (default: auto-derive from data path)")
	flag.Parse()

	// Apply saved settings for any flag not explicitly set via CLI.
	explicit := map[string]bool{}
	flag.Visit(func(f *flag.Flag) { explicit[f.Name] = true })
	if s := loadStartupSettings(); s.Server != nil {
		if !explicit["port"] && s.Server.Port != nil {
			*port = *s.Server.Port
		}
		if !explicit["host"] && s.Server.Host != nil {
			*host = *s.Server.Host
		}
		if !explicit["data"] && s.Server.Data != nil && *s.Server.Data != "" {
			*data = *s.Server.Data
		}
		if !explicit["mods"] && s.Server.Mods != nil && *s.Server.Mods != "" {
			*mods = *s.Server.Mods
		}
	}

	dataDir := *data
	if dataDir == "" {
		dataDir = defaultDataDir()
	}
	if dataDir == "" {
		log.Fatal("Cannot determine data directory. Use -data to specify it manually.")
	}

	// Slow-changing files: 2s poll interval
	slowFiles := []string{
		filepath.Join(dataDir, "silos.json"),
		filepath.Join(dataDir, "productions.json"),
		filepath.Join(dataDir, "husbandries.json"),
		filepath.Join(dataDir, "fillTypes.json"),
		filepath.Join(dataDir, "animalFood.json"),
		filepath.Join(dataDir, "goods.json"),
		filepath.Join(dataDir, "fields.json"),
		filepath.Join(dataDir, "fruitTypes.json"),
		filepath.Join(dataDir, "mapMeta.json"),
		filepath.Join(dataDir, "hotspots.json"),
		filepath.Join(dataDir, "vehicleMeta.json"),
		filepath.Join(dataDir, "vehicleCategories.json"),
		filepath.Join(dataDir, "autoDriveMarkers.json"),
		filepath.Join(dataDir, "modInfo.json"),
		filepath.Join(dataDir, "weather.json"),
	}

	b := newBroker()
	go watchFiles(slowFiles, 2*time.Second, b)

	// Fast-changing file: 500ms poll interval
	vb := newBroker()
	go watchFiles([]string{filepath.Join(dataDir, "vehicles.json")}, 500*time.Millisecond, vb)

	mc := newMapCache()
	go watchAndRebuildMap(filepath.Join(dataDir, "mapMeta.json"), mc)

	adIcons := newADIconCache()
	go watchSavegameChange(dataDir, *mods, adIcons)


	staticFS, err := fs.Sub(staticFiles, "static")
	if err != nil {
		log.Fatalf("failed to create static sub-fs: %v", err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/", handleDashboard)
	mux.Handle("/lib/", http.FileServer(http.FS(staticFS)))
	mux.Handle("/i18n/", http.FileServer(http.FS(staticFS)))
	mux.HandleFunc("/api/data", handleData(dataDir))
	mux.HandleFunc("/api/events", handleEvents(b))
	mux.HandleFunc("/api/vehicles", handleVehicles(dataDir))
	mux.HandleFunc("/api/vehicle-events", handleVehicleEvents(vb))
	mux.HandleFunc("/api/settings", handleSettings())
	mux.HandleFunc("/api/savegame/{savegameId}", handleSavegame())
	mux.HandleFunc("/api/command", handleCommand(dataDir))
	soilPres := newSoilPresence(dataDir)
	mux.HandleFunc("/api/soil/presence", soilPres.handler())
	mux.HandleFunc("/api/map/overview", handleMapOverview(mc))
	mux.HandleFunc("/api/map/heightmap", handleMapHeightmap(dataDir))
	mux.HandleFunc("/api/map/layer/{name}", handleMapLayer(dataDir))
	mux.HandleFunc("/api/ad-icons/{name}", handleADIcons(adIcons))
	mux.HandleFunc("/api/ad-icons-preview", handleADIconsPreview(adIcons))
	mux.HandleFunc("/api/mod-config", handleModConfig(dataDir))
	mux.HandleFunc("/api/perf-export", handlePerfExport(dataDir))

	fmt.Print(`
▄▖▄▖▄▖▄▖  ▄▖       ▖  ▖    ▘▗       ▄▖
▙▖▚ ▄▌▙▖  ▙▖▀▌▛▘▛▛▌▛▖▞▌▛▌▛▌▌▜▘▛▌▛▘  ▚ █▌▛▘▌▌█▌▛▘
▌ ▄▌▙▖▄▌  ▌ █▌▌ ▌▌▌▌▝ ▌▙▌▌▌▌▐▖▙▌▌   ▄▌▙▖▌ ▚▘▙▖▌

`)
	printLink := func(url, label string) {
		fmt.Printf("  \033]8;;%s\033\\%s\033]8;;\033\\  %s\n", url, url, label)
	}
	fmt.Println("─────────────────────────────────────────")
	fmt.Println("FarmMonitor Dashboard available at:")
	printLink(fmt.Sprintf("http://localhost:%d", *port), "")
	if ifaces, err := net.Interfaces(); err == nil {
		for _, iface := range ifaces {
			if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
				continue
			}
			addrs, _ := iface.Addrs()
			for _, a := range addrs {
				var ip net.IP
				switch v := a.(type) {
				case *net.IPNet:
					ip = v.IP
				case *net.IPAddr:
					ip = v.IP
				}
				if ip == nil || ip.IsLoopback() || ip.To4() == nil {
					continue
				}
				printLink(fmt.Sprintf("http://%s:%d", ip, *port), fmt.Sprintf("(%s)", iface.Name))
			}
		}
	}
	fmt.Println("─────────────────────────────────────────")
	fmt.Println()

	addr := fmt.Sprintf("%s:%d", *host, *port)
	log.Printf("Settings: %s", settingsPath())
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatal(err)
	}
}
