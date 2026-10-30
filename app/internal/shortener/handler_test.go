package shortener

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

func newTestServer(t *testing.T, fault Fault) (*Server, *httptest.Server, *prometheus.Registry) {
	t.Helper()
	reg := prometheus.NewRegistry()
	s := &Server{Store: NewMemory(), Metrics: NewMetrics(reg), Log: slog.New(slog.NewTextHandler(io.Discard, nil)), BaseURL: "http://sho.test", Fault: fault}
	ts := httptest.NewServer(s.Routes())
	t.Cleanup(ts.Close)
	return s, ts, reg
}

func create(t *testing.T, ts *httptest.Server, body string) (*http.Response, map[string]any) {
	t.Helper()
	res, err := http.Post(ts.URL+"/api/links", "application/json", strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	var out map[string]any
	_ = json.NewDecoder(res.Body).Decode(&out)
	return res, out
}

var noFollow = &http.Client{CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}

func TestCreateRedirectAndCount(t *testing.T) {
	_, ts, _ := newTestServer(t, Fault{})
	res, out := create(t, ts, `{"url":"https://example.com/a/long/path"}`)
	if res.StatusCode != http.StatusCreated {
		t.Fatalf("create: got %d", res.StatusCode)
	}
	code := out["code"].(string)
	if !ValidCode(code) || out["short_url"] != "http://sho.test/"+code {
		t.Fatalf("unexpected body: %v", out)
	}

	for i := 0; i < 2; i++ {
		r, err := noFollow.Get(ts.URL + "/" + code)
		if err != nil {
			t.Fatal(err)
		}
		r.Body.Close()
		if r.StatusCode != http.StatusFound || r.Header.Get("Location") != "https://example.com/a/long/path" {
			t.Fatalf("redirect: got %d to %q", r.StatusCode, r.Header.Get("Location"))
		}
	}

	r, err := http.Get(ts.URL + "/api/links/" + code)
	if err != nil {
		t.Fatal(err)
	}
	defer r.Body.Close()
	var link Link
	_ = json.NewDecoder(r.Body).Decode(&link)
	if link.Hits != 2 {
		t.Fatalf("hits: got %d, want 2", link.Hits)
	}
}

func TestRejectsBadURLs(t *testing.T) {
	_, ts, _ := newTestServer(t, Fault{})
	for _, body := range []string{`{"url":"ftp://x.org"}`, `{"url":"not a url"}`, `{"url":"https://"}`, `{`, `{"url":"https://x.org/` + strings.Repeat("a", 2100) + `"}`} {
		if res, _ := create(t, ts, body); res.StatusCode != http.StatusBadRequest {
			t.Errorf("%.40s…: got %d, want 400", body, res.StatusCode)
		}
	}
}

func TestUnknownAndJunkCodes(t *testing.T) {
	_, ts, _ := newTestServer(t, Fault{})
	for _, path := range []string{"/AAAAAAA", "/short", "/api/links/nope"} {
		r, err := noFollow.Get(ts.URL + path)
		if err != nil {
			t.Fatal(err)
		}
		r.Body.Close()
		if r.StatusCode != http.StatusNotFound {
			t.Errorf("%s: got %d, want 404", path, r.StatusCode)
		}
	}
}

func TestInjectedFaultAndMetrics(t *testing.T) {
	s, ts, reg := newTestServer(t, Fault{})
	_, out := create(t, ts, `{"url":"https://example.com"}`)
	s.Fault = Fault{ErrorRate: 1}
	r, err := noFollow.Get(ts.URL + "/" + out["code"].(string))
	if err != nil {
		t.Fatal(err)
	}
	r.Body.Close()
	if r.StatusCode != http.StatusInternalServerError {
		t.Fatalf("with ErrorRate 1: got %d, want 500", r.StatusCode)
	}

	rec := httptest.NewRecorder()
	promhttp.HandlerFor(reg, promhttp.HandlerOpts{}).ServeHTTP(rec, httptest.NewRequest("GET", "/metrics", nil))
	body := rec.Body.String()
	for _, want := range []string{
		`shortener_http_requests_total{code="201",method="POST",route="create"} 1`,
		`shortener_http_requests_total{code="500",method="GET",route="redirect"} 1`,
		`shortener_http_request_duration_seconds_bucket{method="GET",route="redirect",le="0.3"}`,
		`shortener_links_created_total 1`,
	} {
		if !strings.Contains(body, want) {
			t.Errorf("metrics missing %q", want)
		}
	}
}

func TestReadinessFollowsShutdown(t *testing.T) {
	s, _, reg := newTestServer(t, Fault{})
	admin := httptest.NewServer(s.AdminRoutes(promhttp.HandlerFor(reg, promhttp.HandlerOpts{})))
	defer admin.Close()
	status := func() int {
		r, err := http.Get(admin.URL + "/readyz")
		if err != nil {
			t.Fatal(err)
		}
		r.Body.Close()
		return r.StatusCode
	}
	if status() != http.StatusServiceUnavailable {
		t.Fatal("ready before start")
	}
	s.SetReady(true)
	if status() != http.StatusOK {
		t.Fatal("not ready after start")
	}
	s.SetReady(false)
	if status() != http.StatusServiceUnavailable {
		t.Fatal("still ready while draining")
	}
}

func TestCodes(t *testing.T) {
	seen := map[string]bool{}
	for i := 0; i < 2000; i++ {
		c, err := NewCode()
		if err != nil || !ValidCode(c) || seen[c] {
			t.Fatalf("bad or repeated code %q (err %v)", c, err)
		}
		seen[c] = true
	}
	for _, bad := range []string{"", "abc", "abcdefgh", "abc-def", "abcdéfg"} {
		if ValidCode(bad) {
			t.Errorf("ValidCode(%q) = true", bad)
		}
	}
}
