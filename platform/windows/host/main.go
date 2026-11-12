package main

import (
	"archive/zip"
	"bytes"
	"context"
	"crypto/sha256"
	_ "embed"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"
)

//go:embed ui.html
var embeddedUI []byte

type ServerProfile struct {
	ID            string                 `json:"id"`
	DisplayName   string                 `json:"displayName"`
	Protocol      string                 `json:"protocol"`
	ServerAddress string                 `json:"serverAddress"`
	ServerPort    int                    `json:"serverPort"`
	CountryCode   string                 `json:"countryCode"`
	FlagEmoji     string                 `json:"flagEmoji"`
	CountryFa     string                 `json:"countryFa"`
	CountryEn     string                 `json:"countryEn"`
	TransportTag  string                 `json:"transportTag"`
	IsInfoNode    bool                   `json:"isInfoNode"`
	Extra         map[string]interface{} `json:"extraParams"`
}

type SubscriptionSource struct {
	ID                string `json:"id"`
	Name              string `json:"name"`
	URL               string `json:"url"`
	LastStatusMessage string `json:"lastStatusMessage"`
}

type RoutingOptions struct {
	BypassLan             bool     `json:"bypassLan"`
	BypassIranDomains     bool     `json:"bypassIranDomains"`
	CustomDirectDomains   []string `json:"customDirectDomains"`
	CustomDirectCidrs     []string `json:"customDirectCidrs"`
	RemoteDnsServer       string   `json:"remoteDnsServer"`
	DirectDnsServer       string   `json:"directDnsServer"`
	EnableTrafficSniffing bool     `json:"enableTrafficSniffing"`
	EnableMux             bool     `json:"enableMux"`
	UseTunMode            bool     `json:"useTunMode"`
}

type AppState struct {
	Phase              string               `json:"phase"`
	ConnectedSinceUnix int64                `json:"connectedSinceUnix"`
	ActiveProfileID    string               `json:"activeProfileId"`
	IsSmartMode        bool                 `json:"isSmartMode"`
	Language           string               `json:"language"`
	ThemePreset        string               `json:"themePreset"`
	LivePingMs         int                  `json:"livePingMs"`
	ProfilePings       map[string]int       `json:"profilePings"`
	PingHistory        []int                `json:"pingHistory"`
	Profiles           []ServerProfile      `json:"profiles"`
	Subscriptions      []SubscriptionSource `json:"subscriptions"`
	RoutingOptions     RoutingOptions       `json:"routingOptions"`
	ErrorMessage       string               `json:"errorMessage"`
	AppVersion         string               `json:"appVersion"`
	CoreVersion        string               `json:"coreVersion"`
	MixedPort          int                  `json:"mixedPort"`
}

var (
	mu               sync.Mutex
	state            AppState
	singboxCmd       *exec.Cmd
	activeCfg        string
	storagePath      string
	tunnelGeneration int
	proxyMu          sync.Mutex
	proxyManaged     bool
	proxySaved       *proxySnapshot
)

type proxySnapshot struct {
	enable            string
	enablePresent     bool
	server            string
	serverPresent     bool
	autoConfig        string
	autoConfigPresent bool
}

func initDefaultState() {
	appData := os.Getenv("LOCALAPPDATA")
	if appData == "" {
		home, _ := os.UserHomeDir()
		appData = filepath.Join(home, ".config")
	}
	dir := filepath.Join(appData, "SpeedllConnect")
	_ = os.MkdirAll(dir, 0755)
	storagePath = filepath.Join(dir, "desktop_state_v1.json")

	state = AppState{
		Phase:         "disconnected",
		IsSmartMode:   false,
		Language:      "fa",
		ThemePreset:   "royalPurple",
		LivePingMs:    0,
		ProfilePings:  make(map[string]int),
		PingHistory:   []int{},
		Profiles:      []ServerProfile{},
		Subscriptions: []SubscriptionSource{},
		RoutingOptions: RoutingOptions{
			BypassLan:             true,
			BypassIranDomains:     true,
			CustomDirectDomains:   []string{},
			CustomDirectCidrs:     []string{},
			RemoteDnsServer:       "1.1.1.1",
			DirectDnsServer:       "8.8.8.8",
			EnableTrafficSniffing: true,
			EnableMux:             false,
			UseTunMode:            false,
		},
		AppVersion:  "1.4.0 (Build 9)",
		CoreVersion: "sing-box v1.14.4",
		MixedPort:   2080,
	}

	raw, err := os.ReadFile(storagePath)
	if err == nil && len(raw) > 0 {
		var loaded AppState
		if json.Unmarshal(raw, &loaded) == nil {
			loaded.Phase = "disconnected"
			loaded.ConnectedSinceUnix = 0
			loaded.ErrorMessage = ""
			if loaded.ProfilePings == nil {
				loaded.ProfilePings = make(map[string]int)
			}
			if loaded.RoutingOptions.RemoteDnsServer == "" {
				loaded.RoutingOptions.RemoteDnsServer = "1.1.1.1"
			}
			if loaded.RoutingOptions.DirectDnsServer == "" {
				loaded.RoutingOptions.DirectDnsServer = "8.8.8.8"
			}
			if loaded.MixedPort <= 0 || loaded.MixedPort > 65535 {
				loaded.MixedPort = 2080
			}
			loaded.AppVersion = "1.4.0 (Build 9)"
			loaded.CoreVersion = "sing-box v1.14.4"
			state = loaded
		}
	}
}

func saveStateLocked() {
	raw, err := json.MarshalIndent(state, "", "  ")
	if err == nil && storagePath != "" {
		_ = os.WriteFile(storagePath, raw, 0600)
	}
}

func stableHash(input string) string {
	var h uint32 = 0x811c9dc5
	for i := 0; i < len(input); i++ {
		h ^= uint32(input[i])
		h *= 0x01000193
	}
	return fmt.Sprintf("%08x", h)
}

