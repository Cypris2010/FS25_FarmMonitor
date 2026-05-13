package main

import (
	"archive/zip"
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"encoding/json"
	_ "embed"
	"flag"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"
)

// set once in main from -game flag or auto-detection
var gameDataDir string

//go:embed dashboard.html
var dashboardHTML []byte

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

func watchFiles(files []string, b *broker) {
	modTimes := make(map[string]time.Time, len(files))
	for _, f := range files {
		if info, err := os.Stat(f); err == nil {
			modTimes[f] = info.ModTime()
		}
	}

	for range time.Tick(2 * time.Second) {
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

func handleDashboard(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Write(dashboardHTML)
}

func handleData(dataDir string) http.HandlerFunc {
	type payload struct {
		Silos       json.RawMessage `json:"silos"`
		Productions json.RawMessage `json:"productions"`
		Husbandries json.RawMessage `json:"husbandries"`
		FillTypes   json.RawMessage `json:"fillTypes"`
		AnimalFood  json.RawMessage `json:"animalFood"`
		Goods       json.RawMessage `json:"goods"`
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
// DDS decoder (DXT1 / DXT5)
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
	if imgW <= 0 || imgH <= 0 || imgW > 4096 || imgH > 4096 {
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
		if dxgi != 98 && dxgi != 99 { // BC7_UNORM / BC7_UNORM_SRGB
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
// Icon cache
// ---------------------------------------------------------------------------

type iconCache struct {
	mu   sync.RWMutex
	data map[string][]byte // fill type name (uppercase) → PNG bytes
}

func newIconCache() *iconCache {
	return &iconCache{data: make(map[string][]byte)}
}

func (c *iconCache) get(name string) ([]byte, bool) {
	c.mu.RLock()
	defer c.mu.RUnlock()
	v, ok := c.data[strings.ToUpper(name)]
	return v, ok
}

func (c *iconCache) rebuild(fillTypesPath string) {
	raw, err := os.ReadFile(fillTypesPath)
	if err != nil {
		return
	}
	var parsed struct {
		FillTypes []struct {
			Name               string `json:"name"`
			HudOverlayFilename string `json:"hudOverlayFilename"`
		} `json:"fillTypes"`
	}
	if err := json.Unmarshal(raw, &parsed); err != nil {
		log.Printf("[icons] parse error: %v", err)
		return
	}
	next := make(map[string][]byte, len(parsed.FillTypes))
	for _, ft := range parsed.FillTypes {
		if ft.HudOverlayFilename == "" {
			continue
		}
		pngData, err := hudPathToPNG(ft.HudOverlayFilename)
		if err != nil {
			log.Printf("[icons] %s: %v", ft.Name, err)
			continue
		}
		next[ft.Name] = pngData
	}
	c.mu.Lock()
	c.data = next
	c.mu.Unlock()
	log.Printf("[icons] rebuilt: %d icons loaded", len(next))
}

func hudPathToPNG(hudPath string) ([]byte, error) {
	fileData, err := readHudFile(hudPath)
	if err != nil {
		return nil, err
	}
	// Detect format by magic bytes, not extension (Lua sometimes reports wrong extension).
	if len(fileData) >= 4 && string(fileData[0:4]) == "\x89PNG" {
		return fileData, nil
	}
	img, err := decodeDDS(fileData)
	if err != nil {
		return nil, fmt.Errorf("DDS decode: %w", err)
	}
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

// readHudFile loads raw bytes for a hudOverlayFilename path.
// Handles three cases:
//  1. Absolute path that exists on disk (extracted mod or vanilla)
//  2. Absolute path inside a packed mod ZIP (most common)
//  3. dataS/... relative path → resolved via FS25 install dir
func readHudFile(hudPath string) ([]byte, error) {
	if filepath.IsAbs(hudPath) {
		if data, err := os.ReadFile(hudPath); err == nil {
			return data, nil
		}
		return readFromModZip(hudPath)
	}
	if strings.HasPrefix(hudPath, "dataS/") || strings.HasPrefix(hudPath, "dataS\\") {
		base := fs25DataDir()
		if base == "" {
			return nil, fmt.Errorf("FS25 install dir not found (use -game flag): %s", hudPath)
		}
		return os.ReadFile(filepath.Join(base, filepath.FromSlash(hudPath)))
	}
	return nil, fmt.Errorf("unresolvable path: %s", hudPath)
}

// readFromModZip extracts a file from its mod's ZIP archive.
// Example: .../mods/FS25_SomeMod/textures/icon.png → opens FS25_SomeMod.zip, reads textures/icon.png.
// Also tries swapping .png ↔ .dds if the exact path is not found.
func readFromModZip(absPath string) ([]byte, error) {
	sep := string(filepath.Separator)
	modsMarker := sep + "mods" + sep
	idx := strings.Index(absPath, modsMarker)
	if idx < 0 {
		return nil, fmt.Errorf("no mods directory in path: %s", absPath)
	}
	modsDir := absPath[:idx+len(modsMarker)-1]
	rest := absPath[idx+len(modsMarker):]
	slashIdx := strings.Index(rest, sep)
	if slashIdx < 0 {
		return nil, fmt.Errorf("expected mod subdirectory in: %s", rest)
	}
	modName := rest[:slashIdx]
	innerPath := filepath.ToSlash(rest[slashIdx+1:])
	return readFromZip(filepath.Join(modsDir, modName+".zip"), innerPath)
}

func readFromZip(zipPath, innerPath string) ([]byte, error) {
	r, err := zip.OpenReader(zipPath)
	if err != nil {
		return nil, fmt.Errorf("open %s: %w", filepath.Base(zipPath), err)
	}
	defer r.Close()

	// Build alternate path: swap .png ↔ .dds in case Lua reported the wrong extension.
	altPath := innerPath
	switch strings.ToLower(filepath.Ext(innerPath)) {
	case ".png":
		altPath = innerPath[:len(innerPath)-4] + ".dds"
	case ".dds":
		altPath = innerPath[:len(innerPath)-4] + ".png"
	}

	for _, f := range r.File {
		name := filepath.ToSlash(f.Name)
		if name == innerPath || name == altPath {
			rc, err := f.Open()
			if err != nil {
				return nil, err
			}
			defer rc.Close()
			return io.ReadAll(rc)
		}
	}
	return nil, fmt.Errorf("%s not found in %s", innerPath, filepath.Base(zipPath))
}

func fs25DataDir() string {
	if gameDataDir != "" {
		return gameDataDir
	}
	switch runtime.GOOS {
	case "darwin":
		p := "/Applications/Farming Simulator 25.app/Contents/Resources"
		if _, err := os.Stat(p); err == nil {
			return p
		}
	case "windows":
		for _, p := range []string{
			`C:\Program Files (x86)\Farming Simulator 2025`,
			`C:\Program Files\Farming Simulator 2025`,
		} {
			if _, err := os.Stat(p); err == nil {
				return p
			}
		}
	}
	return ""
}

func watchAndRebuildIcons(fillTypesPath string, cache *iconCache) {
	var lastMod time.Time
	if info, err := os.Stat(fillTypesPath); err == nil {
		lastMod = info.ModTime()
		cache.rebuild(fillTypesPath)
	}
	for range time.Tick(2 * time.Second) {
		info, err := os.Stat(fillTypesPath)
		if err != nil {
			continue
		}
		if info.ModTime().After(lastMod) {
			lastMod = info.ModTime()
			go cache.rebuild(fillTypesPath)
		}
	}
}

func handleIcons(cache *iconCache) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		name := strings.TrimSuffix(r.PathValue("name"), ".png")
		data, ok := cache.get(name)
		if !ok {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "image/png")
		w.Header().Set("Cache-Control", "public, max-age=3600")
		w.Write(data)
	}
}

// ---------------------------------------------------------------------------
// Startup settings
// ---------------------------------------------------------------------------

type serverConfig struct {
	Port *int    `json:"port,omitempty"`
	Host *string `json:"host,omitempty"`
	Data *string `json:"data,omitempty"`
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
	game := flag.String("game", "", "Path to FS25 install directory (for vanilla icons, default: auto-detect)")
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
	}

	if *game != "" {
		gameDataDir = *game
	}

	dataDir := *data
	if dataDir == "" {
		dataDir = defaultDataDir()
	}
	if dataDir == "" {
		log.Fatal("Cannot determine data directory. Use -data to specify it manually.")
	}

	jsonFiles := []string{
		filepath.Join(dataDir, "silos.json"),
		filepath.Join(dataDir, "productions.json"),
		filepath.Join(dataDir, "husbandries.json"),
		filepath.Join(dataDir, "fillTypes.json"),
		filepath.Join(dataDir, "animalFood.json"),
		filepath.Join(dataDir, "goods.json"),
	}

	b := newBroker()
	go watchFiles(jsonFiles, b)

	icons := newIconCache()
	go watchAndRebuildIcons(filepath.Join(dataDir, "fillTypes.json"), icons)

	mux := http.NewServeMux()
	mux.HandleFunc("/", handleDashboard)
	mux.HandleFunc("/api/data", handleData(dataDir))
	mux.HandleFunc("/api/events", handleEvents(b))
	mux.HandleFunc("/api/settings", handleSettings())
	mux.HandleFunc("/api/savegame/{savegameId}", handleSavegame())
	mux.HandleFunc("/icons/{name}", handleIcons(icons))

	log.Printf("Settings: %s", settingsPath())

	addr := fmt.Sprintf("%s:%d", *host, *port)
	log.Printf("FarmMonitor dashboard → http://localhost:%d", *port)
	log.Printf("Data directory: %s", dataDir)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatal(err)
	}
}
