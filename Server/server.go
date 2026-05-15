package main

import (
	"crypto/sha256"
	"encoding/json"
	_ "embed"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"sync"
	"time"
)

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
		Fields      json.RawMessage `json:"fields"`
		FieldMeta   json.RawMessage `json:"fieldMeta"`
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
			FieldMeta:   readFile("fieldMeta.json"),
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

	jsonFiles := []string{
		filepath.Join(dataDir, "silos.json"),
		filepath.Join(dataDir, "productions.json"),
		filepath.Join(dataDir, "husbandries.json"),
		filepath.Join(dataDir, "fillTypes.json"),
		filepath.Join(dataDir, "animalFood.json"),
		filepath.Join(dataDir, "goods.json"),
		filepath.Join(dataDir, "fields.json"),
		filepath.Join(dataDir, "fieldMeta.json"),
	}

	b := newBroker()
	go watchFiles(jsonFiles, b)

	mux := http.NewServeMux()
	mux.HandleFunc("/", handleDashboard)
	mux.HandleFunc("/api/data", handleData(dataDir))
	mux.HandleFunc("/api/events", handleEvents(b))
	mux.HandleFunc("/api/settings", handleSettings())
	mux.HandleFunc("/api/savegame/{savegameId}", handleSavegame())

	log.Printf("Settings: %s", settingsPath())

	addr := fmt.Sprintf("%s:%d", *host, *port)
	log.Printf("FarmMonitor dashboard → http://localhost:%d", *port)
	log.Printf("Data directory: %s", dataDir)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatal(err)
	}
}