func resolveCountry(name, host string) (string, string, string, string) {
	combined := strings.ToLower(name + " " + host)
	type cEntry struct {
		code, emoji, fa, en string
		keys                []string
	}
	entries := []cEntry{
		{"DE", "🇩🇪", "آلمان", "Germany", []string{"🇩🇪", "آلمان", "germany", "falkenstein", "hetzner", "frankfurt", "de-", ".de"}},
		{"TR", "🇹🇷", "ترکیه", "Turkey", []string{"🇹🇷", "ترکیه", "turkey", "istanbul", "tr-", ".tr"}},
		{"NL", "🇳🇱", "هلند", "Netherlands", []string{"🇳🇱", "هلند", "netherlands", "amsterdam", "nl-", ".nl"}},
		{"FR", "🇫🇷", "فرانسه", "France", []string{"🇫🇷", "فرانسه", "france", "paris", "fr-", ".fr"}},
		{"GB", "🇬🇧", "انگلیس", "United Kingdom", []string{"🇬🇧", "انگلیس", "بریتانیا", "england", "london", "uk-", "gb-"}},
		{"US", "🇺🇸", "آمریکا", "United States", []string{"🇺🇸", "آمریکا", "امریکا", "usa", "united states", "us-"}},
		{"FI", "🇫🇮", "فنلاند", "Finland", []string{"🇫🇮", "فنلاند", "finland", "helsinki", "fi-"}},
		{"SE", "🇸🇪", "سوئد", "Sweden", []string{"🇸🇪", "سوئد", "sweden", "stockholm", "se-"}},
		{"AE", "🇦🇪", "امارات", "UAE", []string{"🇦🇪", "امارات", "دبی", "dubai", "uae", "ae-"}},
		{"CA", "🇨🇦", "کانادا", "Canada", []string{"🇨🇦", "کانادا", "canada", "toronto", "ca-"}},
		{"SG", "🇸🇬", "سنگاپور", "Singapore", []string{"🇸🇬", "سنگاپور", "singapore", "sg-"}},
		{"JP", "🇯🇵", "ژاپن", "Japan", []string{"🇯🇵", "ژاپن", "japan", "tokyo", "jp-"}},
		{"CH", "🇨🇭", "سوئیس", "Switzerland", []string{"🇨🇭", "سوئیس", "switzerland", "zurich", "ch-"}},
		{"AT", "🇦🇹", "اتریش", "Austria", []string{"🇦🇹", "اتریش", "austria", "vienna", "at-"}},
		{"PL", "🇵🇱", "لهستان", "Poland", []string{"🇵🇱", "لهستان", "poland", "warsaw", "pl-"}},
		{"RU", "🇷🇺", "روسیه", "Russia", []string{"🇷🇺", "روسیه", "russia", "moscow", "ru-"}},
	}
	for _, e := range entries {
		for _, k := range e.keys {
			if strings.Contains(combined, k) {
				return e.code, e.emoji, e.fa, e.en
			}
		}
	}
	return "UN", "🌐", "سرور جهانی", "Global Server"
}

func isInfoNode(host string, port int, uuid string) bool {
	h := strings.ToLower(strings.TrimSpace(host))
	if h == "" || h == "127.0.0.1" || h == "0.0.0.0" || h == "localhost" || h == "::1" || h == "1.1.1.1" || h == "8.8.8.8" || port <= 5 {
		return true
	}
	if uuid == "00000000-0000-0000-0000-000000000000" {
		return true
	}
	return false
}

func buildTransportSummary(proto string, extra map[string]interface{}) string {
	parts := []string{strings.ToUpper(proto)}
	if t, ok := extra["type"].(string); ok && t != "" && strings.ToLower(t) != "tcp" {
		parts = append(parts, strings.ToUpper(t))
	}
	if s, ok := extra["security"].(string); ok && s != "" && strings.ToLower(s) != "none" {
		parts = append(parts, strings.ToUpper(s))
	}
	return strings.Join(parts, " · ")
}

