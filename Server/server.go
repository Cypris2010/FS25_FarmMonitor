package main

import (
	"archive/zip"
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"encoding/json"
	"encoding/xml"
	_ "embed"
	"flag"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"
)

//go:embed dashboard.html
var dashboardHTML []byte

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

func handleCommand(dataDir string) http.HandlerFunc {
	type jsonCommand struct {
		ID       string `json:"id"`
		Cmd      string `json:"cmd"`
		UniqueID string `json:"uniqueId,omitempty"`
		FillType string `json:"fillType,omitempty"`
		Mode     string `json:"mode,omitempty"`
		Amount   string `json:"amount,omitempty"`
		X        string `json:"x,omitempty"`
		Y        string `json:"y,omitempty"`
		Z        string `json:"z,omitempty"`
		Marker1  string `json:"marker1,omitempty"`
		Marker2  string `json:"marker2,omitempty"`
	}
	type xmlCommand struct {
		XMLName  xml.Name `xml:"command"`
		ID       string   `xml:"id,attr"`
		Cmd      string   `xml:"cmd,attr"`
		UniqueID string   `xml:"uniqueId,attr"`
		FillType string   `xml:"fillType,attr"`
		Mode     string   `xml:"mode,attr"`
		Amount   string   `xml:"amount,attr"`
		X        string   `xml:"x,attr"`
		Y        string   `xml:"y,attr"`
		Z        string   `xml:"z,attr"`
		Marker1  string   `xml:"marker1,attr"`
		Marker2  string   `xml:"marker2,attr"`
	}
	type xmlCommands struct {
		XMLName  xml.Name     `xml:"commands"`
		Count    int          `xml:"count,attr"`
		Commands []xmlCommand `xml:"command"`
	}

	var mu sync.Mutex

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
		log.Printf("[command] received: cmd=%s uniqueId=%s mode=%s marker1=%s marker2=%s", cmd.Cmd, cmd.UniqueID, cmd.Mode, cmd.Marker1, cmd.Marker2)
		if cmd.ID == "" {
			cmd.ID = fmt.Sprintf("%d", time.Now().UnixNano())
		}

		newCmd := xmlCommand{
			ID:       cmd.ID,
			Cmd:      cmd.Cmd,
			UniqueID: cmd.UniqueID,
			FillType: cmd.FillType,
			Mode:     cmd.Mode,
			Amount:   cmd.Amount,
			X:        cmd.X,
			Y:        cmd.Y,
			Z:        cmd.Z,
			Marker1:  cmd.Marker1,
			Marker2:  cmd.Marker2,
		}

		mu.Lock()
		defer mu.Unlock()

		// Read existing commands.xml (if present) and append — prevents overwrite when
		// multiple commands arrive before Lua has had a chance to poll the file.
		cmdPath := filepath.Join(dataDir, "commands.xml")
		var allCmds []xmlCommand
		if existing, err := os.ReadFile(cmdPath); err == nil {
			var existingXML xmlCommands
			if err2 := xml.Unmarshal(existing, &existingXML); err2 == nil {
				allCmds = existingXML.Commands
			}
		}
		allCmds = append(allCmds, newCmd)

		xmlData, err := xml.MarshalIndent(xmlCommands{
			Count:    len(allCmds),
			Commands: allCmds,
		}, "", "  ")
		if err != nil {
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}

		// Write to a temp file first, then rename atomically — ensures Lua never
		// reads a partially-written file (os.Rename is atomic on POSIX).
		payload := append([]byte(xml.Header), xmlData...)
		tmpPath := cmdPath + ".tmp"
		if err := os.WriteFile(tmpPath, payload, 0644); err != nil {
			http.Error(w, "write error", http.StatusInternalServerError)
			return
		}
		if err := os.Rename(tmpPath, cmdPath); err != nil {
			_ = os.Remove(tmpPath)
			http.Error(w, "write error", http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"id": cmd.ID})
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
		Fields      json.RawMessage `json:"fields"`
		FruitTypes  json.RawMessage `json:"fruitTypes"`
		MapMeta     json.RawMessage `json:"mapMeta"`
		Hotspots    json.RawMessage `json:"hotspots"`
		Vehicles          json.RawMessage `json:"vehicles"`
		VehicleMeta       json.RawMessage `json:"vehicleMeta"`
		VehicleCategories json.RawMessage `json:"vehicleCategories"`
		AutoDriveMarkers  json.RawMessage `json:"autoDriveMarkers"`
		ModInfo           json.RawMessage `json:"modInfo"`
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
	}

	b := newBroker()
	go watchFiles(slowFiles, 2*time.Second, b)

	// Fast-changing file: 500ms poll interval
	vb := newBroker()
	go watchFiles([]string{filepath.Join(dataDir, "vehicles.json")}, 500*time.Millisecond, vb)

	mc := newMapCache()
	go watchAndRebuildMap(filepath.Join(dataDir, "mapMeta.json"), mc)

	mux := http.NewServeMux()
	mux.HandleFunc("/", handleDashboard)
	mux.HandleFunc("/api/data", handleData(dataDir))
	mux.HandleFunc("/api/events", handleEvents(b))
	mux.HandleFunc("/api/vehicles", handleVehicles(dataDir))
	mux.HandleFunc("/api/vehicle-events", handleVehicleEvents(vb))
	mux.HandleFunc("/api/settings", handleSettings())
	mux.HandleFunc("/api/savegame/{savegameId}", handleSavegame())
	mux.HandleFunc("/api/command", handleCommand(dataDir))
	mux.HandleFunc("/api/map/overview", handleMapOverview(mc))
	mux.HandleFunc("/api/map/heightmap", handleMapHeightmap(dataDir))

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