func parseSingleURI(rawLine string) (*ServerProfile, bool) {
	line := strings.TrimSpace(rawLine)
	if line == "" || strings.HasPrefix(line, "#") || strings.HasPrefix(line, "//") {
		return nil, false
	}
	lower := strings.ToLower(line)

	// VMess base64 JSON
	if strings.HasPrefix(lower, "vmess://") && !strings.Contains(line, "@") {
		b64 := strings.TrimSpace(line[8:])
		if idx := strings.Index(b64, "#"); idx >= 0 {
			b64 = b64[:idx]
		}
		b64 = strings.ReplaceAll(strings.ReplaceAll(b64, "-", "+"), "_", "/")
		if rem := len(b64) % 4; rem != 0 {
			b64 += strings.Repeat("=", 4-rem)
		}
		decoded, err := base64.StdEncoding.DecodeString(b64)
		if err != nil {
			return nil, false
		}
		var m map[string]interface{}
		if json.Unmarshal(decoded, &m) != nil {
			return nil, false
		}
		host := fmt.Sprintf("%v", m["add"])
		port, _ := strconv.Atoi(fmt.Sprintf("%v", m["port"]))
		if port == 0 {
			port = 443
		}
		uuid := fmt.Sprintf("%v", m["id"])
		ps := strings.TrimSpace(fmt.Sprintf("%v", m["ps"]))
		if ps == "" || ps == "<nil>" {
			ps = host
		}
		netType := fmt.Sprintf("%v", m["net"])
		if netType == "" || netType == "<nil>" {
			netType = "tcp"
		}
		tlsVal := fmt.Sprintf("%v", m["tls"])
		sec := "none"
		if tlsVal == "tls" || tlsVal == "true" {
			sec = "tls"
		}
		extra := map[string]interface{}{
			"uuid":     uuid,
			"type":     netType,
			"security": sec,
			"sni":      fmt.Sprintf("%v", m["sni"]),
			"host":     fmt.Sprintf("%v", m["host"]),
			"path":     fmt.Sprintf("%v", m["path"]),
		}
		cc, emoji, fa, en := resolveCountry(ps, host)
		info := isInfoNode(host, port, uuid)
		return &ServerProfile{
			ID:            "vmess_" + stableHash(line),
			DisplayName:   ps,
			Protocol:      "vmess",
			ServerAddress: host,
			ServerPort:    port,
			CountryCode:   cc,
			FlagEmoji:     emoji,
			CountryFa:     fa,
			CountryEn:     en,
			TransportTag:  buildTransportSummary("vmess", extra),
			IsInfoNode:    info,
			Extra:         extra,
		}, true
	}

	var proto string
	switch {
	case strings.HasPrefix(lower, "vless://"):
		proto = "vless"
	case strings.HasPrefix(lower, "trojan://"):
		proto = "trojan"
	case strings.HasPrefix(lower, "hysteria2://"), strings.HasPrefix(lower, "hy2://"):
		proto = "hysteria2"
	case strings.HasPrefix(lower, "ss://"):
		proto = "shadowsocks"
	default:
		return nil, false
	}

	var remark string
	beforeFrag := line
	if hashIdx := strings.Index(line, "#"); hashIdx >= 0 {
		beforeFrag = line[:hashIdx]
		rawFrag := line[hashIdx+1:]
		if unescaped, err := url.QueryUnescape(rawFrag); err == nil {
			remark = strings.TrimSpace(unescaped)
		} else {
			remark = strings.TrimSpace(rawFrag)
		}
	}

	u, err := url.Parse(beforeFrag)
	if err != nil || u.Hostname() == "" {
		return nil, false
	}
	host := u.Hostname()
	port, _ := strconv.Atoi(u.Port())
	if port <= 0 {
		port = 443
	}
	if remark == "" {
		remark = host
	}

	userInfo := u.User.Username()
	if unescaped, err := url.QueryUnescape(userInfo); err == nil && unescaped != "" {
		userInfo = unescaped
	}

	q := u.Query()
	extra := map[string]interface{}{}
	for k, vals := range q {
		if len(vals) > 0 {
			extra[k] = vals[0]
		}
	}

	switch proto {
	case "vless":
		extra["uuid"] = userInfo
	case "trojan":
		extra["password"] = userInfo
		if _, ok := extra["security"]; !ok {
			extra["security"] = "tls"
		}
	case "hysteria2":
		extra["auth"] = userInfo
		extra["security"] = "tls"
	case "shadowsocks":
		decodedUser := userInfo
		if !strings.Contains(decodedUser, ":") {
			b64 := strings.ReplaceAll(strings.ReplaceAll(decodedUser, "-", "+"), "_", "/")
			if rem := len(b64) % 4; rem != 0 {
				b64 += strings.Repeat("=", 4-rem)
			}
			if raw, err := base64.StdEncoding.DecodeString(b64); err == nil {
				decodedUser = string(raw)
			}
		}
		if colon := strings.Index(decodedUser, ":"); colon > 0 {
			extra["method"] = decodedUser[:colon]
			extra["password"] = decodedUser[colon+1:]
		}
	}

	cc, emoji, fa, en := resolveCountry(remark, host)
	info := isInfoNode(host, port, userInfo)
	return &ServerProfile{
		ID:            proto + "_" + stableHash(line),
		DisplayName:   remark,
		Protocol:      proto,
		ServerAddress: host,
		ServerPort:    port,
		CountryCode:   cc,
		FlagEmoji:     emoji,
		CountryFa:     fa,
		CountryEn:     en,
		TransportTag:  buildTransportSummary(proto, extra),
		IsInfoNode:    info,
		Extra:         extra,
	}, true
}

func parseSubscriptionPayload(payload string) []ServerProfile {
	trimmed := strings.TrimSpace(payload)
	if trimmed == "" {
		return nil
	}

	// Try direct multiline first
	lines := strings.Split(strings.ReplaceAll(trimmed, "\r\n", "\n"), "\n")
	var results []ServerProfile
	for _, l := range lines {
		if p, ok := parseSingleURI(l); ok {
			results = append(results, *p)
		}
	}
	if len(results) > 0 {
		return results
	}

	// Try Base64 decoding
	var b64Builder strings.Builder
	for _, l := range lines {
		s := strings.TrimSpace(l)
		if s == "" || strings.HasPrefix(s, "#") || strings.HasPrefix(s, "//") {
			continue
		}
		b64Builder.WriteString(s)
	}
	b64 := strings.ReplaceAll(strings.ReplaceAll(b64Builder.String(), "-", "+"), "_", "/")
	if rem := len(b64) % 4; rem != 0 {
		b64 += strings.Repeat("=", 4-rem)
	}
	if decoded, err := base64.StdEncoding.DecodeString(b64); err == nil {
		decLines := strings.Split(strings.ReplaceAll(string(decoded), "\r\n", "\n"), "\n")
		for _, l := range decLines {
			if p, ok := parseSingleURI(l); ok {
				results = append(results, *p)
			}
		}
	}
	return results
}

func measureSinglePing(p ServerProfile) int {
	if p.IsInfoNode || p.ServerAddress == "" || p.ServerPort <= 0 {
		return -1
	}
	addr := net.JoinHostPort(p.ServerAddress, strconv.Itoa(p.ServerPort))
	start := time.Now()
	conn, err := net.DialTimeout("tcp", addr, 1400*time.Millisecond)
	if err != nil {
		return -1
	}
	_ = conn.Close()
	ms := int(time.Since(start).Milliseconds())
	if ms <= 0 {
		ms = 1
	}
	return ms
}

func pingAllProfilesParallel() map[string]int {
	mu.Lock()
	profiles := append([]ServerProfile(nil), state.Profiles...)
	mu.Unlock()

	results := make(map[string]int)
	var resMu sync.Mutex
	var wg sync.WaitGroup
	sem := make(chan struct{}, 32)

	for _, p := range profiles {
		if p.IsInfoNode {
			continue
		}
		wg.Add(1)
		go func(prof ServerProfile) {
			defer wg.Done()
			sem <- struct{}{}
			ms := measureSinglePing(prof)
			<-sem
			resMu.Lock()
			results[prof.ID] = ms
			resMu.Unlock()
		}(p)
	}
	wg.Wait()

	mu.Lock()
	for k, v := range results {
		state.ProfilePings[k] = v
	}
	if state.IsSmartMode {
		if best := pickBestProfileLocked(); best != nil {
			state.ActiveProfileID = best.ID
		}
	}
	if ping, ok := state.ProfilePings[state.ActiveProfileID]; ok {
		state.LivePingMs = ping
		if ping > 0 {
			state.PingHistory = append(state.PingHistory, ping)
			if len(state.PingHistory) > 16 {
				state.PingHistory = state.PingHistory[len(state.PingHistory)-16:]
			}
		}
	}
	saveStateLocked()
	mu.Unlock()
	return results
}

func pickBestProfileLocked() *ServerProfile {
	var best *ServerProfile
	bestPing := 999999
	for i := range state.Profiles {
		p := &state.Profiles[i]
		if p.IsInfoNode {
			continue
		}
		if best == nil {
			best = p
		}
		if ms, ok := state.ProfilePings[p.ID]; ok && ms > 0 && ms < bestPing {
			bestPing = ms
			best = p
		}
	}
	return best
}

func buildSingboxConfig(p ServerProfile, r RoutingOptions, listenPort int) map[string]interface{} {
	outbound := map[string]interface{}{
		"tag":         "proxy",
		"type":        p.Protocol,
		"server":      p.ServerAddress,
		"server_port": p.ServerPort,
	}

	strExtra := func(k string) string {
		if v, ok := p.Extra[k]; ok && v != nil {
			s := fmt.Sprintf("%v", v)
			if s != "<nil>" {
				return strings.TrimSpace(s)
			}
		}
		return ""
	}

	switch p.Protocol {
	case "vless":
		outbound["uuid"] = strExtra("uuid")
		if flow := strExtra("flow"); flow != "" {
			outbound["flow"] = flow
		}
	case "vmess":
		outbound["uuid"] = strExtra("uuid")
		outbound["security"] = "auto"
	case "trojan":
		outbound["password"] = strExtra("password")
	case "shadowsocks":
		method := strExtra("method")
		if method == "" {
			method = "2022-blake3-aes-128-gcm"
		}
		outbound["method"] = method
		outbound["password"] = strExtra("password")
	case "hysteria2":
		outbound["password"] = strExtra("auth")
	}

	sec := strings.ToLower(strExtra("security"))
	sni := strExtra("sni")
	if sni == "" {
		sni = strExtra("host")
	}
	if sni == "" {
		sni = p.ServerAddress
	}

	if sec == "tls" || sec == "reality" || p.Protocol == "trojan" || p.Protocol == "hysteria2" {
		tlsMap := map[string]interface{}{
			"enabled":     true,
			"server_name": sni,
			"insecure":    strExtra("allowInsecure") == "1" || strExtra("insecure") == "1",
		}
		if fp := strExtra("fp"); fp != "" {
			tlsMap["utls"] = map[string]interface{}{
				"enabled":     true,
				"fingerprint": fp,
			}
		}
		if sec == "reality" {
			tlsMap["reality"] = map[string]interface{}{
				"enabled":    true,
				"public_key": strExtra("pbk"),
				"short_id":   strExtra("sid"),
			}
		}
		outbound["tls"] = tlsMap
	}

	netType := strings.ToLower(strExtra("type"))
	switch netType {
	case "ws":
		rawPath := strExtra("path")
		if rawPath == "" {
			rawPath = "/"
		}
		earlyData := 0
		if qIdx := strings.Index(rawPath, "?"); qIdx >= 0 {
			qPart := rawPath[qIdx+1:]
			rawPath = rawPath[:qIdx]
			if rawPath == "" {
				rawPath = "/"
			}
			if parsedQ, err := url.ParseQuery(qPart); err == nil {
				if edStr := parsedQ.Get("ed"); edStr != "" {
					earlyData, _ = strconv.Atoi(edStr)
				}
			}
		}
		wsHost := strExtra("host")
		if wsHost == "" {
			wsHost = sni
		}
		tr := map[string]interface{}{
			"type": "ws",
			"path": rawPath,
			"headers": map[string]interface{}{
				"Host": wsHost,
			},
		}
		if earlyData > 0 {
			tr["max_early_data"] = earlyData
			tr["early_data_header_name"] = "Sec-WebSocket-Protocol"
		}
		outbound["transport"] = tr
	case "grpc":
		outbound["transport"] = map[string]interface{}{
			"type":         "grpc",
			"service_name": strExtra("serviceName"),
		}
	case "http", "tcp":
		if strings.ToLower(strExtra("headerType")) == "http" {
			rawPath := strExtra("path")
			if rawPath == "" {
				rawPath = "/"
			}
			outbound["transport"] = map[string]interface{}{
				"type": "http",
				"path": rawPath,
			}
		}
	}

	if r.EnableMux && (p.Protocol == "vless" || p.Protocol == "vmess" || p.Protocol == "trojan") {
		outbound["multiplex"] = map[string]interface{}{
			"enabled":     true,
			"protocol":    "h2mux",
			"max_streams": 8,
		}
	}

	inbounds := []map[string]interface{}{
		{
			"type":        "mixed",
			"tag":         "mixed-in",
			"listen":      "127.0.0.1",
			"listen_port": listenPort,
			"sniff":       r.EnableTrafficSniffing,
		},
	}
	if r.UseTunMode {
		inbounds = append(inbounds, map[string]interface{}{
			"type":           "tun",
			"tag":            "tun-in",
			"interface_name": "SpeedllTun",
			"inet4_address":  "172.19.0.1/30",
			"inet6_address":  "fdfe:dcba:9876::1/126",
			"mtu":            1400,
			"auto_route":     true,
			"strict_route":   true,
			"stack":          "system",
			"sniff":          r.EnableTrafficSniffing,
		})
	}

	rules := []map[string]interface{}{
		{"protocol": "dns", "outbound": "dns-out"},
	}
	if r.BypassLan {
		rules = append(rules, map[string]interface{}{
			"ip_is_private": true,
			"outbound":      "direct",
		})
	}
	if r.BypassIranDomains {
		rules = append(rules, map[string]interface{}{
			"domain_suffix": []string{".ir"},
			"outbound":      "direct",
		})
	}
	if len(r.CustomDirectDomains) > 0 {
		rules = append(rules, map[string]interface{}{
			"domain_suffix": r.CustomDirectDomains,
			"outbound":      "direct",
		})
	}
	if len(r.CustomDirectCidrs) > 0 {
		rules = append(rules, map[string]interface{}{
			"ip_cidr":  r.CustomDirectCidrs,
			"outbound": "direct",
		})
	}

	return map[string]interface{}{
		"log": map[string]interface{}{
			"level": "warn",
		},
		"dns": map[string]interface{}{
			"servers": []map[string]interface{}{
				{
					"tag":     "dns-remote",
					"address": "tcp://" + r.RemoteDnsServer,
					"detour":  "proxy",
				},
				{
					"tag":     "dns-direct",
					"address": r.DirectDnsServer,
					"detour":  "direct",
				},
			},
			"rules": []map[string]interface{}{
				{"outbound": "any", "server": "dns-direct"},
				{"domain_suffix": []string{".ir"}, "server": "dns-direct"},
			},
			"final":    "dns-remote",
			"strategy": "ipv4_only",
		},
		"inbounds": inbounds,
		"outbounds": []map[string]interface{}{
			outbound,
			{"type": "direct", "tag": "direct"},
			{"type": "dns", "tag": "dns-out"},
			{"type": "block", "tag": "block"},
		},
		"route": map[string]interface{}{
			"auto_detect_interface": true,
			"rules":                 rules,
			"final":                 "proxy",
		},
	}
}

func ensureSingboxBinary() (string, error) {
	exePath, _ := os.Executable()
	exeDir := filepath.Dir(exePath)
	binName := "sing-box.exe"
	if runtime.GOOS != "windows" {
		binName = "sing-box"
	}

	candidates := []string{
		filepath.Join(exeDir, "bin", binName),
		filepath.Join(exeDir, binName),
		filepath.Join(filepath.Dir(storagePath), "bin", binName),
	}
	for _, c := range candidates {
		if info, err := os.Stat(c); err == nil && !info.IsDir() {
			return c, nil
		}
	}

	if runtime.GOOS != "windows" {
		return "", fmt.Errorf("فایل هسته %s یافت نشد؛ دانلود خودکار فقط برای ویندوز فعال است", binName)
	}

	targetDir := filepath.Join(filepath.Dir(storagePath), "bin")
	if err := os.MkdirAll(targetDir, 0755); err != nil {
		return "", err
	}
	targetPath := filepath.Join(targetDir, binName)

	const (
		zipURL       = "https://github.com/SagerNet/sing-box/releases/download/v1.14.4/sing-box-1.14.4-windows-amd64.zip"
		zipSHA256Hex = "99185d75d314a07dbba4a130c8ad986cbeb629a07927975636b341ca61f991df"
	)

	client := &http.Client{Timeout: 120 * time.Second}
	resp, err := client.Get(zipURL)
	if err != nil {
		return "", fmt.Errorf("دانلود خودکار هسته ناموفق بود: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("دانلود خودکار هسته ناموفق بود (HTTP %d)", resp.StatusCode)
	}

	body, err := io.ReadAll(io.LimitReader(resp.Body, 128*1024*1024))
	if err != nil {
		return "", err
	}
	digest := sha256.Sum256(body)
	if hex.EncodeToString(digest[:]) != zipSHA256Hex {
		return "", fmt.Errorf("checksum هسته sing-box مطابق نسخه تأییدشده نیست")
	}

	zr, err := zip.NewReader(bytes.NewReader(body), int64(len(body)))
	if err != nil {
		return "", err
	}

	foundExecutable := false
	for _, f := range zr.File {
		name := filepath.Base(f.Name)
		if name == "" || name == "." || name == ".." {
			continue
		}
		mode := os.FileMode(0644)
		if strings.EqualFold(name, binName) {
			mode = 0755
			foundExecutable = true
		}
		rc, err := f.Open()
		if err != nil {
			return "", err
		}
		out, err := os.OpenFile(filepath.Join(targetDir, name), os.O_CREATE|os.O_WRONLY|os.O_TRUNC, mode)
		if err != nil {
			rc.Close()
			return "", err
		}
		_, copyErr := io.Copy(out, rc)
		closeErr := out.Close()
		rc.Close()
		if copyErr != nil {
			return "", copyErr
		}
		if closeErr != nil {
			return "", closeErr
		}
	}
	if !foundExecutable {
		return "", fmt.Errorf("sing-box.exe در بسته دانلودشده یافت نشد")
	}
	return targetPath, nil
}

func queryRegValue(name string) (string, bool) {
	const regKey = `HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings`
	cmd := exec.Command("reg", "query", regKey, "/v", name)
	configureHiddenProcess(cmd)
	out, err := cmd.Output()
	if err != nil {
		return "", false
	}
	for _, line := range strings.Split(string(out), "\n") {
		fields := strings.Fields(line)
		if len(fields) >= 3 && strings.EqualFold(fields[0], name) {
			return strings.Join(fields[2:], " "), true
		}
	}
	return "", false
}

func setRegValue(name, valueType, value string) {
	const regKey = `HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings`
	cmd := exec.Command("reg", "add", regKey, "/v", name, "/t", valueType, "/d", value, "/f")
	configureHiddenProcess(cmd)
	_ = cmd.Run()
}

func deleteRegValue(name string) {
	const regKey = `HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings`
	cmd := exec.Command("reg", "delete", regKey, "/v", name, "/f")
	configureHiddenProcess(cmd)
	_ = cmd.Run()
}

func restoreRegValue(name, valueType, value string, present bool) {
	if present {
		setRegValue(name, valueType, value)
		return
	}
	deleteRegValue(name)
}

func setWindowsSystemProxy(enable bool, port int) {
	if runtime.GOOS != "windows" {
		return
	}
	proxyMu.Lock()
	defer proxyMu.Unlock()
	if enable {
		if !proxyManaged {
			enableValue, enablePresent := queryRegValue("ProxyEnable")
			serverValue, serverPresent := queryRegValue("ProxyServer")
			autoConfigValue, autoConfigPresent := queryRegValue("AutoConfigURL")
			proxySaved = &proxySnapshot{
				enable:            enableValue,
				enablePresent:     enablePresent,
				server:            serverValue,
				serverPresent:     serverPresent,
				autoConfig:        autoConfigValue,
				autoConfigPresent: autoConfigPresent,
			}
			proxyManaged = true
		}
		deleteRegValue("AutoConfigURL")
		setRegValue("ProxyServer", "REG_SZ", fmt.Sprintf("127.0.0.1:%d", port))
		setRegValue("ProxyEnable", "REG_DWORD", "1")
		return
	}
	if !proxyManaged {
		return
	}
	proxyManaged = false
	saved := proxySaved
	proxySaved = nil
	if saved == nil {
		setRegValue("ProxyEnable", "REG_DWORD", "0")
		return
	}
	restoreRegValue("ProxyEnable", "REG_DWORD", saved.enable, saved.enablePresent)
	restoreRegValue("ProxyServer", "REG_SZ", saved.server, saved.serverPresent)
	restoreRegValue("AutoConfigURL", "REG_SZ", saved.autoConfig, saved.autoConfigPresent)
}

func findFreeLoopbackPort() (int, error) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return 0, err
	}
	defer listener.Close()
	return listener.Addr().(*net.TCPAddr).Port, nil
}

func stopTunnelLocked() {
	tunnelGeneration++
	setWindowsSystemProxy(false, 0)
	if singboxCmd != nil && singboxCmd.Process != nil {
		_ = singboxCmd.Process.Kill()
		singboxCmd = nil
	}
	if activeCfg != "" {
		_ = os.Remove(activeCfg)
		activeCfg = ""
	}
	state.Phase = "disconnected"
	state.ConnectedSinceUnix = 0
}

func startTunnelWithActiveProfile() error {
	mu.Lock()
	if state.IsSmartMode {
		if best := pickBestProfileLocked(); best != nil {
			state.ActiveProfileID = best.ID
		}
	}
	var chosen *ServerProfile
	for i := range state.Profiles {
		if state.Profiles[i].ID == state.ActiveProfileID && !state.Profiles[i].IsInfoNode {
			chosen = &state.Profiles[i]
			break
		}
	}
	if chosen == nil {
		chosen = pickBestProfileLocked()
		if chosen != nil {
			state.ActiveProfileID = chosen.ID
		}
	}
	if chosen == nil {
		state.Phase = "failed"
		state.ErrorMessage = "لطفاً ابتدا یک اشتراک یا سرور معتبر اضافه کنید."
		mu.Unlock()
		return errors.New(state.ErrorMessage)
	}
	prof := *chosen
	routing := state.RoutingOptions
	state.Phase = "connecting"
	state.ErrorMessage = ""
	stopTunnelLocked()
	state.Phase = "connecting"
	mu.Unlock()

	listenPort, err := findFreeLoopbackPort()
	if err != nil {
		mu.Lock()
		state.Phase = "failed"
		state.ErrorMessage = "پورت آزاد محلی برای هسته اتصال یافت نشد (ERR-CORE-PORT)."
		mu.Unlock()
		return err
	}
	mu.Lock()
	state.MixedPort = listenPort
	mu.Unlock()

	binPath, err := ensureSingboxBinary()
	if err != nil {
		mu.Lock()
		state.Phase = "failed"
		state.ErrorMessage = err.Error()
		mu.Unlock()
		return err
	}

	cfgMap := buildSingboxConfig(prof, routing, listenPort)
	cfgBytes, _ := json.MarshalIndent(cfgMap, "", "  ")
	cfgFile := filepath.Join(os.TempDir(), fmt.Sprintf("speedll_win_%d.json", time.Now().UnixNano()))
	if err := os.WriteFile(cfgFile, cfgBytes, 0600); err != nil {
		mu.Lock()
		state.Phase = "failed"
		state.ErrorMessage = "خطا در ساخت فایل کانفیگ موقت"
		mu.Unlock()
		return err
	}

	cmd := exec.Command(binPath, "run", "-c", cfgFile)
	cmd.Dir = filepath.Dir(binPath)
	configureHiddenProcess(cmd)
	var stderrBuf bytes.Buffer
	cmd.Stderr = &stderrBuf

	if err := cmd.Start(); err != nil {
		_ = os.Remove(cfgFile)
		mu.Lock()
		state.Phase = "failed"
		state.ErrorMessage = "خطا در اجرای هسته sing-box: " + err.Error()
		mu.Unlock()
		return err
	}

	exitCh := make(chan error, 1)
	go func() {
		exitCh <- cmd.Wait()
	}()

	ready := false
	exited := false
	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		select {
		case <-exitCh:
			exited = true
		default:
		}
		if exited {
			break
		}
		conn, dialErr := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", listenPort), 200*time.Millisecond)
		if dialErr == nil {
			_ = conn.Close()
			ready = true
			break
		}
		time.Sleep(180 * time.Millisecond)
	}

	if !ready {
		_ = cmd.Process.Kill()
		if !exited {
			<-exitCh
		}
		_ = os.Remove(cfgFile)
		mu.Lock()
		state.Phase = "failed"
		if exited {
			state.ErrorMessage = "هسته sing-box پیش از آماده‌شدن متوقف شد (ERR-CORE-CRASH)."
		} else {
			state.ErrorMessage = "هسته sing-box پورت محلی را باز نکرد (ERR-CORE-PORT-TIMEOUT)."
		}
		mu.Unlock()
		return errors.New(state.ErrorMessage)
	}

	if runtime.GOOS == "windows" && !routing.UseTunMode {
		setWindowsSystemProxy(true, listenPort)
	}

	mu.Lock()
	singboxCmd = cmd
	activeCfg = cfgFile
	generation := tunnelGeneration
	state.Phase = "connected"
	state.ConnectedSinceUnix = time.Now().Unix()
	state.ErrorMessage = ""
	mu.Unlock()

	go func() {
		<-exitCh
		mu.Lock()
		defer mu.Unlock()
		if generation != tunnelGeneration || singboxCmd != cmd {
			return
		}
		singboxCmd = nil
		setWindowsSystemProxy(false, 0)
		if activeCfg != "" {
			_ = os.Remove(activeCfg)
			activeCfg = ""
		}
		if state.Phase == "connected" || state.Phase == "connecting" {
			state.Phase = "failed"
			state.ConnectedSinceUnix = 0
			state.ErrorMessage = "هسته اتصال به‌طور ناگهانی متوقف شد (ERR-CORE-CRASH)."
		}
	}()

	go func() {
		ms := measureSinglePing(prof)
		mu.Lock()
		state.LivePingMs = ms
		state.ProfilePings[prof.ID] = ms
		mu.Unlock()
	}()

	return nil
}

func isBlockedIP(ip net.IP) bool {
	if ip == nil {
		return true
	}
	if ip.IsLoopback() || ip.IsPrivate() || ip.IsUnspecified() ||
		ip.IsLinkLocalUnicast() || ip.IsLinkLocalMulticast() || ip.IsMulticast() {
		return true
	}
	if ip4 := ip.To4(); ip4 != nil && ip4[0] == 100 && ip4[1] >= 64 && ip4[1] <= 127 {
		return true
	}
	return false
}

func safeSubscriptionDialContext(ctx context.Context, network, address string) (net.Conn, error) {
	host, port, err := net.SplitHostPort(address)
	if err != nil {
		return nil, err
	}
	addresses, err := net.DefaultResolver.LookupIPAddr(ctx, host)
	if err != nil {
		return nil, err
	}
	var lastErr error
	for _, candidate := range addresses {
		if isBlockedIP(candidate.IP) {
			return nil, errors.New("آدرس مقصد اشتراک مجاز نیست")
		}
		dialer := net.Dialer{Timeout: 10 * time.Second}
		conn, dialErr := dialer.DialContext(ctx, network, net.JoinHostPort(candidate.IP.String(), port))
		if dialErr == nil {
			return conn, nil
		}
		lastErr = dialErr
	}
	if lastErr == nil {
		lastErr = errors.New("آدرس اشتراک قابل دسترسی نیست")
	}
	return nil, lastErr
}

func newSubscriptionHTTPClient() *http.Client {
	transport := &http.Transport{
		DialContext:           safeSubscriptionDialContext,
		TLSHandshakeTimeout:   10 * time.Second,
		ResponseHeaderTimeout: 15 * time.Second,
	}
	return &http.Client{
		Timeout:   20 * time.Second,
		Transport: transport,
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			if len(via) >= 3 {
				return errors.New("تعداد ریدایرکت‌های اشتراک بیش از حد مجاز است")
			}
			if req.URL.Scheme != "http" && req.URL.Scheme != "https" {
				return errors.New("طرح آدرس اشتراک مجاز نیست")
			}
			return nil
		},
	}
}

func openDesktopAppWindow(urlStr string) {
	if runtime.GOOS != "windows" {
		return
	}
	userDataDir := filepath.Join(filepath.Dir(storagePath), "WindowProfile")
	_ = os.MkdirAll(userDataDir, 0755)

	candidates := []string{
		`C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe`,
		`C:\Program Files\Microsoft\Edge\Application\msedge.exe`,
		`C:\Program Files\Google\Chrome\Application\chrome.exe`,
	}
	for _, browser := range candidates {
		if _, err := os.Stat(browser); err == nil {
			cmd := exec.Command(
				browser,
				"--app="+urlStr,
				"--window-size=480,830",
				"--user-data-dir="+userDataDir,
				"--no-first-run",
				"--disable-extensions",
			)
			configureHiddenProcess(cmd)
			if cmd.Start() == nil {
				go func() {
					_ = cmd.Wait()
					mu.Lock()
					stopTunnelLocked()
					mu.Unlock()
					os.Exit(0)
				}()
				return
			}
		}
	}
	_ = exec.Command("rundll32", "url.dll,FileProtocolHandler", urlStr).Start()
}

func main() {
	initDefaultState()

	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		_, _ = w.Write(embeddedUI)
	})

	mux.HandleFunc("/api/state", func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		defer mu.Unlock()
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		_ = json.NewEncoder(w).Encode(state)
	})

	mux.HandleFunc("/api/toggle", func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		curPhase := state.Phase
		mu.Unlock()

		if curPhase == "connected" || curPhase == "connecting" {
			mu.Lock()
			stopTunnelLocked()
			mu.Unlock()
		} else {
			_ = startTunnelWithActiveProfile()
		}
		mu.Lock()
		defer mu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(state)
	})

	mux.HandleFunc("/api/select", func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			ID        string `json:"id"`
			SmartMode *bool  `json:"smartMode"`
		}
		_ = json.NewDecoder(r.Body).Decode(&body)

		mu.Lock()
		wasConnected := state.Phase == "connected"
		if body.SmartMode != nil {
			state.IsSmartMode = *body.SmartMode
			if state.IsSmartMode {
				if best := pickBestProfileLocked(); best != nil {
					state.ActiveProfileID = best.ID
				}
			}
		}
		if body.ID != "" {
			state.ActiveProfileID = body.ID
			state.IsSmartMode = false
		}
		if p, ok := state.ProfilePings[state.ActiveProfileID]; ok {
			state.LivePingMs = p
		}
		saveStateLocked()
		mu.Unlock()

		if wasConnected {
			_ = startTunnelWithActiveProfile()
		} else {
			go func() {
				mu.Lock()
				var active *ServerProfile
				for i := range state.Profiles {
					if state.Profiles[i].ID == state.ActiveProfileID {
						p := state.Profiles[i]
						active = &p
						break
					}
				}
				mu.Unlock()
				if active != nil {
					ms := measureSinglePing(*active)
					mu.Lock()
					state.LivePingMs = ms
					state.ProfilePings[active.ID] = ms
					mu.Unlock()
				}
			}()
		}

		mu.Lock()
		defer mu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(state)
	})

	mux.HandleFunc("/api/ping-all", func(w http.ResponseWriter, r *http.Request) {
		wasConnected := false
		prevActive := ""
		mu.Lock()
		wasConnected = state.Phase == "connected"
		prevActive = state.ActiveProfileID
		mu.Unlock()

		pingAllProfilesParallel()

		mu.Lock()
		newActive := state.ActiveProfileID
		isSmart := state.IsSmartMode
		mu.Unlock()

		if wasConnected && isSmart && newActive != "" && newActive != prevActive {
			_ = startTunnelWithActiveProfile()
		}

		mu.Lock()
		defer mu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(state)
	})

	mux.HandleFunc("/api/import", func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			Input string `json:"input"`
		}
		_ = json.NewDecoder(r.Body).Decode(&body)
		text := strings.TrimSpace(body.Input)

		var imported []ServerProfile
		lower := strings.ToLower(text)
		if !strings.Contains(text, "\n") && (strings.HasPrefix(lower, "https://") || strings.HasPrefix(lower, "http://")) {
			client := newSubscriptionHTTPClient()
			req, err := http.NewRequest("GET", text, nil)
			if err == nil {
				req.Header.Set("User-Agent", "v2rayNG/1.8.23 SpeedllConnect/1.1 (sing-box)")
				resp, err := client.Do(req)
				if err == nil {
					rawBytes, _ := io.ReadAll(io.LimitReader(resp.Body, 2*1024*1024))
					resp.Body.Close()
					if resp.StatusCode == 200 {
						imported = parseSubscriptionPayload(string(rawBytes))
					}
					if len(imported) > 0 {
						u, _ := url.Parse(text)
						hostName := "اشتراک"
						if u != nil && u.Host != "" {
							hostName = u.Host
						}
						mu.Lock()
						subID := "sub_" + stableHash(text)
						found := false
						for i := range state.Subscriptions {
							if state.Subscriptions[i].ID == subID || state.Subscriptions[i].URL == text {
								state.Subscriptions[i].LastStatusMessage = fmt.Sprintf("دریافت موفق (%d سرور)", len(imported))
								found = true
								break
							}
						}
						if !found {
							state.Subscriptions = append(state.Subscriptions, SubscriptionSource{
								ID:                subID,
								Name:              hostName,
								URL:               text,
								LastStatusMessage: fmt.Sprintf("دریافت موفق (%d سرور)", len(imported)),
							})
						}
						mu.Unlock()
					}
				}
			}
		} else {
			imported = parseSubscriptionPayload(text)
		}

		if len(imported) == 0 {
			w.WriteHeader(http.StatusBadRequest)
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]string{
				"error": "خطا در دریافت یا پارس کردن لینک اشتراک / کانفیگ.",
			})
			return
		}

		mu.Lock()
		existingByID := make(map[string]int)
		for i, p := range state.Profiles {
			existingByID[p.ID] = i
		}
		for _, p := range imported {
			if idx, ok := existingByID[p.ID]; ok {
				state.Profiles[idx] = p
			} else {
				state.Profiles = append(state.Profiles, p)
			}
		}
		if state.ActiveProfileID == "" {
			if best := pickBestProfileLocked(); best != nil {
				state.ActiveProfileID = best.ID
			}
		}
		saveStateLocked()
		mu.Unlock()

		go pingAllProfilesParallel()

		mu.Lock()
		defer mu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(state)
	})

	mux.HandleFunc("/api/refresh-subs", func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		subs := append([]SubscriptionSource(nil), state.Subscriptions...)
		mu.Unlock()

		client := newSubscriptionHTTPClient()
		for _, s := range subs {
			req, err := http.NewRequest("GET", s.URL, nil)
			if err != nil {
				continue
			}
			req.Header.Set("User-Agent", "v2rayNG/1.8.23 SpeedllConnect/1.1 (sing-box)")
			resp, err := client.Do(req)
			if err != nil {
				continue
			}
			rawBytes, _ := io.ReadAll(io.LimitReader(resp.Body, 2*1024*1024))
			resp.Body.Close()
			if resp.StatusCode != 200 {
				continue
			}
			imported := parseSubscriptionPayload(string(rawBytes))
			if len(imported) == 0 {
				continue
			}
			mu.Lock()
			existingByID := make(map[string]int)
			for i, p := range state.Profiles {
				existingByID[p.ID] = i
			}
			for _, p := range imported {
				if idx, ok := existingByID[p.ID]; ok {
					state.Profiles[idx] = p
				} else {
					state.Profiles = append(state.Profiles, p)
				}
			}
			saveStateLocked()
			mu.Unlock()
		}
		go pingAllProfilesParallel()

		mu.Lock()
		defer mu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(state)
	})

	mux.HandleFunc("/api/settings", func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			Language       string          `json:"language"`
			ThemePreset    string          `json:"themePreset"`
			RoutingOptions *RoutingOptions `json:"routingOptions"`
			ClearProfiles  bool            `json:"clearProfiles"`
			DeleteProfile  string          `json:"deleteProfile"`
		}
		_ = json.NewDecoder(r.Body).Decode(&body)

		mu.Lock()
		if body.Language != "" {
			state.Language = body.Language
		}
		if body.ThemePreset != "" {
			state.ThemePreset = body.ThemePreset
		}
		if body.RoutingOptions != nil {
			state.RoutingOptions = *body.RoutingOptions
		}
		if body.ClearProfiles {
			state.Profiles = []ServerProfile{}
			state.ActiveProfileID = ""
			state.ProfilePings = make(map[string]int)
		}
		if body.DeleteProfile != "" {
			filtered := make([]ServerProfile, 0, len(state.Profiles))
			for _, p := range state.Profiles {
				if p.ID != body.DeleteProfile {
					filtered = append(filtered, p)
				}
			}
			state.Profiles = filtered
			if state.ActiveProfileID == body.DeleteProfile {
				if best := pickBestProfileLocked(); best != nil {
					state.ActiveProfileID = best.ID
				} else {
					state.ActiveProfileID = ""
				}
			}
		}
		saveStateLocked()
		defer mu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(state)
	})

	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return
	}
	port := listener.Addr().(*net.TCPAddr).Port
	localURL := fmt.Sprintf("http://127.0.0.1:%d", port)

	server := &http.Server{
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}
	go openDesktopAppWindow(localURL)
	_ = server.Serve(listener)
}
